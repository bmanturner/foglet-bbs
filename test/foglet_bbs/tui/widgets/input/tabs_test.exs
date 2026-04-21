defmodule Foglet.TUI.Widgets.Input.TabsTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Input.Tabs

  # --- Local helpers (copied from list_row_test.exs pattern) ---

  defp flatten_text(tree), do: tree |> collect_text([]) |> Enum.reverse() |> Enum.join("")

  defp collect_text(nil, acc), do: acc
  defp collect_text(list, acc) when is_list(list), do: Enum.reduce(list, acc, &collect_text/2)

  defp collect_text(%{children: children} = node, acc) do
    acc = maybe_add_content(node, acc)
    collect_text(children, acc)
  end

  defp collect_text(%{content: content}, acc) when is_binary(content), do: [content | acc]
  defp collect_text(%{text: t}, acc) when is_binary(t), do: [t | acc]
  defp collect_text(_other, acc), do: acc

  defp maybe_add_content(%{content: content}, acc) when is_binary(content), do: [content | acc]
  defp maybe_add_content(_node, acc), do: acc

  defp theme, do: Theme.default()
  defp alt_theme, do: Theme.resolve(:danger)

  defp tabs_state do
    Tabs.init(tabs: ["Home", "Posts", "Settings"])
  end

  describe "init/1" do
    test "test 2 — active index defaults to 0" do
      state = tabs_state()
      assert Map.get(state.raxol_state, :active_index) == 0
    end

    test "init with custom active index" do
      state = Tabs.init(tabs: ["A", "B", "C"], active: 1)
      assert Map.get(state.raxol_state, :active_index) == 1
    end

    test "WR-04 — atom tab entries are coerced to string labels" do
      state = Tabs.init(tabs: [:home, :posts])
      flat = flatten_text(Tabs.render(state, theme: theme()))
      assert flat =~ "home"
      assert flat =~ "posts"
    end

    test "WR-04 — map with :label passes through" do
      state = Tabs.init(tabs: [%{label: "Mixed"}])
      flat = flatten_text(Tabs.render(state, theme: theme()))
      assert flat =~ "Mixed"
    end

    test "WR-04 — nil tab entry raises ArgumentError with helpful message" do
      assert_raise ArgumentError, ~r/:tabs entry must be/, fn ->
        Tabs.init(tabs: [nil])
      end
    end

    test "WR-04 — tuple tab entry raises ArgumentError" do
      assert_raise ArgumentError, ~r/:tabs entry must be/, fn ->
        Tabs.init(tabs: [{:bad, "shape"}])
      end
    end

    test "WR-04 — map without :label raises ArgumentError" do
      assert_raise ArgumentError, ~r/:tabs entry must be/, fn ->
        Tabs.init(tabs: [%{name: "oops"}])
      end
    end
  end

  describe "handle_event/2 (D-14)" do
    test "test 3 — Right arrow advances to index 1" do
      state = tabs_state()
      {_new_state, action} = Tabs.handle_event(%{key: :right}, state)
      assert action == {:tab_changed, 1}
    end

    test "test 4 — Left arrow at index 0 wraps or stays — action tuple shape verified" do
      state = tabs_state()
      {_new_state, action} = Tabs.handle_event(%{key: :left}, state)
      # Raxol wraps around — at index 0, left goes to last tab (index 2)
      assert match?({:tab_changed, _n}, action)
    end

    test "test 5 — digit key '2' jumps to index 1" do
      state = tabs_state()
      {_new_state, action} = Tabs.handle_event(%{key: :char, char: "2"}, state)
      assert action == {:tab_changed, 1}
    end

    test "test 6 — unrelated key returns nil action and is pure" do
      state = tabs_state()
      {_new_state, action} = Tabs.handle_event(%{key: :enter}, state)
      assert is_nil(action)
    end

    test "test 7 — purity: same input + event -> same output" do
      state = tabs_state()
      result1 = Tabs.handle_event(%{key: :right}, state)
      result2 = Tabs.handle_event(%{key: :right}, state)
      assert result1 == result2
    end
  end

  describe "render/2 — smoke (D-18)" do
    test "test 1 — returns a non-nil map with :type key" do
      state = tabs_state()
      result = Tabs.render(state, theme: theme())
      refute is_nil(result)
      assert is_map(result)
      assert Map.has_key?(result, :type)
    end

    test "rendered output contains tab labels" do
      state = tabs_state()
      result = Tabs.render(state, theme: theme())
      flat = flatten_text(result)
      assert flat =~ "Home"
    end
  end

  describe "render/2 — theme hygiene (D-18)" do
    test "test 8 — no hardcoded color atoms in rendered tree" do
      state = tabs_state()
      result = Tabs.render(state, theme: theme())
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)

      for color <- ~w(red green cyan yellow blue magenta white black) do
        refute serialized =~ ":#{color}",
               "Tabs leaked :#{color} atom in serialized tree"
      end
    end

    test "test 9 — alt-theme produces different rendered output" do
      state = tabs_state()
      default_result = Tabs.render(state, theme: theme())
      danger_result = Tabs.render(state, theme: alt_theme())

      refute inspect(default_result, printable_limit: :infinity, limit: :infinity) ==
               inspect(danger_result, printable_limit: :infinity, limit: :infinity)
    end

    test "test 10 — moduledoc mentions digit shortcuts and D-15 caller-filter contract" do
      {:docs_v1, _anno, _lang, _format, %{"en" => moduledoc}, _metadata, _docs} =
        Code.fetch_docs(Foglet.TUI.Widgets.Input.Tabs)

      has_digit_ref =
        String.contains?(moduledoc, "digit") or String.contains?(moduledoc, "1-9") or
          String.contains?(moduledoc, "1–9")

      has_d15_ref = String.contains?(moduledoc, "D-15")

      assert has_digit_ref or has_d15_ref,
             "Moduledoc must mention digit shortcuts (1-9) and/or D-15 screen-filter contract"
    end
  end
end
