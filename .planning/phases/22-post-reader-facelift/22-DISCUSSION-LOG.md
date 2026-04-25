# Phase 22: post-reader-facelift - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the analysis.

**Date:** 2026-04-25
**Phase:** 22-post-reader-facelift
**Mode:** assumptions
**Areas analyzed:** Shared Post Unit, Header Shape, Body Gutter And Viewport, Progress Treatment, Test Placement

## Assumptions Presented

### Shared Post Unit

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Extend `Foglet.TUI.Widgets.Post.PostCard` rather than create a new sibling widget. | Likely | `lib/foglet_bbs/tui/widgets/post/post_card.ex`; `lib/foglet_bbs/tui/screens/post_reader.ex`; `.planning/phases/22-post-reader-facelift/22-SPEC.md` |

### Header Shape

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Use one compact header string: `Post X of N • #message_number • @handle • age ago`, produced by PostCard helper code and rendered by PostReader above the viewport. | Confident | `SCREENS.md` §Post Reader; `.planning/phases/22-post-reader-facelift/22-SPEC.md`; `lib/foglet_bbs/tui/widgets/post/post_card.ex` |

### Body Gutter And Viewport

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Add the left gutter in `PostCard.render_body_lines/4` / `MarkdownBody` line assembly so `Viewport` still owns scrolling over body rows. | Likely | `lib/foglet_bbs/tui/screens/post_reader.ex`; `lib/foglet_bbs/tui/screens/post_reader/state.ex`; `lib/foglet_bbs/tui/widgets/post/markdown_body.ex`; `.planning/phases/22-post-reader-facelift/22-SPEC.md` |

### Progress Treatment

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Always render compact text progress `Posts X/N`; add a segmented bar such as `▰▱` only when width permits, inside PostReader chrome-adjacent content rather than inside the scrollable body. | Likely | `SCREENS.md` §Post Reader; `.planning/phases/22-post-reader-facelift/22-SPEC.md`; prior v1.3 size-contract contexts |

### Test Placement

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Extend `post_reader_test.exs` and `layout_smoke_test.exs`; add `post_card_test.exs` only if PostCard gets new public helper behavior. | Confident | `test/foglet_bbs/tui/screens/post_reader_test.exs`; `test/foglet_bbs/tui/layout_smoke_test.exs`; `.planning/phases/19-main-menu-dashboard/19-CONTEXT.md`; `.planning/phases/20-rich-rows-and-thread-flow/20-CONTEXT.md`; `.planning/phases/21-board-directory-facelift/21-CONTEXT.md` |

## Corrections Made

No corrections — all assumptions confirmed.
