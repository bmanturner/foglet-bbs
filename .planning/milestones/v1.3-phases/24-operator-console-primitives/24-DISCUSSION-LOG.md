# Phase 24: operator-console-primitives - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the analysis.

**Date:** 2026-04-25
**Phase:** 24-operator-console-primitives
**Mode:** assumptions
**Areas analyzed:** Widget Placement, Table Strategy, Primitive Purity, Visual Contracts, Modal.Form Refresh

## Assumptions Presented

### Widget Placement

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Add `Display.Badge`, `Display.KvGrid`, a new display-level operator table wrapper, and `Workspace.Inspector`; update `Modal.Form` in place. | Confident | `.planning/phases/24-operator-console-primitives/24-SPEC.md`; `SCREENS.md` §Widget And Primitive Work; `lib/foglet_bbs/tui/widgets/README.md`; existing `lib/foglet_bbs/tui/widgets/display/table.ex`; existing `lib/foglet_bbs/tui/widgets/modal/form.ex` |

### Table Strategy

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Wrap/reuse `Display.Table` rather than fork Raxol table logic; add console defaults, fixture coverage, empty-state/selection helpers, and selected-row action return semantics. | Likely | `lib/foglet_bbs/tui/widgets/display/table.ex` already wraps Raxol table, handles sortable/filterable/selectable options, theme routing, and empty tables; Phase 24 SPEC explicitly says to reuse/wrap the existing foundation. |

### Primitive Purity

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Keep all new console primitives presentation-only over caller-provided data. Do not convert Account/Moderation/Sysop tab bodies and do not call domain contexts inside widgets. | Confident | Phase 24 SPEC requirements 7-8; project `AGENTS.md` widget/context boundaries; `lib/foglet_bbs/tui/widgets/README.md`; existing widget patterns. |

### Visual Contracts

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Prefer compact text/glyph output that is width-safe through `TextWidth`, theme-routed through `Theme`/`Presentation.theme_mappings().badges`, and tested at 64x22, 80x24, 132x50. | Confident | `.planning/phases/16-unicode-width-foundation/16-CONTEXT.md`; `.planning/phases/17-theme-and-mode-metadata/17-CONTEXT.md`; `lib/foglet_bbs/tui/presentation.ex`; `lib/foglet_bbs/tui/theme.ex`; `test/foglet_bbs/tui/layout_smoke_test.exs`; `SCREENS.md` Operator Console direction. |

### Modal.Form Refresh

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Preserve `Modal.Form` public behavior and body-only rendering; change only body hierarchy: heading, required markers, inline/base errors, footer. | Confident | `.planning/phases/24-operator-console-primitives/24-SPEC.md`; `SCREENS.md` §Widget And Primitive Work; `lib/foglet_bbs/tui/widgets/modal/form.ex`; `test/foglet_bbs/tui/widgets/modal/form_test.exs`. |

## Corrections Made

No corrections — all assumptions confirmed.

## External Research

None. Codebase and project docs provided sufficient evidence for context capture.
