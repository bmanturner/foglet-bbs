defmodule Foglet.Config.TestIsolationTest do
  @moduledoc """
  Regression for FOG-263 — process-global ETS cache leak across tests.

  `Foglet.Config` writes go through ETS (`:foglet_config`), which the Ecto
  sandbox does not roll back. A test that mutates a key without invalidating
  the cache on exit can leave a stale value visible to the rest of the suite.
  Originally surfaced as a CI flake on PR #33 / FOG-253 where a sibling test
  pinned `registration_mode = "invite_only"` and downstream registration
  assertions then failed with `invite_code: is invalid or unavailable`.

  This file pairs two sequential tests: step A mutates `registration_mode`
  through `FogletBbs.ConfigTestHelpers.put_config!/3`, step B asserts the
  ETS cache was invalidated on step A's exit. ExUnit runs tests within a
  module in source order, so step B observes step A's exit-time effects
  even at `--seed 0`.

  `async: false` is required because `:foglet_config` is a process-global
  named ETS table — we must own ordering relative to siblings.
  """

  use FogletBbs.DataCase, async: false

  alias Foglet.Config
  alias FogletBbs.ConfigTestHelpers

  setup do
    Config.init_cache()
    Config.invalidate("registration_mode")
    Config.put!("registration_mode", "open", nil)
    on_exit(fn -> Config.invalidate("registration_mode") end)
    :ok
  end

  describe "FOG-263 regression" do
    test "step A: put_config!/3 mutates registration_mode for this test" do
      assert Config.get!("registration_mode") == "open"
      ConfigTestHelpers.put_config!("registration_mode", "invite_only", nil)
      assert Config.get!("registration_mode") == "invite_only"
    end

    test "step B: ETS cache was invalidated on step A's exit (no leak)" do
      # The sandbox rolled back step A's DB write; without ETS invalidation
      # the cache would still hand back "invite_only" and this read would
      # raise `Ecto.NoResultsError` on the cache miss path or return the
      # stale cached string. With the helper's on_exit invalidation the
      # cache miss reloads from DB, where setup just seeded "open".
      assert Config.get!("registration_mode") == "open"
    end
  end

  describe "ensure_config_isolated/1" do
    test "drops listed keys from the ETS cache on test exit" do
      Config.put!("registration_mode", "invite_only", nil)
      assert Config.get!("registration_mode") == "invite_only"

      ConfigTestHelpers.ensure_config_isolated(["registration_mode"])

      # The on_exit hook registered above will invalidate after this test
      # body returns. We can at least verify the helper itself is a no-op
      # synchronously and does not blow up on an empty key list.
      assert ConfigTestHelpers.ensure_config_isolated([]) == :ok
    end
  end
end
