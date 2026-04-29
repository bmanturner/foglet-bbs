# Phase 41: TUI Contract And Modal Effects - Specification

**Created:** 2026-04-29
**Ambiguity score:** 0.15 (gate: <= 0.20)
**Requirements:** 6 locked

## Goal

Foglet's TUI runtime has exactly one public production screen contract (`init/1`, `update/3`, `render/2`) and routes every `Modal.Form` submit payload through a first-class `Foglet.TUI.Effect` path instead of process-dictionary handoffs.

## Background

The current production App dispatch already prefers the canonical screen contract: screen state is initialized through `init/1`, reducer messages are sent through `update/3`, and rendering calls `render/2`. `Foglet.TUI.Screen` still declares legacy optional callbacks for `render/1`, `handle_key/2`, and `init_screen_state/1`, and several production screens still expose those helpers. Tests and smoke helpers also use `init_screen_state/1` extensively, which keeps the old contract alive.

Modal submit routing is also split across hidden process-local state. `Foglet.TUI.App` reads `{Foglet.TUI.App, :pending_screen_modal_submit}` after `Modal.Form.handle_event/2`, `Foglet.TUI.Widgets.Modal.Form.SubmitStash` centralizes another process-dictionary payload stash, and `Foglet.TUI.Screens.Sysop.BoardsView` uses its own `{BoardsView, :pending_submit}` key. These paths make modal submit behavior hard to trace and under-tested at the App shell boundary.

## Requirements

1. **Canonical screen behavior only**: `Foglet.TUI.Screen` must stop declaring `render/1`, `handle_key/2`, and `init_screen_state/1` as behavior callbacks or optional callbacks.
   - Current: `lib/foglet_bbs/tui/screen.ex` declares those callbacks as a bounded compatibility surface.
   - Target: The behavior exposes only `init/1`, `update/3`, `render/2`, and optional `subscriptions/2`.
   - Acceptance: A grep for callback declarations in `Foglet.TUI.Screen` finds no `render/1`, `handle_key/2`, or `init_screen_state/1` callback entries, and `rtk mix compile --warnings-as-errors` succeeds.

2. **No public legacy screen helpers**: Production screen modules must not expose public `render/1`, `handle_key/2`, or `init_screen_state/1` helpers after this phase.
   - Current: Screens including PostReader, NewThread, PostComposer, Sysop, Moderation, Account, Login, Register, Verify, BoardList, and ThreadList expose one or more legacy helper functions.
   - Target: Production screen setup, input, and rendering flow through `init/1`, `update/3`, and `render/2`; reusable setup belongs in state constructors or private helpers instead of public compatibility callbacks.
   - Acceptance: `rtk rg -n "def (render|handle_key|init_screen_state)\\(" lib/foglet_bbs/tui/screens` returns no production screen compatibility function definitions, except functions in non-screen helper modules whose names are not implementing the old `Foglet.TUI.Screen` callbacks.

3. **Canonical tests and smoke helpers**: Screen tests, render fixtures, and layout smoke helpers must construct screen state through `init/1`, explicit state constructors, or App route initialization instead of `init_screen_state/1`.
   - Current: `test/foglet_bbs/tui/layout_smoke_test.exs`, `test/foglet_bbs/tui/app_test.exs`, and multiple screen tests call screen `init_screen_state/1` helpers directly.
   - Target: Tests exercise the same public screen contract production App uses; state-only unit tests may call first-class `State.new/1` or equivalent state-module constructors.
   - Acceptance: `rtk rg -n "init_screen_state" test/foglet_bbs/tui lib/foglet_bbs/tui/SCREEN_CONTRACT.md` finds no remaining recommendation or test dependency on screen-level `init_screen_state/1`, and the migrated tests remain behavioral rather than text-presence-only assertions.

4. **First-class modal submit effect**: `Foglet.TUI.Effect` must provide an explicit modal-submit request that carries the target screen key, submit kind, and payload.
   - Current: Modal submit payloads are communicated by callbacks that write to process dictionaries and are then popped by App or local screen helpers.
   - Target: Modal form submit callbacks can return or emit a `Foglet.TUI.Effect` value that App interprets and routes as `{:modal_submit, kind, payload}` to the target screen's `update/3`.
   - Acceptance: `Foglet.TUI.Effect` has a typed constructor for modal submit, App interprets that effect without using `Process.get/1`, `Process.put/2`, or `Process.delete/1` for modal-submit payload transfer, and existing target screen `{:modal_submit, kind, payload}` reducers still receive the same message shape.

5. **Remove process-dictionary modal submit handoffs**: All current `Modal.Form` submit payload handoffs in the TUI runtime must stop using process dictionaries.
   - Current: App pending submit, `Modal.Form.SubmitStash`, and `Sysop.BoardsView` pending submit paths use process-local storage.
   - Target: `Modal.Form` submit flow preserves explicit return values or effects all the way back to App or the owning screen; `SubmitStash` is deleted or left unused only if no production/test code references it.
   - Acceptance: `rtk rg -n "pending_screen_modal_submit|SubmitStash|pending_submit|Process\\.(get|put|delete)" lib/foglet_bbs/tui test/foglet_bbs/tui` shows no modal-submit payload handoff in production code, allowing unrelated test fakes only when they are not part of modal-submit routing.

6. **Direct modal round-trip coverage**: Tests must prove a form submit travels from modal event handling through App effect interpretation to the target screen reducer, including visible failure behavior.
   - Current: Modal-submit behavior is covered mostly through reducer paths and indirect screen tests; the direct App-shell submit round trip is a known coverage gap.
   - Target: Targeted tests cover successful submit routing, missing or invalid target handling, and failure visibility without relying on a hidden process-dictionary side channel.
   - Acceptance: Tests fail if the App does not deliver a modal submit to target `update/3`, if submit failure is silently swallowed, or if the implementation reintroduces a process-dictionary submit handoff.

## Boundaries

**In scope:**
- Remove the legacy screen callbacks from `Foglet.TUI.Screen`.
- Remove public production-screen `render/1`, `handle_key/2`, and `init_screen_state/1` compatibility helpers.
- Migrate screen tests, render fixtures, and smoke helpers to canonical `init/1`, `update/3`, and `render/2` seams or explicit state constructors.
- Add a first-class modal-submit effect to `Foglet.TUI.Effect`.
- Route App-shell modal form submits through the new effect to target screen `update/3`.
- Replace or delete `Modal.Form.SubmitStash` and `Sysop.BoardsView` process-dictionary submit handoffs.
- Add direct modal-submit round-trip tests for success and failure paths.
- Update `SCREEN_CONTRACT.md` so it describes the post-cleanup contract only.

**Out of scope:**
- Extracting `Foglet.TUI.App` runtime helper modules - covered by Phase 42.
- Decomposing large screen modules into reducer/state/render modules beyond what is necessary to remove legacy callbacks - covered by Phase 43.
- Replacing Raxol or changing the terminal UI product surface - explicitly excluded from v2.1.
- Changing domain context behavior for oneliners, boards, accounts, or sysop mutations - this phase changes modal routing, not domain rules.
- Adding new end-user browser workflows or browser modal flows - Foglet remains SSH-first.
- Adding text-presence-only tests - project testing standards forbid them.

## Constraints

- Preserve the existing screen reducer message shape `{:modal_submit, kind, payload}` at the target screen boundary unless an implementation plan explicitly proves every target can migrate atomically.
- Keep modal ownership in `Foglet.TUI.App`; screens may request modal operations through effects but must not own global modal shell state.
- Keep render functions pure over already-loaded state; this phase must not introduce render-time domain queries, process state, or subscriptions.
- Route colors and widget usage through existing TUI/theme conventions when touched.
- Use `rtk` for project commands.
- Run `rtk mix precommit` after implementation in the execution phase.

## Acceptance Criteria

- [ ] `Foglet.TUI.Screen` exposes only `init/1`, `update/3`, `render/2`, and optional `subscriptions/2`.
- [ ] No production screen module exposes public `render/1`, `handle_key/2`, or `init_screen_state/1` compatibility helpers.
- [ ] TUI tests and render smoke helpers no longer call screen-level `init_screen_state/1`.
- [ ] `Foglet.TUI.Effect` has a typed modal-submit constructor carrying target screen key, submit kind, and payload.
- [ ] App interprets modal-submit effects and routes them to target screen `update/3` as `{:modal_submit, kind, payload}`.
- [ ] App, `Modal.Form`, `SubmitStash`, and `Sysop.BoardsView` no longer use process dictionaries for modal-submit payload transfer.
- [ ] Direct tests cover successful modal-submit routing from form event through App to target screen reducer.
- [ ] Direct tests cover missing or invalid modal-submit target behavior with a visible failure path.
- [ ] `rtk mix precommit` passes after the implementation.

## Ambiguity Report

| Dimension           | Score | Min   | Status | Notes |
|---------------------|-------|-------|--------|-------|
| Goal Clarity        | 0.90  | 0.75  | met    | One canonical screen contract and one explicit modal-submit path. |
| Boundary Clarity    | 0.87  | 0.70  | met    | User selected full legacy helper removal and all modal submit handoffs. |
| Constraint Clarity  | 0.72  | 0.65  | met    | Target reducer message shape, App modal ownership, and no process-dictionary submit handoff are locked. |
| Acceptance Criteria | 0.85  | 0.70  | met    | Direct contract tests and grep-verifiable cleanup criteria are specified. |
| **Ambiguity**       | 0.15  | <=0.20| met    | Gate passed after round 1. |

Status: met = dimension meets minimum, below = planner treats as assumption.

## Interview Log

| Round | Perspective | Question summary | Decision locked |
|-------|-------------|------------------|-----------------|
| 1 | Researcher | How hard should the canonical screen-contract cleanup go? | Remove all legacy public production screen helpers, including `init_screen_state/1`; tests must migrate to `init/1` or explicit state constructors. |
| 1 | Researcher | Which modal-submit handoffs should this phase replace? | Replace all submit handoffs: App pending submit, `SubmitStash`, and `Sysop.BoardsView` pending submit. |
| 1 | Researcher | What proof is required for the modal-submit round trip? | Require direct contract tests for form submit effect emission, App routing to target `update/3`, success behavior, and visible failure/no-target behavior. |

---

*Phase: 41-tui-contract-and-modal-effects*
*Spec created: 2026-04-29*
*Next step: $gsd-discuss-phase 41 - implementation decisions (how to build what's specified above)*
