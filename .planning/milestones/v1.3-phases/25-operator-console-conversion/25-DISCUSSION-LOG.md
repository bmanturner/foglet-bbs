# Phase 25: operator-console-conversion - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the analysis.

**Date:** 2026-04-25
**Phase:** 25-operator-console-conversion
**Mode:** assumptions
**Areas analyzed:** Modal.Form reuse strategy, ConsoleTable adoption and selection ownership, destructive-action styling, layout smoke harness shape, theme-hygiene test style, ordering and parallelism

## Assumptions Presented

### A. Modal.Form Reuse Strategy For Tab Bodies
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Use `Modal.Form` directly inline for Account profile, Account prefs, Sysop site, Sysop limits — no new tab-body adapter module. | Confident | `widgets/modal/form.ex:17,144-169`; `screens/sysop/boards_view.ex:34,147-148,235-294,443-485` |
| Caveat surfaced for prefs: theme-swatch arrow cycling does not map cleanly to Modal.Form Tab/Enter focus contract. | — | `screens/account/prefs_form.ex:158-177` |

### B. ConsoleTable Adoption And Selection Ownership
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Listings move to `Display.ConsoleTable`; selection moves out of screen-local indices into the wrapped `Display.Table` cursor. | Likely | `widgets/display/console_table.ex:36-72`; `screens/sysop/boards_view.ex:443-485` |

### C. Destructive-Action Styling
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| No new theme slot. Reuse `Presentation.theme_mappings().commands.destructive => :error`. | Confident | `presentation.ex:42-46,96-101`; `chrome/command_bar.ex:26,87,250`; `workspace/inspector.ex:76` |

### D. Layout Smoke Harness Shape
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Existing operator shell tests don't activate tabs and only run at 80x24. Add per-tab fixtures iterating `[{64,22},{80,24}]` with primitive sentinels. | Confident | `test/foglet_bbs/tui/layout_smoke_test.exs:1735-1824` (shell only); `:273-353` (size-contract precedent) |

### E. Theme-Hygiene Test Style
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Use existing `Foglet.TUI.WidgetHelpers.color_atom_leaked?/2` + `color_names/0` render-output helper, not source grep. | Likely | `test/support/foglet/tui/widget_helpers.ex:21,38,60`; consumed across all Phase 24 primitive tests |

### F. Ordering And Parallelism
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Wave 0 establishes shared scaffolding (RadioGroup field, smoke-test pattern, empty-state copy); Account/Moderation/Sysop convert in parallel afterward. | Likely | Disjoint sibling `screens/{account,moderation,sysop}/state.ex`; disjoint context dependencies |

## Corrections Made

No corrections — user accepted all assumptions ("Yes, proceed").

## Decisions From Discussion

### Account prefs theme-cycling under Modal.Form
- **Question:** How should Account prefs handle the theme-cycling interaction under `Modal.Form`?
- **User chose:** Add RadioGroup-style enum field (recommended).
- **Rationale:** Keeps prefs uniform with profile/site/limits forms, preserves the existing arrow-cycle UX, and keeps the Modal.Form refresh as the single forms primitive (consistent with Phase 24 D-05).
- **Captured as:** D-03 in CONTEXT.md.

## Auto-Resolved

Not applicable — interactive run.

## External Research

None performed. Codebase contained sufficient evidence (Phase 24 verification, in-repo precedents, theme contract).
