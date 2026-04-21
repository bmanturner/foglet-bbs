defmodule Foglet.TUI.Screens.MainMenu do
  @moduledoc """
  BBS main menu — primary screen after login (SSH-07, SSH-08).

  MainMenu is intentionally stateless: no `screen_state[:main_menu]`.
  Future contributors should not add `init_screen_state/1` reflexively.

  `@menu_items` and `@menu_keys` intentionally duplicate data because menu rows and
  KeyBar hints have different formatting needs.

  The welcome line, spacer, and three menu rows stay intentionally sparse:
  future milestones own the reserved whitespace.
  """

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame

  import Raxol.Core.Renderer.View

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

  @spec render(map()) :: any()
  def render(state) do
    handle = state.current_user && state.current_user.handle
    theme = Theme.from_state(state)

    content =
      column style: %{gap: 0} do
        [text("Welcome back, #{handle || "guest"}.", fg: theme.primary.fg), text("")] ++
          Enum.map(@menu_items, fn {k, label} ->
            text("  [#{k}] #{label}", fg: theme.primary.fg)
          end)
      end

    ScreenFrame.render(state, "Main Menu", content, @menu_keys)
  end

  @spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
  def handle_key(%{key: :char, char: c}, state) when c in ["b", "B"] do
    {:update, %{state | current_screen: :board_list}, [{:load_boards}]}
  end

  def handle_key(%{key: :char, char: c}, state) when c in ["c", "C"] do
    {w, _h} = state.terminal_size || @default_terminal_size

    ss =
      Foglet.TUI.Screens.NewThread.init_screen_state(width: w)
      |> Map.put(:origin, :main_menu)

    new_screen_state = Map.put(state.screen_state, :new_thread, ss)

    {:update, %{state | current_screen: :new_thread, screen_state: new_screen_state},
     [{:load_boards_for_new_thread}]}
  end

  def handle_key(%{key: :char, char: c}, state) when c in ["q", "Q"] do
    {:update, state, [{:terminate, :logout}]}
  end

  def handle_key(_key, _state), do: :no_match
end
