defmodule Foglet.SSH.CLIHandler do
  @moduledoc """
  Foglet-owned SSH channel handler (`:ssh_server_channel` behaviour).

  ## Responsibilities

  This module replaces the old pattern of wrapping `Raxol.SSH.CLIHandler`
  (which required impersonating `Raxol.SSH.Server` via `ConnectionCounter`).
  We now own the full channel lifecycle directly:

  1. **`ssh_channel_up`** — read peer info; try to correlate a previously-stashed
     pubkey (from `KeyCB.is_auth_key/3`) with a registered `Foglet.Accounts.SSHKey`
     row; start a `Foglet.Sessions.Session` with the matched user (or nil for
     guests); store the session_pid in channel state.

  2. **`pty`** — start the Raxol Lifecycle with full context (session_context,
     terminal_size). The context reaches `Foglet.TUI.App.init/1` through the
     `options:` field of the map Lifecycle passes to `init/1`.

  3. **`data`** — parse SSH channel bytes → Raxol events → dispatch to Lifecycle.

  4. **`window_change`** — dispatch resize event to Lifecycle; notify Session.

  5. **`eof` / `closed`** — stop Lifecycle; terminate Session; close channel.

  6. **EXIT trapping** — if Lifecycle exits unexpectedly, close the SSH channel
     so the client gets a clean disconnect rather than a hung terminal.

  ## Pubkey correlation

  `KeyCB.is_auth_key/3` stashes `{peer_ip, peer_port} => public_key_record`
  in `Foglet.SSH.PubkeyStash` (ETS). On `ssh_channel_up` we:

  1. Obtain the peer address via `:ssh.connection_info(connection_ref, [:peer])`.
  2. Pop the stashed pubkey (or `:miss` if the client used password-based flow,
     which is rejected at the daemon level — all connections use no_auth_needed).
  3. If a pubkey was offered, authenticate it through
     `Accounts.authenticate_by_public_key/1` to find the matching user and
     record last-used metadata.
  4. Build the session context accordingly.

  ## Connection limit

  Enforced here rather than via a separate GenServer. The module attribute
  `@max_connections` is the limit. A simple `:persistent_term` counter tracks
  active connections so we avoid a global GenServer bottleneck.
  """

  @behaviour :ssh_server_channel

  require Logger

  alias Foglet.Accounts.Auth
  alias Foglet.Sessions
  alias Foglet.Sessions.Preferences
  alias Raxol.SSH.IOAdapter

  @max_connections 500

  defstruct [
    :channel_id,
    :connection_ref,
    :peer,
    :session_pid,
    :lifecycle_pid,
    :dispatcher_pid,
    :width,
    :height,
    over_limit: false,
    cleanup_done?: false,
    counter_counted?: false
  ]

  # --- :ssh_server_channel callbacks ---

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_msg({:ssh_channel_up, channel_id, connection_ref}, %__MODULE__{} = state) do
    peer = read_peer(connection_ref)
    do_channel_up(state, channel_id, connection_ref, peer)
  end

  # Lifecycle exited — close the channel so the client terminal disconnects.
  @impl true
  def handle_msg({:EXIT, pid, reason}, %{lifecycle_pid: pid} = state) do
    Logger.info(
      "[SSH.CLIHandler] Lifecycle #{inspect(pid)} exited (#{inspect(reason)}); closing channel"
    )

    # Delegate to the shared cleanup helper. cleanup/2 sends the alt-screen
    # leave first (so iTerm2 restores the primary buffer before teardown),
    # then stops session, optionally closes the channel, and decrements the
    # counter exactly once for accepted connections.
    new_state = cleanup(state, close_channel: true)
    {:stop, new_state.channel_id || 0, new_state}
  end

  @impl true
  def handle_msg(_msg, state), do: {:ok, state}

  @impl true
  def handle_ssh_msg(
        {:ssh_cm, conn, {:pty, ch, want_reply, {_term, width, height, _pxw, _pxh, _modes}}},
        state
      ) do
    context = build_context(state, width, height)

    # Take over the terminal immediately on PTY allocation, before Raxol
    # initialization or the first render can write to the primary buffer.
    send_alt_screen_enter(state)

    {:ok, lifecycle_pid} =
      Raxol.Core.Runtime.Lifecycle.start_link(Foglet.TUI.App,
        # Pid-only registration: Raxol derives a globally-unique name from the
        # app module unless `:name` is present, which collapses every SSH
        # session onto one Lifecycle and rejects concurrent connections with
        # `{:error, {:already_started, _}}`. CLIHandler tracks the pid in
        # state, so a registered name is unnecessary.
        name: nil,
        environment: :ssh,
        io_writer: make_crlf_writer(state.connection_ref, state.channel_id),
        width: width,
        height: height,
        context: context,
        # Keep Raxol's own alt-screen lifecycle enabled as a backup. The direct
        # CLIHandler takeover above runs earlier and also clears scrollback.
        alternate_screen: true
      )

    Process.link(lifecycle_pid)
    :ssh_connection.reply_request(conn, want_reply, :success, ch)

    # WR-05: resolve the dispatcher pid once here, immediately after Lifecycle
    # start, and stash it on state so per-keystroke / per-resize dispatches do
    # not block on a synchronous GenServer.call into the Lifecycle. The
    # dispatcher pid is stable for the Lifecycle's lifetime; if a future Raxol
    # version can rebuild it, refresh on the EXIT path or expose a notification.
    dispatcher_pid = resolve_dispatcher(lifecycle_pid)

    {:ok,
     %{
       state
       | lifecycle_pid: lifecycle_pid,
         dispatcher_pid: dispatcher_pid,
         width: width,
         height: height
     }}
  end

  @impl true
  def handle_ssh_msg({:ssh_cm, _conn, {:data, _ch, _type, data}}, state) do
    events = IOAdapter.parse_input(data)
    dispatch_events(state.dispatcher_pid, events)
    {:ok, state}
  end

  @impl true
  def handle_ssh_msg({:ssh_cm, _conn, {:window_change, _ch, width, height, _pxw, _pxh}}, state) do
    # Two dispatches, on purpose:
    #   1. :resize hits Raxol's dispatcher system-event path
    #      (vendor/raxol/.../dispatcher.ex:615) — resizes the rendering engine
    #      but never reaches App.update/2.
    #   2. :window is not a system event, so it flows through to App.update/2
    #      where normalize_message/1 turns it into {:window_change, w, h} and
    #      do_update/2 updates state.terminal_size. Without this second
    #      dispatch, SizeGate.too_small? stays stuck on the initial PTY size
    #      and the gate never triggers on resize.
    resize = Raxol.Core.Events.Event.new(:resize, %{width: width, height: height})
    window = Raxol.Core.Events.Event.new(:window, %{width: width, height: height})
    dispatch_events(state.dispatcher_pid, [resize, window])

    # IN-01: Session.set_terminal_size/2 is owned by the App's
    # do_update({:window_change, …}, …) handler, which already fires from the
    # :window event dispatched above. Casting here too would double-write the
    # same value and obscure ownership of the "session knows its size"
    # invariant.

    {:ok, %{state | width: width, height: height}}
  end

  @impl true
  def handle_ssh_msg({:ssh_cm, conn, {:shell, ch, want_reply}}, state) do
    :ssh_connection.reply_request(conn, want_reply, :success, ch)
    {:ok, state}
  end

  @impl true
  def handle_ssh_msg({:ssh_cm, _conn, {:eof, _ch}}, state) do
    # Client is done sending; send→client direction still open. Emit the
    # alt-screen LEAVE escape here so iTerm2 restores the primary buffer
    # before `{:closed}` arrives and the channel tears down. Without this,
    # the TUI's final frame lingers in the user's scrollback post-disconnect.
    send_alt_screen_leave(state)
    {:ok, state}
  end

  @impl true
  def handle_ssh_msg({:ssh_cm, _conn, {:closed, _ch}}, state) do
    # Belt-and-suspenders: if the client dropped without sending EOF
    # (e.g. window closed abruptly), the cleanup helper sends LEAVE anyway.
    # The channel may already be fully closed, in which case the send no-ops.
    new_state = cleanup(state, close_channel: false)
    {:stop, new_state.channel_id || 0, new_state}
  end

  @impl true
  def handle_ssh_msg(_msg, state), do: {:ok, state}

  @impl true
  def terminate(_reason, state) do
    _ = cleanup(state, close_channel: false)
    :ok
  end

  # Internal channel-up implementation. Exposed via channel_up_for_test/4 so
  # focused unit tests can drive the over-limit and rate-limit branches with a
  # specified peer rather than depending on a real SSH connection_info lookup.
  defp do_channel_up(%__MODULE__{} = state, channel_id, connection_ref, peer) do
    case check_connection_limit() do
      :over_limit ->
        _ =
          safe_ssh_send(
            connection_ref,
            channel_id,
            "Connection limit reached. Try again later.\r\n"
          )

        _ = safe_ssh_close(connection_ref, channel_id)

        # Over-limit reject is a fully-rejected state. check_connection_limit/0
        # already compensated its own increment, so no later cleanup is owed:
        # cleanup_done? is true and counter_counted? is false. Future cleanup
        # delegations are no-ops.
        new_state = %__MODULE__{
          over_limit: true,
          channel_id: channel_id,
          connection_ref: connection_ref,
          cleanup_done?: true,
          counter_counted?: false
        }

        {:ok, new_state}

      :ok ->
        if Foglet.SSH.RateLimiter.allow?(peer) do
          # check_connection_limit/0 already incremented the counter; the
          # accepted path now owns one decrement, tracked via counter_counted?.
          pubkey_user = resolve_pubkey_user(peer)
          session_pid = start_session(pubkey_user)

          Logger.info(
            "[SSH.CLIHandler] Channel up — peer=#{inspect(peer)} " <>
              "user=#{inspect(pubkey_user && pubkey_user.handle)} " <>
              "session_pid=#{inspect(session_pid)}"
          )

          new_state = %__MODULE__{
            state
            | channel_id: channel_id,
              connection_ref: connection_ref,
              peer: peer,
              session_pid: session_pid,
              counter_counted?: true,
              cleanup_done?: false
          }

          {:ok, new_state}
        else
          # check_connection_limit/0 incremented the counter before we got here;
          # undo it so rate-limited connections don't drift the count upward.
          # After this immediate compensation the counter is balanced, so the
          # rejected state owes no further decrement.
          _ = decrement_connection_count()

          _ =
            safe_ssh_send(
              connection_ref,
              channel_id,
              "Rate limit exceeded. Try again later.\r\n"
            )

          _ = safe_ssh_close(connection_ref, channel_id)

          new_state = %__MODULE__{
            over_limit: true,
            channel_id: channel_id,
            connection_ref: connection_ref,
            cleanup_done?: true,
            counter_counted?: false
          }

          {:ok, new_state}
        end
    end
  end

  @doc false
  # Test-only entry point for driving channel-up logic with an explicit peer.
  # Avoids needing a real SSH connection_ref to exercise the rate-limit and
  # over-limit branches of the handler.
  def channel_up_for_test(%__MODULE__{} = state, channel_id, connection_ref, peer) do
    do_channel_up(state, channel_id, connection_ref, peer)
  end

  # Clear the primary screen + scrollback, enter alt-screen, then clear the alt
  # buffer. `CSI 3 J` is what prevents scroll-up from revealing the caller's
  # pre-SSH shell history while the TUI is active.
  defp send_alt_screen_enter(%{connection_ref: ref, channel_id: ch})
       when not is_nil(ref) and not is_nil(ch) do
    _ = :ssh_connection.send(ref, ch, "\e[H\e[2J\e[3J\e[?1049h\e[H\e[2J\e[3J")
    :ok
  rescue
    _ -> :ok
  end

  defp send_alt_screen_enter(_state), do: :ok

  # Emit the alt-screen LEAVE escape (DECRST 1049) directly to the SSH channel
  # so the client's terminal restores the primary screen buffer on disconnect.
  # Safe to call when the channel is already closed — `:ssh_connection.send/3`
  # just returns an error we ignore.
  defp send_alt_screen_leave(%{connection_ref: ref, channel_id: ch})
       when not is_nil(ref) and not is_nil(ch) do
    _ = :ssh_connection.send(ref, ch, "\e[?1049l")
    :ok
  rescue
    _ -> :ok
  end

  defp send_alt_screen_leave(_state), do: :ok

  # --- Private helpers ---

  # Wrap IOAdapter.make_writer so bare LF rendered by Raxol.Terminal.Renderer
  # is translated to CRLF before going to the SSH channel. Without this, raw
  # SSH mode doesn't return the cursor to column 0 on \n, so every logical
  # row consumes ~2 visible rows (auto-wrap stair-step). Normalize existing
  # \r\n first so we don't turn them into \r\r\n.
  defp make_crlf_writer(connection_ref, channel_id) do
    inner = IOAdapter.make_writer(connection_ref, channel_id)

    fn data when is_binary(data) ->
      cooked =
        data
        |> :binary.replace("\r\n", "\n", [:global])
        |> :binary.replace("\n", "\r\n", [:global])

      inner.(cooked)
    end
  end

  defp read_peer(connection_ref) do
    case :ssh.connection_info(connection_ref, [:peer]) do
      [{:peer, {{ip, port}, _socket}}] -> {ip, port}
      [{:peer, {ip, port}}] when is_tuple(ip) and is_integer(port) -> {ip, port}
      _ -> :unknown
    end
  rescue
    _ -> :unknown
  end

  defp resolve_pubkey_user(peer) do
    case Foglet.SSH.PubkeyStash.pop(peer) do
      {:ok, public_key} ->
        case encode_public_key(public_key) do
          {:ok, openssh_text} ->
            case Auth.authenticate_by_public_key(openssh_text) do
              {:ok, user} -> user
              _ -> nil
            end

          _ ->
            nil
        end

      :miss ->
        nil
    end
  end

  defp encode_public_key(public_key) do
    text = :ssh_file.encode([{public_key, []}], :openssh_key)
    {:ok, to_string(text)}
  rescue
    _ -> :error
  catch
    _, _ -> :error
  end

  defp start_session(nil) do
    # Guest session — no user_id yet; will be promoted on TUI login.
    case Sessions.Supervisor.start_guest_session() do
      {:ok, pid} -> pid
      _ -> nil
    end
  end

  defp start_session(user) do
    preferences = Preferences.from_user(user)

    case Sessions.Supervisor.start_session(
           user_id: user.id,
           handle: user.handle,
           role: user.role,
           timezone: preferences.timezone,
           time_format: preferences.time_format,
           theme_id: preferences.theme_id,
           theme: preferences.theme
         ) do
      {:ok, pid} -> pid
      _ -> nil
    end
  end

  # Build the context map that reaches Foglet.TUI.App.init/1.
  # The Lifecycle passes `%{width:, height:, options: [all_lifecycle_opts]}` to
  # init/1. App.init/1 reads `context[:options][:context]` to get this map.
  defp build_context(state, width, height) do
    user =
      if is_pid(state.session_pid) do
        case Sessions.Session.get_state(state.session_pid) do
          %{user_id: nil} -> nil
          %{user_id: uid} -> Foglet.Accounts.get_user(uid)
        end
      else
        nil
      end

    preferences = Preferences.from_user(user)

    %{
      session_context: %Foglet.TUI.SessionContext{
        user: user,
        user_id: user && user.id,
        session_pid: state.session_pid,
        pubkey_authenticated: not is_nil(user),
        registration_mode: Foglet.Config.registration_mode(),
        max_post_length: Foglet.Config.max_post_length(),
        timezone: preferences.timezone,
        time_format: preferences.time_format,
        theme_id: preferences.theme_id,
        theme: preferences.theme,
        ssh_peer: state.peer
      },
      terminal_size: {width, height}
    }
  end

  defp dispatch_events(nil, _events), do: :ok

  defp dispatch_events(dispatcher_pid, events) when is_pid(dispatcher_pid) do
    Enum.each(events, &GenServer.cast(dispatcher_pid, {:dispatch, &1}))
  end

  # Resolve the Raxol dispatcher pid from the Lifecycle once at PTY start.
  # Returns nil if the Lifecycle is unreachable (already exited) so dispatching
  # before the EXIT message is observed becomes a no-op.
  defp resolve_dispatcher(nil), do: nil

  defp resolve_dispatcher(lifecycle_pid) do
    %{dispatcher_pid: pid} = GenServer.call(lifecycle_pid, :get_full_state)
    pid
  catch
    :exit, _ -> nil
  end

  defp stop_lifecycle(nil), do: :ok

  defp stop_lifecycle(pid) do
    if Process.alive?(pid), do: Raxol.Core.Runtime.Lifecycle.stop(pid)
  rescue
    _ -> :ok
  end

  defp stop_session(nil), do: :ok

  defp stop_session(pid) do
    if Process.alive?(pid) do
      DynamicSupervisor.terminate_child(Sessions.Supervisor, pid)
    end
  rescue
    _ -> :ok
  end

  defp maybe_close_channel(%{connection_ref: ref, channel_id: ch})
       when not is_nil(ref) and not is_nil(ch) do
    :ssh_connection.close(ref, ch)
  rescue
    _ -> :ok
  end

  defp maybe_close_channel(_state), do: :ok

  # Wrappers that tolerate a nil or test-only connection ref/channel without
  # raising. The rejection paths drive these directly with the values stashed
  # on state during channel-up.
  defp safe_ssh_send(nil, _ch, _data), do: :ok
  defp safe_ssh_send(_ref, nil, _data), do: :ok

  defp safe_ssh_send(ref, ch, data) do
    :ssh_connection.send(ref, ch, data)
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp safe_ssh_close(nil, _ch), do: :ok
  defp safe_ssh_close(_ref, nil), do: :ok

  defp safe_ssh_close(ref, ch) do
    :ssh_connection.close(ref, ch)
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  # Single cleanup helper invoked by every termination-sensitive callback.
  # Order is intentional:
  #   1. Send the alt-screen LEAVE escape while the channel is still open so
  #      the client's primary screen buffer is restored before teardown.
  #   2. Stop the Raxol Lifecycle (idempotent, tolerates already-stopped pid).
  #   3. Stop the Sessions.Session (idempotent, tolerates already-stopped pid).
  #   4. Optionally close the SSH channel — only the lifecycle-EXIT path needs
  #      to actively close; `:closed` and `terminate` are already triggered by
  #      a closed channel.
  #   5. Decrement the global connection counter exactly once, gated by
  #      counter_counted?, so EOF→closed→terminate ordering does not
  #      double-decrement.
  # The helper is idempotent: if cleanup_done? is true it returns the state
  # unchanged. The returned state has cleanup_done?: true and
  # counter_counted?: false so subsequent invocations no-op.
  defp cleanup(%__MODULE__{cleanup_done?: true} = state, _opts), do: state

  defp cleanup(%__MODULE__{} = state, opts) do
    send_alt_screen_leave(state)
    stop_lifecycle(state.lifecycle_pid)
    _ = stop_session(state.session_pid)

    if Keyword.get(opts, :close_channel, false) do
      maybe_close_channel(state)
    end

    if state.counter_counted? do
      _ = decrement_connection_count()
    end

    %__MODULE__{state | cleanup_done?: true, counter_counted?: false}
  end

  # --- Connection limit via ETS atomic counter ---

  @counter_table __MODULE__.Counter

  @doc """
  Initializes the ETS counter table for tracking active SSH connections.
  Must be called once before the daemon starts accepting connections.
  Called from `Foglet.SSH.Supervisor.init/1`.
  """
  def init_counter do
    _ = :ets.new(@counter_table, [:named_table, :public, :set])
    :ets.insert(@counter_table, {:count, 0})
    :ok
  end

  defp check_connection_limit do
    # Atomically increment; if the result exceeds the limit, decrement and reject.
    new_count = :ets.update_counter(@counter_table, :count, {2, 1})

    if new_count > @max_connections do
      _ = :ets.update_counter(@counter_table, :count, {2, -1, 0, 0})
      :over_limit
    else
      :ok
    end
  end

  defp decrement_connection_count do
    :ets.update_counter(@counter_table, :count, {2, -1, 0, 0})
  end
end
