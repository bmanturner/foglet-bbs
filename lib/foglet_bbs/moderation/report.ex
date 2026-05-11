defmodule Foglet.Moderation.Report do
  @moduledoc """
  Durable moderation report for posts, oneliners, and users.
  """

  use Foglet.Schema

  @type t :: %__MODULE__{}

  @target_kinds [:post, :oneliner, :user]
  @statuses [:open, :resolved, :dismissed]

  schema "reports" do
    field :target_kind, Ecto.Enum, values: @target_kinds
    field :target_id, Ecto.UUID
    field :reason, :string
    field :notes, :string
    field :status, Ecto.Enum, values: @statuses, default: :open
    field :resolved_at, :utc_datetime_usec
    field :resolution_note, :string

    belongs_to :reporter, Foglet.Accounts.User
    belongs_to :resolved_by, Foglet.Accounts.User

    timestamps()
  end

  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(report, attrs) do
    report
    |> cast(attrs, [:target_kind, :target_id, :reason, :notes])
    |> update_change(:reason, &String.trim/1)
    |> normalize_optional_text(:notes)
    |> validate_required([:target_kind, :target_id, :reason, :reporter_id])
    |> validate_length(:reason, min: 1)
    |> foreign_key_constraint(:reporter_id)
    |> foreign_key_constraint(:resolved_by_id)
  end

  @spec resolution_changeset(t(), map(), :resolved | :dismissed, Ecto.UUID.t()) ::
          Ecto.Changeset.t()
  def resolution_changeset(report, attrs, status, resolver_id)
      when status in [:resolved, :dismissed] do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    report
    |> cast(attrs, [:resolution_note])
    |> update_change(:resolution_note, &String.trim/1)
    |> change(status: status, resolved_by_id: resolver_id, resolved_at: now)
    |> validate_required([:status, :resolved_by_id, :resolved_at, :resolution_note])
    |> validate_length(:resolution_note, min: 1)
    |> foreign_key_constraint(:reporter_id)
    |> foreign_key_constraint(:resolved_by_id)
  end

  defp normalize_optional_text(changeset, field) do
    update_change(changeset, field, fn
      value when is_binary(value) ->
        value
        |> String.trim()
        |> case do
          "" -> nil
          trimmed -> trimmed
        end

      value ->
        value
    end)
  end
end
