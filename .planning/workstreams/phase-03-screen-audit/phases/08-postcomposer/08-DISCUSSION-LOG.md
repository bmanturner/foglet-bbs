# Phase 8: PostComposer - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in `08-CONTEXT.md`.

**Date:** 2026-04-22
**Phase:** 08-postcomposer
**Areas discussed:** with-chain rewrite shape, source-order guard placement, terminal fallback/helper hygiene, audit guardrails

---

## with-chain rewrite shape

| Option | Description | Selected |
|--------|-------------|----------|
| Minimal `with` around publish only | Keep pre-checks as guards; rewrite publish branch with low regression risk | Yes |
| Full `with` from top to bottom | Uniform style with higher branch-regression risk | No |
| Keep current nested `case` | No rewrite; misses COMPOSER-02 | No |

**Notes:** Preserve modal error branches and success command behavior exactly.

## Source-order guard comment placement

| Option | Description | Selected |
|--------|-------------|----------|
| Exact Phase 7 wording verbatim | Copy existing note text unchanged | No |
| Equivalent PostComposer-specific wording | Same semantic warning with module-specific phrasing | Yes |
| Keep current comments only | No new warning note | No |

**Notes:** Comment must sit above the guarded `handle_key/2` clauses.

## Terminal/default-size and helper hygiene cleanup

| Option | Description | Selected |
|--------|-------------|----------|
| Introduce `@default_terminal_size {80, 24}` everywhere needed | Replace inline fallback and keep helper-only theme/domain access | Yes |
| Keep inline fallback | Avoid movement but fails audit direction | No |
| Partial cleanup only | Attribute in one path, defer the rest | No |

**Notes:** Keep grep-gate hygiene trajectory for #7/#8/#9.

## Audit guardrails and acceptance

| Option | Description | Selected |
|--------|-------------|----------|
| Full guardrail closure this phase | Prove COMPOSER + audit rubric with precommit green | Yes |
| Refactor now, audit later | Split acceptance across phases | No |
| Minimal tests only | Skip full audit proof | No |

**User clarification:** Phase-8-only override accepted: line-count increase is allowed for this phase if visible row count does not increase and protected layout regions are not filled.

---

*Captured during `$gsd-manager --ws phase-03-screen-audit` inline discuss flow.*
