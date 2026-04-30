---
phase: 47-bound-unbounded-list-queries-drop-chrome-v1-shims-and-reduce
plan: 05
subsystem: tui-login
tags: [refactor, tui, login, decomposition]
requires: [Login.State :sub-keyed map shape (D-13)]
provides:
  - Foglet.TUI.Screens.Login.Menu (per-mode reducer)
  - Foglet.TUI.Screens.Login.LoginForm (per-mode reducer + :login task results)
  - Foglet.TUI.Screens.Login.ResetRequest (per-mode reducer + :reset_request task results)
  - Foglet.TUI.Screens.Login.ResetConsume (per-mode reducer + :reset_token task results)
affects:
  - Foglet.TUI.Screens.Login (now thin dispatcher + render glue, ~106 lines)
tech-stack:
  added: []
  patterns:
    - per-mode-reducer-modules (D-14, sibling pattern from Phase 43 PostReader)
    - task-atom-routed task-result dispatch (D-16)
    - one-line case-delegate dispatch in reduce_key/2 (D-15)
key-files:
  created:
    - lib/foglet_bbs/tui/screens/login/menu.ex
    - lib/foglet_bbs/tui/screens/login/login_form.ex
    - lib/foglet_bbs/tui/screens/login/reset_request.ex
    - lib/foglet_bbs/tui/screens/login/reset_consume.ex
  modified:
    - lib/foglet_bbs/tui/screens/login.ex (606 → 106 lines)
    - .dialyzer_ignore.exs (login.ex moved from Bucket C* to Bucket C2; D-17)
    - .planning/codebase/CONCERNS.md (R1-R7 entries marked resolved by Phase 47)
decisions:
  - D-13 preserved: Login.State stays a :sub-keyed map (no struct conversion)
  - D-14 honored: per-mode helpers duplicated rather than introducing a shared internal module
  - D-15 honored: reduce_key/2 is a four-way case with one-line delegates per branch
  - D-16 honored: task-result handlers route by task atom, not by current :sub
  - D-17 honored: did not chase :contract_supertype with speculative @specs; removed login.ex from Bucket C* after the per-mode extraction collapsed the state-shape leak, kept it in Bucket C2 because render/2's Raxol element return still warns identically
metrics:
  duration: ~25min
  completed: 2026-04-30T13:13:51Z
  tasks_completed: 2
  files_created: 4
  files_modified: 3
  tests_passing: 2235/2235
---

# Phase 47 Plan 05: Login Mode-Machine Reducer Decomposition Summary

Decomposed `Foglet.TUI.Screens.Login` from a 606-line multi-mode reducer
into a thin top-level dispatcher (~106 lines) plus four per-mode reducer
modules under `lib/foglet_bbs/tui/screens/login/`, following the Phase 43
PostReader sibling-module pattern. The `:sub`-keyed map state shape was
preserved verbatim (D-13). Closes SPEC R7 and the phase-level cleanup
gate.

## What changed

### Per-mode reducer modules (new)

Each module owns one sub-state's `handle_key/2` plus, where applicable,
a `handle_task_result/3` for the matching task atom (D-16):

| Module                                        | Sub-state         | handle_key/2 | handle_task_result/3 |
| --------------------------------------------- | ----------------- | ------------ | -------------------- |
| `Foglet.TUI.Screens.Login.Menu`               | `:menu`           | yes          | n/a (no task atoms target the menu) |
| `Foglet.TUI.Screens.Login.LoginForm`          | `:login_form`     | yes          | `:login`             |
| `Foglet.TUI.Screens.Login.ResetRequest`       | `:reset_request`  | yes          | `:reset_request`     |
| `Foglet.TUI.Screens.Login.ResetConsume`       | `:reset_consume`  | yes          | `:reset_token`       |

Helpers were moved with their owning sub-state:

- `Menu`: `enter_login_form/1`, `maybe_register/1`,
  `maybe_enter_reset_request/1`, `enter_reset_consume/1`,
  `registration_mode/1`, `session_ctx/1`.
- `LoginForm`: `submit_login/1`, `authenticate_login/5`,
  `login_success_result/3`, `handle_login_result/2` cascade,
  `complete_verify_login/2`, `login_error_modal/3`,
  `unlock_login_form/1`, `focused_input/1`, `update_focused_input/2`.
  Also moved the `app_state_from_local/2`, `local_result/2`, and
  `domain_module/2` helpers needed for the wrap/unwrap inside
  `handle_task_result/3`.
- `ResetRequest`: `submit_reset_request/1`, `email_shape?/1`,
  `dispatch_reset_request/3`, `no_email_operator_message/1`, plus the
  four `@reset_*` copy attributes (`@reset_email_dispatched_message`,
  `@reset_invalid_email_message`, `@reset_no_email_intro`,
  `@reset_no_email_no_sysops_fallback`).
- `ResetConsume`: `submit_reset_consume/1`, `focused_input/1`,
  `update_focused_input/2`, plus the three reset-consume copy
  attributes (`@reset_consume_invalid_or_expired_message`,
  `@reset_consume_password_mismatch_message`,
  `@reset_consume_password_invalid_message`).

Per the plan's D-14 guidance, helpers used in multiple modes
(`focused_input/1`, `update_focused_input/2`, `domain_module/2`,
`default_domain_module/1`) were duplicated rather than introducing a
shared internal helper module. Each duplication site is a small
self-contained block; this matches the Phase 43 sub-100-line-module
style and avoids the circular-alias risk of having sub-modules call back
into the parent.

### Top-level dispatcher (refactored)

`lib/foglet_bbs/tui/screens/login.ex` is now 106 lines. It contains:

- The four `update/3` clauses (Ctrl+C quit, key dispatch, three
  task-atom delegates, catch-all).
- `reduce_key/2`: a four-way `case LoginState.sub(state)` with one-line
  delegates (D-15).
- `app_state_from_local/2` and `local_result/2`: app-state wrap/unwrap
  glue used by the key-dispatch path. The `:no_match` and `{:update, …}`
  shapes are exhaustive after the refactor; the previous `{state, [eff]}`
  fall-through was dead code from the pre-refactor flow where
  `handle_login_result/2` returned that shape directly through
  `reduce_key/2`. Dialyzer flagged it as unreachable; it was removed.

### Dialyzer ignore (D-17)

`.dialyzer_ignore.exs`:

- **Removed `login.ex` from Bucket C*** (state-shape `:contract_supertype`):
  the multi-shape map warning that motivated the entry collapsed naturally
  after the per-mode extraction split the union-of-shapes traffic to
  per-mode boundaries.
- **Re-added `login.ex` under Bucket C2** with refreshed Phase 47
  rationale: `render/2`'s Raxol element return still triggers
  `:contract_supertype` identically to the other Bucket C2 entries. Per
  D-17 we did not chase the entry by adding speculative `@spec`s.

`Login.State` keeps its Bucket C* entry — `LoginState.get/put` still
operate on the union of sub-state map shapes by design (D-13 explicitly
preserves the `:sub`-keyed map; tagged-union conversion is out of scope).

## Acceptance criteria status (SPEC R7)

| Criterion                                                                                       | Status |
| ----------------------------------------------------------------------------------------------- | ------ |
| Four per-mode reducer modules exist under `lib/foglet_bbs/tui/screens/login/`                   | met    |
| `Login.State` preserves `:sub`-keyed map shape (no `defstruct`)                                 | met    |
| `lib/foglet_bbs/tui/screens/login.ex` < 300 lines                                               | met (106) |
| `reduce_key/2` four-way dispatch is one-line delegators (D-15)                                  | met    |
| Task-result handlers route by task atom, not by `:sub` (D-16)                                   | met    |
| `mix dialyzer` green; if `:contract_supertype` ignore remains, rationale cites Phase 47 (D-17)  | met    |
| Existing login screen tests pass without modification                                           | met (80/80) |
| `.planning/codebase/CONCERNS.md` reflects resolved tech-debt entries                            | met (R1-R7) |
| `mix precommit` green (compile, formatter, Credo, Sobelow, Dialyzer)                            | met    |
| Full test suite green                                                                            | met (2235/2235) |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed dead `local_result/2` clause flagged by dialyzer**

- **Found during:** Task 2 verification (`mix dialyzer`)
- **Issue:** After the per-mode extraction, the `local_result({state, effects}, _)`
  clause in `login.ex` became unreachable. Dialyzer reported
  `pattern_match` because `reduce_key/2` now only emits `:no_match` or
  `{:update, _, _}` (the `{state, effects}` shape was used by the
  pre-refactor `handle_login_result/2` flow that ran inside
  `reduce_key/2`; that flow is now contained in `LoginForm.handle_task_result/3`
  which feeds `update/3` directly without going through `local_result/2`).
- **Fix:** Removed the dead clause; the remaining `:no_match` and
  `{:update, _, _}` clauses are now exhaustive over the actual return
  shapes.
- **Files modified:** `lib/foglet_bbs/tui/screens/login.ex`
- **Commit:** `5b056577`

### Architectural Adjustments

**1. Removed unused `Foglet.Config` alias from login.ex**

- **Found during:** Task 1 verification (`mix compile`)
- **Issue:** After moving `registration_mode/1` (the only consumer of
  `Foglet.Config` via `Config.get/2`) into `Login.Menu`, `Foglet.Config`
  was no longer aliased in `login.ex`. The `dispatch_reset_request/3`
  helper that *was* still in `login.ex` during Task 1 used the
  fully-qualified `Foglet.Config.delivery_mode()` call, so the alias
  wasn't actually consumed.
- **Fix:** Removed `Config` from `alias Foglet.{Accounts, Config}` →
  `alias Foglet.Accounts`. Resolved the `unused alias Config` warning
  for the warnings-as-errors gate.
- **Note:** This is bookkeeping, not a behavior change. Foglet.Config
  itself is still used (under its full module name) by ResetRequest in
  Task 2.

## CONCERNS.md updates (phase cleanup gate)

The following five tech-debt entries from `.planning/codebase/CONCERNS.md`
were annotated with Phase 47 dispositions:

| Entry                                                              | Disposition            | Phase 47 plan |
| ------------------------------------------------------------------ | ---------------------- | ------------- |
| `Foglet.Posts.list_posts/1` still loads every post in a thread     | Resolved (R1)          | 01            |
| `Foglet.Threads.list_threads/2` runs per-thread aggregation join   | Resolved (R3, R4)      | 02            |
| Legacy Chrome V1 / flat-key-hint compatibility shims               | Resolved (R5)          | 03            |
| `Foglet.TUI.App` is still 483 lines                                | Reduced (R6)           | 04            |
| Several screen modules remain large (`login.ex` 606 lines)         | Resolved for login (R7) | 05            |

Original issue text was retained as historical context; each entry now
leads with a `Disposition:` line pointing to the resolving plan's
SUMMARY.

## Self-Check: PASSED

- `lib/foglet_bbs/tui/screens/login/menu.ex` — FOUND
- `lib/foglet_bbs/tui/screens/login/login_form.ex` — FOUND
- `lib/foglet_bbs/tui/screens/login/reset_request.ex` — FOUND
- `lib/foglet_bbs/tui/screens/login/reset_consume.ex` — FOUND
- `lib/foglet_bbs/tui/screens/login.ex` — FOUND (106 lines)
- `.dialyzer_ignore.exs` — FOUND (login.ex moved to Bucket C2)
- `.planning/codebase/CONCERNS.md` — FOUND (R1-R7 dispositions added)
- Commit `b0c30ff6` (Task 1) — FOUND
- Commit `5b056577` (Task 2) — FOUND
- `mix test` — 2235/2235 pass
- `mix precommit` — green
