defmodule Foglet.Oneliners.Entry do
  @moduledoc """
  Persisted oneliner entry schema.

  Entries are created by `Foglet.Oneliners`; ownership and moderation fields are
  assigned by trusted domain code, not caller attributes.
  """

  use Foglet.Schema

  @type t :: %__MODULE__{}

  schema "oneliners" do
    field :body, :string
    field :hidden, :boolean, default: false
    field :hidden_reason, :string

    belongs_to :user, Foglet.Accounts.User
    belongs_to :hidden_by, Foglet.Accounts.User

    timestamps(updated_at: false)
  end

  @doc """
  Builds a changeset for user-submitted oneliner content.

  Only the body is caller-controlled. Ownership is expected to be present on the
  entry struct before this function is called.
  """
  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(entry, attrs) do
    entry
    |> cast(attrs, [:body])
    |> update_change(:body, &String.trim/1)
    |> validate_required([:body, :user_id])
    |> validate_length(:body, min: 1, max: 120)
  end

  @doc """
  Builds a changeset for a trusted moderation hide operation.

  The moderator id is passed separately and applied programmatically; it is not
  accepted from caller-controlled attrs.
  """
  @spec hide_changeset(t(), String.t(), Ecto.UUID.t()) :: Ecto.Changeset.t()
  def hide_changeset(entry, reason, moderator_id) do
    entry
    |> change(hidden: true, hidden_reason: reason, hidden_by_id: moderator_id)
    |> update_change(:hidden_reason, &String.trim/1)
    |> validate_required([:hidden, :hidden_reason, :hidden_by_id])
  end
end
