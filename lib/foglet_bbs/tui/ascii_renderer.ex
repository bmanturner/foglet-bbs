defmodule Foglet.TUI.AsciiRenderer do
  @moduledoc """
  Renders a Raxol view tree to a plain ASCII/Unicode string grid.

  Used by `mix foglet.tui.render` so agents (and humans) can "see" any TUI
  screen without an SSH client. The renderer drives the same
  `Raxol.UI.Layout.Engine` that the live TUI uses; only the final paint step
  differs — instead of writing cells to a terminal, positioned `:text` and
  `:box` elements are drawn onto a 2D character grid.

  The output is intentionally style-stripped: no ANSI escapes, no color, no
  bold/dim. Layout, content, and box borders only. This keeps the captured
  output diffable and easy for an LLM to reason about.
  """

  alias Foglet.TUI.TextWidth
  alias Raxol.UI.Layout.Engine

  @doc """
  Renders a view tree at `{width, height}` and returns a newline-joined string.
  """
  @spec render(any(), {pos_integer(), pos_integer()}) :: String.t()
  def render(tree, {width, height})
      when is_integer(width) and width > 0 and is_integer(height) and height > 0 do
    elements = Engine.apply_layout(tree, %{width: width, height: height})

    grid =
      elements
      |> List.flatten()
      |> Enum.reduce(%{}, &paint_element(&1, &2, width, height))

    grid_to_string(grid, width, height)
  end

  # --- painting -------------------------------------------------------------

  defp paint_element(%{type: :text, x: x, y: y, text: text}, grid, w, h)
       when is_binary(text) and is_integer(x) and is_integer(y) do
    paint_text(grid, x, y, text, w, h)
  end

  defp paint_element(
         %{type: :box, x: x, y: y, width: bw, height: bh, attrs: %{border: border}},
         grid,
         w,
         h
       )
       when border not in [nil, :none] do
    paint_box(grid, x, y, bw, bh, border, w, h)
  end

  defp paint_element(_other, grid, _w, _h), do: grid

  defp paint_text(grid, _x, y, _text, _w, h) when y < 0 or y >= h, do: grid

  defp paint_text(grid, x, y, text, w, h) do
    text
    |> String.graphemes()
    |> Enum.reduce({grid, x}, fn grapheme, {acc, cx} ->
      glyph_width = max(TextWidth.display_width(grapheme), 1)

      acc =
        if cx < 0 or cx >= w do
          acc
        else
          char = if printable?(grapheme), do: grapheme, else: "?"
          acc = put_cell(acc, cx, y, char, w, h)

          if glyph_width > 1 and cx + 1 < w do
            put_cell(acc, cx + 1, y, " ", w, h)
          else
            acc
          end
        end

      {acc, cx + glyph_width}
    end)
    |> elem(0)
  end

  defp paint_box(grid, x, y, bw, bh, border, w, h) when bw >= 2 and bh >= 2 do
    {tl, tr, bl, br, hor, ver} = border_chars(border)

    grid
    |> put_cell(x, y, tl, w, h)
    |> put_cell(x + bw - 1, y, tr, w, h)
    |> put_cell(x, y + bh - 1, bl, w, h)
    |> put_cell(x + bw - 1, y + bh - 1, br, w, h)
    |> paint_horizontal(x + 1, y, bw - 2, hor, w, h)
    |> paint_horizontal(x + 1, y + bh - 1, bw - 2, hor, w, h)
    |> paint_vertical(x, y + 1, bh - 2, ver, w, h)
    |> paint_vertical(x + bw - 1, y + 1, bh - 2, ver, w, h)
  end

  defp paint_box(grid, _x, _y, _bw, _bh, _border, _w, _h), do: grid

  defp paint_horizontal(grid, x, y, len, char, w, h) when len > 0 do
    Enum.reduce(0..(len - 1), grid, fn i, acc ->
      put_cell(acc, x + i, y, char, w, h)
    end)
  end

  defp paint_horizontal(grid, _x, _y, _len, _char, _w, _h), do: grid

  defp paint_vertical(grid, x, y, len, char, w, h) when len > 0 do
    Enum.reduce(0..(len - 1), grid, fn i, acc ->
      put_cell(acc, x, y + i, char, w, h)
    end)
  end

  defp paint_vertical(grid, _x, _y, _len, _char, _w, _h), do: grid

  defp border_chars(:double), do: {"╔", "╗", "╚", "╝", "═", "║"}
  defp border_chars(:thick), do: {"┏", "┓", "┗", "┛", "━", "┃"}
  defp border_chars(:rounded), do: {"╭", "╮", "╰", "╯", "─", "│"}
  defp border_chars(_single), do: {"┌", "┐", "└", "┘", "─", "│"}

  # --- grid -----------------------------------------------------------------

  # The grid is a map keyed by `{y, x}` of single-grapheme strings. Cells not
  # in the map render as " ". Map storage keeps painting cheap regardless of
  # grid size.
  defp put_cell(grid, x, y, _char, w, h) when x < 0 or y < 0 or x >= w or y >= h, do: grid
  defp put_cell(grid, x, y, char, _w, _h), do: Map.put(grid, {y, x}, char)

  defp grid_to_string(grid, width, height) do
    0..(height - 1)
    |> Enum.map_join("\n", fn y ->
      0..(width - 1)
      |> Enum.map(fn x -> Map.get(grid, {y, x}, " ") end)
      |> IO.iodata_to_binary()
      |> String.trim_trailing()
    end)
  end

  defp printable?(grapheme) do
    case String.next_codepoint(grapheme) do
      {<<cp::utf8>>, _} -> cp >= 0x20 and cp != 0x7F
      _ -> false
    end
  end
end
