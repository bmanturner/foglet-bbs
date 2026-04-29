# Phase 35: Auth & Home Screens - Specification

**Created:** 2026-04-28
**Ambiguity score:** 0.16 (gate: <= 0.20)
**Requirements:** 7 locked

## Goal

Login, Register, Verify, and MainMenu/oneliners become pure screen-owned update-loop flows using screen-local state and `Foglet.TUI.Context`, with their auth/home local state and task results no longer handled by screen-specific App clauses.

## Background

Phase 34 added the runtime foundation: `Foglet.TUI.Screen` now supports `init/1`, `update/3`, and `render/2`; `Foglet.TUI.Context` exposes the narrow screen-facing runtime boundary; `Foglet.TUI.Effect` provides generic navigation, task, modal, session, terminal, publish, and quit effects; and `Foglet.TUI.App` can interpret those effects and route `{:screen_task_result, screen_key, op, result}` back through a screen reducer.

The target auth/home screens still primarily use the legacy `render/1` and `handle_key/2` path over `%Foglet.TUI.App{}`. `Login` stores sub-state in `screen_state[:login]` but its login result is still handled through `App.do_update({:login_result, result})` and `App.do_update({:task_error, :login, reason})`. `Register` still returns `{:register_wizard, event}` commands that App delegates back to `Register.handle_wizard_event/2`. `Verify` still routes developer/command events through `App.do_update({:verify_event, event})`. `MainMenu` is documented as stateless even though App owns `recent_oneliners`, `selected_oneliner_index`, `pending_hide_oneliner_id`, oneliner load/submit/hide task result clauses, and modal request plumbing.

Phase 35 proves the production migration pattern on entry and home flows before board/thread/post/operator migrations begin. The phase must preserve existing user-facing auth behavior while removing App-specific local-flow ownership for the target screens.

## Requirements

1. **Login update ownership**: `Foglet.TUI.Screens.Login` handles menu/form/reset keys and login task success/failure through `update/3` over Login-owned local state and `Foglet.TUI.Context`.
   - Current: Login key handling uses `handle_key/2` over App state, and login task results are handled by App clauses before calling `Login.handle_login_result/2`.
   - Target: Login exposes the new screen contract for its local flow, requests authentication/reset work through explicit effects or equivalent new-runtime commands, and consumes login task results through `Login.update/3`.
   - Acceptance: Focused tests drive Login through `init/1` and `update/3` for menu navigation, login submission, success to main menu or verify, invalid credentials, pending/rejected/suspended modals, reset request, and reset token consumption without calling App's `{:login_result, _}` or `{:task_error, :login, _}` clauses.

2. **Register update ownership**: `Foglet.TUI.Screens.Register` handles invite step, combined registration step, registration outcomes, and pending-approval termination requests through `update/3`.
   - Current: Register key handling returns `{:register_wizard, event}` commands that App delegates back into `Register.handle_wizard_event/2`, and submission logic mutates App-shaped state directly.
   - Target: Register owns wizard transitions and registration result handling in its reducer, uses screen-local state for collected fields/errors, and emits runtime effects for navigation, modal display, session promotion, and pending-approval termination.
   - Acceptance: Tests drive invite-only, open, and sysop-approved registration paths through Register `update/3`; no App-specific `{:register_wizard, _}` delegation is required for those paths.

3. **Verify update ownership**: `Foglet.TUI.Screens.Verify` handles code entry, submit, resend, cooldown, no-user, success, and failure outcomes through `update/3`.
   - Current: Verify key handling and `handle_verify_event/2` operate on App-shaped state, and App owns the `{:verify_event, event}` delegation hook.
   - Target: Verify owns its state transitions and result handling through `Verify.update/3`, including submit/resend work and modal effects.
   - Acceptance: Verify tests prove character entry, backspace, submit success, invalid/expired codes, cooldown, resend success/failure, and no-user handling through the new update loop without using App's `{:verify_event, _}` clause.

4. **MainMenu state ownership**: `Foglet.TUI.Screens.MainMenu` owns recent oneliners, selected oneliner index, pending hide target, menu navigation, oneliner composer/hide modal requests, and oneliner task results in screen-local state.
   - Current: MainMenu is documented as stateless while App stores oneliner rows and selection, opens composer/hide modals, submits/hides oneliners, clamps selection, and handles oneliner loaded/created/hidden results.
   - Target: MainMenu has a first-class local state type that stores oneliner rows, selection, and pending hide target; MainMenu `update/3` owns navigation/actions and handles load/create/hide task results.
   - Acceptance: MainMenu tests prove load, select up/down, open composer, cancel composer, submit success/error, open hide modal, hide validation, hide success/error, and visible-action gating through MainMenu state/update rather than App top-level oneliner fields.

5. **App local-flow clause removal**: App no longer contains screen-specific local-flow handlers for Phase 35 auth/home behavior.
   - Current: App has clauses for `{:login_result, _}`, `{:task_error, :login, _}`, `{:register_wizard, _}`, `{:verify_event, _}`, `{:load_oneliners}`, `{:oneliners_loaded, _}`, `{:open_oneliner_composer}`, `{:submit_oneliner, _}`, `{:oneliner_created, _}`, `{:open_hide_oneliner_modal, _}`, `{:submit_hide_oneliner, _}`, and `{:oneliner_hidden, _}`.
   - Target: Those Phase 35 local-flow concerns are either removed from App or reduced to generic effect/task routing that does not name the production screen's business event.
   - Acceptance: A code-level check or focused test proves auth/home task results route through `{:screen_task_result, screen_key, op, result}` into the owning screen reducer, and App no longer mutates Login/Register/Verify/MainMenu local state for these flows.

6. **Behavior preservation**: Existing auth/home user-facing behavior remains unchanged while ownership moves.
   - Current: Existing tests cover registration modes, no-email reset honesty, reset token consumption, verification delivery failures, status modals, pending approval termination, modal precedence, Ctrl+C/quit handling, session promotion, oneliner composer/hide behavior, and main-menu role/action visibility.
   - Target: The same behaviors pass after migration, with any updated tests asserting reducer state/effects instead of App-owned local fields.
   - Acceptance: Existing focused auth/home tests are updated to the new ownership boundary and pass, including Login/Register/Verify screen tests, MainMenu screen tests, relevant App runtime tests, and render fixture/smoke coverage for the affected screens.

7. **Migration boundary documentation**: The migrated screens' docs and state modules describe their new ownership boundary.
   - Current: Some module docs still state legacy ownership, such as MainMenu being stateless and Login/Register/Verify local state living under App-shaped `screen_state`.
   - Target: Module docs and state modules accurately describe screen-local state, reducer-owned events, context usage, and which effects are emitted to App.
   - Acceptance: The target screen modules no longer document obsolete App-owned local-flow behavior, and docs identify App as runtime/effect interpreter rather than owner of auth/home state.

## Boundaries

**In scope:**
- Migrate Login local state, auth task requests, login task results, reset request, and reset-token consumption to the new screen update loop.
- Migrate Register wizard state, registration submission, verification delivery outcome handling, and pending-approval termination request ownership to the new screen update loop.
- Migrate Verify code buffer, submit/resend events, cooldown state, verification results, and resend results to the new screen update loop.
- Migrate MainMenu navigation, oneliner loading, oneliner selection, composer/hide modal requests, create/hide submission, and create/hide results to MainMenu local state/update.
- Preserve existing auth/home behavior: modal precedence, Ctrl+C/quit behavior, session promotion, pending approval termination, no-email reset honesty, verification failure copy, and oneliner authorization visibility.
- Update focused tests so they assert reducer state/effects and generic App routing rather than App-owned local-flow fields.
- Update target screen docs and state modules to match the new ownership boundary.

**Out of scope:**
- Migrating BoardList or ThreadList - Phase 36 owns board/thread directory migration.
- Migrating PostReader, PostComposer, or NewThread - Phase 37 owns post and composer migration.
- Migrating Account, Moderation, or Sysop - Phase 38 owns account/operator workbench migration.
- Removing all remaining legacy screen-specific App state/result clauses - Phase 39 owns final App shell simplification after all screen families migrate.
- Visual redesign of Login, Register, Verify, MainMenu, oneliner rows, or modal forms - this phase is ownership/runtime migration.
- Changing durable auth, verification, reset, oneliner, moderation, or authorization domain behavior - context modules remain the domain boundary.
- Adding browser-facing auth or home workflows - Foglet remains SSH/TUI-first.

## Constraints

- The primary product surface remains SSH/TUI; no end-user Phoenix browser flow is introduced.
- Screens must use the Phase 34 screen contract: screen-local state plus `Foglet.TUI.Context`, not `%Foglet.TUI.App{}`.
- Domain side effects remain in `Foglet.Accounts`, `Foglet.Accounts.Verification`, `Foglet.Oneliners`, authorization contexts, and related domain modules.
- Async domain work requested by screens must use the Phase 34 task-effect path through `Foglet.TUI.Command.task/2`.
- Task success/failure for migrated flows must return through the requesting screen's `update/3`.
- Modal precedence and SizeGate behavior remain App/runtime responsibilities.
- Route/session/publish/quit work remains App/runtime effect interpretation; screens request those outcomes, they do not own SSH lifecycle mechanics.
- Existing render contracts should remain stable except where minimal adaptation is required by the ownership migration.

## Acceptance Criteria

- [ ] Login can be initialized, updated, and rendered through `init/1`, `update/3`, and `render/2` without requiring legacy `handle_key/2` or App-specific login result clauses for local login/reset flows.
- [ ] Register invite/open/sysop-approved registration paths run through Register `update/3`, including pending-approval termination requests, without App `{:register_wizard, _}` delegation.
- [ ] Verify code entry, submit, resend, cooldown, success, and failure paths run through Verify `update/3` without App `{:verify_event, _}` delegation.
- [ ] MainMenu stores recent oneliners, selected oneliner index, and pending hide target in MainMenu screen-local state, not App top-level oneliner fields.
- [ ] MainMenu handles oneliner load/create/hide task results through MainMenu `update/3` via screen-tagged task results.
- [ ] App auth/home local-flow clauses are removed or reduced to generic effect/task routing that does not mutate target screen local state directly.
- [ ] Session promotion, pending approval termination, modal precedence, Ctrl+C/quit, no-email reset honesty, verification delivery failures, and oneliner composer/hide behavior remain covered and passing.
- [ ] Target screen docs and state modules describe the new screen-owned ownership boundary.
- [ ] Targeted auth/home screen tests, App runtime tests, and affected render smoke/fixture checks pass.

## Ambiguity Report

| Dimension           | Score | Min   | Status | Notes |
|---------------------|-------|-------|--------|-------|
| Goal Clarity        | 0.90  | 0.75  | met    | Pure update-loop migration for four target screen flows is locked. |
| Boundary Clarity    | 0.83  | 0.70  | met    | Board/thread/post/operator and final App cleanup are explicitly deferred. |
| Constraint Clarity  | 0.78  | 0.65  | met    | Phase 34 contract, task effects, SSH/TUI surface, and behavior preservation are locked. |
| Acceptance Criteria | 0.80  | 0.70  | met    | Pass/fail reducer ownership, App-clause removal, and preservation checks are specified. |
| **Ambiguity**       | 0.16  | <=0.20| met    | Gate passed after round 1. |

Status: met = meets minimum, below = below minimum (planner treats as assumption)

## Interview Log

| Round | Perspective | Question summary | Decision locked |
|-------|-------------|------------------|-----------------|
| 1 | Researcher | What is the core deliverable for Login/Register/Verify/MainMenu? | Pure update loops: target screens own init/update/render state and local results; old App local-flow clauses are removed for these flows. |
| 1 | Researcher | How far should MainMenu/oneliners move? | MainMenu owns recent rows, selected row, pending hide target, composer/hide requests, and oneliner task results in screen-local state. |
| 1 | Researcher | Which preservation boundary matters most? | Auth edge cases remain explicit: session promotion, pending approval termination, reset honesty, verification delivery failures, modal precedence, and Ctrl+C/quit. |

---

*Phase: 35-auth-home-screens*
*Spec created: 2026-04-28*
*Next step: $gsd-discuss-phase 35 - implementation decisions (how to build what's specified above)*
