---
phase: 33-composer-wrap-boards-interaction
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - lib/foglet_bbs/tui/widgets/compose.ex
  - test/foglet_bbs/tui/widgets/compose_test.exs
autonomous: true
requirements:
  - POST-02
tags:
  - tui
  - composer
  - raxol
  - text-width

must_haves:
  truths:
    - "D-01: composer visual wrapping is implemented in shared Foglet.TUI.Widgets.Compose.render_input/4"
    - "D-02: Foglet.TUI.TextWidth.wrap/2 is used for body display rows while MultiLineInput.value remains the logical buffer"
    - "D-03: MultiLineInput wrap remains :none; visual wrapping is Foglet-owned render behavior"
    - "D-05: cursor and key handling continue through MultiLineInput.update/2"
    - "Compose.render_input/4 accepts width: N and renders a long single logical line as multiple text nodes when N is compact"
  artifacts:
    - path: "lib/foglet_bbs/tui/widgets/compose.ex"
      provides: "Shared visual wrapping renderer for composer body input"
      contains: "TextWidth.wrap"
    - path: "test/foglet_bbs/tui/widgets/compose_test.exs"
      provides: "Unit coverage for render-only soft wrapping and logical value preservation"
      contains: "width:"
---

<objective>
Update the shared composer body renderer so `Compose.render_input/4` can visually soft-wrap long logical lines using `Foglet.TUI.TextWidth.wrap/2` without changing `MultiLineInput.value`, while preserving existing cursor/key ownership by `MultiLineInput`.
</objective>

<execution_context>
@/Users/brendan.turner/Dev/personal/foglet_bbs/.codex/get-shit-done/workflows/execute-plan.md
@/Users/brendan.turner/Dev/personal/foglet_bbs/.codex/get-shit-done/templates/summary.md
</execution_context>

<context>
@AGENTS.md
@docs/raxol/getting-started/WIDGET_GALLERY.md
@lib/foglet_bbs/tui/widgets/README.md
@.planning/phases/33-composer-wrap-boards-interaction/33-CONTEXT.md
@.planning/phases/33-composer-wrap-boards-interaction/33-RESEARCH.md
@lib/foglet_bbs/tui/widgets/compose.ex
@lib/foglet_bbs/tui/text_width.ex
@test/foglet_bbs/tui/text_width_test.exs
</context>

<threat_model>
T-33-01: Visual wrapping could mutate or submit display text with inserted newlines. Mitigation: keep wrapping render-only, never write wrapped rows back to `MultiLineInput.value`, and add tests that assert the original single-line value remains byte-identical after render.
</threat_model>

<tasks>

<task type="auto" tdd="false">
  <name>Task 1: Add width-aware visual row generation to Compose.render_input/4</name>
  <files>lib/foglet_bbs/tui/widgets/compose.ex</files>
  <read_first>
    - lib/foglet_bbs/tui/widgets/compose.ex
    - lib/foglet_bbs/tui/text_width.ex
    - .planning/phases/33-composer-wrap-boards-interaction/33-CONTEXT.md
  </read_first>
  <action>
    In `Foglet.TUI.Widgets.Compose.render_input/4`, add support for a `:width` option.

    Concrete target behavior:
    - `width = Keyword.get(opts, :width, Map.get(input_st, :width))`
    - If `width` is a positive integer, render visual rows by wrapping each logical line with `TextWidth.wrap(line_with_optional_cursor, width)`.
    - If `width` is missing, non-integer, or less than 1, preserve existing behavior of one rendered row per logical line.
    - Preserve empty-input/empty-line display by rendering `[placeholder]` when a visual row is `""`, and default placeholder remains `""`.
    - Cursor insertion remains focused-only and logical-position-based: for the logical line whose index equals `cursor_row`, split with `TextWidth.split_at(line, cursor_col)` and inject `"\u2588"` between the before/after strings before visual wrapping.
    - Do not call `MultiLineInput.update/2`, mutate `input_st`, or write any wrapped text into state.

    Keep the return shape as `column style: %{gap: 0}` containing `text(display, fg: theme.primary.fg)` rows.
  </action>
  <verify>
    <automated>rtk mix format lib/foglet_bbs/tui/widgets/compose.ex</automated>
    <manual>Confirm `lib/foglet_bbs/tui/widgets/compose.ex` contains `Keyword.get(opts, :width` and `TextWidth.wrap`.</manual>
  </verify>
  <acceptance_criteria>
    - `rtk rg -n "Keyword.get\\(opts, :width|TextWidth\\.wrap" lib/foglet_bbs/tui/widgets/compose.ex` prints matches for both patterns.
    - `rtk rg -n "MultiLineInput.update" lib/foglet_bbs/tui/widgets/compose.ex` prints no matches outside documentation or comments.
    - `rtk mix format lib/foglet_bbs/tui/widgets/compose.ex` exits 0.
  </acceptance_criteria>
</task>

<task type="auto" tdd="false">
  <name>Task 2: Add focused shared-renderer tests for wrapping and cursor placement</name>
  <files>test/foglet_bbs/tui/widgets/compose_test.exs</files>
  <read_first>
    - test/foglet_bbs/tui/widgets/composer/editor_frame_test.exs
    - test/foglet_bbs/tui/text_width_test.exs
    - lib/foglet_bbs/tui/widgets/compose.ex
  </read_first>
  <action>
    Create `test/foglet_bbs/tui/widgets/compose_test.exs` if it does not exist.

    Add tests that:
    - Build a `%MultiLineInput{}` with `value: "alpha beta gamma delta"`, `wrap: :none`, and a cursor position.
    - Render with `Compose.render_input(input, false, theme, width: 10)` and assert the flattened text contains multiple wrapped visual chunks, including `"alpha beta"` and `"gamma"`.
    - Assert the original `input.value` still equals `"alpha beta gamma delta"` after render.
    - Render an empty value with `empty_line_placeholder: " "` and `width: 10`, asserting flattened output is not missing the placeholder behavior.
    - Render a focused long line with cursor position after `"alpha "` and assert flattened text contains `"\u2588"` on the rendered output.

    Use existing helpers from `Foglet.TUI.WidgetHelpers`, especially `flatten_text/1`, and construct a basic `Foglet.TUI.Theme` or use the same distinctive-theme pattern from `EditorFrameTest`.
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/widgets/compose_test.exs</automated>
  </verify>
  <acceptance_criteria>
    - `test/foglet_bbs/tui/widgets/compose_test.exs` contains `Compose.render_input`.
    - `test/foglet_bbs/tui/widgets/compose_test.exs` contains `width: 10`.
    - `test/foglet_bbs/tui/widgets/compose_test.exs` contains an assertion that `input.value == "alpha beta gamma delta"`.
    - `rtk mix test test/foglet_bbs/tui/widgets/compose_test.exs` exits 0.
  </acceptance_criteria>
</task>

</tasks>

<verification>
Run:

```bash
rtk mix test test/foglet_bbs/tui/widgets/compose_test.exs test/foglet_bbs/tui/text_width_test.exs
```
</verification>

<success_criteria>
- `Compose.render_input/4` supports `width: N` visual wrapping.
- Wrapped display rows are produced with `TextWidth.wrap/2`.
- `MultiLineInput.value` remains unchanged by render.
- Cursor rendering still uses the existing `"\u2588"` block.
</success_criteria>
