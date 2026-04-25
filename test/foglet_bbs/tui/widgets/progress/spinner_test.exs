defmodule Foglet.TUI.Widgets.Progress.SpinnerTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.WidgetHelpers,
    only: [flatten_text: 1, color_atom_leaked?: 2, color_names: 0, assert_text_run: 3]

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Progress.Spinner

  defp theme, do: Theme.default()
  defp alt_theme, do: Theme.resolve(:danger)

  defp distinctive_theme do
    %Theme{
      accent: %{fg: "#spinner-accent", style: [:bold]},
      dim: %{fg: "#spinner-dim"}
    }
  end

  describe "render/2 — smoke (D-18)" do
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
      assert serialized =~ t.accent.fg
    end

    test "message mode emits glyph and loading text as separate styled runs" do
      t = distinctive_theme()
      tree = Spinner.render(0, message: "Loading boards", theme: t)

      assert flatten_text(tree) =~ " Loading boards"
      assert_text_run(tree, "Loading boards", fg: t.dim.fg)

      serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)
      assert serialized =~ t.accent.fg
      assert serialized =~ t.dim.fg
    end
  end

  describe "render/2 — theme hygiene (D-18)" do
    test "no hardcoded color atoms appear in the rendered output (IN-03)" do
      tree = Spinner.render(0, theme: theme())
      serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)

      for color <- color_names() do
        refute color_atom_leaked?(serialized, color),
               "Spinner leaked :#{color} atom"
      end
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
