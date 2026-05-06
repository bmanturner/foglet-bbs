defmodule Foglet.TUI.Widgets.Input.RadioGroupTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.WidgetHelpers,
    only: [flatten_text: 1, color_atom_leaked?: 2, color_names: 0, assert_text_run: 3]

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Input.RadioGroup

  defp theme, do: Theme.default()
  defp alt_theme, do: Theme.resolve(:danger)

  defp distinctive_theme do
    %Theme{
      selected: %{fg: "#radio-selected", bg: "#radio-selected-bg"},
      unselected: %{fg: "#radio-unselected"},
      dim: %{fg: "#radio-dim"}
    }
  end

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

    test "selected semantic marker appears exactly once when selected_index = 0" do
      result = RadioGroup.render(["One", "Two", "Three"], 0, theme: theme())
      flat = flatten_text(result)
      occurrences = flat |> String.split("●") |> length() |> Kernel.-(1)
      assert occurrences == 1
    end

    test "unselected semantic markers appear twice for 3 options with selected_index = 0" do
      result = RadioGroup.render(["One", "Two", "Three"], 0, theme: theme())
      flat = flatten_text(result)
      occurrences = flat |> String.split("◇") |> length() |> Kernel.-(1)
      assert occurrences == 2
    end

    test "semantic selected row does not duplicate focus arrow and radio marker" do
      result = RadioGroup.render(["One", "Two", "Three"], 0, theme: theme())
      flat = flatten_text(result)
      assert String.starts_with?(flat, "● One")
      assert flat =~ "◇ Two"
      assert flat =~ "◇ Three"
      refute flat =~ "> (o)"
    end

    test "selected option uses theme.selected.fg" do
      t = theme()
      result = RadioGroup.render(["One", "Two"], 0, theme: t)
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)
      assert serialized =~ t.selected.fg
    end

    test "unselected options use theme.unselected.fg" do
      t = theme()
      result = RadioGroup.render(["One", "Two"], 0, theme: t)
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)
      assert serialized =~ t.unselected.fg
    end
  end

  describe "render/3 — theme hygiene (D-18)" do
    test "semantic visual contract styles selected, unselected, and disabled rows" do
      t = distinctive_theme()

      tree =
        RadioGroup.render(["Alpha", "Beta", "Gamma"], 0,
          disabled_indices: [2],
          theme: t
        )

      assert flatten_text(tree) == "● Alpha◇ Beta◇ Gamma"
      assert_text_run(tree, "● Alpha", fg: t.selected.fg, bg: t.selected.bg, style: [:bold])
      assert_text_run(tree, "◇ Beta", fg: t.unselected.fg)
      assert_text_run(tree, "◇ Gamma", fg: t.dim.fg, style: [:dim])
    end

    test "ascii marker_style preserves legacy scaffolding output" do
      tree = RadioGroup.render(["a", "b"], 0, marker_style: :ascii, theme: theme())
      flat = flatten_text(tree)

      assert flat =~ "> (o) a"
      assert flat =~ "  ( ) b"
    end

    test "no hardcoded color atoms leak into the tree (IN-03)" do
      tree = RadioGroup.render(["One", "Two", "Three"], 1, theme: theme())
      serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)

      for color <- color_names() do
        refute color_atom_leaked?(serialized, color), "leaked :#{color}"
      end
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

      on_count = flat |> String.split("●") |> length() |> Kernel.-(1)
      assert on_count == 1

      off_count = flat |> String.split("◇") |> length() |> Kernel.-(1)
      assert off_count == 2

      assert flat =~ "● c"
    end
  end

  describe "render/3 — out-of-range selected_index (WR-02)" do
    test "index above last option clamps to last (still one (o) marker)" do
      result = RadioGroup.render(["a", "b"], 5, theme: theme())
      flat = flatten_text(result)
      on_count = flat |> String.split("●") |> length() |> Kernel.-(1)
      assert on_count == 1
      assert flat =~ "● b"
    end

    test "negative index clamps to 0 (first option highlighted)" do
      result = RadioGroup.render(["a", "b"], -1, theme: theme())
      flat = flatten_text(result)
      on_count = flat |> String.split("●") |> length() |> Kernel.-(1)
      assert on_count == 1
      assert flat =~ "● a"
    end

    test "empty options list renders nothing selectable (no crash)" do
      result = RadioGroup.render([], 0, theme: theme())
      flat = flatten_text(result)
      refute flat =~ "●"
      refute flat =~ "◇"
    end
  end
end
