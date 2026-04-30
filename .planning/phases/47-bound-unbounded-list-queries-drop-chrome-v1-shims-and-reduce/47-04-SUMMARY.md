---
phase: 47-bound-unbounded-list-queries-drop-chrome-v1-shims-and-reduce
plan: 04
subsystem: tui
tags: [refactor, tui, app-shell, helpers, R6]
requires:
  - lib/foglet_bbs/tui/app.ex
  - lib/foglet_bbs/tui/app/routing.ex
  - lib/foglet_bbs/tui/app/modal.ex
  - lib/foglet_bbs/tui/app/effects.ex
provides:
  - lib/foglet_bbs/tui/app/screen_states.ex
  - lib/foglet_bbs/tui/app/session_alias.ex
affects:
  - lib/foglet_bbs/tui/app.ex
  - lib/foglet_bbs/tui/app/routing.ex
tech-stack:
  added: []
  patterns:
    - App-shell helper extraction (Phase 42 App.Routing / App.Modal precedent)
    - Thin one-line delegating callback clauses preserve public boundary
key-files:
  created:
    - lib/foglet_bbs/tui/app/screen_states.ex
    - lib/foglet_bbs/tui/app/session_alias.ex
    - test/foglet_bbs/tui/app/screen_states_test.exs
    - test/foglet_bbs/tui/app/session_alias_test.exs
  modified:
    - lib/foglet_bbs/tui/app.ex
    - lib/foglet_bbs/tui/app/routing.ex
decisions:
  - Kept :screen_state field name singular (D-18 — no rename to :screen_states)
  - Routing.screen_state_for/2 and put_screen_state/3 retained as public delegators that route through ScreenStates (D-19)
  - SessionAlias absorbed :heartbeat_tick (session lifecycle helper) to keep app.ex strictly under 400 lines while staying within D-20's "session aliasing" remit
metrics:
  duration: ~25m
  completed: 2026-04-30
  tasks-completed: 2
  app_ex_lines_before: 483
  app_ex_lines_after: 398
---

# Phase 47 Plan 04: App.ScreenStates and App.SessionAlias Extraction Summary

Extract two responsibilities from `Foglet.TUI.App` into focused, unit-tested
helper modules following the Phase 42 `App.Routing` / `App.Modal` precedent;
reduce `app.ex` below the 400-line budget while preserving the public callback
boundary.

## Tasks Completed

| Task | Name                               | Commits                                       |
| ---- | ---------------------------------- | --------------------------------------------- |
| 1    | Extract App.ScreenStates           | 87edc7be (RED), 65ccd195 (GREEN)              |
| 2    | Extract App.SessionAlias + reduce  | a1a69ef5 (RED), 209125cb (GREEN)              |

## What Was Built

**`Foglet.TUI.App.ScreenStates`** (34 lines, < 100 budget): owns
`get/2`, `put/3`, `update/4`, and `delete/2` over `state.screen_state`. All
helpers are nil-safe — `state.screen_state || %{}` is honored consistently
(matches the prior inline semantic at `routing.ex:46-48`). The `:screen_state`
field itself is unchanged (D-18 — no rename).

**`Foglet.TUI.App.SessionAlias`** (75 lines, < 80 budget): owns
`set_user/2`, `promote_session/2`, `session_replaced/2`, and `heartbeat/1`.
Extracted from the corresponding `do_update` clauses in `app.ex`. App keeps
thin one-line delegating clauses; the public callback boundary is unchanged
and the existing `app_test.exs` cases for these messages pass without
modification.

**Routing migration:** `Routing.screen_state_for/2` and
`Routing.put_screen_state/3` now delegate into `ScreenStates` rather than
inlining `Map.get`/`Map.put`. Routing keeps its public delegators because
internal callers (`init_route_screen_state/3`, `route_screen_update/3`,
`render_local_state/4`) still flow through Routing.

**App moduledoc:** updated to mention the two new helpers and compressed
the state-flow paragraph; verbose per-function `@doc` blocks on the public
delegators were collapsed to single-line `@doc` strings (matching the
existing `modal.ex` / `routing.ex` style and reflecting accurate
"through ScreenStates / Routing" wording after the extractions).

## Verification

- `rtk mix test test/foglet_bbs/tui/app/screen_states_test.exs test/foglet_bbs/tui/app/routing_test.exs` — green (21 tests)
- `rtk mix test test/foglet_bbs/tui/app/session_alias_test.exs test/foglet_bbs/tui/app_test.exs` — green (132 tests)
- `rtk mix test` (full suite) — green (1 property, 2251 tests, 0 failures)
- `rtk mix precommit` — passed (compile w/ warnings-as-errors, formatter, Credo, Sobelow, Dialyzer)

## Acceptance Criteria

- `lib/foglet_bbs/tui/app/screen_states.ex` exists, 34 lines (< 100, D-21) ✓
- `lib/foglet_bbs/tui/app/session_alias.ex` exists, 75 lines (< 80, D-21) ✓
- `lib/foglet_bbs/tui/app.ex` 398 lines (< 400, R6, D-21) ✓
- Dedicated unit tests for both helpers (R6) ✓
- `:screen_state` field preserved (D-18, no rename) ✓
- Public callback boundary on App unchanged — existing `app_test.exs` passes
  unmodified (D-20) ✓
- No inline `Map.put`/`Map.get`/`Map.update` against `screen_state` in
  `app.ex` or `routing.ex` ✓
- `rtk mix precommit` clean ✓

## Deviations from Plan

**1. [Rule 2 — Auto-add missing critical functionality]
SessionAlias absorbed `:heartbeat_tick` to satisfy the dual size budgets**

- **Found during:** Task 2, after the literal D-20 set (`:set_user`,
  `:promote_session`, `:session_replaced`) was extracted, `app.ex` was at
  411 lines — over the < 400 budget required by R6 and D-21.
- **Fix:** Per the plan's audit instruction ("If the count is still >= 400
  after both extractions, audit `app.ex` for any other inline screen_state
  manipulation or session aliasing helpers that were missed and migrate
  them"), moved the `:heartbeat_tick` clause to `SessionAlias.heartbeat/1`.
  `:heartbeat_tick` is a session lifecycle helper (it pings
  `Foglet.Sessions.Session.heartbeat/1` to keep `last_seen_at` alive), so
  it fits inside the "session aliasing" remit. The original
  `Raxol.Core.Runtime.Command` alias was also briefly removed and
  re-added during the audit — the final tree retains it because the
  `:terminate_after_modal` clause still uses `Command.quit()`.
- **Files modified:** `lib/foglet_bbs/tui/app/session_alias.ex`,
  `lib/foglet_bbs/tui/app.ex`
- **Commit:** 209125cb

**2. [Rule 2 — clarification] Compressed `@doc` blocks on public delegators**

- **Found during:** Task 2 sizing audit.
- **Issue:** The pre-existing multi-line `@doc"""…"""` blocks on
  `screen_state_for/2` and `put_screen_state/3` referred to "through the
  routing helper", which became inaccurate after Task 1 routed those
  functions through `ScreenStates`. Other public delegators on App used the
  same verbose 6-line @doc style which differs from the surrounding
  `modal.ex` / `routing.ex` single-line `@doc` style.
- **Fix:** Collapsed all public delegator `@doc` blocks to single-line
  attributes and updated the wording to match the actual delegation target
  (Routing or ScreenStates). The shared section comment above the
  delegators retains the "public boundary for render fixtures" rationale.
- **Files modified:** `lib/foglet_bbs/tui/app.ex`
- **Commit:** 209125cb

## TDD Gate Compliance

Both tasks followed RED → GREEN explicitly:

- 87edc7be — `test(47-04): add failing tests for App.ScreenStates` (9 tests, all failing — `Foglet.TUI.App.ScreenStates` undefined)
- 65ccd195 — `feat(47-04): extract App.ScreenStates helper module` (9/9 → green)
- a1a69ef5 — `test(47-04): add failing tests for App.SessionAlias` (7 tests, all failing — `Foglet.TUI.App.SessionAlias` undefined)
- 209125cb — `feat(47-04): extract App.SessionAlias and reduce app.ex below 400 lines` (7/7 → green; full suite green)

No separate REFACTOR commits were produced because the GREEN commits already
contain the canonical, formatter-compliant shape (the Mix formatter
PostToolUse hook normalized the file after each edit).

## Known Stubs

None.

## Self-Check: PASSED

- `lib/foglet_bbs/tui/app/screen_states.ex` — FOUND
- `lib/foglet_bbs/tui/app/session_alias.ex` — FOUND
- `test/foglet_bbs/tui/app/screen_states_test.exs` — FOUND
- `test/foglet_bbs/tui/app/session_alias_test.exs` — FOUND
- Commit 87edc7be — FOUND
- Commit 65ccd195 — FOUND
- Commit a1a69ef5 — FOUND
- Commit 209125cb — FOUND
