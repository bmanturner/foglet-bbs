defmodule Foglet.TUI.Widgets.List.SmartListTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.WidgetHelpers,
    only: [flatten_text: 1, color_atom_leaked?: 2, color_names: 0]

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.List.SmartList

  defp theme, do: Theme.default()
  defp alt_theme, do: Theme.resolve(:danger)

  # Shared fixture: two-item single-select list
  defp two_item_fixture do
    SmartList.init(options: [{"A", 1}, {"B", 2}])
  end

  # Activate search focus in the raxol_state (required for character input processing)
  defp activate_search(state) do
    updated_rs = Map.put(state.raxol_state, :is_search_focused, true)
    %{state | raxol_state: updated_rs}
  end

  # ---------------------------------------------------------------------------
  # init/1
  # ---------------------------------------------------------------------------

  describe "init/1" do
    test "single-select default: multiple false, enable_search false, page_size 10" do
      st = SmartList.init(options: [{"A", 1}, {"B", 2}])

      assert st.multiple == false
      assert st.enable_search == false
      assert st.page_size == 10
      assert is_map(st.raxol_state)
      assert is_nil(st.last_action)
    end

    test "full option surface round-trips all four values" do
      st =
        SmartList.init(
          options: [{"X", :x}, {"Y", :y}],
          enable_search: true,
          multiple: true,
          page_size: 5
        )

      assert st.enable_search == true
      assert st.multiple == true
      assert st.page_size == 5
      assert st.raxol_state.enable_search == true
      assert st.raxol_state.multiple == true
      assert st.raxol_state.page_size == 5
    end
  end

  # ---------------------------------------------------------------------------
  # render/2 — smoke (D-18)
  # ---------------------------------------------------------------------------

  describe "render/2 — smoke (D-18)" do
    test "returns a non-nil map with :type key" do
      result = SmartList.render(two_item_fixture(), theme: theme())

      refute is_nil(result)
      assert is_map(result)
      assert Map.has_key?(result, :type)
    end

    test "rendered tree contains option labels" do
      result = SmartList.render(two_item_fixture(), theme: theme())
      flat = flatten_text(result)

      assert flat =~ "A"
      assert flat =~ "B"
    end
  end

  # ---------------------------------------------------------------------------
  # handle_event/2 (D-14)
  # ---------------------------------------------------------------------------

  describe "handle_event/2 (D-14)" do
    test "Down arrow moves focused_index" do
      st = two_item_fixture()
      before_idx = st.raxol_state.focused_index

      {new_st, _action} = SmartList.handle_event(%{key: :down}, st)

      assert new_st.raxol_state.focused_index != before_idx
    end

    test "Enter in single-select returns {:item_selected, value} for focused item" do
      # Default fixture: focused_index is 0, option {"A", 1}
      st = two_item_fixture()
      {_new_st, action} = SmartList.handle_event(%{key: :enter}, st)

      assert {:item_selected, 1} = action
    end

    test "search buffer grows after character input when search focused" do
      st =
        SmartList.init(
          options: [{"Alpha", 1}, {"Beta", 2}],
          enable_search: true
        )

      st = activate_search(st)

      {new_st, _action} = SmartList.handle_event(%{key: :char, char: "a"}, st)

      # search_buffer should now contain "a"
      assert new_st.raxol_state.search_buffer == "a"
    end

    test "multi-select Space toggles focused option in selected_indices" do
      st =
        SmartList.init(
          options: [{"A", 1}, {"B", 2}],
          multiple: true
        )

      before_size = MapSet.size(st.raxol_state.selected_indices)
      {new_st, _action} = SmartList.handle_event(%{key: :space}, st)
      after_size = MapSet.size(new_st.raxol_state.selected_indices)

      # Toggle should change the MapSet size (0 → 1)
      assert after_size != before_size
    end

    test "multi-select Enter returns {:items_selected, [values]} after toggling" do
      st =
        SmartList.init(
          options: [{"A", 1}, {"B", 2}],
          multiple: true
        )

      # Toggle item 0 via Space, then confirm via Enter
      {st_after_space, _} = SmartList.handle_event(%{key: :space}, st)
      {_final_st, action} = SmartList.handle_event(%{key: :enter}, st_after_space)

      assert {:items_selected, values} = action
      assert is_list(values)
      assert 1 in values
    end

    test "PageDown on large list action is nil when no page boundary crossed" do
      # With 10 items and page_size 10, page_down stays on page 0
      opts = Enum.map(1..10, fn i -> {"Item #{i}", i} end)
      st = SmartList.init(options: opts, page_size: 10)

      {_new_st, action} = SmartList.handle_event(%{key: :page_down}, st)

      # Within a single page: action is nil
      assert is_nil(action)
    end

    test "purity: same state + event produces same output" do
      st = two_item_fixture()

      {result1, action1} = SmartList.handle_event(%{key: :down}, st)
      {result2, action2} = SmartList.handle_event(%{key: :down}, st)

      assert result1.raxol_state.focused_index == result2.raxol_state.focused_index
      assert action1 == action2
    end
  end

  # ---------------------------------------------------------------------------
  # render/2 — theme hygiene (D-18)
  # ---------------------------------------------------------------------------

  describe "render/2 — theme hygiene (D-18)" do
    test "no hardcoded color atoms appear in serialized render tree (IN-03)" do
      result = SmartList.render(two_item_fixture(), theme: theme())
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)

      for color <- color_names() do
        refute color_atom_leaked?(serialized, color), "leaked :#{color} atom"
      end
    end

    test "alt-theme differential: default and danger themes produce different render trees" do
      result_default = SmartList.render(two_item_fixture(), theme: theme())
      result_alt = SmartList.render(two_item_fixture(), theme: alt_theme())

      s1 = inspect(result_default, printable_limit: :infinity, limit: :infinity)
      s2 = inspect(result_alt, printable_limit: :infinity, limit: :infinity)

      refute s1 == s2, "default and danger themes must produce different render trees"
    end
  end
end
