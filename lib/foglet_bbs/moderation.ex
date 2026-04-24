defmodule Foglet.Moderation do
  @moduledoc """
  Narrow moderation audit context.

  Phase 08 only persists hide-oneliner audit records. Reports, sanctions, user
  mutations, and broader moderation workflows remain outside this context.
  """

  import Ecto.Query, warn: false

  alias Foglet.Accounts.User
  alias Foglet.Moderation.Action
  alias Foglet.Oneliners.Entry
  alias FogletBbs.Repo

  @default_limit 50
  @max_limit 100

  @type scope :: :site | {:board, Ecto.UUID.t()}

  @doc """
  Records a successful oneliner hide audit row.
  """
  @spec record_hide_oneliner!(User.t(), Entry.t(), String.t(), map()) :: Action.t()
  def record_hide_oneliner!(%User{} = moderator, %Entry{} = entry, reason, metadata \\ %{}) do
    %Action{mod_id: moderator.id}
    |> Action.changeset(%{
      kind: :hide_oneliner,
      target_kind: :oneliner,
      target_id: entry.id,
      reason: reason,
      metadata: normalize_metadata(metadata)
    })
    |> Repo.insert!()
  end

  @doc """
  Lists moderation audit actions visible to the provided authorization scopes.

  Oneliners are site-scoped in v1.1. Board-scope tuples are accepted to preserve
  the future scope contract, but they do not see site-scoped oneliner actions.
  """
  @spec list_actions_for_scopes([scope()], keyword()) :: [Action.t()]
  def list_actions_for_scopes(scopes, opts \\ [])

  def list_actions_for_scopes([], _opts), do: []

  def list_actions_for_scopes(scopes, opts) when is_list(scopes) do
    if :site in scopes do
      limit = bounded_limit(Keyword.get(opts, :limit, @default_limit))

      Repo.all(
        from action in Action,
          where: action.kind == :hide_oneliner and action.target_kind == :oneliner,
          order_by: [desc: action.inserted_at],
          limit: ^limit,
          preload: [:mod]
      )
    else
      []
    end
  end

  defp normalize_metadata(metadata) when is_map(metadata) do
    Map.new(metadata, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_metadata(_metadata), do: %{}

  defp bounded_limit(limit) when is_integer(limit) do
    limit
    |> max(0)
    |> min(@max_limit)
  end

  defp bounded_limit(_limit), do: @default_limit
end
