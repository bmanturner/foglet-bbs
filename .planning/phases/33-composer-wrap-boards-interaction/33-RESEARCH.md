# Phase 33: Composer Wrap & Boards Interaction - Research

**Created:** 2026-04-28
**Scope:** POST-02, BOARD-01

## Research Complete

Phase 33 is a narrow TUI stabilization phase. The existing code already exposes the two main primitives needed:

- `Foglet.TUI.TextWidth.wrap/2` preserves logical newline boundaries and returns display-width-bounded visual rows.
- `Foglet.TUI.Widgets.List.BoardTree.handle_event/2` already returns semantic actions for `:node_expanded`, `:node_collapsed`, and `:node_activated`.

## Implementation Findings

### Composer Wrap

`PostComposer` and `NewThread` both delegate body edit-mode rendering to `Foglet.TUI.Widgets.Compose.render_input/4`. That helper currently splits `input_st.value` only on real newline characters and injects the cursor into the logical line whose index matches `input_st.cursor_pos`.

The safest implementation is to keep `MultiLineInput` as the input and navigation authority, leave both state modules on `wrap: :none`, and make `Compose.render_input/4` produce visual rows at render time. This keeps submitted text unchanged because both submit paths continue reading `input_state.value`.

The likely API change is an optional `:width` option:

```elixir
Compose.render_input(input_st, focused?, theme, width: body_width)
```

When `:width` is omitted, preserve the existing no-wrap behavior or use `input_st.width` as a fallback only if it is a positive integer. Callers should pass the explicit body width derived from the current terminal width so resize reflow is render-only.

### Cursor Mapping

`MultiLineInput.cursor_pos` remains logical `{row, col}`. For the focused logical row, inject `"\u2588"` before wrapping, or split the logical row at `cursor_col`, wrap the left and right portions, then place the cursor in the correct visual segment.

Injecting before wrapping is simpler and acceptable if tests prove the cursor appears in the expected visual row for a long focused line. Use `TextWidth.split_at/2` before injection so wide graphemes remain safe.

### Boards Enter Toggle

`BoardList.handle_key/2` has a bespoke Enter branch that only handles `:node_activated`. `BoardTree.handle_event/2` already returns `:node_expanded` and `:node_collapsed` when Enter changes parent expansion state. Persisting the returned `%BoardTree{}` into `screen_state[:board_list].board_tree` is enough.

Category Enter should return `{:update, state, []}` with no domain commands. Board leaf Enter must continue setting `current_screen: :thread_list`, `current_board: board`, `screen_state[:thread_list]`, and `{:load_threads, board.id}`.

## Risks And Pitfalls

- `TextWidth.wrap/2` returns `[]` for an empty string. `Compose.render_input/4` must still render one placeholder row for empty input so existing layout does not collapse.
- If wrap width is computed too large, compact 64x22 render tests will not show wrapping. Use `max(width - 4, 20)` or the editor frame body budget consistently from the screens.
- Board category Enter currently has a regression test expecting `:no_match`; that test must be replaced with toggle assertions.
- Do not add Repo, PubSub, subscription, or thread commands for category toggling. The expansion state is already UI-local.

## Validation Architecture

Use focused ExUnit tests and existing TUI render commands:

- Unit/widget coverage for `Compose.render_input/4` wrapping behavior can be added in screen tests or a new `test/foglet_bbs/tui/widgets/compose_test.exs`.
- Screen coverage in `post_composer_test.exs` and `new_thread_test.exs` should seed a single long logical line, render at compact width, and assert multiple visible segments while `input_state.value` remains exactly unchanged.
- Resize/reflow coverage should render the same state at `{80, 24}` and `{64, 22}` and assert the compact render exposes more wrapped segments without adding `"\n"` to the state value.
- Boards coverage belongs in `board_list_test.exs`: category Enter collapses and expands, visible glyph flips between `▸` and `▾`, category Enter returns `[]` commands, and board leaf Enter still emits `{:load_threads, "b1"}`.

Recommended verification commands:

```bash
rtk mix test test/foglet_bbs/tui/screens/post_composer_test.exs test/foglet_bbs/tui/screens/new_thread_test.exs test/foglet_bbs/tui/screens/board_list_test.exs
rtk mix foglet.tui.render post_composer --width 64 --height 22
rtk mix foglet.tui.render board_list --width 64 --height 22
rtk mix precommit
```

## Research Complete
