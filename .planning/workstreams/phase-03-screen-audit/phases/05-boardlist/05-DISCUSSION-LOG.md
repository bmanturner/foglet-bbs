# Phase 5: BoardList - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-21
**Phase:** 05-BoardList
**Areas discussed:** Loading feedback policy, `load_boards/1` dead-code disposition, state-shape contract

---

## Loading feedback policy

| Option | Description | Selected |
|--------|-------------|----------|
| 1A | Keep plain `"Loading..."` text unless measured delay proves spinner value | |
| 1B | Always use spinner for `load_boards` loading state | ✓ |
| 1C | Keep plain text permanently, no spinner evaluation | |

**User's choice:** `1B`
**Notes:** User overrode the default recommendation and requested spinner adoption.

---

## `load_boards/1` dead-code resolution

| Option | Description | Selected |
|--------|-------------|----------|
| 2A | Keep function as test seam; mark `@doc false`; add comment about App owning production path | ✓ |
| 2B | Delete function and migrate tests to App-only flow | |
| 2C | Keep as-is without doc/comment clarification | |

**User's choice:** `2A`
**Notes:** Keep compatibility/test utility but make production ownership explicit.

---

## State-shape contract

| Option | Description | Selected |
|--------|-------------|----------|
| 3A | Add explicit `init_screen_state/1` and replace inline default literals | ✓ |
| 3B | Keep inline defaults and document exception | |
| 3C | Make BoardList intentionally stateless | |

**User's choice:** `3A`
**Notes:** BoardList should conform to AUDIT-19 initializer policy.

---

## the agent's Discretion

- Exact spinner widget implementation details.
- Exact helper naming and section-order cleanup strategy.

## Deferred Ideas

- None raised during this focused discuss session.
