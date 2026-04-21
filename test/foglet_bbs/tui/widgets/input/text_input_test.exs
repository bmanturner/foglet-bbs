defmodule Foglet.TUI.Widgets.Input.TextInputTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Input.TextInput

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

  describe "init/1" do
    test "test 2 — default value produces struct with empty raxol_state value" do
      state = TextInput.init([])
      assert Map.get(state.raxol_state, :value) == ""
    end

    test "test 3 — supplied value round-trips through struct" do
      state = TextInput.init(value: "hello")
      assert Map.get(state.raxol_state, :value) == "hello"
    end

    test "test 10 — mask_char option causes render to not show raw value" do
      state = TextInput.init(value: "secret", mask_char: "*")
      result = TextInput.render(state, theme: theme())
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)
      refute serialized =~ "secret"
    end
  end

  describe "handle_event/2 (D-14)" do
    test "test 4 — character input changes state" do
      state = TextInput.init(value: "")
      {new_state, _action} = TextInput.handle_event(%{key: :char, char: "a"}, state)
      assert new_state != state
    end

    test "test 5 — Enter returns :submitted action" do
      state = TextInput.init(value: "hello")
      {_new_state, action} = TextInput.handle_event(%{key: :enter}, state)
      assert action == :submitted
    end

    test "test 6 — Esc returns :cancelled action" do
      state = TextInput.init(value: "hello")
      {_new_state, action} = TextInput.handle_event(%{key: :escape}, state)
      assert action == :cancelled
    end

    test "test 7 — purity: same input + event -> same output" do
      state = TextInput.init(value: "test")
      result1 = TextInput.handle_event(%{key: :enter}, state)
      result2 = TextInput.handle_event(%{key: :enter}, state)
      assert result1 == result2
    end
  end

  describe "render/2 — smoke (D-18)" do
    test "test 1 — returns a non-nil map with :type key" do
      state = TextInput.init(value: "")
      result = TextInput.render(state, theme: theme())
      refute is_nil(result)
      assert is_map(result)
      assert Map.has_key?(result, :type)
    end

    test "render with value shows text in output" do
      state = TextInput.init(value: "mytext")
      result = TextInput.render(state, theme: theme())
      flat = flatten_text(result)
      assert flat =~ "mytext"
    end
  end

  describe "render/2 — theme hygiene (D-18)" do
    test "test 8 — no hardcoded color atoms in rendered tree" do
      state = TextInput.init(value: "hello")
      result = TextInput.render(state, theme: theme())
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)

      for color <- ~w(red green cyan yellow blue magenta white black) do
        refute serialized =~ ":#{color}",
               "TextInput leaked :#{color} atom in serialized tree"
      end
    end

    test "test 9 — alt-theme produces different rendered output" do
      state = TextInput.init(value: "hello")
      default_result = TextInput.render(state, theme: theme())
      danger_result = TextInput.render(state, theme: alt_theme())
      refute inspect(default_result, printable_limit: :infinity, limit: :infinity) ==
               inspect(danger_result, printable_limit: :infinity, limit: :infinity)
    end
  end
end
