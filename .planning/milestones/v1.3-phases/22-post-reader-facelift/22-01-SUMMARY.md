---
phase: 22-post-reader-facelift
plan: 01
subsystem: tui
tags: [tui, widget, post-card, reader-parts, markdown, viewport, tdd]

requires:
  - phase: 16-unicode-width-foundation
    provides: TextWidth display-width helpers for gutter width budgeting
  - phase: 17-theme-and-mode-metadata
    provides: Theme slots used by reader header, progress, and gutter styling
provides:
  - Reader-oriented PostCard helper with separated header, progress, and body lines
  - Guttered markdown body rows suitable for Viewport.children
  - Widget tests for compact metadata, fallbacks, theme hygiene, progress, guttering, markdown preservation, and narrow widths
affects: [post-reader-facelift, tui-widgets, post-reader]

tech-stack:
  added: []
  patterns:
    - Public widget helper returns non-scrolling reader surfaces separately from viewport body rows
    - Guttered body lines wrap MarkdownBody output without reparsing or stringifying markdown

key-files:
  created:
    - .planning/phases/22-post-reader-facelift/22-01-SUMMARY.md
  modified:
    - lib/foglet_bbs/tui/widgets/post/post_card.ex
    - test/foglet_bbs/tui/widgets/post/post_card_test.exs

key-decisions:
  - "Kept reader assembly in PostCard through reader_parts/5 instead of adding a screen-local or parallel reader card module."
  - "Deferred segmented progress and implemented only compact Posts X/N progress for the Phase 22 baseline."

patterns-established:
  - "PostCard.reader_parts/5 returns %{header, progress, body_lines} so PostReader can keep Viewport ownership limited to body rows."
  - "Reader body guttering measures the gutter with TextWidth and floors the remaining body width to at least one cell."

requirements-completed: [READER-01, READER-02, READER-03, READER-04]

duration: 3min
completed: 2026-04-25
---

# Phase 22 Plan 01: PostCard Reader Parts Summary

**Shared PostCard reader post unit with compact metadata, compact progress, and guttered markdown body rows**

## Performance

- **Duration:** 3min
- **Started:** 2026-04-25T21:52:59Z
- **Completed:** 2026-04-25T21:55:35Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Added RED tests for the public reader helper contract before implementation.
- Implemented `PostCard.reader_parts/5` returning separated `:header`, `:progress`, and `:body_lines`.
- Added guttered body-line assembly that preserves `MarkdownBody.render_tuples_as_lines/4` styling and remains safe at width `1`.

## Task Commits

1. **Task 1: Add PostCard reader helper contract tests** - `8fa926e` (test)
2. **Task 2: Implement PostCard reader helper, compact header, progress, and guttered body rows** - `8d87dd4` (feat)

**Plan metadata:** committed separately as summary documentation.

## Files Created/Modified

- `lib/foglet_bbs/tui/widgets/post/post_card.ex` - Added `reader_parts/5`, compact reader header/progress helpers, and guttered reader body-line assembly.
- `test/foglet_bbs/tui/widgets/post/post_card_test.exs` - Added reader helper contract tests for metadata, fallbacks, theme hygiene, progress separation, guttering, markdown preservation, and narrow widths.
- `.planning/phases/22-post-reader-facelift/22-01-SUMMARY.md` - Execution summary.

## Decisions Made

- Used `reader_parts/5` as the public helper name and map return shape recommended by the plan.
- Kept existing `render/4`, `render_from_tuples/5`, and `render_body_lines/4` behavior backward compatible; reader guttering lives in a dedicated helper path.
- Used compact `Posts X/N` progress only; segmented glyph progress remains deferred.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- The RED gate failed as intended because `PostCard.reader_parts/5` was undefined before implementation.
- A concurrent unrelated commit appeared at `HEAD` while executing; plan commits remained present and no unrelated files were staged or modified by this plan.

## Known Stubs

None.

## Threat Flags

None - no network endpoints, authorization paths, file access patterns, schemas, or persistence trust boundaries were introduced.

## Verification

- `rtk mix test test/foglet_bbs/tui/widgets/post/post_card_test.exs` - passed after implementation.
- `rtk mix compile --warnings-as-errors` - passed.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Plan 22-02 can integrate `PostCard.reader_parts/5` into `PostReader.render_post_content/5` and warm paths, passing only `body_lines` into the viewport while rendering `header` and `progress` outside the scrollable content.

## Self-Check: PASSED

- Summary file exists at `.planning/phases/22-post-reader-facelift/22-01-SUMMARY.md`.
- Task commits found in git history: `8fa926e`, `8d87dd4`.
- No STATE.md or ROADMAP.md updates were made by this executor.

---
*Phase: 22-post-reader-facelift*
*Completed: 2026-04-25*
