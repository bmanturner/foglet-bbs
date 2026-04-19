---
plan: 01-02
title: Chrome widgets — ScreenFrame, StatusBar, KeyBar
status: complete
completed: 2026-04-19
commit: 7813941
---

# Summary — Plan 01-02: Chrome widgets — ScreenFrame, StatusBar, KeyBar

## What was done

Created three chrome widgets under `lib/foglet_bbs/tui/widgets/chrome/`:

**ScreenFrame** (`screen_frame.ex`) — locked render/4 signature:
`render(state, title, content_element, key_list) :: any()`
Wraps every screen: outer bordered box → column → StatusBar → divider → content_element → KeyBar.
Reads theme from `state.session_context.theme` internally.

**StatusBar** (`status_bar.ex`) — renders "Foglet BBS — {title} | @{handle}" as a styled row.
Reads handle from `state.current_user.handle`; falls back to "guest".

**KeyBar** (`key_bar.ex`) — renders `[{"Key", "Description"}, ...]` as a themed accent-colored row.

All three use the Raxol block-macro DSL (`row/column/text do...end`). No legacy function-form.
