---
phase: 43-large-screen-decomposition
reviewed: 2026-04-29T23:59:15Z
depth: standard
files_reviewed: 20
files_reviewed_list:
  - lib/foglet_bbs/tui/SCREEN_CONTRACT.md
  - lib/foglet_bbs/tui/screens/account.ex
  - lib/foglet_bbs/tui/screens/account/render.ex
  - lib/foglet_bbs/tui/screens/login.ex
  - lib/foglet_bbs/tui/screens/login/render.ex
  - lib/foglet_bbs/tui/screens/main_menu.ex
  - lib/foglet_bbs/tui/screens/main_menu/render.ex
  - lib/foglet_bbs/tui/screens/new_thread.ex
  - lib/foglet_bbs/tui/screens/new_thread/render.ex
  - lib/foglet_bbs/tui/screens/post_reader.ex
  - lib/foglet_bbs/tui/screens/post_reader/render.ex
  - lib/foglet_bbs/tui/screens/sysop.ex
  - lib/foglet_bbs/tui/screens/sysop/render.ex
  - test/foglet_bbs/tui/layout_smoke_test.exs
  - test/foglet_bbs/tui/screens/account_test.exs
  - test/foglet_bbs/tui/screens/login_test.exs
  - test/foglet_bbs/tui/screens/main_menu_test.exs
  - test/foglet_bbs/tui/screens/new_thread_test.exs
  - test/foglet_bbs/tui/screens/post_reader_test.exs
  - test/foglet_bbs/tui/screens/sysop_test.exs
findings:
  critical: 1
  warning: 1
  info: 0
  total: 2
status: issues_found
---

# Phase 43: Code Review Report

**Reviewed:** 2026-04-29T23:59:15Z
**Depth:** standard
**Files Reviewed:** 20
**Status:** issues_found

## Summary

Reviewed the Phase 43 large-screen decomposition source, tests, and screen contract docs. The extraction mostly preserves reducer/render boundaries, but PostReader lost a defensive terminal-size fallback that can crash rendering, and two new render modules now perform runtime config reads despite the documented render purity boundary.

## Critical Issues

### CR-01: BLOCKER - PostReader Render Crashes When Terminal Size Is Missing

**File:** `lib/foglet_bbs/tui/screens/post_reader/render.ex:24`
**Issue:** The extracted PostReader render path destructures `context.terminal_size` directly with `{w, h} = context.terminal_size`. Before this extraction, `PostReader.render/2` used `context.terminal_size || @default_terminal_size`, so a missing or nil terminal size rendered with the 80x24 fallback. `Context.new/1` currently accepts `terminal_size: nil`, and direct render/test/fixture callers can produce that shape; the current code raises `MatchError` and tears down the render path instead of showing the reader.
**Fix:**
```elixir
@default_terminal_size {80, 24}

def render(%State{} = state, %Context{} = context) do
  frame_state = frame_state(state, context)
  theme = Theme.from_state(frame_state)
  {w, h} = context.terminal_size || @default_terminal_size
  post_content = render_local_post_content(state, frame_state, theme, w, h)
  ...
end
```

Add a focused test that calls `PostReader.render/2` with `Context.new(terminal_size: nil)` and a loading or loaded `%PostReader.State{}` to lock the fallback behavior.

## Warnings

### WR-01: WARNING - Render Modules Still Perform Runtime Config Reads

**File:** `lib/foglet_bbs/tui/screens/new_thread/render.ex:185`
**Issue:** `NewThread.Render` calls `Config.get!/1` from render-time helpers, and `Login.Render` calls `Config.get/2` at `lib/foglet_bbs/tui/screens/login/render.ex:83`. `Foglet.Config` is a read-through ETS cache; on cache miss these calls hit `Repo.get_by!/2`, which violates the new `SCREEN_CONTRACT.md` rule that render modules must not query the database or perform runtime work outside already-loaded state/context. The Phase 43 purity tests only forbid `Config.put`, so this regression is not covered. It also leaves Login render vulnerable to DB/cache failures because `Config.get/2` only rescues missing rows, not DB errors.
**Fix:** Move these values into reducer-owned state or `Context.session_context` before render, then make render use only those already-loaded values with local defaults. Extend the render-purity source check to forbid `Config.get`, `Config.get!`, and `Config.fetch` in sibling render modules unless a future contract explicitly allows cached config reads.

---

_Reviewed: 2026-04-29T23:59:15Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
