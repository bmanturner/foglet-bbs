# Phase 40: Verification & Documentation - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the analysis.

**Date:** 2026-04-29T14:29:07Z
**Phase:** 40-verification-documentation
**Mode:** assumptions
**Areas analyzed:** Deferred Cleanup Register, Legacy Callback Removal, Modal Failure Fix, Breadcrumb Completion, Verification And Docs

## Assumptions Presented

### Deferred Cleanup Register
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Phase 40 should start by inventorying all Phase 39 carry-forward items, then close each as fixed, intentionally excluded, or still blocking with evidence. | Confident | `.planning/phases/40-verification-documentation/40-SPEC.md`; `.planning/phases/39-app-shell-simplification/39-SUMMARY.md`; `.planning/phases/39-app-shell-simplification/deferred-items.md`; `.planning/phases/39-app-shell-simplification/39-REVIEW-FIX.md` |

### Legacy Callback Removal
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Production runtime should remove `Foglet.TUI.Screen` transitional callbacks and App's legacy dispatch/render fallback once tests or fixtures are updated; helper modules with local `handle_key/2` are not the same target unless they implement the screen behavior. | Likely | `lib/foglet_bbs/tui/screen.ex`; `lib/foglet_bbs/tui/app.ex`; `lib/foglet_bbs/tui/screens/post_reader.ex`; `lib/foglet_bbs/tui/screens/post_composer.ex`; `lib/foglet_bbs/tui/screens/new_thread.ex` |

### Modal Failure Fix
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| The Account/MainMenu doomed-submit failures should be fixed by preserving/replaying `Modal.Form.submit_state` or explicitly transitioning the modal form to `{:error, _}` on async failure, not by deleting those tests or loosening assertions. | Likely | `test/foglet_bbs/tui/screens/account_test.exs:1242`; `test/foglet_bbs/tui/screens/account_test.exs:1271`; `lib/foglet_bbs/tui/widgets/modal/form.ex`; `lib/foglet_bbs/tui/screens/main_menu.ex` |

### Breadcrumb Completion
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Remaining production screens should emit explicit `breadcrumb_parts`; keeping `["Foglet"]` is acceptable only when that is the intentional breadcrumb and is actively tested. | Likely | `test/foglet_bbs/tui/layout_smoke_test.exs`; `test/foglet_bbs/tui/widgets/chrome/breadcrumb_migration_test.exs`; `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex`; `.planning/phases/39-app-shell-simplification/39-SUMMARY.md` |

### Verification And Docs
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Phase 40 should prove the migration through a coverage inventory, focused reducer/effect tests, App-shell tests, targeted render smoke at required sizes, then document the new screen contract in a TUI-adjacent doc linked from the widget/TUI README. | Confident | Phase 40 SPEC requirements 6-11; `.planning/codebase/TESTING.md`; `test/foglet_bbs/tui/app_runtime_contract_test.exs`; `test/foglet_bbs/tui/layout_smoke_test.exs`; `lib/foglet_bbs/tui/widgets/README.md` |

## Corrections Made

### Verification And Docs
- **Original assumption:** Phase 40 should run targeted render smoke at `64x22`, `80x24`, and `132x50`.
- **User correction:** The user does not care about targeted render smoke tests at various terminal sizes.
- **Applied decision:** Because the SPEC locks render smoke as a close-gate requirement, planning should keep this evidence lightweight and minimum-useful rather than building an expansive terminal-size campaign.

## External Research

No external research was performed. The repo and phase artifacts provided enough evidence.
