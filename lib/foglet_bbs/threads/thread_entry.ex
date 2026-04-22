defmodule Foglet.Threads.ThreadEntry do
  @moduledoc """
  Read-model projection of a thread row as returned by `Foglet.Threads.list_threads/2`.

  Carries the scalar thread fields from the database `select:` projection, a
  computed boolean `:has_unread` annotation (true when the thread has activity
  newer than the user's last read pointer), and a batch-preloaded `:created_by`
  association.

  This is a plain Elixir struct — not an Ecto schema — and exists solely to give
  the thread-list pipeline a named, dialyzer-visible shape instead of an anonymous
  `map()`.
  """

  @type t :: %__MODULE__{
          id: String.t() | nil,
          title: String.t() | nil,
          board_id: String.t() | nil,
          sticky: boolean() | nil,
          locked: boolean() | nil,
          post_count: non_neg_integer() | nil,
          first_post_id: String.t() | nil,
          last_post_at: DateTime.t() | nil,
          deleted_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          created_by_id: String.t() | nil,
          has_unread: boolean() | nil,
          created_by: Foglet.Accounts.User.t() | nil
        }

  defstruct [
    :id,
    :title,
    :board_id,
    :sticky,
    :locked,
    :post_count,
    :first_post_id,
    :last_post_at,
    :deleted_at,
    :inserted_at,
    :created_by_id,
    :has_unread,
    :created_by
  ]
end
