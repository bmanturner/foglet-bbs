---
phase: 19-main-menu-dashboard
plan: "01"
subsystem: tui-screens
tags:
  - main-menu
  - data-layer
  - single-source-of-truth
  - destinations-actions-split
  - role-gating
  - tdd

dependency_graph:
  requires:
    - "Phase 18: Chrome V2 (ScreenFrame.render/4 command-bar contract)"
    - "ShellVisibility predicates (account_visible?/1, moderation_visible?/1, sysop_visible?/1)"
    - "Foglet.Authorization Bodyguard policy (:hide_oneliner in @mod_site_actions)"
  provides:
    - "MainMenu.visible_destinations/1 — public, returns [{key, label}] filtered by role"
    - "MainMenu.visible_actions/1 — public, returns command-bar groups filtered by role/state"
    - "@main_menu_commands — single canonical descriptor list with :kind and :visibility tags"
  affects:
    - "Plan 02 (Navigation/Oneliners boxed panels) — consumes visible_destinations/1 and visible_actions/1"
    - "Plan 03 (size-contract assertions) — structural data layer is now stable"

tech_stack:
  added: []
  patterns:
    - "Module-attribute descriptor list with :kind tag as single source of truth (D-01)"
    - "Private command_visible?/3 gate dispatching on :visibility atom tag"
    - "Public data-layer functions (visible_destinations/1, visible_actions/1) for testability"

key_files:
  created: []
  modified:
    - lib/foglet_bbs/tui/screens/main_menu.ex
    - test/foglet_bbs/tui/screens/main_menu_test.exs

decisions:
  - "A/M/S removed from command bar: they are pure destinations; only O, H, ↑/↓ are actions (D-01)"
  - "visible_destinations/1 and visible_actions/1 made public for testability (consistent with ShellVisibility convention)"
  - "Existing 'rendered shell rows and command labels follow ShellVisibility' test narrowed to rows-only (command? check removed) because D-01 removes A/M/S from command bar"

metrics:
  duration: "~6 minutes"
  completed_date: "2026-04-25"
  tasks_completed: 1
  tasks_total: 1
  files_created: 0
  files_modified: 2
---

# Phase 19 Plan 01: MainMenu Data Layer — Single-Source-of-Truth Split Summary

Single canonical `@main_menu_commands` descriptor list with `:kind` tag introduced; `visible_destinations/1` and `visible_actions/1` derived by filtering it so destinations and actions share a data source and cannot drift.

## What Was Built

Refactored `Foglet.TUI.Screens.MainMenu` to implement the D-01 single-source-of-truth mandate. The structural realization: a single `@main_menu_commands` module attribute where every entry carries a `:kind` (`:destination` | `:action`) and a `:visibility` atom. Two public functions — `visible_destinations/1` and `visible_actions/1` — filter this one list. Because they share a data source, destinations and actions cannot drift independently.

### Files Modified

**`lib/foglet_bbs/tui/screens/main_menu.ex`**

- Replaced `@base_items`, `@base_keys`, `@oneliner_item`, `@oneliner_key`, `@logout_item`, `@logout_key` with a single `@main_menu_commands` list (9 entries: 6 destinations, 3 actions).
- Added private `command_visible?/3` dispatching on `:visibility` atom tag using `ShellVisibility` predicates and `selected_hideable_oneliner/1` for the `:hide_oneliner_policy` case.
- Added public `visible_destinations/1` — filters `@main_menu_commands` for `:destination` entries, returns `[{key, label}]` tuples for the body builder.
- Added public `visible_actions/1` — filters `@main_menu_commands` for `:action` entries, groups into "Actions" (H + O) and "Select" (↑/↓) for `ScreenFrame.render/4`.
- Deleted `visible_menu_items/1` and `visible_menu_keys/1`.
- Updated `render/1` to call `visible_destinations(user)` and `visible_actions(state)`.
- Shortened labels per D-08: "Browse Boards" → "Boards", "Compose New Thread" → "Compose".

**`test/foglet_bbs/tui/screens/main_menu_test.exs`**

- Updated label assertions on existing tests: `"  [B] Browse Boards"` → `"  [B] Boards"`, `"  [C] Compose New Thread"` → `"  [C] Compose"`.
- Added `"Phase 19 destinations vs. actions split"` describe block with 11 new tests:
  - 4 tests: `visible_destinations/1` role-gating (anonymous, :user, :mod, :sysop)
  - 5 tests: `visible_actions/1` visibility (no oneliners → O only; oneliners → O+↑/↓; mod/sysop with hideable → H; :user with hideable → no H)
  - 1 test: literal-keys non-duplication sweep (B/C/A/M/S/Q never in actions for any role × oneliner state)
  - 1 test: structural disjointness as a data property (`MapSet.disjoint?/2` for all role × oneliner combinations)
- Added `role_label_to_role/1` helper for the disjointness property test.
- Narrowed existing "rendered shell rows and command labels follow ShellVisibility" test to rows-only (the `command?` assertion was testing old behavior where A/M/S appeared in the command bar; D-01 removes them from command bar).

## TDD Gate Compliance

RED gate: commit `7891bfc` — 11 new tests failing (`UndefinedFunctionError` for `visible_destinations/1` and `visible_actions/1`).

GREEN gate: commit `a6b26a0` — all 42 tests passing (31 existing + 11 new).

No REFACTOR commit needed (code was clean after GREEN).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Existing "command labels follow ShellVisibility" test checked obsolete behavior**

- **Found during:** Task 1 GREEN phase
- **Issue:** The pre-Phase-19 test at line 376 checked that A/M/S keys appeared in the command bar rendered text. D-01 explicitly removes A/M/S from the command bar (they are now body destinations only). The test was asserting behavior that the plan intentionally eliminates.
- **Fix:** Narrowed the test to check menu row visibility only (the `command?` assertion was dropped); added a clear code comment explaining the D-01 rationale.
- **Files modified:** `test/foglet_bbs/tui/screens/main_menu_test.exs` (line 368)
- **Commits:** `a6b26a0`

The plan's `<action>` section listed only lines 234-235 as requiring test updates, but the test at line 376 also needed updating because D-01 changes the command bar composition. This is a correct application of the design intent, not a regression.

## Verification Results

- `rtk mix test test/foglet_bbs/tui/screens/main_menu_test.exs` — 42 tests, 0 failures
- `rtk mix compile --warnings-as-errors` — no warnings in `foglet_bbs` application code
- `rtk mix format --check-formatted` — both files formatted correctly
- `rg -n "@main_menu_commands" main_menu.ex` — 4 matches (declaration + 2 filter call sites + 1 doc reference)
- `rg -n "kind: :destination"` — 6 matches (6 destination entries)
- `rg -n "kind: :action"` — 3 matches (3 action entries)
- `rg -n "visible_menu_items"` — 0 matches (deleted)
- `rg -n "visible_menu_keys"` — 0 matches (deleted)
- `rg -n "@base_items"` — 0 matches (deleted)
- `rg -n "@base_keys"` — 0 matches (deleted)
- `rg -n "Phase 19 destinations vs. actions split"` — 1 match (new describe block present)
- `rg -n "MapSet.disjoint"` — 1 match (structural disjointness assertion present)
- `rg -n "command bar non-duplication"` — 1 match (literal-keys sweep present)
- `rg -n "anonymous still sees Compose"` — 1 match (anonymous-C destination test present)
- `rg -n "Browse Boards"` — 0 matches (label shortened per D-08)
- `rg -n "Compose New Thread"` — 0 matches (label shortened per D-08)

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns, or schema changes introduced. The refactor touches only the TUI data layer; all role gating continues to route through `ShellVisibility` predicates and `Bodyguard.permit?/4`. The threat register mitigations T-19-01 through T-19-03 are all addressed:

- **T-19-01** (information disclosure): `visible_destinations/1` gates anonymous access through `ShellVisibility`; anonymous tests lock B/C/Q only.
- **T-19-02** (elevation of privilege): `command_visible?(:hide_oneliner_policy, ...)` routes through `selected_hideable_oneliner/1` → `Bodyguard.permit?/4`; negative test locks :user from H.
- **T-19-03** (tampering via drift): D-01 single `@main_menu_commands` list makes drift a compile-time impossibility; `MapSet.disjoint?/2` test catches any future misclassification.

## Self-Check: PASSED

- `lib/foglet_bbs/tui/screens/main_menu.ex` — FOUND
- `test/foglet_bbs/tui/screens/main_menu_test.exs` — FOUND
- `.planning/phases/19-main-menu-dashboard/19-01-SUMMARY.md` — FOUND
- commit `7891bfc` (RED gate) — FOUND
- commit `a6b26a0` (GREEN gate) — FOUND
- 42 tests, 0 failures — CONFIRMED
