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
        wrap:          boolean() (default false)

  Returns a Raxol view element (a `column do ... end` block). When `wrap: true`
  is passed, lines are wrapped to the supplied terminal display width before
  view elements are emitted.
  """

  import Raxol.Core.Renderer.View

  alias Foglet.Markdown
  alias Foglet.TUI.TextWidth
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
    wrap? = Keyword.get(opts, :wrap, false)

    markdown_text
    |> Markdown.render()
    |> group_by_newline()
    |> maybe_wrap_lines(width, wrap?)
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
    wrap? = Keyword.get(opts, :wrap, false)

    tuples
    |> group_by_newline()
    |> maybe_wrap_lines(width, wrap?)
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
    wrap? = Keyword.get(opts, :wrap, false)

    tuples
    |> group_by_newline()
    |> maybe_wrap_lines(width, wrap?)
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

  # Splits a flat `[{text, style}]` list into line groups while preserving
  # exactly one blank visible line for paragraph separators.
  @spec group_by_newline([tuple_entry()]) :: [[tuple_entry()]]
  defp group_by_newline(tuples) do
    tuples
    |> Enum.reduce({[], [], 0}, &group_tuple/2)
    |> finish_line_groups()
  end

  defp newline?({"\n", :plain}), do: true
  defp newline?(_), do: false

  defp group_tuple(tuple, {groups, current, newline_count}) do
    if newline?(tuple) do
      {groups, current, newline_count + 1}
    else
      if newline_count > 0 do
        groups = flush_newlines(groups, current, newline_count)
        {groups, [tuple], 0}
      else
        {groups, [tuple | current], 0}
      end
    end
  end

  defp finish_line_groups({groups, current, newline_count}) do
    groups
    |> flush_newlines(current, newline_count)
    |> Enum.reverse()
  end

  defp flush_newlines(groups, [], _newline_count), do: groups

  defp flush_newlines(groups, current, newline_count) when newline_count >= 2 do
    [[], Enum.reverse(current) | groups]
  end

  defp flush_newlines(groups, current, _newline_count) do
    [Enum.reverse(current) | groups]
  end

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
  # Private — display-width wrapping
  # ------------------------------------------------------------------

  defp maybe_wrap_lines(line_groups, _width, false), do: line_groups
  defp maybe_wrap_lines(line_groups, width, true), do: wrap_lines(line_groups, width)

  defp wrap_lines(line_groups, width) do
    Enum.flat_map(line_groups, &wrap_line_group(&1, width))
  end

  defp wrap_line_group([], _width), do: [[]]

  defp wrap_line_group(line_group, width) when is_integer(width) and width > 0 do
    {lines, current} =
      line_group
      |> tokenize_group()
      |> Enum.reduce({[], []}, fn token, acc -> append_wrap_token(acc, token, width) end)

    finish_wrapped_lines(lines, current)
  end

  defp tokenize_group(line_group) do
    Enum.flat_map(line_group, fn {string, style} ->
      string
      |> String.split(~r/(\s+)/, include_captures: true, trim: true)
      |> Enum.map(fn token -> {token, style} end)
    end)
  end

  defp append_wrap_token({lines, current}, {token, style}, width) do
    cond do
      whitespace?(token) ->
        append_whitespace_token({lines, current}, {token, style}, width)

      current == [] ->
        start_wrapped_line(lines, {String.trim_leading(token), style}, width)

      TextWidth.display_width(line_text(current) <> token) <= width ->
        {lines, current ++ [{token, style}]}

      true ->
        start_wrapped_line(
          lines ++ [trim_line_trailing(current)],
          {String.trim_leading(token), style},
          width
        )
    end
  end

  defp append_whitespace_token({lines, current}, {token, style}, width) do
    if current != [] and TextWidth.display_width(line_text(current) <> token) <= width do
      {lines, current ++ [{token, style}]}
    else
      {lines, current}
    end
  end

  defp start_wrapped_line(lines, {"", _style}, _width), do: {lines, []}

  defp start_wrapped_line(lines, {token, style}, width) do
    chunks = split_token(token, style, width, [])

    case chunks do
      [] ->
        {lines, []}

      [current] ->
        {lines, current}

      chunks ->
        {complete, [current]} = Enum.split(chunks, -1)
        {lines ++ complete, current}
    end
  end

  defp split_token("", _style, _width, chunks), do: Enum.reverse(chunks)

  defp split_token(token, style, width, chunks) do
    if TextWidth.display_width(token) <= width do
      Enum.reverse([[{token, style}] | chunks])
    else
      {left, right} = TextWidth.split_at(token, width)

      if left == "" do
        Enum.reverse(chunks)
      else
        split_token(right, style, width, [[{left, style}] | chunks])
      end
    end
  end

  defp finish_wrapped_lines([], []), do: [[]]
  defp finish_wrapped_lines(lines, []), do: Enum.map(lines, &compact_line/1)

  defp finish_wrapped_lines(lines, current),
    do: Enum.map(lines ++ [trim_line_trailing(current)], &compact_line/1)

  defp whitespace?(token), do: String.match?(token, ~r/^\s+$/)

  defp line_text(line), do: Enum.map_join(line, fn {token, _style} -> token end)

  defp trim_line_trailing(line) do
    {rev, trimmed?} =
      line
      |> Enum.reverse()
      |> Enum.reduce({[], false}, fn
        {token, style}, {acc, false} ->
          trimmed = String.trim_trailing(token)

          cond do
            trimmed == "" -> {acc, false}
            trimmed == token -> {[{token, style} | acc], true}
            true -> {[{trimmed, style} | acc], true}
          end

        tuple, {acc, true} ->
          {[tuple | acc], true}
      end)

    case {rev, trimmed?} do
      {[], _} -> []
      {trimmed, _} -> trimmed
    end
  end

  defp compact_line(line) do
    line
    |> Enum.reduce([], fn
      {text, style}, [{previous, style} | rest] ->
        [{previous <> text, style} | rest]

      tuple, acc ->
        [tuple | acc]
    end)
    |> Enum.reverse()
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
  defp line_group_to_row([], theme) do
    text("", fg: theme.primary.fg)
  end

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
