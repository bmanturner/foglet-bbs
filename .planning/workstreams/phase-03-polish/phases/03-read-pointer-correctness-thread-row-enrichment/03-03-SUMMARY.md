---
phase: 3
plan: "03"
status: complete
started: "2026-04-20"
completed: "2026-04-20"
---

# Plan 03 — ListRow.render_with_metadata/6: Summary

## What was built

Extended `Foglet.TUI.Widgets.List.ListRow` with a new `render_with_metadata/6` entry point that renders a single row with left-aligned title, right-aligned metadata, and optional bold title treatment for unread threads.

## Key changes

- **`lib/foglet_bbs/tui/widgets/list/list_row.ex`**: New `render_with_metadata/6` with `compute_parts/4` (layout math), `truncate_title/2` (… truncation), `styles_for/3` (selected/unselected+read/unselected+unread styling)
- **`test/foglet_bbs/tui/widgets/list/list_row_test.exs`**: New test file with 15 tests (backwards compat, right-alignment, truncation, metadata preservation, bold-on-unread, selection-wins, default width, theme hygiene)

## Key decisions

- Used `row style: %{gap: 0}` with manually computed padding spaces instead of Raxol's `spacer/1` — needed exact width control for right-alignment
- Title truncates with `…` (U+2026) when combined width exceeds terminal; metadata always fully visible (D-03)
- Bold-on-unread only applies when unselected; selected rows ignore `unread?` (selection highlight wins)

## Key files

- `lib/foglet_bbs/tui/widgets/list/list_row.ex` — render_with_metadata/6 + private helpers
- `test/foglet_bbs/tui/widgets/list/list_row_test.exs` — 15 new tests

## Self-Check: PASSED
