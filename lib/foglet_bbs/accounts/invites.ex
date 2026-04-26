defmodule Foglet.Accounts.Invites do
  @moduledoc """
  Invite management functions for `Foglet.Accounts`.
  """

  import Ecto.Query, warn: false

  alias Foglet.Accounts.{Invite, User}
  alias FogletBbs.Repo

  @type invite_status :: %{
          code: String.t(),
          issuer_id: Ecto.UUID.t(),
          inserted_at: DateTime.t(),
          consumed_at: DateTime.t() | nil,
          consumed_by_user_id: Ecto.UUID.t() | nil,
          revoked_at: DateTime.t() | nil,
          status: :available | :consumed | :revoked
        }

  @spec create_invite(User.t()) ::
          {:ok, Invite.t()} | {:error, :forbidden | :limit_reached | Ecto.Changeset.t()}
  def create_invite(%User{} = actor) do
    with :ok <- Bodyguard.permit(Foglet.Authorization, :generate_invite, actor, :site),
         :ok <- ensure_invite_generation_policy(actor),
         :ok <- ensure_invite_generation_limit(actor) do
      insert_invite(actor, 5)
    else
      {:error, :forbidden} -> {:error, :forbidden}
      {:error, :limit_reached} -> {:error, :limit_reached}
    end
  end

  @spec list_invites(User.t()) :: {:ok, [invite_status()]} | {:error, :forbidden}
  def list_invites(%User{} = actor) do
    with :ok <- Bodyguard.permit(Foglet.Authorization, :generate_invite, actor, :site) do
      invites =
        Repo.all(from(i in Invite, order_by: [desc: i.inserted_at]))
        |> Enum.map(&invite_status_map/1)

      {:ok, invites}
    end
  end

  @spec get_invite_status(String.t()) :: {:ok, invite_status()} | {:error, :not_found}
  def get_invite_status(code) when is_binary(code) do
    case Repo.get_by(Invite, code: code) do
      %Invite{} = invite -> {:ok, invite_status_map(invite)}
      nil -> {:error, :not_found}
    end
  end

  @spec revoke_invite(User.t(), String.t()) ::
          {:ok, Invite.t()} | {:error, :forbidden | :not_found | :unavailable}
  def revoke_invite(%User{} = actor, code) when is_binary(code) do
    with :ok <- Bodyguard.permit(Foglet.Authorization, :revoke_invite, actor, :site) do
      case Repo.get_by(Invite, code: code) do
        nil ->
          {:error, :not_found}

        %Invite{} = invite ->
          revoke_available_invite(invite, code)
      end
    end
  end

  defp ensure_invite_generation_policy(%User{role: :sysop}), do: :ok

  defp ensure_invite_generation_policy(%User{role: :mod}) do
    case Foglet.Config.invite_code_generators() do
      policy when policy in ["mods", "any_user"] -> :ok
      _policy -> {:error, :forbidden}
    end
  end

  defp ensure_invite_generation_policy(%User{role: :user}) do
    case Foglet.Config.invite_code_generators() do
      "any_user" -> :ok
      _policy -> {:error, :forbidden}
    end
  end

  defp ensure_invite_generation_policy(%User{}), do: {:error, :forbidden}

  defp ensure_invite_generation_limit(%User{role: :user, id: user_id}) do
    if Foglet.Config.invite_code_generators() == "any_user" do
      case Foglet.Config.invite_generation_per_user_limit() do
        0 ->
          :ok

        limit when is_integer(limit) and limit > 0 ->
          count = Repo.aggregate(from(i in Invite, where: i.issuer_id == ^user_id), :count)

          if count >= limit do
            {:error, :limit_reached}
          else
            :ok
          end
      end
    else
      :ok
    end
  end

  defp ensure_invite_generation_limit(%User{}), do: :ok

  defp insert_invite(%User{} = actor, attempts_remaining) do
    %Invite{issuer_id: actor.id}
    |> Invite.changeset(%{code: generate_invite_code()})
    |> Repo.insert()
    |> case do
      {:ok, invite} ->
        {:ok, invite}

      {:error, changeset} = error ->
        if invite_code_collision?(changeset) and attempts_remaining > 1 do
          insert_invite(actor, attempts_remaining - 1)
        else
          error
        end
    end
  end

  defp invite_code_collision?(%Ecto.Changeset{errors: errors}) do
    Keyword.has_key?(errors, :code)
  end

  defp generate_invite_code do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.encode32(case: :upper, padding: false)
    |> String.replace(~r/[^A-Z0-9]/, "")
  end

  defp invite_status_map(%Invite{} = invite) do
    %{
      code: invite.code,
      issuer_id: invite.issuer_id,
      inserted_at: invite.inserted_at,
      consumed_at: invite.consumed_at,
      consumed_by_user_id: invite.consumed_by_user_id,
      revoked_at: invite.revoked_at,
      status: Invite.status(invite)
    }
  end

  defp revoke_available_invite(%Invite{} = invite, code) do
    if Invite.status(invite) == :available do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      query =
        from i in Invite,
          where: i.code == ^code and is_nil(i.consumed_at) and is_nil(i.revoked_at)

      case Repo.update_all(query, set: [revoked_at: now, updated_at: now]) do
        {1, _rows} -> {:ok, Repo.get!(Invite, invite.id)}
        {0, _rows} -> {:error, :unavailable}
      end
    else
      {:error, :unavailable}
    end
  end
end
