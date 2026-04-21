---
phase: 2-markdown-rendering-correctness
plan: 01
subsystem: [ui, rendering]
tags: [raxol, markdown, mdex, ansi, tui, theme]

requires:
  - phase: 1-widget-foundation-theme-screen-chrome
    provides: Foglet.TUI.Theme struct, theme slots, function-form widget pattern
provides:
  - Post.MarkdownBody.render/4 — markdown string → Raxol column of themed text/2 rows
  - Post.MarkdownBody.render_tuples/4 — pre-parsed tuples → Raxol column (cache-friendly)
  - Post.MarkdownBody.line_count/1 — logical line count for scroll bounds
  - Newline-grouping algorithm: Enum.chunk_by → reject newline groups → one row per logical line
affects: [post-card, post-reader, thread-list]

tech-stack:
  added: []
  patterns:
    - "Newline grouping via Enum.chunk_by(&newline?/1) + Enum.reject(&newline_group?/1)"
    - "Theme slot mapping: :bold→accent, :dim→dim, :underline→title, :italic→primary, :plain→primary"
    - "Dual entry point: render/4 (string input) + render_tuples/4 (cached tuples)"

key-files:
  created:
    - test/foglet_bbs/tui/widgets/post/markdown_body_test.exs
  modified:
    - lib/foglet_bbs/tui/widgets/post/markdown_body.ex

key-decisions:
  - "Option B newline layout: group tuples between newline markers into line-groups, emit one row per physical line (preserves inline style mixing)"
  - "Trust Raxol layout for wrapping — no pre-wrapping at width; scroll window applied at line-group level"
  - "Bold uses theme.accent.fg rather than theme.primary so bold runs visually pop"

patterns-established:
  - "Function-form widget: import Raxol.Core.Renderer.View, no use Raxol.UI.Components"
  - "Dual render entry point pattern: render/4 for string input, render_tuples/4 for cached parse output"

requirements-completed: [RENDER-01, RENDER-02]

duration: 15min
completed: 2026-04-20
---

# Plan 02-01: Post.MarkdownBody Summary

**Newline-grouping markdown renderer that eliminates visible \n artifacts by grouping Foglet.Markdown tuples into line-groups, styled per D-06 theme slots**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-04-20T11:45:00Z
- **Completed:** 2026-04-20T12:00:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Replaced Phase 1 stub with working render/4 that groups styled tuples between `{"\n", :plain}` separators into line-groups
- Each logical line emits as a `row` of `text/2` siblings, preserving inline style mixing (bold within plain, etc.)
- Theme-driven style mapping per D-06: bold→accent, dim→dim, underline→title, italic→primary
- Scroll windowing via scroll_offset/max_lines at the line-group level
- render_tuples/4 for PostCard cache integration (Plan 02-02)
- 20 unit tests covering grouping, theme, scroll, line_count, render_tuples parity

## Task Commits

1. **Task 1: Replace stub in markdown_body.ex** — `85fd86e` (feat)
2. **Task 2: Create markdown_body_test.exs** — `85fd86e` (test, same commit)

## Files Created/Modified
- `lib/foglet_bbs/tui/widgets/post/markdown_body.ex` — Full implementation: render/4, render_tuples/4, line_count/1, group_by_newline, window_lines, styled_text
- `test/foglet_bbs/tui/widgets/post/markdown_body_test.exs` — 20 tests: basic contract, line grouping, theme application, scroll window, line_count, render_tuples parity

## Decisions Made
- Followed plan exactly — Option B newline grouping, Raxol-trusted wrapping, D-06 style mapping
- No deviations from plan

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered
- Database not running initially; created local `postgres` role to satisfy Ecto sandbox requirement
- All warnings in compile output are pre-existing (raxol vendor code), not from this plan's files

## User Setup Required
None

## Next Phase Readiness
- Post.MarkdownBody ready for PostCard consumption (Plan 02-02 Wave 2)
- render_tuples/4 and line_count/1 ready for PostReader cache integration (Plan 02-03 Wave 3)

---
*Phase: 2-markdown-rendering-correctness*
*Completed: 2026-04-20*
