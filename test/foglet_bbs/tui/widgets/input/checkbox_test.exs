defmodule Foglet.TUI.Widgets.Input.CheckboxTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.WidgetHelpers,
    only: [flatten_text: 1, color_atom_leaked?: 2, color_names: 0, assert_text_run: 3]

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Input.Checkbox

  defp theme, do: Theme.default()
  defp alt_theme, do: Theme.resolve(:danger)

  defp distinctive_theme do
    %Theme{
      success: %{fg: "#checkbox-success"},
      error: %{fg: "#checkbox-error"},
      unselected: %{fg: "#checkbox-unselected"},
      dim: %{fg: "#checkbox-dim"}
    }
  end

  describe "render/2 — smoke (D-18)" do
    test "returns a non-nil Raxol element with :type key" do
      result = Checkbox.render("Remember me", checked?: true, theme: theme())
      refute is_nil(result)
      assert is_map(result)
      assert Map.has_key?(result, :type)
    end

    test "semantic checked marker appears when checked?: true" do
      result = Checkbox.render("Remember me", checked?: true, theme: theme())
      assert flatten_text(result) =~ "✓"
    end

    test "semantic unchecked marker appears when checked?: false" do
      result = Checkbox.render("Remember me", checked?: false, theme: theme())
      assert flatten_text(result) =~ "◇"
    end

    test "label appears in the rendered text" do
      result = Checkbox.render("Remember me", checked?: true, theme: theme())
      assert flatten_text(result) =~ "Remember me"
    end

    test "checked state uses theme.success.fg" do
      t = theme()
      result = Checkbox.render("x", checked?: true, theme: t)
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)
      assert serialized =~ t.success.fg
    end

    test "unchecked state uses theme.unselected.fg" do
      t = theme()
      result = Checkbox.render("x", checked?: false, theme: t)
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)
      assert serialized =~ t.unselected.fg
    end

    test "disabled uses theme.dim.fg regardless of checked?" do
      t = theme()

      for checked? <- [true, false] do
        result = Checkbox.render("x", checked?: checked?, disabled: true, theme: t)
        serialized = inspect(result, printable_limit: :infinity, limit: :infinity)

        assert serialized =~ t.dim.fg,
               "disabled (checked?=#{checked?}) must use dim.fg"
      end
    end

    test "omitting :disabled defaults to false (uses selected/unselected, not dim)" do
      t = theme()
      result = Checkbox.render("x", checked?: true, theme: t)
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)

      assert serialized =~ t.success.fg
    end
  end

  describe "render/2 — theme hygiene (D-18)" do
    test "semantic visual contract styles checked, unchecked, disabled, and error states" do
      t = distinctive_theme()

      checked = Checkbox.render("Subscribed", checked?: true, theme: t)
      unchecked = Checkbox.render("Available", checked?: false, theme: t)
      disabled = Checkbox.render("Locked", checked?: true, disabled: true, theme: t)
      error = Checkbox.render("Blocked", checked?: false, error: true, theme: t)

      assert flatten_text(checked) == "✓ Subscribed"
      assert flatten_text(unchecked) == "◇ Available"
      assert flatten_text(disabled) == "✓ Locked"
      assert flatten_text(error) == "× Blocked"

      assert_text_run(checked, "✓ Subscribed", fg: t.success.fg, style: [:bold])
      assert_text_run(unchecked, "◇ Available", fg: t.unselected.fg)
      assert_text_run(disabled, "✓ Locked", fg: t.dim.fg, style: [:dim])
      assert_text_run(error, "× Blocked", fg: t.error.fg, style: [:bold])
    end

    test "ascii marker_style preserves legacy checkbox markers" do
      assert Checkbox.render("x", checked?: true, marker_style: :ascii, theme: theme())
             |> flatten_text() == "[x] x"

      assert Checkbox.render("x", checked?: false, marker_style: :ascii, theme: theme())
             |> flatten_text() == "[ ] x"
    end

    test "no hardcoded color atoms leak into the tree (IN-03)" do
      scenarios = [
        [checked?: true, theme: theme()],
        [checked?: false, theme: theme()],
        [checked?: true, disabled: true, theme: theme()]
      ]

      for scenario <- scenarios, color <- color_names() do
        tree = Checkbox.render("x", scenario)
        serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)

        refute color_atom_leaked?(serialized, color),
               "scenario #{inspect(scenario)} leaked :#{color}"
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
