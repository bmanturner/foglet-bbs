---
id: 260426-jbn
description: Fix global one-connection-at-a-time bottleneck in SSH/Raxol stack
status: complete
---

# Quick Task 260426-jbn — Concurrent SSH connections

## Goal

Foglet BBS only allowed one active SSH connection at a time globally; every additional concurrent session crashed during channel setup. Restore concurrent connections (one session per user, many users).

## Plan

1. Diagnose root cause — confirm by reproduction, not inference. (See RESEARCH.md.)
2. Patch `vendor/raxol/lib/raxol/core/runtime/lifecycle/initializer.ex`:
   - `start_dispatcher/5` — include `:ssh` in the unnamed-Dispatcher branch.
   - `start_plugin_manager/2` — adopt existing pid on `{:already_started, _}` (PluginLifecycle is a VM singleton by design).
3. Pass `name: nil` to `Lifecycle.start_link` from `lib/foglet_bbs/ssh/cli_handler.ex` (defensive; redundant after the upstream Dispatcher fix but cheap insurance).
4. Add `test/foglet_bbs/ssh/concurrent_lifecycle_test.exs` — assert distinct Lifecycle/Dispatcher/Engine pids and per-session resize state isolation.
5. File two upstream issues at `DROOdotFOO/raxol`.

## Artifacts

- `260426-jbn-RESEARCH.md` — full audit of every per-Lifecycle process.
- `260426-jbn-PROPOSAL.md` — option comparison, diffs, test plan, risk register, upstream-issue drafts.
- `260426-jbn-SUMMARY.md` — what shipped.
