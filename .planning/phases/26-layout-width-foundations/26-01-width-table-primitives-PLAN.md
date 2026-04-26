---
phase: 26
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - lib/foglet_bbs/tui/text_width.ex
  - lib/foglet_bbs/tui/widgets/display/table.ex
  - lib/foglet_bbs/tui/widgets/display/console_table.ex
  - test/foglet_bbs/tui/text_width_test.exs
  - test/foglet_bbs/tui/widgets/display/table_test.exs
  - test/foglet_bbs/tui/widgets/display/console_table_test.exs
autonomous: true
requirements:
  - LAYOUT-04
  - LAYOUT-05
  - LAYOUT-06
user_setup: []
tags:
  - tui
  - width
  - widgets
  - elixir
must_haves:
  truths:
    - "`Foglet.TUI.TextWidth.wrap/2` exists, returns a list of strings, preserves grapheme clusters, prefers word boundaries, and never emits a line wider than the requested display width."
    - "`Display.Table` and `ConsoleTable` can be initialized with a width budget and resolve compact/responsive column widths before rendering."
    - "Width budgets are drawable content widths, not raw terminal widths. The screen frame border consumes at least 2 columns, so a string whose display width equals the terminal column count is already too wide for framed content."
    - "Table cell values are elided at cell boundaries with `…` using `TextWidth.truncate/2` or `TextWidth.truncate/3`, not pre-truncated with `String.slice/3` in screen state builders."
  artifacts:
    - path: "lib/foglet_bbs/tui/text_width.ex"
      provides: "Reusable visual wrapping helper."
      contains: "def wrap(text, width)"
    - path: "lib/foglet_bbs/tui/widgets/display/table.ex"
      provides: "Width-aware table column and cell rendering foundation."
      contains: "available_width"
    - path: "lib/foglet_bbs/tui/widgets/display/console_table.ex"
      provides: "Operator-console facade passes width/page options to Display.Table."
      contains: "width:"
---

<objective>
Add the shared width primitives that later Phase 26 screen fixes depend on: `TextWidth.wrap/2` plus responsive table sizing/cell elision in `Display.Table` and `ConsoleTable`.
</objective>

<context>
@.planning/phases/26-layout-width-foundations/26-CONTEXT.md
@.planning/phases/26-layout-width-foundations/26-RESEARCH.md
@.planning/phases/26-layout-width-foundations/26-SPEC.md
@AGENTS.md
@lib/foglet_bbs/tui/text_width.ex
@lib/foglet_bbs/tui/widgets/display/table.ex
@lib/foglet_bbs/tui/widgets/display/console_table.ex
@test/foglet_bbs/tui/text_width_test.exs
@test/foglet_bbs/tui/widgets/display/table_test.exs
@test/foglet_bbs/tui/widgets/display/console_table_test.exs
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add grapheme-aware TextWidth.wrap/2</name>
  <files>lib/foglet_bbs/tui/text_width.ex, test/foglet_bbs/tui/text_width_test.exs</files>
  <read_first>
    - lib/foglet_bbs/tui/text_width.ex
    - test/foglet_bbs/tui/text_width_test.exs
    - .planning/phases/26-layout-width-foundations/26-SPEC.md
  </read_first>
  <action>
    Add `@spec wrap(term(), integer()) :: [String.t()]` and `def wrap(text, width)` to `Foglet.TUI.TextWidth`.

    Required behavior:
    - `width <= 0` returns `[]`.
    - Empty string returns `[]`.
    - Preserve existing newline boundaries: split input on `"\n"` before wrapping each logical line; blank input lines should produce `""` in the returned list.
    - Prefer wrapping at whitespace/word boundaries when the next word would exceed `width`.
    - Split no-space blobs only when necessary using `split_at/2`.
    - Every emitted nonblank line must satisfy `display_width(line) <= width`.
    - Do not split grapheme clusters. Use `String.graphemes/1`, existing `split_at/2`, and `display_width/1`; do not use byte slicing except through existing helper functions.
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/text_width_test.exs</automated>
  </verify>
  <acceptance_criteria>
    - `rtk rg -n "def wrap\\(text, width\\)" lib/foglet_bbs/tui/text_width.ex` returns one match.
    - `rtk rg -n "wrap/2" test/foglet_bbs/tui/text_width_test.exs` returns at least one match.
    - Tests cover ASCII word wrapping, `あ`, `cafe\\u0301`, a ZWJ emoji string, and a no-space `ssh-rsa`-shaped blob.
    - `rtk mix test test/foglet_bbs/tui/text_width_test.exs` exits 0.
  </acceptance_criteria>
</task>

<task type="auto">
  <name>Task 2: Add width-aware table and ConsoleTable rendering contracts</name>
  <files>lib/foglet_bbs/tui/widgets/display/table.ex, lib/foglet_bbs/tui/widgets/display/console_table.ex, test/foglet_bbs/tui/widgets/display/table_test.exs, test/foglet_bbs/tui/widgets/display/console_table_test.exs</files>
  <read_first>
    - lib/foglet_bbs/tui/widgets/display/table.ex
    - lib/foglet_bbs/tui/widgets/display/console_table.ex
    - test/foglet_bbs/tui/widgets/display/table_test.exs
    - test/foglet_bbs/tui/widgets/display/console_table_test.exs
    - lib/foglet_bbs/tui/text_width.ex
  </read_first>
  <action>
    Extend `Display.Table.init/1` to accept optional `:width` and `:page_size`, store the resolved width in the table state, and normalize columns before Raxol render:
    - Treat `:width` as the drawable content width available inside the caller's container, not the raw terminal width. If a caller only has `{terminal_cols, terminal_rows}`, it must subtract the outer frame border first; at minimum `terminal_cols - 2` for left/right border glyphs, and usually `terminal_cols - 4` when `ScreenFrame` padding is also in play.
    - Integer column widths remain honored when total width fits.
    - `:auto` columns receive a share of remaining width.
    - Optional ratio columns may be represented as `%{width: {:ratio, n}}`; resolve ratios to integers.
    - Enforce a minimum data column width of `3` so ellipsis can render.
    - Cell values must be converted to strings and truncated with `TextWidth.truncate(value, column_width)`.
    - Header labels must also fit their column widths.

    Extend `ConsoleTable.init/1` to accept `:width`, pass it to `Table.init/1`, and preserve current default behavior when no width is supplied.
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/widgets/display/table_test.exs test/foglet_bbs/tui/widgets/display/console_table_test.exs</automated>
  </verify>
  <acceptance_criteria>
    - `rtk rg -n "TextWidth\\.truncate" lib/foglet_bbs/tui/widgets/display/table.ex` returns at least one match.
    - `rtk rg -n "width:" lib/foglet_bbs/tui/widgets/display/console_table.ex` returns at least one match.
    - Table and ConsoleTable tests include a framed-width case: given a 64-column terminal, the width budget passed to table rendering is no greater than 62, and no flattened table line exceeds that drawable width.
    - Table tests assert a long cell at width 24 renders `…` and no flattened line exceeds 24 display columns.
    - ConsoleTable tests assert Code/Status/Created/Used by columns remain present with a compact width and rendered text includes separator whitespace between headers.
    - `rtk mix test test/foglet_bbs/tui/widgets/display/table_test.exs test/foglet_bbs/tui/widgets/display/console_table_test.exs` exits 0.
  </acceptance_criteria>
</task>

</tasks>

<threat_model>
Phase 26 Plan 01 is presentation-only. It introduces no new domain mutations, persistence writes, authorization paths, token handling, SSH authentication, or external input channels. Main risk is denial-of-service from pathological wrapping loops; guard with `width <= 0` handling and tests for no-space blobs.
</threat_model>

<verification>
- `rtk mix test test/foglet_bbs/tui/text_width_test.exs`
- `rtk mix test test/foglet_bbs/tui/widgets/display/table_test.exs test/foglet_bbs/tui/widgets/display/console_table_test.exs`
</verification>

<success_criteria>
- `TextWidth.wrap/2` passes grapheme/no-space blob tests.
- Table rendering can fit compact widths without overflowing flattened render output.
- Existing table and ConsoleTable behavior tests still pass.
</success_criteria>
