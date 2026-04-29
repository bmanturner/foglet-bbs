# Phase 43: Large Screen Decomposition - Pattern Map

## PATTERN MAPPING COMPLETE

## Target Files

| New file | Role | Closest existing analog |
|----------|------|-------------------------|
| `lib/foglet_bbs/tui/screens/new_thread/render.ex` | Sibling render entry point for NewThread | Current `NewThread.render/2` plus helper family in `new_thread.ex` |
| `lib/foglet_bbs/tui/screens/login/render.ex` | Sibling render entry point for Login | Current `Login.render/2` plus helper family in `login.ex` |
| `lib/foglet_bbs/tui/screens/main_menu/render.ex` | Sibling render entry point for MainMenu | Current `MainMenu.render/2`, `nav_panel/3`, `oneliners_panel/2` |
| `lib/foglet_bbs/tui/screens/sysop/render.ex` | Sibling render entry point for Sysop | Current `Sysop.render/2`, `render_tab_body/3`, existing Sysop surface modules |
| `lib/foglet_bbs/tui/screens/account/render.ex` | Sibling render entry point for Account | Current `Account.render/2`, `render_tab_body/3`, existing Account surface modules |
| `lib/foglet_bbs/tui/screens/post_reader/render.ex` | Sibling render entry point for PostReader | Current `PostReader.render/2`, `render_post_content/5`, `PostCard.render/3` use |
| `lib/foglet_bbs/tui/SCREEN_CONTRACT.md` | Documentation update | Existing screen contract checklist |

## Existing Boundary Pattern

Screen modules implement the public screen contract and own reducer behavior:

```elixir
@behaviour Foglet.TUI.Screen

@impl true
@spec init(Context.t()) :: State.t()
def init(%Context{} = context), do: State.from_context(context)

@impl true
@spec update(term(), State.t(), Context.t()) :: {State.t(), [Effect.t()]}
def update(message, %State{} = state, %Context{} = context) do
  ...
end

@impl true
@spec render(State.t(), Context.t()) :: any()
def render(%State{} = state, %Context{} = context) do
  ...
end
```

Phase 43 should keep the first two callbacks in the top-level module and make `render/2` a thin delegation:

```elixir
alias Foglet.TUI.Screens.NewThread.Render

@impl true
@spec render(State.t(), Context.t()) :: any()
def render(%State{} = state, %Context{} = context), do: Render.render(state, context)
```

For `Sysop` and `Account`, preserve the existing fallback clause:

```elixir
def render(local_state, %Context{} = context),
  do: render(normalize_state(local_state, context), context)
```

and delegate only from the canonical `%State{}` clause.

## Render Module Shape

Render modules should use the same imports and aliases the moved helpers already use, minus reducer-only dependencies:

```elixir
defmodule Foglet.TUI.Screens.NewThread.Render do
  @moduledoc """
  Pure render entry point for the NewThread screen.
  """

  alias Foglet.TUI.Context
  alias Foglet.TUI.Screens.NewThread.State
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame

  import Raxol.Core.Renderer.View

  @spec render(State.t(), Context.t()) :: any()
  def render(%State{} = state, %Context{} = context) do
    ...
  end
end
```

Keep `Effect`, domain context aliases, `Modal`, task modules, and reducer helpers out of render modules unless a helper is purely display data.

## Existing Surface Module Pattern

`Sysop` and `Account` already have useful screen-owned surface modules. Render modules should call these rather than absorbing their code:

- `Foglet.TUI.Screens.Sysop.BoardsView.render/2`
- `Foglet.TUI.Screens.Sysop.UsersView.render/2`
- `Foglet.TUI.Screens.Sysop.SiteForm.render/2`
- `Foglet.TUI.Screens.Sysop.LimitsForm.render/2`
- `Foglet.TUI.Screens.Account.ProfileForm.render/2`
- `Foglet.TUI.Screens.Account.PrefsForm.render/2`
- `Foglet.TUI.Screens.Account.SSHKeysSurface.render/2`
- `Foglet.TUI.Screens.Shared.InvitesSurface.render/2`

This follows D-08 from the phase context.

## Widget And Theme Pattern

Moved render code should continue to route display through:

- `Foglet.TUI.Theme.from_context/1` or existing state/theme helpers
- `Foglet.TUI.Theme.from_state/1` where the render model is intentionally App-shaped
- `Foglet.TUI.Widgets.Chrome.ScreenFrame.render/4`
- `Foglet.TUI.Widgets.Input.Tabs.render/3`
- `Foglet.TUI.Widgets.List.SelectionList.render/3`
- `Foglet.TUI.Widgets.List.ListRow.render/3`
- `Foglet.TUI.Widgets.Composer.EditorFrame.render/1`
- `Foglet.TUI.Widgets.Post.MarkdownBody.render/2`
- `Foglet.TUI.Widgets.Post.PostCard.render/3`

Do not introduce hardcoded color atoms in new render modules.

## Test Patterns

Prefer behavior and structure:

- reducer/effect tests keep calling `Screen.update/3`;
- smoke tests keep using existing layout helpers or `rtk mix foglet.tui.render`;
- source-shape tests can assert `defmodule Foglet.TUI.Screens.<Screen>.Render` exists and top-level screen modules delegate to it;
- avoid tests that only assert UI text exists.

Useful verification greps:

```bash
rtk rg -n "defmodule Foglet\\.TUI\\.Screens\\.(NewThread|Login|MainMenu|Sysop|Account|PostReader)\\.Render" lib/foglet_bbs/tui/screens
rtk rg -n "Render\\.render\\(" lib/foglet_bbs/tui/screens/{new_thread,login,main_menu,sysop,account,post_reader}.ex
rtk rg -n "Effect\\.|Repo\\.|PubSub|Config\\.put|Effect\\.task" lib/foglet_bbs/tui/screens/*/render.ex
```

