---
plan: 01-01
title: Theme struct + CLIHandler injection
status: complete
completed: 2026-04-19
commit: 7813941
---

# Summary — Plan 01-01: Theme struct + CLIHandler injection

## What was done

Created `Foglet.TUI.Theme` struct at `lib/foglet_bbs/tui/theme.ex` with 10 named color slots:
`border`, `primary`, `dim`, `accent`, `title`, `error`, `warning`, `selected`, `unselected`, `status_bar`.

Implemented two palettes:
- `gray/0` — the active v1.0.1 phosphor-gray palette
- `green/0` — green phosphor (retained for future use, inactive)

Added `resolve/1` for atom-based palette lookup (`:gray | :green | fallback`).

Injected `theme: Foglet.TUI.Theme.default()` into `session_context` in
`lib/foglet_bbs/ssh/cli_handler.ex` `build_context/3`, making the theme
available to every screen via `get_in(state, [:session_context, :theme])`.

## Outcome

All screens can now read `theme.primary.fg`, `theme.accent.fg`, etc. instead of hardcoding `:green`/`:cyan`/`:red`. Foundation for Plans 01-02 through 01-04.
