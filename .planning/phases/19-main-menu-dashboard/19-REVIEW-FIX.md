---
phase: 19-main-menu-dashboard
fixed_at: 2026-04-25T20:54:17Z
review_path: .planning/phases/19-main-menu-dashboard/19-REVIEW.md
iteration: 1
findings_in_scope: 8
fixed: 8
skipped: 0
status: all_fixed
---

# Phase 19: Code Review Fix Report

**Fixed at:** 2026-04-25T20:54:17Z
**Source review:** .planning/phases/19-main-menu-dashboard/19-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 8
- Fixed: 8
- Skipped: 0

## Fixed Issues

### WR-01: `Map.fetch!/2` on `@nav_glyphs` panics the whole screen if a destination is added without a glyph

**Files modified:** `lib/foglet_bbs/tui/screens/main_menu.ex`
**Commit:** 654915c
**Applied fix:** Folded destination glyphs into the canonical `@main_menu_commands` descriptors and rendered nav rows from filtered descriptor maps while preserving the public `visible_destinations/1` tuple contract.

### WR-02: `@oneliner_body_limit` comment math is inconsistent with the right-panel inner width

**Files modified:** `lib/foglet_bbs/tui/screens/main_menu.ex`, `test/foglet_bbs/tui/layout_smoke_test.exs`
**Commit:** d70e577
**Applied fix:** Reduced the oneliner body display limit to keep selected rows within the 64-column right-panel inner width and added right-edge containment assertions for normal and CJK oneliner layout smoke tests.

### WR-03: Inner-width allocation math is duplicated between production and tests

**Files modified:** `lib/foglet_bbs/tui/screens/main_menu.ex`, `test/foglet_bbs/tui/screens/main_menu_test.exs`
**Commit:** 61237eb
**Applied fix:** Added a `@doc false` test-visible wrapper around `nav_panel_inner_width/1` and updated the navigation row budget test to call it directly instead of duplicating allocation constants.

### IN-01: `command_priority/2` clauses for "A", "M", "S" are unreachable

**Files modified:** `lib/foglet_bbs/tui/screens/main_menu.ex`
**Commit:** 0360b00
**Applied fix:** Removed the unreachable destination-key priority clause after confirming command priorities only apply to action entries.

### IN-02: `command_priority/2`'s `priority` parameter is effectively unused for "H" and "O"

**Files modified:** `lib/foglet_bbs/tui/screens/main_menu.ex`
**Commit:** 0360b00
**Applied fix:** Replaced threaded group priority arguments with fixed action priorities: `H` sorts first, `O` later, and remaining action rows default to the select priority.

### IN-03: `visible_destinations/1` builds a state shim that is fragile against future visibility tags

**Files modified:** `lib/foglet_bbs/tui/screens/main_menu.ex`
**Commit:** 0360b00
**Applied fix:** Split destination visibility from state-aware action visibility, removing the synthetic state shim from destination filtering.

### IN-04: `clamp/3` shadows `Kernel.max/2` and `Kernel.min/2` via implicit imports

**Files modified:** `lib/foglet_bbs/tui/screens/main_menu.ex`
**Commit:** 0360b00
**Applied fix:** Renamed clamp bounds to `lower` and `upper` and qualified the `Kernel.max/2` and `Kernel.min/2` calls.

### IN-05: `role_label_to_role/1` test helper masks the test's own intent

**Files modified:** `test/foglet_bbs/tui/screens/main_menu_test.exs`
**Commit:** 0360b00
**Applied fix:** Added an explicit anonymous `build_state(nil)` branch and removed the role-label shim from the disjointness property test.

---

_Fixed: 2026-04-25T20:54:17Z_
_Fixer: the agent (gsd-code-fixer)_
_Iteration: 1_
