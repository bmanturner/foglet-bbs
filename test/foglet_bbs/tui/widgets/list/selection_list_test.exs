defmodule Foglet.TUI.Widgets.List.SelectionListTest do
  use ExUnit.Case, async: true

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.List.SelectionList

  defp distinctive_theme do
    %Theme{
      dim: %{fg: "#selection-dim"},
      selected: %{fg: "#selection-selected"},
      unselected: %{fg: "#selection-unselected"}
    }
  end

  describe "render/4 — theme hygiene (D-18)" do
    test "empty state uses theme.dim when the widget owns visible styling" do
      theme = distinctive_theme()

      tree =
        SelectionList.render(
          [],
          0,
          fn {_item, _idx, _selected?} ->
            text("unused")
          end, theme: theme)

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
          end, theme: theme)

      serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)

      assert serialized =~ "A"
      assert serialized =~ "B"
      assert serialized =~ theme.selected.fg
      assert serialized =~ theme.unselected.fg
    end
  end
end
