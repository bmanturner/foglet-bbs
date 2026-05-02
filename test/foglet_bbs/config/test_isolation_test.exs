defmodule Foglet.Config.TestIsolationTest do
  @moduledoc """
  Regression for FOG-263 — process-global ETS cache leak across tests.

  `Foglet.Config` writes go through ETS (`:foglet_config`), which the Ecto
  sandbox does not roll back. A test that mutates a key without invalidating
  the cache on exit can leave a stale value visible to the rest of the suite
  (originally surfaced on PR #33 / FOG-253 as a sticky
  `registration_mode = "invite_only"` that broke unrelated `register_user`
  assertions with `invite_code: is invalid or unavailable`).

  These tests pin `FogletBbs.ConfigTestHelpers`' contract directly: after a
  helper-managed mutation, an `on_exit` callback is registered with
  `ExUnit.OnExitHandler` that invalidates the ETS row. We drive that handler
  ourselves against a controlled child pid so the assertion is deterministic
  under any `--seed` and does not depend on inter-test ordering.

  `async: false` is required because `:foglet_config` is a process-global
  named ETS table.
  """

  use FogletBbs.DataCase, async: false

  alias ExUnit.OnExitHandler
  alias Foglet.Config
  alias FogletBbs.ConfigTestHelpers

  setup do
    Config.init_cache()
    Config.invalidate("registration_mode")
    Config.invalidate("delivery_mode")
    Config.put!("registration_mode", "open", nil)
    Config.put!("delivery_mode", "no_email", nil)

    on_exit(fn ->
      Config.invalidate("registration_mode")
      Config.invalidate("delivery_mode")
    end)

    :ok
  end

  describe "put_config!/3" do
    test "registers an on_exit callback that invalidates the ETS cache for the key" do
      assert Config.get!("registration_mode") == "open"

      child =
        run_in_isolated_test_pid(fn ->
          ConfigTestHelpers.put_config!("registration_mode", "invite_only", nil)
        end)

      # The mutation is visible (DB sandbox is shared with this owner pid; the
      # helper's put!/3 invalidates ETS, so a re-read repopulates from DB).
      assert Config.get!("registration_mode") == "invite_only"

      # Drive the on_exit callbacks that ExUnit would fire on test exit.
      assert OnExitHandler.run(child, 5_000) == :ok

      refute :ets.member(:foglet_config, "registration_mode"),
             "expected put_config!/3's on_exit callback to drop the registration_mode cache row"
    end
  end

  describe "ensure_config_isolated/1" do
    test "registers an on_exit callback that invalidates each listed key" do
      # Prime the cache so we can observe invalidation.
      assert Config.get!("registration_mode") == "open"
      assert Config.get!("delivery_mode") == "no_email"
      assert :ets.member(:foglet_config, "registration_mode")
      assert :ets.member(:foglet_config, "delivery_mode")

      child =
        run_in_isolated_test_pid(fn ->
          :ok = ConfigTestHelpers.ensure_config_isolated(["registration_mode", "delivery_mode"])
        end)

      assert OnExitHandler.run(child, 5_000) == :ok

      refute :ets.member(:foglet_config, "registration_mode")
      refute :ets.member(:foglet_config, "delivery_mode")
    end

    test "an empty key list is a no-op that returns :ok" do
      assert ConfigTestHelpers.ensure_config_isolated([]) == :ok
    end
  end

  # ---- helpers --------------------------------------------------------------

  # `ExUnit.Callbacks.on_exit/1` binds to `self()` and writes through
  # `ExUnit.OnExitHandler`. To unit-test the helper's contract without
  # depending on ExUnit's per-test lifecycle (and the inter-test ordering
  # that an "A then B" pair would imply), we run the helper inside a
  # short-lived child process that we explicitly register with the handler.
  # After the child exits we hand its pid to the caller so they can drive
  # `OnExitHandler.run/2` and assert the registered callbacks fire.
  defp run_in_isolated_test_pid(fun) when is_function(fun, 0) do
    parent = self()

    child =
      spawn(fn ->
        OnExitHandler.register(self())
        fun.()
        send(parent, {:ready, self()})

        receive do
          :exit -> :ok
        end
      end)

    assert_receive {:ready, ^child}, 5_000

    ref = Process.monitor(child)
    send(child, :exit)
    assert_receive {:DOWN, ^ref, :process, ^child, _}, 5_000

    child
  end
end
