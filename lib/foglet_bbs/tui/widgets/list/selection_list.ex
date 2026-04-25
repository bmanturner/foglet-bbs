defmodule Foglet.TUI.Widgets.List.SelectionList do
  @moduledoc """
  Shared selection list renderer for Foglet BBS (LIST-04, WIDGET-01).

  A pure rendering widget — no internal state. Parent screens own
  selected_index (in state.screen_state). Navigation (j/k/Enter)
  stays in screen modules.

  API:
    SelectionList.render(items, selected_index, row_renderer_fn)
    SelectionList.render(items, selected_index, row_renderer_fn, theme: theme)

  Where row_renderer_fn receives {item, idx, selected?} and must
  return a Raxol view element (typically via List.ListRow.render/3
  or inline text/2 calls).

  Used by: BoardList, ThreadList, NewThread board picker.
  """

  import Raxol.Core.Renderer.View
  alias Foglet.TUI.Theme

  @type flex_column :: %{
          required(:type) => :flex,
          required(:direction) => :column,
          required(:children) => any(),
          required(:style) => any(),
          required(:gap) => any(),
          required(:align) => any(),
          required(:justify) => any()
        }

  @doc """
  Renders the selection list.

  `items`           — list of items to render (any term)
  `selected_index`  — 0-based index of the currently selected item
  `row_renderer_fn` — fn({item, idx, selected?}) -> view_element
  `opts`            — optional `:theme` for built-in empty-state styling
  """
  @spec render(list(), non_neg_integer(), ({any(), non_neg_integer(), boolean()} -> any())) ::
          flex_column()
  def render(items, selected_index, row_renderer_fn)
      when is_list(items) and is_integer(selected_index) and is_function(row_renderer_fn, 1) do
    render(items, selected_index, row_renderer_fn, [])
  end

  @spec render(
          list(),
          non_neg_integer(),
          ({any(), non_neg_integer(), boolean()} -> any()),
          keyword()
        ) :: flex_column()
  def render(items, selected_index, row_renderer_fn, opts)
      when is_list(items) and is_integer(selected_index) and is_function(row_renderer_fn, 1) and
             is_list(opts) do
    theme = Keyword.get(opts, :theme)

    rows =
      case {items, theme} do
        {[], %Theme{} = theme} ->
          [text("No items", fg: theme.dim.fg)]

        _ ->
          items
          |> Enum.with_index()
          |> Enum.map(fn {item, idx} ->
            selected = idx == selected_index
            row_renderer_fn.({item, idx, selected})
          end)
      end

    column style: %{gap: 0} do
      rows
    end
  end
end
