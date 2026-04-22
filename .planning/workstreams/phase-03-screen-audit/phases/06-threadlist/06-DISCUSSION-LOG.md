# Phase 6: ThreadList - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-21
**Phase:** 06-ThreadList
**Areas discussed:** module-load guard strategy, `load_threads/2` dead-code disposition, loading feedback, `created_by` preload contract, state-shape contract

---

## `Code.ensure_loaded/1` guard strategy

| Option | Description | Selected |
|--------|-------------|----------|
| 1 | Add `Code.ensure_loaded/1` once, then gate both arity probes on success | ✓ |
| 2 | Keep current behavior without `ensure_loaded` | |
| 3 | Remove arity probing and support one path only | |

**User's choice:** `1`
**Notes:** Treats missing module-load handling as a correctness bug to close.

---

## `load_threads/2` dead-code disposition

| Option | Description | Selected |
|--------|-------------|----------|
| 1 | Keep as public/test seam, mark `@doc false`, comment App owns production path | ✓ |
| 2 | Delete and migrate tests to App-only path | |
| 3 | Keep unchanged with current docs | |

**User's choice:** `1`
**Notes:** Keep seam but make ownership explicit.

---

## Loading indicator policy

| Option | Description | Selected |
|--------|-------------|----------|
| 1 | Keep plain loading text unless measured latency justifies spinner | |
| 2 | Always use spinner for thread loading state | ✓ |
| 3 | Keep plain text permanently | |

**User's choice:** `2`
**Notes:** User explicitly chose spinner adoption.

---

## `created_by` preload contract

| Option | Description | Selected |
|--------|-------------|----------|
| 1 | Hard preload contract; test must fail if `created_by.handle` missing | ✓ |
| 2 | Keep fallback only; no strict preload guarantee | |
| 3 | Hybrid strict+fallback emphasis | |

**User's choice:** `1`
**Notes:** Enforce data contract in tests.

---

## `thread_list` state-shape contract

| Option | Description | Selected |
|--------|-------------|----------|
| 1 | Add public `init_screen_state/1` and replace inline defaults | ✓ |
| 2 | Keep inline defaults, document exception | |
| 3 | Make ThreadList stateless | |

**User's choice:** `1`
**Notes:** Align with AUDIT-19 adoption pattern.

---

## the agent's Discretion

- Exact spinner widget selection and rendering details.
- Exact helper naming and section-order mechanics.

## Deferred Ideas

- None raised during this focused discussion.
