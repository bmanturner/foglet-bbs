defmodule Foglet.TUI.LayoutTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import ExUnit.CaptureLog
  import StreamData

  alias Foglet.TUI.Layout
  alias Foglet.TUI.Layout.Rect

  describe "vertical/2" do
    test "applies length, fill, and max constraints from top to bottom" do
      parent = %Rect{x: 2, y: 3, width: 10, height: 6}

      assert Layout.vertical(parent, [{:length, 2}, {:fill, 1}, {:max, 2}]) == [
               %Rect{x: 2, y: 3, width: 10, height: 2},
               %Rect{x: 2, y: 5, width: 10, height: 2},
               %Rect{x: 2, y: 7, width: 10, height: 2}
             ]
    end

    test "supports :min sugar and leaves trailing space when no constraint consumes it" do
      parent = %Rect{x: 0, y: 0, width: 8, height: 10}

      assert Layout.vertical(parent, [{:length, 3}, {:max, 2}]) == [
               %Rect{x: 0, y: 0, width: 8, height: 3},
               %Rect{x: 0, y: 3, width: 8, height: 2}
             ]

      assert [%Rect{height: 10}] = Layout.vertical(parent, [:min])
    end

    test "clips over-constrained input in declaration order and warns" do
      parent = %Rect{x: 0, y: 0, width: 8, height: 5}

      log =
        capture_log(fn ->
          assert Layout.vertical(parent, [{:length, 3}, {:length, 4}, {:length, 2}]) == [
                   %Rect{x: 0, y: 0, width: 8, height: 3},
                   %Rect{x: 0, y: 3, width: 8, height: 2},
                   %Rect{x: 0, y: 5, width: 8, height: 0}
                 ]
        end)

      assert log =~ "clipped over-constrained vertical layout"
    end
  end

  describe "horizontal/2" do
    test "applies percent, min, and weighted fill constraints from left to right" do
      parent = %{x: 4, y: 2, width: 20, height: 6}

      assert Layout.horizontal(parent, [{:percent, 25}, {:min, 3}, {:fill, 2}]) == [
               %Rect{x: 4, y: 2, width: 5, height: 6},
               %Rect{x: 9, y: 2, width: 7, height: 6},
               %Rect{x: 16, y: 2, width: 8, height: 6}
             ]
    end

    test "caps max constraints instead of stretching them to the parent edge" do
      parent = %Rect{x: 0, y: 0, width: 10, height: 3}

      assert Layout.horizontal(parent, [{:length, 3}, {:max, 2}]) == [
               %Rect{x: 0, y: 0, width: 3, height: 3},
               %Rect{x: 3, y: 0, width: 2, height: 3}
             ]
    end
  end

  describe "center/2" do
    test "centers tuple and map sizes" do
      parent = %Rect{x: 1, y: 2, width: 9, height: 5}

      assert Layout.center(parent, {4, 2}) == %Rect{x: 3, y: 3, width: 4, height: 2}

      assert Layout.center(parent, %{width: 5, height: 3}) == %Rect{
               x: 3,
               y: 3,
               width: 5,
               height: 3
             }
    end

    test "clips oversized centered children and warns" do
      parent = %Rect{x: 1, y: 2, width: 9, height: 5}

      log =
        capture_log(fn ->
          assert Layout.center(parent, {12, 9}) == %Rect{x: 1, y: 2, width: 9, height: 5}
        end)

      assert log =~ "clipped over-constrained center layout"
    end
  end

  property "fitting horizontal constraints produce non-overlapping rects inside the parent" do
    check all(
            width <- integer(1..120),
            constraints <- fitting_constraints(width),
            max_runs: 100
          ) do
      parent = %Rect{x: 3, y: 5, width: width, height: 7}
      rects = Layout.horizontal(parent, constraints)

      assert Enum.all?(rects, &inside?(&1, parent))
      assert ordered_non_overlapping?(rects, :horizontal)
    end
  end

  property "fitting vertical constraints produce non-overlapping rects inside the parent" do
    check all(
            height <- integer(1..80),
            constraints <- fitting_constraints(height),
            max_runs: 100
          ) do
      parent = %Rect{x: 3, y: 5, width: 13, height: height}
      rects = Layout.vertical(parent, constraints)

      assert Enum.all?(rects, &inside?(&1, parent))
      assert ordered_non_overlapping?(rects, :vertical)
    end
  end

  defp fitting_constraints(total) do
    constraint =
      one_of([
        integer(0..20) |> map(&{:length, &1}),
        integer(0..20) |> map(&{:min, &1}),
        constant(:min),
        integer(0..20) |> map(&{:max, &1}),
        integer(0..100) |> map(&{:percent, &1}),
        integer(1..5) |> map(&{:fill, &1})
      ])

    constraint
    |> list_of(min_length: 1, max_length: 8)
    |> filter(&(base_total(&1, total) <= total))
  end

  defp base_total(constraints, total) do
    constraints
    |> Enum.map(&base_size(&1, total))
    |> Enum.sum()
  end

  defp base_size({:length, n}, _total), do: n
  defp base_size({:min, n}, _total), do: n
  defp base_size(:min, _total), do: 0
  defp base_size({:max, _n}, _total), do: 0
  defp base_size({:percent, p}, total), do: round(total * p / 100)
  defp base_size({:fill, _weight}, _total), do: 0

  defp inside?(%Rect{} = child, %Rect{} = parent) do
    child.x >= parent.x and child.y >= parent.y and
      child.x + child.width <= parent.x + parent.width and
      child.y + child.height <= parent.y + parent.height
  end

  defp ordered_non_overlapping?(rects, :horizontal) do
    rects
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [left, right] -> left.x + left.width <= right.x end)
  end

  defp ordered_non_overlapping?(rects, :vertical) do
    rects
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [top, bottom] -> top.y + top.height <= bottom.y end)
  end
end
