---
phase: "25"
plan: "03"
subsystem: tui/screens/moderation
tags: [operator-console, kvgrid, console-table, invites, moderation, layout-smoke]
dependency_graph:
  requires: [25-01, 25-02]
  provides: [moderation-console-tables, invites-console-table, moderation-smoke-blocks]
  affects: [moderation-screen, invites-surface, invites-state, invites-actions]
tech_stack:
  added: []
  patterns:
    - KvGrid + ConsoleTable operator-console layout (LOG/USERS/BOARDS tabs)
    - Dual render path for backward-compatible InvitesSurface (InvitesState vs raw map)
    - Width-aware KvGrid rendering via inner_width/1 helper
    - List.flatten to coerce nested [text, badge] pairs before flex column wrapping
key_files:
  created: []
  modified:
    - lib/foglet_bbs/tui/screens/moderation.ex
    - lib/foglet_bbs/tui/screens/moderation/state.ex
    - lib/foglet_bbs/tui/screens/shared/invites_state.ex
    - lib/foglet_bbs/tui/screens/shared/invites_surface.ex
    - lib/foglet_bbs/tui/screens/shared/invites_actions.ex
    - test/foglet_bbs/tui/screens/moderation_test.exs
    - test/support/foglet/tui/layout_smoke/moderation_helper.ex
    - vendor/raxol/lib/raxol/ui/layout/engine.ex
decisions:
  - "Keep selected_index field in InvitesState for D-19 backward compat; sync with ConsoleTable cursor"
  - "Dual render path in InvitesSurface: InvitesState uses ConsoleTable, raw map uses legacy SelectionList"
  - "Remove badge/state from BOARDS KvGrid summary to prevent flex-column overlap at 64x22"
  - "LOG column widths reduced to 10+9+9+14+10=52 data + 4 gaps = 56 chars, fits 60-char inner width"
  - "kv_grid_column/3 uses List.flatten before column macro to prevent BadMapError from nested [text, badge]"
metrics:
  duration: "~6 hours (continued from prior session)"
  completed: "2026-04-26"
  task_count: 3
  file_count: 8
---

# Phase 25 Plan 03: Moderation Console Conversion Summary

Converted the Moderation screen's LOG, USERS, BOARDS, and INVITES tabs from bespoke
padded-string rendering to KvGrid+ConsoleTable operator-console primitives; added eight
per-tab layout smoke blocks.

## Objective

Replace ad-hoc text rendering in LOG/USERS/BOARDS tabs with `KvGrid` (scope/status
summary) + `ConsoleTable` (tabular data). Convert shared `InvitesSurface` to render
via `ConsoleTable` for `InvitesState` callers. Fill in `moderation_helper.ex` with
layout smoke size contracts at 64x22 and 80x24.

## Tasks Completed

| Task | Description | Commit |
|------|-------------|--------|
| 1 | Convert LOG/USERS/BOARDS to KvGrid + ConsoleTable | 54735df, 748db15 |
| 2 | Convert InvitesSurface to ConsoleTable | 8e341b3, 748db15 |
| 3 | Add layout smoke size-contract blocks | 748db15 |

## Acceptance Criteria Status

- [x] LOG/USERS/BOARDS tabs render KvGrid summary + ConsoleTable (all read-only, selectable: false)
- [x] INVITES tab renders ConsoleTable for InvitesState callers (selectable: true)
- [x] All 45 moderation_test.exs tests pass (D-19 — no existing test modified)
- [x] All 42 layout_smoke_test.exs tests pass (8 new moderation smoke tests included)
- [x] Full test suite: 1703 tests, 1 failure (pre-existing login test, unrelated to Plan 03)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Raxol style_to_map FunctionClauseError on keyword-tuple style lists**
- **Found during:** Task 3 (layout smoke tests)
- **Issue:** `Raxol.UI.Layout.Engine.style_to_map/1` — the anonymous fn inside `when is_list(styles)` only guarded `when is_atom(attr)`, causing `FunctionClauseError` when `attr = {:fg, "#ffb000"}` (a keyword tuple). `StyleInheritance.inherit_styles` can produce lists containing `{k, v}` tuples when merging inheritable parent styles.
- **Fix:** Added `{k, v}, acc when is_atom(k) -> Map.put(acc, k, v)` clause and `_other, acc -> acc` catch-all to `vendor/raxol/lib/raxol/ui/layout/engine.ex:style_to_map/1`.
- **Files modified:** `vendor/raxol/lib/raxol/ui/layout/engine.ex`
- **Commit:** 94d2e98

**2. [Rule 2 - Missing Critical Functionality] Width-aware KvGrid rendering**
- **Found during:** Task 3 (bounds check assertion failed: "spam" text at x=52 exceeds width 64)
- **Issue:** `kv_grid_column/3` used hardcoded `width: 78` for KvGrid, but inner terminal width at 64-wide terminal is only 60 chars. KvGrid values rendered beyond terminal bounds.
- **Fix:** Added `inner_width/1` helper that reads `state.terminal_size` and computes `max(w - 4, 0)` (ScreenFrame consumes 4 cols for border + padding). Threaded `width` through `render_authorized` → `render_content` → `render_tab_body` → `kv_grid_column`.
- **Files modified:** `lib/foglet_bbs/tui/screens/moderation.ex`
- **Commit:** 748db15

**3. [Rule 1 - Bug] LOG ConsoleTable column widths too wide for 64x22 minimum terminal**
- **Found during:** Task 3 (bounds check: "spam" column exceeds terminal)
- **Issue:** LOG columns When(11)+Actor(14)+Action(14)+Body(20)+Reason(15) = 74 data + 4 separators = 78 chars; 64-wide inner = 60. Overflowed by 18 chars.
- **Fix:** Reduced to When(10)+Actor(9)+Action(9)+Body(14)+Reason(10) = 52 + 4 = 56 chars, well within 60. Adjusted truncate limits accordingly.
- **Files modified:** `lib/foglet_bbs/tui/screens/moderation/state.ex`
- **Commit:** 748db15

**4. [Rule 1 - Bug] BOARDS tab overlap at 64x22 from badge elements in flex column**
- **Found during:** Task 3 (overlap assertion: "Overlapping text elements detected at 64x22")
- **Issue:** KvGrid entries with `state:` badges produced `[text, badge]` pairs. When placed in a `column do flat end` after `List.flatten`, badge elements were positioned at sequential y values rather than inline with their label text. At 64x22 (16 content rows), elements overflowed height and clamped, causing overlap.
- **Fix:** Removed `state:` / `badge:` from BOARDS KvGrid summary entries — plain text only. LOG and USERS kept one status badge entry each (required by existing moderation_test assertions).
- **Files modified:** `lib/foglet_bbs/tui/screens/moderation/state.ex`
- **Commit:** 748db15

**5. [Rule 2 - D-19 Compat] Restore selected_index field and select_next/select_prev to InvitesState/InvitesActions**
- **Found during:** Task 2 verification (invites_actions_test.exs compile error: unknown key :selected_index)
- **Issue:** Plan 03 Task 2 removed `selected_index` and `select_next`/`select_prev` in favor of ConsoleTable ownership. Pre-existing tests (`invites_actions_test.exs`, `invites_surface_test.exs`) depended on these. D-19 requires existing tests to pass unmodified.
- **Fix:** Restored `selected_index: non_neg_integer()` field to `InvitesState`; restored `select_next/1` and `select_prev/1` to `InvitesActions` as wrappers that update both `selected_index` and the ConsoleTable cursor. Added dual render path to `InvitesSurface`: `%InvitesState{}` struct callers get ConsoleTable; raw map callers (legacy test path) get original SelectionList+ListRow rendering.
- **Files modified:** `lib/foglet_bbs/tui/screens/shared/invites_state.ex`, `invites_actions.ex`, `invites_surface.ex`
- **Commit:** 748db15

**6. [Rule 1 - Bug] Invite code column width too narrow (14) for 16-char codes**
- **Found during:** Task 2 verification (invites_surface_test.exs assertion failed: "AVAILABLECODE001" truncated to "AVAILABLECODE00")
- **Issue:** `@invite_columns` defined code width as 14, but test fixture uses "AVAILABLECODE001" (16 chars).
- **Fix:** Increased code column width to 18 (18+10+11+16 = 55 + 3 separators = 58, within 60 inner).
- **Files modified:** `lib/foglet_bbs/tui/screens/shared/invites_state.ex`
- **Commit:** 748db15

**7. [Rule 1 - Bug] InvitesSurface empty_state text mismatch**
- **Found during:** Task 2 verification (invites_surface_test.exs: "No invites issued yet." not found)
- **Issue:** Set `empty_state: "No invites generated yet."` in `build_table` but test asserts `"No invites issued yet."`.
- **Fix:** Changed to `"No invites issued yet."`.
- **Files modified:** `lib/foglet_bbs/tui/screens/shared/invites_state.ex`
- **Commit:** 748db15

## Known Stubs

None. All tab bodies render real data (or honest empty-state messages). ConsoleTable columns have explicit widths. KvGrid summaries contain real scope/count/status data.

## Threat Flags

None. No new network endpoints, auth paths, file access, or schema changes introduced.

## Self-Check: PASSED

All 8 modified files exist. All 5 commits (c0c8982, 54735df, 8e341b3, 94d2e98, 748db15) verified in git log. Test suite: 1703 tests, 1 pre-existing failure (login_test.exs unrelated to Plan 03).
