---
phase: 20-rich-rows-and-thread-flow
fixed_at: 2026-04-25T21:30:00Z
status: all_fixed
fix_scope: critical_warning
findings_in_scope: 2
fixed: 2
skipped: 0
iteration: 3
final_review_status: clean
---

# Phase 20: Code Review Fix Report

## Summary

Applied the Phase 20 code review fixes in auto mode. The initial review warning
was fixed in iteration 1. The iteration 2 re-review surfaced one blocker, which
was also fixed. The final iteration 3 re-review is clean.

## Fixes Applied

### WR-01: Generic State Atoms Are Accepted But Rendered As Blank Slots

**Status:** fixed

Updated `Foglet.TUI.Widgets.List.RichRow` so `state_cluster` remains backward
compatible with built-in ThreadList atoms while also accepting explicit
caller-owned glyph cells such as `%{key: :subscribed, glyph: "◆", slot:
:success}`. Explicit cells render in caller order, preserve the fixed cluster
width, and route styling through the supplied theme slot.

Added RichRow tests that assert custom glyph rendering, theme slot routing, and
selected-row background behavior for explicit state cells.

Commit:

```text
47e846b fix(20): render explicit rich row state cells
```

### BL-01: Nil-Activity Threads Sort Before Active Threads

**Status:** fixed

Updated `ThreadList.sort_by_recency/1` so timestamped threads sort newest-first
while nil `last_post_at` rows sort last within their sticky/non-sticky group.
The fix no longer reverses the nil sentinel ahead of active rows.

Added a ThreadList regression test with a nil row and a dated row in the same
group, asserting the active row is selected before the nil row.

Commit:

```text
8a6e004 fix(20): keep nil-activity threads last
```

## Verification

Focused Phase 20 verification passed:

```text
rtk mix test test/foglet_bbs/tui/widgets/list/rich_row_test.exs test/foglet_bbs/tui/screens/thread_list_test.exs test/foglet_bbs/tui/layout_smoke_test.exs
77 tests, 0 failures
```

Final auto re-review wrote `20-REVIEW.md` with `status: clean` and no findings.
