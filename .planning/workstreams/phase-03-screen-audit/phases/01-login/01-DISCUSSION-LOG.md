# Phase 1: Login — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in 01-CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-21
**Phase:** 01-login
**Areas discussed:** Widget scope (pre-patch), Form field layout, Screen state init, Error state shape, Key routing precedence

---

## Widget scope (pre-patch)

User requested making the `Input.TextInput` box optional (not part of the original gray areas — surfaced during layout discussion).

| Option | Description | Selected |
|--------|-------------|----------|
| Micro-patch before Phase 1 | Standalone commit adds `bordered: false` opt to `Input.TextInput`; Phase 1 consumes it | ✓ |
| Bundle into Phase 1 as documented exception | Widget tweak + screen diff in one commit, AUDIT-13 exception noted | |
| Work with box as-is | Accept bordered layout, choose label-above or placeholder approach | |

**User's choice:** Micro-patch before Phase 1 (recommended)
**Notes:** Keeps the audit diff to one screen file. Widget patch lands first, green precommit, then Phase 1 planning proceeds against the post-patch `Input.TextInput`.

---

## Form field layout

| Option | Description | Selected |
|--------|-------------|----------|
| Label inline, same row | `text/2` label + borderless TextInput side-by-side; visually identical to today | ✓ |
| Label above, TextInput below | Two rows per field; more vertical space | |
| Placeholder inside box | No label line; placeholder text disappears once typing starts | |

**User's choice:** Label inline, same row
**Notes:** With `bordered: false` decided, inline layout directly mirrors the current `"Handle:   value█"` format. Sets visual precedent for Phase 2 (Register) and Phase 7 (NewThread).

---

## Screen state init

| Option | Description | Selected |
|--------|-------------|----------|
| Minimal — menu sub only | `%{sub: :menu}`; TextInput structs created lazily in `enter_login_form/1` | ✓ |
| Full pre-init | `init_screen_state/1` returns complete state including TextInput structs | |

**User's choice:** Minimal — `%{sub: :menu}`
**Notes:** TextInputs created fresh each time user enters the form. Smaller per-session footprint. Sets D-14 init pattern for Phases 2 and 7.

---

## Error state shape

| Option | Description | Selected |
|--------|-------------|----------|
| Top-level `error: nil` in login_ss | Flat map alongside TextInput structs — `%{..., error: nil \| "…"}` | ✓ |
| Keep nested `form:` sub-map | Preserve `form: %{error: …}` sub-map alongside TextInput structs | |

**User's choice:** Top-level `error: nil`
**Notes:** Eliminates the `form` map entirely. Clean flat state shape sets the inline-error pattern for Phase 2 (Register).

---

## Key routing precedence

| Option | Description | Selected |
|--------|-------------|----------|
| Screen intercepts first | Tab, Escape, Enter caught before TextInput; rest delegated | ✓ |
| Delegate first, check action | All keys go to TextInput first; screen inspects returned action | |

**User's choice:** Screen intercepts first (recommended)
**Notes:** Tab, Escape, Enter are screen-semantic keys — interception is unambiguous. Char/backspace/cursor keys are TextInput-semantic — delegation is clean. TextInput's `:submitted`/`:cancelled` actions are never produced (Enter/Escape intercepted first), so `_action` can be discarded in the delegating clause. Sets key-routing precedent for Phases 2 and 7.

---

## Claude's Discretion

- Helper naming (`focused_input/1`, `update_focused_input/3`, etc.)
- Exact `@spec` surface on `init_screen_state/1`
- Row layout macro for inline label+TextInput
- AUDIT-18 section re-ordering details
- `with` chain clause structure inside `submit_login/1`

## Deferred Ideas

- `bordered: true` form variant — option available after micro-patch but not used in Phase 1
- FUT-03 `█`-block cursor style for `Input.TextInput` — still deferred
- Input value extraction helper — planner decides if needed
