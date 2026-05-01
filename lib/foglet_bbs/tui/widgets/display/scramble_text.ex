defmodule Foglet.TUI.Widgets.Display.ScrambleText do
  @moduledoc """
  Themed deterministic scramble-text reveal (D-07, D-09, D-13, D-16).

  Stateless: callers pass the target text, frame index, and options on every
  render. The widget is deterministic for a fixed target/frame/options tuple,
  and callers own all animation timing.

  Honours:
    * D-07/D-09 — theme-routed colors only
    * D-13     — `theme:` keyword arg
    * D-16     — no state struct; frame index is caller-owned

  ## Options

    * `:charset` — `:upper | :lower | :numeric | :mixed | {:custom, binary}`.
      Defaults to `:mixed`; all built-in sets are terminal-safe ASCII.
    * `:direction` — `:left_to_right | :right_to_left | :center_out | :random`.
      Defaults to `:left_to_right`. Random reveal order is deterministic for a
      fixed `:seed`.
    * `:cursor` — `nil | :underscore | :block | {:custom, grapheme}`. Defaults
      to `nil`. The cursor is omitted once the text is fully settled.
    * `:reveal_rate` — positive integer frames per settled character. Defaults
      to `2`.
    * `:settle_duration` — positive integer total frames to settle all target
      graphemes. Overrides `:reveal_rate` when provided.
    * `:seed` — integer seed for deterministic scramble. If omitted, the seed
      falls back to `:erlang.phash2({frame, target})`.
    * `:theme` — required `%Foglet.TUI.Theme{}` struct.
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.Theme

  @default_charset :mixed
  @default_direction :left_to_right
  @default_cursor nil
  @default_reveal_rate 2
  @upper "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  @lower "abcdefghijklmnopqrstuvwxyz"
  @numeric "0123456789"
  @mixed @upper <> @lower <> @numeric

  @type charset :: :upper | :lower | :numeric | :mixed | {:custom, binary()}
  @type direction :: :left_to_right | :right_to_left | :center_out | :random
  @type cursor :: nil | :underscore | :block | {:custom, String.t()}

  @doc """
  Renders `target` at `frame`.

  See the module documentation for supported options.
  """
  def render(target, frame, opts)
      when is_binary(target) and is_integer(frame) and frame >= 0 and is_list(opts) do
    %Theme{} = theme = Keyword.fetch!(opts, :theme)
    graphemes = String.graphemes(target)

    case graphemes do
      [] ->
        text("", fg: theme.primary.fg, style: slot_style(theme.primary))

      _ ->
        render_graphemes(graphemes, frame, opts, theme)
    end
  end

  @doc """
  Convenience two-argument form that reads `:frame` from `opts`.
  """
  def render(target, opts) when is_binary(target) and is_list(opts) do
    frame = Keyword.get(opts, :frame, 0)
    render(target, frame, Keyword.delete(opts, :frame))
  end

  @doc """
  Returns the first frame at which `target` is fully settled for `opts`.
  """
  @spec settled_frame(String.t(), keyword()) :: non_neg_integer()
  def settled_frame(target, opts) when is_binary(target) and is_list(opts) do
    len = target |> String.graphemes() |> length()

    case Keyword.get(opts, :settle_duration) do
      duration when is_integer(duration) and duration > 0 -> duration
      _ -> len * reveal_rate(opts)
    end
  end

  @doc "Recommended frame duration in ms for caller-driven animation."
  @spec frame_duration_ms() :: 100
  def frame_duration_ms, do: 100

  defp render_graphemes(graphemes, frame, opts, theme) do
    target = Enum.join(graphemes)
    len = length(graphemes)
    settled = settled_count(len, frame, opts)
    order = reveal_order(len, Keyword.get(opts, :direction, @default_direction), opts)
    settled_indexes = order |> Enum.take(settled) |> MapSet.new()
    charset = charset_graphemes(Keyword.get(opts, :charset, @default_charset))
    seed = Keyword.get(opts, :seed, :erlang.phash2({frame, target}))
    cursor = cursor_grapheme(Keyword.get(opts, :cursor, @default_cursor))

    rendered_graphemes =
      graphemes
      |> Enum.with_index()
      |> Enum.flat_map(fn {grapheme, index} ->
        rendered =
          if MapSet.member?(settled_indexes, index) do
            text(grapheme, fg: theme.primary.fg, style: slot_style(theme.primary))
          else
            text(scrambled_grapheme(charset, seed, frame, index, target),
              fg: theme.dim.fg,
              style: slot_style(theme.dim)
            )
          end

        if cursor && settled < len && index == cursor_after_index(order, settled, len) do
          [
            rendered,
            text(cursor, fg: theme.accent.fg, style: slot_style(theme.accent))
          ]
        else
          [rendered]
        end
      end)

    children =
      if cursor && settled == 0 do
        [text(cursor, fg: theme.accent.fg, style: slot_style(theme.accent)) | rendered_graphemes]
      else
        rendered_graphemes
      end

    row style: %{gap: 0} do
      children
    end
  end

  defp settled_count(len, frame, opts) do
    count =
      case Keyword.get(opts, :settle_duration) do
        duration when is_integer(duration) and duration > 0 ->
          div(frame * len, duration)

        _ ->
          div(frame, reveal_rate(opts))
      end

    count |> min(len) |> max(0)
  end

  defp reveal_rate(opts) do
    case Keyword.get(opts, :reveal_rate, @default_reveal_rate) do
      rate when is_integer(rate) and rate > 0 -> rate
      _ -> @default_reveal_rate
    end
  end

  defp reveal_order(len, :left_to_right, _opts), do: Enum.to_list(0..(len - 1)//1)
  defp reveal_order(len, :right_to_left, _opts), do: Enum.to_list((len - 1)..0//-1)

  defp reveal_order(len, :center_out, _opts) do
    center_left = div(len - 1, 2)
    center_right = div(len, 2)

    Stream.flat_map(0..len, fn distance ->
      [center_left - distance, center_right + distance]
    end)
    |> Enum.uniq()
    |> Enum.filter(&(&1 >= 0 and &1 < len))
  end

  defp reveal_order(len, :random, opts) do
    seed = Keyword.get(opts, :seed, 0)

    0..(len - 1)//1
    |> Enum.sort_by(&:erlang.phash2({seed, :reveal_order, &1}))
  end

  defp reveal_order(len, _unknown, opts), do: reveal_order(len, @default_direction, opts)

  defp cursor_after_index(order, settled, len) do
    cond do
      settled <= 0 -> -1
      settled >= len -> len - 1
      true -> Enum.at(order, settled - 1)
    end
  end

  defp charset_graphemes(:upper), do: String.graphemes(@upper)
  defp charset_graphemes(:lower), do: String.graphemes(@lower)
  defp charset_graphemes(:numeric), do: String.graphemes(@numeric)
  defp charset_graphemes(:mixed), do: String.graphemes(@mixed)

  defp charset_graphemes({:custom, custom}) when is_binary(custom) do
    case String.graphemes(custom) do
      [] -> charset_graphemes(@default_charset)
      graphemes -> graphemes
    end
  end

  defp charset_graphemes(_unknown), do: charset_graphemes(@default_charset)

  defp scrambled_grapheme(charset, seed, frame, index, target) do
    charset
    |> Enum.at(:erlang.phash2({seed, frame, index, target}, length(charset)))
  end

  defp cursor_grapheme(nil), do: nil
  defp cursor_grapheme(:underscore), do: "_"
  defp cursor_grapheme(:block), do: "█"

  defp cursor_grapheme({:custom, grapheme}) when is_binary(grapheme) do
    grapheme |> String.graphemes() |> List.first()
  end

  defp cursor_grapheme(_unknown), do: nil

  defp slot_style(slot) when is_map(slot), do: Map.get(slot, :style, [])
  defp slot_style(_slot), do: []
end
