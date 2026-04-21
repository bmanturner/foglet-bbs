defmodule Foglet.TUI.Widgets.Display.ProgressTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Display.Progress

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
    test "returns a non-nil result for 0.5 progress" do
      result = Progress.render(0.5, theme: theme())
      refute is_nil(result)
    end

    test "default width uses @default_width (40)" do
      result = Progress.render(0.5, theme: theme())
      refute is_nil(result)
    end

    test "label appears in flattened text when passed" do
      result = Progress.render(0.5, label: "Loading", theme: theme())
      flat = flatten_text(result)
      assert flat =~ "Loading"
    end

    test "boundary: 0.0 renders without crash" do
      result = Progress.render(0.0, theme: theme())
      refute is_nil(result)
    end

    test "boundary: 1.0 renders without crash" do
      result = Progress.render(1.0, theme: theme())
      refute is_nil(result)
    end

    test "integer 0 coerces to float without crash (WR-01)" do
      result = Progress.render(0, theme: theme())
      refute is_nil(result)
    end

    test "integer 1 coerces to float without crash (WR-01)" do
      result = Progress.render(1, theme: theme())
      refute is_nil(result)
    end

    test "out-of-range value above 1.0 is clamped (WR-01)" do
      result = Progress.render(1.5, theme: theme())
      refute is_nil(result)
    end

    test "negative value is clamped to 0.0 (WR-01)" do
      result = Progress.render(-0.5, theme: theme())
      refute is_nil(result)
    end
  end

  describe "render/2 — theme hygiene (D-18, Pitfall 8)" do
    test "Pitfall 8 is documented in moduledoc" do
      assert {:docs_v1, _, _, _, %{"en" => moduledoc}, _, _} = Code.fetch_docs(Progress)
      assert moduledoc =~ "Pitfall 8"
    end

    test "no :green atom leaks from Raxol's extract_colors/1 defaults" do
      tree = Progress.render(0.5, theme: theme())
      serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)
      refute serialized =~ ":green", "Progress leaked :green atom: #{serialized}"
    end

    test "no :black atom leaks from Raxol's extract_colors/1 defaults" do
      tree = Progress.render(0.5, theme: theme())
      serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)
      refute serialized =~ ":black", "Progress leaked :black atom: #{serialized}"
    end

    test "no :white atom leaks from Raxol's extract_colors/1 defaults" do
      tree = Progress.render(0.5, theme: theme())
      serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)
      refute serialized =~ ":white", "Progress leaked :white atom: #{serialized}"
    end

    test "no other hardcoded color atoms appear in the rendered output" do
      tree = Progress.render(0.5, theme: theme())
      serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)

      refute serialized =~ ":red", "Progress leaked :red atom"
      refute serialized =~ ":cyan", "Progress leaked :cyan atom"
      refute serialized =~ ":yellow", "Progress leaked :yellow atom"
      refute serialized =~ ":blue", "Progress leaked :blue atom"
      refute serialized =~ ":magenta", "Progress leaked :magenta atom"
    end

    test "alt-theme differential: default vs danger produce different serialized output" do
      default_tree = Progress.render(0.5, theme: theme())
      danger_tree = Progress.render(0.5, theme: alt_theme())

      s1 = inspect(default_tree, printable_limit: :infinity, limit: :infinity)
      s2 = inspect(danger_tree, printable_limit: :infinity, limit: :infinity)

      assert s1 != s2, "Expected different rendering with different themes"
    end
  end
end
