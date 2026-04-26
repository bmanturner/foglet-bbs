# PROPOSAL: Fix concurrent SSH sessions in Foglet BBS

**Companion to:** `260426-jbn-RESEARCH.md`
**Status:** Recommendation only — no code changes applied

---

## TL;DR

Apply **Option A** (adopt-existing in Initializer) to two children:
PluginManager and Dispatcher. Both patches go in `vendor/raxol/`. Total
diff: ~15 lines across one file. Then harden the regression test to exercise
events + render and to clean up between runs. File two upstream issues —
Dispatcher is a clean bug, PluginManager is a design discussion.

---

## Option comparison

| Option | What changes | Surface area | Foglet impact | Foglet-side risk | Upstream maintenance burden |
|--------|--------------|--------------|---------------|------------------|----------------------------|
| **A. Adopt-existing in Initializer** ✅ recommended | Patch `start_plugin_manager/2` and `start_dispatcher/5` in `vendor/raxol/.../initializer.ex` to handle `{:error, {:already_started, pid}}` and reuse the existing pid. For Dispatcher, also extend the `:ssh` branch to pass `[name: nil]` so the second Lifecycle goes through the unnamed path. | One file, two functions, ~15 lines. | All concurrent sessions share one PluginLifecycle GenServer process and one Dispatcher per *first* Lifecycle adopted. Wait — see footnote.¹ | Low. Foglet has no plugins; PluginLifecycle's hot path is a no-op (`plugin_lifecycle.ex:222-229`). For Dispatcher we want truly per-session, so Option A becomes "name: nil only" rather than adopt — see implementation. | Lost on next `vendor/raxol` update unless upstreamed. Flag this in a `vendor/raxol/PATCHES.md` if we don't already track. |
| B. Per-Lifecycle unique names | Suffix every child name with `make_ref()` or session id. | One file, but several functions; need to thread name through many call sites. | Truly per-session children — semantically what we want. | Medium. PluginLifecycle's API hardcodes `GenServer.call(__MODULE__, ...)` everywhere (`plugin_lifecycle.ex:76, 84, 92, 100, ...`). Suffixing the GenServer's registered name doesn't help the existing client API; we'd need to rewrite or wrap every public function to accept a target. | Higher than A; same risk of being lost on update. |
| C. Patch upstream and pin a fork | Submit fix to `DROOdotFOO/raxol`, pin to our fork in `vendor/raxol/` or in `mix.exs`. | Same code change as A or B, but lives upstream. | Same as the chosen pattern. | Same as A/B short-term; long-term we own a fork. | Best long-term — no patch drift — but blocked on upstream review. Out of scope for "ship today." |
| D. Architecture pivot — single Lifecycle, multiplex sessions inside | Foglet runs **one** Lifecycle process; CLIHandler routes events to the Dispatcher with a session tag; the app demuxes session by tag. | Massive Foglet rewrite. | TUI App and every screen/widget needs to handle session context per-message instead of per-process. `Foglet.TUI.App` currently treats its own state as the session's state (`AGENTS.md` "App owns global UI state, current screen, modal routing"). | Very high. Would invalidate per-session screen state, modals, scroll position. Conflicts with one-screen-per-session model. | None upstream-side, but Foglet would be carrying a fundamentally non-standard usage of Raxol. |

¹ **Important nuance for Option A on Dispatcher:** the goal is per-session
Dispatchers (each session has its own model state). If we adopt the existing
pid we'd collapse all sessions onto one model — wrong. The right move for
Dispatcher is to pass `[name: nil]` so each Lifecycle starts its own
unnamed Dispatcher. This is what the existing `:agent`/`:liveview` branches
already do. For PluginManager, adopt-existing is fine because the per-session
plugin state is empty and the registered process is functionally a no-op
filter chain.

---

## Recommended fix (Option A, refined)

### File: `vendor/raxol/lib/raxol/core/runtime/lifecycle/initializer.ex`

**Change 1 — PluginManager: adopt existing on collision.**

Current (lines 115–132):

```elixir
defp start_plugin_manager(_options, :agent), do: {:ok, nil}
defp start_plugin_manager(_options, :liveview), do: {:ok, nil}

defp start_plugin_manager(options, _environment) do
  plugin_manager_opts = Keyword.get(options, :plugin_manager_opts, [])

  case Manager.start_link(plugin_manager_opts) do
    {:ok, pm_pid} ->
      Log.info_with_context(
        "[Lifecycle.Initializer] PluginManager started with PID: #{inspect(pm_pid)}"
      )

      {:ok, pm_pid}

    {:error, reason} ->
      {:error, {:plugin_manager_start_failed, reason}, fn -> :ok end}
  end
end
```

Proposed:

```elixir
defp start_plugin_manager(_options, :agent), do: {:ok, nil}
defp start_plugin_manager(_options, :liveview), do: {:ok, nil}

defp start_plugin_manager(options, _environment) do
  plugin_manager_opts = Keyword.get(options, :plugin_manager_opts, [])

  case Manager.start_link(plugin_manager_opts) do
    {:ok, pm_pid} ->
      Log.info_with_context(
        "[Lifecycle.Initializer] PluginManager started with PID: #{inspect(pm_pid)}"
      )

      {:ok, pm_pid}

    # Adopt-existing: PluginLifecycle is registered as a singleton
    # (plugin_lifecycle.ex:65-67). Concurrent Lifecycles share the same
    # plugin manager process. Safe today because (a) the registered
    # GenServer's hot path is a passthrough when no plugins are loaded
    # (plugin_lifecycle.ex:222-229), and (b) all dispatcher-side filter
    # calls go through the stored pid, not the registered name.
    {:error, {:already_started, pm_pid}} ->
      Log.info_with_context(
        "[Lifecycle.Initializer] PluginManager already started; adopting PID: #{inspect(pm_pid)}"
      )

      {:ok, pm_pid}

    {:error, reason} ->
      {:error, {:plugin_manager_start_failed, reason}, fn -> :ok end}
  end
end
```

**Change 2 — Dispatcher: include `:ssh` in the unnamed-environment list.**

Current (lines 208–211):

```elixir
environment = Keyword.get(options, :environment, :terminal)

dispatcher_opts =
  if environment in [:agent, :liveview], do: [name: nil], else: []
```

Proposed:

```elixir
environment = Keyword.get(options, :environment, :terminal)

# `:ssh` is multi-instance per channel (one Lifecycle per SSH session),
# so the Dispatcher must not hold a globally-registered name. Same
# reasoning as :agent and :liveview, which were already in this list.
dispatcher_opts =
  if environment in [:agent, :liveview, :ssh], do: [name: nil], else: []
```

That's it. Two changes, one file. No CLIHandler changes needed (the existing
`name: nil` for Lifecycle already works; PluginManager and Dispatcher are
internal and not addressable by the caller).

### Why not also patch CodeReloader / TimeTravel / CycleProfiler?

- **CodeReloader** (`code_reloader.ex:18-19`): only starts in `Mix.env() == :dev` (`initializer.ex:57`). Never runs in production. Local dev hazard only — flag for follow-up, don't block the fix.
- **TimeTravel** (`time_travel.ex:50-54`) and **CycleProfiler** (`cycle_profiler.ex:70-74`): both opt-in and Foglet doesn't pass the flags. Not a hazard. Their `start_link` already accepts `:name` overrides, so a future patch is trivial.

---

## Test plan

### File: `test/foglet_bbs/ssh/concurrent_lifecycle_test.exs`

Replace the current 39-line file with a more thorough version. Sketch:

```elixir
defmodule Foglet.SSH.ConcurrentLifecycleTest do
  @moduledoc """
  Regression: every SSH connection must get its own Raxol Lifecycle and its
  own Dispatcher / RenderingEngine. Two Lifecycles must be able to render
  independently without sharing model state.

  See vendor/raxol/lib/raxol/core/runtime/lifecycle/initializer.ex and
  .planning/quick/260426-jbn-.../260426-jbn-RESEARCH.md for the audit.
  """

  use ExUnit.Case, async: false

  alias Raxol.Core.Events.Event
  alias Raxol.Core.Runtime.Lifecycle

  @opts_template [
    name: nil,
    environment: :ssh,
    width: 80,
    height: 24,
    context: %{
      session_context: %{
        user: nil, user_id: nil, session_pid: nil,
        peer: nil, pubkey_user: nil
      },
      terminal_size: {80, 24}
    }
  ]

  setup do
    on_exit(fn ->
      # Belt-and-suspenders: any leaked PluginLifecycle / Dispatcher
      # singletons get cleared so subsequent tests start cleanly.
      for name <- [
        Raxol.Core.Runtime.Plugins.PluginLifecycle,
        Raxol.Core.Runtime.Events.Dispatcher
      ] do
        case Process.whereis(name) do
          nil -> :ok
          pid -> GenServer.stop(pid, :normal, 1_000)
        end
      end
    end)

    :ok
  end

  test "two concurrent Lifecycles start with distinct dispatcher pids" do
    {:ok, pid1} = Lifecycle.start_link(Foglet.TUI.App, @opts_template)
    {:ok, pid2} = Lifecycle.start_link(Foglet.TUI.App, @opts_template)

    assert pid1 != pid2
    assert Process.alive?(pid1) and Process.alive?(pid2)

    %{dispatcher_pid: d1, rendering_engine_pid: r1} =
      GenServer.call(pid1, :get_full_state)

    %{dispatcher_pid: d2, rendering_engine_pid: r2} =
      GenServer.call(pid2, :get_full_state)

    # Each Lifecycle owns its own Dispatcher and Engine.
    assert is_pid(d1) and is_pid(d2) and d1 != d2
    assert is_pid(r1) and is_pid(r2) and r1 != r2

    stop_lifecycles([pid1, pid2])
  end

  test "events dispatched to one Lifecycle don't leak into the other" do
    {:ok, pid1} = Lifecycle.start_link(Foglet.TUI.App, @opts_template)
    {:ok, pid2} = Lifecycle.start_link(Foglet.TUI.App, @opts_template)

    %{dispatcher_pid: d1} = GenServer.call(pid1, :get_full_state)
    %{dispatcher_pid: d2} = GenServer.call(pid2, :get_full_state)

    GenServer.cast(d1, {:dispatch, Event.new(:resize, %{width: 120, height: 40})})
    GenServer.cast(d2, {:dispatch, Event.new(:resize, %{width: 200, height: 60})})

    # Allow casts to process (no Process.sleep in product code per AGENTS;
    # in tests we synchronize via :sys.get_state).
    state1 = :sys.get_state(d1)
    state2 = :sys.get_state(d2)

    assert {state1.width, state1.height} == {120, 40}
    assert {state2.width, state2.height} == {200, 60}

    stop_lifecycles([pid1, pid2])
  end

  test "force-render both lifecycles synchronously" do
    {:ok, pid1} = Lifecycle.start_link(Foglet.TUI.App, @opts_template)
    {:ok, pid2} = Lifecycle.start_link(Foglet.TUI.App, @opts_template)

    %{rendering_engine_pid: r1} = GenServer.call(pid1, :get_full_state)
    %{rendering_engine_pid: r2} = GenServer.call(pid2, :get_full_state)

    # render_frame_sync uses GenServer.call → exercises the full pipeline
    # and surfaces any singleton collision deep in plugin filters / layout.
    assert :ok = GenServer.call(r1, :render_frame_sync)
    assert :ok = GenServer.call(r2, :render_frame_sync)

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
```

Key invariants this exercises:

| Invariant | Asserted by |
|-----------|-------------|
| Lifecycle process is per-session | Test 1: `pid1 != pid2` |
| Dispatcher process is per-session | Test 1: `d1 != d2` |
| RenderingEngine process is per-session | Test 1: `r1 != r2` |
| Per-session model state stays separate | Test 2: distinct widths in dispatcher state after cross-dispatched events |
| Render pipeline doesn't deadlock under concurrent calls | Test 3: `render_frame_sync` succeeds for both |
| Test is rerunnable | `setup` + `on_exit` cleanup of leaked named singletons |

`render_frame_sync` ends up calling `GenServer.call(state.dispatcher_pid,
:get_render_context)` (`engine.ex:154-171`), so the Engine→Dispatcher round
trip must work for the call to return `:ok`. If anything in the chain still
addresses a singleton by `__MODULE__`, this test will deadlock or get the
wrong session's data, and we'll know.

---

## Risk register

| Risk | Severity | Mitigation |
|------|----------|------------|
| Adopted PluginLifecycle leaks state across sessions | Medium | Plugin state is keyed by plugin_id (`plugin_lifecycle.ex:415-438`) and ETS-backed via `StateManager` (`state_manager.ex:147-150`). With zero plugins loaded, there's no state to leak. Add a smoke check in PR: `assert PluginRegistry.count() == 0` after running the test. |
| `vendor/raxol` patch lost on next vendor update | Medium | Document in `vendor/raxol/PATCHES.md` (or whatever the convention is — needs verification) and file the upstream issue immediately so the patch goes away. |
| Dispatcher's `Registry` for PubSub (`dispatcher.ex:23, @registry_name :raxol_event_subscriptions`) may not be started in test env | Low | Code already handles `ArgumentError` rescue (`dispatcher.ex:352-356`). Test 3 doesn't broadcast, so this won't fire. |
| `Raxol.Core.UserPreferences` and `FocusManager.FocusServer` are global singletons not started in test env | Low | Code defensively wraps these (`dispatcher.ex:644-648, 758-760`). Tests don't exercise them. |
| First-Lifecycle's PluginManager dies before second-Lifecycle finishes — adopted pid is dead | Low | If `:already_started` is returned but process dies before adoption, the second Lifecycle would crash on its first `GenServer.call(pm_pid, ...)`. Standard Elixir failure mode; the calling Lifecycle would `{:stop, reason}` and the SSH channel would close cleanly via the `EXIT` handler at `cli_handler.ex:148-168`. Acceptable. |

---

## Upstream issue draft — to file at `https://github.com/DROOdotFOO/raxol/issues`

### Issue 1 (clean bug): `:ssh` environment missing from Dispatcher's multi-instance branch

**Title:** `Dispatcher singleton blocks concurrent :ssh sessions — missing from :agent/:liveview branch in initializer.ex`

**Body:**

```markdown
## Summary

`Raxol.Core.Runtime.Lifecycle.Initializer.start_dispatcher/5` registers the
Dispatcher with `name: __MODULE__` for every environment except `:agent`
and `:liveview`. The `:ssh` environment is conceptually multi-instance
(one Lifecycle per SSH channel) but is not in this list, so the second
concurrent SSH session fails with `{:error, {:already_started, _}}`.

## Reproduction

```elixir
opts = [name: nil, environment: :ssh, width: 80, height: 24]

{:ok, _} = Raxol.Core.Runtime.Lifecycle.start_link(MyApp, opts)
{:ok, _} = Raxol.Core.Runtime.Lifecycle.start_link(MyApp, opts)
#=> ** (MatchError) ... {:error, {:plugin_manager_start_failed, ...}}
#   (or, after fixing PluginManager, an :already_started error from Dispatcher)
```

## Root cause

`vendor/raxol/lib/raxol/core/runtime/lifecycle/initializer.ex:208-211`:

```elixir
environment = Keyword.get(options, :environment, :terminal)

dispatcher_opts =
  if environment in [:agent, :liveview], do: [name: nil], else: []
```

Every callsite of the Dispatcher in the runtime addresses it by pid stored
in another process's state (e.g. `engine.ex:103`, `cli_handler` patterns
in downstream apps), so the `__MODULE__` registration is unused in the hot
path. Adding `:ssh` to the list is safe.

## Proposed fix (one-liner)

```diff
   dispatcher_opts =
-    if environment in [:agent, :liveview], do: [name: nil], else: []
+    if environment in [:agent, :liveview, :ssh], do: [name: nil], else: []
```

(Or, more honestly: drop the env check and always `[name: nil]`. The
runtime never looks the Dispatcher up by name.)

## Why this matters

Raxol advertises "SSH serving" in its package description (`mix.exs`), and
the runtime has explicit `:ssh` branches in `dispatcher.ex:211`,
`engine.ex:434`, and `lifecycle.ex:324-328`. Concurrent SSH sessions are
the obvious deployment shape and don't currently work.

Happy to send a PR with the one-liner + a regression test.
```

### Issue 2 (design discussion): PluginLifecycle hardcodes `__MODULE__`

**Title:** `PluginLifecycle assumes singleton-per-VM; breaks when Lifecycle is multi-instance`

**Body:**

```markdown
## Context

`Raxol.Core.Runtime.Plugins.PluginLifecycle` (in `raxol_core`) registers
itself as `name: __MODULE__` (plugin_lifecycle.ex:65-67) and every public
client function calls `GenServer.call(__MODULE__, ...)`
(plugin_lifecycle.ex:76, 84, 92, 100, 108, ...). When concurrent Raxol
Lifecycles exist (e.g. one per SSH channel), `Initializer.start_plugin_manager/2`
fails with `{:error, {:already_started, _}}`, which the with-chain converts
to `{:plugin_manager_start_failed, ...}` and aborts Lifecycle init.

## Question for maintainers

Is the plugin manager intended to be:

(a) **VM-global** — one plugin set per BEAM, shared across all Lifecycles? In
that case, `start_plugin_manager/2` should adopt the existing pid on
`:already_started` rather than failing. Suggested fix attached.

(b) **Per-Lifecycle** — each app instance has its own plugin set? In that
case the `__MODULE__` hardcoding in PluginLifecycle's client API needs to
be reworked to accept a target server.

I'd guess (a) given the StateManager already namespaces plugins by id and
the registry is ETS-global, but want to confirm before sending a PR.

## Minimal viable fix for (a)

```diff
   defp start_plugin_manager(options, _environment) do
     plugin_manager_opts = Keyword.get(options, :plugin_manager_opts, [])

     case Manager.start_link(plugin_manager_opts) do
       {:ok, pm_pid} ->
         {:ok, pm_pid}

+      {:error, {:already_started, pm_pid}} ->
+        # Adopt the existing singleton manager; safe under design (a).
+        {:ok, pm_pid}

       {:error, reason} ->
         {:error, {:plugin_manager_start_failed, reason}, fn -> :ok end}
     end
   end
```

Happy to send a PR once design intent is confirmed.
```

---

## Sequencing

1. Apply Change 1 + Change 2 in `vendor/raxol/.../initializer.ex` (single commit).
2. Replace the regression test (single commit).
3. Run the full Foglet test suite + `mix precommit`.
4. Smoke test by SSH-ing in twice from two terminals.
5. File the two upstream issues.
6. Add a note to `vendor/raxol/PATCHES.md` (or create one) tracking the local diff and pointing at the upstream issue numbers.

Steps 1–4 are the production-blocking fix. Steps 5–6 protect us from drift.
