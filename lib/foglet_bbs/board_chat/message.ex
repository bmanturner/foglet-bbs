defmodule Foglet.BoardChat.Message do
  @moduledoc """
  Schema for permanent board chat messages (FOG-242 C3).

  Rows live in this table only when the owning board is configured with
  `chat_storage_mode = :permanent`. Inserts go through
  `Foglet.BoardChat.Permanent.insert/3`, which enforces the storage-mode
  invariant before writing.
  """
  use Foglet.Schema

  @type t :: %__MODULE__{}

  @body_max 4_000

  schema "board_chat_messages" do
    field :body, :string

    belongs_to :board, Foglet.Boards.Board
    belongs_to :user, Foglet.Accounts.User

    timestamps()
  end

  @doc "Maximum allowed message body length, in characters."
  def body_max, do: @body_max

  @doc """
  Insert changeset. `board_id` and `user_id` are set on the struct by the
  context, not cast from user input.
  """
  def insert_changeset(message, attrs) do
    message
    |> cast(attrs, [:body])
    |> update_change(:body, &trim_body/1)
    |> validate_required([:body])
    |> validate_length(:body, min: 1, max: @body_max)
    |> foreign_key_constraint(:board_id)
    |> foreign_key_constraint(:user_id)
  end

  defp trim_body(nil), do: nil
  defp trim_body(body) when is_binary(body), do: String.trim(body)
  defp trim_body(other), do: other
end
