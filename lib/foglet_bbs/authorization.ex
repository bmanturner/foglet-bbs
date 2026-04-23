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

  alias Foglet.Accounts.User

  @valid_actions [
    :lock_thread, :unlock_thread, :sticky_thread, :unsticky_thread,
    :move_thread, :delete_thread,
    :delete_post, :edit_post_as_mod,
    :hide_oneliner,
    :create_board, :update_board, :archive_board,
    :create_category, :update_category, :archive_category,
    :edit_config,
    :generate_invite, :revoke_invite
  ]

  @mod_site_actions [
    :lock_thread, :unlock_thread, :sticky_thread, :unsticky_thread,
    :move_thread, :delete_thread,
    :delete_post, :edit_post_as_mod,
    :hide_oneliner,
    :generate_invite, :revoke_invite
  ]

  @mod_board_actions [
    :lock_thread, :unlock_thread, :sticky_thread, :unsticky_thread,
    :move_thread, :delete_thread,
    :delete_post, :edit_post_as_mod,
    :hide_oneliner
  ]

  @type actor :: User.t() | nil
  @type action :: atom()
  @type scope :: :site | {:board, Ecto.UUID.t()}

  # ---------- Bodyguard.Policy callback ----------
  #
  # We always return :ok or {:error, :forbidden} explicitly (never bare :error)
  # so Bodyguard.permit/4's coercion preserves the reason unchanged (D-14).

  @impl Bodyguard.Policy
  @spec authorize(action(), actor(), scope()) :: :ok | {:error, :forbidden}

  # Invalid actor guards (D-24) — checked before any role or action dispatch.
  def authorize(_action, nil, _scope), do: {:error, :forbidden}

  def authorize(_action, %User{deleted_at: d}, _scope) when not is_nil(d),
    do: {:error, :forbidden}

  def authorize(_action, %User{status: :suspended}, _scope), do: {:error, :forbidden}
  def authorize(_action, %User{status: :pending}, _scope), do: {:error, :forbidden}

  # Unknown action (D-13) — safe default, warning, no raise.
  def authorize(action, _actor, _scope) when action not in @valid_actions do
    require Logger

    Logger.warning(
      "[Foglet.Authorization] Unknown action atom: #{inspect(action)} — returning forbidden"
    )

    {:error, :forbidden}
  end

  # Sysop: permitted for all valid actions at any scope.
  def authorize(_action, %User{role: :sysop}, _scope), do: :ok

  # Mod: sysop-only actions — explicit deny BEFORE the mod-site allowlist (ordering matters).
  def authorize(:edit_config, %User{role: :mod}, _scope), do: {:error, :forbidden}

  # Mod: site-scope moderation actions.
  def authorize(action, %User{role: :mod}, :site) when action in @mod_site_actions, do: :ok

  # Mod: board-scope moderation actions (subset — no board lifecycle ops).
  def authorize(action, %User{role: :mod}, {:board, _board_id})
      when action in @mod_board_actions,
      do: :ok

  # Safe default deny (D-13 catch-all; mirrors InvitesSurface.visible?/2 final clause).
  def authorize(_action, _actor, _scope), do: {:error, :forbidden}

  # ---------- Public helpers (non-Bodyguard) ----------

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

  def scopes_for(%User{status: status}, _action) when status in [:suspended, :pending],
    do: []

  def scopes_for(%User{role: :sysop}, _action), do: [:site]
  def scopes_for(%User{role: :mod}, _action), do: [:site]
  def scopes_for(_actor, _action), do: []
end
