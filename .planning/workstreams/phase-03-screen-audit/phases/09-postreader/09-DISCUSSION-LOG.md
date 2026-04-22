# Phase 9: PostReader - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in `09-CONTEXT.md`.

**Date:** 2026-04-22
**Phase:** 09-postreader
**Areas discussed:** domain/helper swap strategy, callback ownership, loading-state policy, render-path purity boundaries

---

## Domain/helper swap strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Full helper adoption now | Use `Domain.get/2` across all load/flush domain lookups with fallback parity | Yes |
| Partial adoption | Load path only now, defer flush path | No |
| No further helper changes | Keep current mix of resolution patterns | No |

## Dead-code and callback ownership (`load_posts/2`, `flush_read_pointers/2`)

| Option | Description | Selected |
|--------|-------------|----------|
| Keep both public callbacks and verify contracts | Treat as App-dispatched lifecycle callbacks | Yes |
| Convert one/both to private | Requires dispatcher reshaping | No |
| Delete one/both | Aggressive cleanup, high behavior risk | No |

## Loading-state and UX restraint (`AUDIT-10`)

| Option | Description | Selected |
|--------|-------------|----------|
| Keep plain loading text | Preserve static `"Loading posts..."` | No |
| Add spinner now | Spinner adoption for loading states in this phase | Yes |
| Hybrid | Spinner only for load, never flush | No |

## Render-path purity and cache/viewport boundaries

| Option | Description | Selected |
|--------|-------------|----------|
| Strict purity + documented exceptions | No state writes in `render_*`; mutate only in non-render helpers/commands | Yes |
| Allow targeted render mutations | Convenience-first caching in render path | No |
| Keep current behavior without purity tests | Minimal effort, weaker guard | No |

---

*Captured during `$gsd-manager --ws phase-03-screen-audit` inline discuss flow.*
