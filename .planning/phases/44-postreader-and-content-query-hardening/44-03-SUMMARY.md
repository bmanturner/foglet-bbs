---
phase: 44-postreader-and-content-query-hardening
plan: 44-03
subsystem: tui
tags: [postreader, render-cache, resize, render-purity, tui-tests]
requires:
  - phase: 44-postreader-and-content-query-hardening
    provides: PostReader bounded-window reducer integration and active render module split.
provides:
  - Reducer-side render-cache pruning to the active terminal width.
  - Structural resize-cache eviction tests for PostReader state.
  - Active `PostReader.Render` source guard for render-boundary state writes.
affects: [postreader, tui-runtime, render-purity]
tech-stack:
  added: []
  patterns:
    - Reducer warming prunes stale-width render-cache keys before cache hit or insert.
    - Render purity guard scans the active sibling render module and reports offending source lines.
key-files:
  created:
    - .planning/phases/44-postreader-and-content-query-hardening/44-03-SUMMARY.md
  modified:
    - lib/foglet_bbs/tui/screens/post_reader.ex
    - test/foglet_bbs/tui/screens/post_reader_test.exs
    - .planning/phases/44-postreader-and-content-query-hardening/deferred-items.md
key-decisions:
  - "Render-cache eviction stays in `warm_cache/4` reducer/state plumbing, not in `PostReader.Render`."
  - "Cache keys remain `{post_id, terminal_width}` while active state retains only current-width entries after warming."
  - "The purity guard treats `lib/foglet_bbs/tui/screens/post_reader/render.ex` as the active render boundary."
patterns-established:
  - "PostReader resize tests inspect `render_cache` key structure instead of rendered text."
  - "Render-boundary source guards should list path and line number for forbidden state writes."
requirements-completed: [POST-02, POST-03]
duration: 4min
completed: 2026-04-30
---

# Phase 44 Plan 44-03: Resize Cache And Render Purity Summary

**PostReader now prunes stale-width render-cache entries during reducer warming and guards the active render module against state writes.**

## Performance

- **Duration:** 4 min
- **Started:** 2026-04-30T00:35:06Z
- **Completed:** 2026-04-30T00:39:26Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments

- Added `render_cache_for_width/2` and wired `warm_cache/4` so warming at a terminal width first drops all stale-width cache entries, including cache-hit paths.
- Added reducer-level resize coverage proving a width-80 cache is replaced by width-40 keys while preserving `{post_id, width}` key shape.
- Updated the render purity guard to scan `PostReader.Render` as the active render boundary and reject `put_in`, `%{state | ...}`, `Map.put`, `Map.update`, and `Map.delete` with path/line diagnostics.

## Task Commits

Each task was committed atomically:

1. **Task 44-03-01: Add reducer-side cache eviction** - `2437d584` (feat)
2. **Task 44-03-02: Add structural resize-cache eviction test** - `6f7f7511` (test)
3. **Task 44-03-03: Strengthen active render-boundary purity guard** - `795f52be` (test)

**Plan metadata:** captured in this docs commit.

## Files Created/Modified

- `lib/foglet_bbs/tui/screens/post_reader.ex` - Prunes `render_cache` to the current terminal width before cache lookup or insertion.
- `test/foglet_bbs/tui/screens/post_reader_test.exs` - Updates cache expectations, adds structural resize eviction coverage, and scans the active render module for forbidden state writes.
- `.planning/phases/44-postreader-and-content-query-hardening/deferred-items.md` - Records the still-blocking out-of-scope Dialyzer findings from final precommit.

## Decisions Made

- Kept eviction in `warm_cache/4` because cache mutation belongs to reducer/state plumbing, while `PostReader.Render` remains display-only.
- Kept the existing `{post_id, terminal_width}` cache key shape, pruning by width rather than changing cache identity.
- Scanned the whole sibling render module for purity because render assembly now lives in `PostReader.Render`; top-level render helpers remain covered when present.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Updated stale-width cache expectation after reducer eviction**
- **Found during:** Task 44-03-01
- **Issue:** An existing cache-width test asserted that both width 80 and width 40 entries remain after resize, which contradicted POST-02 and caused the task test gate to fail.
- **Fix:** Updated the test to assert the current width remains and stale width 80 keys are absent.
- **Files modified:** `test/foglet_bbs/tui/screens/post_reader_test.exs`
- **Verification:** `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs` passed.
- **Committed in:** `2437d584`

---

**Total deviations:** 1 auto-fixed (Rule 1 bug).
**Impact on plan:** No scope change; the existing test was aligned with the planned cache-eviction behavior.

## Issues Encountered

- `rtk mix precommit` failed on existing Dialyzer findings already observed by 44-02: `lib/foglet_bbs/posts/reader_window.ex` references unknown type `Foglet.Posts.Post.t/0`, and `lib/foglet_bbs/tui/screens/post_reader/render.ex` has an impossible guard. Targeted plan verification passed, and the blocker is recorded in `deferred-items.md`.

## Verification

- `rtk rg -n "defp render_cache_for_width|cached_width != width" lib/foglet_bbs/tui/screens/post_reader.ex` - passed.
- `rtk rg -n "render_cache_for_width\\(ss\\.render_cache, w\\)|render_cache_for_width\\(ss\\.render_cache, width\\)" lib/foglet_bbs/tui/screens/post_reader.ex` - passed.
- `rtk rg -n "Map\\.put\\(|%\\{state \\||put_in\\(" lib/foglet_bbs/tui/screens/post_reader/render.ex` - passed with no matches.
- `rtk rg -n "render_cache.*80|render_cache.*40|elem\\(.*1\\).*80|elem\\(.*1\\).*40" test/foglet_bbs/tui/screens/post_reader_test.exs` - passed.
- `rtk rg -n "refute Enum\\.any\\?.*render_cache|Enum\\.all\\?.*render_cache" test/foglet_bbs/tui/screens/post_reader_test.exs` - passed.
- `rtk rg -n "post_reader/render\\.ex|PostReader\\.Render|forbidden_patterns" test/foglet_bbs/tui/screens/post_reader_test.exs` - passed.
- `rtk rg -n "Map\\.update\\(|Map\\.delete\\(" test/foglet_bbs/tui/screens/post_reader_test.exs` - passed.
- `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs` - passed, 82 tests, 0 failures.
- `rtk mix compile --warnings-as-errors` - passed for `foglet_bbs`; dependency warnings from `raxol` were emitted.
- `rtk mix precommit` - failed on out-of-scope Dialyzer findings documented above.

## Known Stubs

None.

## Threat Flags

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Plan 44-04 can proceed with PostReader resize-cache and render-purity invariants covered. The remaining Phase 44 work can focus on soft-delete list/query policy without revisiting render-cache plumbing.

## Self-Check: PASSED

- Found `.planning/phases/44-postreader-and-content-query-hardening/44-03-SUMMARY.md`.
- Found `lib/foglet_bbs/tui/screens/post_reader.ex`.
- Found `test/foglet_bbs/tui/screens/post_reader_test.exs`.
- Found task commits `2437d584`, `6f7f7511`, and `795f52be` in git history.
- Stub scan found no placeholder/stub patterns in plan-modified source/test files.
- Threat surface scan found no new endpoints, auth paths, file access patterns, migrations, or schema changes.
- Note: `.planning/STATE.md` was concurrently advanced to Phase 45 by another executor before final metadata updates; this plan did not overwrite that active state.

---
*Phase: 44-postreader-and-content-query-hardening*
*Completed: 2026-04-30*
