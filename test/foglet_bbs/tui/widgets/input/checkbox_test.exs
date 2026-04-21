defmodule Foglet.TUI.Widgets.Input.CheckboxTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Input.Checkbox

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

  describe "render/2 — smoke (D-18)" do
    test "returns a non-nil Raxol element with :type key" do
      result = Checkbox.render("Remember me", checked?: true, theme: theme())
      refute is_nil(result)
      assert is_map(result)
      assert Map.has_key?(result, :type)
    end

    test "checked marker [x] appears when checked?: true" do
      result = Checkbox.render("Remember me", checked?: true, theme: theme())
      assert flatten_text(result) =~ "[x]"
    end

    test "unchecked marker [ ] appears when checked?: false" do
      result = Checkbox.render("Remember me", checked?: false, theme: theme())
      assert flatten_text(result) =~ "[ ]"
    end

    test "label appears in the rendered text" do
      result = Checkbox.render("Remember me", checked?: true, theme: theme())
      assert flatten_text(result) =~ "Remember me"
    end

    test "checked state uses theme.selected.fg" do
      t = theme()
      result = Checkbox.render("x", checked?: true, theme: t)
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)
      assert serialized =~ to_string(t.selected.fg)
    end

    test "unchecked state uses theme.unselected.fg" do
      t = theme()
      result = Checkbox.render("x", checked?: false, theme: t)
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)
      assert serialized =~ to_string(t.unselected.fg)
    end

    test "disabled uses theme.dim.fg regardless of checked?" do
      t = theme()

      for checked? <- [true, false] do
        result = Checkbox.render("x", checked?: checked?, disabled: true, theme: t)
        serialized = inspect(result, printable_limit: :infinity, limit: :infinity)

        assert serialized =~ to_string(t.dim.fg),
               "disabled (checked?=#{checked?}) must use dim.fg"
      end
    end

    test "omitting :disabled defaults to false (uses selected/unselected, not dim)" do
      t = theme()
      result = Checkbox.render("x", checked?: true, theme: t)
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)

      # Should use selected.fg, not dim.fg (since dim.fg != selected.fg in default theme)
      assert serialized =~ to_string(t.selected.fg)
    end
  end

  describe "render/2 — theme hygiene (D-18)" do
    test "no hardcoded color atoms leak into the tree" do
      for scenario <- [
            [checked?: true, theme: theme()],
            [checked?: false, theme: theme()],
            [checked?: true, disabled: true, theme: theme()]
          ] do
        tree = Checkbox.render("x", scenario)
        serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)
        refute serialized =~ ":red", "scenario leaked :red"
        refute serialized =~ ":green", "scenario leaked :green"
        refute serialized =~ ":cyan", "scenario leaked :cyan"
        refute serialized =~ ":yellow", "scenario leaked :yellow"
        refute serialized =~ ":blue", "scenario leaked :blue"
        refute serialized =~ ":magenta", "scenario leaked :magenta"
        refute serialized =~ ":white", "scenario leaked :white"
        refute serialized =~ ":black", "scenario leaked :black"
      end
    end

    test "rendering with an alternate theme produces different color output" do
      default_tree = Checkbox.render("x", checked?: false, theme: theme())
      alt_tree = Checkbox.render("x", checked?: false, theme: alt_theme())

      default_out = inspect(default_tree, printable_limit: :infinity, limit: :infinity)
      alt_out = inspect(alt_tree, printable_limit: :infinity, limit: :infinity)

      refute default_out == alt_out,
             "theme slot change must produce a different tree"
    end
  end
end
