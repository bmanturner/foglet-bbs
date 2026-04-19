---
plan: 01-04
title: Migrate all 9 screens to ScreenFrame + delete old flat widgets
status: complete
completed: 2026-04-19
commit: 677b7eb
---

# Summary — Plan 01-04: Screen migration + flat widget deletion

## What was done

Migrated all 9 TUI screens to `ScreenFrame.render/4`, replacing the old
per-screen `box + StatusBar + KeyBar` pattern:

- `login.ex` — ScreenFrame wired; menu and form sub-states use theme slots
- `register.ex` — ScreenFrame wired; wizard steps use `theme.primary/accent/error/dim`
- `verify.ex` — ScreenFrame wired; cooldown/attempt text uses theme error/dim
- `main_menu.ex` — ScreenFrame wired; menu items use `theme.primary.fg`
- `board_list.ex` — ScreenFrame wired; SelectionList + ListRow replace inline row logic
- `thread_list.ex` — ScreenFrame wired; SelectionList + ListRow replace inline row logic
- `post_reader.ex` — ScreenFrame wired; markdown tuple renderer uses `theme.primary/dim`
- `post_composer.ex` — ScreenFrame wired; input + preview use `theme.primary/dim/error`
- `new_thread.ex` — ScreenFrame wired; board picker uses SelectionList + ListRow; compose step uses theme

All hardcoded `:green`, `:cyan`, `:red`, `:yellow` atom colors replaced with
`theme.primary.fg`, `theme.accent.fg`, `theme.error.fg`, `theme.warning.fg`, `theme.dim.fg`.

Deleted old flat widgets:
- `lib/foglet_bbs/tui/widgets/key_bar.ex`
- `lib/foglet_bbs/tui/widgets/status_bar.ex`

## Outcome

Every screen now renders through a single unified chrome assembly.
Zero hardcoded color atoms remain in screen modules.
`mix compile --warnings-as-errors` passes clean. Credo strict passes clean.
Dialyzer warnings are pre-existing (stub `no_return` + `contract_supertype` — baseline unchanged).
