# Phase 45: SSH And Session Runtime Hardening - Research

## RESEARCH COMPLETE

## User Constraints

### Public-Key Stash Cleanup
- D-01: Add timestamped TTL/sweep behavior inside `Foglet.SSH.PubkeyStash` rather than introducing durable storage or changing the SSH authentication model. ETS remains ephemeral and reconstructable; stale entries are bounded by age and removed through an explicit sweep path.
- D-02: Keep `put/2` and `pop/1` semantics compatible for `KeyCB` and `CLIHandler`. Add the smallest public or test-supported API needed to make stale-entry cleanup deterministic, such as injectable timestamps, a sweep function, or TTL options.
- D-03: Do not change `no_auth_needed: true` or the guest fallback behavior. Public-key matching remains a convenience handoff into an authenticated session when the offered key matches; missing or expired stash entries still become guest sessions.

### Promotion Audit Metadata
- D-04: Carry peer metadata from `Foglet.SSH.CLIHandler` into the session context/promotion path instead of logging peer context only at channel-up time. Promotion happens later through `Foglet.TUI.App` and `Foglet.Sessions.Supervisor`, so the peer must be available at that boundary.
- D-05: Emit structured Logger metadata for guest-to-user promotion, including promoted session pid or identity, target user id/handle, peer context when available, and whether a prior session was replaced when known. Durable database audit rows are out of scope.
- D-06: Preserve one-session-per-user semantics. Any replacement metadata should describe the existing replacement protocol; it must not introduce a new replacement model or weaken the Registry-slot-before-promotion invariant.

### Unified CLIHandler Cleanup
- D-07: Extract one cleanup helper in `Foglet.SSH.CLIHandler` that owns alt-screen leave, lifecycle stop, session stop, connection-counter decrement, and channel close where applicable.
- D-08: Make cleanup idempotent enough for callback delegation: EOF may restore the alt screen while the actual stop follows on closed, lifecycle EXIT may close the channel before `terminate/2`, and `terminate/2` may run after partial cleanup. The shared helper should prevent double decrement and tolerate already-closed resources.
- D-09: Keep terminal restoration best-effort and direct to the SSH channel. The phase hardens existing cleanup paths; it should not redesign Raxol lifecycle ownership or terminal rendering behavior.

### Connection Counter Proof
- D-10: Prove counter balance with focused callback/unit paths plus the existing real SSH channel coverage where it provides useful confidence. Do not require brittle full-network simulations for every listed branch when a deterministic direct callback path can prove the invariant.
- D-11: Tests should reset the ETS counter explicitly, drive each listed lifecycle path, and assert the counter returns to the expected value without drifting upward or below zero.
- D-12: Over-limit reject and rate-limit reject paths should remain semantically rejected states that do not require later decrement. The tests should make this explicit so future cleanup refactors do not double-decrement or leak counts.

### Forced-Promotion Fallback
- D-13: Preserve the existing deterministic `promote_guest_session/2 force-terminates a session that does not stop gracefully` test as the SESS-01 acceptance proof unless implementation changes require an equivalent assertion.
- D-14: Keep the fallback proof process-synchronized with monitors and Registry/state checks. Avoid `Process.sleep/1` and pure liveness checks.

### the agent's Discretion
- Exact TTL duration, sweep function names, metadata key names, and whether promotion metadata is passed as opts or stored in `SessionContext`.
- Cleanup idempotence may use state flags, returned state, helper options, or narrow callback wrappers, provided counter behavior is provably balanced.
- Test-only helpers are acceptable when they make fragile SSH paths deterministic without broadening production APIs unnecessarily.

## Project Constraints (from AGENTS.md)

- Use `rtk` as the shell command prefix in this repo. [VERIFIED: AGENTS.md]
- Foglet is SSH-first; do not add end-user browser workflows. [VERIFIED: AGENTS.md]
- Keep domain workflows in `Foglet.*`; Phoenix namespaces are infrastructure. [VERIFIED: AGENTS.md]
- Postgres is authoritative for durable state; ETS/process state must be reconstructable. [VERIFIED: AGENTS.md]
- Keep SSH channel lifecycle in `Foglet.SSH.CLIHandler`; keep UI behavior in `Foglet.TUI.App` and screens. [VERIFIED: AGENTS.md]
- Use `start_supervised!/1` in tests; avoid `Process.sleep/1` and `Process.alive?/1`; synchronize with monitors, messages, or `:sys.get_state/1`. [VERIFIED: AGENTS.md]
- Do not write tests that only assert the presence or absence of text. [VERIFIED: AGENTS.md]
- Run `rtk mix precommit` when code changes are complete. [VERIFIED: AGENTS.md]

## Standard Stack

- Use existing ETS-backed runtime modules for SSH handoff state. `Foglet.SSH.PubkeyStash` already owns a named public ETS table and `Application.start/2` initializes it. [VERIFIED: `lib/foglet_bbs/ssh/pubkey_stash.ex`, `lib/foglet_bbs/application.ex`]
- Use existing `:ssh_server_channel` callback tests for deterministic lifecycle coverage. `test/foglet_bbs/ssh/cli_handler_test.exs` already drives `handle_ssh_msg/2`, `handle_msg/2`, and real SSH channel startup. [VERIFIED: codebase]
- Use `ExUnit.CaptureLog` for log assertions when needed, but prefer assertions on structured behavior and process state over matching only message text. [VERIFIED: `test/foglet_bbs/ssh/daemon_owner_test.exs`, AGENTS.md]
- Keep session replacement in `Foglet.Sessions.Supervisor`; `Foglet.Sessions.Session` should only apply final promotion state after the supervisor has ensured the Registry slot is clear. [VERIFIED: `lib/foglet_bbs/sessions/supervisor.ex`, `lib/foglet_bbs/sessions/session.ex`]

## Architecture Patterns

### Pubkey stash

`PubkeyStash.put/2` currently stores `{peer_key, public_key}` and `pop/1` expects that shape. The safe upgrade path is to store `{peer_key, public_key, inserted_at_ms}` internally while accepting legacy two-tuples in `pop/1` if necessary during the change. [VERIFIED: `lib/foglet_bbs/ssh/pubkey_stash.ex`]

Recommended API:

```elixir
@ttl_ms :timer.minutes(5)

def put(peer_key, public_key, now_ms \\ System.monotonic_time(:millisecond))
def pop(peer_key, now_ms \\ System.monotonic_time(:millisecond))
def sweep(now_ms \\ System.monotonic_time(:millisecond), ttl_ms \\ @ttl_ms)
```

`pop/2` should treat expired entries as `:miss` and delete them. `sweep/2` should remove only entries older than `ttl_ms` and return a count so tests can prove stale entries were removed. [VERIFIED: phase context + codebase]

### Promotion audit metadata

`CLIHandler.build_context/3` is the right boundary to add SSH peer context because it already creates `%Foglet.TUI.SessionContext{}` for `App.init/1`. `App.do_update({:promote_session, user}, state)` is the right boundary to pass audit context to `Sessions.Supervisor.promote_guest_session/3`. [VERIFIED: `lib/foglet_bbs/ssh/cli_handler.ex`, `lib/foglet_bbs/tui/app.ex`]

Recommended path:

1. Add `ssh_peer` to `Foglet.TUI.SessionContext`.
2. Set `ssh_peer: state.peer` in `CLIHandler.build_context/3`.
3. Add `promote_guest_session/3` with an `opts` keyword list in `Foglet.Sessions.Supervisor`.
4. Derive replacement metadata in the supervisor before promotion: `:none`, `:same_session`, or `{:replaced, old_pid}`.
5. Pass audit metadata to `Foglet.Sessions.Session.promote_to_user/3`.
6. Log in `Session.handle_cast/2` with metadata keys such as `event: :guest_promoted`, `session_pid: self()`, `user_id: user.id`, `handle: user.handle`, `ssh_peer: peer`, and `replacement: replacement`.

This keeps replacement authority in the supervisor and final session mutation in the session process. [VERIFIED: codebase]

### CLI cleanup and counter balance

`CLIHandler` currently duplicates cleanup in lifecycle `:EXIT`, `{:closed, _}`, and `terminate/2`. A helper should own all side effects and return state with a cleanup flag so repeated calls cannot double-decrement. [VERIFIED: `lib/foglet_bbs/ssh/cli_handler.ex`]

Recommended struct change:

```elixir
defstruct [
  :channel_id,
  :connection_ref,
  :peer,
  :session_pid,
  :lifecycle_pid,
  :width,
  :height,
  over_limit: false,
  cleanup_done?: false,
  counter_counted?: false
]
```

Set `counter_counted?: true` only when `check_connection_limit/0` accepts the connection. Rejected over-limit and rate-limited states should keep it false after compensation. The cleanup helper should decrement only when `counter_counted?` is true and `cleanup_done?` is false. [VERIFIED: codebase + D-08/D-12]

## Don't Hand-Roll

- Do not add a GenServer solely for the pubkey stash TTL; ETS plus explicit sweep is enough for this phase. [VERIFIED: D-01]
- Do not add database audit tables; structured Logger metadata is the locked requirement. [VERIFIED: D-05]
- Do not simulate every SSH lifecycle path through a live network daemon; direct callback tests are acceptable for counter invariants. [VERIFIED: D-10]
- Do not change `no_auth_needed: true`, guest fallback behavior, or one-session-per-user replacement semantics. [VERIFIED: D-03, D-06]

## Common Pitfalls

- Double decrementing the counter when `{:eof, _}` and `{:closed, _}` both occur. EOF should restore alt-screen only; closed or lifecycle exit should own stop cleanup. [VERIFIED: codebase + D-08]
- Treating rate-limit rejection as an active connection that needs later cleanup. It should compensate immediately and mark the state as not counted. [VERIFIED: `CLIHandler.handle_msg/2` current comments]
- Losing peer context by logging it only at channel-up. Promotion happens later in `App.do_update/2`, so peer must be carried in `SessionContext`. [VERIFIED: D-04]
- Testing promotion audit only by checking a message string. The useful proof is that metadata is passed through the promotion path and emitted by the session process. [VERIFIED: AGENTS.md + D-05]
- Using `Process.sleep/1` to wait for casts or replacement fallback. Use `:sys.get_state/1`, monitors, and `assert_receive`. [VERIFIED: AGENTS.md]

## Code Examples

Recommended cleanup helper shape:

```elixir
defp cleanup(state, opts \\ []) do
  close_channel? = Keyword.get(opts, :close_channel?, false)

  if state.cleanup_done? do
    state
  else
    send_alt_screen_leave(state)
    stop_lifecycle(state.lifecycle_pid)
    _ = stop_session(state.session_pid)
    if close_channel?, do: maybe_close_channel(state)
    if state.counter_counted?, do: decrement_connection_count()
    %{state | cleanup_done?: true, counter_counted?: false}
  end
end
```

Recommended session context field:

```elixir
%Foglet.TUI.SessionContext{
  ...,
  ssh_peer: state.peer
}
```

Recommended promotion API:

```elixir
Foglet.Sessions.Supervisor.promote_guest_session(
  state.session_pid,
  user,
  audit: %{ssh_peer: Map.get(state.session_context, :ssh_peer)}
)
```

## Validation Architecture

- Quick command: `rtk mix test test/foglet_bbs/ssh/cli_handler_test.exs test/foglet_bbs/sessions/supervisor_test.exs test/foglet_bbs/sessions/session_test.exs`
- Full command: `rtk mix precommit`
- Required focused test areas:
  - `PubkeyStash` stale sweep removes expired entries and preserves fresh entries.
  - `CLIHandler` builds `SessionContext` with peer metadata.
  - `App` calls the supervisor promotion API with audit metadata from `SessionContext`.
  - `Sessions.Supervisor` reports replacement metadata without changing replacement semantics.
  - `Sessions.Session` emits promotion audit metadata and still updates identity/preferences.
  - `CLIHandler` counter returns to zero for normal close, EOF-to-close, lifecycle exit, over-limit reject, rate-limit reject, and crash-during-init paths.
  - Existing forced `replace_then_promote/3` fallback proof remains deterministic.

## Research Confidence

All implementation findings above are HIGH confidence because they are derived from current codebase files, phase context, and project instructions read in this session. No external library or web research was needed for this phase; it uses existing Elixir, Erlang SSH, ETS, Logger, ExUnit, and Raxol integration already present in the repository.
