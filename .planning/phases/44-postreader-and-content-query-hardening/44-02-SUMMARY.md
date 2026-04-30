---
phase: 44-postreader-and-content-query-hardening
plan: 44-02
subsystem: tui
tags: [postreader, reader-window, bounded-state, tui, reducer-tests]
requires:
  - phase: 44-postreader-and-content-query-hardening
    provides: Tombstone-capable `Foglet.Posts.list_reader_window/2` and `%Foglet.Posts.ReaderWindow{}` metadata.
provides:
  - PostReader route entry uses bounded reader-window loads.
  - PostReader adjacent-window navigation requests next/previous bounded windows.
  - PostReader jump-last and thread-activity reloads use reader-window options.
  - Fake-domain tests proving PostReader does not call unbounded `list_posts/1` for reducer window flows.
affects: [postreader, tui-runtime, read-pointers]
tech-stack:
  added: []
  patterns:
    - Screen state stores bounded active `posts` plus explicit window cursor metadata.
    - Reducer effects use `:load_posts_window` and domain-owned reader-window options.
key-files:
  created:
    - .planning/phases/44-postreader-and-content-query-hardening/44-02-SUMMARY.md
  modified:
    - lib/foglet_bbs/tui/screens/post_reader.ex
    - lib/foglet_bbs/tui/screens/post_reader/state.ex
    - test/foglet_bbs/tui/screens/post_reader_test.exs
    - .planning/phases/44-postreader-and-content-query-hardening/deferred-items.md
key-decisions:
  - "PostReader keeps `%State{}.posts` as the active bounded window while storing first/last cursor and previous/next metadata beside it."
  - "Adjacent-window landing is driven by explicit `pending_window_direction` so next loads select index 0 and previous loads select the final returned post."
  - "Thread activity reloads request `direction: :around` anchored to the selected post message number when available."
patterns-established:
  - "Fake posts domains can raise on legacy unbounded calls and send bounded option telemetry back to ExUnit."
requirements-completed: [POST-01]
duration: 10min
completed: 2026-04-30
---

# Phase 44 Plan 44-02: PostReader Bounded Window Integration Summary

**PostReader now reads and navigates thread content through bounded reader windows while keeping local state limited to the active window.**

## Performance

- **Duration:** 10 min
- **Started:** 2026-04-30T00:21:38Z
- **Completed:** 2026-04-30T00:31:13Z
- **Tasks:** 4
- **Files modified:** 4

## Accomplishments

- Added reader-window cursor metadata and `reader_window_limit` to `%Foglet.TUI.Screens.PostReader.State{}` without replacing the existing `posts` field.
- Switched reducer route-entry, jump-last, adjacent-window navigation, and matching thread-activity reloads to `Foglet.Posts.list_reader_window/2`.
- Added boundary handling for `n`, `space`, `page_down`, `p`, and `page_up` so crossing a loaded window requests the adjacent bounded window and seeds pending read data for the landed post.
- Added fake-domain reducer tests proving a 1000-post thread loads only a 50-post active window and never uses `list_posts/1` on the bounded reducer path.

## Task Commits

Each task was committed atomically:

1. **Task 44-02-01: Add reader-window state metadata** - `fe417694` (feat)
2. **Task 44-02-02: Load bounded reader windows** - `58bd31a5` (feat)
3. **Task 44-02-03: Request adjacent reader windows** - `8d9c9f9f` (feat)
4. **Task 44-02-04: Prove bounded PostReader contract** - `f9c0a6fa` (test)

**Plan metadata:** captured in this docs commit.

## Files Created/Modified

- `lib/foglet_bbs/tui/screens/post_reader/state.ex` - Adds bounded-window cursor metadata, window navigation flags, limit, and pending direction intent.
- `lib/foglet_bbs/tui/screens/post_reader.ex` - Routes PostReader load, jump-last, thread activity, and boundary navigation through `:load_posts_window` effects.
- `test/foglet_bbs/tui/screens/post_reader_test.exs` - Adds fake-domain bounded contract tests and updates reducer assertions for `:load_posts_window`.
- `.planning/phases/44-postreader-and-content-query-hardening/deferred-items.md` - Records out-of-scope precommit Dialyzer blockers found after plan verification.

## Decisions Made

- Kept the public `load_posts/2` compatibility seam intact while making reducer route-entry and thread-activity flows use `list_reader_window/2`.
- Used `pending_window_direction` on state rather than encoding navigation intent in task payloads so reducer result handling can select the correct boundary post deterministically.
- Anchored thread-activity reloads around the selected post's `message_number`, falling back to current window cursors only when no selected post is available.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Stabilized subscriptions export test module loading**
- **Found during:** Task 44-02-02
- **Issue:** An existing assertion used `function_exported?/3` without first ensuring `Foglet.TUI.Screens.PostReader` was loaded, which became order-sensitive during the reducer test run.
- **Fix:** Added `Code.ensure_loaded?/1` before the export assertion.
- **Files modified:** `test/foglet_bbs/tui/screens/post_reader_test.exs`
- **Verification:** `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs` passed.
- **Committed in:** `58bd31a5`

---

**Total deviations:** 1 auto-fixed (Rule 1 bug).
**Impact on plan:** No product scope change; the fix made an existing structural test deterministic.

## Issues Encountered

- `rtk mix precommit` failed after plan verification due to out-of-scope Dialyzer findings: prior-wave `lib/foglet_bbs/posts/reader_window.ex` references unknown type `Foglet.Posts.Post.t/0`, and pre-existing `lib/foglet_bbs/tui/screens/post_reader/render.ex` has an impossible guard. These are documented in `deferred-items.md`.

## Verification

- `rtk rg -n "window_first_message_number|window_last_message_number|window_has_previous\\?|window_has_next\\?|reader_window_limit" lib/foglet_bbs/tui/screens/post_reader/state.ex` - passed.
- `rtk rg -n "posts:" lib/foglet_bbs/tui/screens/post_reader/state.ex` - passed.
- `rtk rg -n "load_posts_window|list_reader_window" lib/foglet_bbs/tui/screens/post_reader.ex` - passed.
- `rtk rg -n "posts_mod\\.list_posts\\(thread_id\\)" lib/foglet_bbs/tui/screens/post_reader.ex` - passed with no matches.
- `rtk rg -n "selected_index_after_load|jump_last" lib/foglet_bbs/tui/screens/post_reader.ex` - passed.
- `rtk rg -n "direction: :next|after_message_number|direction: :previous|before_message_number" lib/foglet_bbs/tui/screens/post_reader.ex` - passed.
- `rtk rg -n "pending_window_direction|window_direction|load_direction" lib/foglet_bbs/tui/screens/post_reader.ex lib/foglet_bbs/tui/screens/post_reader/state.ex` - passed.
- `rtk rg -n "unbounded list_posts/1 is forbidden|list_reader_window\\(thread_id, opts\\)|reader_window_requested" test/foglet_bbs/tui/screens/post_reader_test.exs` - passed.
- `rtk rg -n "1000|length\\(.*posts\\).*< 1000|direction: :last|direction: :next|direction: :previous" test/foglet_bbs/tui/screens/post_reader_test.exs` - passed.
- `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs` - passed, 81 tests, 0 failures.
- `rtk mix compile --warnings-as-errors` - passed for `foglet_bbs`; existing dependency warnings were emitted by `raxol`.
- `rtk mix precommit` - failed on out-of-scope Dialyzer findings documented above.

## Known Stubs

None.

## Threat Flags

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Plan 44-03 can build on a PostReader reducer that already treats `posts` as the bounded active window. The remaining Phase 44 work should preserve the `:load_posts_window` contract and can focus on resize-cache/render-purity hardening without reworking reader-window query semantics.

## Self-Check: PASSED

- Found `.planning/phases/44-postreader-and-content-query-hardening/44-02-SUMMARY.md`.
- Found `lib/foglet_bbs/tui/screens/post_reader.ex`.
- Found `lib/foglet_bbs/tui/screens/post_reader/state.ex`.
- Found `test/foglet_bbs/tui/screens/post_reader_test.exs`.
- Found task commits `fe417694`, `58bd31a5`, `8d9c9f9f`, and `f9c0a6fa` in git history.
- Stub scan found no placeholder/stub patterns in plan-modified source/test files.
- Threat surface scan found no new endpoints, auth paths, file access patterns, migrations, or schema changes.

---
*Phase: 44-postreader-and-content-query-hardening*
*Completed: 2026-04-30*
