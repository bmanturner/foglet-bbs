# Phase 42: App Runtime Helper Extraction - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the analysis.

**Date:** 2026-04-29
**Phase:** 42-app-runtime-helper-extraction
**Mode:** assumptions
**Areas analyzed:** Helper Module Boundaries, Public API And Test Seams, Extraction Order, Coverage

## Assumptions Presented

### Helper Module Boundaries

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Helper modules should live under `Foglet.TUI.App.*` as `Routing`, `Modal`, `Subscriptions`, and `Effects`, because the extracted logic is App-shell runtime behavior, not general TUI domain behavior. | Confident | `lib/foglet_bbs/tui/app.ex`; `.planning/codebase/CONCERNS.md`; `.planning/phases/42-app-runtime-helper-extraction/42-SPEC.md` |

### Public API And Test Seams

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Preserve thin public compatibility seams on `Foglet.TUI.App` where current tests or external callers use them, delegating to helpers during migration. | Likely | `test/foglet_bbs/tui/app_runtime_contract_test.exs`; `test/foglet_bbs/tui/app_test.exs`; `.planning/phases/42-app-runtime-helper-extraction/42-SPEC.md` |

### Extraction Order

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Extraction should happen in dependency order: Routing first, Modal second, Effects third, Subscriptions fourth, with App-level callbacks staying as the integration harness. | Likely | `lib/foglet_bbs/tui/app.ex` route helpers feed modal submit/effects/subscription topic derivation; `lib/foglet_bbs/tui/effect.ex`; `lib/foglet_bbs/tui/pub_sub_forwarder.ex` |

### Coverage

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Tests should migrate most runtime-contract assertions to helper-level tests while keeping App tests for Raxol callback integration, refresh side effects, and end-to-end modal/effect routing. | Confident | `test/foglet_bbs/tui/app_runtime_contract_test.exs`; `test/foglet_bbs/tui/app_test.exs`; `.planning/codebase/TESTING.md` |

## Corrections Made

### Public API And Test Seams

- **Original assumption:** Preserve thin public compatibility seams on `Foglet.TUI.App` where current tests or external callers use them, including route/context/effect helper functions that can delegate to extracted modules during migration.
- **User correction:** Do not preserve anything just for the sake of tests that become irrelevant after the refactor. Remove or rewrite those tests so coverage targets the new functionality and new helper APIs.
- **Reason:** The implementation should optimize for maintainable ownership and meaningful behavior coverage, not old test compatibility.

## External Research

No external research was performed. Codebase and project planning artifacts provided enough evidence for this internal hardening phase.
