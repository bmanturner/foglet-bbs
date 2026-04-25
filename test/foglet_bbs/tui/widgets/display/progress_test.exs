defmodule Foglet.TUI.Widgets.Display.ProgressTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.WidgetHelpers,
    only: [flatten_text: 1, color_atom_leaked?: 2, color_names: 0, assert_text_run: 3]

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
      warning: %{fg: "#progress-warning"},
      error: %{fg: "#progress-error"},
      dim: %{fg: "#progress-dim"}
    }
  end

  describe "render/2 — smoke (D-18)" do
    test "label appears in flattened text when passed" do
      result = Progress.render(0.5, label: "Loading", theme: theme())
      flat = flatten_text(result)
      assert flat =~ "Loading"
    end
  end

  describe "render/2 — theme hygiene (D-18, Pitfall 8)" do
    test "compact mode is default and renders segmented progress glyphs" do
      t = distinctive_theme()
      tree = Progress.render(0.4, segments: 5, show_percentage: false, theme: t)

      assert flatten_text(tree) == "▰▰▱▱▱"
      assert_text_run(tree, "▰▰", fg: t.accent.fg)
      assert_text_run(tree, "▱▱▱", fg: t.dim.fg)
    end

    test "bracket mode preserves the legacy bar shape behind an option" do
      tree = Progress.render(0.5, mode: :bracket, width: 6, show_percentage: false, theme: theme())

      assert flatten_text(tree) == "[██  ]"
    end

    test "compact progress fill, track, label, and percentage use theme slots" do
      t = distinctive_theme()
      tree = Progress.render(0.5, label: "Loading", theme: t)
      serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)

      assert serialized =~ t.accent.fg
      assert serialized =~ t.dim.fg
      assert serialized =~ t.primary.fg
    end

    test "bracket mode uses theme border around the legacy bar" do
      t = distinctive_theme()
      tree = Progress.render(0.5, mode: :bracket, show_percentage: false, theme: t)
      serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)

      assert serialized =~ t.border.fg
    end

    test "complete progress uses theme.success for fill" do
      t = distinctive_theme()
      tree = Progress.render(1.0, theme: t)
      serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)

      assert serialized =~ t.success.fg
    end

    test "warning and error states use semantic threshold slots" do
      t = distinctive_theme()

      warning = Progress.render(0.85, theme: t)
      error = Progress.render(1.2, theme: t)

      assert inspect(warning, printable_limit: :infinity, limit: :infinity) =~ t.warning.fg
      assert inspect(error, printable_limit: :infinity, limit: :infinity) =~ t.error.fg
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
