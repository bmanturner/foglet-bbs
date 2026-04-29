---
phase: 40-verification-documentation
plan: 02
subsystem: tui
tags: [tui, raxol, screen-contract, app-runtime, verification]
requires:
  - phase: 40-verification-documentation
    provides: "Plan 40-01 deferred cleanup foundation and Phase 39 screen reducer migration context"
provides:
  - "App key/render dispatch through update/3 and render/2 without production legacy fallback"
  - "Render fixtures and migrated post/composer/thread tests using reducer/render contract helpers"
  - "Screen behavior docs marking broad App-state callbacks as bounded compatibility only"
affects: [phase-40, tui-runtime, screen-migration, verification]
tech-stack:
  added: []
  patterns:
    - "Screen tests drive local state through init/1, update/3, and render/2 helpers"
    - "App no-ops missing update/3 only for override screens by guarding route_screen_update/3"
key-files:
  created:
    - ".planning/phases/40-verification-documentation/40-02-SUMMARY.md"
  modified:
    - "lib/foglet_bbs/tui/app.ex"
    - "lib/foglet_bbs/tui/screen.ex"
    - "lib/foglet_bbs/tui/render_fixtures.ex"
    - "test/foglet_bbs/tui/app_runtime_contract_test.exs"
    - "test/foglet_bbs/tui/screens/post_reader_test.exs"
    - "test/foglet_bbs/tui/screens/post_composer_test.exs"
    - "test/foglet_bbs/tui/screens/new_thread_test.exs"
key-decisions:
  - "Keep compatibility callback declarations bounded in Foglet.TUI.Screen so existing modules with @impl annotations continue compiling while App production dispatch ignores them."
  - "Use test-local reducer adapters to preserve behavior assertions while removing direct calls to legacy screen callbacks."
patterns-established:
  - "App key dispatch routes to route_screen_update/3 and relies on screen update/3 effects."
  - "Render fixtures build context with App.build_context/1 and seed local state through screen init/1."
requirements-completed: [VERIFY-02, VERIFY-03]
duration: 14min
completed: 2026-04-29
---

# Phase 40 Plan 02: Legacy Screen Callback Boundary Summary

**Production TUI screen dispatch now routes through init/update/render, with broad App-state callbacks bounded to compatibility helpers only.**

## Performance

- **Duration:** 14 min
- **Started:** 2026-04-29T15:09:14Z
- **Completed:** 2026-04-29T15:23:02Z
- **Tasks:** 3
- **Files modified:** 7 implementation/test files

## Accomplishments

- Moved render fixtures for Login, Register, Verify, Account, Moderation, and Sysop from `init_screen_state/1` to `App.build_context/1` plus `Screen.init/1`.
- Migrated PostReader, PostComposer, and NewThread tests onto local reducer/render helpers instead of direct legacy `render/1` and `handle_key/2` calls.
- Removed App production fallback dispatch to screen `handle_key/2`, `render/1`, and the legacy `process_screen_commands/2` adapter.
- Updated `Foglet.TUI.Screen` docs so `init/1`, `update/3`, `render/2`, and optional `subscriptions/2` are canonical; remaining broad callbacks are explicitly bounded compatibility surface.

## Task Commits

1. **Task 1: Move fixtures and tests to new contract seams** - `7b3aefc` (test)
2. **Task 2: Remove App production fallback dispatch** - `6da5109` (feat)
3. **Task 3: Update Screen behaviour docs and optional callbacks** - `7c2f473` (docs)

## Files Created/Modified

- `lib/foglet_bbs/tui/app.ex` - Removed production fallback dispatch and retained guarded no-op behavior for override screens without `update/3`.
- `lib/foglet_bbs/tui/screen.ex` - Reframed behavior docs around canonical screen callbacks and bounded compatibility callbacks.
- `lib/foglet_bbs/tui/render_fixtures.ex` - Seeds migrated screen fixture state through `Screen.init/1` and `App.build_context/1`.
- `test/foglet_bbs/tui/app_runtime_contract_test.exs` - Added runtime proof for new-contract key/render dispatch and update-less override no-op.
- `test/foglet_bbs/tui/screens/post_reader_test.exs` - Added reducer/render test adapters and removed direct legacy callback dependence.
- `test/foglet_bbs/tui/screens/post_composer_test.exs` - Finished new-contract helper migration and corrected reducer-era expectations.
- `test/foglet_bbs/tui/screens/new_thread_test.exs` - Added reducer/render test adapters and adjusted no-op/error assertions to the new reducer contract.

## Decisions Made

- Kept `render/1`, `handle_key/2`, and `init_screen_state/1` declared in the behavior as bounded compatibility callbacks because existing modules still expose those helpers with `@impl` annotations. App production dispatch no longer calls them.
- Treated the existing text-oriented tests as out of scope unless they directly depended on the legacy callback seam; this plan changed call boundaries without broad assertion rewrites.

## Deviations from Plan

None - plan executed within the intended files and contract boundary.

## Issues Encountered

- `rtk mix foglet.tui.render main_menu --width 80 --height 24` initially failed in the sandbox because Mix PubSub could not open a local TCP socket (`:eperm`). It passed after rerunning with approval for the render command.
- Pre-existing Raxol dependency warnings still appear during test/precommit output; they were not introduced by this plan and `rtk mix precommit` passed.

## Verification

- `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs test/foglet_bbs/tui/screens/post_composer_test.exs test/foglet_bbs/tui/screens/new_thread_test.exs` - 197 tests, 0 failures.
- `rtk mix test test/foglet_bbs/tui/app_runtime_contract_test.exs test/foglet_bbs/tui/app_test.exs` - 141 tests, 0 failures.
- `rtk mix test test/foglet_bbs/tui/screen_test.exs test/foglet_bbs/tui/app_runtime_contract_test.exs` - 13 tests, 0 failures.
- `rtk mix test test/foglet_bbs/tui/app_runtime_contract_test.exs test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/screens/post_reader_test.exs test/foglet_bbs/tui/screens/post_composer_test.exs test/foglet_bbs/tui/screens/new_thread_test.exs test/foglet_bbs/tui/screen_test.exs` - 342 tests, 0 failures.
- `rtk rg -n ":handle_key|, :render, \\[state\\]|process_screen_commands\\(" lib/foglet_bbs/tui/app.ex` - no matches.
- `rtk rg -n "transitional|legacy render callback|legacy key handler|init_screen_state" lib/foglet_bbs/tui/screen.ex` - only bounded compatibility `init_screen_state/1` mentions remain.
- `rtk mix foglet.tui.render main_menu --width 80 --height 24` - passed.
- `rtk mix precommit` - passed.

## Known Stubs

None.

## Threat Flags

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Plan 40-03 can assume App production key/render dispatch no longer depends on broad screen callbacks. Remaining compatibility functions live in screen modules only as bounded cleanup surface, not production App routing.

## Self-Check: PASSED

- Summary file exists at `.planning/phases/40-verification-documentation/40-02-SUMMARY.md`.
- Task commits found in git history: `7b3aefc`, `6da5109`, `7c2f473`.
- No tracked file deletions were introduced by task commits.

---
*Phase: 40-verification-documentation*
*Completed: 2026-04-29*
