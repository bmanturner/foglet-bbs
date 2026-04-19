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
  3. If a pubkey was offered, look it up in `Accounts.get_user_by_public_key/1`
     to find the matching user.
  4. Build the session context accordingly.

  ## Connection limit

  Enforced here rather than via a separate GenServer. The module attribute
  `@max_connections` is the limit. A simple `:persistent_term` counter tracks
  active connections so we avoid a global GenServer bottleneck.
  """

  @behaviour :ssh_server_channel

  require Logger

  alias Foglet.Sessions
  alias Raxol.SSH.IOAdapter

  @max_connections 500

  defstruct [
    :channel_id,
    :connection_ref,
    :peer,
    :session_pid,
    :lifecycle_pid,
    :width,
    :height
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

    case check_connection_limit() do
      :over_limit ->
        _ =
          :ssh_connection.send(
            connection_ref,
            channel_id,
            "Connection limit reached. Try again later.\r\n"
          )

        _ = :ssh_connection.close(connection_ref, channel_id)
        {:ok, state}

      :ok ->
        increment_connection_count()
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
            session_pid: session_pid
        }

        {:ok, new_state}
    end
  end

  # Lifecycle exited — close the channel so the client terminal disconnects.
  @impl true
  def handle_msg({:EXIT, pid, reason}, %{lifecycle_pid: pid} = state) do
    Logger.info(
      "[SSH.CLIHandler] Lifecycle #{inspect(pid)} exited (#{inspect(reason)}); closing channel"
    )

    # Restore the client's primary screen buffer before we close the channel.
    # This is the graceful-quit path (TUI Command.quit → Lifecycle :shutdown →
    # {:EXIT, lifecycle_pid}). At this point the SSH channel is still open, so
    # the escape reaches iTerm2 before teardown. Without this, the TUI's final
    # frame lingers on the alt buffer after disconnect.
    send_alt_screen_leave(state)
    maybe_close_channel(state)
    {:stop, state.channel_id || 0, state}
  end

  @impl true
  def handle_msg(_msg, state), do: {:ok, state}

  @impl true
  def handle_ssh_msg(
        {:ssh_cm, _conn, {:pty, _ch, _want_reply, {_term, width, height, _pxw, _pxh, _modes}}},
        state
      ) do
    context = build_context(state, width, height)

    {:ok, lifecycle_pid} =
      Raxol.Core.Runtime.Lifecycle.start_link(Foglet.TUI.App,
        environment: :ssh,
        io_writer: make_crlf_writer(state.connection_ref, state.channel_id),
        width: width,
        height: height,
        context: context,
        # Take over the SSH client's terminal with the alternate screen buffer
        # (DECSET 1049). The TUI runs on the alt buffer; on disconnect the
        # client's primary buffer is restored, leaving its scrollback untouched.
        alternate_screen: true
      )

    Process.link(lifecycle_pid)

    {:ok, %{state | lifecycle_pid: lifecycle_pid, width: width, height: height}}
  end

  @impl true
  def handle_ssh_msg({:ssh_cm, _conn, {:data, _ch, _type, data}}, state) do
    events = IOAdapter.parse_input(data)
    dispatch_events(state.lifecycle_pid, events)
    {:ok, state}
  end

  @impl true
  def handle_ssh_msg({:ssh_cm, _conn, {:window_change, _ch, width, height, _pxw, _pxh}}, state) do
    # Use Event.new(:resize,...) so Raxol's Dispatcher routes this through
    # handle_resize_event/2 (type: :resize is in system_event?/1's allowlist).
    # Event.window/3 produces type: :window, which is NOT a system event and
    # goes to the app update/2 path, leaving the Rendering Engine dimensions
    # unchanged. This is the root cause of Gap 6 (terminal resize ignored).
    event = Raxol.Core.Events.Event.new(:resize, %{width: width, height: height})
    dispatch_events(state.lifecycle_pid, [event])

    if is_pid(state.session_pid) do
      Sessions.Session.set_terminal_size(state.session_pid, {width, height})
    end

    {:ok, %{state | width: width, height: height}}
  end

  @impl true
  def handle_ssh_msg({:ssh_cm, _conn, {:shell, _ch, _want_reply}}, state) do
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
    # (e.g. window closed abruptly), try the LEAVE escape anyway. The
    # channel may already be fully closed, in which case the send no-ops.
    send_alt_screen_leave(state)
    stop_lifecycle(state.lifecycle_pid)
    _ = stop_session(state.session_pid)
    _ = decrement_connection_count()
    {:stop, state.channel_id || 0, state}
  end

  @impl true
  def handle_ssh_msg(_msg, state), do: {:ok, state}

  @impl true
  def terminate(_reason, state) do
    stop_lifecycle(state.lifecycle_pid)
    _ = stop_session(state.session_pid)
    :ok
  end

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
            case Foglet.Accounts.get_user_by_public_key(openssh_text) do
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
    case Sessions.Supervisor.start_session(
           user_id: user.id,
           handle: user.handle,
           role: user.role
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
          %{user_id: uid} -> Foglet.Accounts.get_user!(uid)
        end
      else
        nil
      end

    reg_mode =
      try do
        Foglet.Config.get!("registration_mode")
      rescue
        _ -> "open"
      end

    max_post_length =
      try do
        Foglet.Config.get!("max_post_length")
      rescue
        _ -> 8192
      end

    %{
      session_context: %{
        user: user,
        user_id: user && user.id,
        session_pid: state.session_pid,
        pubkey_authenticated: not is_nil(user),
        registration_mode: reg_mode,
        max_post_length: max_post_length
      },
      terminal_size: {width, height}
    }
  end

  defp dispatch_events(nil, _events), do: :ok

  defp dispatch_events(lifecycle_pid, events) do
    case get_dispatcher(lifecycle_pid) do
      nil -> :ok
      pid -> Enum.each(events, &GenServer.cast(pid, {:dispatch, &1}))
    end
  end

  defp get_dispatcher(lifecycle_pid) do
    if Process.alive?(lifecycle_pid) do
      %{dispatcher_pid: pid} = GenServer.call(lifecycle_pid, :get_full_state)
      pid
    else
      nil
    end
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

  defp increment_connection_count do
    # Already incremented atomically inside check_connection_limit/0; this is a no-op.
    :ok
  end

  defp decrement_connection_count do
    :ets.update_counter(@counter_table, :count, {2, -1, 0, 0})
  end
end
