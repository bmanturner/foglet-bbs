---
phase: 45
plan: 45-02
subsystem: ssh-sessions
tags: [ssh, sessions, audit, promotion]
requires: []
provides: [audit-aware-guest-promotion, ssh-peer-in-session-context]
affects:
  - lib/foglet_bbs/tui/session_context.ex
  - lib/foglet_bbs/ssh/cli_handler.ex
  - lib/foglet_bbs/tui/app.ex
  - lib/foglet_bbs/sessions/supervisor.ex
  - lib/foglet_bbs/sessions/session.ex
tech_stack:
  added: []
  patterns:
    - structured-keyword-list-logger-metadata
    - compatibility-wrapper-for-arity-extension
key_files:
  created: []
  modified:
    - lib/foglet_bbs/tui/session_context.ex
    - lib/foglet_bbs/ssh/cli_handler.ex
    - lib/foglet_bbs/tui/app.ex
    - lib/foglet_bbs/sessions/supervisor.ex
    - lib/foglet_bbs/sessions/session.ex
    - test/foglet_bbs/ssh/cli_handler_test.exs
    - test/foglet_bbs/sessions/supervisor_test.exs
    - test/foglet_bbs/sessions/session_test.exs
decisions:
  - SSH peer descriptor flows from CLIHandler -> SessionContext -> App -> Supervisor.promote_guest_session/3 audit map.
  - Replacement context is computed in Sessions.Supervisor at the Registry-lookup boundary, then merged into the audit map before the Session cast (preserves D-06 invariant).
  - Promotion log line uses Logger keyword metadata (event: :guest_promoted, ssh_peer:, replacement:, ...) rather than string templating so log aggregators can filter on structured fields.
  - 2-arg promote_guest_session/promote_to_user kept as compatibility wrappers to avoid touching unrelated callers in this plan.
metrics:
  duration: ~25 min
  completed: 2026-04-29
---

# Phase 45 Plan 45-02: Promotion Audit + Peer Context Summary

Plumbs the SSH peer descriptor from `Foglet.SSH.CLIHandler` into the TUI
`SessionContext` and threads it (alongside replacement context) through a new
audit-aware `promote_guest_session/3` / `promote_to_user/3` API so that
guest-to-user promotions emit structured operator-grade audit logs (SSH-02 /
D-04 / D-05) without disturbing the existing one-session-per-user replacement
or forced-termination fallback (D-06, D-13, D-14).

## What Changed

### Task 45-02-01 — `feat(45-02): carry SSH peer into TUI session context` (8a5df3ad)

- Added `ssh_peer: term() | nil` to `Foglet.TUI.SessionContext` (struct,
  typespec, and field doc).
- Populated it in `Foglet.SSH.CLIHandler.build_context/3` from the peer that
  was already captured at `:ssh_channel_up` time.
- Updated the existing context-shape tests in
  `test/foglet_bbs/ssh/cli_handler_test.exs` to construct the field
  explicitly (one nil, one `{{127, 0, 0, 1}, 2222}`).

### Task 45-02-02 — `feat(45-02): structured guest-promotion audit metadata` (f785a29b)

- Added `Foglet.Sessions.Supervisor.promote_guest_session/3` taking `opts`
  with `:audit`. It computes the replacement context at the Registry
  lookup boundary (`:none`, `:same_session`, or `{:replaced, old_pid}`)
  and merges it into the audit map before delegating to the Session.
  The 2-arg version is now a compatibility wrapper.
- Added `Foglet.Sessions.Session.promote_to_user/3` and a matching
  `handle_cast({:promote_to_user, user, audit}, state)` clause that emits
  `Logger.info("Session guest promoted", ...)` with structured metadata
  (`event: :guest_promoted`, `session_pid:`, `user_id:`, `handle:`,
  `ssh_peer:`, `replacement:`). The 2-arg version is now a wrapper.
- Updated `Foglet.TUI.App.do_update({:promote_session, user}, state)` to
  call the 3-arg supervisor with `audit: %{ssh_peer: ...}` pulled from
  `state.session_context`.
- Tests:
  - Added `promote_guest_session/3 accepts audit metadata and promotes the
    guest` to `supervisor_test.exs`.
  - Added `promote_to_user/3 accepts audit metadata and reaches the same
    user state` to `session_test.exs`.
  - Preserved the existing forced-termination fallback test
    (`promote_guest_session/2 force-terminates a session that does not
    stop gracefully`) untouched — `replace_then_promote/4` still
    runs through the supervisor under the same monitor / Registry
    assertions.

## Verification

- `rtk mix test test/foglet_bbs/ssh/cli_handler_test.exs
  test/foglet_bbs/sessions/supervisor_test.exs
  test/foglet_bbs/sessions/session_test.exs` — 44 tests, 0 failures.
- `rtk mix compile --warnings-as-errors` — clean for `foglet_bbs`
  (residual warnings come from the vendored `raxol` tree and are out of
  scope for this plan).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Sequencing] Deferred App.ex audit-aware call to Task 2 commit**
- **Found during:** Task 1
- **Issue:** Task 45-02-01's action list told us to update
  `App.do_update({:promote_session, user}, state)` to call
  `Foglet.Sessions.Supervisor.promote_guest_session/3`, but the 3-arg
  arity is only introduced in Task 45-02-02. Committing the App.ex change
  in Task 1 would have left the build broken between commits.
- **Fix:** Moved the App.ex edit into the Task 2 commit so each commit
  compiles independently. Task 1 still added the field, populated it in
  CLIHandler, and updated the cli_handler tests — its acceptance still
  ran cleanly.
- **Files modified:** `lib/foglet_bbs/tui/app.ex` (now in commit
  `f785a29b` instead of `8a5df3ad`).
- **Commit:** `f785a29b`

### Acceptance Criterion Pattern Note (not a code change)

Task 45-02-01's acceptance criterion `rg -n
"promote_guest_session\(state\.session_pid, user, audit:"
lib/foglet_bbs/tui/app.ex` does not match because the call is wrapped
across two lines by the formatter:

```elixir
Foglet.Sessions.Supervisor.promote_guest_session(state.session_pid, user,
  audit: %{ssh_peer: Map.get(state.session_context, :ssh_peer)}
)
```

A multi-line pattern (`rg -nU`) or a relaxed single-line pattern
(`rg "promote_guest_session\(state\.session_pid, user,"`) confirms the
audited call is present. Functionally the criterion is satisfied.

## Threat Model Mitigations

- **T-45-03 (medium):** Mitigated. `ssh_peer` is now part of
  `SessionContext` and is forwarded by `App` into the supervisor's audit
  map, so the promotion log line carries peer context whenever the SSH
  channel had one.
- **T-45-04 (high):** Mitigated. Replacement decisions still live in
  `Sessions.Supervisor`; audit metadata is appended only after the
  Registry lookup determines `replacement:`. The
  `replace_then_promote/4` path keeps its monitor/`:DOWN` ordering
  intact.
- **T-45-05 (medium):** Mitigated. New tests assert state and Registry
  behaviour directly (Session state fields, `Registry.lookup`) rather
  than matching log strings, so the audit boundary stays test-friendly
  without making tests brittle.

## Self-Check: PASSED

- File `lib/foglet_bbs/tui/session_context.ex` exists.
- File `lib/foglet_bbs/ssh/cli_handler.ex` exists.
- File `lib/foglet_bbs/tui/app.ex` exists.
- File `lib/foglet_bbs/sessions/supervisor.ex` exists.
- File `lib/foglet_bbs/sessions/session.ex` exists.
- File `test/foglet_bbs/ssh/cli_handler_test.exs` exists.
- File `test/foglet_bbs/sessions/supervisor_test.exs` exists.
- File `test/foglet_bbs/sessions/session_test.exs` exists.
- Commit `8a5df3ad` (Task 45-02-01) present in git log.
- Commit `f785a29b` (Task 45-02-02) present in git log.
