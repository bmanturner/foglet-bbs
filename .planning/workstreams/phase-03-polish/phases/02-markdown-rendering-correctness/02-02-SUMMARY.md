---
phase: 2-markdown-rendering-correctness
plan: 02
subsystem: [ui, rendering]
tags: [raxol, post-card, time-ago, theme, tui]

requires:
  - phase: 2-markdown-rendering-correctness
    provides: Post.MarkdownBody.render/4 and render_tuples/4 (Plan 01)
provides:
  - Post.PostCard.render/4 — post struct → full card with header + divider + body
  - Post.PostCard.render_from_tuples/5 — post + cached tuples → card (skips Markdown.parse)
  - Post.PostCard.body_line_count/1 — logical body line count for scroll bounds
affects: [post-reader]

tech-stack:
  added: []
  patterns:
    - "Thin assembly widget: owns layout, delegates body rendering to MarkdownBody"
    - "Dual entry point: render/4 (string) + render_from_tuples/5 (cached tuples)"
    - "Graceful degradation: missing user/inserted_at fields render partial header"

key-files:
  created:
    - test/foglet_bbs/tui/widgets/post/post_card_test.exs
  modified:
    - lib/foglet_bbs/tui/widgets/post/post_card.ex

key-decisions:
  - "PostCard is pure (no cache) — cache ownership deferred to PostReader per Plan 03"
  - "Time-ago via Foglet.TimeAgo.format/1 replaces raw DateTime display"
  - "Header uses theme.dim.fg, divider uses theme.border.fg"

patterns-established:
  - "Assembly widget pattern: header + divider + delegated body element in a column"
  - "NaiveDateTime support via DateTime.from_naive!/2 conversion"

requirements-completed: [RENDER-01, RENDER-02]

duration: 10min
completed: 2026-04-20
---

# Plan 02-02: Post.PostCard Summary

**Per-post card widget assembling dim header (Post X of N + By @handle · time-ago), themed divider, and delegated MarkdownBody body — pure with no cache ownership**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-04-20T12:05:00Z
- **Completed:** 2026-04-20T12:15:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Full per-post card: two-line dim header, themed border divider, MarkdownBody body
- render_from_tuples/5 for PostReader cache integration (Plan 03)
- TimeAgo integration replacing raw DateTime display
- Graceful degradation when user or inserted_at is nil
- NaiveDateTime support for schemas that don't use utc_datetime
- 18 unit tests covering header, body delegation, tuples path, theme hygiene

## Task Commits

1. **Task 1: Replace stub in post_card.ex** — `80bbbe0` (feat)
2. **Task 2: Create post_card_test.exs** — `80bbbe0` (test, same commit)

## Files Created/Modified
- `lib/foglet_bbs/tui/widgets/post/post_card.ex` — Full implementation: render/4, render_from_tuples/5, body_line_count/1, assemble_card, author_line
- `test/foglet_bbs/tui/widgets/post/post_card_test.exs` — 18 tests: header content, body delegation, render_from_tuples, body_line_count, theme hygiene

## Decisions Made
- Followed plan exactly — PostCard pure, cache deferred to PostReader
- No deviations from plan

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None

## Next Phase Readiness
- PostCard ready for PostReader integration (Plan 02-03 Wave 3)
- render_from_tuples/5 enables cache-hit path in PostReader
- body_line_count/1 enables scroll bounds computation without full card assembly

---
*Phase: 2-markdown-rendering-correctness*
*Completed: 2026-04-20*
