defmodule Foglet.TUI.Screens.Domain do
  @moduledoc """
  Domain-module lookup helper for Foglet BBS TUI screens.

  One responsibility:

  1. **Lookup** — Given a `session_context` map and a domain key atom,
     returns the configured domain module or `{:error, :not_configured}`
     when the key is absent or the domain is not set up.

  Supported keys (AUDIT-02 baseline + Phase 29 :accounts):
    :boards, :threads, :posts, :markdown, :oneliners, :moderation, :accounts

  Callers provide `state.session_context` (the narrower input).
  Each call site is responsible for its own default-module fallback
  via an explicit `{:error, :not_configured}` branch. This keeps
  defaults visible and test-injectable at the call site.

  See `Foglet.TUI.Screens.BoardList`, `ThreadList`, `PostReader`,
  `PostComposer`, `NewThread` for call-site examples. The `:accounts`
  key was added in Phase 29 to swap `Foglet.Accounts` under the
  Sysop USERS load triad (`{:load_sysop_users}`).
  """

  @supported_keys [:boards, :threads, :posts, :markdown, :oneliners, :moderation, :accounts]

  @type domain_key ::
          :boards | :threads | :posts | :markdown | :oneliners | :moderation | :accounts
  @type result :: {:ok, module()} | {:error, :not_configured}

  @doc """
  Returns `{:ok, module}` when `ctx` contains a domain module configured
  for `key`, or `{:error, :not_configured}` otherwise.

  `key` must be one of #{inspect(@supported_keys)}. Unknown keys always
  return `{:error, :not_configured}` — no raise.
  """
  @spec get(map(), domain_key()) :: result()
  def get(ctx, key) when key in @supported_keys do
    mod =
      case Map.get(ctx, :domain) do
        domain when is_map(domain) -> Map.get(domain, key)
        _ -> nil
      end

    case mod do
      mod when is_atom(mod) and not is_nil(mod) -> {:ok, mod}
      _ -> {:error, :not_configured}
    end
  end

  def get(_ctx, _key), do: {:error, :not_configured}
end
