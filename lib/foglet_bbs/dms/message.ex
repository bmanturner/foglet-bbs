defmodule Foglet.DMs.Message do
  @moduledoc """
  Durable two-party direct message row.

  Deletion is per participant: sender and recipient each get an independent
  timestamp that hides the row from their own conversation view without changing
  the other participant's history.
  """

  use Foglet.Schema

  @type t :: %__MODULE__{}

  schema "direct_messages" do
    field :body, :string
    field :read_at, :utc_datetime_usec
    field :deleted_by_sender_at, :utc_datetime_usec
    field :deleted_by_recipient_at, :utc_datetime_usec

    belongs_to :sender, Foglet.Accounts.User
    belongs_to :recipient, Foglet.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  @doc "Builds a trusted insert changeset for direct messages."
  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(message, attrs) do
    message
    |> cast(attrs, [:body])
    |> update_change(:body, &String.trim/1)
    |> validate_required([:sender_id, :recipient_id, :body])
    |> validate_length(:body, min: 1, max: 20_000)
    |> foreign_key_constraint(:sender_id)
    |> foreign_key_constraint(:recipient_id)
  end
end
