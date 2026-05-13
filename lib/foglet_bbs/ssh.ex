defmodule Foglet.SSH do
  @moduledoc "Domain boundary for SSH access rules and connection audit/caller history."
  import Ecto.Query

  alias Foglet.Accounts.User
  alias Foglet.Authorization
  alias Foglet.SSH.{AccessRule, LastCaller}
  alias FogletBbs.Repo

  @default_raw_ip_retention_days 90

  def default_raw_ip_retention_days, do: @default_raw_ip_retention_days

  def list_access_rules do
    Repo.all(from r in AccessRule, order_by: [desc: r.inserted_at])
  end

  def list_access_rules(actor) do
    with :ok <- permit_access_rule_management(actor) do
      {:ok, list_access_rules()}
    end
  end

  def create_access_rule(attrs, actor \\ nil)

  def create_access_rule(%User{} = actor, attrs) when is_map(attrs) do
    with :ok <- permit_access_rule_management(actor) do
      create_access_rule(attrs, actor)
    end
  end

  def create_access_rule(attrs, actor) when is_map(attrs) do
    %AccessRule{}
    |> AccessRule.changeset(attrs)
    |> AccessRule.put_created_by(actor)
    |> Repo.insert()
  end

  def remove_access_rule(id), do: AccessRule |> Repo.get(id) |> delete_found()

  def remove_access_rule(actor, id) do
    with :ok <- permit_access_rule_management(actor) do
      remove_access_rule(id)
    end
  end

  def enable_access_rule(id), do: set_access_rule_enabled(id, true)

  def enable_access_rule(actor, id) do
    with :ok <- permit_access_rule_management(actor) do
      enable_access_rule(id)
    end
  end

  def disable_access_rule(id), do: set_access_rule_enabled(id, false)

  def disable_access_rule(actor, id) do
    with :ok <- permit_access_rule_management(actor) do
      disable_access_rule(id)
    end
  end

  def evaluate_access(ip, opts \\ []) do
    rules =
      Repo.all(from r in AccessRule, where: r.enabled == true, order_by: [asc: r.inserted_at])

    deny = Enum.find(rules, &(&1.mode == :deny and AccessRule.matches?(&1, ip)))
    allow = Enum.find(rules, &(&1.mode == :allow and AccessRule.matches?(&1, ip)))

    cond do
      deny -> {:deny, %{reason: deny.reason, rule: deny}}
      allow -> {:allow, %{reason: allow.reason, rule: allow}}
      Keyword.get(opts, :allowlist_enabled?, false) -> {:deny, %{reason: "not_allowlisted"}}
      true -> {:allow, %{reason: "default_allow"}}
    end
  end

  def record_last_caller(attrs) do
    {user, attrs} = Map.pop(attrs, :user)
    attrs = normalize_last_caller_attrs(attrs)

    %LastCaller{}
    |> LastCaller.changeset(attrs)
    |> LastCaller.put_user(user)
    |> Repo.insert()
  end

  def list_public_last_callers(limit \\ 10) do
    Repo.all(
      from c in LastCaller,
        where: c.public_visible == true and c.outcome == :accepted,
        order_by: [desc: c.occurred_at],
        limit: ^limit,
        preload: [:user]
    )
  end

  def redact_last_caller_raw_ips_older_than(days \\ @default_raw_ip_retention_days) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days, :day) |> DateTime.truncate(:microsecond)

    Repo.update_all(
      from(c in LastCaller, where: c.occurred_at < ^cutoff and not is_nil(c.peer_ip)),
      set: [peer_ip: nil, peer_port: nil, public_visible: false]
    )
  end

  def detach_last_callers_for_user(%{id: user_id}) do
    Repo.update_all(from(c in LastCaller, where: c.user_id == ^user_id),
      set: [user_id: nil, public_visible: false]
    )
  end

  defp set_access_rule_enabled(id, enabled) do
    case Repo.get(AccessRule, id) do
      nil -> {:error, :not_found}
      rule -> rule |> Ecto.Changeset.change(enabled: enabled) |> Repo.update()
    end
  end

  defp permit_access_rule_management(actor) do
    Bodyguard.permit(Authorization, :manage_ssh_access_rules, actor, :site)
  end

  defp delete_found(nil), do: {:error, :not_found}
  defp delete_found(rule), do: Repo.delete(rule)

  defp normalize_last_caller_attrs(attrs) do
    attrs
    |> Map.put_new(:occurred_at, DateTime.utc_now() |> DateTime.truncate(:microsecond))
    |> Map.put_new(:metadata, %{})
    |> normalize_peer_ip()
  end

  defp normalize_peer_ip(%{peer_ip: peer_ip} = attrs) when is_tuple(peer_ip),
    do: %{attrs | peer_ip: AccessRule.ip_to_string(peer_ip)}

  defp normalize_peer_ip(attrs), do: attrs
end
