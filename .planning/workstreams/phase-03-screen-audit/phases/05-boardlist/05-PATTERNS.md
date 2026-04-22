# Phase 5: BoardList — Pattern Map

**Mapped:** 2026-04-22
**Files analyzed:** 2
**Analogs found:** 2 / 2

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `lib/foglet_bbs/tui/screens/board_list.ex` | list screen + key router | key event -> screen state -> command tuple | itself + `lib/foglet_bbs/tui/screens/thread_list.ex` (initializer/state plumbing shape) | exact for list behavior, partial for initializer shape |
| `test/foglet_bbs/tui/screens/board_list_test.exs` | screen behavior tests | command/assertion round-trip | itself + `test/foglet_bbs/tui/screens/thread_list_test.exs` route assertions | exact |

## Pattern Assignments

### `lib/foglet_bbs/tui/screens/board_list.ex`

Keep the existing list rendering contract:

```elixir
SelectionList.render(boards, ss.selected_index, fn {board, _idx, selected} ->
  unread = board_unread(board)
  unread_str = if unread > 0, do: " (#{unread} unread)", else: ""
  ListRow.render("#{board.name}#{unread_str}", selected, theme)
end)
```

Adopt explicit initializer pattern used elsewhere in audited screens:

```elixir
@spec init_screen_state(keyword()) :: map()
def init_screen_state(_opts \\ []), do: %{selected_index: 0}
```

Then replace repeated inline fallbacks:

```elixir
ss = get_in(state.screen_state, [:board_list]) || init_screen_state()
```

Loading affordance should stay in the same render branch (`state.board_list == nil`) and switch from static text to spinner-backed row using existing stateless spinner API:

```elixir
frame = div(System.monotonic_time(:millisecond), Spinner.frame_duration_ms())

row style: %{gap: 1} do
  [
    Spinner.render(frame, style: :line, theme: theme),
    text("Loading…", fg: theme.dim.fg)
  ]
end
```

Dead-code seam retention pattern:

```elixir
@doc false
# Test seam retained for direct unit tests. Production loading is owned by
# Foglet.TUI.App.do_update({:load_boards}, state).
@spec load_boards(map()) :: {map(), list()}
def load_boards(state) do
  ...
end
```

### `test/foglet_bbs/tui/screens/board_list_test.exs`

Preserve route behavior tests as-is:

- load seam populates list.
- `j`/`k` movement bounded.
- Enter opens thread list and dispatches `{:load_threads, board.id}`.
- `Q` returns to main menu.

Add focused assertions for Phase 5 goals:

```elixir
assert BoardList.init_screen_state() == %{selected_index: 0}
assert function_exported?(BoardList, :load_boards, 1)
assert _ = BoardList.render(%{state | board_list: nil})
```

Avoid chrome-internal assertions; keep tests BoardList-owned.

