# Phase 33: Pattern Map

## Target Files And Closest Analogs

| Target | Role | Closest Existing Analog | Pattern To Preserve |
|--------|------|-------------------------|---------------------|
| `lib/foglet_bbs/tui/widgets/compose.ex` | Shared body editor renderer | `lib/foglet_bbs/tui/text_width.ex`, `lib/foglet_bbs/tui/widgets/composer/editor_frame.ex` | Pure render helper, theme-routed text rows, display-width helpers |
| `lib/foglet_bbs/tui/screens/post_composer.ex` | Reply composer caller | Existing `composer_body/6` and `render_preview/4` | Derive width from `state.terminal_size`, keep submit reading `input_state.value` |
| `lib/foglet_bbs/tui/screens/new_thread.ex` | New-thread caller | Existing `render_body_section/3` | Keep title and body focus behavior separate; body edit delegates to `Compose.render_input/4` |
| `lib/foglet_bbs/tui/screens/board_list.ex` | Boards key handling | Existing `handle_tree_key/2`, Enter board-leaf branch | Persist returned `BoardTree` in screen state and emit commands only for board leaf activation |
| `test/foglet_bbs/tui/screens/post_composer_test.exs` | Reply composer tests | Existing render and submit tests | Seed `MultiLineInput` directly; assert flattened text and state value |
| `test/foglet_bbs/tui/screens/new_thread_test.exs` | New-thread tests | Existing compose-step render and submit tests | Seed `body_input_state`; keep title tests unchanged |
| `test/foglet_bbs/tui/screens/board_list_test.exs` | Boards interaction tests | Existing left/right collapse and board-leaf Enter tests | Use `BoardList.load_boards/1`, `handle_key/2`, and `flatten_text/1` |

## Code Excerpts

`Compose.render_input/4` currently renders logical lines:

```elixir
lines =
  input_st.value
  |> String.split("\n")
  |> case do
    [] -> [""]
    ls -> ls
  end
```

The phase should replace the one-row-per-logical-line output with visual rows produced from `TextWidth.wrap/2`, while preserving the same `text(display, fg: theme.primary.fg)` output shape.

`BoardList.handle_key/2` currently ignores category Enter:

```elixir
case BoardTree.handle_event(%{key: :enter}, tree) do
  {%BoardTree{} = new_tree, :node_activated} -> ...
  _other -> :no_match
end
```

The phase should add explicit `:node_expanded` and `:node_collapsed` handling before the `_other` branch and return `{:update, put_ss(state, %{ss | board_tree: new_tree}), []}`.
