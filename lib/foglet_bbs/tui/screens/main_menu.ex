defmodule Foglet.TUI.Screens.MainMenu do
  @moduledoc "BBS main menu — primary screen after login (SSH-07, SSH-08)."

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame

  import Raxol.Core.Renderer.View

  @menu_items [
    {"B", "Browse Boards"},
    {"C", "Compose New Thread"},
    {"Q", "Logout"}
  ]

  @spec render(map()) :: any()
  def render(state) do
    handle = state.current_user && state.current_user.handle
    theme = (Map.get(state, :session_context) || %{}) |> Map.get(:theme) || Theme.default()

    content =
      column style: %{gap: 0} do
        [text("Welcome back, #{handle || "guest"}.", fg: theme.primary.fg), text("")] ++
          Enum.map(@menu_items, fn {k, label} ->
            text("  [#{k}] #{label}", fg: theme.primary.fg)
          end)
      end

    ScreenFrame.render(state, "Main Menu", content, [
      {"B", "Boards"},
      {"C", "Compose"},
      {"Q", "Logout"}
    ])
  end

  @spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
  def handle_key(%{key: :char, char: c}, state) when c in ["b", "B"] do
    {:update, %{state | current_screen: :board_list}, [{:load_boards}]}
  end

  def handle_key(%{key: :char, char: c}, state) when c in ["c", "C"] do
    {w, _h} = state.terminal_size || {80, 24}
    ss = Foglet.TUI.Screens.NewThread.init_screen_state(width: w)
    new_screen_state = Map.put(state.screen_state, :new_thread, ss)

    {:update, %{state | current_screen: :new_thread, screen_state: new_screen_state},
     [{:load_boards_for_new_thread}]}
  end

  def handle_key(%{key: :char, char: c}, state) when c in ["q", "Q"] do
    {:update, state, [{:terminate, :logout}]}
  end

  def handle_key(_key, _state), do: :no_match
end
