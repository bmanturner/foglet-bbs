---
phase: 19-main-menu-dashboard
plan: "02"
subsystem: tui-screens
tags:
  - main-menu
  - boxed-panels
  - navigation-panel
  - oneliners-panel
  - glyph-rows
  - right-align
  - terminal-width-budget
  - tdd

dependency_graph:
  requires:
    - "Phase 19 Plan 01: visible_destinations/1 data layer (glyph key + label tuples)"
    - "Phase 16: TextWidth.display_width/1, pad_trailing/2, slice_to_width/2"
    - "Phase 17: theme.border.fg, theme.title.fg, theme.primary.fg slots"
    - "Phase 18: ScreenFrame outer chrome box idiom (border: :single, border_fg)"
  provides:
    - "nav_panel/3 — boxed Navigation panel with glyph rows and terminal-size-aware right-align"
    - "nav_row/3 — single text node: glyph + label + TextWidth padding + right-aligned key"
    - "nav_panel_inner_width/1 — derives per-render width budget from state.terminal_size"
    - "oneliners_panel/2 — boxed Oneliners panel wrapping existing oneliner_rows/2"
    - "@nav_panel_min_inner_width 20 — floor constant for pathological/missing terminal_size"
    - "@nav_glyphs map — canonical glyph assignments for all six destinations"
  affects:
    - "Plan 03 (size-contract assertions) — consumes nav_panel_inner_width/1 math"
    - "Any future per-glyph slot routing (D-08 deferred: single text node kept simple)"

tech_stack:
  added: []
  patterns:
    - "Terminal-size-aware inner width budget: split_pane ratio math + box border deducted + floor at min constant"
    - "Right-align via TextWidth.pad_trailing/2 against computed budget (matches ListRow pattern)"
    - "Theme-slot-only row styling: theme.primary.fg on full row text node, theme.title.fg on panel headers"
    - "TDD RED/GREEN gate for panel visual refactor"

key_files:
  created: []
  modified:
    - lib/foglet_bbs/tui/screens/main_menu.ex
    - test/foglet_bbs/tui/screens/main_menu_test.exs

key-decisions:
  - "Single text node per nav_row (glyph + label + padding + key) defers per-glyph slot routing while keeping right-align math simple (D-08)"
  - "nav_panel_inner_width/1 defaults to outer_width=80 when terminal_size missing so existing tests without explicit size still produce a 28-col budget"
  - "split_pane min_size tuned from 24 to 18 (D-12) to ensure both boxed panels fit at 64-wide minimum"
  - "Panel headers elevated to theme.title.fg; oneliner rows remain theme.primary.fg for visual hierarchy"

patterns-established:
  - "Budget floor pattern: max(computed_width, @minimum_constant) protects against unset/pathological state"
  - "Panel helper pattern: private defp panel/N wraps box + column + header text + row list for reuse"

requirements-completed:
  - HOME-02

duration: ~10min
completed: "2026-04-25"
---

# Phase 19 Plan 02: Boxed Navigation + Oneliners Panels with Glyph Rows Summary

**Boxed Navigation panel with terminal-size-aware right-aligned glyph rows (● Boards B, ✎ Compose C, etc.) and matching boxed Oneliners panel; Welcome back line removed (D-11)**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-04-25T20:05:00Z
- **Completed:** 2026-04-25T20:18:48Z
- **Tasks:** 1 (TDD: RED + GREEN)
- **Files modified:** 2

## Accomplishments

- Replaced flat `column` menu rows with boxed `┌ Navigation ┐` panel; each destination renders as `glyph + " " + label + padding + key` with the right edge tracking `nav_panel_inner_width(state)` (terminal-size-aware, floored at 20)
- Wrapped existing oneliners column in matching boxed `┌ Oneliners ┐` panel; all pre-existing oneliner test contracts (nil, empty, single, many, long-Unicode) continue to pass unchanged
- Deleted the `Welcome back, handle.` line (D-11) and elevated both panel headers to `theme.title.fg`
- Migrated the long-handle/body oneliner width assertion from `String.length(row) <= 39` to `Foglet.TUI.TextWidth.display_width(row) <= 39` (Phase 16 width-correctness)
- Added "Phase 19 body visual" describe block: per-size budget test at 64x22 / 80x24 / 132x50, panel headers co-render test, no-welcome-line test for all roles

## Task Commits

TDD RED/GREEN cycle:

1. **RED: Phase 19 body visual failing tests** - `3b08814` (test)
2. **GREEN: Boxed panels + glyph rows implementation** - `e02f94e` (feat)

No REFACTOR commit needed (code was clean after GREEN).

## Files Created/Modified

- `lib/foglet_bbs/tui/screens/main_menu.ex` — Added `@nav_panel_min_inner_width`, `@nav_glyphs`, `nav_panel_inner_width/1`, `nav_panel/3`, `nav_row/3`, `oneliners_panel/2`; refactored `render/1` body; dropped `Welcome back` line; tuned `min_size: 18`
- `test/foglet_bbs/tui/screens/main_menu_test.exs` — Updated "render includes main menu owned text rows", "authenticated user with role :user sees Account", "rendered shell rows follow ShellVisibility"; migrated `String.length` to `TextWidth.display_width`; added "Phase 19 body visual" describe block (3 new tests)

## Decisions Made

- Single text node per `nav_row/3` (glyph + label + padding + key via `TextWidth.pad_trailing/2`) defers per-glyph slot routing while keeping right-align math tractable (D-08 documented in `@nav_glyphs` comment)
- `nav_panel_inner_width/1` defaults `outer_width` to 80 when `state.terminal_size` is nil/malformed — existing tests that don't set `terminal_size` still get a 28-col inner budget
- `split_pane min_size` reduced from 24 to 18 so both boxed panels fit at 64-wide (D-12)

## Deviations from Plan

None — plan executed exactly as written. The formatting step (auto-run `mix format`) aligned indentation on multi-line assert message strings; this is expected formatter behavior, not a logic change.

## Verification Results

- `rtk mix test test/foglet_bbs/tui/screens/main_menu_test.exs` — 45 tests, 0 failures
- `rtk mix compile --warnings-as-errors` — no warnings in `foglet_bbs` application code
- `rtk mix format --check-formatted` — both files formatted correctly
- `rg -n "@nav_glyphs"` — 2 matches (declaration + usage)
- `rg -n "@nav_panel_min_inner_width"` — 3 matches (declaration + comment + usage)
- `rg -n "@nav_panel_inner_width\b"` — 0 matches (old fixed-budget constant absent)
- `rg -n "border: :single"` — 2 matches (Navigation + Oneliners panels)
- `rg -n "Welcome back"` — 0 matches (D-11 satisfied)
- `rg -n "defp nav_panel\b"` — 1 match
- `rg -n "defp nav_row"` — 1 match
- `rg -n "defp oneliners_panel"` — 1 match
- `rg -nE "fg:\s*:(red|green|blue|...)"` — 0 matches (no hardcoded color atoms)
- `rg -n "min_size: 18"` — 1 match
- `rg -n "String.length(row)"` — 0 matches (migration complete)
- `rg -n "TextWidth.display_width(row)"` — 2 matches (long-handle test + per-size budget test)

## TDD Gate Compliance

RED gate: commit `3b08814` — 5 new tests failing (Welcome back still present; glyph rows absent; Navigation header absent)

GREEN gate: commit `e02f94e` — all 45 tests passing

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns, or schema changes introduced. Threat mitigations from the plan's threat register:

- **T-19-05** (display width drift): all width math routes through `TextWidth.display_width/1` and `TextWidth.pad_trailing/2`; per-row computed-width-budget test asserts `<= nav_panel_inner_width(state)` at each canonical size for every row x every role.
- **T-19-06** (oneliner overflow): existing `clip/2` helper unchanged; the long-handle/body test now uses `TextWidth.display_width(row) <= 39` (Phase 16 migration complete).
- **T-19-07** (theme bypass via hardcoded atoms): `rg -nE "fg:\s*:(red|...)"` returns zero in `main_menu.ex`. All slot accesses route through `theme.<slot>.fg`.

## Known Stubs

None — all data flows are wired through `visible_destinations/1` and `oneliner_rows/2`. No placeholder text beyond the existing "No oneliners yet." empty-state message (which is correct behavior, not a stub).

## Self-Check: PASSED

- `lib/foglet_bbs/tui/screens/main_menu.ex` — FOUND
- `test/foglet_bbs/tui/screens/main_menu_test.exs` — FOUND
- `.planning/phases/19-main-menu-dashboard/19-02-SUMMARY.md` — FOUND (this file)
- commit `3b08814` (RED gate) — FOUND
- commit `e02f94e` (GREEN gate) — FOUND
- 45 tests, 0 failures — CONFIRMED

## Next Phase Readiness

- Plan 03 (size-contract assertions) can now consume `nav_panel_inner_width/1` and the `@nav_panel_min_inner_width` constant directly via the public module or by mirroring the math (as the "Phase 19 body visual" test already does)
- The `nav_row/3` single-text-node shape is clean for positioned-render testing in Plan 03
- Per-glyph slot routing (D-08) remains deferred; the inline comment in `@nav_glyphs` documents the upgrade path

---
*Phase: 19-main-menu-dashboard*
*Completed: 2026-04-25*
