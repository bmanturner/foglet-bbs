---
phase: 23-composer-facelift
plan: 4
subsystem: ui
tags: [tui, raxol, composer, layout-smoke, validation]

requires:
  - phase: 23-composer-facelift
    provides: PostComposer and NewThread migrations to Composer.EditorFrame
provides:
  - Composer size-contract smoke coverage at 64x22, 80x24, and 132x50
  - Validation proof for Phase 23 focused tests, preservation tests, and precommit
affects: [composer-facelift, tui-layout-smoke, post-composer, new-thread]

tech-stack:
  added: []
  patterns:
    - Positioned layout smoke tests assert terminal bounds and composer row overlap safety
    - Async TUI app tests seed runtime config keys read during render paths

key-files:
  created:
    - .planning/phases/23-composer-facelift/23-04-SUMMARY.md
  modified:
    - test/foglet_bbs/tui/layout_smoke_test.exs
    - lib/foglet_bbs/tui/screens/post_composer.ex
    - test/foglet_bbs/tui/app_test.exs

key-decisions:
  - "Composer size-contract overlap assertions are scoped to composer content rows; the full positioned output still gets bounds checks."
  - "Reply quote context now renders as separate width-truncated text rows instead of one newline-bearing text node."

patterns-established:
  - "Composer layout smoke fixtures use real PostComposer.render/1 and NewThread.render/1 states at canonical terminal sizes."
  - "Render tests that depend on Config.get!/1 seed the ETS cache for all required keys."

requirements-completed: [COMPOSER-01, COMPOSER-02, COMPOSER-03, COMPOSER-04, COMPOSER-05]

duration: 21min
completed: 2026-04-25
---

# Phase 23 Plan 4: Composer Size Contract Summary

**Composer layout smoke coverage now proves both composer screens keep mode controls, content, and counters visible at 64x22, 80x24, and 132x50**

## Performance

- **Duration:** 21min
- **Started:** 2026-04-25T21:53:45Z
- **Completed:** 2026-04-25T22:14:46Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Added `describe "composer — size contract"` to `test/foglet_bbs/tui/layout_smoke_test.exs`.
- Covered `PostComposer.render/1` and `NewThread.render/1` in edit and preview modes at `[{64, 22}, {80, 24}, {132, 50}]`.
- Asserted required `Composer`, `Edit`, `Preview`, content text, `/` budget text, `Title`, and `60 chars` visibility.
- Asserted positioned text stays inside terminal bounds with `TextWidth.display_width/1` and composer content rows do not overlap.
- Ran the full Phase 23 focused validation, preservation tests, and `rtk mix precommit`.

## Task Commits

Each task was committed atomically:

1. **Task 1 RED: Add composer size-contract smoke tests** - `d0dde7c` (test)
2. **Task 1 GREEN: Enforce composer size contract** - `b385e46` (fix)
3. **Task 2: Run Phase 23 validation and precommit** - `71afc1a` (test)

**Plan metadata:** this docs summary commit

_Note: Task 1 followed the TDD RED/GREEN gate. The RED run failed on the new 64x22 PostComposer quote-context bounds assertion before the production render fix._

## Files Created/Modified

- `test/foglet_bbs/tui/layout_smoke_test.exs` - Added Phase 23 composer smoke coverage and positioned text helpers.
- `lib/foglet_bbs/tui/screens/post_composer.ex` - Emits reply quote context as separate truncated text rows.
- `test/foglet_bbs/tui/app_test.exs` - Seeds `delivery_mode` in async render tests so login render avoids DB access.
- `.planning/phases/23-composer-facelift/23-04-SUMMARY.md` - Execution summary for this plan.

## Decisions Made

- Scoped same-row overlap checks to composer content rows because the existing shared chrome top row can overlap at 64 columns independently of the composer surface.
- Kept full positioned bounds checks across all text elements, including chrome and keybar text.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Split reply quote context into separate positioned rows**
- **Found during:** Task 1 (Add composer size-contract smoke tests)
- **Issue:** `PostComposer` rendered two quote lines as one newline-bearing text node, causing the positioned layout to measure it as one overflowing row at 64x22.
- **Fix:** Changed reply quote rendering to emit one width-truncated `text/2` node per quote line.
- **Files modified:** `lib/foglet_bbs/tui/screens/post_composer.ex`
- **Verification:** `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs`
- **Committed in:** `b385e46`

**2. [Rule 3 - Blocking] Seeded delivery mode for async app render tests**
- **Found during:** Task 2 (Run Phase 23 focused validation and precommit)
- **Issue:** `app_test.exs` async render tests seeded registration/email settings but not `delivery_mode`; login render called `Config.delivery_mode/0` and hit the database without sandbox ownership.
- **Fix:** Added `:ets.insert(:foglet_config, {"delivery_mode", "none"})` to the existing app test setup.
- **Files modified:** `test/foglet_bbs/tui/app_test.exs`
- **Verification:** `rtk mix test test/foglet_bbs/tui/widgets/compose_test.exs test/foglet_bbs/tui/app_test.exs`
- **Committed in:** `71afc1a`

---

**Total deviations:** 2 auto-fixed (1 Rule 1 bug, 1 Rule 3 blocker)
**Impact on plan:** Both fixes were required to make the planned size-contract and validation gates meaningful. No domain workflow, browser surface, autosave, attachment, poll, mention, rich text, or preview pipeline scope was added.

## Issues Encountered

- `rtk mix test test/foglet_bbs/tui/widgets/compose_test.exs test/foglet_bbs/tui/app_test.exs` initially failed with three `DBConnection.OwnershipError` failures from login rendering. The Task 2 fixture fix resolved the failures.
- Validation commands and precommit emitted existing vendored Raxol warnings; all commands exited successfully.

## Known Stubs

None. Stub-pattern scan found only existing test placeholders, nil/empty assertions, and input placeholder strings; no new stubbed UI data source was introduced.

## Threat Flags

None. No new network endpoints, auth paths, file access patterns, schema changes, or mutation boundaries were introduced.

## User Setup Required

None - no external service configuration required.

## Verification

- `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` - passed, 29 tests, 0 failures.
- `rtk mix test test/foglet_bbs/tui/widgets/composer/editor_frame_test.exs test/foglet_bbs/tui/screens/post_composer_test.exs test/foglet_bbs/tui/screens/new_thread_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` - passed, 119 tests, 0 failures.
- `rtk mix test test/foglet_bbs/tui/widgets/compose_test.exs test/foglet_bbs/tui/app_test.exs` - passed, 140 tests, 0 failures.
- `rtk mix precommit` - passed successfully.
- Forbidden composer-scope scan for browser routes, autosave/draft persistence, attachments, polls, mentions, rich text, and `PostCard.render` preview plumbing - no matches.

## TDD Gate Compliance

- RED commit present: `d0dde7c` (`test(23-04): add failing composer size smoke tests`).
- GREEN commit present after RED: `b385e46` (`fix(23-04): enforce composer size contract`).

## Next Phase Readiness

Phase 23 is ready for orchestration-level merge and shared artifact updates. Composer shell, both screen migrations, layout smoke coverage, focused validation, preservation tests, and precommit are green.

## Self-Check: PASSED

- Found `test/foglet_bbs/tui/layout_smoke_test.exs`.
- Found `lib/foglet_bbs/tui/screens/post_composer.ex`.
- Found `test/foglet_bbs/tui/app_test.exs`.
- Found `.planning/phases/23-composer-facelift/23-04-SUMMARY.md`.
- Found task commits `d0dde7c`, `b385e46`, and `71afc1a` in git history.
- Confirmed `.planning/STATE.md` and `.planning/ROADMAP.md` have no worktree changes.

---
*Phase: 23-composer-facelift*
*Completed: 2026-04-25*
