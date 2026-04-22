---
phase: 08
slug: postcomposer
status: draft
shadcn_initialized: false
preset: not_applicable_tui
created: 2026-04-22
---

# Phase 08 — UI Design Contract

> TUI interaction contract for PostComposer submit-flow cleanup.

---

## Design System

| Property | Value |
|----------|-------|
| Tool | none (Raxol TUI primitives) |
| Preset | not applicable |
| Component library | Foglet TUI widgets + Raxol components |
| Icon library | none |
| Font | terminal monospace |

---

## Interaction Contract

- Keep current mode switching (`Tab` edit/preview) unchanged.
- Keep current body editing path (`Compose` + `MultiLineInput`) unchanged.
- Keep submit/cancel key semantics (`Ctrl+S`, `Ctrl+C`) unchanged.
- Add a source-order warning note for `handle_key/2` clauses to prevent reorder regressions.

---

## Spacing and Density Contract

- No new rows added below the character counter (reserved for later milestones).
- Visible row count must not increase.
- No nested borders in `ScreenFrame` content.

---

## Color and Theme Contract

- Theme access stays on `%Foglet.TUI.Theme{}` slots via `Theme.from_state/1`.
- Domain module lookup stays on `Screens.Domain.get/2`.
- No named color atoms, no hex literals, no direct ANSI.

---

## Copy Contract

- Preserve current modal error messages and key-hint labels.
- Preserve submit failure string (`"Failed to create post."`) and existing empty/length messages.

---

## Checker Sign-Off

- [x] Interaction parity: PASS
- [x] Density and sparseness: PASS
- [x] Theme routing: PASS
- [x] Reserved region protection: PASS
- [x] Source-order key semantics protected: PASS

**Approval:** approved
