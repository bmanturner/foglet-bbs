# Phase 09: postreader - Pattern Map

**Mapped:** 2026-04-22  
**Files analyzed:** 2  
**Analogs found:** 2 / 2

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `lib/foglet_bbs/tui/screens/post_reader.ex` | component | event-driven | `lib/foglet_bbs/tui/screens/thread_list.ex` | exact |
| `test/foglet_bbs/tui/screens/post_reader_test.exs` | test | event-driven | `test/foglet_bbs/tui/screens/thread_list_test.exs` | exact |

## Pattern Assignments

### `lib/foglet_bbs/tui/screens/post_reader.ex` (component, event-driven)

**Analog:** `lib/foglet_bbs/tui/screens/thread_list.ex`

**Imports + screen wrapper pattern** (`lib/foglet_bbs/tui/screens/thread_list.ex:9-16`):
```elixir
alias Foglet.TimeAgo
alias Foglet.TUI.Screens.Domain
alias Foglet.TUI.Theme
alias Foglet.TUI.Widgets.Chrome.ScreenFrame
alias Foglet.TUI.Widgets.List.{ListRow, SelectionList}
alias Foglet.TUI.Widgets.Progress.Spinner

import Raxol.Core.Renderer.View
```

**Loading spinner render pattern** (`lib/foglet_bbs/tui/screens/thread_list.ex:37-48`):
```elixir
defp render_thread_content(state, _ss, theme) when state.current_thread_list == nil do
  column style: %{gap: 0} do
    [
      row style: %{gap: 1} do
        [
          Spinner.render(0, theme: theme, style: :dots),
          text("Loading...", fg: theme.dim.fg)
        ]
      end
    ]
  end
end
```

**Public callback contract seam pattern** (`lib/foglet_bbs/tui/screens/thread_list.ex:140-150`):
```elixir
# Production load orchestration is owned by Foglet.TUI.App.do_update({:load_threads, board_id}, state).
@doc false
@spec load_threads(map(), String.t()) :: {map(), list()}
def load_threads(state, board_id) do
  ctx = Map.get(state, :session_context) || %{}
  threads_mod = resolve_threads_module(ctx)

  user_id = state.current_user && state.current_user.id
  threads = dispatch_thread_load(threads_mod, board_id, user_id)
  {%{state | current_thread_list: threads}, []}
end
```

**Domain.get fallback parity pattern** (`lib/foglet_bbs/tui/screens/thread_list.ex:152-157`):
```elixir
defp resolve_threads_module(ctx) do
  case Domain.get(ctx, :threads) do
    {:ok, mod} -> mod
    {:error, :not_configured} -> Foglet.Threads
  end
end
```

### `test/foglet_bbs/tui/screens/post_reader_test.exs` (test, event-driven)

**Analog:** `test/foglet_bbs/tui/screens/thread_list_test.exs`

**State fixture shape pattern** (`test/foglet_bbs/tui/screens/thread_list_test.exs:130-143`):
```elixir
setup do
  state =
    %Foglet.TUI.App{
      current_screen: :thread_list,
      current_user: %Foglet.Accounts.User{id: "u1", handle: "alice"},
      current_board: %{id: "b1", name: "General", slug: "general"},
      session_context: %{domain: %{threads: FakeThreads}},
      terminal_size: {80, 24},
      current_thread_list: nil,
      screen_state: %{thread_list: %{selected_index: 0}}
    }
    |> Map.from_struct()
```

**Command tuple assertions pattern** (`test/foglet_bbs/tui/screens/thread_list_test.exs:188-192`):
```elixir
test "'Q' returns to :board_list and dispatches {:load_boards} (LIST-02)", %{state: state} do
  {:update, s, cmds} = ThreadList.handle_key(%{key: :char, char: "Q"}, state)
  assert s.current_screen == :board_list
  assert {:load_boards} in cmds
end
```

**Loading-branch render test pattern** (`test/foglet_bbs/tui/screens/thread_list_test.exs:217-220`):
```elixir
test "nil current_thread_list renders loading affordance", %{state: state} do
  flat = flatten_text(ThreadList.render(state))
  assert flat =~ "Loading..."
end
```

## Shared Patterns

### Domain Lookup + Explicit Fallback Branches
**Source:** `lib/foglet_bbs/tui/screens/domain.ex:35-43`  
**Apply to:** `post_reader.ex` load/flush/parse module resolution
```elixir
@spec get(map(), domain_key()) :: result()
def get(ctx, key) when key in @supported_keys do
  case get_in(ctx, [:domain, key]) do
    mod when is_atom(mod) and not is_nil(mod) -> {:ok, mod}
    _ -> {:error, :not_configured}
  end
end

def get(_ctx, _key), do: {:error, :not_configured}
```

### Spinner Composition Without Row Growth
**Source:** `lib/foglet_bbs/tui/screens/board_list.ex:36-49`  
**Apply to:** `post_reader.ex` loading branch
```elixir
frame = System.monotonic_time(:millisecond) |> abs() |> div(Spinner.frame_duration_ms())

column style: %{gap: 0} do
  [
    row(
      style: %{gap: 1},
      do: [
        Spinner.render(frame, style: :line, theme: theme),
        text("Loading…", fg: theme.dim.fg)
      ]
    )
  ]
end
```

### App Command Ownership for I/O Work
**Source:** `lib/foglet_bbs/tui/app.ex:337-343,433-443,469-477`  
**Apply to:** callback ownership checks (`load_posts/2`, `flush_read_pointers/2`)
```elixir
# process_screen_commands/2 converts I/O dispatch tuples returned by
# screens (e.g. {:load_boards}, {:load_threads, id}) into real
# Command.task structs ...
process_screen_commands(new_state, commands)
```
```elixir
defp do_update({:load_posts, thread_id, opts}, state) when is_list(opts) do
  ctx = Map.get(state, :session_context) || %{}
  posts_mod = get_in(ctx, [:domain, :posts]) || Foglet.Posts

  task =
    Command.task(fn ->
      {:posts_loaded, posts_mod.list_posts(thread_id), opts}
    end)

  {state, [task]}
end
```
```elixir
defp do_update({:flush_read_pointers, ctx}, state) do
  sc = Map.get(state, :session_context) || %{}
  boards_mod = get_in(sc, [:domain, :boards]) || Foglet.Boards
  threads_mod = get_in(sc, [:domain, :threads]) || Foglet.Threads
  user_id = ctx[:user_id] || (state.current_user && state.current_user.id)

  task = Command.task(fn -> flush_read_pointers_task(ctx, user_id, boards_mod, threads_mod) end)
  {state, [task]}
end
```

### Render Purity Boundary (No State Writes in `render_*`)
**Source:** `lib/foglet_bbs/tui/screens/post_reader.ex:77-83,330-338,363-383`  
**Apply to:** all PostReader render-path changes
```elixir
# render_post_content is a read-only function — the Viewport state built here
# is transient, not written back into screen_state.
{vp, _cmds} = Viewport.update({:set_visible_height, available_height}, ss.viewport)
{vp, _cmds} = Viewport.update({:set_children, body_lines}, vp)
```
```elixir
defp warm_cache(ss, state, post, w) do
  key = {post.id, w}
  if Map.has_key?(ss.render_cache, key), do: ss, else: %{ss | render_cache: Map.put(ss.render_cache, key, parse_body(state, post))}
end
```

## No Analog Found

None.

## Metadata

**Analog search scope:** `lib/foglet_bbs/tui/screens`, `lib/foglet_bbs/tui/widgets`, `lib/foglet_bbs/tui`, `test/foglet_bbs/tui/screens`, `test/foglet_bbs/tui`  
**Files scanned:** 10  
**Pattern extraction date:** 2026-04-22
