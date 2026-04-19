defmodule Foglet.TUI.Screens.MainMenu do
  @moduledoc "BBS main menu — primary screen after login (SSH-07, SSH-08)."

  alias Foglet.TUI.Widgets.{KeyBar, StatusBar}

  import Raxol.Core.Renderer.View

  @menu_items [
    {"B", "Browse Boards"},
    {"C", "Compose New Thread"},
    {"Q", "Logout"}
  ]

  @spec render(map()) :: any()
  def render(state) do
    handle = state.current_user && state.current_user.handle

    box style: %{border: :single, padding: 1} do
      column style: %{gap: 0, justify_content: :space_between} do
        [
          column style: %{gap: 0} do
            [
              StatusBar.render(%{handle: handle, location: "Main Menu"}),
              divider(),
              column style: %{gap: 0} do
                [text("Welcome back, #{handle || "guest"}.", fg: :green), text("")] ++
                  Enum.map(@menu_items, fn {k, label} ->
                    text("  [#{k}] #{label}", fg: :green)
                  end)
              end
            ]
          end,
          KeyBar.render([{"B", "Boards"}, {"C", "Compose"}, {"Q", "Logout"}])
        ]
      end
    end
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
