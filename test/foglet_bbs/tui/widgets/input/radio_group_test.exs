defmodule Foglet.TUI.Widgets.Input.RadioGroupTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Input.RadioGroup

  # --- flatten_text helpers (copied verbatim from list_row_test.exs:9-24) ---

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

  describe "render/3 — smoke (D-18)" do
    test "returns a non-nil Raxol element" do
      result = RadioGroup.render(["One", "Two", "Three"], 0, theme: theme())
      refute is_nil(result)
      assert is_map(result)
      assert Map.has_key?(result, :type)
    end

    test "all option labels appear in the rendered text" do
      result = RadioGroup.render(["One", "Two", "Three"], 0, theme: theme())
      flat = flatten_text(result)
      assert flat =~ "One"
      assert flat =~ "Two"
      assert flat =~ "Three"
    end

    test "selected marker (o) appears exactly once when selected_index = 0" do
      result = RadioGroup.render(["One", "Two", "Three"], 0, theme: theme())
      flat = flatten_text(result)
      occurrences = flat |> String.split("(o)") |> length() |> Kernel.-(1)
      assert occurrences == 1
    end

    test "unselected markers ( ) appear twice for 3 options with selected_index = 0" do
      result = RadioGroup.render(["One", "Two", "Three"], 0, theme: theme())
      flat = flatten_text(result)
      occurrences = flat |> String.split("( )") |> length() |> Kernel.-(1)
      assert occurrences == 2
    end

    test "selected row starts with '> ' and unselected rows start with '  '" do
      result = RadioGroup.render(["One", "Two", "Three"], 0, theme: theme())
      flat = flatten_text(result)
      assert String.starts_with?(flat, "> ")
      assert flat =~ "  ( ) Two"
      assert flat =~ "  ( ) Three"
    end

    test "selected option uses theme.selected.fg" do
      t = theme()
      result = RadioGroup.render(["One", "Two"], 0, theme: t)
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)
      assert serialized =~ to_string(t.selected.fg)
    end

    test "unselected options use theme.unselected.fg" do
      t = theme()
      result = RadioGroup.render(["One", "Two"], 0, theme: t)
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)
      assert serialized =~ to_string(t.unselected.fg)
    end
  end

  describe "render/3 — theme hygiene (D-18)" do
    test "no hardcoded color atoms leak into the tree" do
      tree = RadioGroup.render(["One", "Two", "Three"], 1, theme: theme())
      serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)
      refute serialized =~ ":red", "leaked :red"
      refute serialized =~ ":green", "leaked :green"
      refute serialized =~ ":cyan", "leaked :cyan"
      refute serialized =~ ":yellow", "leaked :yellow"
      refute serialized =~ ":blue", "leaked :blue"
      refute serialized =~ ":magenta", "leaked :magenta"
      refute serialized =~ ":white", "leaked :white"
      refute serialized =~ ":black", "leaked :black"
    end

    test "rendering with an alternate theme produces different color output" do
      default_tree = RadioGroup.render(["a", "b"], 0, theme: theme())
      alt_tree = RadioGroup.render(["a", "b"], 0, theme: alt_theme())

      default_out = inspect(default_tree, printable_limit: :infinity, limit: :infinity)
      alt_out = inspect(alt_tree, printable_limit: :infinity, limit: :infinity)

      refute default_out == alt_out,
             "theme slot change must produce a different tree"
    end

    test "boundary — selected_index at end marks only the last option" do
      t = theme()
      result = RadioGroup.render(["a", "b", "c"], 2, theme: t)
      flat = flatten_text(result)

      # exactly one (o) marker
      on_count = flat |> String.split("(o)") |> length() |> Kernel.-(1)
      assert on_count == 1

      # exactly two ( ) markers
      off_count = flat |> String.split("( )") |> length() |> Kernel.-(1)
      assert off_count == 2

      # the selected marker is in a "> " prefixed row
      assert flat =~ "> (o) c"
    end
  end

  describe "render/3 — out-of-range selected_index (WR-02)" do
    test "index above last option clamps to last (still one (o) marker)" do
      result = RadioGroup.render(["a", "b"], 5, theme: theme())
      flat = flatten_text(result)
      on_count = flat |> String.split("(o)") |> length() |> Kernel.-(1)
      assert on_count == 1
      assert flat =~ "> (o) b"
    end

    test "negative index clamps to 0 (first option highlighted)" do
      result = RadioGroup.render(["a", "b"], -1, theme: theme())
      flat = flatten_text(result)
      on_count = flat |> String.split("(o)") |> length() |> Kernel.-(1)
      assert on_count == 1
      assert flat =~ "> (o) a"
    end

    test "empty options list renders nothing selectable (no crash)" do
      result = RadioGroup.render([], 0, theme: theme())
      flat = flatten_text(result)
      refute flat =~ "(o)"
      refute flat =~ "( )"
    end
  end
end
