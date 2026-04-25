defmodule Foglet.TUI.Widgets.Input.ButtonTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.WidgetHelpers,
    only: [flatten_text: 1, color_atom_leaked?: 2, color_names: 0, assert_text_run: 3]

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Input.Button

  defp theme, do: Theme.default()
  defp alt_theme, do: Theme.resolve(:danger)

  defp distinctive_theme do
    %Theme{
      accent: %{fg: "#button-accent"},
      primary: %{fg: "#button-primary"},
      success: %{fg: "#button-success"},
      error: %{fg: "#button-error"},
      dim: %{fg: "#button-dim"},
      unselected: %{fg: "#button-unselected"}
    }
  end

  describe "render/2 — smoke (D-18)" do
    test "returns a non-nil Raxol element" do
      result = Button.render("Save", role: :primary, theme: theme())
      refute is_nil(result)
      assert is_map(result)
      assert Map.has_key?(result, :type)
    end

    test "label appears in the rendered text" do
      result = Button.render("Save", role: :primary, theme: theme())
      assert flatten_text(result) =~ "Save"
    end

    test "shortcut renders alongside label when provided" do
      result = Button.render("Save", role: :primary, shortcut: "Ctrl+S", theme: theme())
      assert flatten_text(result) =~ "Ctrl+S"
    end

    test "primary role uses theme.accent.fg" do
      t = theme()
      result = Button.render("Save", role: :primary, theme: t)
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)
      assert serialized =~ t.accent.fg
    end

    test "danger role uses theme.error.fg" do
      t = theme()
      result = Button.render("Delete", role: :danger, theme: t)
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)
      assert serialized =~ t.error.fg
    end

    test "success role uses theme.success.fg" do
      t = theme()
      result = Button.render("OK", role: :success, theme: t)
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)
      assert serialized =~ t.success.fg
    end

    test "secondary role uses theme.unselected.fg (no :bold)" do
      t = theme()
      result = Button.render("Cancel", role: :secondary, theme: t)
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)
      assert serialized =~ t.unselected.fg
    end

    test "disabled uses theme.dim.fg regardless of role" do
      t = theme()

      for role <- [:primary, :secondary, :danger, :success] do
        result = Button.render("x", role: role, disabled: true, theme: t)
        serialized = inspect(result, printable_limit: :infinity, limit: :infinity)

        assert serialized =~ t.dim.fg,
               "disabled #{role} button must use dim.fg"
      end
    end

    test "IN-04 — unknown :role falls back to :secondary styling (documented)" do
      t = theme()
      bogus_result = Button.render("x", role: :bogus_role, theme: t)
      secondary_result = Button.render("x", role: :secondary, theme: t)

      # The role_style/3 fallback makes unknown roles indistinguishable
      # from :secondary — pinning this contract here catches an
      # accidental change to strict-role validation.
      assert inspect(bogus_result) == inspect(secondary_result)
    end

    test "omitting :role defaults to @default_role (:secondary)" do
      t = theme()
      result_default = Button.render("Click", theme: t)
      result_secondary = Button.render("Click", role: :secondary, theme: t)

      default_out = inspect(result_default, printable_limit: :infinity, limit: :infinity)
      secondary_out = inspect(result_secondary, printable_limit: :infinity, limit: :infinity)

      assert default_out == secondary_out
    end
  end

  describe "render/2 — theme hygiene (D-18)" do
    test "shortcut key and command label are separate styled runs" do
      t = distinctive_theme()
      tree = Button.render("Save", role: :primary, shortcut: "Ctrl+S", theme: t)

      assert flatten_text(tree) == "Ctrl+S Save"
      assert_text_run(tree, "Ctrl+S ", fg: t.accent.fg, style: [:bold])
      assert_text_run(tree, "Save", fg: t.accent.fg, style: [:bold])
    end

    test "destructive labels stay boring and use the error slot" do
      t = distinctive_theme()
      tree = Button.render("Delete", role: :danger, shortcut: "D", theme: t)

      assert flatten_text(tree) == "D Delete"
      assert_text_run(tree, "D ", fg: t.accent.fg, style: [:bold])
      assert_text_run(tree, "Delete", fg: t.error.fg, style: [:bold])
      refute flatten_text(tree) =~ "!"
    end

    test "roles route through semantic theme slots" do
      t = distinctive_theme()

      expectations = [
        primary: t.accent.fg,
        secondary: t.unselected.fg,
        danger: t.error.fg,
        success: t.success.fg
      ]

      for {role, expected_fg} <- expectations do
        tree = Button.render("Button", role: role, theme: t)
        serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)

        assert serialized =~ expected_fg,
               "#{role} should use #{expected_fg}"
      end
    end

    test "disabled role routes through theme.dim" do
      t = distinctive_theme()
      tree = Button.render("Button", role: :success, disabled: true, theme: t)
      serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)

      assert serialized =~ t.dim.fg
      refute serialized =~ t.success.fg
    end

    test "no hardcoded color atoms leak into the tree (IN-03)" do
      for role <- [:primary, :secondary, :danger, :success],
          color <- color_names() do
        tree = Button.render("x", role: role, theme: theme())
        serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)

        refute color_atom_leaked?(serialized, color),
               "#{role} leaked :#{color}"
      end
    end

    test "rendering with an alternate theme produces different color output" do
      default_tree = Button.render("Save", role: :primary, theme: theme())
      alt_tree = Button.render("Save", role: :primary, theme: alt_theme())

      default_out = inspect(default_tree, printable_limit: :infinity, limit: :infinity)
      alt_out = inspect(alt_tree, printable_limit: :infinity, limit: :infinity)

      refute default_out == alt_out,
             "theme slot change must produce a different tree"
    end
  end
end
