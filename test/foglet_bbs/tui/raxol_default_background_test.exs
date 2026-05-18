defmodule FogletBbs.TUI.RaxolDefaultBackgroundTest do
  use ExUnit.Case, async: true

  alias Raxol.Terminal.{Renderer, ScreenBuffer}

  test "plain UI text with spaces keeps terminal-default background unset" do
    cells =
      Raxol.UI.Renderer.render_to_cells(%{
        type: :text,
        x: 0,
        y: 0,
        text: "A B"
      })

    assert [
             {0, 0, "A", :white, nil, []},
             {1, 0, " ", :white, nil, []},
             {2, 0, "B", :white, nil, []}
           ] = cells

    refute ansi_for_cells(cells) =~ "\e[40m"
  end

  test "explicit UI backgrounds still paint cells and emit background SGR" do
    cells =
      Raxol.UI.Renderer.render_to_cells(%{
        type: :text,
        x: 0,
        y: 0,
        text: "A B",
        style: %{bg: :black}
      })

    assert [
             {0, 0, "A", :white, :black, []},
             {1, 0, " ", :white, :black, []},
             {2, 0, "B", :white, :black, []}
           ] = cells

    assert ansi_for_cells(cells) =~ "\e[40m"
  end

  test "panel borders keep terminal-default background unset" do
    cells =
      %{
        type: :panel,
        attrs: %{border: :single, border_fg: :cyan},
        children: []
      }
      |> Raxol.UI.Layout.Engine.apply_layout(%{width: 6, height: 4})
      |> Raxol.UI.Renderer.render_to_cells()

    assert Enum.any?(cells, fn {_x, _y, char, :cyan, nil, _attrs} -> char == "─" end)

    refute Enum.any?(cells, fn
             {_x, _y, char, _fg, bg, _attrs} when char in ["┌", "┐", "└", "┘", "─", "│"] ->
               not is_nil(bg)

             _cell ->
               false
           end)

    refute ansi_for_cells(cells, 6, 4) =~ "\e[40m"
  end

  test "explicit panel border backgrounds still paint cells" do
    cells =
      %{
        type: :panel,
        attrs: %{border: :single, border_fg: :cyan, border_bg: :blue},
        children: []
      }
      |> Raxol.UI.Layout.Engine.apply_layout(%{width: 6, height: 4})
      |> Raxol.UI.Renderer.render_to_cells()

    assert Enum.all?(cells, fn
             {_x, _y, char, :cyan, :blue, _attrs} when char in ["┌", "┐", "└", "┘", "─", "│"] ->
               true

             _cell ->
               false
           end)

    assert ansi_for_cells(cells, 6, 4) =~ "\e[44m"
  end

  defp ansi_for_cells(cells, width \\ 3, height \\ 1) do
    buffer =
      Enum.reduce(cells, ScreenBuffer.new(width, height), fn {x, y, char, fg, bg, attrs},
                                                             buffer ->
        style = %{
          foreground: fg,
          background: bg,
          bold: :bold in attrs,
          italic: :italic in attrs,
          underline: :underline in attrs
        }

        ScreenBuffer.write_char(buffer, x, y, char, style)
      end)

    buffer
    |> Renderer.new(%{}, %{}, false)
    |> Renderer.render()
  end
end
