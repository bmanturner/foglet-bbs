defmodule Foglet.TUI.Widgets.List.ListRow do
  @moduledoc """
  Individual list row renderer for Foglet BBS selection lists (WIDGET-01, LIST-03).

  Two public entry points:

    * `render/3` — a simple row with selection marker and a flat title.
      Used by BoardList and the NewThread board picker. Unchanged from
      Phase 1.

    * `render_with_metadata/6` (callable as `/5` and `/6` — default
      opts) — a row with left-aligned title, right-aligned metadata,
      and optional bold-on-unread treatment. Used by ThreadList rows
      (LIST-03) to display `"@handle · N posts · Xh ago"` right-aligned
      against a left-aligned thread title with a `…` truncation
      fallback on narrow terminals.

  ## UI-SPEC contract

  Selected:   fg: theme.selected.fg, bg: theme.selected.bg, style: [:bold]
  Unselected: fg: theme.unselected.fg (or theme.primary.fg + :bold when unread)
  Metadata:   fg: theme.dim.fg (or selection fg when selected)
  Marker:     "> " (selected) / "  " (unselected) — 2 graphemes

  Terminal width is provided by the caller; the function assumes no
  chrome overhead (that's the ScreenFrame's job) so `width` is the
  inner content width.
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.Theme

  @min_title_length 20
  @ellipsis "…"

  @doc """
  Renders a single selectable row (Phase 1 signature — unchanged).

  `label`    — the display string for this row (already formatted by caller)
  `selected` — true if this row is the currently selected item
  `theme`    — the session theme struct
  """
  @spec render(String.t(), boolean(), Theme.t()) :: any()
  def render(label, selected, theme) do
    marker = if selected, do: "> ", else: "  "
    full = "#{marker}#{label}"

    if selected do
      selected_style = Map.get(theme.selected, :style, [:bold])
      text(full, fg: theme.selected.fg, bg: theme.selected.bg, style: selected_style)
    else
      text(full, fg: theme.unselected.fg)
    end
  end

  @doc """
  Renders a row with a left-aligned title and right-aligned metadata
  (LIST-03).

  Parameters:

    * `title`    — the title string (without a selection marker; the
                   function prepends `"> "` / `"  "`).
    * `metadata` — the metadata string (e.g. `"@alice · 5 posts · 2h ago"`).
                   Rendered dim on the right side and always fully visible
                   — the title truncates before the metadata does.
    * `selected` — true if this row is the currently selected item.
    * `unread?`  — true if the row should render with bold title
                   (ignored when `selected` is true; selection highlight
                   takes precedence).
    * `theme`    — the session theme struct.
    * `opts`     — keyword list:
        * `:width` — the inner content width in terminal cells. Required;
                     omit at your peril (defaults to 80 for safety).

  Layout:

      "> title text……………………………………… @handle · 5 posts · 2h ago"
      ^^ marker (2)   ^^^^^^^^^^^^^^^^^^ padding    ^^^^^^^^^^^^^^^^^^^^^^ metadata

  When `title + 2 (gap) + metadata > width`, the title truncates with
  `"…"`. Minimum kept title length is `@min_title_length` graphemes
  (20 today); below that the function still preserves the full
  metadata and emits at least one grapheme of title + `"…"`.
  """
  @spec render_with_metadata(
          String.t(),
          String.t(),
          boolean(),
          boolean(),
          Theme.t(),
          keyword()
        ) :: any()
  def render_with_metadata(title, metadata, selected, unread?, theme, opts \\ []) do
    width = Keyword.get(opts, :width, 80)
    marker = if selected, do: "> ", else: "  "

    {title_part, padding_part, metadata_part} =
      compute_parts(marker, title, metadata, width)

    {title_style, metadata_style, padding_style} =
      styles_for(selected, unread?, theme)

    row style: %{gap: 0} do
      [
        text(title_part, title_style),
        text(padding_part, padding_style),
        text(metadata_part, metadata_style)
      ]
    end
  end

  # ---------------------------------------------------------------
  # Private — layout math
  # ---------------------------------------------------------------

  @spec compute_parts(String.t(), String.t(), String.t(), pos_integer()) ::
          {String.t(), String.t(), String.t()}
  defp compute_parts(marker, title, metadata, width) do
    marker_len = String.length(marker)
    metadata_len = String.length(metadata)
    min_gap = 2

    max_title_body = max(width - marker_len - min_gap - metadata_len, 0)
    title_body = truncate_title(title, max_title_body)

    title_part = marker <> title_body
    title_part_len = marker_len + String.length(title_body)

    # Clamp padding so total length does not exceed width.
    # If metadata alone exceeds width, padding collapses to 0 — metadata
    # visibility is the priority contract, so we accept the overflow.
    padding_len =
      (width - title_part_len - metadata_len)
      |> max(0)
      |> min(width)

    padding_part = String.duplicate(" ", padding_len)

    {title_part, padding_part, metadata}
  end

  @spec truncate_title(String.t(), non_neg_integer()) :: String.t()
  defp truncate_title(title, max_len) do
    # max_len == 0: first clause fires (empty title has length 0 <= 0) → returns ""
    # max_len == 1: falls to `true` clause → returns @ellipsis
    # max_len >= 2 and < @min_title_length: below-minimum fallback — emit 1 char + ellipsis
    # max_len >= @min_title_length: standard truncation with ellipsis
    title_len = String.length(title)

    cond do
      title_len <= max_len ->
        title

      max_len >= @min_title_length ->
        String.slice(title, 0, max_len - 1) <> @ellipsis

      max_len >= 2 ->
        # Below minimum title length — emit at least 1 char + ellipsis
        String.slice(title, 0, 1) <> @ellipsis

      true ->
        @ellipsis
    end
  end

  # ---------------------------------------------------------------
  # Private — style selection
  # ---------------------------------------------------------------

  defp styles_for(true = _selected, _unread?, theme) do
    selected_style = Map.get(theme.selected, :style, [:bold])
    sel_kw = [fg: theme.selected.fg, bg: theme.selected.bg, style: selected_style]

    {sel_kw, sel_kw, sel_kw}
  end

  defp styles_for(false = _selected, true = _unread?, theme) do
    {
      [fg: theme.primary.fg, style: [:bold]],
      [fg: theme.dim.fg],
      [fg: theme.dim.fg]
    }
  end

  defp styles_for(false = _selected, false = _unread?, theme) do
    {
      [fg: theme.unselected.fg],
      [fg: theme.dim.fg],
      [fg: theme.dim.fg]
    }
  end
end
