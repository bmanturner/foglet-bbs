defmodule Foglet.Oneliners do
  @moduledoc """
  Domain context for persisted oneliners.

  The context owns actor assignment, validation, and bounded recent-visible
  queries for the main-menu social strip.
  """

  import Ecto.Query, warn: false

  alias Foglet.Accounts.User
  alias Foglet.Authorization
  alias Foglet.Moderation
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

  @doc """
  Hides a visible oneliner after actor authorization and reason validation.

  Oneliners are site-scoped in v1.1. The actor must have a permitted `:site`
  scope for `:hide_oneliner`; board-only scopes intentionally do not authorize
  this mutation.
  """
  @spec hide_entry(User.t() | nil, Entry.t() | Ecto.UUID.t(), String.t()) ::
          {:ok, Entry.t()}
          | {:error, :already_hidden | :forbidden | :not_found | Ecto.Changeset.t()}
  def hide_entry(actor, entry_or_id, reason) do
    with {:ok, entry} <- fetch_entry(entry_or_id),
         :ok <- ensure_visible(entry),
         :ok <- authorize_hide(actor),
         {:ok, changeset} <- hide_changeset(entry, actor, reason) do
      Repo.transact(fn ->
        with {:ok, hidden_entry} <- Repo.update(changeset) do
          hidden_entry = Repo.preload(hidden_entry, :user)

          _action =
            Moderation.record_hide_oneliner!(
              actor,
              hidden_entry,
              hidden_entry.hidden_reason,
              oneliner_metadata(hidden_entry)
            )

          {:ok, hidden_entry}
        end
      end)
    end
  end

  defp ensure_not_latest_visible_user(repo, %User{} = user) do
    latest =
      repo.one(
        from e in Entry,
          where: not e.hidden,
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

  defp fetch_entry(%Entry{} = entry), do: {:ok, Repo.preload(entry, :user)}

  defp fetch_entry(entry_id) when is_binary(entry_id) do
    case Repo.get(Entry, entry_id) do
      nil -> {:error, :not_found}
      entry -> {:ok, Repo.preload(entry, :user)}
    end
  end

  defp fetch_entry(_entry_or_id), do: {:error, :not_found}

  defp ensure_visible(%Entry{hidden: false}), do: :ok
  defp ensure_visible(%Entry{hidden: true}), do: {:error, :already_hidden}

  defp authorize_hide(%User{} = actor) do
    actor
    |> Authorization.scopes_for(:hide_oneliner)
    |> Enum.filter(&(&1 == :site))
    |> Enum.find(fn scope ->
      Bodyguard.permit(Foglet.Authorization, :hide_oneliner, actor, scope) == :ok
    end)
    |> case do
      nil -> {:error, :forbidden}
      _scope -> :ok
    end
  end

  defp authorize_hide(_actor), do: {:error, :forbidden}

  defp hide_changeset(%Entry{} = entry, %User{} = actor, reason) do
    hidden_by_id = actor.id
    changeset = Entry.hide_changeset(entry, to_string(reason), hidden_by_id)

    if changeset.valid? do
      {:ok, changeset}
    else
      {:error, changeset}
    end
  end

  defp oneliner_metadata(%Entry{} = entry) do
    %{
      "body" => entry.body,
      "author_handle" => entry.user.handle
    }
  end
end
