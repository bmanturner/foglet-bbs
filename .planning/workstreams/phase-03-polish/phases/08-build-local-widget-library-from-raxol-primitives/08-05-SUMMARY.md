---
phase: "08"
plan: "05"
subsystem: tui-widgets
tags: [raxol, widget, docs, readme, catalog, smoke, precommit, d-12, d-18, req-w-12, req-w-13]
dependency_graph:
  requires:
    - 08-01 (Input.Button, Input.Checkbox, Input.RadioGroup)
    - 08-02 (Input.TextInput, Input.Tabs, Input.Menu)
    - 08-03 (Display.Table, Display.Tree, Display.Progress, Progress.Spinner)
    - 08-04 (List.SmartList)
  provides:
    - lib/foglet_bbs/tui/widgets/README.md (D-12 widget catalog index)
    - test/foglet_bbs/tui/widgets/catalog_smoke_test.exs (cross-bucket integration smoke)
  affects:
    - Any developer onboarding to the TUI widget layer (README discoverability)
    - Regression detection for combined-render theme hygiene (smoke test)
tech_stack:
  added: []
  patterns:
    - "D-12 discoverability: Markdown table per bucket with relative .ex file links"
    - "Cross-bucket render_catalog/1: single helper renders all 11 widgets for combined inspection"
    - "~w() sigil + for-loop: cleaner than inline refute per atom for 8 color atoms"
key_files:
  created:
    - lib/foglet_bbs/tui/widgets/README.md
    - test/foglet_bbs/tui/widgets/catalog_smoke_test.exs
  modified:
    - lib/foglet_bbs/tui/widgets/display/table.ex
decisions:
  - "Table.normalize_column/1 now accepts :key as alias for :id — plan spec uses %{key: :name} column maps but Raxol Table.create_cells/7 reads column.id; normalize_column/1 now derives :id from :key when :id is absent"
  - "Color atom refute uses ~w() sigil + for loop instead of per-atom inline refute — functionally equivalent, avoids 8 near-identical refute lines"
  - "Pre-existing credo issues in post_composer.ex + login.ex + test files are out-of-scope (existed before 08-05 work); documented in deferred-items"
metrics:
  duration_minutes: 3
  completed_date: "2026-04-21"
  tasks_completed: 2
  files_created: 2
  files_modified: 1
  tests_added: 13
---

# Phase 08 Plan 05: Widget Catalog README + Cross-Bucket Smoke Test Summary

One-liner: D-12 Markdown index linking all 20 widgets by file + cross-bucket smoke test proving combined-render theme hygiene holds across all 11 Phase 8 widgets.

## What Was Built

### Files Created

| File | Description |
|------|-------------|
| `lib/foglet_bbs/tui/widgets/README.md` | D-12 catalog index — one Markdown row per widget with relative file link, per-bucket grouping, theme contract description, new-widget contribution guide |
| `test/foglet_bbs/tui/widgets/catalog_smoke_test.exs` | 13-test cross-bucket integration suite: per-widget smoke renders (11) + combined theme hygiene refute + alt-theme differential |

### Files Modified

| File | Change | Commit |
|------|--------|--------|
| `lib/foglet_bbs/tui/widgets/display/table.ex` | `normalize_column/1` now derives `:id` from `:key` when `:id` absent | 108ca8e |

## Requirements Closed

| Requirement | Status |
|-------------|--------|
| REQ-W-12 — Widget catalog README with D-12 discoverability index | Closed |
| REQ-W-13 — Cross-bucket smoke test proves combined theme hygiene | Closed |

## README Coverage

The README indexes all 20 widgets in the catalog:

| Bucket | Widgets |
|--------|---------|
| Chrome (Phase 1) | ScreenFrame, StatusBar, KeyBar |
| Compose/Modal (Phase 4/7) | Compose, Modal |
| Post (Phase 1–3) | MarkdownBody, PostCard |
| List | SelectionList, ListRow, SmartList |
| Input (Phase 8) | Button, Checkbox, RadioGroup, TextInput, Tabs, Menu |
| Display (Phase 8) | Table, Tree, Progress |
| Progress (Phase 8) | Spinner |

Every linked `.ex` file was verified to exist (20/20 found).

## Test Counts Across Phase 8

| Plan | Widget(s) | Tests |
|------|-----------|-------|
| 08-01 | Input.Button, Input.Checkbox, Input.RadioGroup | 31 |
| 08-02 | Input.TextInput, Input.Tabs, Input.Menu | 37 |
| 08-03 | Display.Table, Display.Tree, Display.Progress, Progress.Spinner | 45 |
| 08-04 | List.SmartList | 15 |
| 08-05 | CatalogSmokeTest (cross-bucket) | 13 |
| **Total Phase 8** | **11 widgets + integration** | **141** |

Full widget layer (including pre-existing pre-Phase-8 tests): **244 tests, 0 failures**.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Table.normalize_column/1 did not inject :id from :key**
- **Found during:** Task 2 (first smoke test run)
- **Issue:** Raxol Table's `create_cells/7` accesses `column.id` directly. The plan's smoke test spec uses `%{key: :name, label: "Name"}` column maps (using `:key` not `:id`). `normalize_column/1` from 08-03 only injected `:align`, `:width`, and `:format` — it left `:id` absent, causing `KeyError: key :id not found`
- **Fix:** Added `:key → :id` derivation step in `normalize_column/1`: when `:id` is absent but `:key` is present, `:id` is set to the `:key` value before passing to Raxol
- **Files modified:** `lib/foglet_bbs/tui/widgets/display/table.ex`
- **Commit:** 108ca8e

### Out-of-Scope Pre-existing Credo Issues

The following credo warnings were present at base commit `2dd5c5f` (before 08-05 work) and are NOT caused by this plan's changes. Documented here per scope-boundary rule:

| File | Issue |
|------|-------|
| `test/foglet_bbs/tui/screens/thread_list_test.exs:124` | Alias not alphabetically ordered |
| `test/foglet_bbs/tui/screens/new_thread_test.exs:45` | Alias not alphabetically ordered |
| `lib/foglet_bbs/tui/screens/post_composer.ex:271` | Cyclomatic complexity 10 (max 9) |
| `lib/foglet_bbs/tui/screens/login.ex:263` | Cyclomatic complexity 11 (max 9) |

These exist in prior wave commits (08-01 through 08-04 merges or earlier). `mix precommit` exits 12 due to these issues; they block the green gate but are not caused by this plan. Logged to `deferred-items.md` for resolution in a separate cleanup plan.

## TDD Gate Compliance

Task 2 followed RED → GREEN → style sequence:

| Phase | Commit | Description |
|-------|--------|-------------|
| RED | 5706eac | `test(08-05)` — catalog smoke test added (all 13 tests defined) |
| GREEN | 108ca8e | `feat(08-05)` — table.ex fix allowing tests to pass |
| STYLE | e6c6491 | `style(08-05)` — formatter applied to smoke test |

## Known Stubs

None. The README links to real files (all verified). The smoke test calls real widget `init/1` + `render/2` implementations with minimal but non-empty fixtures.

## Threat Flags

No new network endpoints, auth paths, file access patterns, or schema changes introduced.

T-08-05-03 mitigation implemented: all smoke test fixtures are minimal (1–2 options per widget) so `inspect(trees, limit: :infinity)` is bounded in practice.

## Self-Check

Files created/modified:
- `lib/foglet_bbs/tui/widgets/README.md` — FOUND
- `test/foglet_bbs/tui/widgets/catalog_smoke_test.exs` — FOUND
- `lib/foglet_bbs/tui/widgets/display/table.ex` — FOUND (modified)

Commits:
- dfa8f99 — FOUND (README)
- 5706eac — FOUND (smoke test RED)
- 108ca8e — FOUND (table.ex fix GREEN)
- e6c6491 — FOUND (formatter style)

Tests: 13 smoke tests pass, 244 total widget tests pass, 0 failures.

## Self-Check: PASSED
