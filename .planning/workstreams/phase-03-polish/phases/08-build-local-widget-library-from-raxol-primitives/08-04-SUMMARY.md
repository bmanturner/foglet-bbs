---
phase: 08
plan: "04"
subsystem: tui-widgets
tags: [raxol, widget, list, stateful, search, pagination, multi-select, pattern-2]
dependency_graph:
  requires:
    - lib/foglet_bbs/tui/widgets/list/selection_list.ex
    - lib/foglet_bbs/tui/theme.ex
    - vendor/raxol/lib/raxol/ui/components/input/select_list.ex
  provides:
    - lib/foglet_bbs/tui/widgets/list/smart_list.ex
  affects:
    - lib/foglet_bbs/tui/widgets/README.md (to be updated in 08-05)
tech_stack:
  added: []
  patterns:
    - "Pattern 2: stateful facade over Raxol component (init/handle_event/render triplet)"
    - "SelectList event translation: %{key: :char, char: c} → %{key: c} for SelectList compatibility"
    - "Multi-select confirmation reads before_rs.selected_indices (Enter toggles in SelectList)"
key_files:
  created:
    - lib/foglet_bbs/tui/widgets/list/smart_list.ex
    - test/foglet_bbs/tui/widgets/list/smart_list_test.exs
  modified: []
decisions:
  - "translate_event_for_select_list/1: SelectList expects raw char string as key (e.g. %{key: \"a\"}), not the :char atom — translated before wrapping in %Event{}"
  - "Multi-select Enter uses before_rs.selected_indices: SelectList toggles the focused item on Enter, so reading after_rs would give the wrong (post-toggle) selection set"
  - "page_for/1 computes logical page via div(focused_index, page_size): SelectList moves focused_index, not current_page field, on PageUp/PageDown"
metrics:
  duration: "~20 minutes"
  completed: "2026-04-21"
  tasks_completed: 1
  files_created: 2
---

# Phase 08 Plan 04: List.SmartList Summary

**One-liner:** Pattern 2 stateful facade over `Raxol.UI.Components.Input.SelectList` with search, pagination, and multi-select — establishing the `{:item_selected, v}` / `{:items_selected, [v]}` / `{:search_changed, t}` / `{:page_changed, n}` action atom vocabulary.

## What Was Built

`Foglet.TUI.Widgets.List.SmartList` — the stateful sibling of `List.SelectionList`. Wraps `Raxol.UI.Components.Input.SelectList` following the D-14 Pattern 2 triplet: `init/1` + `handle_event/2` + `render/2` (no process).

### Files Created

| File | Description |
|------|-------------|
| `lib/foglet_bbs/tui/widgets/list/smart_list.ex` | Widget module: Pattern 2 delegation to SelectList + action derivation |
| `test/foglet_bbs/tui/widgets/list/smart_list_test.exs` | 15 tests: init, render smoke, handle_event state transitions, theme hygiene, alt-theme differential |

## Requirements Closed

- **REQ-W-01** — stateful list widget with search/pagination/multi-select

## Action Atom Vocabulary Added

| Atom | Trigger |
|------|---------|
| `{:item_selected, value}` | Enter in single-select mode (focused item) |
| `{:items_selected, [values]}` | Enter in multi-select mode (accumulated selection) |
| `{:search_changed, term}` | Character input changes search_buffer (enable_search: true) |
| `{:page_changed, page_index}` | PageUp/PageDown crosses a page boundary |
| `nil` | Navigation key with no semantic action |

## Theme Slots Consumed

| Slot | Used for |
|------|----------|
| `theme.border.fg` | Outer box border in render/2 |
| `theme.unselected.fg` | Option text (unselected row) |
| `theme.selected.fg` + `theme.selected.bg` | Selected/focused option highlight |
| `theme.accent.fg` | Search prompt styling |
| `theme.dim.fg` | Pagination info styling |

## Raxol SelectList State Fields Verified

During implementation, confirmed actual field names from `vendor/raxol/lib/raxol/ui/components/input/select_list.ex`:

| Field | Type | RESEARCH.md assumption | Actual |
|-------|------|----------------------|--------|
| `focused_index` | integer | correct | correct |
| `selected_indices` | MapSet.t() | correct | correct |
| `search_buffer` | String.t() | correct | correct |
| `current_page` | integer | present | present (but NOT updated by PageUp/PageDown navigation — `focused_index` is) |
| `page_size` | integer | correct | correct |

**RESEARCH.md Assumption Log update:** `current_page` exists in the state but is NOT mutated by `Navigation.handle_page_down/1` / `handle_page_up/1`. Those functions move `focused_index` by `visible_items` steps. Page boundary detection in `derive_action` was implemented via `page_for/1 = div(focused_index, page_size)` rather than comparing `current_page` fields directly.

## Key Implementation Decisions

### 1. Character input translation

SelectList's `classify_key/2` calls `single_character?(key)` which checks `is_binary(key) and byte_size(key) == 1`. Our callers pass `%{key: :char, char: "a"}` (Raxol canonical form). The private `translate_event_for_select_list/1` remaps the event to `%{key: "a", char: "a"}` before wrapping in `%Event{}`, making the character reach SelectList's search handler.

### 2. Multi-select Enter semantics

SelectList's `handle_event` for `:enter` calls `Selection.update_selection_state` which toggles the focused index in multi-select mode. Reading `after_rs.selected_indices` on Enter would give the post-toggle set (focused item removed). `derive_action` reads `before_rs.selected_indices` to capture the user's accumulated selection before the Enter toggle.

### 3. Page change detection

`Navigation.handle_page_down/1` mutates `focused_index` by `visible_items` steps, not `current_page`. The `page_for/1` helper computes logical page as `div(focused_index, page_size)` and compares before/after to detect boundary crossings.

## Test Count

15 tests across 4 `describe` blocks:
- `init/1` — 2 tests
- `render/2 — smoke (D-18)` — 2 tests
- `handle_event/2 (D-14)` — 9 tests (navigation, selection, search, multi-select, pagination, purity)
- `render/2 — theme hygiene (D-18)` — 2 tests (hardcoded atom refute + alt-theme differential)

## Verification Results

```
mix test test/foglet_bbs/tui/widgets/list/smart_list_test.exs   → 15 tests, 0 failures
mix test test/foglet_bbs/tui/widgets/list/                       → 30 tests, 0 failures
mix compile --warnings-as-errors                                  → clean (raxol vendor warnings only)
mix format --check-formatted                                      → clean
mix credo --strict (smart_list.ex)                               → no issues found
```

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] SelectList character input requires raw char string as key**
- **Found during:** Task 1 (first test run)
- **Issue:** `derive_action` for `%{key: :char}` events was not triggering search buffer update in SelectList because SelectList's `single_character?/1` checks `is_binary(key)` — the `:char` atom fails that guard
- **Fix:** Added private `translate_event_for_select_list/1` that converts `%{key: :char, char: c}` to `%{key: c}` before wrapping in `%Raxol.Core.Events.Event{}`
- **Files modified:** `lib/foglet_bbs/tui/widgets/list/smart_list.ex`
- **Commit:** ba0e25e

**2. [Rule 1 - Bug] Multi-select Enter read wrong raxol_state snapshot**
- **Found during:** Task 1 (first test run)
- **Issue:** `derive_action` for `{:enter, multiple: true}` read `after_rs.selected_indices` — but SelectList toggles the focused item on Enter, so the post-toggle snapshot had item 0 removed rather than included
- **Fix:** Changed to read `before_rs.selected_indices` to capture the accumulated selection set before the confirmation toggle
- **Files modified:** `lib/foglet_bbs/tui/widgets/list/smart_list.ex`
- **Commit:** ba0e25e (same commit — both fixes resolved before the commit)

## Known Stubs

None. All data flows are wired: options pass through SelectList, search buffer is live, selections derive from real MapSet state.

## Threat Flags

No new network endpoints, auth paths, file access patterns, or schema changes introduced. Widget is purely in-memory and stateless across requests.

## Self-Check: PASSED

- `lib/foglet_bbs/tui/widgets/list/smart_list.ex` — FOUND
- `test/foglet_bbs/tui/widgets/list/smart_list_test.exs` — FOUND
- Commit `ba0e25e` — FOUND in git log
- 15 tests, 0 failures — CONFIRMED
