# Phase 6: ThreadList — Pattern Map

**Mapped:** 2026-04-21
**Files analyzed:** 3
**Analogs found:** 3 / 3

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `lib/foglet_bbs/tui/screens/thread_list.ex` | list screen + key router + domain adapter seam | key event -> screen state -> command tuple | itself + `lib/foglet_bbs/tui/screens/board_list.ex` initializer/loading structure | exact for behavior, partial for loading affordance |
| `test/foglet_bbs/tui/screens/thread_list_test.exs` | screen behavior tests | command/assertion round-trip | itself + `test/foglet_bbs/tui/screens/board_list_test.exs` | exact |
| `test/foglet_bbs/threads_test.exs` | domain preload contract tests | query -> loaded relation assertions | existing thread context tests in same file | exact |

## Pattern Assignments

### `lib/foglet_bbs/tui/screens/thread_list.ex`

Keep current row rendering and sort contract:

```elixir
SelectionList.render(sorted, ss.selected_index, fn {thread, _idx, selected} ->
  render_thread_row(thread, selected, inner_width, theme)
end)
```

```elixir
{sticky, regular} = Enum.split_with(threads, &(Map.get(&1, :sticky, false) == true))
sort_by_recency(sticky) ++ sort_by_recency(regular)
```

Adopt initializer pattern used by audited list screens:

```elixir
@spec init_screen_state(keyword()) :: map()
def init_screen_state(_opts \\ []), do: %{selected_index: 0}
```

Replace repeated fallbacks:

```elixir
ss = get_in(state.screen_state, [:thread_list]) || init_screen_state()
```

Correct module probe pattern with explicit load guard:

```elixir
loaded? =
  case Code.ensure_loaded(threads_mod) do
    {:module, _} -> true
    {:error, _} -> false
  end

cond do
  loaded? and function_exported?(threads_mod, :list_threads, 2) -> ...
  loaded? and function_exported?(threads_mod, :list_threads, 1) -> ...
  true -> ...
end
```

### `test/foglet_bbs/tui/screens/thread_list_test.exs`

Preserve existing navigation and metadata assertions.
Add explicit checks for:

- `init_screen_state/1` returning `%{selected_index: 0}`.
- loading branch render when `current_thread_list == nil`.
- module-load guard path still selecting 2-arity when module is loaded and exports it.

### `test/foglet_bbs/threads_test.exs`

Use existing seeded-user/thread patterns and assert 2-arity contract returns `created_by` preloaded:

```elixir
assert Enum.all?(rows, fn row ->
  is_map(row.created_by) and is_binary(row.created_by.handle) and row.created_by.handle != ""
end)
```

This locks THREADS-04 against future preload regressions.
