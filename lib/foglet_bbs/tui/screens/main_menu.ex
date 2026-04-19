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
      column style: %{gap: 0} do
        [
          text(" Foglet BBS ", style: [:bold]),
          divider(),
          StatusBar.render(%{handle: handle, location: "Main Menu"}),
          column style: %{gap: 0} do
            [text("Welcome back, #{handle || "guest"}.", fg: :green), text("")] ++
              Enum.map(@menu_items, fn {k, label} ->
                text("  [#{k}] #{label}", fg: :green)
              end)
          end,
          KeyBar.render([{"B", "Boards"}, {"C", "Compose"}, {"Q", "Logout"}])
        ]
      end
    end
  end

  @spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
  def handle_key(%{key: key}, state) when key in ["b", "B"] do
    {:update, %{state | current_screen: :board_list}, [{:load_boards}]}
  end

  def handle_key(%{key: key}, state) when key in ["c", "C"] do
    {:update, %{state | current_screen: :post_composer, composer_draft: "", current_thread: nil},
     []}
  end

  def handle_key(%{key: key}, state) when key in ["q", "Q"] do
    {:update, state, [{:terminate, :logout}]}
  end

  def handle_key(_key, _state), do: :no_match
end
