# RESEARCH: Foglet BBS — single-connection ceiling caused by globally-named per-Lifecycle children

**Researched:** 2026-04-26
**Domain:** Raxol Core Runtime (vendored at `vendor/raxol/`, plugin layer in `deps/raxol_core/`)
**Confidence:** HIGH (every claim is anchored to file:line; reproduction already exists)

---

## Summary

Foglet BBS spins up one `Raxol.Core.Runtime.Lifecycle` per SSH channel
(`lib/foglet_bbs/ssh/cli_handler.ex:185`). The Lifecycle process itself was
recently fixed to allow concurrent instances (`name: nil` override at
`cli_handler.ex:191`), but every concurrent Lifecycle still tries to start
**five named singletons** in `Initializer.initialize_all/2`. The first one to
hit a collision is the PluginManager (currently failing the regression test);
once it's adopted, the next blocker is the Dispatcher, then the
ProcessComponent DynamicSupervisor (during render), then the dev-only
CodeReloader, time-travel, and cycle-profiler servers.

Of those five children, **none is genuinely singleton-by-design for
multi-tenant SSH use**. They are all "singleton-by-accident": registered with
`name: __MODULE__` and called via `GenServer.call(__MODULE__, ...)` from
within the Lifecycle's own subtree. Every client of these processes already
has access to a per-Lifecycle PID through the Lifecycle state, so the named
registration is not actually load-bearing — it's a default that was never
audited for multi-tenant use.

**Primary recommendation:** Adopt-existing pattern at the Initializer (Option
A in PROPOSAL.md), applied to PluginManager **and** Dispatcher. This is the
minimum viable patch and matches the existing pattern Raxol already uses for
`:agent`/`:liveview` environments (`initializer.ex:115-116, 211`). Extend the
`:ssh` environment to receive the same treatment those environments get.

---

## Reproduction status

| Step | Status | Anchor |
|------|--------|--------|
| Lifecycle name collision (Bottleneck #1) | Fixed | `cli_handler.ex:191` (`name: nil`), `lifecycle.ex:82-87` |
| PluginManager collision (Bottleneck #2) | Confirmed by failing test | `concurrent_lifecycle_test.exs`, `initializer.ex:118-131`, `plugin_lifecycle.ex:65-67` |
| Dispatcher collision (Bottleneck #3) | Predicted, not yet hit | `dispatcher.ex:48-63`, `initializer.ex:208-217` |
| Resolve at render: ProcessComponent under `Raxol.DynamicSupervisor` | Tolerated by code, but global | `engine.ex:462-468` |
| CodeReloader (`:dev` only) | Singleton, dev-only | `code_reloader.ex:18-19, 26` |
| TimeTravel/CycleProfiler (opt-in only) | Singleton, opt-in only | `time_travel.ex:50-54`, `cycle_profiler.ex:70-74` |

The current test fails at PluginManager because that's the first child started
after the registry table; the table itself is per-app-module and doesn't
collide.

---

## Per-Lifecycle process audit

The startup sequence is `Lifecycle.init/1` → `Initializer.initialize_all/2`
(`lifecycle.ex:118`, `initializer.ex:18-29`):

1. `initialize_registry_table/1` (`initializer.ex:96-113`)
2. `start_plugin_manager/2` (`initializer.ex:115-132`)
3. `initialize_app_model/2` (no process)
4. `start_dispatcher/5` (`initializer.ex:186-224`)
5. `maybe_start_driver/3` (returns `{:ok, nil}` for `:ssh` — `initializer.ex:230`)
6. `start_rendering_engine/3` (`initializer.ex:257-291`)
7. From `Lifecycle.build_initial_state/8` → `maybe_start_code_reloader/1` (`lifecycle.ex:158`, `initializer.ex:56-72`)
8. From `Lifecycle.init/1` → `maybe_start_time_travel/1` and `maybe_start_cycle_profiler/1` (`lifecycle.ex:115-116, 422-494`)

Plus children started lazily from inside the per-Lifecycle pipeline:

9. `Raxol.DynamicSupervisor` children: `ProcessComponent` instances, started during render (`engine.ex:462-468`).

### Classification

| # | Process | Started at | Name registration | Logical scope | Classification |
|---|---------|-----------|-------------------|---------------|----------------|
| 1 | **CommandRegistry ETS table** | `initializer.ex:96-113` | `:ets.new(Module.concat(CommandRegistryTable, app_module), :named_table)` (`initializer.ex:97-105`) | Per-app-module | **Per-Lifecycle is fine in practice** — same app module across Lifecycles writes to the same protected table; `ensure_table` is idempotent. Not a collision source today (every Foglet SSH session uses `Foglet.TUI.App`, so the table is shared). Reads via `:ets.lookup` are safe; concurrent writes during plugin command registration could race if plugins differ per-session, but Foglet's plugins don't. Acceptable as-is. |
| 2 | **`PluginManager`** facade — really `PluginRegistry.init/0` (ETS) + `PluginLifecycle.start_link/1` (GenServer) | `plugin_manager.ex:66-72` | `PluginLifecycle.start_link` registers `name: __MODULE__` (`plugin_lifecycle.ex:65-67`); all client calls hit `GenServer.call(__MODULE__, ...)` (`plugin_lifecycle.ex:76, 84, 92, ...`) | Per-Lifecycle (each Lifecycle holds `pm_pid` in its state at `lifecycle.ex:172`; `Dispatcher.apply_plugin_filters/2` calls the manager via the pid stored on its own state at `dispatcher.ex:621-631`) | **Accidentally global.** All clients route via state-held pid, the `__MODULE__` registration is never actually used by the runtime (it's only used by external callers like REPL helpers). The plugin **registry** ETS tables (`:raxol_plugin_registry`, `:raxol_plugin_commands` — `plugin_registry.ex:31-32, 55-79`) are inherently global, but they tolerate concurrent writes; the **lifecycle GenServer** is the actual collision point. |
| 3 | **`Dispatcher`** | `initializer.ex:213-217` via `Dispatcher.start_link(self(), state, dispatcher_opts)` | Defaults to `name: __MODULE__` at `dispatcher.ex:53` unless `:name` opt provided. `dispatcher_opts` is `[name: nil]` only for `:agent`/`:liveview` (`initializer.ex:210-211`) — **`:ssh` is not in that list, so SSH gets the default `name: Raxol.Core.Runtime.Events.Dispatcher`**. | Per-Lifecycle (Lifecycle stores `dispatcher_pid` at `lifecycle.ex:175` and CLIHandler routes events through the pid at `cli_handler.ex:432-434`). | **Accidentally global.** Once PluginManager is fixed, this is the **next blocker** — second concurrent SSH session will get `{:error, {:already_started, _}}` from Dispatcher at `initializer.ex:222`. The pattern matching for the error already exists in the with-chain (`initializer.ex:218-223`) but only converts to `{:error, ...}` and doesn't adopt. |
| 4 | **Terminal Driver** | `initializer.ex:233-254` | N/A — for `:ssh` environment, `maybe_start_driver/3` returns `{:ok, nil}` immediately (`initializer.ex:230`). | N/A | **Per-Lifecycle pid-only (irrelevant for SSH).** Not started for SSH at all. |
| 5 | **`Rendering.Engine`** | `initializer.ex:275-289` via `Engine.start_link(engine_opts)` (keyword list) | `Engine.start_link/1` (list overload) calls `split_server_opts(opts)` (`engine.ex:60-66`, `genserver_helpers.ex:138-160`) which pulls `:name` out of opts. `engine_opts` is built at `initializer.ex:260-273` and **never includes `:name`**, so server_opts is `[]` → no name registration. The `start_link/1` map overload (`engine.ex:54-58`) **does** force `name: __MODULE__`, but Initializer never goes through that path; only `Raxol.Core.Runtime.Supervisor.init/1:65-72` does (used by `Raxol.Application`, not by Lifecycle). | Per-Lifecycle | **Per-Lifecycle pid-only — already correct.** (Confirm: pid is stored in Lifecycle state at `lifecycle.ex:177` and addressed by pid-only at `lifecycle.ex:213-214`.) |
| 6 | **`CodeReloader`** | `lifecycle.ex:158` → `initializer.ex:57-71` | `name: __MODULE__` (`code_reloader.ex:19`) **and** the `FileSystem` watcher it spawns is named `:code_reloader_watcher` (`code_reloader.ex:24-26`). Both are singletons. | Per-Lifecycle in spirit, but inherently dev-only | **Accidentally global, but only matters in `:dev` env.** Foglet runs in `:prod` for real connections; `Mix.env() == :dev` guard means this never fires for production users. Still a hazard for local two-window development. |
| 7 | **`TimeTravel`** | `lifecycle.ex:115, 422-452` | `name: __MODULE__` default; can be overridden via opts (`time_travel.ex:50-54`) | Per-Lifecycle | **Accidentally global, but opt-in.** Only started when `time_travel: true` is passed to `Lifecycle.start_link/2` — Foglet doesn't pass it. Not a runtime hazard today. |
| 8 | **`CycleProfiler`** | `lifecycle.ex:116, 469-494` | Same pattern as TimeTravel: `name: __MODULE__` default, override-able (`cycle_profiler.ex:70-74`) | Per-Lifecycle | **Accidentally global, but opt-in.** Only started when `profiler: true`. Not a hazard. |
| 9 | **`ProcessComponent`** instances under `Raxol.DynamicSupervisor` | `engine.ex:462-470` during render | DynamicSupervisor name `Raxol.DynamicSupervisor` is global; child IDs are `"pc-#{inspect(mod)}"` derived per process_component node. | DynamicSupervisor itself is global; children are keyed by component id. | **Tolerated.** `engine.ex:467` already adopts `{:error, {:already_started, pid}} -> pid`, so concurrent Lifecycles share live ProcessComponents by id. This works as-is **iff** Foglet's screens don't expect per-session ProcessComponent state — needs to be confirmed with TUI authors. Foglet's current screens use stateless widgets (per `AGENTS.md` and `lib/foglet_bbs/tui/widgets/README.md`); ProcessComponents are not used. |
| 10 | **Other ETS / global state encountered during render** | various | `:raxol_plugin_registry` and `:raxol_plugin_commands` (`plugin_registry.ex:31-32`); `:raxol_event_subscriptions` Registry (`dispatcher.ex:23`); `Raxol.Core.FocusManager.FocusServer` (queried via `Process.whereis` at `dispatcher.ex:759`); `Raxol.Core.UserPreferences` | Application-global by intent | **Singleton-by-design — irrelevant.** These are intentionally per-VM and read-mostly or per-Lifecycle-conditional. Leave alone. |

### What this means for the immediate bug

After the Lifecycle name fix, exactly **two** children block concurrent SSH
sessions in production:

1. **`PluginLifecycle`** GenServer (rows 2 above)
2. **`Dispatcher`** GenServer (row 3 above)

Both are clients-via-pid in the runtime's actual call paths, so making them
non-singleton is safe. The CodeReloader (row 6) is a dev-mode hazard; the
others are inert under Foglet's current configuration.

---

## Why the PluginManager case is interesting

Reading `PluginLifecycle` (`plugin_lifecycle.ex:62-184`) reveals that **every
public function in the GenServer API hardcodes `__MODULE__` as the target**:

```elixir
def load(plugin_id, module, config \\ %{}) do
  GenServer.call(__MODULE__, {:load, plugin_id, module, config})
end
```

So even if Initializer adopts the existing pid, the existing pid is the
*first* Lifecycle's plugin manager — every subsequent Lifecycle's plugin
operations would route through the first session's process. That's actually
**fine for Foglet right now** because:

- Foglet doesn't load plugins dynamically (`grep -r "PluginManager.load_plugin" lib/` returns nothing).
- `Dispatcher.apply_plugin_filters/2` (`dispatcher.ex:621-631`) is the only hot path that touches the plugin manager during normal operation, and it uses `state.plugin_manager` (a stored pid), not `__MODULE__`. So if all Lifecycles share the same plugin manager pid, they all route filters through it, and since no plugins are loaded, the filter chain is a passthrough (`plugin_lifecycle.ex:222-229`: `if map_size(state.plugin_configs) == 0, do: {:reply, {:ok, event}, state}`).
- The `__MODULE__`-hardcoded API is invoked only by hypothetical plugin-management UIs that don't exist in Foglet.

**Verdict:** Adopting the existing PluginManager pid is safe for Foglet
today. If Foglet ever adds per-session plugins, it'll need a different
strategy (per-session plugin namespace, or upstream patch — see PROPOSAL.md
Option C).

---

## Why the Dispatcher case is different

The Dispatcher is **not** addressed via `__MODULE__` from anywhere in the
runtime hot path. Every caller (`engine.ex:103, 155`, `dispatcher.ex:621`,
`cli_handler.ex:432-433`) uses an explicit pid stored in another process's
state. Therefore making Dispatcher non-singleton is even safer than for
PluginManager — there are zero callers to worry about.

The fix is one line: extend the env list at `initializer.ex:210-211`:

```elixir
dispatcher_opts =
  if environment in [:agent, :liveview, :ssh], do: [name: nil], else: []
```

Or — more honestly — drop the env check entirely and always use
`[name: nil]`, since the runtime never relies on the registered name. (This
is what we'd propose upstream.)

---

## Existing test exercises only the surface

`test/foglet_bbs/ssh/concurrent_lifecycle_test.exs` (39 lines) currently:

- Asserts two `start_link`s for the same app module return distinct alive pids.
- Does **not** dispatch any input events to either Lifecycle.
- Does **not** trigger a render.
- Does **not** clean up — both Lifecycles leak across tests; on a second run, the global `Raxol.Core.FocusManager.FocusServer`, `:raxol_plugin_registry` ETS, and the unattended PluginLifecycle GenServer (when adopted) accumulate state.

We need a test that:

1. Boots two Lifecycles.
2. Casts a synthetic `:resize` and a `:key` event into each Dispatcher.
3. Forces a synchronous render via `GenServer.call(engine_pid, :render_frame_sync)` (`engine.ex:154`) to verify each Lifecycle's view pipeline runs without colliding.
4. Stops both Lifecycles via `Raxol.Core.Runtime.Lifecycle.stop/1` (`lifecycle.ex:99-101`), waits for them to terminate (monitor + receive), and asserts subsequent `start_link`s succeed (catches teardown leakage).
5. Runs twice in the same `mix test` invocation by leveraging `setup` to reset shared state where possible.

Test detail goes in PROPOSAL.md.

---

## Upstream Raxol — provenance and known-issue search

| Question | Answer | Anchor |
|----------|--------|--------|
| Where does Raxol live? | Repo: `https://github.com/DROOdotFOO/raxol`. Vendored at `vendor/raxol/`. Hex package name: `raxol` v2.4.0. The plugin code path used by Foglet is from `deps/raxol_core/` (`raxol_core` v2.4.0, same source repo, packaged as a separate Hex package). | `vendor/raxol/mix.exs:4-6, 25-27, 380-385`; `deps/raxol_core/mix.exs:4-6, 18-19` |
| Is `vendor/raxol` a fork or a vanilla pin? | Per AGENTS.md ("`vendor/raxol/` is vendored") and `mix.exs:64` (`{:raxol, path: "vendor/raxol"}`), it's a vendored copy. We did not check the diff vs. upstream `v2.4.0`; some Foglet-specific patches may already exist (e.g., the `:ssh` environment branches in `dispatcher.ex:211` and `engine.ex:434` look upstream-original, not Foglet additions). | — |
| Is concurrent multi-session a documented use case? | **No.** `vendor/raxol/CHANGELOG.md` mentions "concurrent" only in the context of test suites (lines 680, 1287, 1647) and damage tracking, never multi-session. The cookbook directory `vendor/raxol/docs/cookbook/` is empty in our checkout (despite being referenced in the docs config), so there's no `SSH_DEPLOYMENT.md` to consult. The `mix.exs` description boasts "SSH serving" (`vendor/raxol/mix.exs:367-369`), but the runtime architecture clearly assumes one app instance per VM. | `vendor/raxol/CHANGELOG.md`; `vendor/raxol/mix.exs:367-369` |
| Is this a Foglet misuse or a Raxol design gap? | **Mixed, but leaning Raxol design gap.** Raxol's runtime supports a `:ssh` environment branch (`dispatcher.ex:211`, `engine.ex:434`, `lifecycle.ex:324-328`) — i.e., it explicitly contemplates SSH as a deployment mode. The runtime also already has `:agent` and `:liveview` branches that pass `[name: nil]` for the Dispatcher (`initializer.ex:210-211`) precisely because those environments are multi-instance. **`:ssh` should have the same treatment and doesn't.** That's a real upstream bug, not a Foglet misuse. The PluginManager `__MODULE__` hardcoding is a deeper architectural decision and a closer call — but at minimum, the Initializer should adopt-existing rather than fail. | `initializer.ex:115-131, 210-211`; `lifecycle.ex:82-87, 324-328` |

**Filing recommendation:** Yes, worth filing on `DROOdotFOO/raxol` as two
separate concerns:

1. (Bug) `:ssh` environment is missing from the multi-instance Dispatcher branch — drop-in one-line fix.
2. (Design discussion) PluginManager / PluginLifecycle hardcodes `__MODULE__` and breaks when Lifecycle is non-singleton — needs design input from upstream maintainers about whether plugins are meant to be VM-global or per-app-instance.

Draft issue body lives in PROPOSAL.md.

---

## Open questions

1. **Is Raxol's vendored copy already patched vs. upstream v2.4.0?** We didn't run `git log vendor/raxol/` or diff against the tagged upstream. If it is patched, our PROPOSAL diffs may collide with existing local changes. Recommendation: run `git -C vendor/raxol log --oneline -20` (or the equivalent for the vendoring scheme used) before applying.
2. **Does Foglet ever plan per-session plugins?** If yes, the PluginManager singleton-by-design assumption breaks and Option C (per-Lifecycle namespacing) becomes mandatory. Today Foglet has zero plugins, so Option A is fine.
3. **Is the empty `vendor/raxol/docs/cookbook/` directory a stripped vendor artifact, or is upstream like that too?** Worth a quick check before filing the upstream issue, to make sure we don't reference docs that don't exist on GitHub either.

---

## Sources

All claims above are anchored to the following files (HIGH confidence):

- `lib/foglet_bbs/ssh/cli_handler.ex` (the caller of `Lifecycle.start_link`)
- `vendor/raxol/lib/raxol/core/runtime/lifecycle.ex`
- `vendor/raxol/lib/raxol/core/runtime/lifecycle/initializer.ex`
- `vendor/raxol/lib/raxol/core/runtime/runtime_supervisor.ex` (used by `Raxol.Application`, not by Lifecycle — proves rendering Engine has two start paths)
- `vendor/raxol/lib/raxol/core/runtime/events/dispatcher.ex`
- `vendor/raxol/lib/raxol/core/runtime/rendering/engine.ex`
- `vendor/raxol/lib/raxol/dev/code_reloader.ex`
- `vendor/raxol/lib/raxol/debug/time_travel.ex`
- `vendor/raxol/lib/raxol/performance/cycle_profiler.ex`
- `deps/raxol_core/lib/raxol/core/runtime/plugins/plugin_manager.ex`
- `deps/raxol_core/lib/raxol/core/runtime/plugins/plugin_lifecycle.ex`
- `deps/raxol_core/lib/raxol/core/runtime/plugins/plugin_registry.ex`
- `deps/raxol_core/lib/raxol/core/runtime/plugins/plugin_supervisor.ex`
- `deps/raxol_core/lib/raxol/core/runtime/plugins/state_manager.ex`
- `deps/raxol_core/lib/raxol/core/utils/genserver_helpers.ex`
- `mix.exs`, `vendor/raxol/mix.exs`, `deps/raxol_core/mix.exs` (provenance)
- `test/foglet_bbs/ssh/concurrent_lifecycle_test.exs` (current failing regression)
- `vendor/raxol/CHANGELOG.md` (negative result: no documented multi-session support)
