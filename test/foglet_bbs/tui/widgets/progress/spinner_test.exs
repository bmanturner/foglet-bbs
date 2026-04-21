defmodule Foglet.TUI.Widgets.Progress.SpinnerTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Progress.Spinner

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

  describe "render/2 — smoke (D-18)" do
    test "returns a non-nil result at frame 0" do
      result = Spinner.render(0, theme: theme())
      refute is_nil(result)
    end

    test "default style uses @default_style (:line)" do
      # :line style has 4 frames: [|, /, -, \]
      # Renders without error using the default
      result = Spinner.render(0, theme: theme())
      refute is_nil(result)
    end

    test "frame-index advance produces different glyph" do
      t = theme()
      glyph_0 = flatten_text(Spinner.render(0, theme: t))
      glyph_1 = flatten_text(Spinner.render(1, theme: t))
      assert glyph_0 != glyph_1, "Expected frame 0 and frame 1 to produce different glyphs"
    end

    test "theme slot: rendered output contains accent.fg color" do
      t = theme()
      result = Spinner.render(0, theme: t)
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)
      assert serialized =~ to_string(t.accent.fg)
    end
  end

  describe "render/2 — theme hygiene (D-18)" do
    test "no hardcoded color atoms appear in the rendered output" do
      tree = Spinner.render(0, theme: theme())
      serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)

      refute serialized =~ ":red", "Spinner leaked :red atom"
      refute serialized =~ ":green", "Spinner leaked :green atom"
      refute serialized =~ ":yellow", "Spinner leaked :yellow atom"
      refute serialized =~ ":cyan", "Spinner leaked :cyan atom"
      refute serialized =~ ":magenta", "Spinner leaked :magenta atom"
      refute serialized =~ ":blue", "Spinner leaked :blue atom"
      refute serialized =~ ":white", "Spinner leaked :white atom"
      refute serialized =~ ":black", "Spinner leaked :black atom"
    end

    test "alt-theme differential: default vs danger produce different serialized output" do
      default_tree = Spinner.render(0, theme: theme())
      danger_tree = Spinner.render(0, theme: alt_theme())

      s1 = inspect(default_tree, printable_limit: :infinity, limit: :infinity)
      s2 = inspect(danger_tree, printable_limit: :infinity, limit: :infinity)

      assert s1 != s2, "Expected different rendering with different themes"
    end
  end
end
