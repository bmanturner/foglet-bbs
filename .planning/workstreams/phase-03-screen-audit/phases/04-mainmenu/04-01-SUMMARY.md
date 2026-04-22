---
phase: 04-mainmenu
plan: 01
subsystem: ui
tags: [elixir, tui, main-menu, audit]
requires:
  - phase: 00-cross-cutting-extractions-prelude
    provides: Theme.from_state/1 helper used by MainMenu render
provides:
  - Explicit MainMenu statelessness documentation and reserved-whitespace guardrails
  - Separate @menu_items and @menu_keys attributes wired into render/4
  - Focused MainMenu-owned route/render tests with no ScreenFrame-internal assertions
affects: [mainmenu, screen-audit, phase-05-boardlist]
tech-stack:
  added: []
  patterns: [intentional-stateless-screen-docs, audit-gate-driven-sparseness]
key-files:
  created: []
  modified:
    - lib/foglet_bbs/tui/screens/main_menu.ex
    - test/foglet_bbs/tui/screens/main_menu_test.exs
key-decisions:
  - "MainMenu remains intentionally stateless with no init_screen_state/1."
  - "@menu_items and @menu_keys remain intentionally duplicated for separate render vs KeyBar contracts."
patterns-established:
  - "Stateless screen deviation is documented in moduledoc instead of adding default screen_state."
  - "MainMenu tests assert only screen-owned behavior, not ScreenFrame chrome internals."
requirements-completed: [MENU-01, MENU-02, MENU-03, MENU-04, MENU-05]
duration: 4 min
completed: 2026-04-21
---

# Phase 04 Plan 01: MainMenu Summary

**MainMenu is now explicitly stateless and sparse by contract while preserving existing routes, visible strings, and KeyBar behavior.**

## Performance

- **Duration:** 4 min
- **Started:** 2026-04-21T20:54:10Z
- **Completed:** 2026-04-21T20:58:34Z
- **Tasks:** 3
- **Files modified:** 2

## Accomplishments
- Expanded `MainMenu` moduledoc to explicitly document intentional statelessness, reserved whitespace, and load-bearing data duplication.
- Added `@default_terminal_size` and `@menu_keys`, and wired `ScreenFrame.render/4` to `@menu_keys` while preserving plain `text/2` menu rows from `@menu_items`.
- Reworked `main_menu_test.exs` to lock MainMenu-owned behavior (`B/b`, `C/c`, `Q/q`, `:no_match`, rendered strings, no `init_screen_state/1`) and removed ScreenFrame-internal layout assertions.
- Ran full rubric gates, focused tests, and `mix precommit` successfully.

## Task Commits

1. **Task 1: Make main_menu.ex explicit and rubric-compliant** - `b04d274` (feat)
2. **Task 2: Tighten MainMenu tests around screen-owned behavior** - `1fc317d` (test)
3. **Task 3: Run rubric gates and full precommit** - `c81d9e6` (fix)

## Files Created/Modified
- `lib/foglet_bbs/tui/screens/main_menu.ex` - moduledoc contract, `@default_terminal_size`, `@menu_keys`, and compose fallback cleanup.
- `test/foglet_bbs/tui/screens/main_menu_test.exs` - MainMenu-owned behavior assertions and render-string checks.

## Decisions Made
- Retained MainMenu’s intentional statelessness deviation (no `screen_state[:main_menu]`, no `init_screen_state/1`) and documented it directly in the moduledoc.
- Kept `@menu_items` + `@menu_keys` as separate load-bearing data shapes rather than DRY consolidation.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] MainMenu line-count gate initially exceeded threshold**
- **Found during:** Task 3 (Run rubric gates and full precommit)
- **Issue:** `wc -l lib/foglet_bbs/tui/screens/main_menu.ex` returned 73, exceeding the plan’s `<= 70` gate.
- **Fix:** Compressed moduledoc blank spacing without changing required wording or behavior.
- **Files modified:** `lib/foglet_bbs/tui/screens/main_menu.ex`
- **Verification:** `wc -l` now returns 70; focused tests and `mix precommit` pass.
- **Committed in:** `c81d9e6`

---

**Total deviations:** 1 auto-fixed (Rule 1 bug)
**Impact on plan:** No scope creep; fix was strictly required to satisfy explicit acceptance criteria.

## Known Stubs

None.

## Issues Encountered

- Local sandbox intermittently blocked Mix PubSub socket startup for some Mix commands; reran validation commands with escalated permissions and completed all gates successfully.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- MainMenu audit goals are complete and verified (`MENU-01..05`).
- Phase 04 is ready to proceed to subsequent screen audit phases in this workstream.

## Self-Check: PASSED

- Verified summary file exists.
- Verified task commits exist: `b04d274`, `1fc317d`, `c81d9e6`.
