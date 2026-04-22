---
phase: 07
slug: newthread
status: complete
shadcn_initialized: false
preset: not_applicable_tui
created: 2026-04-22
---

# Phase 07 — UI Design Contract

> TUI interaction contract for NewThread title-input migration.

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

- Keep the current two-step flow: `:board` then `:compose`.
- Migrate title editing to `Input.TextInput` while preserving existing key semantics.
- Keep body editing via `Compose` + `MultiLineInput` unchanged.
- Preserve key hints (`Tab`, `Ctrl+S`, `Ctrl+C`) and source-order key interception semantics.

---

## Spacing and Density Contract

- No new rows added below the compose counter (reserved region for future milestone).
- Line count should decrease or remain neutral; visible row count must not increase.
- No nested border surfaces inside `ScreenFrame` content.

---

## Color and Theme Contract

- Route all coloring through `%Foglet.TUI.Theme{}` slots.
- No named color atoms, no hex literals, no theme-map mutation.
- Every widget call uses `theme: theme` explicitly.

---

## Copy Contract

- Keep existing screen title and key-hint vocabulary.
- Preserve existing error message semantics for empty title/body and thread creation failures.

---

## Checker Sign-Off

- [x] Interaction parity: PASS
- [x] Density and sparseness: PASS
- [x] Theme routing: PASS
- [x] Reserved region protection: PASS
- [x] Source-order key semantics preserved: PASS

**Approval:** approved
