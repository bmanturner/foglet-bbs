# Phase 7: NewThread - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-21
**Phase:** 07-NewThread
**Areas discussed:** title-input migration, body compose invariants, helper/terminal-size policy, source-order constraints, audit guardrails

---

## Title input migration (`NEWTHREAD-01`)

| Option | Description | Selected |
|--------|-------------|----------|
| 1 | Replace hand-rolled title input with `Input.TextInput`, accept cursor visual drift | ✓ |
| 2 | Keep hand-rolled title input unchanged | |
| 3 | Hybrid TextInput state + custom `█` title render layer | |

**User's choice:** `1`
**Notes:** Accepts visual drift from legacy cursor behavior.

---

## Body composer invariants (`NEWTHREAD-02`)

| Option | Description | Selected |
|--------|-------------|----------|
| 1 | Keep `Compose` + `MultiLineInput` pipeline unchanged | ✓ |
| 2 | Refactor body path to a different widget/pipeline | |
| 3 | Keep pipeline but allow keybinding behavior changes | |

**User's choice:** `1`
**Notes:** Body path is explicitly out of scope for behavior changes.

---

## Helper/terminal-size policy (`NEWTHREAD-03`)

| Option | Description | Selected |
|--------|-------------|----------|
| 1 | Add/keep `@default_terminal_size` and route all `{80,24}`/helper callsites through audit-compliant paths | ✓ |
| 2 | Keep existing inline fallbacks | |
| 3 | Partial helper migration only | |

**User's choice:** `1`
**Notes:** Zero grep-gate regressions required.

---

## Source-order guard (`NEWTHREAD-04`)

| Option | Description | Selected |
|--------|-------------|----------|
| 1 | Preserve source-order-sensitive guarded clauses unchanged | ✓ |
| 2 | Allow wording/position tweaks to note | |
| 3 | Drop source-order note if tests pass | |

**User's choice:** keep guarded clause order unchanged
**Notes:** User requested explicit rationale for ordering dependency; rationale confirmed from code.

---

## Audit guardrails (`AUDIT-16/17/18/19`)

| Option | Description | Selected |
|--------|-------------|----------|
| 1 | Strict guardrails: no row growth, no protected-region fill, canonical ordering, explicit init-state compliance | ✓ |
| 2 | Prioritize migration even with modest layout growth | |
| 3 | Allow section/state exceptions if behavior unchanged | |

**User's choice:** `1`
**Notes:** Guardrail compliance is non-negotiable.

---

## the agent's Discretion

- Exact TextInput integration details for title field.
- Exact section-order cleanup mechanics.

## Deferred Ideas

- None raised during this discuss session.
