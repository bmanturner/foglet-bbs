defmodule Foglet.TUI.TextTest do
  use ExUnit.Case, async: true

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.Text
  alias Foglet.TUI.Text.Line
  alias Foglet.TUI.Text.Span
  alias Foglet.TUI.Theme
  alias Foglet.TUI.WidgetHelpers

  @screen_sources Path.wildcard("lib/foglet_bbs/tui/screens/**/*.{ex,exs}")

  setup do
    %{theme: Theme.default()}
  end

  test "span converts to the same Raxol text node as hand-written themed text", %{theme: theme} do
    composed =
      "Saved."
      |> Span.new(fg: :success)
      |> Span.bold()
      |> Text.to_raxol(theme)

    assert composed == text("Saved.", fg: theme.success.fg, style: [:bold])
  end

  test "line converts to equivalent styled runs for mixed text", %{theme: theme} do
    composed =
      Line.new([
        Span.new("[Enter]", fg: :accent) |> Span.bold(),
        Span.new(" OK", fg: :dim)
      ])
      |> Text.to_raxol(theme)

    hand_written =
      row style: %{gap: 0} do
        [
          text("[Enter]", fg: theme.accent.fg, style: [:bold]),
          text(" OK", fg: theme.dim.fg)
        ]
      end

    assert composed == hand_written
  end

  test "text converts to equivalent multi-line Raxol tree", %{theme: theme} do
    composed =
      [
        Line.new(Span.new("Title", fg: :title) |> Span.underline()),
        Line.new("Muted", fg: :dim, italic: true)
      ]
      |> Text.new()
      |> Text.to_raxol(theme)

    hand_written =
      column style: %{gap: 0} do
        [
          text("Title", fg: theme.title.fg, style: [:underline]),
          text("Muted", fg: theme.dim.fg, style: [:italic])
        ]
      end

    assert composed == hand_written
  end

  test "append and style helpers compose values without mutating earlier spans", %{theme: theme} do
    line =
      "A"
      |> Span.new(fg: :primary)
      |> Line.new()
      |> Line.append(Span.new("B", fg: :accent) |> Span.bold())

    assert WidgetHelpers.flatten_text(Text.to_raxol(line, theme)) == "AB"

    assert [
             %{content: "A", fg: primary},
             %{content: "B", fg: accent, style: [:bold]}
           ] = WidgetHelpers.text_runs(Text.to_raxol(line, theme))

    assert primary == theme.primary.fg
    assert accent == theme.accent.fg
  end

  test "raw terminal color atoms are rejected" do
    assert_raise ArgumentError, ~r/raw terminal color atoms/, fn ->
      Span.new("bad", fg: :red)
    end
  end

  test "screen modules do not introduce raw ANSI escape codes" do
    for path <- @screen_sources do
      source = File.read!(path)

      refute source =~ ~S(\e[),
             "#{path} contains a raw ANSI escape sequence; use Foglet.TUI.Text or Raxol style opts"

      refute source =~ <<27>>,
             "#{path} contains a literal escape character; use Foglet.TUI.Text or Raxol style opts"
    end
  end
end
