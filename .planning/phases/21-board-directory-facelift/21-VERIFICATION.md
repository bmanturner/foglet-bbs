---
phase: 21-board-directory-facelift
verified: 2026-04-25T22:45:11Z
status: passed
score: 5/5 must-haves verified
overrides_applied: 0
re_verification:
  previous_status: gaps_found
  previous_score: 4/5
  gaps_closed:
    - "Focused board/category details are now visible through both the 64x22-safe compact details strip and a width-gated wide inspector."
  gaps_remaining: []
  regressions: []
---

# Phase 21: Board Directory Facelift Verification Report

**Phase Goal:** Board browsing presents categories, board state, subscriptions, and details as structured rows.
**Verified:** 2026-04-25T22:45:11Z
**Status:** passed
**Re-verification:** Yes - after compact details strip and wide inspector gap closure

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Users can distinguish expanded/collapsed categories, read/unread boards, and subscription state visually. | VERIFIED | `BoardTree.render/2` dispatches category and board rows separately, board rows use `RichRow.render/1` with state clusters, and layout tests assert category glyphs, subscription glyphs, unread glyphs, unread counts, and ages at 64x22, 80x24, and 132x50. |
| 2 | Board labels are semantic columns, not embedded bracket text. | VERIFIED | `BoardTree` composes board title, state cluster, and metadata as separate row fields; `board_list_test.exs` refutes legacy `[required]`, `[subscribed]`, and `[unsubscribed]` labels. |
| 3 | Focused board/category details are visible through a 64x22-safe compact details strip, with a wide inspector only when width permits. | VERIFIED | `BoardList.render_board_content/3` renders `details_strip/4` and conditionally appends `wide_inspector/4`; `@wide_inspector_min_width` is 100, compact widths return no inspector, and tests prove compact 64x22 board/category strips plus wide-only inspector behavior. |
| 4 | The current single-label tree limitation is solved through row callbacks or a dedicated board-tree wrapper. | VERIFIED | `Foglet.TUI.Widgets.List.BoardTree` is the dedicated wrapper and exposes focused entry APIs so `BoardList` no longer depends on raw `Display.Tree` internals. |
| 5 | Existing tree state and subscribe/open/back workflows continue to work. | VERIFIED | `BoardList` forwards navigation to `BoardTree.handle_event/2`, uses `focused_board_entry/1` for open/subscribe/unsubscribe, preserves back navigation, and screen tests still pass. |

**Score:** 5/5 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/foglet_bbs/boards.ex` | `:last_post_at` on directory entries via board-rooted aggregate | VERIFIED | `board_directory_for/1` populates `last_post_at` from `last_post_ats/0`; the aggregate is rooted on `Board` with a left join to non-deleted threads. |
| `lib/foglet_bbs/tui/widgets/list/board_tree.ex` | Stateful BoardTree wrapper rendering structured rows | VERIFIED | Public `init/1`, `handle_event/2`, `render/2`, `focused_board_entry/1`, and `focused_entry/1` exist; `focused_entry/1` returns category or board data with `:kind`. |
| `lib/foglet_bbs/tui/screens/board_list.ex` | BoardList migrated to BoardTree with focused details surfaces | VERIFIED | `BoardTree.render/2`, `details_strip/4`, and width-gated `wide_inspector/4` are wired in the loaded render branch. |
| `lib/foglet_bbs/tui/screens/board_list/state.ex` | Screen-local `board_tree` state | VERIFIED | `board_tree` remains the screen-local tree holder. |
| `test/foglet_bbs/tui/widgets/list/board_tree_test.exs` | Widget contract tests | VERIFIED | Included in the passing focused TUI test run. |
| `test/foglet_bbs/tui/screens/board_list_test.exs` | Integration workflow, glyph, compact details, and wide inspector tests | VERIFIED | Lines 131-160 assert compact board details at 64x22, compact category details at 64x22, and inspector visibility only at 132x50 rather than 80x24. |
| `test/foglet_bbs/tui/layout_smoke_test.exs` | 64x22/80x24/132x50 BoardList size contract | VERIFIED | Lines 356-520 exercise BoardList row visibility and overlap constraints at all required sizes. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `Boards.board_directory_for/1` | `last_post_ats/0` | `last_post_ats = last_post_ats()` then `Map.get(last_post_ats, board.id)` | WIRED | Board directory entries receive real last-post timestamps. |
| `BoardTree.focused_entry/1` | `BoardList.details_strip/4` | focused entry lookup before detail formatting | WIRED | `details_strip/4` calls `BoardTree.focused_entry/1` and truncates detail text to the current row width. |
| `BoardTree.focused_entry/1` | `BoardList.wide_inspector/4` | focused entry lookup before inspector formatting | WIRED | `wide_inspector/4` calls `BoardTree.focused_entry/1` only after the min-width guard permits rendering. |
| `BoardList.render_board_content/3` | `BoardTree.render/2` | loaded board-list render branch | WIRED | BoardList renders the dedicated BoardTree wrapper rather than the raw tree component. |
| `BoardList.handle_key/2` | `BoardTree.handle_event/2` | navigation/open key paths | WIRED | Navigation and activation flow through BoardTree APIs. |
| `BoardList` | subscribe/open/back commands | focused board entry plus existing command tuples | WIRED | Existing workflow behavior remains covered by screen tests. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `lib/foglet_bbs/boards.ex` | `last_post_at` | `last_post_ats/0` query over boards and non-deleted threads | Yes | FLOWING |
| `lib/foglet_bbs/tui/widgets/list/board_tree.ex` | focused board/category data | Tree node `data` built from `directory_to_nodes/1` and `board_to_node/1` | Yes | FLOWING |
| `lib/foglet_bbs/tui/screens/board_list.ex` | compact details strip text | `BoardTree.focused_entry/1` plus current directory | Yes | FLOWING |
| `lib/foglet_bbs/tui/screens/board_list.ex` | wide inspector text | `BoardTree.focused_entry/1` plus current directory after width guard | Yes | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Board directory `last_post_at` behavior | `rtk mix test test/foglet_bbs/boards/boards_test.exs --only board_directory` | 6 tests, 0 failures | PASS |
| BoardTree, BoardList, and layout contracts | `rtk mix test test/foglet_bbs/tui/widgets/list/board_tree_test.exs test/foglet_bbs/tui/screens/board_list_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` | 78 tests, 0 failures | PASS |
| Compile with warnings as errors | `rtk mix compile --warnings-as-errors` | exited 0 | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| BOARDS-01 | 21-02, 21-03, 21-04 | Rows distinguish category expansion, read/unread, and subscription state with semantic columns and glyphs. | SATISFIED | BoardTree code and layout/screen tests verify glyphs and semantic row composition. |
| BOARDS-02 | 21-02, 21-03, 21-04 | Focused board/category details visible through compact details strip, with wide inspector only when width permits. | SATISFIED | Compact strip exists at 64x22; `wide_inspector/4` is gated by `@wide_inspector_min_width`; tests assert the inspector is absent at 80x24 and present at 132x50. |
| BOARDS-03 | 21-01 | Existing board open, expand/collapse, subscribe, unsubscribe, and back workflows continue to work after facelift. | SATISFIED | BoardList workflow tests pass, and handle paths still use BoardTree focus APIs plus existing commands. |
| BOARDS-04 | 21-04 | Single-label tree limitation solved through row callbacks or BoardTree wrapper. | SATISFIED | Dedicated `BoardTree` wrapper exists and is wired into BoardList. |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None | - | - | - | No phase-blocking stub, placeholder, hardcoded-empty, or orphaned-details pattern found. |

### Human Verification Required

None.

### Gaps Summary

No remaining gaps. The previously blocking BOARDS-02 concern is closed: the compact details strip is always rendered from focused category/board data and remains width-truncated for compact terminals, while the wide inspector is explicitly suppressed below 100 columns and rendered only when width permits. Later milestone phases do not need to absorb any unresolved Phase 21 requirement.

---

_Verified: 2026-04-25T22:45:11Z_
_Verifier: the agent (gsd-verifier)_
