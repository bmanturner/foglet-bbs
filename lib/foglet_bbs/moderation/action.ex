defmodule Foglet.Moderation.Action do
  @moduledoc """
  Durable moderation audit action.

  This schema is intentionally narrow in v1.1: only oneliner hide actions are
  persisted here.
  """

  use Foglet.Schema

  @type t :: %__MODULE__{}

  schema "mod_actions" do
    field :kind, Ecto.Enum, values: [:hide_oneliner]
    field :target_kind, Ecto.Enum, values: [:oneliner]
    field :target_id, Ecto.UUID
    field :reason, :string
    field :metadata, :map, default: %{}

    belongs_to :mod, Foglet.Accounts.User

    timestamps(updated_at: false)
  end

  @doc """
  Builds a changeset for a trusted moderation audit action.

  Moderator ownership is set on the struct by the calling context before this
  changeset runs; caller attrs never cast `mod_id`.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(action, attrs) do
    action
    |> cast(attrs, [:kind, :target_kind, :target_id, :reason, :metadata])
    |> update_change(:reason, &String.trim/1)
    |> validate_required([:kind, :target_kind, :target_id, :reason, :mod_id])
  end
end
