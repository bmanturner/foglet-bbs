# Phase 26: Layout & Width Foundations - Research

**Researched:** 2026-04-26

## User Constraints From CONTEXT.md

Phase 26 is a stabilization foundation phase. It must repair shared TUI width behavior before later form, cursor, auth, composer, and board interaction phases depend on it.

Locked decisions:

- Fix shared primitives first: `Foglet.TUI.TextWidth`, `Input.Tabs`, `Display.Table` / `ConsoleTable`, `List.BoardTree`, and `Post.MarkdownBody`.
- Keep screen changes thin; screens should pass width/height/user context into shared widgets.
- At 64x22, primary content wins. Secondary summaries and detail strips may collapse or be omitted.
- Responsive table work belongs in shared table primitives and cell-boundary ellipsis, not fixed pre-truncation in screen state builders.
- Moderation LOG timestamps use the current user's preferred timezone with deterministic `Etc/UTC` fallback.
- `TextWidth.wrap/2` is a visual helper: grapheme-aware, word-boundary preferred, no-space blob splitting only when necessary.
- Markdown paragraph breaks stay in `MarkdownBody`; `PostReader` continues to delegate.

## Phase Requirements

Required IDs: `LAYOUT-01`, `LAYOUT-02`, `LAYOUT-03`, `LAYOUT-04`, `LAYOUT-05`, `LAYOUT-06`, `POST-01`.

## Summary

The implementation should proceed from deterministic primitives outward:

1. Add `TextWidth.wrap/2` and table cell-fit helpers backed by `display_width/1`, `split_at/2`, `slice_to_width/2`, `truncate/3`, and `pad_trailing/2`.
2. Make `Display.Table` / `ConsoleTable` accept render-time width budgets and compute explicit column widths before delegating to Raxol's table renderer.
3. Clamp `Input.Tabs.render/2` to the available inner frame width so Account, Moderation, and Sysop inherit the trailing-glyph fix.
4. Pass real body dimensions from Moderation and Boards into widgets and trim/collapse secondary output when compact.
5. Preserve markdown blank lines in `MarkdownBody.group_by_newline/1` by emitting explicit blank line groups instead of dropping newline runs.

## Architecture Patterns

### Pattern 1: Primitive Contract First

`Foglet.TUI.TextWidth` already centralizes display width behavior and uses `Raxol.UI.TextMeasure`. New wrapping and table fitting should reuse it rather than measuring with `String.length/1`.

Relevant files:

- `lib/foglet_bbs/tui/text_width.ex`
- `test/foglet_bbs/tui/text_width_test.exs`
- `lib/foglet_bbs/tui/widgets/display/table.ex`
- `lib/foglet_bbs/tui/widgets/display/console_table.ex`

### Pattern 2: Screen Calculates Available Body, Widget Owns Fitting

`ScreenFrame` consumes the terminal border and padding. Screens can calculate inner width/height from `state.terminal_size`, but truncation/windowing should happen inside the shared widget or a small helper local to the widget.

Good examples:

- `BoardList.row_width/1` already converts terminal columns into an inner width.
- `BoardTree.render/2` accepts `width:` and keeps individual rows width-safe.
- `Moderation.inner_width/1` already computes width; it needs a matching body-height concept and compact rendering choices.

### Pattern 3: Rebuild Bounded Table State From Domain Rows

Moderation currently rebuilds tables at render time through `fresh_log_table/1`, `fresh_users_table/1`, and `fresh_boards_table/1`. That preserves test helpers that mutate raw row lists without rebuilding widget state. Keep that approach, but extend builders to accept width/timezone inputs.

### Pattern 4: Explicit Blank Line Groups

`MarkdownBody.group_by_newline/1` currently chunks on `{"\n", :plain}` and rejects newline groups. This collapses `First\n\nSecond`. The correct behavior is to count newline runs and insert exactly one blank group for any run length of two or more separators while preserving one separator as a soft line break.

## Common Pitfalls

### Pitfall 1: Fixed Character Truncation Masks Table Bugs

`Moderation.State.build_log_table/1` pre-truncates `actor`, `action`, `body`, and `reason`. That makes rows appear to fit but prevents available-width use. Move long-field elision to cell fitting so 80x24 LOG can consume body width and elide at cell boundaries with `...`/`…`.

### Pitfall 2: `String.length/1` Reintroduces Unicode Drift

Tests must assert `TextWidth.display_width(line) <= width` for wrapped and table-rendered lines. Combining `e`, CJK `あ`, ZWJ emoji, and ssh-rsa-shaped no-space blobs must be covered.

### Pitfall 3: Raxol Table May Need Explicit Widths

`Display.Table.normalize_column/1` defaults widths to 20. `ConsoleTable.normalize_column/1` defaults widths to 12. Auto/responsive behavior should resolve to explicit integer widths before calling the underlying Raxol table so render output is deterministic.

### Pitfall 4: Selection State Must Stay In Widget State

Boards and tables already keep cursor/selection inside `BoardTree`, `Display.Tree`, and `ConsoleTable`. Do not introduce parallel selected-index state for Phase 26. If visible rows are windowed, scroll/window offsets must be derived from the existing cursor or added to the widget state deliberately.

### Pitfall 5: Human SSH Evidence Is Required For Fit

Automated layout smoke tests catch many element-position regressions, but the SPEC explicitly requires human SSH checks at 64x22 and 80x24. Plans must include a manual verification artifact path and exact scenarios.

## Validation Architecture

### Test Framework

Elixir ExUnit with existing helpers:

- `test/foglet_bbs/tui/text_width_test.exs`
- `test/foglet_bbs/tui/widgets/display/table_test.exs`
- `test/foglet_bbs/tui/widgets/display/console_table_test.exs`
- `test/foglet_bbs/tui/widgets/input/tabs_test.exs`
- `test/foglet_bbs/tui/widgets/list/board_tree_test.exs`
- `test/foglet_bbs/tui/widgets/post/markdown_body_test.exs`
- `test/foglet_bbs/tui/layout_smoke_test.exs`
- `test/foglet_bbs/tui/screens/moderation_test.exs`
- `test/foglet_bbs/tui/screens/board_list_test.exs`

### Phase Requirements To Test Map

| Requirement | Automated Coverage | Manual Coverage |
|-------------|--------------------|-----------------|
| LAYOUT-01 | `tabs_test.exs`, `layout_smoke_test.exs` Account/Moderation/Sysop 64x22 | SSH Account, Moderation, Sysop at 64x22 |
| LAYOUT-02 | `moderation_test.exs`, `layout_smoke_test.exs` LOG/USERS/BOARDS at 64x22 | SSH Moderation LOG/USERS/BOARDS at 64x22 |
| LAYOUT-03 | `board_list_test.exs`, `layout_smoke_test.exs` overlarge directory at 64x22 | SSH Boards overlarge directory at 64x22 |
| LAYOUT-04 | `console_table_test.exs`, `shared/invites_state` or Sysop test | SSH Sysop INVITES at 80x24 |
| LAYOUT-05 | `moderation_test.exs` with long body/reason and timezone user | SSH Moderation LOG at 80x24 |
| LAYOUT-06 | `text_width_test.exs` wrap tests | None |
| POST-01 | `markdown_body_test.exs`, `post_reader_test.exs` | SSH Post Reader sample post |

### Sampling Rate

- After primitive tasks: run focused widget tests.
- After screen-fit tasks: run focused screen tests plus `layout_smoke_test.exs`.
- Before completion: run `rtk mix precommit`.

## Security Domain

Phase 26 changes presentation and rendering only. No new authorization, persistence, SSH auth, token, invite lifecycle, or moderation mutation paths are introduced. Maintain existing context boundaries and do not move domain behavior into TUI render functions.

## Assumptions Log

- `ScreenFrame` continues to consume 4 columns in total for border/padding, matching existing `inner_width/1` comments.
- `Tzdata` is available because existing chrome clock formatting already uses timezone behavior.
- `ConsoleTable` can safely grow an optional `width:` / `height:` contract without breaking callers because defaults can preserve current behavior.

## Open Questions

- Exact column ratios are intentionally left to implementation; acceptance requires separated columns and no overlap, not a specific ratio.
- Whether Boards uses scroll offset stored in `BoardTree` or screen-local state is open, but cursor ownership must remain in `BoardTree` / `Display.Tree`.

## Sources

- `.planning/phases/26-layout-width-foundations/26-SPEC.md`
- `.planning/phases/26-layout-width-foundations/26-CONTEXT.md`
- `.planning/REQUIREMENTS.md`
- `.planning/PROJECT.md`
- `docs/raxol/getting-started/WIDGET_GALLERY.md`
- `lib/foglet_bbs/tui/widgets/README.md`
- `lib/foglet_bbs/tui/text_width.ex`
- `lib/foglet_bbs/tui/widgets/input/tabs.ex`
- `lib/foglet_bbs/tui/widgets/display/table.ex`
- `lib/foglet_bbs/tui/widgets/display/console_table.ex`
- `lib/foglet_bbs/tui/screens/moderation.ex`
- `lib/foglet_bbs/tui/screens/moderation/state.ex`
- `lib/foglet_bbs/tui/screens/board_list.ex`
- `lib/foglet_bbs/tui/widgets/list/board_tree.ex`
- `lib/foglet_bbs/tui/widgets/post/markdown_body.ex`

## RESEARCH COMPLETE

