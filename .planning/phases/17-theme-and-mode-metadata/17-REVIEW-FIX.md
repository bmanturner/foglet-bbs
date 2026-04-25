---
phase: 17-theme-and-mode-metadata
fixed_at: 2026-04-25T19:05:00Z
review_path: .planning/phases/17-theme-and-mode-metadata/17-REVIEW.md
iteration: 1
findings_in_scope: 2
fixed: 2
skipped: 0
status: all_fixed
---

# Phase 17: Code Review Fix Report

**Fixed at:** 2026-04-25T19:05:00Z
**Source review:** .planning/phases/17-theme-and-mode-metadata/17-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 2
- Fixed: 2
- Skipped: 0

## Fixed Issues

### WR-01: Auto-generated menu IDs collide for duplicate labels

**Files modified:** `lib/foglet_bbs/tui/widgets/input/menu.ex`, `test/foglet_bbs/tui/widgets/input/menu_test.exs`
**Commit:** 9c76147
**Applied fix:** Replaced the single-arity recursive `normalize_items/2` and `normalize_item/2` helpers with index-aware variants. Each list of items is now traversed via `Enum.with_index/1`, and `normalize_item/3` builds the auto-id segment as `"#{index}:#{label}"` rather than the bare `label`. Two sibling items sharing a label now resolve to distinct ids (e.g. `"auto:0:Open"` vs `"auto:1:Open"`), keeping Raxol cursor state, submenu `open_path`, and `{:menu_action, id}` unambiguous. Updated the existing nested-id test to reflect the new format and added three new tests covering: duplicate sibling labels, duplicate labels under different parents, and explicit `:id` still winning over the indexed default. Updated the `@doc` for `normalize_items/1` to describe the new format and reference both WR-03 (deterministic ids) and WR-01 (sibling disambiguation).

### WR-02: Out-of-range tab active index renders no selected tab

**Files modified:** `lib/foglet_bbs/tui/widgets/input/tabs.ex`, `test/foglet_bbs/tui/widgets/input/tabs_test.exs`
**Commit:** 739f12f
**Applied fix:** `init/1` now pipes the caller-provided `:active` through a new private `clamp_active_index/2` helper before passing it to `RaxolTabs.init/1`. The clamp returns `0` for an empty tab list, `0` for negatives, and `min(idx, length(tabs) - 1)` otherwise — mirroring the defensive shape already used by `Foglet.TUI.Widgets.Input.RadioGroup.clamp_index/2` and preserving the existing default (`0`). Added a comment block above the helper that explains the failure mode (`render_tab/4` only marks `idx == active_index` selected) and the cross-widget rationale. Added four tests: above-range clamps to last with the expected indicator placement, negative clamps to first, empty tab list with non-zero `:active` falls back to `0`, and clamped state still renders exactly one indicator glyph.

---

_Fixed: 2026-04-25T19:05:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
