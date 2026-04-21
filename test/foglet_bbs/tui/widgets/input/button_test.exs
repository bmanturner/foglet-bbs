defmodule Foglet.TUI.Widgets.Input.ButtonTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.WidgetHelpers,
    only: [flatten_text: 1, color_atom_leaked?: 2, color_names: 0]

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Input.Button

  defp theme, do: Theme.default()
  defp alt_theme, do: Theme.resolve(:danger)

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
      assert serialized =~ to_string(t.accent.fg)
    end

    test "danger role uses theme.error.fg" do
      t = theme()
      result = Button.render("Delete", role: :danger, theme: t)
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)
      assert serialized =~ to_string(t.error.fg)
    end

    test "success role uses theme.primary.fg" do
      t = theme()
      result = Button.render("OK", role: :success, theme: t)
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)
      assert serialized =~ to_string(t.primary.fg)
    end

    test "secondary role uses theme.primary.fg (no :bold)" do
      t = theme()
      result = Button.render("Cancel", role: :secondary, theme: t)
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)
      assert serialized =~ to_string(t.primary.fg)
    end

    test "disabled uses theme.dim.fg regardless of role" do
      t = theme()

      for role <- [:primary, :secondary, :danger, :success] do
        result = Button.render("x", role: role, disabled: true, theme: t)
        serialized = inspect(result, printable_limit: :infinity, limit: :infinity)

        assert serialized =~ to_string(t.dim.fg),
               "disabled #{role} button must use dim.fg"
      end
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
