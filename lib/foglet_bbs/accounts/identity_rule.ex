defmodule Foglet.Accounts.IdentityRule do
  @moduledoc "Operator-managed registration/account identity access-policy rule."
  use Foglet.Schema

  @kinds [:reserved_handle, :banned_handle, :banned_email, :banned_email_domain]

  schema "identity_policy_rules" do
    field :kind, Ecto.Enum, values: @kinds
    field :value, :string
    field :normalized_value, :string
    field :enabled, :boolean, default: true
    field :reason, :string
    field :comment, :string

    belongs_to :created_by, Foglet.Accounts.User
    belongs_to :updated_by, Foglet.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  def kinds, do: @kinds

  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [:kind, :value, :enabled, :reason, :comment, :created_by_id, :updated_by_id])
    |> validate_required([:kind, :value, :reason])
    |> validate_length(:reason, max: 160)
    |> validate_length(:comment, max: 1_000)
    |> normalize_value()
    |> unique_constraint([:kind, :normalized_value])
  end

  def enabled_changeset(rule, enabled, actor_id \\ nil) do
    rule
    |> change(%{enabled: enabled, updated_by_id: actor_id})
  end

  def normalize(:reserved_handle, value), do: normalize_handle(value)
  def normalize(:banned_handle, value), do: normalize_handle(value)
  def normalize(:banned_email, value), do: normalize_email(value)
  def normalize(:banned_email_domain, value), do: normalize_domain(value)
  def normalize("reserved_handle", value), do: normalize(:reserved_handle, value)
  def normalize("banned_handle", value), do: normalize(:banned_handle, value)
  def normalize("banned_email", value), do: normalize(:banned_email, value)
  def normalize("banned_email_domain", value), do: normalize(:banned_email_domain, value)
  def normalize(_, _), do: {:error, :invalid_kind}

  defp normalize_value(changeset) do
    kind = get_field(changeset, :kind)
    value = get_field(changeset, :value)

    case normalize(kind, value) do
      {:ok, normalized} ->
        changeset
        |> update_change(:value, &String.trim(to_string(&1)))
        |> put_change(:normalized_value, normalized)

      {:error, message} when is_binary(message) ->
        add_error(changeset, :value, message)

      {:error, _} ->
        add_error(changeset, :value, "is invalid")
    end
  end

  defp normalize_handle(value) when is_binary(value) do
    trimmed = String.trim(value)

    if Regex.match?(Foglet.Accounts.User.handle_format(), trimmed) do
      {:ok, String.downcase(trimmed)}
    else
      {:error, "must be a valid handle"}
    end
  end

  defp normalize_handle(_), do: {:error, "must be a valid handle"}

  defp normalize_email(value) when is_binary(value) do
    trimmed = String.trim(value)

    if Regex.match?(~r/^[^@\s]+@[^@\s]+\.[^@\s]+$/, trimmed) do
      [local, domain] = String.split(trimmed, "@", parts: 2)
      {:ok, String.downcase(local) <> "@" <> String.downcase(domain)}
    else
      {:error, "must be a valid email address"}
    end
  end

  defp normalize_email(_), do: {:error, "must be a valid email address"}

  defp normalize_domain(value) when is_binary(value) do
    domain = value |> String.trim() |> String.trim_leading("@") |> String.downcase()

    if Regex.match?(~r/^(?!-)[a-z0-9-]+(?<!-)(\.(?!-)[a-z0-9-]+(?<!-))+$/, domain) do
      {:ok, domain}
    else
      {:error, "must be a valid email domain"}
    end
  end

  defp normalize_domain(_), do: {:error, "must be a valid email domain"}
end
