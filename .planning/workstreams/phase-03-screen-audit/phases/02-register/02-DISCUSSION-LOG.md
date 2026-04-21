# Phase 2: Register — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-21
**Phase:** 02-register
**Areas discussed:** :confirm step, Wizard init, login.ex scope

---

## :confirm step

*Pre-discussion observation: ROADMAP and REQUIREMENTS cite "handle → email → password → confirm → submit" in test coverage requirements, but the current register.ex has no :confirm step — it goes password → submit directly. This discrepancy triggered the gray area.*

### Wizard structure

| Option | Description | Selected |
|--------|-------------|----------|
| Handle is separate | invite_only: invite_code → handle → [email + password + confirm]. Others: handle → [email + password + confirm] | |
| Handle on combined step | invite_only: invite_code → [handle + email + password + confirm]. Others: [handle + email + password + confirm] | ✓ |

**User's choice:** Handle on combined step

**Notes:** User provided key context upfront (before area selection): "collect the email, password, and confirm password fields on the same step. invite code can remain on a separate step. verify also remains a separate step." Then chose to also put handle on the combined step.

### Tab navigation on combined step

| Option | Description | Selected |
|--------|-------------|----------|
| Tab cycles, Enter submits | Tab moves focus through all 4 fields; Enter on confirm submits | ✓ |
| Enter advances, Enter submits | Enter moves focus field-by-field; no Tab involvement | |

**User's choice:** Tab cycles, Enter submits (Phase 1 pattern extended to 4 fields)

---

## Wizard init

| Option | Description | Selected |
|--------|-------------|----------|
| register.ex self-initializes | Lazy fallback in render/handle_key; login.ex just sets current_screen: :register | ✓ |
| app.ex initializes on transition | app.ex calls Register.init_screen_state/1 during screen transition; expands app.ex touches | |

**User's choice:** register.ex self-initializes (Recommended)

**Notes:** Self-init follows Phase 1 D-03 lazy-init precedent and keeps AUDIT-13(b) scope minimal.

---

## login.ex scope

*Context: login.ex:maybe_register/1 writes `register_wizard: default_wizard(state)`. Removing the struct field in Phase 2 would cause a compile error. The question is whether Phase 2 touches login.ex or finds another approach.*

| Option | Description | Selected |
|--------|-------------|----------|
| Expand AUDIT-13(b) to cover login.ex | Remove `register_wizard: default_wizard(state)` from maybe_register/1; amend exception | ✓ |
| Defer to Phase 1 scope | Have Phase 1 proactively clean up maybe_register/1 before Phase 2 runs | |

**User's choice:** Expand AUDIT-13(b) to cover login.ex (Recommended)

**Notes:** The diff is a one-line deletion; user agreed the scope expansion is acceptable.

---

## Claude's Discretion

- Naming of register screen-state helpers (`get_register_ss/1`, etc.)
- Whether `handle_wizard_event/2` is kept public or collapsed into `do_update` dispatch
- AUDIT-18 canonical section reordering
- Exact `with` chain clause structure for `submit/2`

## Deferred Ideas

None — discussion stayed within phase scope.
