---
phase: 41-tui-contract-and-modal-effects
plan: 41-01
subsystem: tui
tags: [elixir, raxol, tui, screen-contract]

requires:
  - phase: 40
    provides: screen-owned TUI reducers with bounded legacy callback compatibility
provides:
  - canonical Foglet.TUI.Screen behavior callbacks only
  - production screen cleanup removing public legacy callback helpers
  - compile and precommit verification for the contract cleanup
affects: [tui-screen-contract, modal-effects, screen-tests]

tech-stack:
  added: []
  patterns:
    - canonical screen callbacks init/1, update/3, render/2, subscriptions/2
    - explicit State.new/1 constructors for direct state setup

key-files:
  created:
    - .planning/phases/41-tui-contract-and-modal-effects/41-01-SUMMARY.md
  modified:
    - lib/foglet_bbs/tui/screen.ex
    - lib/foglet_bbs/tui/screens/post_reader.ex
    - lib/foglet_bbs/tui/screens/post_composer.ex
    - lib/foglet_bbs/tui/screens/new_thread.ex
    - lib/foglet_bbs/tui/screens/board_list.ex
    - lib/foglet_bbs/tui/screens/thread_list.ex
    - lib/foglet_bbs/tui/screens/account.ex
    - lib/foglet_bbs/tui/screens/sysop.ex
    - lib/foglet_bbs/tui/screens/moderation.ex
    - lib/foglet_bbs/tui/screens/login.ex
    - lib/foglet_bbs/tui/screens/register.ex
    - lib/foglet_bbs/tui/screens/verify.ex

key-decisions:
  - "Removed the public compatibility behavior instead of preserving old callback declarations."
  - "Kept reusable direct setup on existing State modules rather than screen-level init_screen_state/1 helpers."

patterns-established:
  - "Production screens expose the canonical Foglet.TUI.Screen reducer/render contract only."
  - "Old App-state render/key wrappers are deleted instead of being kept as public shims."

requirements-completed: [TUI-01]

duration: 15min
completed: 2026-04-29
---

# Phase 41 Plan 41-01: TUI Screen Contract Cleanup Summary

**Canonical TUI screen behavior with legacy public render/key/init helpers removed from production screens**

## Performance

- **Duration:** 15 min
- **Started:** 2026-04-29T17:51:09Z
- **Completed:** 2026-04-29T18:05:44Z
- **Tasks:** 3
- **Files modified:** 12 source files, 1 summary

## Accomplishments

- Reduced `Foglet.TUI.Screen` to `init/1`, `update/3`, `render/2`, and optional `subscriptions/2`.
- Removed public old-callback helpers from content/navigation screens and account/sysop/moderation/auth screens.
- Replaced leftover screen setup fallbacks with existing state constructors such as `State.new/1` and auth state defaults.
- Verified the cleanup with greps, `rtk mix compile --warnings-as-errors`, and `rtk mix precommit`.

## Task Commits

1. **Task 41-01-01: Screen behavior contract** - `29e4bc6c` (`refactor`)
2. **Task 41-01-02: Content/navigation screen helpers** - `e108a73e` (`refactor`)
3. **Task 41-01-03: Workspace/auth screen helpers** - `3873f1bd` (`refactor`)
4. **Task 41-01-03 formatter follow-up** - `941f352e` (`style`)

## Files Created/Modified

- `lib/foglet_bbs/tui/screen.ex` - Removed legacy callback types, callback declarations, optional callbacks, and compatibility docs.
- `lib/foglet_bbs/tui/screens/post_reader.ex` - Removed public `render/1`, `handle_key/2`, and `init_screen_state/1` compatibility API.
- `lib/foglet_bbs/tui/screens/post_composer.ex` - Removed public legacy render/key/init helpers and stale private App-state paths.
- `lib/foglet_bbs/tui/screens/new_thread.ex` - Removed public legacy render/key/init helpers and stale private App-state paths.
- `lib/foglet_bbs/tui/screens/board_list.ex` - Removed public `init_screen_state/1`.
- `lib/foglet_bbs/tui/screens/thread_list.ex` - Removed public `init_screen_state/1`.
- `lib/foglet_bbs/tui/screens/account.ex` - Removed public old init/render/key helpers and kept rendering through private app-state model plumbing.
- `lib/foglet_bbs/tui/screens/sysop.ex` - Removed public old init/render/key helpers and stale App-state key delegation helpers.
- `lib/foglet_bbs/tui/screens/moderation.ex` - Removed public old init/render/key helpers and stale App-state key delegation helpers.
- `lib/foglet_bbs/tui/screens/login.ex` - Removed public `init_screen_state/1`.
- `lib/foglet_bbs/tui/screens/register.ex` - Removed public `init_screen_state/1` and renamed private fallback setup.
- `lib/foglet_bbs/tui/screens/verify.ex` - Removed public `init_screen_state/1`.

## Decisions Made

- Followed the plan's hard cleanup path: production screen modules no longer keep public helpers named like the old callbacks.
- Left non-screen helper modules with their own `handle_key/2` or `render/2` APIs intact because they are widget/subview contracts, not `Foglet.TUI.Screen` compatibility callbacks.

## Deviations from Plan

None - plan scope was executed as written.

## Issues Encountered

- `rtk mix compile --warnings-as-errors` could not pass between task 2 and task 3 because removing callbacks from `Foglet.TUI.Screen` made the still-planned task-3 helpers emit `@impl` warnings. The final task removed those helpers and compile passed.
- `rtk mix precommit` formatted one trailing blank line in `moderation.ex`, captured in `941f352e`. Formatter churn in unrelated `test/foglet_bbs/tui/app_test.exs` was reverted because it was outside plan 41-01.

## Verification

- `rtk rg -n "@callback (render\\(state|handle_key|init_screen_state)|render: 1|handle_key: 2|init_screen_state: 1|Bounded compatibility" lib/foglet_bbs/tui/screen.ex` returned no matches.
- `rtk rg -n "def (handle_key|init_screen_state)\\(|def render\\(state\\)|init_screen_state|legacy render/1|legacy handle_key|compatibility" lib/foglet_bbs/tui/screens/...target production screens...` returned no matches.
- `rtk rg -n "@callback (init|update|render|subscriptions)" lib/foglet_bbs/tui/screen.ex` shows only the canonical callbacks.
- `rtk mix compile --warnings-as-errors` passed.
- `rtk mix precommit` passed.

## Known Stubs

None introduced by this plan. Stub-scan hits were pre-existing content strings/comments such as loading/empty-state checks, placeholder text for input widgets, and defensive "not available" authorization copy.

## Threat Flags

None - no new network endpoints, auth paths, file access patterns, persistence surfaces, or trust-boundary schema changes.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Phase 41 can continue to modal submit effect cleanup with production screens no longer exposing the legacy screen compatibility contract.

## Self-Check: PASSED

- Summary file exists: `.planning/phases/41-tui-contract-and-modal-effects/41-01-SUMMARY.md`.
- Task commits found in git history: `29e4bc6c`, `e108a73e`, `3873f1bd`, `941f352e`.
- Shared state files were not updated by this executor; pre-existing `.planning/STATE.md` and `AGENTS.md` worktree changes remain unstaged.

---
*Phase: 41-tui-contract-and-modal-effects*
*Completed: 2026-04-29*
