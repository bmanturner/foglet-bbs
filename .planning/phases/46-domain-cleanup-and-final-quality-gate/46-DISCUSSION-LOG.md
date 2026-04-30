# Phase 46: Domain Cleanup And Final Quality Gate - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the analysis.

**Date:** 2026-04-29
**Phase:** 46-domain-cleanup-and-final-quality-gate
**Mode:** assumptions
**Areas analyzed:** DOM-02 Documentation Placement, QUAL-01 Dialyzer Baseline Reduction, QUAL-03 CONCERNS.md Walk, Plan Decomposition, Risk Boundary

## Assumptions Presented

### DOM-02 Documentation Placement
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Add `## Transaction strategy` paragraph to existing `@moduledoc`, plus one-line inline pointer comments above `Repo.transaction()` at `:154` and `:196` | Confident | `lib/foglet_bbs/boards/server.ex` moduledoc already uses `##` subheaders (`## Message number allocation`, `## Crash recovery`); SPEC requires reader to encounter rationale before the call |

### QUAL-01 Dialyzer Baseline Reduction Strategy
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Three-bucket walk: narrow what can be narrowed, group Raxol-opaque `render/*` returns under one shared comment block, group Ecto-opaque entries under another | Likely | `lib/foglet_bbs/tui/screens/login.ex` shows `@spec init(Context.t()) :: map()` (narrowable) vs `@spec render(map(), Context.t()) :: any()` (Raxol-opaque) |
| Fix `boards/server.ex :call_without_opaque` by tightening Multi callback specs and remove from ignore | Confident | SPEC §Acceptance Criteria #3 mandates removal |
| Update header comment to assert "every kept entry has a stated reason" invariant | Confident | SPEC §Target.4 explicit |

### QUAL-03 CONCERNS.md Walk
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Walk top-to-bottom in existing file order (Tech Debt → Known Bugs → Security → Performance → Under-tested Zones); annotate every `### ` heading inline | Confident | `.planning/codebase/CONCERNS.md` uses consistent `### ` heading shape; SPEC §Target.4 mandates inline placement |
| Cross-reference dispositions against phases 41–45 SUMMARY.md files | Confident | All five SUMMARY.md files exist; SPEC §Background already maps phases to concern categories |
| SSH `PubkeyStash` TTL → `Fixed in Phase 45`; deferred perf items → `Intentionally retained` with backlog pointer | Confident | SPEC §Background calls out Phase 45 PubkeyStash fix; SPEC §Out of scope locks deferred perf items |

### Plan Decomposition
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| One plan per requirement, ordered DOM-01 → DOM-02 → QUAL-01 → QUAL-03 (smallest/safest first, capstone audit last) | Likely | SPEC requirements 1–4 are independent file-level targets; QUAL-03 benefits from QUAL-01 results being final before disposition pointers are written |

### Risk Boundary
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Run `rtk mix precommit && rtk mix test` after every plan's commits, not just at phase end; v2.0 baseline (1 property + 2161 tests) is the floor | Confident | SPEC §Constraints #1 and #2 mandate per-commit precommit-green and no test regression |

## Corrections Made

No corrections — all assumptions confirmed via "Yes, proceed".

## Auto-Resolved

Not applicable (no `--auto`, no Unclear assumptions).

## External Research

No external research performed — codebase + SPEC + prior CONTEXT.md files
provided sufficient evidence for every assumption.
