defmodule Foglet.TUI.Widgets.Post.MarkdownBody do
  @moduledoc """
  Markdown-to-terminal body renderer for Foglet BBS (WIDGET-01, RENDER-01, RENDER-02).

  Consumes `Foglet.Markdown.render/1` output — a flat list of
  `{String.t(), style_atom}` tuples with `{"\\n", :plain}` separators
  between logical lines — and produces a `column` of `row`-wrapped
  `text/2` siblings, one row per logical line.

  ## Why per-line grouping (RENDER-01 root cause)

  The previous pipeline mapped every tuple 1:1 to a `text/2` node,
  including `{"\\n", :plain}` separators. Newlines became visible "\\n"
  children because `text/2` emits literal content and does not advance
  the layout cursor. Grouping tuples by newline separators and emitting
  one `row`-wrapped line per group lets the enclosing `column` provide
  line separation through sibling layout — the correct mechanism.

  ## Style mapping (D-06)

  | Foglet.Markdown style | Theme slot + text/2 style  |
  |-----------------------|----------------------------|
  | `:plain`              | `fg: theme.primary.fg`     |
  | `:bold`               | `fg: theme.accent.fg, style: [:bold]` |
  | `:italic`             | `fg: theme.primary.fg, style: [:italic]` |
  | `:dim` (code)         | `fg: theme.dim.fg, style: [:dim]` |
  | `:underline` (H1-H6)  | `fg: theme.title.fg, style: [:underline, :bold]` |

  Bold uses `theme.accent.fg` (amber in `:gray` / `:green`) rather than
  `theme.primary` so bold runs visually stand out from the body text
  without relying solely on the `:bold` terminal style (which some
  terminal emulators collapse). `:italic` and `:underline` compose the
  style attribute with a color, matching the existing pattern in
  `post_reader.ex:199-210`.

  ## Contract

      render(markdown_text, width, theme, opts \\\\ [])

      opts:
        scroll_offset: non_neg_integer()  (default 0)
        max_lines:     pos_integer() | :all (default :all)

  Returns a Raxol view element (a `column do ... end` block).
  `width` is accepted for future grapheme-aware wrapping; this
  implementation passes it through without hard-wrapping (see Plan
  objective for rationale).
  """

  import Raxol.Core.Renderer.View

  alias Foglet.Markdown
  alias Foglet.TUI.Theme

  @type style_atom :: :plain | :bold | :italic | :dim | :underline
  @type tuple_entry :: {String.t(), style_atom()}

  @doc """
  Render a markdown string to a Raxol view element.

  Strips/filters `{"\\n", :plain}` separator tuples, groups the
  remaining tuples into logical lines, and emits one `row`-wrapped
  line per group inside an outer `column`.
  """
  @spec render(String.t(), pos_integer(), Theme.t(), keyword()) :: any()
  def render(markdown_text, width, %Theme{} = theme, opts \\ [])
      when is_binary(markdown_text) and is_integer(width) and width > 0 do
    scroll_offset = Keyword.get(opts, :scroll_offset, 0)
    max_lines = Keyword.get(opts, :max_lines, :all)

    markdown_text
    |> Markdown.render()
    |> group_by_newline()
    |> window_lines(scroll_offset, max_lines)
    |> lines_to_column(theme)
  end

  @doc """
  Render from already-computed tuples (skips `Foglet.Markdown.render/1`).
  Used by PostCard when it wants to cache the markdown parse separately
  from the view assembly.
  """
  @spec render_tuples([tuple_entry()], pos_integer(), Theme.t(), keyword()) :: any()
  def render_tuples(tuples, width, %Theme{} = theme, opts \\ [])
      when is_list(tuples) and is_integer(width) and width > 0 do
    scroll_offset = Keyword.get(opts, :scroll_offset, 0)
    max_lines = Keyword.get(opts, :max_lines, :all)

    tuples
    |> group_by_newline()
    |> window_lines(scroll_offset, max_lines)
    |> lines_to_column(theme)
  end

  @doc """
  Render tuples as a flat list of Raxol row elements — one per logical line.

  Returned shape: a plain list (not a column). Each element is either a bare
  `text/2` (single-run line) or a `row/2` (multi-run line). Used by
  `Raxol.UI.Components.Display.Viewport` as `children:` — the Viewport owns
  windowing / scroll-slicing.

  Differs from `render_tuples/4` in two ways:
    * No column wrapper — returns the raw list.
    * No `scroll_offset` / `max_lines` windowing — opts are ignored.

  Empty input returns `[]`. The Viewport handles empty children gracefully.
  """
  @spec render_tuples_as_lines([tuple_entry()], pos_integer(), Theme.t(), keyword()) :: [any()]
  def render_tuples_as_lines(tuples, width, %Theme{} = theme, opts \\ [])
      when is_list(tuples) and is_integer(width) and width > 0 do
    _ = opts

    tuples
    |> group_by_newline()
    |> Enum.map(fn group -> line_group_to_row(group, theme) end)
  end

  @doc """
  Count the number of logical lines produced by a markdown string.
  Used by PostReader/PostCard to compute scroll bounds without
  re-rendering the view.
  """
  @spec line_count(String.t()) :: non_neg_integer()
  def line_count(markdown_text) when is_binary(markdown_text) do
    markdown_text
    |> Markdown.render()
    |> group_by_newline()
    |> length()
  end

  # ------------------------------------------------------------------
  # Private — line grouping
  # ------------------------------------------------------------------

  # Splits a flat `[{text, style}]` list into a list of line-groups,
  # dropping `{"\n", :plain}` separator tuples and empty groups.
  # Each group is a `[{text, style}]` list of one or more styled runs
  # that belong on the same physical line.
  @spec group_by_newline([tuple_entry()]) :: [[tuple_entry()]]
  defp group_by_newline(tuples) do
    tuples
    |> Enum.chunk_by(&newline?/1)
    |> Enum.reject(&newline_group?/1)
  end

  defp newline?({"\n", :plain}), do: true
  defp newline?(_), do: false

  defp newline_group?([{"\n", :plain} | _]), do: true
  defp newline_group?([]), do: true
  defp newline_group?(_), do: false

  # Apply scroll_offset / max_lines to the list of line-groups.
  defp window_lines(lines, 0, :all), do: lines

  defp window_lines(lines, scroll_offset, :all) when scroll_offset > 0 do
    Enum.drop(lines, scroll_offset)
  end

  defp window_lines(lines, scroll_offset, max_lines)
       when is_integer(max_lines) and max_lines > 0 and scroll_offset >= 0 do
    lines
    |> Enum.drop(scroll_offset)
    |> Enum.take(max_lines)
  end

  # ------------------------------------------------------------------
  # Private — view emission
  # ------------------------------------------------------------------

  # Emits `column do [row do [text, text, ...] end, ...] end`.
  #
  # Empty list → a column containing a single blank text (keeps the
  # outer layout rectangle predictable for callers). Raxol's `column`
  # macro raises on an empty `do` block in some builds.
  defp lines_to_column([], theme) do
    column style: %{gap: 0} do
      [text("", fg: theme.primary.fg)]
    end
  end

  defp lines_to_column(line_groups, theme) do
    rows = Enum.map(line_groups, fn group -> line_group_to_row(group, theme) end)

    column style: %{gap: 0} do
      rows
    end
  end

  # A single logical line becomes a `row` of styled `text/2` siblings.
  # A row with a single plain run collapses to a bare `text/2` (avoids
  # an unnecessary row wrapper and matches the terseness of
  # `text("", ...)` used elsewhere).
  defp line_group_to_row([{s, style}], theme) do
    styled_text(s, style, theme)
  end

  defp line_group_to_row(tuples, theme) do
    children = Enum.map(tuples, fn {s, style} -> styled_text(s, style, theme) end)

    row style: %{gap: 0} do
      children
    end
  end

  # Style-atom → text/2 call. Maps atoms to theme slots per D-06.
  defp styled_text(s, :plain, theme), do: text(s, fg: theme.primary.fg)

  defp styled_text(s, :bold, theme),
    do: text(s, fg: theme.accent.fg, style: [:bold])

  defp styled_text(s, :italic, theme),
    do: text(s, fg: theme.primary.fg, style: [:italic])

  defp styled_text(s, :dim, theme),
    do: text(s, fg: theme.dim.fg, style: [:dim])

  defp styled_text(s, :underline, theme),
    do: text(s, fg: theme.title.fg, style: [:underline, :bold])

  # Unknown style atom → fall back to plain (defensive, matches the
  # wildcard clause in the old `render_markdown_tuples/2`).
  defp styled_text(s, _unknown, theme), do: text(s, fg: theme.primary.fg)
end
