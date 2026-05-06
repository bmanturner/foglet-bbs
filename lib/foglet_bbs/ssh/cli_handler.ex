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
  2. Pop the stashed pubkey (or `:miss` if no key was offered; the SSH transport
     normally requires public-key auth, so `:miss` is a defensive guest path).
  3. If a pubkey was offered, authenticate it through
     `Accounts.authenticate_by_public_key/1` to find the matching user and
     record last-used metadata. When no active user matches, keep the
     OpenSSH-encoded text for guest registration.
  4. Build the session context accordingly.

  ## Connection limit

  Enforced here rather than via a separate GenServer. The module attribute
  `@max_connections` is the limit. A simple `:persistent_term` counter tracks
  active connections so we avoid a global GenServer bottleneck.
  """

  @behaviour :ssh_server_channel

  require Logger

  alias Foglet.Sessions
  alias Foglet.Sessions.Preferences
  alias Foglet.SSH.CLIHandler.Cleanup
  alias Foglet.SSH.CLIHandler.ConnectionCounter
  alias Foglet.SSH.CLIHandler.PubkeyIdentity
  alias Raxol.SSH.IOAdapter

  @max_connections 500

  defstruct [
    :channel_id,
    :connection_ref,
    :peer,
    :pubkey_user,
    :pubkey_gate,
    :session_pid,
    :lifecycle_pid,
    :dispatcher_pid,
    :door_runner_pid,
    :active_door_manifest,
    :offered_ssh_public_key,
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
    new_state = Cleanup.cleanup(state, close_channel: true)
    {:stop, new_state.channel_id || 0, new_state}
  end

  @impl true
  def handle_msg({:foglet_launch_door, manifest, session, terminal_size}, state) do
    {:ok, launch_door_runner(state, manifest, session, terminal_size)}
  end

  @impl true
  def handle_msg({:door_started, pid, door_id}, %{door_runner_pid: pid} = state) do
    track_door_presence(state, pid, door_id)
    _ = safe_ssh_send(state.connection_ref, state.channel_id, "\r\n[Door #{door_id} started]\r\n")
    {:ok, state}
  end

  @impl true
  def handle_msg({:door_exited, pid, door_id, reason, status}, %{door_runner_pid: pid} = state) do
    Foglet.Sessions.DoorPresence.untrack_runner(pid)
    message = "\r\n[Door #{door_id} exited: #{inspect(reason)}#{exit_status_suffix(status)}]\r\n"
    _ = safe_ssh_send(state.connection_ref, state.channel_id, message)
    dispatch_current_window(state)
    dispatch_raw(state.dispatcher_pid, {:door_exited, door_id, reason, status})
    {:ok, %{state | door_runner_pid: nil, active_door_manifest: nil}}
  end

  @impl true
  def handle_msg({:door_exited, _pid, _door_id, _reason, _status}, state), do: {:ok, state}

  # FOG-674: catch unmatched linked-process EXITs so abnormal failures are
  # observable. Privacy-safe context only: peer host:port, the involved pid,
  # and the sanitized reason tag — no auth payloads, no channel data.
  @impl true
  def handle_msg({:EXIT, pid, reason}, state) when reason not in [:normal, :shutdown] do
    Logger.warning("[SSH.CLIHandler] Unexpected linked exit",
      event: :ssh_cli_handler_linked_exit,
      pid: inspect(pid),
      peer: inspect(state.peer),
      reason: sanitize_reason(reason)
    )

    {:ok, state}
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
    Cleanup.send_alt_screen_enter(state)

    {:ok, lifecycle_pid} =
      start_lifecycle(
        io_writer: make_crlf_writer(state.connection_ref, state.channel_id),
        width: width,
        height: height,
        context: context
      )

    finish_lifecycle_start(state, conn, ch, want_reply, lifecycle_pid, width, height)
  end

  @impl true
  def handle_ssh_msg({:ssh_cm, _conn, {:data, _ch, _type, data}}, state) do
    if active_door?(state) do
      Foglet.Doors.Runner.input(state.door_runner_pid, data)
    else
      events = IOAdapter.parse_input(data)
      dispatch_events(state.dispatcher_pid, events)
    end

    {:ok, state}
  end

  @impl true
  def handle_ssh_msg({:ssh_cm, _conn, {:window_change, _ch, width, height, _pxw, _pxh}}, state) do
    if active_door?(state) do
      Foglet.Doors.Runner.resize(state.door_runner_pid, {width, height})
    else
      # Two dispatches, on purpose:
      #   1. :resize hits Raxol's dispatcher system-event path
      #      (vendor/raxol/.../dispatcher.ex:615) — resizes the rendering engine
      #      but never reaches App.update/2.
      #   2. :window is not a system event, so it flows through to App.update/2
      #      where normalize_message/1 turns it into {:window_change, w, h} and
      #      do_update/2 updates state.terminal_size. Without this second
      #      dispatch, SizeGate.too_small? stays stuck on the initial PTY size
      #      and the gate never triggers on resize.
      dispatch_window(state.dispatcher_pid, width, height)
    end

    # IN-01: Session.set_terminal_size/2 is owned by the App's
    # do_update({:window_change, …}, …) handler. While a door is active we
    # intentionally suppress App/Raxol resize dispatches so Foglet does not
    # repaint over the child PTY; the current size is replayed when the door
    # exits before Foglet renders its return modal.

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
    Cleanup.send_alt_screen_leave(state)
    {:ok, state}
  end

  @impl true
  def handle_ssh_msg({:ssh_cm, _conn, {:closed, _ch}}, state) do
    # Belt-and-suspenders: if the client dropped without sending EOF
    # (e.g. window closed abruptly), the cleanup helper sends LEAVE anyway.
    # The channel may already be fully closed, in which case the send no-ops.
    new_state = Cleanup.cleanup(state, close_channel: false)
    {:stop, new_state.channel_id || 0, new_state}
  end

  @impl true
  def handle_ssh_msg(_msg, state), do: {:ok, state}

  @impl true
  # FOG-674: orderly channel teardown is intentionally silent.
  def terminate(:normal, state), do: terminate_cleanup(state)
  def terminate(:shutdown, state), do: terminate_cleanup(state)
  def terminate({:shutdown, _}, state), do: terminate_cleanup(state)

  def terminate(reason, state) do
    # FOG-674: log abnormal channel teardown with privacy-safe context only —
    # peer host:port + sanitized reason tag. Never raw key material, password
    # attempts, or channel data.
    Logger.warning("[SSH.CLIHandler] Channel terminating abnormally",
      event: :ssh_cli_handler_terminated_abnormal,
      peer: inspect(state.peer),
      reason: sanitize_reason(reason)
    )

    terminate_cleanup(state)
  end

  defp terminate_cleanup(state) do
    _ = Cleanup.cleanup(state, close_channel: false)
    :ok
  end

  # FOG-674: collapse channel-teardown reasons to a single safe atom.
  defp sanitize_reason(reason) when is_atom(reason), do: reason
  defp sanitize_reason(tuple) when is_tuple(tuple) and tuple_size(tuple) > 0, do: elem(tuple, 0)
  defp sanitize_reason(_), do: :unknown

  # Internal channel-up implementation. Exposed via channel_up_for_test/4 so
  # focused unit tests can drive the over-limit and rate-limit branches with a
  # specified peer rather than depending on a real SSH connection_info lookup.
  defp do_channel_up(%__MODULE__{} = state, channel_id, connection_ref, peer) do
    case ConnectionCounter.check_in(@max_connections) do
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
        # delegations are no-ops. Use update-syntax (not a fresh struct) so any
        # field init/1 sets in the future is preserved on the rejection path
        # symmetrically with the accepted branch.
        new_state = %__MODULE__{
          state
          | over_limit: true,
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
          pubkey_resolution = PubkeyIdentity.resolve(peer)
          pubkey_user = Map.get(pubkey_resolution, :user)
          pubkey_gate = Map.get(pubkey_resolution, :gate)
          offered_ssh_public_key = Map.get(pubkey_resolution, :offered_ssh_public_key)
          session_pid = PubkeyIdentity.start_session(pubkey_resolution)

          # Successful BBS connect boundary: count only after connection-limit
          # and rate-limit gates pass and the guest/member session exists. This
          # keeps rejected attempts, later auth promotion, cleanup, resize, and
          # old-session replacement cleanup outside the durable total-call path.
          _new_total_call_count = Foglet.SiteCounters.increment_call_count()

          Logger.info(
            "[SSH.CLIHandler] Channel up — peer=#{inspect(peer)} " <>
              "user=#{inspect(pubkey_user && pubkey_user.handle)} " <>
              "pubkey_gate=#{inspect(pubkey_gate)} " <>
              "session_pid=#{inspect(session_pid)}"
          )

          new_state = %__MODULE__{
            state
            | channel_id: channel_id,
              connection_ref: connection_ref,
              peer: peer,
              pubkey_user: pubkey_user,
              pubkey_gate: pubkey_gate,
              session_pid: session_pid,
              offered_ssh_public_key: offered_ssh_public_key,
              counter_counted?: true,
              cleanup_done?: false
          }

          {:ok, new_state}
        else
          # check_connection_limit/0 incremented the counter before we got here;
          # undo it so rate-limited connections don't drift the count upward.
          # After this immediate compensation the counter is balanced, so the
          # rejected state owes no further decrement.
          _ = ConnectionCounter.decrement()

          _ =
            safe_ssh_send(
              connection_ref,
              channel_id,
              "Rate limit exceeded. Try again later.\r\n"
            )

          _ = safe_ssh_close(connection_ref, channel_id)

          new_state = %__MODULE__{
            state
            | over_limit: true,
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

  @doc false
  def context_for_test(%__MODULE__{} = state, width, height) do
    build_context(state, width, height)
  end

  @doc false
  def peer_from_connection_info_for_test(info), do: peer_from_connection_info(info)

  @doc false
  def finish_lifecycle_start_for_test(
        %__MODULE__{} = state,
        conn,
        ch,
        want_reply,
        lifecycle_pid,
        width,
        height
      ) do
    finish_lifecycle_start(state, conn, ch, want_reply, lifecycle_pid, width, height)
  end

  # --- Private helpers ---

  # Wrap IOAdapter.make_writer so bare LF rendered by Raxol.Terminal.Renderer
  # is translated to CRLF before going to the SSH channel. Without this, raw
  # SSH mode doesn't return the cursor to column 0 on \n, so every logical
  # row consumes ~2 visible rows (auto-wrap stair-step). Normalize existing
  # \r\n first so we don't turn them into \r\r\n.
  defp make_crlf_writer(connection_ref, channel_id) do
    inner = IOAdapter.make_writer(connection_ref, channel_id)

    fn data ->
      cooked =
        data
        |> IO.iodata_to_binary()
        |> :binary.replace("\r\n", "\n", [:global])
        |> :binary.replace("\n", "\r\n", [:global])

      inner.(cooked)
    end
  end

  defp read_peer(connection_ref) do
    connection_ref
    |> :ssh.connection_info([:peer])
    |> peer_from_connection_info()
  rescue
    _ -> :unknown
  end

  defp peer_from_connection_info([{:peer, {transport, {ip, port}}}])
       when is_atom(transport) and is_tuple(ip) and is_integer(port),
       do: {ip, port}

  defp peer_from_connection_info([{:peer, {{ip, port}, _socket}}])
       when is_tuple(ip) and is_integer(port),
       do: {ip, port}

  defp peer_from_connection_info([{:peer, {ip, port}}]) when is_tuple(ip) and is_integer(port),
    do: {ip, port}

  defp peer_from_connection_info(_info), do: :unknown

  # Build the context map that reaches Foglet.TUI.App.init/1.
  # The Lifecycle passes `%{width:, height:, options: [all_lifecycle_opts]}` to
  # init/1. App.init/1 reads `context[:options][:context]` to get this map.
  defp build_context(state, width, height) do
    user = session_user(state) || state.pubkey_user

    preferences = Preferences.from_user(user)

    %{
      session_context: %Foglet.TUI.SessionContext{
        user: user,
        user_id: user && user.id,
        session_pid: state.session_pid,
        pubkey_authenticated: not is_nil(state.pubkey_user),
        registration_mode: Foglet.Config.registration_mode(),
        guest_mode_enabled: Foglet.Config.guest_mode_enabled?(),
        guest: false,
        max_post_length: Foglet.Config.max_post_length(),
        timezone: preferences.timezone,
        time_format: preferences.time_format,
        theme_id: preferences.theme_id,
        theme: preferences.theme,
        ssh_peer: state.peer,
        offered_ssh_public_key: if(is_nil(user), do: state.offered_ssh_public_key),
        door_handler_pid: self()
      },
      terminal_size: {width, height}
    }
  end

  defp session_user(state) do
    if is_pid(state.session_pid) do
      case Sessions.Session.get_state(state.session_pid) do
        %{user_id: nil} -> nil
        %{user_id: uid} -> Foglet.Accounts.get_user(uid)
      end
    else
      nil
    end
  end

  defp start_lifecycle(opts) do
    Raxol.Core.Runtime.Lifecycle.start_link(Foglet.TUI.App,
      # Pid-only registration: Raxol derives a globally-unique name from the
      # app module unless `:name` is present, which collapses every SSH
      # session onto one Lifecycle and rejects concurrent connections with
      # `{:error, {:already_started, _}}`. CLIHandler tracks the pid in
      # state, so a registered name is unnecessary.
      name: nil,
      environment: :ssh,
      io_writer: Keyword.fetch!(opts, :io_writer),
      width: Keyword.fetch!(opts, :width),
      height: Keyword.fetch!(opts, :height),
      context: Keyword.fetch!(opts, :context),
      # Keep Raxol's own alt-screen lifecycle enabled as a backup. The direct
      # CLIHandler takeover above runs earlier and also clears scrollback.
      alternate_screen: true
    )
  end

  defp finish_lifecycle_start(state, conn, ch, want_reply, lifecycle_pid, width, height) do
    Process.link(lifecycle_pid)

    # WR-05: resolve the dispatcher pid once here, immediately after Lifecycle
    # start, and stash it on state so per-keystroke / per-resize dispatches do
    # not block on a synchronous GenServer.call into the Lifecycle. The
    # dispatcher pid is stable for the Lifecycle's lifetime; if a future Raxol
    # version can rebuild it, refresh on the EXIT path or expose a notification.
    case resolve_dispatcher(lifecycle_pid) do
      {:ok, dispatcher_pid} ->
        :ssh_connection.reply_request(conn, want_reply, :success, ch)

        {:ok,
         %{
           state
           | lifecycle_pid: lifecycle_pid,
             dispatcher_pid: dispatcher_pid,
             width: width,
             height: height
         }}

      {:error, reason} ->
        failed_state = %{
          state
          | lifecycle_pid: lifecycle_pid,
            dispatcher_pid: nil,
            width: width,
            height: height
        }

        Logger.warning(
          "[SSH.CLIHandler] Dispatcher resolution failed during PTY startup; closing channel #{inspect(ch)}",
          event: :ssh_cli_handler_dispatcher_resolution_failed,
          peer: inspect(failed_state.peer),
          pid: inspect(lifecycle_pid),
          reason: sanitize_reason(reason)
        )

        new_state = Cleanup.cleanup(failed_state, close_channel: true)
        {:stop, ch || 0, new_state}
    end
  end

  defp dispatch_events(dispatcher_pid, events) when is_pid(dispatcher_pid) do
    Enum.each(events, &GenServer.cast(dispatcher_pid, {:dispatch, &1}))
  end

  defp dispatch_window(dispatcher_pid, width, height) do
    resize = Raxol.Core.Events.Event.new(:resize, %{width: width, height: height})
    window = Raxol.Core.Events.Event.new(:window, %{width: width, height: height})
    dispatch_events(dispatcher_pid, [resize, window])
  end

  defp dispatch_current_window(%{width: width, height: height, dispatcher_pid: dispatcher_pid})
       when is_integer(width) and width > 0 and is_integer(height) and height > 0 do
    dispatch_window(dispatcher_pid, width, height)
  end

  defp dispatch_current_window(_state), do: :ok

  defp dispatch_raw(nil, _message), do: :ok

  defp dispatch_raw(dispatcher_pid, message) when is_pid(dispatcher_pid) do
    event = Raxol.Core.Events.Event.new(:foglet_runtime, %{message: message})
    GenServer.cast(dispatcher_pid, {:dispatch, event})
  end

  # Resolve the Raxol dispatcher pid from the Lifecycle once at PTY start.
  # If the Lifecycle is unreachable, PTY startup fails closed instead of
  # accepting a terminal whose later input and resize events would no-op.
  defp resolve_dispatcher(lifecycle_pid) when is_pid(lifecycle_pid) do
    case GenServer.call(lifecycle_pid, :get_full_state) do
      %{dispatcher_pid: pid} when is_pid(pid) -> {:ok, pid}
      other -> {:error, {:unexpected_lifecycle_state, other}}
    end
  catch
    :exit, reason -> {:error, {:lifecycle_unreachable, reason}}
  end

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

  defp launch_door_runner(%__MODULE__{door_runner_pid: pid} = state, _manifest, _session, _size)
       when is_pid(pid) do
    _ =
      safe_ssh_send(state.connection_ref, state.channel_id, "\r\nA door is already running.\r\n")

    state
  end

  defp launch_door_runner(%__MODULE__{} = state, manifest, session, terminal_size) do
    output = make_crlf_writer(state.connection_ref, state.channel_id)
    _ = safe_ssh_send(state.connection_ref, state.channel_id, "\e[2J\e[H")

    case Foglet.Doors.Supervisor.start_runner(
           manifest: manifest,
           session: session,
           terminal_size: terminal_size,
           output: output,
           owner: self()
         ) do
      {:ok, pid} ->
        %{state | door_runner_pid: pid, active_door_manifest: manifest}

      {:error, reason} ->
        _ =
          safe_ssh_send(
            state.connection_ref,
            state.channel_id,
            "\r\nDoor launch failed: #{inspect(reason)}\r\n"
          )

        dispatch_raw(state.dispatcher_pid, {:door_launch_failed, manifest.id, reason})
        state
    end
  end

  defp active_door?(%__MODULE__{door_runner_pid: pid}) when is_pid(pid), do: Process.alive?(pid)
  defp active_door?(_state), do: false

  defp track_door_presence(%__MODULE__{} = state, runner_pid, door_id) do
    with user_id when is_binary(user_id) <- current_user_id(state),
         door <- state.active_door_manifest || %{id: door_id, display_name: door_id} do
      Foglet.Sessions.DoorPresence.track(user_id, door, runner_pid)
    else
      _ -> :ok
    end
  end

  defp current_user_id(%{session_pid: session_pid} = state) when is_pid(session_pid) do
    case Sessions.Session.get_state(session_pid) do
      %{user_id: user_id} when is_binary(user_id) -> user_id
      _session_state -> pubkey_user_id(state)
    end
  catch
    :exit, _reason -> pubkey_user_id(state)
  end

  defp current_user_id(state), do: pubkey_user_id(state)

  defp pubkey_user_id(%{pubkey_user: %{id: user_id}}) when is_binary(user_id), do: user_id
  defp pubkey_user_id(_state), do: nil

  defp exit_status_suffix(nil), do: ""
  defp exit_status_suffix(status), do: ", status #{status}"

  @doc """
  Initializes the ETS counter table for tracking active SSH connections.

  Called from `Foglet.SSH.Supervisor.init/1` before the daemon accepts
  connections. The table is VM-local runtime state, so initialization is
  idempotent: if a live table already exists, preserve its current count rather
  than resetting active-connection accounting during an SSH supervisor restart.
  """
  def init_counter, do: ConnectionCounter.init()
end
