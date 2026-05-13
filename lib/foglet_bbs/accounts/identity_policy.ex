defmodule Foglet.Accounts.IdentityPolicy do
  @moduledoc "Context for operator-managed handle/email identity policy rules."
  import Ecto.Query

  alias Ecto.Changeset
  alias Foglet.Accounts.{IdentityRule, User}
  alias FogletBbs.Repo

  @anonymous_error "is unavailable"

  def list_rules do
    Repo.all(from r in IdentityRule, order_by: [asc: r.kind, asc: r.normalized_value])
  end

  def get_rule!(id), do: Repo.get!(IdentityRule, id)

  def create_rule(attrs, actor \\ nil) do
    attrs = maybe_put_actor(attrs, :created_by_id, actor)

    %IdentityRule{}
    |> IdentityRule.changeset(attrs)
    |> Repo.insert()
  end

  def enable_rule(id, actor \\ nil), do: set_enabled(id, true, actor)
  def disable_rule(id, actor \\ nil), do: set_enabled(id, false, actor)
  def remove_rule(id), do: id |> get_rule!() |> Repo.delete()

  def validate_registration_changeset(%Changeset{} = changeset) do
    changeset
    |> validate_handle_policy()
    |> validate_email_policy()
  end

  def handle_allowed?(handle), do: match?(:ok, check_handle(handle))
  def email_allowed?(email), do: match?(:ok, check_email(email))

  def check_handle(handle) do
    with {:ok, normalized} <- IdentityRule.normalize(:banned_handle, handle) do
      case enabled_rule([:reserved_handle, :banned_handle], normalized) do
        nil -> :ok
        rule -> {:blocked, %{kind: rule.kind, rule: rule}}
      end
    end
  end

  def check_email(email) do
    with {:ok, normalized_email} <- IdentityRule.normalize(:banned_email, email),
         {:ok, domain} <- email_domain(normalized_email) do
      cond do
        rule = enabled_rule([:banned_email], normalized_email) ->
          {:blocked, %{kind: rule.kind, rule: rule}}

        rule = domain_rule(domain) ->
          {:blocked, %{kind: rule.kind, rule: rule}}

        true ->
          :ok
      end
    end
  end

  def conflicts_for_rule(%IdentityRule{kind: kind, normalized_value: value})
      when kind in [:reserved_handle, :banned_handle] do
    Repo.all(
      from u in User,
        where: fragment("lower(?)", u.handle) == ^value and is_nil(u.deleted_at),
        select: %{id: u.id, handle: u.handle, email: u.email}
    )
  end

  def conflicts_for_rule(%IdentityRule{kind: :banned_email, normalized_value: value}) do
    Repo.all(
      from u in User,
        where: fragment("lower(?)", u.email) == ^value and is_nil(u.deleted_at),
        select: %{id: u.id, handle: u.handle, email: u.email}
    )
  end

  def conflicts_for_rule(%IdentityRule{kind: :banned_email_domain, normalized_value: value}) do
    Repo.all(
      from u in User,
        where: is_nil(u.deleted_at),
        select: %{id: u.id, handle: u.handle, email: u.email}
    )
    |> Enum.filter(fn %{email: email} ->
      with {:ok, normalized} <- IdentityRule.normalize(:banned_email, email),
           {:ok, domain} <- email_domain(normalized) do
        domain == value or String.ends_with?(domain, "." <> value)
      else
        _ -> false
      end
    end)
  end

  defp set_enabled(id, enabled, actor) do
    id
    |> get_rule!()
    |> IdentityRule.enabled_changeset(enabled, actor_id(actor))
    |> Repo.update()
  end

  defp maybe_put_actor(attrs, field, actor) do
    case actor_id(actor) do
      nil -> attrs
      id -> Map.put(attrs, field, id)
    end
  end

  defp actor_id(%User{id: id}), do: id
  defp actor_id(id) when is_binary(id), do: id
  defp actor_id(_), do: nil

  defp validate_handle_policy(changeset) do
    case Changeset.get_field(changeset, :handle) do
      nil ->
        changeset

      handle ->
        case check_handle(handle) do
          {:blocked, _} -> Changeset.add_error(changeset, :handle, @anonymous_error)
          _ -> changeset
        end
    end
  end

  defp validate_email_policy(changeset) do
    case Changeset.get_field(changeset, :email) do
      nil ->
        changeset

      email ->
        case check_email(email) do
          {:blocked, _} -> Changeset.add_error(changeset, :email, @anonymous_error)
          _ -> changeset
        end
    end
  end

  defp enabled_rule(kinds, normalized_value) do
    Repo.one(
      from r in IdentityRule,
        where: r.enabled and r.kind in ^kinds and r.normalized_value == ^normalized_value,
        order_by: [asc: r.inserted_at],
        limit: 1
    )
  end

  defp domain_rule(domain) do
    Repo.all(
      from r in IdentityRule,
        where: r.enabled and r.kind == :banned_email_domain,
        order_by: [asc: r.inserted_at]
    )
    |> Enum.find(fn rule ->
      domain == rule.normalized_value or String.ends_with?(domain, "." <> rule.normalized_value)
    end)
  end

  defp email_domain(normalized_email) do
    case String.split(normalized_email, "@", parts: 2) do
      [_local, domain] -> {:ok, domain}
      _ -> {:error, :invalid_email}
    end
  end
end
