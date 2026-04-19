defmodule Foglet.TUI.Widgets.List.SelectionList do
  @moduledoc """
  Shared selection list renderer for Foglet BBS (LIST-04, WIDGET-01).

  A pure rendering widget — no internal state. Parent screens own
  selected_index (in state.screen_state). Navigation (j/k/Enter)
  stays in screen modules.

  API:
    SelectionList.render(items, selected_index, row_renderer_fn)

  Where row_renderer_fn receives {item, idx, selected?} and must
  return a Raxol view element (typically via List.ListRow.render/3
  or inline text/2 calls).

  Used by: BoardList, ThreadList, NewThread board picker.
  """

  import Raxol.Core.Renderer.View

  @doc """
  Renders the selection list.

  `items`           — list of items to render (any term)
  `selected_index`  — 0-based index of the currently selected item
  `row_renderer_fn` — fn({item, idx, selected?}) -> view_element
  """
  @spec render(list(), non_neg_integer(), ({any(), non_neg_integer(), boolean()} -> any())) :: any()
  def render(items, selected_index, row_renderer_fn)
      when is_list(items) and is_integer(selected_index) and is_function(row_renderer_fn, 1) do
    rows =
      items
      |> Enum.with_index()
      |> Enum.map(fn {item, idx} ->
        selected = idx == selected_index
        row_renderer_fn.({item, idx, selected})
      end)

    column style: %{gap: 0} do
      rows
    end
  end
end
