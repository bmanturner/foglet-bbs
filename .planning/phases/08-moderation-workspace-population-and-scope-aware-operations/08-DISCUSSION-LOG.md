# Phase 08: moderation-workspace-population-and-scope-aware-operations - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the analysis.

**Date:** 2026-04-24
**Phase:** 08-moderation-workspace-population-and-scope-aware-operations
**Mode:** assumptions
**Areas analyzed:** Domain Surface, Authorization And Scope, Moderation Audit Log, TUI Population, Oneliner Selection and Hide UX

## Assumptions Presented

### Domain Surface
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Phase 8 should introduce `Foglet.Oneliners` / `Foglet.Oneliners.Entry` if Phase 7 has not already landed, and add the actor-first hide operation there rather than in the TUI or a moderation context. | Confident | `.planning/phases/08-moderation-workspace-population-and-scope-aware-operations/08-SPEC.md`; `.planning/phases/07-oneliners-and-main-menu-social-strip/07-CONTEXT.md`; `lib/foglet_bbs/boards.ex` guarded-domain pattern |

### Authorization And Scope
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Hide and workspace population must consume `Foglet.Authorization.scopes_for(actor, action)` as a list and use `Bodyguard.permit(Foglet.Authorization, :hide_oneliner, actor, scope)` for the mutation. | Confident | `.planning/phases/01-authorization-and-scope-backbone/01-CONTEXT.md`; `lib/foglet_bbs/authorization.ex`; `test/foglet_bbs/authorization_test.exs` |

### Moderation Audit Log
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Phase 8 should add a narrow `Foglet.Moderation.Action` schema/context and `mod_actions` migration for `:hide_oneliner` only, not the full reports/sanctions system. | Likely | `.planning/phases/08-moderation-workspace-population-and-scope-aware-operations/08-SPEC.md`; `docs/DATA_MODEL.md`; source search found no existing moderation context or `mod_actions` migration |

### TUI Population
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| The Moderation screen should keep the fixed tab shell and replace placeholder body functions with scoped render state loaded through `Foglet.TUI.App`, while keeping unsupported workflows as honest empty/unavailable states. | Likely | `lib/foglet_bbs/tui/screens/moderation/state.ex`; `lib/foglet_bbs/tui/screens/moderation.ex`; `.planning/phases/07-oneliners-and-main-menu-social-strip/07-CONTEXT.md`; `lib/foglet_bbs/tui/app.ex` |

## Corrections Made

### Oneliner Selection and Hide UX
- **Original assumption:** The first pass did not specify where moderators select an offending oneliner. A premature draft incorrectly placed oneliner hide interaction in the Moderation `QUEUE`.
- **User correction:** `QUEUE` is for reports. Oneliner hide should happen close to where the infringing behavior is found: the main-menu shoutbox/oneliner strip.
- **Captured decision:** All users can select/focus an oneliner. `[Enter]` is reserved for future profile navigation. Moderators/sysops see an inline `[H] Hide oneliner` affordance when authorized. `[H]` launches a required-reason `Modal.Form` flow; after confirm, the oneliner is hidden and disappears from the visible strip. The strip does not need scrolling in this phase. Research should determine exact widgets/primitives.

## External Research

No external research was needed during discussion. The research phase should inspect local Raxol and Foglet widget primitives for the selected-oneliner and modal-form implementation.
