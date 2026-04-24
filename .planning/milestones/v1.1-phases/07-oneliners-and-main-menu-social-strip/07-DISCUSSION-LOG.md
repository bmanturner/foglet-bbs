# Phase 07: oneliners-and-main-menu-social-strip - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md - this log preserves the analysis.

**Date:** 2026-04-24
**Phase:** 07-oneliners-and-main-menu-social-strip
**Mode:** assumptions
**Areas analyzed:** Domain Persistence, Oneliner Schema And Validation, Main Menu Rendering, Composer Flow

## Assumptions Presented

### Domain Persistence
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Phase 07 should add `Foglet.Oneliners` plus `Foglet.Oneliners.Entry` as a normal Ecto context/schema backed directly by Postgres, with no GenServer ring buffer required for this phase. | Confident | `.planning/phases/07-oneliners-and-main-menu-social-strip/07-SPEC.md`; `docs/DATA_MODEL.md`; `lib/foglet_bbs/schema.ex`; existing context patterns |

### Oneliner Schema And Validation
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| The oneliner schema should use `body`, `hidden`, `hidden_reason`, `user_id`, `hidden_by_id`, and `timestamps(updated_at: false)`, with `user_id` set on the struct/context path rather than cast from caller attrs. | Confident | `docs/DATA_MODEL.md`; `.planning/phases/07-oneliners-and-main-menu-social-strip/07-SPEC.md`; `lib/foglet_bbs/schema.ex`; project Ecto guidance |

### Main Menu Rendering
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| `MainMenu.render/1` should remain a pure/stateless renderer and read already-loaded recent oneliners from app state, while `Foglet.TUI.App` owns loading/refresh command tasks. | Confident | `.planning/phases/06-chrome-clock-and-main-menu-wiring/06-CONTEXT.md`; `lib/foglet_bbs/tui/screens/main_menu.ex`; `test/foglet_bbs/tui/screens/main_menu_test.exs`; `lib/foglet_bbs/tui/app.ex` |

### Composer Flow
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| The `[O]` flow should use the existing focused modal/form/input infrastructure, not create a separate full-screen composer. | Likely | `.planning/phases/07-oneliners-and-main-menu-social-strip/07-SPEC.md`; `lib/foglet_bbs/tui/app.ex`; `lib/foglet_bbs/tui/widgets/modal/form.ex`; `lib/foglet_bbs/tui/widgets/input/text_input.ex` |

## Corrections Made

### Schema and Validation
- **Original assumption:** Oneliner posting only needs the locked body validation and persistence behavior from the spec.
- **User correction:** In Phase 7, the same user should not be able to add two visible oneliners in a row.
- **Reason:** This keeps the social strip from becoming one user's repeated posts while staying within the lightweight oneliner behavior scoped to Phase 7.

### Deferred Policy
- **Original assumption:** Configurable oneliner policy is out of scope for Phase 7.
- **User correction:** Note a possible 24-hour configurable cooldown as a deferred idea.
- **Reason:** The user raised this as a desirable future behavior, but the locked Phase 7 spec excludes sysop-editable oneliner policy/configuration.

## External Research

No external research was needed. Codebase docs and the locked Phase 7 spec provided enough evidence.
