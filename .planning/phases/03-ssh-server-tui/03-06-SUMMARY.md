---
phase: 03-ssh-server-tui
plan: "06"
subsystem: tui-app-routing
tags: [gap-closure, tui, ssh, modal, async, resize]
dependency_graph:
  requires: []
  provides:
    - modal-intercept-guard
    - command-result-re-dispatcher
    - resize-event-routing
  affects:
    - lib/foglet_bbs/tui/app.ex
    - lib/foglet_bbs/ssh/cli_handler.ex
tech_stack:
  added: []
  patterns:
    - modal intercept guard before screen dispatch
    - command_result re-dispatch pattern
    - Raxol Event.new(:resize,...) for system event routing
key_files:
  created: []
  modified:
    - lib/foglet_bbs/tui/app.ex
    - lib/foglet_bbs/ssh/cli_handler.ex
    - test/foglet_bbs/tui/app_test.exs
decisions:
  - "Modal intercept guard in do_update({:key,...}) checks state.modal != nil before delegating to screen module — screens never see keys while a modal is open"
  - "command_result re-dispatcher placed immediately before catch-all to unwrap Raxol Command.task runtime envelope"
  - "Event.new(:resize,...) used instead of Event.window/3 so Raxol Dispatcher routes to handle_resize_event/2 which updates the Rendering Engine dimensions"
metrics:
  duration: "~8 minutes"
  completed: "2026-04-19T16:06:35Z"
  tasks_completed: 2
  files_modified: 3
---

# Phase 03 Plan 06: UAT Gap Closure — Modal Intercept, Command Result Dispatcher, Resize Event Summary

**One-liner:** Modal intercept guard in `do_update({:key,...})` + `{:command_result, inner}` re-dispatcher + `Event.new(:resize,...)` fix closes three UAT-blocking gaps in app routing and SSH event translation.

## What Was Built

Three targeted fixes to `app.ex` and `cli_handler.ex` that restore board browsing (Gap 5), fix terminal resize (Gap 6), and fix modal dismiss on Enter while login form is active (Gap 4).

### Task 1: Modal Intercept Guard + command_result Dispatcher (TDD)

**Gap 4 fix:** `do_update({:key, key_event}, state)` now checks `state.modal != nil` first. When a modal is active, all keys route directly to `global_key_handler/2`, which contains all modal dismiss/confirm logic. Previously, the screen module's `handle_key/2` was called unconditionally — Login's `handle_form_key/2` matched `:enter` when `sub` is `:login_form` and `focused_field` is `:password`, calling `submit_login/1` silently without checking `state.modal`. The suspended-account modal could never be dismissed with Enter.

**Gap 5 fix:** Added `do_update({:command_result, inner}, state)` clause immediately before the catch-all. Raxol's `Command.task` runtime wraps every task return value in `{:command_result, inner}` before delivering to `update/2`. Without this clause, all async results (`boards_loaded`, `threads_loaded`, `posts_loaded`, `read_pointers_flushed`) hit the catch-all and were discarded, leaving the Board List permanently on "Loading...".

**Tests added (TDD RED → GREEN):**
- `describe "modal intercept guard (Gap 4)"` — 2 tests covering Enter and Escape dismissal while login form in `:login_form` sub-state
- `describe "command_result dispatcher (Gap 5)"` — 4 tests covering `boards_loaded`, `threads_loaded`, `posts_loaded`, and unknown inner tuples

### Task 2: SSH window_change Emits :resize Event (Gap 6)

`cli_handler.ex` `handle_ssh_msg/2` for `:window_change` changed from:
```elixir
event = Raxol.Core.Events.Event.window(width, height, :resize)
```
to:
```elixir
event = Raxol.Core.Events.Event.new(:resize, %{width: width, height: height})
```

`Event.window/3` produces `type: :window` which is NOT in Raxol's `system_event?/1` allowlist, so it went to the app `update/2` path and `normalize_message/1` converted it to `{:window_change, w, h}` — updating `state.terminal_size` but NOT the Rendering Engine's internal dimensions. `Event.new(:resize,...)` produces `type: :resize` which IS in the allowlist, so Dispatcher routes it to `handle_resize_event/2` which sends `{:update_size,...}` to the Rendering Engine.

## Verification

```
mix test test/foglet_bbs/tui/app_test.exs  → 56 tests, 0 failures
mix test test/foglet_bbs/tui/            → 207 tests, 0 failures
mix precommit                            → 0 failures, 0 warnings, dialyzer passed
```

## Deviations from Plan

None — plan executed exactly as written. The formatter (`mix precommit` runs `mix format`) inserted one blank line after an `assert` call in `app_test.exs`, committed separately as a style fix.

## Known Stubs

None. All three fixes wire real behavior — no placeholders or hardcoded empty values introduced.

## Threat Flags

None. No new network endpoints, auth paths, file access patterns, or schema changes introduced. The `command_result` re-dispatcher's inner tuple originates from our own `Command.task` closures (T-03-gc2-01 accepted). The modal intercept guard enforces T-03-gc2-03 mitigation — modal keys can no longer be consumed silently by screen handlers.

## Self-Check: PASSED

- FOUND: lib/foglet_bbs/tui/app.ex
- FOUND: lib/foglet_bbs/ssh/cli_handler.ex
- FOUND: test/foglet_bbs/tui/app_test.exs
- FOUND commit: bc2f17d (feat: modal intercept + command_result)
- FOUND commit: 01a0d4a (fix: resize event type)
- FOUND commit: f694711 (style: formatter fix)
