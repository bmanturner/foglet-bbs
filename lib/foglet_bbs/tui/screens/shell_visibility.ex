defmodule Foglet.TUI.Screens.ShellVisibility do
  @moduledoc """
  Centralized role/config visibility predicates for Phase 0 shell entry points.

  Consumed by:
    * `Foglet.TUI.Screens.MainMenu` — decides which menu entries to render and
      which key bindings to honor (D-01, D-02).
    * `Foglet.TUI.Screens.Account`, `Foglet.TUI.Screens.Moderation`,
      `Foglet.TUI.Screens.Sysop` — the shells themselves verify their own
      visibility to avoid drift if routed to directly.

  Security Domain (RESEARCH.md): centralizing visibility prevents the common
  pitfall where MainMenu and a shell disagree about who may see something
  (Pitfall 3 — menu visibility is not authorization, but duplicated visibility
  rules are still a tampering/EoP vector via drift). Real actor-aware
  authorization is deferred to Phase 1.

  See also `Foglet.TUI.Screens.Shared.InvitesSurface.visible?/2` for the
  canonical policy/role matrix used by `invites_visible?/2`.
  """

  alias Foglet.TUI.Screens.Shared.InvitesSurface

  @doc """
  Returns `true` for any authenticated (non-nil) user (D-01).

  Account is a standard destination for every logged-in user regardless of role.
  """
  @spec account_visible?(map() | nil) :: boolean()
  def account_visible?(nil), do: false
  def account_visible?(_user), do: true

  @doc """
  Returns `true` when the user holds the `:mod` or `:sysop` role (D-02).

  Sysops can moderate, so both roles grant access to the Moderation shell.
  Returns `false` for `nil` or any user without a recognized moderator role.
  """
  @spec moderation_visible?(map() | nil) :: boolean()
  def moderation_visible?(nil), do: false
  def moderation_visible?(%{role: role}) when role in [:mod, :sysop], do: true
  def moderation_visible?(_), do: false

  @doc """
  Returns `true` only when the user holds the `:sysop` role (D-02).

  The Sysop shell exposes operator-level controls — only sysops may enter.
  Returns `false` for `nil` or any non-sysop user.
  """
  @spec sysop_visible?(map() | nil) :: boolean()
  def sysop_visible?(nil), do: false
  def sysop_visible?(%{role: :sysop}), do: true
  def sysop_visible?(_), do: false

  @doc """
  Returns `true` when the invite policy and user role permit invite generation.

  Resolves the invite policy from `session_context[:invite_code_generators]`;
  falls back to `Foglet.Config.invite_code_generators/0` when the key is absent.
  If the config read fails (ETS not seeded, DB unavailable), treats the policy as
  `nil` — which causes `InvitesSurface.visible?/2` to return `false` for
  non-sysops (safe default).

  Delegates the role + policy decision to
  `Foglet.TUI.Screens.Shared.InvitesSurface.visible?/2` (single source of truth,
  Plan 02). See that module for the full policy/role matrix.
  """
  @spec invites_visible?(map() | nil, map() | nil) :: boolean()
  def invites_visible?(user, session_context) do
    policy = resolve_policy(session_context)
    InvitesSurface.visible?(user, policy)
  end

  # --- private ---

  defp resolve_policy(nil), do: config_policy_or_nil()

  defp resolve_policy(session_context) when is_map(session_context) do
    case Map.get(session_context, :invite_code_generators) do
      nil -> config_policy_or_nil()
      policy when is_binary(policy) -> policy
      _ -> nil
    end
  end

  defp config_policy_or_nil do
    Foglet.Config.invite_code_generators()
  rescue
    e ->
      require Logger

      Logger.warning(
        "[ShellVisibility] invite_code_generators config read failed: " <>
          Exception.message(e) <> " — defaulting policy to nil"
      )

      nil
  catch
    :exit, reason ->
      require Logger

      Logger.warning(
        "[ShellVisibility] invite_code_generators exited: #{inspect(reason)} — " <>
          "defaulting policy to nil"
      )

      nil
  end
end
