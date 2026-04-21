# Phase 4: MainMenu — Pattern Map

**Mapped:** 2026-04-21
**Files analyzed:** 2
**Analogs found:** 2 / 2

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `lib/foglet_bbs/tui/screens/main_menu.ex` | stateless screen / router | event-driven screen navigation | itself + `lib/foglet_bbs/tui/screens/board_list.ex` for `@default_terminal_size` style | exact for behavior, partial for attribute style |
| `test/foglet_bbs/tui/screens/main_menu_test.exs` | screen test | command/assertion round-trip | itself + route assertions in other screen tests | exact |

## Pattern Assignments

### `lib/foglet_bbs/tui/screens/main_menu.ex`

**Keep:** stateless `render/1` + `handle_key/2` shape.

**Add:** attribute-driven literals rather than inline key lists / inline default terminal size.

Recommended pattern:

```elixir
@default_terminal_size {80, 24}

@menu_items [
  {"B", "Browse Boards"},
  {"C", "Compose New Thread"},
  {"Q", "Logout"}
]

@menu_keys [
  {"B", "Boards"},
  {"C", "Compose"},
  {"Q", "Logout"}
]
```

Compose path pattern:

```elixir
{w, _h} = state.terminal_size || @default_terminal_size

ss =
  Foglet.TUI.Screens.NewThread.init_screen_state(width: w)
  |> Map.put(:origin, :main_menu)
```

Render path pattern:

```elixir
theme = Theme.from_state(state)

content =
  column style: %{gap: 0} do
    [text("Welcome back, #{handle || "guest"}.", fg: theme.primary.fg), text("")] ++
      Enum.map(@menu_items, fn {k, label} ->
        text("  [#{k}] #{label}", fg: theme.primary.fg)
      end)
  end

ScreenFrame.render(state, "Main Menu", content, @menu_keys)
```

Moduledoc must explicitly document:

- intentionally stateless, no `screen_state[:main_menu]`
- `@menu_items` / `@menu_keys` duplication is load-bearing
- reserved whitespace is intentional

### `test/foglet_bbs/tui/screens/main_menu_test.exs`

Preserve route tests:

- `B` / `b` => `:board_list` + `{:load_boards}`
- `C` / `c` => `:new_thread` + `{:load_boards_for_new_thread}` + `origin: :main_menu`
- `Q` => `{:terminate, :logout}`
- unknown => `:no_match`

Prefer screen-owned assertions over chrome internals:

```elixir
assert get_in(s, [:screen_state, :new_thread, :step]) == :board
assert get_in(s, [:screen_state, :new_thread, :origin]) == :main_menu
```

If testing render content, assert strings that belong to MainMenu:

```elixir
"Welcome back, alice."
"  [B] Browse Boards"
"  [C] Compose New Thread"
"  [Q] Logout"
```

Avoid assertions about divider placement or `justify_content: :space_between` in this phase unless they are directly needed by the current file; those belong to screen chrome, not MainMenu.
