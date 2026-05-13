defmodule Foglet.Notifications do
  @moduledoc """
  Durable notification context.

  Owns trusted inserts, recipient-scoped inbox queries, read-state mutations,
  idempotent dedupe handling, and user-scoped PubSub refresh signals for active
  TUI sessions.
  """

  import Ecto.Query, warn: false

  alias Foglet.Accounts.User
  alias Foglet.Notifications.Notification
  alias FogletBbs.Repo

  @recent_default_limit 50
  @recent_max_limit 100

  @type user_ref :: User.t() | Ecto.UUID.t()

  @spec create_notification(map()) :: {:ok, Notification.t()} | {:error, Ecto.Changeset.t()}
  def create_notification(attrs) when is_map(attrs) do
    user_id = attrs[:user_id] || attrs["user_id"]
    actor_id = attrs[:actor_id] || attrs["actor_id"]
    dedupe_key = attrs[:dedupe_key] || attrs["dedupe_key"]

    %Notification{user_id: user_id, actor_id: actor_id}
    |> Notification.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, notification} ->
        notification = Repo.preload(notification, :actor)
        _ = broadcast_ignore(notification.user_id, {:notifications, :created, notification})
        {:ok, notification}

      {:error, changeset} ->
        maybe_return_existing_notification(user_id, dedupe_key, changeset)
    end
  end

  @spec list_recent(user_ref(), integer()) :: [Notification.t()]
  def list_recent(user, limit \\ @recent_default_limit) do
    user_id = user_id!(user)
    bounded = limit |> normalize_limit()

    Notification
    |> where([notification], notification.user_id == ^user_id)
    |> order_by([notification], desc: notification.inserted_at, desc: notification.id)
    |> limit(^bounded)
    |> Repo.all()
    |> Repo.preload(:actor)
  end

  @spec unread_count(user_ref()) :: non_neg_integer()
  def unread_count(user) do
    user_id = user_id!(user)

    Repo.aggregate(
      from(notification in Notification,
        where: notification.user_id == ^user_id and is_nil(notification.read_at)
      ),
      :count
    )
  end

  @spec mark_read(user_ref(), Ecto.UUID.t()) :: {:ok, Notification.t()} | {:error, :not_found}
  def mark_read(user, notification_id) when is_binary(notification_id) do
    user_id = user_id!(user)
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    {count, _} =
      Repo.update_all(
        from(notification in Notification,
          where:
            notification.user_id == ^user_id and notification.id == ^notification_id and
              is_nil(notification.read_at)
        ),
        set: [read_at: now]
      )

    case Repo.get_by(Notification, id: notification_id, user_id: user_id) do
      nil ->
        {:error, :not_found}

      notification ->
        notification = Repo.preload(notification, :actor)

        _ = broadcast_read_if_updated(count, user_id, notification_id)

        {:ok, notification}
    end
  end

  @spec mark_all_read(user_ref()) :: {:ok, non_neg_integer()}
  def mark_all_read(user) do
    user_id = user_id!(user)
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    {count, _} =
      Repo.update_all(
        from(notification in Notification,
          where: notification.user_id == ^user_id and is_nil(notification.read_at)
        ),
        set: [read_at: now]
      )

    _ = broadcast_all_read_if_needed(count, user_id)

    {:ok, count}
  end

  @doc """
  Deletes read notifications older than `retention_days`.

  The retention boundary is based on `read_at`: notifications read strictly
  before `now - retention_days` are deleted. Unread notifications are never
  deleted by this cleanup path, even if their `inserted_at` is old.
  """
  @spec cleanup_read_notifications(pos_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, :invalid_retention_days}
  def cleanup_read_notifications(retention_days, opts \\ [])

  def cleanup_read_notifications(retention_days, opts)
      when is_integer(retention_days) and retention_days > 0 do
    now = Keyword.get_lazy(opts, :now, fn -> DateTime.utc_now() end)
    cutoff = DateTime.add(now, -retention_days * 86_400, :second)

    {count, _} =
      Repo.delete_all(
        from(notification in Notification,
          where: not is_nil(notification.read_at) and notification.read_at < ^cutoff
        )
      )

    {:ok, count}
  end

  def cleanup_read_notifications(_retention_days, _opts), do: {:error, :invalid_retention_days}

  defp maybe_return_existing_notification(user_id, dedupe_key, changeset)
       when is_binary(user_id) and is_binary(dedupe_key) do
    case Repo.get_by(Notification, user_id: user_id, dedupe_key: String.trim(dedupe_key)) do
      %Notification{} = notification -> {:ok, Repo.preload(notification, :actor)}
      nil -> {:error, changeset}
    end
  end

  defp maybe_return_existing_notification(_user_id, _dedupe_key, changeset),
    do: {:error, changeset}

  defp user_id!(%User{id: user_id}), do: user_id
  defp user_id!(user_id) when is_binary(user_id), do: user_id

  defp normalize_limit(limit) when is_integer(limit) and limit > 0,
    do: min(limit, @recent_max_limit)

  defp normalize_limit(_limit), do: @recent_default_limit

  defp broadcast_read_if_updated(1, user_id, notification_id) do
    broadcast_ignore(
      user_id,
      {:notifications, :read, %{notification_id: notification_id, user_id: user_id}}
    )
  end

  defp broadcast_read_if_updated(_count, _user_id, _notification_id), do: :ok

  defp broadcast_all_read_if_needed(count, user_id) when count > 0 do
    broadcast_ignore(user_id, {:notifications, :all_read, %{user_id: user_id, count: count}})
  end

  defp broadcast_all_read_if_needed(_count, _user_id), do: :ok

  defp broadcast_ignore(user_id, message) do
    case broadcast(user_id, message) do
      :ok -> :ok
      {:error, _reason} -> :ok
    end
  end

  defp broadcast(user_id, message) do
    with :ok <-
           Phoenix.PubSub.broadcast(
             FogletBbs.PubSub,
             Foglet.PubSub.notifications_topic(user_id),
             message
           ) do
      Phoenix.PubSub.broadcast(FogletBbs.PubSub, Foglet.PubSub.user_topic(user_id), message)
    end
  end
end
