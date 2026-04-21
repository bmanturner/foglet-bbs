# Phase 1: Widget foundation + theme + screen chrome — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-19
**Phase:** 01-widget-foundation-theme-screen-chrome
**Areas discussed:** Color palette, ScreenFrame content API, Widget namespace strategy

---

## Color palette

| Option | Description | Selected |
|--------|-------------|----------|
| Green terminal classic | Keep green as primary/brand, add contrast with white titles, cyan accent, red errors, yellow warnings | |
| Amber/retro | Yellow-amber primary, PDP/VT220 aesthetic | |
| Monochrome + accent | White/bright primary, one accent color only | |
| User-specified hex values | Two complete themes provided with exact hex colors | ✓ |

**User's choice:** User provided two complete named themes with exact hex color values.

**Gray/amber (default for v1.0.1):**
```
border: #555555, primary: #cccccc, dim: #888888,
accent/title: #ffb000 bold, error: #ff5555 bold, warning: #ffff55,
selected: #000000 on #aaaaaa bold, unselected: #cccccc,
status_bar: #000000 on #aaaaaa
```

**Green (defined but not active):**
```
border: #22aa44, primary: #33ff66, dim: #22aa44,
accent: #ffb000 bold, title: #33ff66 bold, error: #ff5555 bold, warning: #ffff55,
selected: #000000 on #33ff66 bold, unselected: #33ff66,
status_bar: #000000 on #33ff66
```

**Theme resolution:**
| Option | Description | Selected |
|--------|-------------|----------|
| Foglet.Config key | tui_theme: "gray" \| "green" set by sysop | |
| Hardcode gray for now | CLIHandler always picks gray in v1.0.1 | ✓ |

**Notes:** `status_bar` added as an additional theme slot (not in original list) — creates reverse-video status bar effect, intentional.

---

## ScreenFrame content API

| Option | Description | Selected |
|--------|-------------|----------|
| Positional args | ScreenFrame.render(state, title, content_element, key_list) | ✓ |
| Options map | ScreenFrame.render(%{state:, title:, content:, keys:}) | |

**User's choice:** Positional args — consistent with existing KeyBar/StatusBar function signatures.

**StatusBar format:**
| Option | Description | Selected |
|--------|-------------|----------|
| "Foglet BBS — {title}" + handle | Preserves app brand on every screen | ✓ |
| Just "{title}" + handle | More compact, vim-like | |

---

## Widget namespace strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Rename and rewrite in new namespace | Create Chrome.*, List.*, Post.* modules; delete old flat modules; update all callers in one pass | ✓ |
| Create new, keep old as delegates | New modules are real; old modules become thin aliases | |

**User's choice:** Clean rename — delete old flat modules, no aliases left behind.

---

## Claude's Discretion

- SelectionList state ownership: parent screen owns `selected_index`, SelectionList is pure rendering
- Post.MarkdownBody and Post.PostCard: define stubs in Phase 1, implement in Phase 2
- KeyBar goes into `Chrome.KeyBar` sub-namespace (not explicitly listed in WIDGET-01 but is part of chrome)

## Deferred Ideas

None.
