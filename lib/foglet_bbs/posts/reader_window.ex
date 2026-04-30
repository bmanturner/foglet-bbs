defmodule Foglet.Posts.ReaderWindow do
  @moduledoc """
  Bounded, tombstone-capable post window for reader/history consumers.

  The posts list is always returned in ascending `message_number` order, even
  when the query direction fetches newest rows first internally.
  """

  alias Foglet.Posts.Post

  @type direction :: :initial | :next | :previous | :last | :around

  @type t :: %__MODULE__{
          posts: [Post.t()],
          first_message_number: pos_integer() | nil,
          last_message_number: pos_integer() | nil,
          has_previous?: boolean(),
          has_next?: boolean(),
          direction: direction()
        }

  @enforce_keys [:posts, :has_previous?, :has_next?]
  defstruct posts: [],
            first_message_number: nil,
            last_message_number: nil,
            has_previous?: false,
            has_next?: false,
            direction: :initial
end
