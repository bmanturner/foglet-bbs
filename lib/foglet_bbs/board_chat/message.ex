defmodule Foglet.BoardChat.Message do
  @moduledoc """
  Schema for permanent board chat messages (FOG-242 C3).

  Rows live in this table only when the owning board is configured with
  `chat_storage_mode = :permanent`. Inserts go through
  `Foglet.BoardChat.Permanent.insert/3`, which enforces the storage-mode
  invariant before writing.
  """
  use Foglet.Schema

  alias Foglet.BoardChat.Body

  @type t :: %__MODULE__{}

  schema "board_chat_messages" do
    field :body, :string
    field :kind, Ecto.Enum, values: [:text, :action], default: :text
    field :metadata, :map, default: %{}

    belongs_to :board, Foglet.Boards.Board
    belongs_to :user, Foglet.Accounts.User

    timestamps()
  end

  @doc "Maximum allowed message body length, in characters."
  def body_max, do: Body.max_length()

  @doc """
  Insert changeset. `board_id` and `user_id` are set on the struct by the
  context, not cast from user input.
  """
  def insert_changeset(message, attrs) do
    message
    |> cast(attrs, [:body, :kind, :metadata])
    |> update_change(:body, &Body.trim/1)
    |> validate_required([:body, :kind, :metadata])
    |> validate_length(:body, min: 1, max: Body.max_length())
    |> foreign_key_constraint(:board_id)
    |> foreign_key_constraint(:user_id)
  end
end
