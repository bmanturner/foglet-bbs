---
phase: 42-app-runtime-helper-extraction
reviewed: 2026-04-29T22:34:53Z
depth: standard
files_reviewed: 11
files_reviewed_list:
  - lib/foglet_bbs/tui/app.ex
  - lib/foglet_bbs/tui/app/routing.ex
  - lib/foglet_bbs/tui/app/modal.ex
  - lib/foglet_bbs/tui/app/effects.ex
  - lib/foglet_bbs/tui/app/subscriptions.ex
  - test/foglet_bbs/tui/app/routing_test.exs
  - test/foglet_bbs/tui/app/modal_test.exs
  - test/foglet_bbs/tui/app/effects_test.exs
  - test/foglet_bbs/tui/app/subscriptions_test.exs
  - test/foglet_bbs/tui/app_runtime_contract_test.exs
  - test/foglet_bbs/tui/app_test.exs
findings:
  critical: 0
  warning: 1
  info: 0
  total: 1
status: issues_found
---

# Phase 42: Code Review Report

**Reviewed:** 2026-04-29T22:34:53Z
**Depth:** standard
**Files Reviewed:** 11
**Status:** issues_found

## Summary

Reviewed the App runtime helper extraction across routing, modal handling, effect interpretation, subscriptions, and the matching contract/unit tests. The extraction mostly preserves the previous behavior, but the new routing helper drops the prior graceful recovery path for unknown screen atoms. That turns corrupted route state, future enum drift, or missing custom route wiring into a blank inert TUI instead of a recoverable MainMenu fallback.

## Warnings

### WR-01: Unknown Screen Routes Now Render Blank And Ignore Input

**File:** `lib/foglet_bbs/tui/app/routing.ex:154`
**Issue:** `screen_module_for/2` now returns `maybe_known_screen_module(screen)` for non-loadable overrides and normal resolution. `maybe_known_screen_module/1` returns `nil` for unknown atoms, so `render_screen/1` falls through to `text("")` and `route_screen_update/3` returns `{state, []}`. Before this extraction, the fallback clause logged an error and returned `Screens.MainMenu`, keeping the SSH TUI usable if `current_screen` was corrupted, a future screen enum was missed in the resolver, or a domain override route was incomplete. This is a runtime behavior regression and the new tests only cover the built-in fallback for a bad `:main_menu` override, not the unknown-screen path.
**Fix:** Restore an explicit unknown-screen fallback in the extracted resolver and add a regression test for both render and key routing:

```elixir
defp maybe_known_screen_module(screen) do
  if screen in known_screens() do
    built_in_screen_module_for(screen)
  else
    require Logger

    Logger.error(
      "[TUI.App.Routing] no screen module for #{inspect(screen)}; falling back to :main_menu"
    )

    Screens.MainMenu
  end
end
```

---

_Reviewed: 2026-04-29T22:34:53Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
