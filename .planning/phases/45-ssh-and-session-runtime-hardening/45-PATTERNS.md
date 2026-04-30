# Phase 45: SSH And Session Runtime Hardening - Pattern Map

## PATTERN MAPPING COMPLETE

## Target Files

| File | Role | Closest existing analog |
|------|------|-------------------------|
| `lib/foglet_bbs/ssh/pubkey_stash.ex` | Add timestamped entries, TTL miss handling, and sweep cleanup | Existing `init/0`, `put/2`, `pop/1` ETS module |
| `test/foglet_bbs/ssh/cli_handler_test.exs` | Add pubkey stash TTL and CLI counter callback tests | Current PubkeyStash correlation and direct SSH callback tests |
| `lib/foglet_bbs/tui/session_context.ex` | Carry SSH peer metadata from CLIHandler to App | Existing typed session context fields |
| `lib/foglet_bbs/ssh/cli_handler.ex` | Populate peer metadata and centralize cleanup/counter behavior | Current `build_context/3`, `handle_msg/2`, `handle_ssh_msg/2`, `terminate/2` |
| `lib/foglet_bbs/tui/app.ex` | Pass audit metadata into session promotion | Current `do_update({:promote_session, user}, state)` |
| `lib/foglet_bbs/sessions/supervisor.ex` | Add `promote_guest_session/3` opts and replacement audit result | Current `promote_guest_session/2` and `replace_then_promote/3` |
| `lib/foglet_bbs/sessions/session.ex` | Log promotion with structured metadata | Current `handle_cast({:promote_to_user, user}, state)` |
| `test/foglet_bbs/sessions/supervisor_test.exs` | Preserve replacement and forced fallback proof with new promotion API | Current one-session-per-user and force-termination tests |
| `test/foglet_bbs/sessions/session_test.exs` | Direct promotion log/state assertions | Current Session GenServer behavior tests |

## Existing Boundary Pattern

`Foglet.SSH.CLIHandler` owns SSH callback lifecycle and builds the typed TUI
session context:

```elixir
%{
  session_context: %Foglet.TUI.SessionContext{
    user: user,
    user_id: user && user.id,
    session_pid: state.session_pid,
    pubkey_authenticated: not is_nil(user)
  },
  terminal_size: {width, height}
}
```

Extend this contract with SSH peer metadata instead of adding global process
dictionary state or durable rows.

## ETS Runtime Pattern

`PubkeyStash` is a small named ETS boundary:

```elixir
def put(peer_key, public_key) do
  :ets.insert(@table, {peer_key, public_key})
end

def pop(peer_key) do
  case :ets.take(@table, peer_key) do
    [{^peer_key, public_key}] -> {:ok, public_key}
    [] -> :miss
  end
end
```

Keep `put/2` and `pop/1` call sites compatible. Add arities/options only for
deterministic tests and TTL sweep.

## Callback Test Pattern

`CLIHandlerTest` already uses direct callback invocations for deterministic
runtime behavior:

```elixir
state = %CLIHandler{channel_id: 7, connection_ref: nil, session_pid: session_pid}

assert {:stop, 7, ^state} =
         CLIHandler.handle_ssh_msg({:ssh_cm, make_ref(), {:closed, 7}}, state)
```

Add counter assertions around callback results instead of relying on real SSH
daemon timing for every lifecycle branch.

## Session Replacement Pattern

`Sessions.Supervisor.promote_guest_session/2` is the one-session-per-user
boundary:

```elixir
case Registry.lookup(@registry, user.id) do
  [] -> Foglet.Sessions.Session.promote_to_user(guest_pid, user)
  [{^guest_pid, _}] -> :ok
  [{old_pid, _}] -> replace_then_promote(old_pid, guest_pid, user)
end
```

Add audit metadata here because this function sees whether a prior session was
absent, the same process, or replaced.

## Verification Greps

```bash
rtk rg -n "def sweep|@ttl_ms|System\\.monotonic_time" lib/foglet_bbs/ssh/pubkey_stash.ex
rtk rg -n "ssh_peer" lib/foglet_bbs/tui/session_context.ex lib/foglet_bbs/ssh/cli_handler.ex lib/foglet_bbs/tui/app.ex
rtk rg -n "promote_guest_session\\(.*audit|promote_to_user\\(.*audit|guest_promoted" lib/foglet_bbs/sessions lib/foglet_bbs/tui/app.ex
rtk rg -n "cleanup_done\\?|counter_counted\\?|defp cleanup" lib/foglet_bbs/ssh/cli_handler.ex
```
