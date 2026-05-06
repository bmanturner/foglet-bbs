defmodule Foglet.TUI.Widgets.List.SelectionListTest do
  use ExUnit.Case, async: true

  import Raxol.Core.Renderer.View
  import Foglet.TUI.WidgetHelpers, only: [flatten_text: 1, assert_text_run: 3]

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.List.SelectionList

  defp distinctive_theme do
    %Theme{
      dim: %{fg: "#selection-dim"},
      selected: %{fg: "#selection-selected", bg: "#selection-selected-bg"},
      unselected: %{fg: "#selection-unselected"}
    }
  end

  describe "render/4 — theme hygiene (D-18)" do
    test "optional simple-label renderer emits canonical selected and normal row shape" do
      theme = distinctive_theme()

      tree = SelectionList.render(["Boards", "Account"], 0, theme: theme)

      assert flatten_text(tree) == "▌ Boards  Account"

      assert_text_run(tree, "▌ Boards",
        fg: theme.selected.fg,
        bg: theme.selected.bg,
        style: [:bold]
      )

      assert_text_run(tree, "  Account", fg: theme.unselected.fg)
    end

    test "optional simple-label renderer dims disabled rows" do
      theme = distinctive_theme()

      tree =
        SelectionList.render(
          [%{label: "Boards"}, %{label: "Sysop", disabled: true}],
          0,
          theme: theme
        )

      assert flatten_text(tree) == "▌ Boards  Sysop"
      assert_text_run(tree, "  Sysop", fg: theme.dim.fg, style: [:dim])
    end

    test "empty state uses theme.dim when the widget owns visible styling" do
      theme = distinctive_theme()

      tree =
        SelectionList.render(
          [],
          0,
          fn {_item, _idx, _selected?} ->
            text("unused")
          end,
          theme: theme
        )

      serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)

      assert serialized =~ "No items"
      assert serialized =~ theme.dim.fg
    end

    test "non-empty rows remain caller-rendered so row presentation stays external" do
      theme = distinctive_theme()

      tree =
        SelectionList.render(
          ["A", "B"],
          1,
          fn {item, _idx, selected?} ->
            fg = if selected?, do: theme.selected.fg, else: theme.unselected.fg
            text(item, fg: fg)
          end,
          theme: theme
        )

      serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)

      assert serialized =~ "A"
      assert serialized =~ "B"
      assert serialized =~ theme.selected.fg
      assert serialized =~ theme.unselected.fg
    end
  end
end
