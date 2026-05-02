defmodule FogletBbs.ConfigTestHelpers do
  @moduledoc """
  Helpers for safely mutating process-global `Foglet.Config` keys inside tests.

  `Foglet.Config` uses a process-global ETS cache (`:foglet_config`). The Ecto
  sandbox rolls back DB writes between tests, but it does not touch ETS — so a
  test that calls `Foglet.Config.put!/3` and exits without invalidating the
  cache leaves a stale value visible to the rest of the suite. That is the
  CI-flake mode triaged in FOG-263 (and originally surfaced by FOG-253 /
  PR #33): a sibling test left `registration_mode = "invite_only"` sticky and
  unrelated `Accounts.register_user/3` assertions then failed with
  `invite_code: is invalid or unavailable`.

  Use these helpers from `setup`/`setup_all` blocks or test bodies — they
  register an `on_exit/1` callback that drops the ETS row, so the next read
  re-populates from the (sandbox-rolled-back) DB.
  """

  alias Foglet.Config

  @doc """
  Set a config `key` to `value` for the current test, auto-invalidating the
  ETS cache when the test exits.

  Equivalent to:

      Config.put!(key, value, updated_by_id)
      on_exit(fn -> Config.invalidate(key) end)

  Must be called from a process where `ExUnit.Callbacks.on_exit/1` is valid
  (a test or `setup` block). Returns the inserted/updated `Foglet.Config.Entry`.
  """
  @spec put_config!(String.t(), term(), String.t() | nil) :: Foglet.Config.Entry.t()
  def put_config!(key, value, updated_by_id \\ nil) when is_binary(key) do
    ExUnit.Callbacks.on_exit(fn -> Config.invalidate(key) end)
    Config.put!(key, value, updated_by_id)
  end

  @doc """
  Register `on_exit` invalidation for `keys` without writing them now.

  Useful when a test mutates several config keys by other paths (e.g. through
  the sysop TUI) and needs to guarantee the ETS cache is dropped on exit so
  later tests re-read the rolled-back DB state.
  """
  @spec ensure_config_isolated([String.t()]) :: :ok
  def ensure_config_isolated(keys) when is_list(keys) do
    ExUnit.Callbacks.on_exit(fn ->
      for key <- keys, do: Config.invalidate(key)
      :ok
    end)

    :ok
  end
end
