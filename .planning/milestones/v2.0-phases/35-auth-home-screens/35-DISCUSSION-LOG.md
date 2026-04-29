# Phase 35: Auth & Home Screens - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or
> execution agents. Decisions captured in CONTEXT.md - this log preserves the
> analysis.

**Date:** 2026-04-28T19:13:17Z
**Phase:** 35-auth-home-screens
**Mode:** assumptions
**Areas analyzed:** Login Migration, Register and Verify Migration, MainMenu
Oneliner Ownership, Modal and Form Submission Boundary, Testing Strategy

## Assumptions Presented

### Login Migration
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| `Login` should keep its existing map-shaped state for this phase while exposing `init/1`, `update/3`, and `render/2` around local state. Login task submission should use the Phase 34 task effect path and consume results in `Login.update/3`. | Confident | `lib/foglet_bbs/tui/screens/login.ex`; `lib/foglet_bbs/tui/screens/login/state.ex`; `lib/foglet_bbs/tui/app.ex` |

### Register And Verify Migration
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| `Register` and `Verify` should preserve current wizard/code-entry semantics and migrate legacy App event names into reducer-owned messages. | Likely | `lib/foglet_bbs/tui/screens/register.ex`; `lib/foglet_bbs/tui/screens/verify.ex`; `test/foglet_bbs/tui/screens/register_test.exs`; `test/foglet_bbs/tui/screens/verify_test.exs` |

### MainMenu Oneliner Ownership
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| `MainMenu` should become stateful with a first-class `main_menu/state.ex` owning recent oneliners, selected index, and pending hide target. App top-level oneliner fields should stop being the source of truth. | Confident | `lib/foglet_bbs/tui/screens/main_menu.ex`; `lib/foglet_bbs/tui/app.ex`; `test/foglet_bbs/tui/screens/main_menu_test.exs` |

### Modal And Form Submission Boundary
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| App should remain the generic modal interpreter, but MainMenu should own composer/hide decisions and oneliner create/hide results. Process-dictionary form stash helpers should be retired if a generic screen event/effect bridge can replace them cleanly. | Likely | `lib/foglet_bbs/tui/app.ex`; `lib/foglet_bbs/tui/screens/main_menu.ex`; `.planning/phases/34-runtime-contract-effects/34-CONTEXT.md` |

### Testing Strategy
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Tests should move toward reducer/effect assertions over `init/1` and `update/3`, preserve behavior edge cases, and avoid brittle text-presence assertions. | Confident | `.planning/phases/35-auth-home-screens/35-SPEC.md`; `.planning/codebase/TESTING.md`; existing auth/home tests |

## Corrections Made

No corrections - all assumptions confirmed.

## External Research

No external research was performed.
