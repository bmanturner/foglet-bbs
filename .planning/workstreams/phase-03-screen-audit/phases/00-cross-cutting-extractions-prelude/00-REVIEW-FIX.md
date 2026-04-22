---
phase: 00-cross-cutting-extractions-prelude
fixed_at: 2026-04-21T00:00:00Z
review_path: .planning/workstreams/phase-03-screen-audit/phases/00-cross-cutting-extractions-prelude/00-REVIEW.md
fix_scope: all
findings_in_scope: 5
fixed: 5
skipped: 0
iteration: 1
status: all_fixed
---

# Phase 00: Code Review Fix Report

**Fixed at:** 2026-04-21T00:00:00Z
**Source review:** `.planning/workstreams/phase-03-screen-audit/phases/00-cross-cutting-extractions-prelude/00-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 5
- Fixed: 5
- Skipped: 0

---

## Fixed Issues

### WR-01: `PostReader.flush_read_pointers/2` parameter name misleading

**Files modified:** `lib/foglet_bbs/tui/screens/post_reader.ex`
**Commit:** ec96e0a
**Applied fix:** Renamed the second parameter from `ctx` to `flush_ctx` throughout the function body (`flush_ctx[:user_id]`, `flush_board_pointer/3`, `flush_thread_pointer/3`, `clear_read_position/2` calls). Added a clarifying comment at the function head making explicit that `flush_ctx` is a flush-data bag (`%{user_id:, board_id:, thread_id:, ...}`) and that domain modules are read from `state.session_context`, not from `flush_ctx`.

Also fixed a pre-existing Credo alias ordering issue in the same file: moved `Foglet.TUI.Screens.Domain` alias before `Foglet.TUI.Theme` (S < T alphabetically).

### WR-02: `registration_mode/1` duplicates inline session-context extraction

**Files modified:** `lib/foglet_bbs/tui/screens/register.ex`, `lib/foglet_bbs/tui/screens/login.ex`
**Commit:** 4e874cc
**Applied fix:** Extracted a private `session_ctx/1` helper (`defp session_ctx(state), do: Map.get(state, :session_context) || %{}`) in both `Register` and `Login` modules. Updated `registration_mode/1` in each module to call `session_ctx(state)` instead of the inline pattern. Each module has its own private copy — no shared module was introduced, staying within phase scope.

### WR-03: `Domain.get/2` does not validate that value is an atom

**Files modified:** `lib/foglet_bbs/tui/screens/domain.ex`
**Commit:** d6861f7
**Applied fix:** Replaced the `nil -> {:error, :not_configured}` match with `mod when is_atom(mod) and not is_nil(mod) -> {:ok, mod}` on the happy path and a catch-all `_ -> {:error, :not_configured}`. This ensures only genuine module atom references succeed; strings, `false`, `0`, and `nil` all fall through to `:not_configured`.

### IN-01: No test for `nil` value stored under a configured key

**Files modified:** `test/foglet_bbs/tui/screens/domain_test.exs`
**Commit:** 4915d94
**Applied fix:** Added a test case `"returns {:error, :not_configured} when the key value is nil"` with `ctx = %{domain: %{boards: nil}}`. This locks in the behavior introduced by the WR-03 `is_atom` guard and documents the nil-coalescing contract explicitly.

### IN-02: Inline domain lookups in `app.ex` `do_update` lack deviation explanation

**Files modified:** `lib/foglet_bbs/tui/app.ex`, `lib/foglet_bbs/tui/screens/board_list.ex`, `lib/foglet_bbs/tui/screens/new_thread.ex`, `lib/foglet_bbs/tui/screens/post_composer.ex`, `lib/foglet_bbs/tui/screens/thread_list.ex`
**Commit:** 53c8a1c
**Applied fix:** Added a three-line comment at the `{:load_boards}` `do_update` clause in `app.ex` explaining that the inline `get_in/2` domain lookups are intentional — task closures must capture only the module atom (not the full state map) to avoid capturing the entire state in the closure, and migration to `Domain.get/2` is tracked for a future phase.

Also fixed pre-existing Credo alias ordering issues across `board_list.ex`, `new_thread.ex`, `post_composer.ex`, and `thread_list.ex` (all had `Foglet.TUI.Theme` listed before `Foglet.TUI.Screens.Domain`; reordered to S < T). These were caught by `mix precommit` and fixed to keep the gate green.

---

_Fixed: 2026-04-21T00:00:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
