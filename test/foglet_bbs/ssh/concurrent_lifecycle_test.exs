defmodule Foglet.SSH.ConcurrentLifecycleTest do
  @moduledoc """
  Regression: every SSH connection must get its own Raxol Lifecycle, Dispatcher
  and RenderingEngine, and per-session model state must not leak between them.

  Background:
    * `Raxol.Core.Runtime.Lifecycle.start_link/2` derives a globally-registered
      process name from the app module unless `:name` is passed
      (vendor/raxol/lib/raxol/core/runtime/lifecycle.ex:82-87). CLIHandler now
      passes `name: nil`.
    * `vendor/raxol/lib/raxol/core/runtime/lifecycle/initializer.ex` previously
      excluded `:ssh` from the multi-instance Dispatcher branch, and aborted
      Lifecycle init when PluginManager was already started. Both are fixed.

  See `.planning/quick/260426-jbn-the-application-only-allows-one-active-c/`
  for the full audit and proposal.
  """

  use FogletBbs.DataCase, async: false

  alias Raxol.Core.Events.Event
  alias Raxol.Core.Runtime.Lifecycle

  @opts_template [
    name: nil,
    environment: :ssh,
    width: 80,
    height: 24,
    context: %{
      session_context: %Foglet.TUI.SessionContext{
        user: nil,
        user_id: nil,
        session_pid: nil,
        pubkey_authenticated: false
      },
      terminal_size: {80, 24}
    }
  ]

  setup do
    # Lifecycle.start_link links to the caller; if the Lifecycle stops for any
    # reason (including the explicit :shutdown cast at end-of-test) the test
    # process would die too. Trap exits so we own teardown.
    Process.flag(:trap_exit, true)

    on_exit(fn ->
      # Belt-and-suspenders: any PluginLifecycle / Dispatcher singletons
      # leaked from earlier Lifecycle starts get cleared so subsequent tests
      # see a clean slate.
      for name <- [
            Raxol.Core.Runtime.Plugins.PluginLifecycle,
            Raxol.Core.Runtime.Events.Dispatcher
          ] do
        case Process.whereis(name) do
          nil -> :ok
          pid -> _ = catch_exit(GenServer.stop(pid, :normal, 1_000))
        end
      end
    end)

    :ok
  end

  test "two concurrent Lifecycles start with distinct dispatcher and engine pids" do
    {:ok, pid1} = Lifecycle.start_link(Foglet.TUI.App, @opts_template)
    {:ok, pid2} = Lifecycle.start_link(Foglet.TUI.App, @opts_template)

    assert pid1 != pid2

    # Synchronous GenServer.call below proves liveness without Process.alive?/1 (per AGENTS.md).
    %{dispatcher_pid: d1, rendering_engine_pid: r1} =
      GenServer.call(pid1, :get_full_state)

    %{dispatcher_pid: d2, rendering_engine_pid: r2} =
      GenServer.call(pid2, :get_full_state)

    assert is_pid(d1) and is_pid(d2)
    assert d1 != d2
    assert is_pid(r1) and is_pid(r2)
    assert r1 != r2

    stop_lifecycles([pid1, pid2])
  end

  test "events dispatched to one Lifecycle don't leak into the other" do
    {:ok, pid1} = Lifecycle.start_link(Foglet.TUI.App, @opts_template)
    {:ok, pid2} = Lifecycle.start_link(Foglet.TUI.App, @opts_template)

    %{dispatcher_pid: d1} = GenServer.call(pid1, :get_full_state)
    %{dispatcher_pid: d2} = GenServer.call(pid2, :get_full_state)

    GenServer.cast(d1, {:dispatch, Event.new(:resize, %{width: 120, height: 40})})
    GenServer.cast(d2, {:dispatch, Event.new(:resize, %{width: 200, height: 60})})

    state1 = :sys.get_state(d1)
    state2 = :sys.get_state(d2)

    assert {state1.width, state1.height} == {120, 40}
    assert {state2.width, state2.height} == {200, 60}

    stop_lifecycles([pid1, pid2])
  end

  defp stop_lifecycles(pids) do
    refs = Enum.map(pids, &Process.monitor/1)
    Enum.each(pids, &Lifecycle.stop/1)

    for ref <- refs do
      receive do
        {:DOWN, ^ref, :process, _, _} -> :ok
      after
        2_000 -> flunk("Lifecycle did not terminate within 2s")
      end
    end
  end
end
