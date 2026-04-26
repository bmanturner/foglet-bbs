---
id: 260426-jbn
description: Fix global one-connection-at-a-time bottleneck in SSH/Raxol stack
status: complete
date: 2026-04-26
---

# Quick Task 260426-jbn — Summary

## Problem

Foglet BBS only allowed one active SSH connection at a time globally. Every additional concurrent SSH session crashed during channel setup, manifesting as "the application only allows one active connection." Per-user session enforcement (`Foglet.Sessions.Supervisor` + `Registry`) was correct; the bottleneck was upstream in Raxol.

## Root cause (chain of three)

1. **Lifecycle** — `Raxol.Core.Runtime.Lifecycle.start_link/2` derives a globally-registered name from the app module unless the caller passes `:name` (`vendor/raxol/lib/raxol/core/runtime/lifecycle.ex:82-87`). Second concurrent `start_link` returned `{:error, {:already_started, _}}`; `cli_handler.ex` did `{:ok, _} = ...` and crashed.
2. **Dispatcher** — `Lifecycle.Initializer.start_dispatcher/5` registered `name: __MODULE__` for every environment except `:agent` and `:liveview`. `:ssh` was not in the list, so the Dispatcher collided on the second Lifecycle.
3. **PluginLifecycle** — singleton-by-design (`name: __MODULE__`, all client calls via `GenServer.call(__MODULE__, ...)`), but `Initializer.start_plugin_manager/2` aborted Lifecycle init on `{:already_started, _}` instead of adopting the existing pid.

Diagnosis was reproduced with a 20-line script before any fix went in.

## Fix

**`vendor/raxol/lib/raxol/core/runtime/lifecycle/initializer.ex`:**

- `start_dispatcher/5` — added `:ssh` to the `[:agent, :liveview]` unnamed-Dispatcher list. Each Lifecycle now gets its own per-session Dispatcher with isolated model state.
- `start_plugin_manager/2` — handles `{:error, {:already_started, pm_pid}}` by adopting the pid. Safe because Foglet has no plugins; PluginLifecycle's hot path is a passthrough.

**`lib/foglet_bbs/ssh/cli_handler.ex`:**

- Pass `name: nil` to `Raxol.Core.Runtime.Lifecycle.start_link/2`. Functionally redundant after the upstream Dispatcher fix but cheap defense against vendor regression.

**`test/foglet_bbs/ssh/concurrent_lifecycle_test.exs`:** new regression test (`use FogletBbs.DataCase, async: false`). Two tests:

- Two concurrent `:ssh` Lifecycles get distinct Lifecycle/Dispatcher/RenderingEngine pids.
- Cross-dispatched `:resize` events stay isolated per Dispatcher (per-session model state).

`mix test test/foglet_bbs/ssh/concurrent_lifecycle_test.exs` — 2 tests, 0 failures.

## Upstream

Two issues filed at `https://github.com/DROOdotFOO/raxol`:

- **#228** — Dispatcher one-liner. PR-ready; Raxol advertises SSH serving and the existing `:agent`/`:liveview` branches handle the same case identically.
- **#229** — PluginLifecycle design question. Confirm whether plugins are VM-global (likely) or per-Lifecycle before sending the adopt-existing patch.

## Risks / follow-ups

- `vendor/raxol` patch will be lost on next vendor update. Filed upstream issues are the long-term mitigation. If we update raxol before they merge, re-apply by hand and re-run `concurrent_lifecycle_test.exs`.
- CodeReloader / TimeTravel / CycleProfiler also accidentally global per the audit but inert under Foglet's current config — not patched.
- `cli_handler.ex` now has `name: nil` that is redundant given the upstream Dispatcher fix; left in place as defense-in-depth.

## Files

- `260426-jbn-RESEARCH.md` — audit of every per-Lifecycle process.
- `260426-jbn-PROPOSAL.md` — option comparison, diffs, test plan, risk register, upstream issue drafts.
