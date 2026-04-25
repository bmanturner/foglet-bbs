defmodule Foglet.TUI.TextWidth do
  @moduledoc """
  Foglet-owned terminal display-width helpers for TUI layout.

  This module wraps `Raxol.UI.TextMeasure` for primitive terminal cell
  measurement and display-width splitting. It is for rendering and layout only;
  product validation rules such as title or post length limits remain separate
  character-count policies.
  """

  @default_ellipsis "…"

  @doc """
  Returns the terminal display width of `text`.
  """
  @spec display_width(term()) :: non_neg_integer()
  def display_width(text) do
    text
    |> to_string()
    |> Raxol.UI.TextMeasure.display_width()
  end

  @doc """
  Splits `text` at a terminal display-width boundary.

  The left side fits within `width` terminal columns. Graphemes wider than the
  remaining space stay on the right side.
  """
  @spec split_at(term(), integer()) :: {String.t(), String.t()}
  def split_at(text, width) when is_integer(width) and width <= 0 do
    {"", to_string(text)}
  end

  def split_at(text, width) when is_integer(width) do
    text = to_string(text)
    {left, _right} = Raxol.UI.TextMeasure.split_at_display_width(text, width)

    split_at_grapheme_boundary(text, byte_size(left), width)
  end

  @doc """
  Returns the portion of `text` that fits within `width` terminal columns.
  """
  @spec slice_to_width(term(), integer()) :: String.t()
  def slice_to_width(text, width) do
    text
    |> split_at(width)
    |> elem(0)
  end

  @doc """
  Truncates `text` to fit within `max_width` terminal columns.
  """
  @spec truncate(term(), integer()) :: String.t()
  def truncate(text, max_width), do: truncate(text, max_width, [])

  @doc """
  Truncates `text` to fit within `max_width` terminal columns.

  Options:

    * `:ellipsis` - suffix for overflow text, defaults to `"…"`
  """
  @spec truncate(term(), integer(), keyword()) :: String.t()
  def truncate(text, max_width, opts) when is_integer(max_width) do
    text = to_string(text)
    ellipsis = opts |> Keyword.get(:ellipsis, @default_ellipsis) |> to_string()

    cond do
      max_width <= 0 ->
        ""

      display_width(text) <= max_width ->
        text

      display_width(ellipsis) >= max_width ->
        slice_to_width(ellipsis, max_width)

      true ->
        available_width = max_width - display_width(ellipsis)
        slice_to_width(text, available_width) <> ellipsis
    end
  end

  @doc """
  Pads the right side of `text` with spaces until it reaches `width` columns.
  """
  @spec pad_trailing(term(), integer()) :: String.t()
  def pad_trailing(text, width) when is_integer(width) do
    text = to_string(text)
    text <> padding(text, width)
  end

  @doc """
  Pads the left side of `text` with spaces until it reaches `width` columns.
  """
  @spec pad_leading(term(), integer()) :: String.t()
  def pad_leading(text, width) when is_integer(width) do
    text = to_string(text)
    padding(text, width) <> text
  end

  defp padding(text, width) do
    " "
    |> List.duplicate(max(width - display_width(text), 0))
    |> Enum.join()
  end

  defp split_at_grapheme_boundary(text, candidate_bytes, width) do
    boundaries = grapheme_boundaries(text)

    cond do
      candidate_bytes in boundaries ->
        split_at_bytes(text, candidate_bytes)

      true ->
        bytes =
          boundaries
          |> Enum.find(fn bytes ->
            bytes > candidate_bytes and display_width(binary_part(text, 0, bytes)) <= width
          end)
          |> case do
            nil ->
              boundaries
              |> Enum.filter(fn bytes ->
                bytes < candidate_bytes and display_width(binary_part(text, 0, bytes)) <= width
              end)
              |> List.last()

            bytes ->
              bytes
          end

        split_at_bytes(text, bytes || 0)
    end
  end

  defp grapheme_boundaries(text) do
    {_position, boundaries} =
      text
      |> String.graphemes()
      |> Enum.reduce({0, [0]}, fn grapheme, {position, boundaries} ->
        position = position + byte_size(grapheme)
        {position, [position | boundaries]}
      end)

    Enum.reverse(boundaries)
  end

  defp split_at_bytes(text, bytes) do
    <<left::binary-size(bytes), right::binary>> = text
    {left, right}
  end
end
