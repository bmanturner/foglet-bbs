---
phase: 04-composer-thread-creation-end-to-end
fixed_at: 2026-04-20T00:00:00Z
review_path: .planning/workstreams/phase-03-polish/phases/04-composer-thread-creation-end-to-end/04-REVIEW.md
iteration: 1
findings_in_scope: 9
fixed: 8
skipped: 1
status: partial
---

# Phase 04: Code Review Fix Report

**Fixed at:** 2026-04-20
**Source review:** .planning/workstreams/phase-03-polish/phases/04-composer-thread-creation-end-to-end/04-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 9
- Fixed: 8
- Skipped: 1

## Fixed Issues

### WR-01: Map access syntax on a screen_state map that is not a struct — latent KeyError risk

**Files modified:** `lib/foglet_bbs/tui/screens/post_composer.ex`
**Commit:** f011ff0
**Applied fix:** Replaced `ss[:reply_to] && ss[:reply_to].id` with an explicit `case Map.get(ss, :reply_to)` pattern in `do_submit/3`, making the nil-guard explicit and consistent with project conventions.

---

### WR-02: `create_reply` result ignored in seeds — silent failure during setup

**Files modified:** `priv/repo/seeds.exs`
**Commit:** f136171
**Applied fix:** Added `{:ok, _} =` pattern-match assertions to all three `Posts.create_reply/4` call sites (intro thread reply and both chat thread replies). Seed failures now raise immediately with a match error rather than continuing silently.

---

### WR-03: `warm_cache/4` is defined but never called from `render_post_content/5`

**Files modified:** `lib/foglet_bbs/tui/screens/post_reader.ex`
**Commit:** 4253a5d
**Applied fix:** Replaced the misleading "caller should store it via warm_cache/4" comment on `parse_body/2` with a precise explanation: `parse_body/2` is a pure read-only helper, the cache is populated by `load_posts/2`, `advance_post/2`, and `scroll_post/2`, and `render_post_content/5` intentionally falls back to `parse_body/2` for uncached posts because it cannot write state.

---

### WR-04: Nested `defmodule` declarations inside test files

**Files modified:** `test/foglet_bbs/tui/screens/new_thread_test.exs`, `test/foglet_bbs/tui/screens/thread_list_test.exs`
**Commit:** 2bd7ce0
**Applied fix:** Moved all fake adapter modules (`FakeBoards`, `FakeBoardsEmpty`, `FakeThreadsOk`, `FakeThreadsMissing`, `FakeThreadsError` in new_thread_test; `FakeThreads`, `HandlelessFakeThreads`, `NiltimeFakeThreads`, `AnnotatingFakeThreads`, `OneArityOnly` in thread_list_test) outside the outer test `defmodule` to top of file, with fully-qualified names (e.g. `Foglet.TUI.Screens.NewThreadTest.FakeBoards`). Added corresponding `alias` declarations inside the test module.

---

### WR-05: Fragile ordering dependency for Ctrl+S/C

**Files modified:** `lib/foglet_bbs/tui/screens/new_thread.ex`
**Commit:** 0b1b2be
**Applied fix:** Added an explicit comment above the `%{focused: :body}` fallthrough clause in `handle_compose_key/3` explaining that the Ctrl+C and Ctrl+S clauses above it must remain there — `Compose.translate_key/1` intentionally passes ctrl+char combos through, so future refactors moving those clauses below the body handler would silently break the submit/cancel shortcuts.

---

### IN-02: Missing `:origin` key in `NewThread.init_screen_state/1`

**Files modified:** `lib/foglet_bbs/tui/screens/new_thread.ex`, `test/foglet_bbs/tui/screens/new_thread_test.exs`
**Commit:** 0b2965b
**Applied fix:** Added `origin: :main_menu` to the map returned by `init_screen_state/1` with an inline comment noting callers may override it. Added a corresponding `assert ss.origin == :main_menu` assertion to the `init_screen_state/1 defaults to board step` test.

---

### IN-03: Misleading comment in post_reader.ex:219

**Files modified:** `lib/foglet_bbs/tui/screens/post_reader.ex`
**Commit:** 4253a5d (combined with WR-03)
**Applied fix:** The comment on `parse_body/2` that created the misleading cross-reference to `warm_cache/4` was replaced entirely with accurate documentation of the caching strategy. See WR-03 above.

---

### IN-04: Dead code `NewThread.load_boards/1` — remove it and its test

**Files modified:** `lib/foglet_bbs/tui/screens/new_thread.ex`, `test/foglet_bbs/tui/screens/new_thread_test.exs`
**Commit:** 8cea02f
**Applied fix:** Removed the `load_boards/1` public function and its `@doc`/`@spec`, the two test cases that exercised it (`load_boards/1 populates boards into screen_state` and `load_boards/1 with no domain module sets empty list`), and the now-unused `FakeBoardsEmpty` adapter module and alias.

---

## Skipped Issues

### IN-01: Dead code — `load_posts/2` and `flush_read_pointers/2` in `PostReader` are never called from `App`

**File:** `lib/foglet_bbs/tui/screens/post_reader.ex:138,161`
**Reason:** Architectural refactor required — not safe to auto-fix
**Original issue:** `PostReader.load_posts/2` and `PostReader.flush_read_pointers/2` are documented as "called by App.update/2" but `app.ex` implements equivalent logic directly in `do_update/2` without delegating to these functions. However, `load_posts/2` in PostReader contains important logic not present in the `app.ex` path (seeding `read_position` on entry and warming the render cache for post 0). Removing or consolidating these functions requires changes to both `app.ex` and `post_reader.ex` to preserve the cache-warming and read-position-seeding behavior. The tests call `PostReader.load_posts/2` directly and pass. This fix requires human review of the intended delegation strategy before it can be safely applied.

---

_Fixed: 2026-04-20_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
