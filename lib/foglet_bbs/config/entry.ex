defmodule Foglet.Config.Entry do
  @moduledoc """
  Sysop-editable runtime configuration entry. See `docs/DATA_MODEL.md` §11.

  Values are always wrapped as `%{"v" => actual_value}` to avoid jsonb
  scalar quirks — this is a DB-level concern; callers of
  `Foglet.Config.get!/1` see only the unwrapped value.
  """

  use Foglet.Schema

  @type t :: %__MODULE__{}

  schema "configuration" do
    field :key, :string
    field :value, :map
    field :description, :string

    belongs_to :updated_by, Foglet.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:key, :value, :description, :updated_by_id])
    |> validate_required([:key, :value])
    |> validate_length(:key, min: 1, max: 128)
    |> unique_constraint(:key)
  end
end
