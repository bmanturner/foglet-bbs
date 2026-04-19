---
phase: 03-ssh-server-tui
plan: "05"
subsystem: ui
tags: [raxol, tui, ssh, screens, layout, registration]

# Dependency graph
requires:
  - phase: 03-ssh-server-tui
    provides: TUI screens with KeyBar and StatusBar widgets, login/register flow
provides:
  - spacer(flex: 1) before KeyBar in all 9 TUI screen render functions (KeyBar pinned to bottom)
  - main_menu.ex without duplicate bold title (StatusBar already renders it)
  - login.ex maybe_register/1 with fully initialised register_wizard (5 keys)
  - register.ex render/1 no longer crashes with KeyError on w.error
affects: [03-06-ssh-server-tui, 04-presence-login-sequence, UAT]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "spacer(flex: 1) as penultimate element in outer column list pushes KeyBar to terminal bottom"
    - "first_step_for_mode/1 private helper in login.ex mirrors Register.first_step_for/1 (private cross-module duplication is intentional)"

key-files:
  created: []
  modified:
    - lib/foglet_bbs/tui/screens/main_menu.ex
    - lib/foglet_bbs/tui/screens/login.ex
    - lib/foglet_bbs/tui/screens/register.ex
    - lib/foglet_bbs/tui/screens/verify.ex
    - lib/foglet_bbs/tui/screens/board_list.ex
    - lib/foglet_bbs/tui/screens/thread_list.ex
    - lib/foglet_bbs/tui/screens/post_reader.ex
    - lib/foglet_bbs/tui/screens/post_composer.ex
    - lib/foglet_bbs/tui/screens/new_thread.ex

key-decisions:
  - "Duplicate first_step_for_mode/1 in login.ex rather than calling the private Register.first_step_for/1 cross-module — avoids coupling to a private API"
  - "spacer(flex: 1) inserted as second-to-last element in outer column, immediately before KeyBar — consistent pattern across all screens"

patterns-established:
  - "All TUI screen outer column lists: [...content..., spacer(flex: 1), KeyBar.render(...)]"

requirements-completed: [SSH-04, SSH-07]

# Metrics
duration: 5min
completed: 2026-04-19
---

# Phase 03 Plan 05: UAT Gap Closure (KeyBar Layout + Registration Crash Fix) Summary

**spacer(flex: 1) added to all 9 screen render functions to pin KeyBar to terminal bottom; duplicate title removed from main_menu; register_wizard initialised with all 5 required keys to fix registration crash**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-04-19T16:03:00Z
- **Completed:** 2026-04-19T16:08:06Z
- **Tasks:** 2
- **Files modified:** 9

## Accomplishments
- All 9 TUI screen render functions now include `spacer(flex: 1)` before `KeyBar.render(...)`, pinning the KeyBar to the terminal bottom (UAT gap 1 fixed)
- Removed redundant `text(" Foglet BBS ", style: [:bold])` and `divider()` from `main_menu.ex` render — StatusBar already renders the full title (UAT gap 2 fixed)
- Fixed `maybe_register/1` in `login.ex` to initialise `register_wizard` with all 5 required keys: `mode`, `step` (valid atom via `first_step_for_mode/1`), `data: %{}`, `error: nil`, `current_input: ""` — preventing KeyError crash in `Register.render/1` (UAT gap 3 / blocker fixed)
- Full TUI test suite: 207 tests, 0 failures

## Task Commits

Each task was committed atomically:

1. **Task 1: Remove duplicate title from main_menu and add spacer to all screens** - `f7a1986` (fix)
2. **Task 2: Fix register_wizard initialisation in login.ex maybe_register/1** - `8633e72` (fix)

**Worktree cleanup:** `be5e59f` (chore: restore files accidentally deleted by worktree reset)

## Files Created/Modified
- `lib/foglet_bbs/tui/screens/main_menu.ex` - Removed redundant title/divider; added spacer before KeyBar
- `lib/foglet_bbs/tui/screens/login.ex` - Added spacer before KeyBar; fixed maybe_register/1 wizard init; added first_step_for_mode/1
- `lib/foglet_bbs/tui/screens/register.ex` - Added spacer before KeyBar
- `lib/foglet_bbs/tui/screens/verify.ex` - Added spacer before KeyBar
- `lib/foglet_bbs/tui/screens/board_list.ex` - Added spacer before KeyBar
- `lib/foglet_bbs/tui/screens/thread_list.ex` - Added spacer before KeyBar
- `lib/foglet_bbs/tui/screens/post_reader.ex` - Added spacer before KeyBar
- `lib/foglet_bbs/tui/screens/post_composer.ex` - Added spacer before KeyBar
- `lib/foglet_bbs/tui/screens/new_thread.ex` - Added spacer before KeyBar in both render_board_step/2 and render_compose_step/2

## Decisions Made
- Duplicated `first_step_for_mode/1` logic in `login.ex` rather than calling the private `Register.first_step_for/1` cross-module. This avoids coupling to a private function in another module.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Restored files accidentally deleted by worktree reset**
- **Found during:** Task 1 commit
- **Issue:** `git reset --soft` to target base brought in a staged index that included deletions of files present in main branch but absent from the worktree filesystem (03-05-PLAN.md, 03-06-PLAN.md, 03-UAT.md, tui/input.ex, config.ex, ROADMAP.md)
- **Fix:** Restored all files from the target commit (`git show 9202427:<file>`) and committed them in a separate chore commit (be5e59f)
- **Files modified:** .planning/phases/03-ssh-server-tui/03-05-PLAN.md, 03-06-PLAN.md, 03-UAT.md, lib/foglet_bbs/tui/input.ex, lib/foglet_bbs/config.ex, .planning/ROADMAP.md
- **Verification:** All files present in working tree after restoration
- **Committed in:** be5e59f (chore commit between Task 1 and Task 2)

---

**Total deviations:** 1 auto-fixed (1 blocking — worktree state issue)
**Impact on plan:** Worktree reset issue only; no plan scope change.

## Issues Encountered
- `git reset --soft` from old HEAD (c53dac0) to target (9202427) caused staged deletions of files that existed in main branch commits but were never checked out in the worktree. Resolved by restoring all affected files from the target commit.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- UAT gaps 1, 2, and 3 are fixed; registration flow is now functional
- UAT tests 2 (login→register navigation), 3 (registration form renders), 4 (spacer layout), and 6 (no duplicate title) should now pass
- Plan 06 (modal intercept guard, command_result dispatcher, SSH resize fix) can run in parallel — no dependencies on plan 05 outputs

## Self-Check

Files exist:
- `lib/foglet_bbs/tui/screens/main_menu.ex` — FOUND
- `lib/foglet_bbs/tui/screens/login.ex` — FOUND
- `lib/foglet_bbs/tui/screens/register.ex` — FOUND

Commits exist:
- f7a1986 — Task 1 (spacer + title removal)
- be5e59f — Worktree file restoration
- 8633e72 — Task 2 (register_wizard fix)

## Self-Check: PASSED

---
*Phase: 03-ssh-server-tui*
*Completed: 2026-04-19*
