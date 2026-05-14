defmodule Foglet.TUI.Layout do
  @moduledoc """
  Small deterministic rectangle helpers for TUI render code.

  A rect is a `%Foglet.TUI.Layout.Rect{}` with `:x`, `:y`, `:width`, and
  `:height` integer fields. Public functions also accept maps with the same
  keys.

  `vertical/2` and `horizontal/2` split a parent rect into child rects using
  these constraints:

    * `{:length, n}` - exactly `n` cells when space allows.
    * `{:min, n}` - at least `n` cells, then eligible for leftover space.
    * `:min` - sugar for `{:min, 0}`.
    * `{:max, n}` - up to `n` cells from leftover space.
    * `{:percent, p}` - `p` percent of the parent, rounded deterministically.
    * `{:fill, weight}` - shares leftover space by positive weight.

  Over-constrained splits are clipped in declaration order and emit a warning
  in dev/test instead of crashing. Under-constrained splits leave trailing
  space empty.
  """

  require Logger

  defmodule Rect do
    @moduledoc """
    Rectangle returned by `Foglet.TUI.Layout`.
    """

    @enforce_keys [:x, :y, :width, :height]
    defstruct [:x, :y, :width, :height]

    @type t :: %__MODULE__{
            x: non_neg_integer(),
            y: non_neg_integer(),
            width: non_neg_integer(),
            height: non_neg_integer()
          }
  end

  @type rect_input ::
          Rect.t()
          | %{
              required(:x) => integer(),
              required(:y) => integer(),
              required(:width) => integer(),
              required(:height) => integer()
            }
  @type constraint ::
          {:length, non_neg_integer()}
          | {:min, non_neg_integer()}
          | :min
          | {:max, non_neg_integer()}
          | {:percent, number()}
          | {:fill, pos_integer()}

  @doc """
  Splits `parent` from top to bottom.

      iex> parent = %Foglet.TUI.Layout.Rect{x: 2, y: 3, width: 10, height: 6}
      iex> Foglet.TUI.Layout.vertical(parent, [{:length, 2}, {:fill, 1}, {:max, 2}])
      [
        %Foglet.TUI.Layout.Rect{x: 2, y: 3, width: 10, height: 2},
        %Foglet.TUI.Layout.Rect{x: 2, y: 5, width: 10, height: 2},
        %Foglet.TUI.Layout.Rect{x: 2, y: 7, width: 10, height: 2}
      ]
  """
  @spec vertical(rect_input(), [constraint()]) :: [Rect.t()]
  def vertical(parent, constraints) when is_list(constraints) do
    rect = rect!(parent)

    rect.height
    |> sizes_for(constraints, :vertical)
    |> build_vertical(rect)
  end

  @doc """
  Splits `parent` from left to right.

      iex> parent = %{x: 0, y: 0, width: 10, height: 4}
      iex> Foglet.TUI.Layout.horizontal(parent, [{:percent, 50}, {:fill, 1}])
      [
        %Foglet.TUI.Layout.Rect{x: 0, y: 0, width: 5, height: 4},
        %Foglet.TUI.Layout.Rect{x: 5, y: 0, width: 5, height: 4}
      ]
  """
  @spec horizontal(rect_input(), [constraint()]) :: [Rect.t()]
  def horizontal(parent, constraints) when is_list(constraints) do
    rect = rect!(parent)

    rect.width
    |> sizes_for(constraints, :horizontal)
    |> build_horizontal(rect)
  end

  @doc """
  Centers a child rect inside `parent`.

  The second argument accepts `%{width: w, height: h}` or `{w, h}`. Sizes larger
  than the parent are clipped.

      iex> Foglet.TUI.Layout.center(%{x: 0, y: 0, width: 9, height: 5}, {4, 2})
      %Foglet.TUI.Layout.Rect{x: 2, y: 1, width: 4, height: 2}
  """
  @spec center(
          rect_input(),
          %{required(:width) => integer(), required(:height) => integer()}
          | {integer(), integer()}
        ) ::
          Rect.t()
  def center(parent, size) do
    rect = rect!(parent)
    {requested_width, requested_height} = size!(size)
    width = min(requested_width, rect.width)
    height = min(requested_height, rect.height)

    if requested_width > rect.width or requested_height > rect.height do
      warn_overconstrained(
        :center,
        {requested_width, requested_height},
        {rect.width, rect.height}
      )
    end

    %Rect{
      x: rect.x + div(rect.width - width, 2),
      y: rect.y + div(rect.height - height, 2),
      width: width,
      height: height
    }
  end

  defp normalize_constraint!({:length, n}) when is_integer(n) and n >= 0,
    do: %{base: n, flex?: false, weight: 0, cap: 0}

  defp normalize_constraint!({:min, n}) when is_integer(n) and n >= 0,
    do: %{base: n, flex?: true, weight: 1, cap: :infinity}

  defp normalize_constraint!(:min), do: normalize_constraint!({:min, 0})

  defp normalize_constraint!({:max, n}) when is_integer(n) and n >= 0,
    do: %{base: 0, flex?: true, weight: 1, cap: n}

  defp normalize_constraint!({:percent, p}) when is_number(p) and p >= 0,
    do: %{base: {:percent, p}, flex?: false, weight: 0, cap: 0}

  defp normalize_constraint!({:fill, weight}) when is_integer(weight) and weight > 0,
    do: %{base: 0, flex?: true, weight: weight, cap: :infinity}

  defp normalize_constraint!(constraint),
    do: raise(ArgumentError, "invalid layout constraint: #{inspect(constraint)}")

  defp sizes_for(total, constraints, axis) when is_integer(total) and total >= 0 do
    specs =
      Enum.map(constraints, fn constraint ->
        constraint
        |> normalize_constraint!()
        |> resolve_percent_base(total)
      end)

    base_sizes = Enum.map(specs, & &1.base)
    base_total = Enum.sum(base_sizes)

    if base_total > total do
      warn_overconstrained(axis, constraints, total)
      clip_in_order(base_sizes, total)
    else
      distribute_leftover(base_sizes, specs, total - base_total)
    end
  end

  defp resolve_percent_base(%{base: {:percent, percent}} = spec, total) do
    %{spec | base: round(total * percent / 100)}
  end

  defp resolve_percent_base(spec, _total), do: spec

  defp clip_in_order(sizes, total) do
    {clipped, _remaining} =
      Enum.map_reduce(sizes, total, fn size, remaining ->
        actual = min(size, max(remaining, 0))
        {actual, remaining - actual}
      end)

    clipped
  end

  defp distribute_leftover(sizes, _specs, 0), do: sizes

  defp distribute_leftover(sizes, specs, leftover) do
    flexes =
      specs
      |> Enum.with_index()
      |> Enum.filter(fn {spec, _index} -> spec.flex? end)

    do_distribute(sizes, flexes, leftover)
  end

  defp do_distribute(sizes, _flexes, leftover) when leftover <= 0, do: sizes

  defp do_distribute(sizes, flexes, leftover) do
    eligible =
      Enum.filter(flexes, fn {spec, index} ->
        has_capacity?(spec, Enum.at(sizes, index))
      end)

    if eligible == [] do
      sizes
    else
      total_weight =
        eligible
        |> Enum.map(fn {spec, _index} -> spec.weight end)
        |> Enum.sum()

      proposals =
        Enum.map(eligible, fn {spec, index} ->
          raw = leftover * spec.weight / total_weight
          floor_share = floor(raw)

          %{
            index: index,
            share: cap_share(floor_share, capacity(spec, Enum.at(sizes, index))),
            remainder: raw - floor_share,
            capacity: capacity(spec, Enum.at(sizes, index))
          }
        end)

      proposals =
        if Enum.sum(Enum.map(proposals, & &1.share)) == 0 do
          [%{Enum.max_by(proposals, &{&1.remainder, -&1.index}) | share: 1}]
        else
          proposals
        end

      {next_sizes, used} =
        Enum.reduce(proposals, {sizes, 0}, fn %{index: index, share: share, capacity: cap},
                                              {acc, used} ->
          actual = cap_share(share, cap)
          {List.update_at(acc, index, &(&1 + actual)), used + actual}
        end)

      do_distribute(next_sizes, flexes, leftover - used)
    end
  end

  defp capacity(%{cap: :infinity}, _current), do: :infinity
  defp capacity(%{cap: cap}, current), do: max(cap - current, 0)

  defp has_capacity?(%{cap: :infinity}, _current), do: true
  defp has_capacity?(spec, current), do: capacity(spec, current) > 0

  defp cap_share(value, :infinity), do: value
  defp cap_share(value, cap), do: min(value, cap)

  defp build_vertical(sizes, %Rect{} = rect) do
    {children, _y} =
      Enum.map_reduce(sizes, rect.y, fn height, y ->
        {%Rect{x: rect.x, y: y, width: rect.width, height: height}, y + height}
      end)

    children
  end

  defp build_horizontal(sizes, %Rect{} = rect) do
    {children, _x} =
      Enum.map_reduce(sizes, rect.x, fn width, x ->
        {%Rect{x: x, y: rect.y, width: width, height: rect.height}, x + width}
      end)

    children
  end

  defp rect!(%Rect{x: x, y: y, width: width, height: height})
       when is_integer(x) and is_integer(y) and is_integer(width) and width >= 0 and
              is_integer(height) and height >= 0 do
    %Rect{x: x, y: y, width: width, height: height}
  end

  defp rect!(%{x: x, y: y, width: width, height: height})
       when is_integer(x) and is_integer(y) and is_integer(width) and width >= 0 and
              is_integer(height) and height >= 0 do
    %Rect{x: x, y: y, width: width, height: height}
  end

  defp rect!(rect), do: raise(ArgumentError, "invalid layout rect: #{inspect(rect)}")

  defp size!(%{width: width, height: height})
       when is_integer(width) and width >= 0 and is_integer(height) and height >= 0 do
    {width, height}
  end

  defp size!({width, height})
       when is_integer(width) and width >= 0 and is_integer(height) and height >= 0 do
    {width, height}
  end

  defp size!(size), do: raise(ArgumentError, "invalid layout size: #{inspect(size)}")

  defp warn_overconstrained(axis, requested, available) do
    if dev_or_test?() do
      Logger.warning(
        "Foglet.TUI.Layout clipped over-constrained #{axis} layout " <>
          "requested=#{inspect(requested)} available=#{inspect(available)}"
      )
    end
  end

  defp dev_or_test? do
    Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) and Mix.env() in [:dev, :test]
  end
end
