---
phase: 19-main-menu-dashboard
plan: "03"
subsystem: tui-screens
tags:
  - main-menu
  - size-contracts
  - layout-smoke-test
  - range-overlap
  - viewport-bound
  - cjk-unicode
  - role-atom-fix
  - oneliner-panel-containment

dependency_graph:
  requires:
    - "Phase 19 Plan 01: visible_destinations/1 data layer"
    - "Phase 19 Plan 02: boxed Navigation + Oneliners panels with glyph rows"
    - "Phase 16: TextWidth.display_width/1, slice_to_width/2"
  provides:
    - "Phase 19 size-contract block in layout_smoke_test.exs at [{64,22},{80,24},{132,50}]"
    - "Range-overlap assertions (per-y Enum.group_by + chunk_every) for Main Menu"
    - "Oneliner-in-right-panel containment assertions (x >= oneliners_header.x)"
    - "CJK + combining-mark long-Unicode fixture at 64x22"
  affects:
    - "Any future Main Menu visual refactors — must keep tests green"
    - "Oneliner clipping constants (@oneliner_body_limit) reduced 22->20 for 64-wide correctness"

tech_stack:
  added: []
  patterns:
    - "Per-y range-overlap assertion: Enum.group_by(elements, &1.y) + chunk_every(2,1,:discard)"
    - "Panel containment anchor: oneliner row x >= oneliners_header.x"
    - "Three-size positioned-render iteration [{64,22},{80,24},{132,50}] (Phase 18 pattern extended)"
    - "CJK double-width + combining-mark fixture using String.duplicate + unicode literals"

key_files:
  created: []
  modified:
    - test/foglet_bbs/tui/layout_smoke_test.exs
    - lib/foglet_bbs/tui/screens/main_menu.ex

decisions:
  - "Range-overlap assertion uses per-y grouping (not identical-{x,y}) per REVIEWS.md MEDIUM finding"
  - "Oneliner-in-right-panel asserted via oneliners_header.x anchor, not panel boundary math"
  - "CJK fixture uses String.duplicate(\"界\", 20) body + combining_segment = \"café noir\" to exercise TextWidth"
  - "Rule 1: @oneliner_body_limit reduced 22->20 to fix overflow at 64-wide right panel (x=27 + 37 = 64)"

metrics:
  duration: "~8 minutes"
  completed_date: "2026-04-25"
  tasks_completed: 1
  tasks_total: 1
  files_created: 0
  files_modified: 2
---

# Phase 19 Plan 03: Main Menu Size-Contract Assertions Summary

Phase 19 size-contract coverage added to `layout_smoke_test.exs` — boxed Navigation + Oneliners panels asserted side-by-side with range-overlap, viewport-bound, and oneliner-panel-containment at the canonical triple [{64,22},{80,24},{132,50}]; HIGH role atom fix (`:member` -> `:user`) and Rule 1 body-limit fix for 64-wide correctness.

## Performance

- **Duration:** ~8 min
- **Completed:** 2026-04-25
- **Tasks:** 1
- **Files modified:** 2

## What Was Built

Extended `test/foglet_bbs/tui/layout_smoke_test.exs` with the Phase 19 Main Menu size-contract block per D-13, D-16, and REVIEWS.md findings. No new test file created (D-17 preserved).

### Files Modified

**`test/foglet_bbs/tui/layout_smoke_test.exs`**

- Replaced the old `"main_menu renders welcome and all menu items at distinct y positions"` test (which asserted the deleted Welcome line and used `role: :member`) with `"main_menu renders Navigation and Oneliners panels at distinct y positions"`:
  - `refute` Welcome presence (D-11)
  - Assert `"Navigation"` and `"Oneliners"` panel headers
  - Assert glyph-shaped rows via `~r/●.*Boards.*B$/` and `~r/↯.*Logout.*Q$/`
  - Keep `"@alice  hello"` oneliner row assertion
  - Fixed role atom: `role: :user` (was `:member`)

- Fixed `role: :member` -> `role: :user` in `"main_menu clips Unicode oneliners to display-width limits"` test (HIGH severity, REVIEWS.md).

- Added new `describe "Phase 19 Main Menu size contracts"` block with two tests:

  **Test 1: "main menu renders Navigation + Oneliners side-by-side without overlap at 64x22, 80x24, 132x50"**
  - Iterates `[{64, 22}, {80, 24}, {132, 50}]`
  - Viewport-bound: every `element.x + TextWidth.display_width(text) <= width`
  - Both panel headers present (`"Navigation"` and `"Oneliners"`) at every size
  - Side-by-side: `nav_header.x < oneliners_header.x` (not stacked)
  - Range overlap (REVIEWS.md MEDIUM fix): per-y `Enum.group_by` + sorted `chunk_every(2,1,:discard)` asserts `prev.x + display_width(prev.text) <= next.x`
  - Oneliner containment: every `"> @"`-prefixed element has `x >= oneliners_header.x`

  **Test 2: "long-Unicode (CJK + combining-mark) oneliner rows clipped to fit inside the right panel at 64x22"**
  - CJK fixture: `String.duplicate("界", 20)` body + `"café noir café noir"` combining segment
  - CJK handle: `"alice" <> String.duplicate("界", 5)`
  - Asserts all elements fit within 64 cols
  - Asserts oneliner rows stay inside right panel (`x >= oneliners_header.x`)

**`lib/foglet_bbs/tui/screens/main_menu.ex`**

- Reduced `@oneliner_body_limit` from 22 to 20 (Rule 1 bug fix — see Deviations).

## Task Commits

1. **feat(19-03): Phase 19 Main Menu size-contract assertions + canonical role atom fix** — `e35dcba`

## Decisions Made

- Range-overlap uses `Enum.group_by(elements, &1.y)` + `chunk_every(2, 1, :discard)` per-y grouping, replacing the identical-`{x, y}` shape. This catches two elements on the same row with different starting columns whose display widths collide.
- Panel containment anchors on `oneliners_header.x` (observed from positioned tree) rather than computing the panel boundary mathematically — robust to `split_pane` ratio changes.
- CJK fixture body uses `String.duplicate("界", 20)` (40 display cols) which gets clipped by `@oneliner_body_limit` to fit within the right panel.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] @oneliner_body_limit 22 caused oneliner row overflow at 64-wide right panel**

- **Found during:** Task 1 — CJK long-Unicode test (Test 8) failed with overflow
- **Issue:** At 64-wide, `split_pane(ratio: {2,3})` positions the Oneliners panel starting at x=27. The maximum oneliner row width with `@oneliner_handle_limit = 12` and `@oneliner_body_limit = 22` is `"> @"(3) + handle(12) + "  "(2) + body(22) = 39 cols`. Placed at x=27: 27 + 39 = 66 > 64 — overflow by 2 cols. The body limit was calibrated before the boxed panel layout was established.
- **Fix:** Reduced `@oneliner_body_limit` from 22 to 20. New max row = 3 + 12 + 2 + 20 = 37 cols. At x=27: 27 + 37 = 64 — exact fit at 64-wide. The existing `TextWidth.display_width(row) <= 39` assertion in the Unicode-clipping test still passes (37 ≤ 39).
- **Files modified:** `lib/foglet_bbs/tui/screens/main_menu.ex` (line 34)
- **Commit:** `e35dcba`

## Verification Results

- `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` — 23 tests, 0 failures
- `rtk mix format --check-formatted` — both files formatted correctly
- `rg -n "Phase 19 Main Menu size contracts" layout_smoke_test.exs` — 2 matches (section comment + describe block)
- `rg -n "elements overlap on y="` — 1 match (range-overlap error message)
- `rg -n "oneliner row bled out of right panel"` — 2 matches (per-size loop + CJK test)
- `rg -n "oneliners_header"` — 9 matches across the two tests
- `rg -n "界" layout_smoke_test.exs` — 2 matches (CJK fixture)
- `awk 'NR>=315 && NR<=560' layout_smoke_test.exs | rg "role: :member"` — 0 matches
- `rg -n "role: :member" layout_smoke_test.exs` — 2 matches (lines 583/645 BoardList/PostReader, preserved)
- `ls test/foglet_bbs/tui/screens/main_menu_layout_test.exs` — NOT FOUND (D-17 upheld)

## Known Stubs

None — all assertions consume live positioned-render output from `Raxol.UI.Layout.Engine.apply_layout/2` via the `apply_at_size/2` helper.

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns, or schema changes. Changes are confined to test assertions and a clipping constant reduction in the TUI render path. Threat mitigations from the plan's register:

- **T-19-08** (silent layout regression): Three-size positioned-render iteration with viewport-bound + range-overlap + side-by-side + oneliner-in-panel assertions — MITIGATED.
- **T-19-09** (oneliner overflow at 64x22): CJK + combining-mark test at 64x22 — MITIGATED (Rule 1 fix to `@oneliner_body_limit` was required to make this green).
- **T-19-10** (accidentally-created test file): `main_menu_layout_test.exs` does NOT exist — MITIGATED.
- **T-19-11** (non-canonical role atom): All Phase 19 Main Menu fixtures use `role: :user`; BoardList/PostReader `:member` preserved — MITIGATED.

## Self-Check: PASSED

- `test/foglet_bbs/tui/layout_smoke_test.exs` — FOUND
- `lib/foglet_bbs/tui/screens/main_menu.ex` — FOUND
- `.planning/phases/19-main-menu-dashboard/19-03-SUMMARY.md` — FOUND (this file)
- commit `e35dcba` — FOUND (`git log --oneline -1` confirms)
- 23 tests, 0 failures — CONFIRMED
