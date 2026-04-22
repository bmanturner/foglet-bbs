# Phase 0: Cross-cutting extractions (prelude) — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in `00-CONTEXT.md` — this log preserves the alternatives considered.

**Date:** 2026-04-21
**Phase:** 00-cross-cutting-extractions-prelude
**Workstream:** phase-03-screen-audit
**Areas discussed:** Plan granularity
**Areas accepted as research default (not discussed):** Domain.get/2 return shape, Theme.from_state/1 fallback policy, Grep-gate regression enforcement

---

## Area selection

### Gray areas presented (multiSelect)

| Option | Description | Selected |
|--------|-------------|----------|
| Domain.get/2 return shape | Direct `module` + fallback vs `{:ok, module} \| {:error, :not_configured}` | (research default accepted) |
| Theme.from_state/1 fallback policy | Silent `Theme.default/0` fallback vs raise vs tagged tuple | (research default accepted) |
| Plan granularity (1 vs 2–3 plans) | 00-01 helpers / 00-02 migration etc. | ✓ |
| Grep-gate regression enforcement | ExUnit grep assertion vs per-phase rubric only vs pre-commit hook | (research default accepted) |

**User's choice:** Plan granularity (only).

**Note on unselected areas:** Using research-recommended defaults (see `00-CONTEXT.md` §Implementation Decisions D-01, D-02, D-07).

---

## Plan granularity

### Question 1 — How should Phase 0 be split into plans?

| Option | Description | Selected |
|--------|-------------|----------|
| Three plans (Recommended) | 00-01 Theme helper + tests; 00-02 Domain module + tests; 00-03 Call-site migration (11 files). Cleanest diff per commit; reversible at finer granularity. | ✓ |
| Two plans | 00-01 Both helpers + tests; 00-02 Migration. Fewer commits. | |
| Single plan | Everything in one commit. Largest diff; no partial rollback. | |

**User's choice:** Three plans (Recommended).

**Notes:** Matches research preference ("one commit per helper, one test each" plus a dedicated migration plan). Each plan commits with green `mix precommit`, providing three reversible landing zones if anything regresses.

### Question 2 — Authoring order for the helpers?

| Option | Description | Selected |
|--------|-------------|----------|
| Standard — implementation, then tests (Recommended) | Author the helper, then write tests covering happy path + two fallback cases. Matches prior `phase-03-polish` D-18 test style. | ✓ |
| TDD — tests first | Red-green-refactor. 3 test cases per helper first, watch them fail, then implement. | |

**User's choice:** Standard order.

**Notes:** The shape of both helpers is already fully specified (return types, fallback policy, key set). TDD's value is maximal when design is emergent; here it is locked. Standard order also matches the mirror test file convention already in the codebase.

---

## Claude's Discretion

Areas where no user decision was needed and Claude resolved from codebase convention:

- Exact moduledoc prose for the two new helpers — follow `Foglet.TUI.Theme` moduledoc style.
- Test file names and locations — extend `test/foglet_bbs/tui/theme_test.exs` with a `describe "from_state/1"` block; create `test/foglet_bbs/tui/screens/domain_test.exs` for the new module.
- Exact `@type` / `@spec` surface on the new module — infer from context (state map, key atom literal type, `{:ok, module()} | {:error, :not_configured}` return).
- Whether to add a deprecation shim for the pre-migration inlined patterns — no shim.

---

## Research defaults accepted without discussion

These areas were presented but the user chose to use research recommendations. Documented here for audit completeness:

### Screens.Domain.get/2 return shape

**Research recommendation (accepted):** `{:ok, module} | {:error, :not_configured}` per `REQUIREMENTS.md AUDIT-02`. Callers pattern-match on the tagged tuple and supply their own default (e.g. `Foglet.Boards`) in the `:error` branch.

**Alternative considered:** Return the module directly with a built-in default matching today's `|| Foglet.<Module>` pattern. Rejected because REQUIREMENTS.md locks the tagged-tuple shape and the explicit "not configured" branch is more surfaceable in future debugging.

### Theme.from_state/1 fallback policy

**Research recommendation (accepted):** Always returns `%Foglet.TUI.Theme{}`. On missing `session_context` or missing `:theme` key, falls back to `Foglet.TUI.Theme.default/0` (which returns `resolve(:gray)`). Preserves exact observable behavior of all 11 current inlined chains.

**Alternatives considered:**
- Raise on missing theme — rejected because prod always has `session_context`, raising would only fail tests that happen to use a minimal state map.
- Return `{:ok, theme} | :error` — rejected because every current caller expects a `%Theme{}` and adding the unwrap adds noise without value.

### Grep-gate regression enforcement

**Research default (accepted):** Per-phase rubric only. `AUDIT-05` grep gates #8 and #9 are verified at the end of 00-03-PLAN and re-verified at the start of every subsequent per-screen phase.

**Alternatives considered:**
- ExUnit grep assertion — rejected because it would couple test infrastructure to file-layout greps that break as files move.
- Pre-commit hook — rejected because the per-phase rubric is already the contract and hooks add noise to every commit.

---

## Deferred Ideas

- Compile-time or CI grep gate for inlined patterns — revisit if Phases 1–9 surface recurring re-introductions.
- Per-screen default-module helper (e.g. `boards_mod/1`) — plan-phase decides case-by-case when a screen has ≥ 2 call sites referencing the same domain module.
- `{80, 24}` terminal-size extraction (grep gate #7) — resolved per-screen in Phases 5/6/7/8/9 via `@default_terminal_size`.
- `Foglet.TUI.Constants` shared module (FUT-01).
- `Foglet.TUI.Screens` behaviour (FUT-02).
- Deprecation shim for inlined patterns — explicitly rejected.

---

*End of discussion log.*
