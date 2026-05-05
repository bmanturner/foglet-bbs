defmodule Foglet.TUI.Widgets.List.SelectableFieldList do
  @moduledoc """
  Selectable field/value list for settings surfaces (D-07, D-09, D-13, D-16).

  This is a stateless read-mode widget: callers own selected index and persist
  any scroll/selection state. It keeps `Display.KvGrid` display-only while
  providing field selection, intentional empty placeholders, optional compact
  descriptions, and deterministic windowing for cramped terminals.
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme

  @default_width 80
  @default_height 12
  @empty_placeholder "—"
  @selected_marker "▸ "
  @plain_marker "  "

  @doc "Render field rows with a visible selected field."
  @spec render([map()], non_neg_integer(), keyword()) :: any()
  def render(fields, selected_index, opts) when is_list(fields) and is_list(opts) do
    %Theme{} = theme = Keyword.fetch!(opts, :theme)
    width = opts |> Keyword.get(:width, @default_width) |> max(20)
    height = opts |> Keyword.get(:height, @default_height) |> max(1)
    selected_index = clamp(selected_index, length(fields))
    label_width = label_width(width)

    blocks = Enum.map(fields, &field_block(&1, width, label_width))
    start = window_start(blocks, selected_index, height)

    visible_rows =
      blocks
      |> Enum.with_index()
      |> Enum.flat_map(fn {block, idx} -> render_block(block, idx == selected_index, theme) end)
      |> Enum.drop(row_offset(blocks, start))
      |> Enum.take(height)

    column style: %{gap: 0} do
      visible_rows
    end
  end

  @doc "Move selected index for list-mode navigation keys."
  @spec move(non_neg_integer(), non_neg_integer(), atom() | String.t()) :: non_neg_integer()
  def move(selected_index, count, key) do
    selected_index
    |> do_move(count, key)
    |> clamp(count)
  end

  defp do_move(idx, _count, key) when key in [:up, "k", "K"], do: idx - 1
  defp do_move(idx, _count, key) when key in [:down, "j", "J"], do: idx + 1
  defp do_move(_idx, _count, key) when key in [:home, "g", "G"], do: 0
  defp do_move(_idx, count, :end), do: count - 1
  defp do_move(idx, _count, _key), do: idx

  defp field_block(field, width, label_width) do
    marker_width = 2
    separator = " : "
    value_width = max(width - marker_width - label_width - TextWidth.display_width(separator), 4)
    description_width = max(width - marker_width - 2, 8)

    value =
      field
      |> Map.get(:value, @empty_placeholder)
      |> display_value()
      |> TextWidth.truncate(value_width)

    row =
      field
      |> Map.get(:label, "")
      |> to_string()
      |> TextWidth.truncate(label_width)
      |> TextWidth.pad_trailing(label_width)
      |> Kernel.<>(separator <> value)

    descriptions =
      field
      |> Map.get(:description)
      |> description_lines(description_width)
      |> Enum.map(&("  " <> &1))

    %{row: row, descriptions: descriptions}
  end

  defp render_block(%{row: row, descriptions: descriptions}, selected?, %Theme{} = theme) do
    marker = if selected?, do: @selected_marker, else: @plain_marker
    style = if selected?, do: [:bold, :reverse], else: []
    fg = if selected?, do: theme.selected.fg, else: theme.unselected.fg

    [text(marker <> row, fg: fg, style: style)] ++
      Enum.map(descriptions, &text(@plain_marker <> &1, fg: theme.dim.fg, style: [:dim, :italic]))
  end

  defp display_value(nil), do: @empty_placeholder
  defp display_value(""), do: @empty_placeholder
  defp display_value(true), do: "Yes"
  defp display_value(false), do: "No"
  defp display_value(value), do: to_string(value)

  defp description_lines(nil, _width), do: []
  defp description_lines("", _width), do: []

  defp description_lines(text, width) do
    text
    |> to_string()
    |> wrap_words(width)
    |> Enum.take(2)
  end

  defp wrap_words(text, width) do
    text
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reduce([""], fn word, [line | rest] ->
      candidate = if line == "", do: word, else: line <> " " <> word

      if TextWidth.display_width(candidate) <= width do
        [candidate | rest]
      else
        [TextWidth.truncate(word, width), line | rest]
      end
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reverse()
  end

  defp label_width(width) when width < 72, do: 14
  defp label_width(width) when width < 100, do: 18
  defp label_width(_width), do: 24

  defp window_start(blocks, selected_index, height) do
    selected_top = row_offset(blocks, selected_index)
    selected_height = blocks |> Enum.at(selected_index, %{descriptions: []}) |> block_height()
    selected_bottom = selected_top + selected_height - 1

    cond do
      selected_top < 0 -> 0
      selected_bottom < height -> 0
      true -> selected_bottom - height + 1
    end
  end

  defp row_offset(blocks, idx) do
    blocks
    |> Enum.take(idx)
    |> Enum.map(&block_height/1)
    |> Enum.sum()
  end

  defp block_height(%{descriptions: descriptions}), do: 1 + length(descriptions)

  defp clamp(_idx, 0), do: 0
  defp clamp(idx, count), do: idx |> max(0) |> min(count - 1)
end
