defmodule Foglet.TUI.Widgets.List.RichRow do
  @moduledoc """
  Stateless rich-row renderer for Foglet BBS selection lists.

  Rich rows combine a focus marker, fixed-width state-glyph cluster,
  truncating title, and optional right-aligned metadata. All color and style
  choices route through `Foglet.TUI.Theme`.
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme

  @cluster_width 4
  @focus_marker "▌ "
  @no_focus_marker "  "
  @ellipsis "…"
  @min_title_length 20
  @glyph_unread "◆"
  @glyph_sticky "●"
  @glyph_locked "⚿"
  @glyph_space " "

  @typedoc "State atoms rendered in the fixed cluster."
  @type state_atom :: :unread | :sticky | :locked | atom()

  @doc """
  Renders a rich list row.

  Required keyword keys:

    * `:title`
    * `:state_cluster`
    * `:selected`
    * `:theme`

  Optional keyword keys:

    * `:metadata` - defaults to `""`; `nil` also means no metadata
    * `:width` - defaults to `80`
    * `:focus_marker` - defaults to `"▌ "`
    * `:emphasis` - currently supports `:bold`
  """
  @spec render(keyword()) :: any()
  def render(opts) when is_list(opts) do
    title = opts |> Keyword.fetch!(:title) |> to_string()
    state_cluster = Keyword.fetch!(opts, :state_cluster)
    selected = Keyword.fetch!(opts, :selected)
    theme = Keyword.fetch!(opts, :theme)

    metadata = opts |> Keyword.get(:metadata, "") |> normalize_metadata()
    width = Keyword.get(opts, :width, 80)
    focus_marker = Keyword.get(opts, :focus_marker, @focus_marker)
    emphasis = Keyword.get(opts, :emphasis, emphasis_for(state_cluster))
    marker = if selected, do: focus_marker, else: @no_focus_marker

    {title_part, padding_part, metadata_part} =
      compute_parts(marker, title, metadata, width)

    marker_style = marker_style(selected, theme)
    glyph_nodes = glyph_nodes(state_cluster, selected, theme)
    separator_style = absent_glyph_style(selected, theme)
    {title_style, metadata_style, padding_style} = styles_for(selected, emphasis, theme)

    children =
      [
        text(marker, marker_style),
        glyph_nodes,
        text(@glyph_space, separator_style),
        text(title_part, title_style),
        text(padding_part, padding_style)
      ]
      |> List.flatten()
      |> maybe_append_metadata(metadata_part, metadata_style)

    row style: %{gap: 0} do
      children
    end
  end

  @doc false
  @spec cluster_width() :: pos_integer()
  def cluster_width, do: @cluster_width

  @spec normalize_metadata(nil | term()) :: String.t()
  defp normalize_metadata(nil), do: ""
  defp normalize_metadata(metadata), do: to_string(metadata)

  @spec emphasis_for([state_atom()]) :: :bold | nil
  defp emphasis_for(state_cluster) when is_list(state_cluster) do
    if :unread in state_cluster, do: :bold
  end

  @spec glyph_nodes([state_atom()], boolean(), Theme.t()) :: [any()]
  defp glyph_nodes(state_cluster, selected, theme) when is_list(state_cluster) do
    state_set = MapSet.new(state_cluster)

    [
      glyph_node(state_set, :unread, @glyph_unread, :accent, selected, theme),
      glyph_node(state_set, :sticky, @glyph_sticky, :info, selected, theme),
      glyph_node(state_set, :locked, @glyph_locked, :warning, selected, theme)
    ]
  end

  @spec glyph_node(MapSet.t(), atom(), String.t(), atom(), boolean(), Theme.t()) :: any()
  defp glyph_node(state_set, state, glyph, slot, selected, theme) do
    if MapSet.member?(state_set, state) do
      text(glyph, glyph_style(slot, selected, theme))
    else
      text(@glyph_space, absent_glyph_style(selected, theme))
    end
  end

  @spec compute_parts(String.t(), String.t(), String.t(), pos_integer()) ::
          {String.t(), String.t(), String.t()}
  defp compute_parts(marker, title, metadata, width) do
    marker_width = TextWidth.display_width(marker)
    reserved_width = marker_width + @cluster_width

    if metadata == "" do
      title_width = max(width - reserved_width, 0)
      title_part = title |> truncate_title(title_width) |> TextWidth.pad_trailing(title_width)

      {title_part, "", ""}
    else
      metadata_width = TextWidth.display_width(metadata)
      min_gap = 2
      max_title_width = max(width - reserved_width - min_gap - metadata_width, 0)
      title_part = truncate_title(title, max_title_width)
      title_width = TextWidth.display_width(title_part)

      padding_width =
        width
        |> Kernel.-(reserved_width)
        |> Kernel.-(title_width)
        |> Kernel.-(metadata_width)
        |> max(0)

      {title_part, TextWidth.pad_trailing("", padding_width), metadata}
    end
  end

  @spec truncate_title(String.t(), non_neg_integer()) :: String.t()
  defp truncate_title(title, max_width) do
    title_width = TextWidth.display_width(title)

    cond do
      title_width <= max_width ->
        title

      max_width >= @min_title_length ->
        TextWidth.truncate(title, max_width)

      max_width >= 2 ->
        TextWidth.truncate(title, min(max_width, TextWidth.display_width(@ellipsis) + 1))

      true ->
        TextWidth.truncate(title, max_width)
    end
  end

  @spec styles_for(boolean(), :bold | nil, Theme.t()) :: {keyword(), keyword(), keyword()}
  defp styles_for(true, _emphasis, theme) do
    selected_style = Map.get(theme.selected, :style, [:bold])
    style = [fg: theme.selected.fg, bg: theme.selected.bg, style: selected_style]

    {style, style, style}
  end

  defp styles_for(false, :bold, theme) do
    {
      [fg: theme.accent.fg, style: [:bold]],
      [fg: theme.dim.fg],
      [fg: theme.dim.fg]
    }
  end

  defp styles_for(false, _emphasis, theme) do
    {
      [fg: theme.unselected.fg],
      [fg: theme.dim.fg],
      [fg: theme.dim.fg]
    }
  end

  @spec marker_style(boolean(), Theme.t()) :: keyword()
  defp marker_style(true, theme) do
    [
      fg: theme.selected.fg,
      bg: theme.selected.bg,
      style: Map.get(theme.selected, :style, [:bold])
    ]
  end

  defp marker_style(false, theme), do: [fg: theme.unselected.fg]

  @spec glyph_style(:accent | :info | :warning, boolean(), Theme.t()) :: keyword()
  defp glyph_style(slot, true, theme) do
    slot_style =
      theme
      |> Map.fetch!(slot)
      |> Map.get(:style, [])

    [
      fg: theme |> Map.fetch!(slot) |> Map.fetch!(:fg),
      bg: theme.selected.bg,
      style: Enum.uniq(slot_style ++ [:bold])
    ]
  end

  defp glyph_style(slot, false, theme) do
    slot_style = Map.fetch!(theme, slot)
    style = Map.get(slot_style, :style, [])

    if style == [] do
      [fg: Map.fetch!(slot_style, :fg)]
    else
      [fg: Map.fetch!(slot_style, :fg), style: style]
    end
  end

  @spec absent_glyph_style(boolean(), Theme.t()) :: keyword()
  defp absent_glyph_style(true, theme) do
    [fg: theme.dim.fg, bg: theme.selected.bg, style: Map.get(theme.selected, :style, [:bold])]
  end

  defp absent_glyph_style(false, theme), do: [fg: theme.dim.fg]

  @spec maybe_append_metadata([any()], String.t(), keyword()) :: [any()]
  defp maybe_append_metadata(children, "", _metadata_style), do: children

  defp maybe_append_metadata(children, metadata, metadata_style),
    do: children ++ [text(metadata, metadata_style)]
end
