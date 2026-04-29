# Phase 41: TUI Contract And Modal Effects - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md - this log preserves the analysis.

**Date:** 2026-04-29T17:22:04Z
**Phase:** 41-tui-contract-and-modal-effects
**Mode:** assumptions
**Areas analyzed:** Screen Contract Cleanup, Modal Submit Effects, Coverage And Failure Behavior, Scope Boundaries

## Assumptions Presented

### Screen Contract Cleanup

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Remove legacy callbacks and public helper functions outright, moving test setup to screen `init/1`, App route initialization, `Foglet.TUI.Context`, or explicit `State.new/1` constructors. | Confident | `.planning/phases/41-tui-contract-and-modal-effects/41-SPEC.md`; `.planning/codebase/CONCERNS.md`; `lib/foglet_bbs/tui/screen.ex`; `lib/foglet_bbs/tui/SCREEN_CONTRACT.md`; `test/foglet_bbs/tui/layout_smoke_test.exs`; `test/foglet_bbs/tui/app_test.exs` |

**Why this way:** The spec locks full legacy helper removal, the concerns audit names the compatibility surface as tech debt, and current greps show both behavior callbacks and many test dependencies on `init_screen_state/1`.

**If wrong:** Downstream planning might leave a compatibility seam that the phase explicitly intends to retire, making future screens and tests continue drifting across two contracts.

### Modal Submit Effects

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Add one explicit `Effect.modal_submit/3`-style path and have modal submit callbacks return or emit that effect instead of stashing payloads. | Confident | `.planning/phases/41-tui-contract-and-modal-effects/41-SPEC.md`; `.planning/codebase/CONCERNS.md`; `lib/foglet_bbs/tui/effect.ex`; `lib/foglet_bbs/tui/app.ex`; `lib/foglet_bbs/tui/widgets/modal/form.ex`; `lib/foglet_bbs/tui/widgets/modal/form/submit_stash.ex` |

**Why this way:** Existing effects are the established screen-to-App runtime request channel. Current modal submit behavior is hidden behind App process dictionary keys and `SubmitStash`, and the spec requires explicit effect routing.

**If wrong:** A planner might redesign modal ownership or widget behavior too broadly, increasing blast radius before Phase 42's App extraction work.

### Reducer Boundary Preservation

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Keep target screen reducers receiving `{:modal_submit, kind, payload}` even though the route to that reducer becomes effect-driven. | Confident | `.planning/phases/41-tui-contract-and-modal-effects/41-SPEC.md`; `lib/foglet_bbs/tui/SCREEN_CONTRACT.md`; `lib/foglet_bbs/tui/app.ex`; `test/foglet_bbs/tui/screens/main_menu_test.exs` |

**Why this way:** The spec explicitly preserves this reducer message shape, and existing screen tests already exercise reducer behavior through that tuple.

**If wrong:** The implementation could accidentally force every modal target reducer to migrate at once, widening the phase beyond its cleanup purpose.

### Scope Boundaries

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Replace modal-submit process-dictionary handoffs in this phase, but leave unrelated `Process.put/get` test fakes alone unless they are part of modal submit routing. | Likely | `.planning/phases/41-tui-contract-and-modal-effects/41-SPEC.md`; `.planning/REQUIREMENTS.md`; `test/foglet_bbs/tui/app_test.exs`; `test/foglet_bbs/tui/screens/new_thread_test.exs`; `test/foglet_bbs/tui/screens/post_composer_test.exs`; `test/foglet_bbs/tui/screens/verify_test.exs` |

**Why this way:** The spec targets modal-submit payload transfer, not every test fake that uses the process dictionary. Current tests use process dictionary stubs for unrelated domain fakes.

**If wrong:** The plan could waste Phase 41 effort rewriting unrelated test scaffolding and bleed into broader test infrastructure cleanup.

## Corrections Made

No corrections - all assumptions confirmed.
