---
phase: 07-oneliners-and-main-menu-social-strip
reviewed: 2026-04-24T03:33:00Z
depth: standard
files_reviewed: 17
files_reviewed_list:
  - lib/foglet_bbs/oneliners.ex
  - lib/foglet_bbs/oneliners/entry.ex
  - lib/foglet_bbs/tui/app.ex
  - lib/foglet_bbs/tui/modal.ex
  - lib/foglet_bbs/tui/screens/domain.ex
  - lib/foglet_bbs/tui/screens/main_menu.ex
  - lib/foglet_bbs/tui/widgets/chrome/clock_formatter.ex
  - lib/foglet_bbs/tui/widgets/chrome/status_bar.ex
  - lib/foglet_bbs/tui/widgets/modal.ex
  - lib/foglet_bbs/tui/widgets/modal/form.ex
  - priv/repo/migrations/20260424024644_create_oneliners.exs
  - test/foglet_bbs/oneliners/oneliners_test.exs
  - test/foglet_bbs/tui/app_test.exs
  - test/foglet_bbs/tui/layout_smoke_test.exs
  - test/foglet_bbs/tui/screens/main_menu_test.exs
  - test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs
  - test/support/fake_oneliners.ex
findings:
  critical: 0
  warning: 1
  info: 0
  total: 1
status: issues_found
---

# Phase 07: Code Review Report

**Reviewed:** 2026-04-24T03:33:00Z
**Depth:** standard
**Files Reviewed:** 17
**Status:** issues_found

## Summary

Reviewed the Phase 07 oneliner persistence, main-menu social strip, modal form flow, chrome clock/status updates, migration, and focused test support. The persistence boundary and TUI submit/refresh path are generally well-scoped, but authenticated startup currently reaches the main menu without scheduling the initial oneliner load, so persisted oneliners can be hidden behind the empty-state until another navigation or post path reloads them.

## Warnings

### WR-01: Authenticated Startup Does Not Load Recent Oneliners

**File:** `lib/foglet_bbs/tui/app.ex:104`
**Issue:** `init/1` sets authenticated users directly to `:main_menu` and returns `{:ok, state}` without queuing `{:load_oneliners}`. The later `:navigate`, `:set_user`, `:promote_session`, and successful submit paths do queue that load, but the normal already-authenticated session startup path does not. That means `recent_oneliners` remains the struct default `[]`, so the main menu can show "No oneliners yet." even when persisted visible oneliners exist.
**Fix:** Add an initial-load path for authenticated main-menu startup. One concrete option is to make `init/1` return a state plus a command when `user` is present, using the same task construction as `{:load_oneliners}`. If the current Raxol lifecycle path cannot consume app init commands safely, add a one-shot startup message/subscription or lifecycle support before relying on it, and cover it with a test that `App.init/1` for an authenticated user results in a queued oneliner load before the first main-menu render.

```elixir
# Sketch only: reuse the existing load_oneliners task construction.
state = %__MODULE__{...}

if user do
  do_update({:load_oneliners}, state)
else
  {:ok, state}
end
```

---

_Reviewed: 2026-04-24T03:33:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
