defmodule Foglet.Authorization do
  @moduledoc """
  Actor-aware, scope-aware authorization policy for operator actions.

  Implements `Bodyguard.Policy`. Callers MUST use `Bodyguard.permit/4` or
  `Bodyguard.permit?/4` — never the `authorize/3` callback directly.

  The domain context function is the real trust boundary (D-17).
  The TUI may call `Bodyguard.permit?/4` for advisory rendering only (D-18).

  Public API:
    * `Bodyguard.permit(Foglet.Authorization, action, actor, scope)` — every guarded
      domain function before side effects
    * `Bodyguard.permit?(Foglet.Authorization, action, actor, scope)` — TUI advisory
      rendering (grey-out, hide)
    * `Foglet.Authorization.scopes_for/2` — data-visibility scope list, consumed by Phase 8

  See .planning/phases/01-authorization-and-scope-backbone/01-CONTEXT.md for decisions.
  """

  @behaviour Bodyguard.Policy

  require Logger

  alias Foglet.Accounts.User

  @valid_actions [
    :lock_thread,
    :unlock_thread,
    :sticky_thread,
    :unsticky_thread,
    :move_thread,
    :delete_thread,
    :delete_post,
    :edit_post_as_mod,
    :hide_oneliner,
    :create_report,
    :list_reports,
    :resolve_report,
    :dismiss_report,
    :create_board,
    :update_board,
    :archive_board,
    :create_category,
    :update_category,
    :archive_category,
    :manage_board_feeds,
    :edit_config,
    :manage_user_status,
    :manage_ssh_access_rules,
    :manage_identity_rules,
    :generate_invite,
    :revoke_invite,
    :send_test_email
  ]

  @mod_site_actions [
    :lock_thread,
    :unlock_thread,
    :sticky_thread,
    :unsticky_thread,
    :move_thread,
    :delete_thread,
    :delete_post,
    :edit_post_as_mod,
    :hide_oneliner,
    :list_reports,
    :resolve_report,
    :dismiss_report,
    :generate_invite,
    :revoke_invite
  ]

  @mod_board_actions [
    :lock_thread,
    :unlock_thread,
    :sticky_thread,
    :unsticky_thread,
    :move_thread,
    :delete_thread,
    :delete_post,
    :edit_post_as_mod,
    :hide_oneliner,
    :manage_board_feeds
  ]

  @type actor :: User.t() | nil
  @type action :: atom()
  @type scope :: :site | {:board, Ecto.UUID.t()}

  @impl Bodyguard.Policy
  @spec authorize(action(), actor(), scope()) :: :ok | {:error, :forbidden}
  def authorize(_action, nil, _scope), do: {:error, :forbidden}

  def authorize(_action, %User{deleted_at: d}, _scope) when not is_nil(d),
    do: {:error, :forbidden}

  def authorize(_action, %User{status: :suspended}, _scope), do: {:error, :forbidden}
  def authorize(_action, %User{status: :pending}, _scope), do: {:error, :forbidden}
  def authorize(_action, %User{status: :rejected}, _scope), do: {:error, :forbidden}

  def authorize(action, _actor, _scope) when action not in @valid_actions do
    Logger.warning(
      "[Foglet.Authorization] Unknown action atom: #{inspect(action)} — returning forbidden"
    )

    {:error, :forbidden}
  end

  def authorize(_action, %User{role: :sysop}, _scope), do: :ok

  def authorize(:edit_config, %User{role: :mod}, _scope), do: {:error, :forbidden}

  def authorize(action, %User{role: :mod}, :site) when action in @mod_site_actions, do: :ok

  def authorize(action, %User{role: :mod}, {:board, _board_id})
      when action in @mod_board_actions,
      do: :ok

  def authorize(:create_report, %User{role: :user}, :site), do: :ok
  def authorize(:generate_invite, %User{role: :user}, :site), do: :ok

  def authorize(_action, _actor, _scope), do: {:error, :forbidden}

  @doc """
  Returns the list of scopes an actor is authorized to operate over for a given
  action. Returns [] for guests, regular users, and non-active actors.

  This is NOT a Bodyguard callback — it is our own API for data-visibility
  filtering (consumed by Phase 8 moderation list queries). The contract is frozen
  (D-23): the v2 `board_moderators` join-table rewrite MUST NOT change the call
  signature or return shape.

  In v1.1 all mods are site-scope (no board_moderators join table yet).
  """
  @spec scopes_for(actor(), action()) :: [scope()]
  def scopes_for(nil, _action), do: []
  def scopes_for(%User{deleted_at: d}, _action) when not is_nil(d), do: []

  def scopes_for(%User{status: status}, _action) when status in [:suspended, :pending, :rejected],
    do: []

  def scopes_for(%User{role: :sysop}, _action), do: [:site]
  def scopes_for(%User{role: :mod}, _action), do: [:site]
  def scopes_for(_actor, _action), do: []
end
