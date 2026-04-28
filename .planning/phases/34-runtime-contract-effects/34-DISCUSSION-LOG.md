# Phase 34: Runtime Contract & Effects - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution
> agents. Decisions captured in CONTEXT.md are the canonical record.

**Date:** 2026-04-28
**Phase:** 34-runtime-contract-effects
**Mode:** assumptions
**Areas analyzed:** Screen Contract, Migration Boundary, Context Shape, Effect
Model, State And Verification

## Inputs Read

- `.planning/PROJECT.md`
- `.planning/REQUIREMENTS.md`
- `.planning/STATE.md`
- `.planning/ROADMAP.md`
- `.planning/phases/34-runtime-contract-effects/34-SPEC.md`
- `.planning/codebase/ARCHITECTURE.md`
- `.planning/codebase/CONVENTIONS.md`
- `.planning/codebase/STRUCTURE.md`
- `.planning/codebase/TESTING.md`
- `.planning/codebase/STACK.md`
- `.planning/codebase/INTEGRATIONS.md`
- `docs/ARCHITECTURE.md`
- `docs/raxol/getting-started/WIDGET_GALLERY.md`
- `lib/foglet_bbs/tui/widgets/README.md`
- `lib/foglet_bbs/tui/screen.ex`
- `lib/foglet_bbs/tui/app.ex`
- `lib/foglet_bbs/tui/command.ex`
- `lib/foglet_bbs/tui/session_context.ex`
- `lib/foglet_bbs/tui/screens/domain.ex`
- Representative screen/state/test files under `lib/foglet_bbs/tui/screens/`
  and `test/foglet_bbs/tui/`
- Local Raxol runtime files under `vendor/raxol/lib/raxol/core/runtime/`

## Assumptions Presented

### Screen Contract
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Define the new screen boundary as `init/1`, `update/3`, and `render/2`, where screens receive screen-local state plus `Foglet.TUI.Context`, not the full `%Foglet.TUI.App{}`. | Likely | `lib/foglet_bbs/tui/screen.ex`; `lib/foglet_bbs/tui/app.ex`; `.planning/REQUIREMENTS.md`; `34-SPEC.md` |

### Migration Boundary
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Do not add a runtime old-screen/new-screen fallback detector. Phase 34 should create the contract, helpers, and focused proof path, while later phases migrate actual screen families deliberately. | Likely | `.planning/ROADMAP.md`; `34-SPEC.md`; existing screens still implement old callbacks |

### Context Shape
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| `Foglet.TUI.Context` should be a narrow typed struct built from App state: current user, session context, session pid, terminal size, route params, and domain override access. It should not expose full App internals or loaded screen data. | Confident | `lib/foglet_bbs/tui/session_context.ex`; `lib/foglet_bbs/tui/screens/domain.ex`; `.planning/REQUIREMENTS.md` RUNTIME-03; `34-SPEC.md` |

### Effect Model
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Prefer an explicit `Foglet.TUI.Effect` API with typed constructors over ad hoc tuple commands. Generic effects should cover navigation, task, modal, session/publish operations, terminal/session updates, and quit, while task effects continue to execute through `Foglet.TUI.Command.task/2`. | Likely | `lib/foglet_bbs/tui/command.ex`; `vendor/raxol/lib/raxol/core/runtime/command.ex`; `lib/foglet_bbs/tui/app.ex` `process_screen_commands/2`; `34-SPEC.md` |

### State And Verification
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Stateful screens should use first-class state structs with `new/1`; stateless screens should be explicit. Phase 34 tests should focus on the new reducer/effect contract and generic App helpers, not broad visual redesign. | Confident | `PostReader.State`; `BoardList.State`; `Account.State`; `Sysop.State`; `test/foglet_bbs/tui/screens/main_menu_test.exs`; `.planning/REQUIREMENTS.md`; `34-SPEC.md` |

## Corrections Made

No corrections - all assumptions confirmed.

## External Research

No external research performed. Raxol is vendored locally, and the relevant
runtime command/subscription behavior was inspected from `vendor/raxol`.
