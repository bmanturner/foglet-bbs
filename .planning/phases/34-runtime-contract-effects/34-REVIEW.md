---
phase: 34-runtime-contract-effects
reviewed: 2026-04-28T18:58:57Z
depth: standard
files_reviewed: 10
files_reviewed_list:
  - docs/ARCHITECTURE.md
  - lib/foglet_bbs/tui/app.ex
  - lib/foglet_bbs/tui/context.ex
  - lib/foglet_bbs/tui/effect.ex
  - lib/foglet_bbs/tui/screen.ex
  - test/foglet_bbs/tui/app_runtime_contract_test.exs
  - test/foglet_bbs/tui/app_test.exs
  - test/foglet_bbs/tui/context_test.exs
  - test/foglet_bbs/tui/effect_test.exs
  - test/foglet_bbs/tui/screen_test.exs
findings:
  critical: 0
  warning: 1
  info: 0
  total: 1
status: issues_found
---

# Phase 34: Code Review Report

**Reviewed:** 2026-04-28T18:58:57Z
**Depth:** standard
**Files Reviewed:** 10
**Status:** issues_found

## Summary

Reviewed the Phase 34 runtime context, effect, screen behaviour, App dispatcher changes, architecture note, and focused tests. The generic effect path is mostly well-covered, but the new-contract dispatcher has a migration trap: any screen that temporarily keeps legacy callbacks while adding the new callbacks will be treated as legacy for key and render routing.

## Warnings

### WR-01: Hybrid New-Contract Screens Silently Bypass New Routing

**File:** `lib/foglet_bbs/tui/app.ex:1308`

**Issue:** `new_contract_screen?/2` only routes key events through `update/3` when a module exports `update/3` and does not export legacy `handle_key/2`; `render_screen/1` similarly calls `render/2` only when `render/1` is absent. That makes a screen implementing both contracts during a staged migration compile successfully but silently continue using the legacy App-wide path, so new reducer effects and local-state rendering will not run until the old callbacks are removed in the same change. The behaviour in `Foglet.TUI.Screen` declares both callback families as optional transitional callbacks, so this is an easy footgun for the deferred phases 35-38 migrations.

**Fix:** Prefer the new callbacks whenever the screen has initialized new local state, or mark migrated screens explicitly instead of using absence of legacy callbacks as the signal. For example:

```elixir
defp new_contract_screen?(%__MODULE__{} = state, screen) do
  key = screen_key(screen)
  module = screen_module_for(state, key)

  function_exported?(module, :update, 3) and Map.has_key?(state.screen_state || %{}, key)
end

defp render_screen(state) do
  key = screen_key(current_route(state))
  module = screen_module_for(state, key)

  if function_exported?(module, :render, 2) and Map.has_key?(state.screen_state || %{}, key) do
    module.render(screen_state_for(state, key), context_for_screen_key(state, key))
  else
    screen_module_for(state.current_screen).render(state)
  end
end
```

Add a regression test with a sample screen that exports `init/1`, `update/3`, `render/2`, and legacy `handle_key/2`/`render/1`; after `Effect.navigate/2`, key events and `App.view/1` should use the new-contract callbacks.

---

_Reviewed: 2026-04-28T18:58:57Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
