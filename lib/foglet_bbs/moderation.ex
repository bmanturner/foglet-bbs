defmodule Foglet.Moderation do
  @moduledoc """
  Narrow moderation audit context.

  Phase 08 only persists hide-oneliner audit records. Reports, sanctions, user
  mutations, and broader moderation workflows remain outside this context.
  """

  import Ecto.Query, warn: false

  alias Foglet.QueryHelpers

  alias Foglet.Accounts.User
  alias Foglet.Authorization
  alias Foglet.Boards
  alias Foglet.Boards.Board
  alias Foglet.Moderation.Action
  alias Foglet.Oneliners.Entry
  alias FogletBbs.Repo

  @default_limit 50
  @workspace_limit 20
  @max_limit 100

  @type scope :: :site | {:board, Ecto.UUID.t()}

  @doc """
  Returns the read-only moderation workspace snapshot visible to an actor.

  The scope list is the trust boundary: actors with no `:hide_oneliner` scope
  receive no populated workspace data.
  """
  @spec workspace_snapshot(User.t() | nil) ::
          {:ok,
           %{
             scopes: [scope(), ...],
             queue: [],
             log: [Action.t()],
             users: [map()],
             boards: [map()],
             sanctions_available?: false
           }}
          | {:error, :forbidden}
  def workspace_snapshot(actor) do
    case Authorization.scopes_for(actor, :hide_oneliner) do
      [] ->
        {:error, :forbidden}

      scopes ->
        {:ok,
         %{
           scopes: scopes,
           queue: [],
           log: list_actions_for_scopes(scopes, limit: @workspace_limit),
           users: active_user_rows(limit: @workspace_limit),
           boards: board_scope_rows(scopes, limit: @workspace_limit),
           sanctions_available?: false
         }}
    end
  end

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

  @doc """
  Returns read-only board rows visible for the provided moderation scopes.

  Board-scope tuples are accepted even though v1.1 currently grants site scopes
  to moderators and sysops.
  """
  @spec board_scope_rows([scope()], keyword()) :: [map()]
  def board_scope_rows(scopes, opts \\ [])

  def board_scope_rows([], _opts), do: []

  def board_scope_rows(scopes, opts) when is_list(scopes) do
    limit = bounded_limit(Keyword.get(opts, :limit, @workspace_limit))

    scope_query =
      if :site in scopes do
        dynamic([b: b], true)
      else
        board_ids =
          scopes
          |> Enum.flat_map(fn
            {:board, board_id} -> [board_id]
            _scope -> []
          end)

        dynamic([b: b], b.id in ^board_ids)
      end

    from(b in Board, as: :b)
    |> join(:inner, [b: b], c in assoc(b, :category), as: :c)
    |> where(^scope_query)
    |> order_by([b: b, c: c], asc: c.display_order, asc: b.display_order)
    |> limit(^limit)
    |> preload([b: b, c: c], category: c)
    |> QueryHelpers.active_boards()
    |> Repo.all()
    |> Enum.map(&board_row/1)
  end

  defp active_user_rows(opts) do
    limit = bounded_limit(Keyword.get(opts, :limit, @workspace_limit))

    from(user in User,
      where: user.status == :active,
      order_by: [asc: user.handle],
      limit: ^limit,
      select: %{
        id: user.id,
        handle: user.handle,
        role: user.role,
        status: user.status,
        inserted_at: user.inserted_at,
        last_seen_at: user.last_seen_at
      }
    )
    |> QueryHelpers.not_deleted()
    |> Repo.all()
  end

  defp board_row(%Board{} = board) do
    %{
      id: board.id,
      slug: board.slug,
      name: board.name,
      description: board.description,
      category_name: board.category.name,
      scope: Boards.scope_for(board)
    }
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
