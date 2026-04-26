# Phase 26: layout-width-foundations - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md - this log preserves the analysis.

**Date:** 2026-04-26
**Phase:** 26-layout-width-foundations
**Mode:** assumptions
**Areas analyzed:** Shared Width Primitives, Viewport Fit, Responsive Tables, Timestamp Formatting, Markdown Paragraph Rendering, Text Wrapping

## Assumptions Presented

### Shared Width Primitives

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Fix width behavior in shared primitives first, then keep screen changes thin. | Confident | `lib/foglet_bbs/tui/text_width.ex`, `lib/foglet_bbs/tui/widgets/input/tabs.ex`, `lib/foglet_bbs/tui/widgets/display/table.ex`, `lib/foglet_bbs/tui/widgets/display/console_table.ex`, `lib/foglet_bbs/tui/widgets/post/markdown_body.ex`, `lib/foglet_bbs/tui/widgets/README.md` |

### Viewport Fit

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Use internal widget/page/window behavior for Moderation tables and Boards tree, with secondary summary/detail/helper rows collapsible at 64x22 before sacrificing primary list/table usability. | Likely | `.planning/phases/26-layout-width-foundations/26-SPEC.md`, `lib/foglet_bbs/tui/screens/moderation.ex`, `lib/foglet_bbs/tui/screens/board_list.ex` |

### Responsive Tables

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Prefer responsive column widths and cell-level display-width ellipsis in `Display.Table`/`ConsoleTable`, avoiding pre-truncated fixed character fields in screen state builders. | Likely | `lib/foglet_bbs/tui/screens/moderation/state.ex`, `lib/foglet_bbs/tui/screens/shared/invites_state.ex`, `lib/foglet_bbs/tui/widgets/display/table.ex`, `lib/foglet_bbs/tui/widgets/display/console_table.ex` |

### Timestamp Formatting

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Reuse the existing user timezone fallback shape from chrome clock, but apply it to Moderation LOG timestamps using current user/session context. | Likely | `lib/foglet_bbs/tui/widgets/chrome/clock_formatter.ex`, `lib/foglet_bbs/accounts/user.ex`, `.planning/phases/26-layout-width-foundations/26-SPEC.md` |

### Markdown Paragraph Rendering

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Preserve blank visual lines in `MarkdownBody.group_by_newline/1` output while clamping newline runs to one blank line; do not move this into `Foglet.Markdown` or PostReader. | Confident | `lib/foglet_bbs/tui/widgets/post/markdown_body.ex`, `lib/foglet_bbs/tui/screens/post_reader.ex`, `test/foglet_bbs/tui/widgets/post/markdown_body_test.exs` |

### Text Wrapping

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Add `Foglet.TUI.TextWidth.wrap/2` beside existing visual width helpers with grapheme-aware width enforcement. | Confident | `lib/foglet_bbs/tui/text_width.ex`, `test/foglet_bbs/tui/text_width_test.exs`, `.planning/phases/26-layout-width-foundations/26-SPEC.md` |

## Corrections Made

No corrections - all assumptions confirmed.
