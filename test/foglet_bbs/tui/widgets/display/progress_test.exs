defmodule Foglet.TUI.Widgets.Display.ProgressTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.WidgetHelpers,
    only: [flatten_text: 1, color_atom_leaked?: 2, color_names: 0]

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Display.Progress

  defp theme, do: Theme.default()
  defp alt_theme, do: Theme.resolve(:danger)

  defp distinctive_theme do
    %Theme{
      border: %{fg: "#progress-border"},
      primary: %{fg: "#progress-primary"},
      accent: %{fg: "#progress-accent"},
      success: %{fg: "#progress-success"},
      dim: %{fg: "#progress-dim"}
    }
  end

  describe "render/2 — smoke (D-18)" do
    test "returns a non-nil result for 0.5 progress" do
      result = Progress.render(0.5, theme: theme())
      refute is_nil(result)
    end

    test "label appears in flattened text when passed" do
      result = Progress.render(0.5, label: "Loading", theme: theme())
      flat = flatten_text(result)
      assert flat =~ "Loading"
    end
  end

  describe "render/2 — theme hygiene (D-18, Pitfall 8)" do
    test "progress fill, track, border, label, and percentage use theme slots" do
      t = distinctive_theme()
      tree = Progress.render(0.5, label: "Loading", theme: t)
      serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)

      assert serialized =~ t.accent.fg
      assert serialized =~ t.dim.fg
      assert serialized =~ t.border.fg
      assert serialized =~ t.primary.fg
    end

    test "complete progress uses theme.success for fill" do
      t = distinctive_theme()
      tree = Progress.render(1.0, theme: t)
      serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)

      assert serialized =~ t.success.fg
    end

    test "Pitfall 8 is documented in moduledoc" do
      assert {:docs_v1, _, _, _, %{"en" => moduledoc}, _, _} = Code.fetch_docs(Progress)
      assert moduledoc =~ "Pitfall 8"
    end

    test "no hardcoded color atoms appear in the rendered output (IN-03)" do
      tree = Progress.render(0.5, theme: theme())
      serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)

      for color <- color_names() do
        refute color_atom_leaked?(serialized, color),
               "Progress leaked :#{color} atom: #{serialized}"
      end
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
