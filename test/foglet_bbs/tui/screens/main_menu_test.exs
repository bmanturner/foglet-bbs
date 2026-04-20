defmodule Foglet.TUI.Screens.MainMenuTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Screens.MainMenu

  setup do
    state =
      %Foglet.TUI.App{
        current_screen: :main_menu,
        current_user: %Foglet.Accounts.User{id: "u1", handle: "alice", role: :user},
        session_context: %{},
        terminal_size: {80, 24}
      }
      |> Map.from_struct()

    %{state: state}
  end

  # ---------------------------------------------------------------------------
  # Tree-traversal helpers
  # ---------------------------------------------------------------------------

  # Recursively walks a view tree collecting all elements matching the predicate.
  defp collect(element, pred, acc \\ [])

  defp collect(element, pred, acc) when is_map(element) do
    acc = if pred.(element), do: [element | acc], else: acc
    children = Map.get(element, :children, [])
    collect(children, pred, acc)
  end

  defp collect(list, pred, acc) when is_list(list) do
    Enum.reduce(list, acc, fn el, acc -> collect(el, pred, acc) end)
  end

  defp collect(_other, _pred, acc), do: acc

  # Returns true if the element has justify_content: :space_between in its style.
  defp has_space_between?(el) do
    style = Map.get(el, :style, %{})
    is_map(style) and Map.get(style, :justify_content) == :space_between
  end

  # Returns true if the element looks like a divider primitive.
  defp divider?(el) when is_map(el) do
    # Raxol emits dividers as %{type: :line} or %{type: :border_line} in some versions.
    Map.get(el, :type) == :divider or
      (Map.get(el, :type) == :view and Map.get(el, :view_type) == :divider) or
      Map.get(el, :type) in [:line, :border_line, :divider, :horizontal_rule]
  end

  defp divider?(_), do: false

  # Checks if any parent's children list contains the StatusBar element
  # followed eventually by a divider. The StatusBar is identified as any
  # subtree containing a text with "Foglet BBS" in its content, so the
  # predicate is robust to wrapping the status bar in a box/row.
  defp has_divider_after_statusbar?(tree) do
    parents_with_children =
      collect(tree, fn el ->
        is_map(el) and is_list(Map.get(el, :children, nil))
      end)

    Enum.any?(parents_with_children, fn parent ->
      children = Map.get(parent, :children, [])

      children
      |> Enum.with_index()
      |> Enum.any?(fn {child, idx} ->
        subtree_contains_status_bar?(child) and
          Enum.any?(Enum.drop(children, idx + 1), &divider?/1)
      end)
    end)
  end

  # Returns true if el or any of its descendants is a text whose content
  # contains the status-bar prefix "Foglet BBS".
  defp subtree_contains_status_bar?(el) do
    collect(el, fn node ->
      is_map(node) and status_bar_text?(node)
    end) != []
  end

  defp status_bar_text?(el) do
    content =
      Map.get(el, :content) || Map.get(el, :text) || Map.get(el, :value) || ""

    is_binary(content) and String.contains?(content, "Foglet BBS")
  end

  # ---------------------------------------------------------------------------
  # Gap 1 test — justify_content: :space_between (Task 1)
  # ---------------------------------------------------------------------------

  test "render/1 outer column uses justify_content: :space_between (Gap 1)", %{state: state} do
    tree = MainMenu.render(state)
    found = collect(tree, &has_space_between?/1)

    assert found != [],
           "Expected at least one column with justify_content: :space_between in the rendered tree, found none.\nTree: #{inspect(tree, limit: 5)}"
  end

  # ---------------------------------------------------------------------------
  # Gap 2 test — divider() immediately after StatusBar (Task 1)
  # ---------------------------------------------------------------------------

  test "render/1 has a divider element after the StatusBar row (Gap 2)", %{state: state} do
    tree = MainMenu.render(state)

    assert has_divider_after_statusbar?(tree),
           "Expected a divider element to appear after the StatusBar row in the rendered tree.\nTree: #{inspect(tree, limit: 6)}"
  end

  # ---------------------------------------------------------------------------
  # Existing tests
  # ---------------------------------------------------------------------------

  test "render/1 does not crash", %{state: state} do
    assert _ = MainMenu.render(state)
  end

  test "'B'/'b' navigates to :board_list with {:load_boards} command", %{state: state} do
    {:update, s, cmds} = MainMenu.handle_key(%{key: :char, char: "B"}, state)
    assert s.current_screen == :board_list
    assert {:load_boards} in cmds

    {:update, s2, cmds2} = MainMenu.handle_key(%{key: :char, char: "b"}, state)
    assert s2.current_screen == :board_list
    assert {:load_boards} in cmds2
  end

  test "'C' navigates to :new_thread wizard and dispatches {:load_boards_for_new_thread}",
       %{state: state} do
    {:update, s, cmds} = MainMenu.handle_key(%{key: :char, char: "C"}, state)
    assert s.current_screen == :new_thread
    assert {:load_boards_for_new_thread} in cmds
    # Wizard screen_state initialised at the board step
    assert get_in(s, [:screen_state, :new_thread, :step]) == :board

    # lowercase 'c' same behaviour
    {:update, s2, cmds2} = MainMenu.handle_key(%{key: :char, char: "c"}, state)
    assert s2.current_screen == :new_thread
    assert {:load_boards_for_new_thread} in cmds2
  end

  test "'Q' emits {:terminate, :logout} command", %{state: state} do
    {:update, _, cmds} = MainMenu.handle_key(%{key: :char, char: "Q"}, state)
    assert {:terminate, :logout} in cmds
  end

  test "unknown key returns :no_match", %{state: state} do
    assert :no_match = MainMenu.handle_key(%{key: :char, char: "z"}, state)
  end
end
