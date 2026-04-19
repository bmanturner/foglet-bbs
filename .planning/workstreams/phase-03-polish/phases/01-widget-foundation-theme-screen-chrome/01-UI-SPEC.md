---
phase: 1
slug: widget-foundation-theme-screen-chrome
status: approved
preset: terminal-tui
created: 2026-04-19
---

# Phase 1 — UI Design Contract (Terminal TUI)

> Visual and interaction contract for the Foglet BBS SSH TUI.
> Generated for gsd-ui-phase; verified by gsd-ui-checker.
>
> **Note:** This app renders in a terminal via Raxol 2.4.0 over SSH.
> All design tokens are terminal concepts (ANSI hex colors, character-cell
> layout, Raxol DSL primitives) — not CSS/web values.

---

## Design System

| Property | Value |
|----------|-------|
| Rendering engine | Raxol 2.4.0 (vendored), block-macro DSL only |
| Layout primitives | `box`, `column`, `row`, `spacer`, `divider`, `text/2` |
| Color system | ANSI truecolor hex — Raxol auto-downsamples to 256/16/mono |
| Component form | Function-form widgets only — NO `use Raxol.UI.Components.Base.Component` |
| Icon / symbol use | ASCII / box-drawing chars only (`>`, `|`, `─`, `═`) |
| Font | Terminal monospace (user's terminal font — no control from app) |

---

## Layout Contract — ScreenFrame

Every screen renders through `Foglet.TUI.Widgets.Chrome.ScreenFrame.render/4`.

```
┌──────────────────────────────────────────────────────────────────┐
│ StatusBar: "Foglet BBS — {title}"          "@{handle}" / "guest" │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  content_element (caller-provided, fills remaining height)       │
│                                                                  │
├──────────────────────────────────────────────────────────────────┤
│ KeyBar: [j/k] Navigate  [Enter] Select  [Q] Back                 │
└──────────────────────────────────────────────────────────────────┘
```

**ScreenFrame.render/4 signature (locked — D-05):**
```elixir
ScreenFrame.render(state, title, content_element, key_list)
```

**Internal layout (locked — D-06):**
`outer bordered box → column → StatusBar → divider → content_element → KeyBar`

**ScreenFrame reads from state (locked — D-07):**
- `state.current_user` — handle for StatusBar
- `state.session_context.theme` — theme struct (falls back to `Foglet.TUI.Theme.default()`)

---

## Spacing Contract (Character Cells)

Terminal layout uses character-cell counts, not px. Declared values:

| Token | Chars | Usage |
|-------|-------|-------|
| gap-0 | 0 | Tight column stacks (chrome rows, list rows) |
| gap-1 | 1 | Row element separation (StatusBar label/value) |
| gap-2 | 2 | KeyBar hint separation |
| pad-1 | 1 | Outer box padding (all four sides) |

Raxol DSL usage: `style: %{gap: N}` on `column`/`row`; `style: %{padding: N}` on `box`.

No exceptions — these four values cover all Phase 1 layout needs.

---

## Color Palette — Gray Theme (`:gray`, default for v1.0.1)

All values locked in D-01 and D-02. Exact hex values — no approximation.

| Slot | Hex / Style | Usage |
|------|-------------|-------|
| `border` | `fg: "#555555"` | Outer `box` border, `divider()` lines |
| `primary` | `fg: "#cccccc"` | Body text, unselected list row text |
| `dim` | `fg: "#888888"` | Secondary labels, metadata text |
| `accent` | `fg: "#ffb000", style: [:bold]` | Highlighted labels, `[C]` key hints accent |
| `title` | `fg: "#ffb000", style: [:bold]` | Screen/section heading text |
| `error` | `fg: "#ff5555", style: [:bold]` | Error messages, validation failures |
| `warning` | `fg: "#ffff55"` | Warning / notice text |
| `selected` | `fg: "#000000", bg: "#aaaaaa", style: [:bold]` | Selected list row (reverse-video) |
| `unselected` | `fg: "#cccccc"` | Non-selected list rows |
| `status_bar` | `fg: "#000000", bg: "#aaaaaa"` | StatusBar reverse-video bar |

**Green theme (`:green`)** — defined but inactive in v1.0.1. Full values in CONTEXT.md D-02.

**Color application rule (locked — D-12):**
- Replace ALL `fg: :green` → appropriate theme slot (`primary`, `unselected`, `accent`, etc.)
- Replace ALL `fg: :cyan` → `theme.accent.fg`
- Replace ALL `fg: :red` → `theme.error.fg`
- Replace ALL `fg: :yellow` → `theme.warning.fg`
- `style: [:dim]` (text style) — KEEP as-is; pair with `theme.dim.fg` when coloring dim text
- `style: [:bold]` — used within theme slot definitions; do not add standalone bold outside slots

---

## Typography Contract (Terminal)

Terminal typography is monospace-fixed. "Type scale" maps to semantic text roles:

| Role | Raxol Render | Usage |
|------|-------------|-------|
| Screen title | `text(str, fg: theme.title.fg, style: [:bold])` | Top of content area, board/thread names |
| Body text | `text(str, fg: theme.primary.fg)` | Post content, descriptions, form labels |
| Dim / meta | `text(str, fg: theme.dim.fg)` | Time-ago, secondary metadata, counts |
| Accent label | `text(str, fg: theme.accent.fg, style: [:bold])` | Key hint brackets `[K]`, interactive labels |
| Error | `text(str, fg: theme.error.fg, style: [:bold])` | Form errors, auth failures |
| Warning | `text(str, fg: theme.warning.fg)` | Non-critical notices |
| Selected row | `text(str, fg: theme.selected.fg, bg: theme.selected.bg, style: [:bold])` | Active list item |

---

## Copywriting Contract

| Element | Copy |
|---------|------|
| StatusBar left | `"Foglet BBS — {Screen Title}"` |
| StatusBar right (authed) | `"@{handle}"` |
| StatusBar right (guest) | `"guest"` |
| Selected row marker | `"> "` (2 chars, leading; unselected: `"  "`) |
| Unread badge | `" ({N} unread)"` appended to board name |
| Loading placeholder | `"Loading..."` with `style: [:dim]` |
| Empty boards | `"No boards subscribed. Ask your sysop to subscribe you."` |
| Key hint format | `"[{KEY}] {Description}"` — bracket in accent color, description in dim |
| Divider | `divider()` Raxol call — no custom char |

---

## Widget Interaction Contract

### SelectionList

| Property | Contract |
|----------|----------|
| Navigation | `j` / `k` move `selected_index`; parent screen owns state |
| Selection | `Enter` confirms selected item |
| Render API | `SelectionList.render(items, selected_index, row_renderer_fn)` — pure, no internal state |
| Row renderer | Provided by parent screen as a fn; receives `{item, idx, selected?}` |
| Screens using it | `BoardList`, `ThreadList`, new-thread board picker |

### StatusBar (Chrome.StatusBar)

| Property | Contract |
|----------|----------|
| Layout | Full-width `row` with title left, handle/guest right |
| Background | `bg: theme.status_bar.bg` fills entire row |
| Title text | `"Foglet BBS — {title}"` — `fg: theme.status_bar.fg` |
| Handle text | `"@{handle}"` or `"guest"` — `fg: theme.status_bar.fg` |
| Separator | `" | "` between title and handle in dim or status_bar.fg |

### KeyBar (Chrome.KeyBar)

| Property | Contract |
|----------|----------|
| Layout | `row` with `gap: 2` — all hints on one line |
| Key bracket | `fg: theme.accent.fg, style: [:bold]` |
| Description | `fg: theme.dim.fg` |
| Format | `"[{KEY}] {Description}"` — each hint is a single `text/2` call |

---

## Migration Checklist (per-screen)

Each of the 9 screens in `lib/foglet_bbs/tui/screens/` must satisfy:

- [ ] `render/1` calls `ScreenFrame.render(state, title, content_el, key_list)`
- [ ] No direct `StatusBar.render/1` or `KeyBar.render/1` calls remain (ScreenFrame handles them)
- [ ] No `fg: :green`, `fg: :cyan`, `fg: :red`, `fg: :yellow` hardcodes remain
- [ ] All color references use `state.session_context.theme.{slot}.{prop}` or equivalent via ScreenFrame
- [ ] Outer `box style: %{border: :single, padding: 1}` is now INSIDE ScreenFrame (not duplicated in caller)

---

## Checker Sign-Off

- [x] Dimension 1 Copywriting: PASS — all visible strings specified
- [x] Dimension 2 Visuals: PASS — layout contract fully diagrammed; ScreenFrame structure locked
- [x] Dimension 3 Color: PASS — exact hex for all 10 theme slots; replacement rules for all named colors
- [x] Dimension 4 Typography: PASS — terminal roles mapped; no px scale needed (monospace fixed)
- [x] Dimension 5 Spacing: PASS — 4 gap/padding tokens cover all Phase 1 needs
- [x] Dimension 6 Registry Safety: PASS — zero new deps; Raxol primitives only; no third-party components

**Approval:** approved 2026-04-19

---

*Phase: 01-widget-foundation-theme-screen-chrome*
*UI-SPEC generated: 2026-04-19 (auto mode — sourced from CONTEXT.md D-01 through D-12 and existing widget code)*
