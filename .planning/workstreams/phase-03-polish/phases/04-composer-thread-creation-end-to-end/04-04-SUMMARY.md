---
phase: 04-composer-thread-creation-end-to-end
plan: "04"
subsystem: tui
tags: [refactor, composer, markdown, widgets, deduplication]

requires:
  - phase: 04-composer-thread-creation-end-to-end
    provides: "Compose widget (Plan 04-01) and MarkdownBody renderer (Phase 2)"
provides:
  - "PostComposer delegates rendering to shared Compose and MarkdownBody widgets"
  - "NewThread delegates rendering to shared Compose and MarkdownBody widgets"
  - "Preview regression smoke tests for both composers"
affects: [post_composer, new_thread, compose_widget]

tech-stack:
  added: []
  patterns: [delegate-to-shared-widget]

key-files:
  created: []
  modified:
    - lib/foglet_bbs/tui/screens/post_composer.ex
    - lib/foglet_bbs/tui/screens/new_thread.ex
    - test/foglet_bbs/tui/screens/post_composer_test.exs
    - test/foglet_bbs/tui/screens/new_thread_test.exs

key-decisions:
  - "PostComposer preview passes raw draft string to MarkdownBody.render/3 (not pre-parsed tuples) to leverage newline grouping"
  - "NewThread passes empty_line_placeholder: \" \" to Compose.render_input/4 to preserve legacy space-for-empty behavior"

patterns-established:
  - "Composer screens delegate to Compose.translate_key/1, Compose.render_input/4, and MarkdownBody.render/3"

requirements-completed: [COMPOSE-01, COMPOSE-02]

duration: 18min
completed: 2026-04-20
---

# Phase 4 Plan 04: Composer Preview via MarkdownBody + Dead-Code Cleanup Summary

**Pure refactor collapsing ~163 LOC of duplicated private helpers by delegating to shared Compose and MarkdownBody widgets**

## Performance

- **Duration:** 18 min
- **Started:** 2026-04-20T18:12:48Z
- **Completed:** 2026-04-20T18:30:16Z
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments
- PostComposer: deleted 4 private functions (translate_key/1, render_input_as_text/3, render_preview/2, render_markdown_tuples/2), replaced with delegations to Compose and MarkdownBody
- NewThread: deleted 4 private functions (translate_key/1, render_body/3, render_preview_text/2, render_markdown_tuples/2), replaced with delegations to Compose and MarkdownBody
- Added 4 preview regression smoke tests (2 per composer) verifying D-11 delegation to MarkdownBody.render/3 does not crash

## Task Commits

Each task was committed atomically:

1. **Task 1: PostComposer cleanup** - `ac69ee1` (refactor)
2. **Task 2: NewThread cleanup** - `4c048ab` (refactor)
3. **Task 3: Preview regression tests** - `a2a0e9e` (test)

## Files Created/Modified
- `lib/foglet_bbs/tui/screens/post_composer.ex` - Delegated to Compose + MarkdownBody; removed 83 LOC (418 -> 335)
- `lib/foglet_bbs/tui/screens/new_thread.ex` - Delegated to Compose + MarkdownBody; removed 80 LOC (480 -> 400)
- `test/foglet_bbs/tui/screens/post_composer_test.exs` - Added 2 preview smoke tests
- `test/foglet_bbs/tui/screens/new_thread_test.exs` - Added 2 preview smoke tests

## Decisions Made
- PostComposer preview passes raw draft string directly to MarkdownBody.render/3, which internally calls Foglet.Markdown.render/1 and groups by newline — this fixes the RENDER-01 bug (visible \n characters) that the old private render_markdown_tuples/2 had
- NewThread passes `empty_line_placeholder: " "` to Compose.render_input/4 to preserve its legacy space-for-empty-line behavior, while PostComposer uses the default (no placeholder)
- Did not add unused `alias Foglet.Config` to NewThread (was in plan but would cause warnings-as-errors failure)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Restored accidentally deleted quote_preview function**
- **Found during:** Task 1 (PostComposer cleanup)
- **Issue:** sed-based line deletion of render_preview/render_markdown_tuples also removed the `defp quote_preview(post) do` function header (off-by-one boundary error)
- **Fix:** Re-added the function header and its `body = Map.get(post, :body, "")` initialization
- **Files modified:** lib/foglet_bbs/tui/screens/post_composer.ex
- **Verification:** mix compile --warnings-as-errors passes, all 18 PostComposer tests pass
- **Committed in:** ac69ee1 (Task 1 commit)

**2. [Rule 1 - Bug] Removed unused alias Foglet.Config from NewThread**
- **Found during:** Task 2 (NewThread cleanup)
- **Issue:** Plan specified adding `alias Foglet.Config` to NewThread, but the module doesn't use Config — would cause --warnings-as-errors failure
- **Fix:** Omitted the Config alias from NewThread
- **Files modified:** lib/foglet_bbs/tui/screens/new_thread.ex
- **Verification:** mix compile --warnings-as-errors exits 0
- **Committed in:** 4c048ab (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (1 blocking, 1 bug)
**Impact on plan:** Both auto-fixes necessary for correctness. No scope creep.

## Issues Encountered
- sed line-range deletions are fragile with special Unicode characters (em dashes, block cursor chars). The edit tool couldn't match text containing █ — had to use sed with precise line numbers instead. The boundary miscalculation that deleted quote_preview's header was caught and fixed by compile + test.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Plan 04-04 (pure refactor) is complete. Combined with 04-03 (behavioral changes), the composer & thread creation end-to-end flow is fully deduplicated.
- Total LOC reduction from baseline: ~163 lines (898 -> 735 across both screens).
- All 539 tests + 1 property pass. Format clean. Zero warnings in project code.

---
*Phase: 04-composer-thread-creation-end-to-end*
*Completed: 2026-04-20*
