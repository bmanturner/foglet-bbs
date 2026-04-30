---
phase: 43-large-screen-decomposition
reviewed: 2026-04-30T00:59:12Z
depth: standard
files_reviewed: 21
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
  - lib/foglet_bbs/tui/screens/sysop/state.ex
  - test/foglet_bbs/tui/layout_smoke_test.exs
  - test/foglet_bbs/tui/screens/account_test.exs
  - test/foglet_bbs/tui/screens/login_test.exs
  - test/foglet_bbs/tui/screens/main_menu_test.exs
  - test/foglet_bbs/tui/screens/new_thread_test.exs
  - test/foglet_bbs/tui/screens/post_reader_test.exs
  - test/foglet_bbs/tui/screens/sysop_test.exs
findings:
  critical: 0
  warning: 2
  info: 0
  total: 2
status: issues_found
---

# Phase 43: Code Review Report

**Reviewed:** 2026-04-30T00:59:12Z
**Depth:** standard
**Files Reviewed:** 21
**Status:** issues_found

## Summary

Reviewed the listed Phase 43 large-screen decomposition files at standard depth. The reducer/render split mostly preserves behavior, but two quality defects remain: PostReader rendering now emits side-effectful warning logs during normal fallback rendering, and NewThread silently hides configuration read failures behind defaults.

Focused test command run: `rtk mix test test/foglet_bbs/tui/screens/account_test.exs test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/tui/screens/main_menu_test.exs test/foglet_bbs/tui/screens/new_thread_test.exs test/foglet_bbs/tui/screens/post_reader_test.exs test/foglet_bbs/tui/screens/sysop_test.exs` passed, but it reproduced the PostReader warning spam.

## Warnings

### WR-01: WARNING - PostReader Render Emits Warning Logs On Cache Misses

**File:** `lib/foglet_bbs/tui/screens/post_reader/render.ex:91`
**Issue:** The render boundary logs `Logger.warning/1` every time a selected post is not already present in `ss.render_cache`. Render is documented as pure over already-loaded state, and this turns ordinary rendering into a noisy side-effect path. The focused test run emitted repeated `[PostReader] render cache miss` warnings from normal render scenarios, so this is not just a defensive branch for impossible state.
**Fix:**
```elixir
tuples =
  case ss.render_cache[{post.id, w}] do
    nil -> PostReader.body_tuples_for(frame_view, post)
    cached -> cached
  end
```

If cache misses need observability, emit telemetry from the reducer cache-warming path or downgrade this to debug-level instrumentation behind an explicit development flag.

### WR-02: WARNING - NewThread Silently Swallows Configuration Failures

**File:** `lib/foglet_bbs/tui/screens/new_thread.ex:377`
**Issue:** `safe_config_get/2` rescues all exceptions from `Config.get!/1` and returns hardcoded defaults. That masks real configuration/cache/database failures and lets the compose flow continue with fallback limits instead of surfacing an operational error. In this path, a failed `max_post_length` read can silently change validation behavior.
**Fix:**
```elixir
defp safe_config_get(key, default) do
  case Config.get!(key) do
    n when is_integer(n) and n > 0 -> n
    _ -> default
  end
rescue
  Ecto.NoResultsError -> default
end
```

Better still, snapshot these limits before render/update through session context or screen state and let unexpected config failures propagate to the caller that can show an explicit error.

---

_Reviewed: 2026-04-30T00:59:12Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
