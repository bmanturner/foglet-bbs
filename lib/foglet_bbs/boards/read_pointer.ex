defmodule Foglet.Boards.ReadPointer do
  @moduledoc "Schema for board read pointers — tracks last-read message number per user per board."
  use Foglet.Schema

  schema "board_read_pointers" do
    field :last_read_message_number, :integer, default: 0
    field :last_read_at, :utc_datetime_usec

    belongs_to :user, Foglet.Accounts.User
    belongs_to :board, Foglet.Boards.Board

    timestamps(updated_at: false)
  end

  @doc "Changeset for upsert. user_id and board_id set on struct before calling."
  def changeset(pointer, attrs) do
    pointer
    |> cast(attrs, [:last_read_message_number, :last_read_at])
    |> validate_required([:last_read_message_number])
    |> unique_constraint([:user_id, :board_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:board_id)
  end
end
