---
phase: 19-main-menu-dashboard
verified: 2026-04-25T15:42:00Z
status: human_needed
score: 4/4 must-haves verified
overrides_applied: 0
re_verification: false
human_verification:
  - test: "Navigate the main menu at 64x22 over a real SSH session — press B, C, A, Q; confirm each hotkey still works."
    expected: "Each destination key navigates immediately without requiring selection-cursor movement. The Navigation panel renders two boxed panels side by side, not stacked. Key letters are right-aligned against the panel edge."
    why_human: "The Raxol layout engine is exercised by positioned-render tests, but real SSH rendering depends on terminal emulator cell-width interpretation of Unicode glyphs (●, ✎, ◇, ⚑, ▣, ↯). The panel right-align math can pass CI while still producing misaligned columns in terminals that measure glyph width differently."
  - test: "Post an oneliner and observe the main menu refreshes with the new entry visible without page reload."
    expected: "Oneliners panel shows the new entry in the > @handle  body row format within the 5-row display limit."
    why_human: "PubSub subscription wiring is not exercised by unit or layout-smoke tests — only live SSH session with a connected user confirms real-time update."
---

# Phase 19: Main Menu Dashboard Verification Report

**Phase Goal:** The main menu becomes a selectable, social BBS home screen while preserving direct hotkeys.
**Verified:** 2026-04-25T15:42:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Users can navigate main-menu destinations with selection keys and existing direct hotkeys. | VERIFIED | `handle_key/2` clauses for B/C/A/M/S/O/H/Q/Up/Down/Enter all present and tested (45 tests, 0 failures). `visible_destinations/1` returns ordered destination list; direct hotkeys unchanged. |
| 2 | Role-gated destinations remain absent when unavailable. | VERIFIED | `command_visible?/3` gates A/M/S through `ShellVisibility` predicates. Tests lock: anonymous sees B/C/Q only; :user adds A; :mod adds M; :sysop adds S. `MapSet.disjoint?/2` property test covers all role × oneliner-state combos. |
| 3 | Users see useful session/activity context such as unread counts, boards, oneliners, or moderation count when available. | VERIFIED | Boxed Oneliners panel renders up to 5 oneliner rows (`@oneliner_display_limit 5`). Empty state shows "No oneliners yet." Tests cover nil/empty/single/many/long-Unicode/CJK fixtures. Activity panel (unread counts, boards, moderation count) is explicitly deferred per D-07 — see Deferred Items below. |
| 4 | The layout remains navigable at 64x22, reaches the intended compact dashboard rhythm around 80x24, and uses side-by-side panels only when width permits. | VERIFIED | `split_pane(direction: :horizontal, ratio: {2, 3}, min_size: 18)` plus `nav_panel_inner_width/1` with `@nav_panel_min_inner_width 20` floor. Phase 19 size-contract block in `layout_smoke_test.exs` asserts: viewport-bound, side-by-side (nav_header.x < oneliners_header.x), per-y range-overlap, and oneliner-in-right-panel containment at [{64,22},{80,24},{132,50}]. 23 smoke tests, 0 failures. |

**Score:** 4/4 truths verified

### Deferred Items

Items not yet met but explicitly addressed in later milestone phases.

| # | Item | Addressed In | Evidence |
|---|------|-------------|----------|
| 1 | Activity panel (unread counts across boards, active session count, pinned thread updates) | Phase 20 | D-07 in 19-CONTEXT.md explicitly removes the Activity panel from Phase 19 scope. SCREENS.md sketch shows it as a future right-panel widget. Phase 20 goal covers rich rows and thread flow including unread state. |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/foglet_bbs/tui/screens/main_menu.ex` | Single `@main_menu_commands` list; `visible_destinations/1`; `visible_actions/1`; `nav_panel/3`; `nav_row/3`; `nav_panel_inner_width/1`; `oneliners_panel/2` | VERIFIED | All 7 items confirmed present in file. 439 lines. No stubs. |
| `test/foglet_bbs/tui/screens/main_menu_test.exs` | "Phase 19 destinations vs. actions split" describe block; "Phase 19 body visual" describe block; 45 tests total | VERIFIED | 45 tests, 0 failures. Both describe blocks present with correct test counts. |
| `test/foglet_bbs/tui/layout_smoke_test.exs` | "Phase 19 Main Menu size contracts" describe block; CJK fixture; range-overlap assertions; oneliner containment | VERIFIED | 23 tests, 0 failures. All four assertion types confirmed present. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `MainMenu.render/1` | `visible_destinations/1` | `destinations = visible_destinations(user)` at line 91 | WIRED | Confirmed in source. |
| `MainMenu.render/1` | `visible_actions/1` | `actions = visible_actions(state)` at line 92 | WIRED | Confirmed in source. Passed to `ScreenFrame.render/4`. |
| `MainMenu.render/1` | `nav_panel/3` | `menu_panel = nav_panel(destinations, theme, inner_width)` at line 95 | WIRED | Confirmed in source. |
| `MainMenu.render/1` | `nav_panel_inner_width/1` | `inner_width = nav_panel_inner_width(state)` at line 94 | WIRED | Confirmed in source. |
| `nav_row/3` | `TextWidth.pad_trailing/2` + `TextWidth.display_width/1` | Right-align math at lines 311-315 | WIRED | Both TextWidth calls confirmed in `nav_row/3`. |
| `visible_destinations/1` + `visible_actions/1` | `@main_menu_commands` | `Enum.filter(&(&1.kind == :destination/action))` at lines 215, 235 | WIRED | 4 matches for `@main_menu_commands` in source (declaration + 2 filter call sites + 1 doc reference). |
| `handle_key/2` | `ShellVisibility` predicates | `ShellVisibility.account_visible?`, `moderation_visible?`, `sysop_visible?` in A/M/S clauses | WIRED | Confirmed in source at lines 157, 168, 180. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `MainMenu.render/1` | `destinations` | `visible_destinations(user)` filters `@main_menu_commands` | Yes — compile-time list, role-filtered per call | FLOWING |
| `MainMenu.render/1` | `actions` | `visible_actions(state)` filters `@main_menu_commands` + `Bodyguard.permit?` | Yes — state-gated at render time | FLOWING |
| `oneliners_panel/2` | `recent_oneliners` | `Map.get(state, :recent_oneliners, [])` via `visible_oneliners/1` | Yes — pulled from `App` state populated by `{:load_recent_oneliners}` command | FLOWING |
| `nav_row/3` | glyph | `Map.fetch!(@nav_glyphs, key)` | Yes — compile-time map lookup. NOTE: `Map.fetch!` will crash screen if `@nav_glyphs` and `@main_menu_commands` drift (WR-01, advisory). | FLOWING (with WR-01 caveat) |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| `visible_destinations/1` returns B/C/Q for nil user | `rtk mix test ... --only "anonymous returns B"` | 45 tests, 0 failures | PASS |
| Navigation glyph rows render with right-aligned key | `rtk mix test ... --only "Phase 19 body visual"` | 45 tests, 0 failures | PASS |
| Side-by-side panels at 64x22 | `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` | 23 tests, 0 failures | PASS |
| CJK oneliner clipped and contained in right panel | Part of layout_smoke_test.exs | 23 tests, 0 failures | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| HOME-01 | 19-01-PLAN.md | User can navigate main-menu destinations with selection keys while existing direct hotkeys continue to work. | SATISFIED | Single `@main_menu_commands` list with `:kind` tag; `visible_destinations/1` returns ordered role-gated list; `handle_key/2` hotkeys unchanged. 11 new tests in "Phase 19 destinations vs. actions split" describe block. |
| HOME-02 | 19-02-PLAN.md | Home shows useful session and BBS activity context, such as unread counts, boards, oneliners, or moderation counts when available. | SATISFIED (partial) | Boxed Oneliners panel renders up to 5 live oneliner rows with CJK/Unicode clipping. Activity panel (unread counts, moderation count) deferred to later phase per D-07. Requirement text says "such as... oneliners... when available" — oneliners are implemented. |
| HOME-03 | 19-03-PLAN.md | Home remains navigable at 64x22, reaches the intended compact dashboard rhythm around 80x24, and uses side-by-side panels only when width permits. | SATISFIED | `split_pane(min_size: 18)` + `nav_panel_inner_width/1` + Phase 19 size-contract block asserts at 64x22/80x24/132x50. |

No orphaned requirements: all three HOME-01, HOME-02, HOME-03 are claimed by plans and verified.

### Anti-Patterns Found

| File | Location | Pattern | Severity | Impact |
|------|----------|---------|----------|--------|
| `main_menu.ex` | Line 310 (`nav_row/3`) | `Map.fetch!(@nav_glyphs, key)` — crash on glyph map drift | Warning (WR-01 from 19-REVIEW.md) | Screen render crash if a new destination is added to `@main_menu_commands` without a matching `@nav_glyphs` entry. Advisory — no current gap. |
| `main_menu.ex` | Lines 34-39 (comment) | `@oneliner_body_limit` comment claims "exact fit at 64-wide" but right-panel inner width is ~34 cols, not 37 | Warning (WR-02 from 19-REVIEW.md) | Comment inaccuracy; size-contract test does not assert right-edge containment within panel, only viewport bound. Advisory. |
| `main_menu.ex` + `main_menu_test.exs` | Lines 283-296 / 450-453 | Inner-width allocation math duplicated between production helper and test | Warning (WR-03 from 19-REVIEW.md) | Silent desync risk if either constant is changed. Advisory. |
| `main_menu.ex` | Lines 277-280 | `command_priority/2` clause for key in `["A","M","S"]` is unreachable | Info (IN-01 from 19-REVIEW.md) | Dead code, no correctness impact. |
| `main_menu_test.exs` | Lines 426-427 | `role_label_to_role/1` helper obscures its own intent | Info (IN-05 from 19-REVIEW.md) | Test readability only. |

All 3 warnings and 5 info items carried forward from 19-REVIEW.md. No critical issues. No new anti-patterns found beyond what 19-REVIEW.md identified.

### Human Verification Required

### 1. Real SSH Terminal — Hotkeys and Panel Rendering

**Test:** SSH into a running Foglet instance as a `:user` role account on a terminal that is 64x22, then 80x24. Press B, C, A, Q. Also use Up/Down to scroll oneliners.

**Expected:** Each destination hotkey navigates immediately (no selection-cursor movement required). Both Navigation and Oneliners panels render as separate boxed sections side by side. The glyph + label + right-aligned key column aligns correctly at the panel right edge — key letters should not float mid-panel.

**Why human:** Unicode glyph display width (●, ✎, ◇, ⚑, ▣, ↯) depends on the terminal emulator's cell-width table. `TextWidth.display_width/1` uses a library table that may not match every terminal. Right-align padding math can pass CI while still producing off-by-one column drift in specific terminals.

### 2. Live Oneliner PubSub Update

**Test:** With two SSH sessions open to the same running instance, post a new oneliner from session B and observe session A's main menu.

**Expected:** Session A's Oneliners panel refreshes with the new entry visible in `> @handle  body` format, without requiring any keypress or navigation.

**Why human:** PubSub subscription wiring in `Foglet.TUI.App` routes `{:recent_oneliners_updated, oneliners}` to screens. Unit tests and layout-smoke tests do not exercise this live subscription path — only a live session with a PubSub broadcast confirms end-to-end update behavior.

### Gaps Summary

No automated gaps found. All four roadmap success criteria are verified by test evidence. The two human verification items are UX/live-behavior checks that cannot be confirmed programmatically.

The three advisory warnings from 19-REVIEW.md (WR-01: `Map.fetch!` glyph drift risk; WR-02: comment math inaccuracy for right-panel inner width; WR-03: duplicated inner-width math) are noted but do not block goal achievement — they are improvement opportunities for a future pass.

---

_Verified: 2026-04-25T15:42:00Z_
_Verifier: Claude (gsd-verifier)_
