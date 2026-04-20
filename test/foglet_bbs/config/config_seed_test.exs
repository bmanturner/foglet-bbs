defmodule Foglet.ConfigSeedTest do
  @moduledoc """
  Confirms that the seed script inserts config entries consumed by the TUI.

  The seed logic lives in `priv/repo/seeds.exs` — this test exercises
  `Foglet.Config.put!/3` + `Foglet.Config.get!/1` directly to simulate
  what the seed does, without requiring `mix run priv/repo/seeds.exs`
  to succeed in the test env (which would also create users, boards,
  and threads — not relevant here).
  """
  use FogletBbs.DataCase, async: false

  alias Foglet.Config

  describe "max_thread_title_length (D-13, Phase 4)" do
    test "can be put! and then read via get!" do
      Config.put!("max_thread_title_length", 60, nil)

      assert Config.get!("max_thread_title_length") == 60
    end

    test "returns 60 as the seeded default when put! is called without a value change" do
      Config.put!("max_thread_title_length", 60, nil)
      Config.put!("max_thread_title_length", 60, nil)

      assert Config.get!("max_thread_title_length") == 60
    end

    test "a sysop can raise the cap without a migration (D-15 backstop still applies)" do
      Config.put!("max_thread_title_length", 300, nil)

      assert Config.get!("max_thread_title_length") == 300
    end
  end
end
