defmodule Foglet.Oneliners do
  @moduledoc """
  Domain context for persisted oneliners.

  The context owns actor assignment, validation, and bounded recent-visible
  queries for the main-menu social strip.
  """

  import Ecto.Query, warn: false

  alias Foglet.Accounts.User
  alias Foglet.Oneliners.Entry
  alias FogletBbs.Repo

  @entry_limit_default 5
  @entry_limit_max 20

  @doc """
  Creates a visible oneliner for the authenticated user.

  Caller-provided ownership or moderation attributes are ignored. A user cannot
  create two latest-visible entries in a row.
  """
  @spec create_entry(User.t(), map()) ::
          {:ok, Entry.t()} | {:error, Ecto.Changeset.t()} | {:error, :same_user_latest_visible}
  def create_entry(%User{} = user, attrs) do
    Repo.transact(fn repo ->
      case ensure_not_latest_visible_user(repo, user) do
        :ok ->
          %Entry{user_id: user.id}
          |> Entry.create_changeset(attrs)
          |> repo.insert()

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  @doc """
  Lists recent visible oneliners newest first.

  The requested limit is clamped to `0..20`, and user records are preloaded for
  handle rendering in the TUI.
  """
  @spec list_recent_visible(integer()) :: [Entry.t()]
  def list_recent_visible(limit \\ @entry_limit_default) do
    bounded_limit = bounded_limit(limit)

    Repo.all(
      from e in Entry,
        where: e.hidden == false,
        order_by: [desc: e.inserted_at],
        limit: ^bounded_limit,
        preload: [:user]
    )
  end

  defp ensure_not_latest_visible_user(repo, %User{} = user) do
    latest =
      repo.one(
        from e in Entry,
          where: e.hidden == false,
          order_by: [desc: e.inserted_at],
          limit: 1
      )

    case latest do
      %Entry{user_id: user_id} when user_id == user.id -> {:error, :same_user_latest_visible}
      _latest -> :ok
    end
  end

  defp bounded_limit(limit) when is_integer(limit) do
    limit
    |> max(0)
    |> min(@entry_limit_max)
  end

  defp bounded_limit(_limit), do: @entry_limit_default
end
