---
phase: 09-postreader
fixed_at: 2026-04-22T15:03:02Z
review_path: .planning/workstreams/phase-03-screen-audit/phases/09-postreader/09-REVIEW.md
iteration: 1
findings_in_scope: 7
fixed: 4
skipped: 3
status: partial
---

# Phase 09: Code Review Fix Report — PostReader

**Fixed at:** 2026-04-22T15:03:02Z
**Source review:** .planning/workstreams/phase-03-screen-audit/phases/09-postreader/09-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 7
- Fixed: 4
- Skipped: 3

## Fixed Issues

### IN-01: `p2_state/1` fixture does not inject `domain` key

**Files modified:** `test/foglet_bbs/tui/screens/post_reader_test.exs`
**Commit:** 0526ee1
**Applied fix:** Added `domain: %{markdown: FakeMarkdown}` to the `session_context` map in `p2_state/1`, ensuring all p2_state-based render/navigation tests use FakeMarkdown instead of silently falling back to the real `Foglet.Markdown` module.

---

### IN-02: Purity-guard scope-tracking regex is non-monotonic for back-to-back `defp render_*` clauses

**Files modified:** `test/foglet_bbs/tui/screens/post_reader_test.exs`
**Commit:** 3110c1e
**Applied fix:** Added a 4-line comment immediately before the `Enum.reduce/3` in the purity guard test, explaining that the regex is sufficient for the current source but is non-monotonic if multi-clause `render_*` functions appear back-to-back, and that a two-pass line-range approach would be needed for full correctness.

---

### IN-03: `FakePosts` and `FakePostsForLoad` are structurally redundant

**Files modified:** `test/foglet_bbs/tui/screens/post_reader_test.exs`
**Commit:** 36bbcaf
**Applied fix:** Added a 3-line comment above `defmodule FakePostsForLoad` explaining that the separate module exists because it uses `message_number` values 5/6 (vs 1/2 in `FakePosts`) to test load-specific read-position keying and distinguish from default-fixture data.

---

### IN-04: Test file contains six nested `defmodule` blocks

**Files modified:** `test/foglet_bbs/tui/screens/post_reader_test.exs`
**Commit:** a640804
**Applied fix:** Added a 2-line comment above the first nested `defmodule FakePosts` block annotating the nested fakes as the standard ExUnit pattern, explicitly exempt from the CLAUDE.md "no nested modules" convention since test files carry no cyclic-dependency risk.

---

## Skipped Issues

### WR-01: `flush_read_pointers/2` silently swallows domain errors

**File:** `lib/foglet_bbs/tui/screens/post_reader.ex:283-284`
**Reason:** Code context differs from review — already implemented. The current source (lines 283-339) already captures `board_result` and `thread_result`, delegates to `apply_flush_result/4`, and uses `flush_result_ok?/1` guards with a `Logger.warning` on failure path. The fix suggested in REVIEW.md is fully present in the code.

---

### WR-02: `flush_board_pointer/3` and `flush_thread_pointer/3` return `nil` instead of `:skip`

**File:** `lib/foglet_bbs/tui/screens/post_reader.ex:294-309`
**Reason:** Code context differs from review — already implemented. Both `flush_board_pointer/3` (line 301) and `flush_thread_pointer/3` (line 311) already have explicit `else :skip` branches in the current source.

---

### WR-03: `build_flush_context/1` uses `nil` as a `Map.get/2` key when `current_thread` absent

**File:** `lib/foglet_bbs/tui/screens/post_reader.ex:506-507`
**Reason:** Code context differs from review — already implemented. The current source (lines 534-539) already uses the guarded `if thread_id do Map.get(..., thread_id, %{}) else %{} end` pattern recommended by the reviewer.

---

_Fixed: 2026-04-22T15:03:02Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
