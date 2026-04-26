defmodule Foglet.QueryHelpers do
  @moduledoc """
  Reusable Ecto query fragments for cross-context predicates.

  These exist to keep soft-delete and archive semantics consistent.
  If you change one of these helpers, every caller is updated atomically.
  """

  import Ecto.Query

  @doc "Filters out rows where `deleted_at` is set."
  def not_deleted(query) do
    where(query, [x], is_nil(x.deleted_at))
  end

  @doc "Filters out rows where `archived` is true."
  def not_archived(query) do
    where(query, [x], x.archived == false)
  end

  @doc """
  Filters to boards in non-archived categories with both board and category
  not archived. Requires the query to have named bindings `b` (board) and
  `c` (category).

  Used in `list_boards/0`, `list_subscribed_boards/1`, and
  `board_scope_rows/2` — any query that joins boards to their category and
  filters out archived entries on both sides.
  """
  def active_boards(query) do
    query
    |> where([b: b], b.archived == false)
    |> where([c: c], c.archived == false)
  end
end
