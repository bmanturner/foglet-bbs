# Phase 34: Runtime Contract & Effects - Specification

**Created:** 2026-04-28
**Ambiguity score:** 0.18 (gate: <= 0.20)
**Requirements:** 8 locked

## Goal

Foglet's TUI gains a tested runtime foundation where a screen can be initialized, updated, rendered, and connected to generic App-interpreted effects without migrating every existing production screen in this phase.

## Background

`Foglet.TUI.Screen` currently defines `render/1`, `handle_key/2`, and optional `init_screen_state/1`, and screen modules receive the broad `%Foglet.TUI.App{}` struct. `Foglet.TUI.App` normalizes Raxol messages, stores route/session/modal data, dispatches keys to screens, owns many screen-specific async result clauses, and mutates top-level fields such as `board_list`, `current_thread_list`, `posts`, `recent_oneliners`, plus entries under `screen_state`. `Foglet.TUI.SessionContext` and `Foglet.TUI.Command.task/2` already exist, and widgets already model local reducer-style primitives through `init/1`, `handle_event/2`, and `render/2`. No `Foglet.TUI.Context` or `Foglet.TUI.Effect` module exists yet.

Phase 34 establishes the new screen runtime contract and effect vocabulary so later phases can migrate screen families without inventing their own ownership rules. It must not add a dual-runtime fallback layer or perform the full screen migration; existing untouched screen behavior must stay green while the foundation lands.

## Requirements

1. **Screen contract**: `Foglet.TUI.Screen` defines the new screen-local callback contract: `init/1`, `update/3`, and `render/2`.
   - Current: The behavior exposes `render/1`, `handle_key/2`, and optional `init_screen_state/1`, with screens receiving broad App state.
   - Target: The behavior documents and types callbacks where `init/1` creates screen-local state, `update/3` consumes normalized messages plus `Foglet.TUI.Context`, and `render/2` renders from screen-local state plus context.
   - Acceptance: Focused tests can define a sample screen module that satisfies the new behavior, initializes local state, updates it from a normalized message, and renders without requiring a `%Foglet.TUI.App{}` struct.

2. **Context boundary**: `Foglet.TUI.Context` exposes only the runtime data screens need.
   - Current: Screens read App fields directly, including current user, session context, terminal size, route-ish fields, and domain overrides.
   - Target: A context struct or equivalent typed boundary exposes current user, session context, session pid, terminal size, route params, and domain overrides without exposing App internals.
   - Acceptance: Tests construct context from an App state and prove the resulting value includes the required fields while excluding screen-specific App storage such as `board_list`, `posts`, and `recent_oneliners`.

3. **Effect vocabulary**: Screens can request runtime work through explicit `Foglet.TUI.Effect` values.
   - Current: Screens return App-dispatch tuples or mutate App fields through `handle_key/2` result paths.
   - Target: Effect values or documented tuple shapes cover navigation, tasks, modal open/dismiss, publish/session operations, terminal-size or session updates, and quit.
   - Acceptance: Constructor or shape tests prove every required effect category can be produced and pattern-matched without depending on a specific screen module.

4. **Generic effect interpretation**: `Foglet.TUI.App` can interpret new runtime effects without screen-specific effect clauses.
   - Current: App has many concrete clauses for screen-owned work such as `{:boards_loaded, boards}`, `{:threads_loaded, threads}`, `{:posts_loaded, posts}`, oneliner handling, moderation loads, and sysop tab loads.
   - Target: App has a generic effect interpreter for the Phase 34 effect categories, separated from individual screen business-result handling.
   - Acceptance: App-shell tests feed representative effects into the interpreter and verify navigation, modal, session/publish, task, and quit effects produce the expected App state or Raxol commands without naming a production screen.

5. **Task result routing**: Task effects run off-process and route success or failure back to the requesting screen's `update/3`.
   - Current: `Foglet.TUI.Command.task/2` wraps off-process tasks, but App owns most task-result messages and directly mutates screen-local data.
   - Target: A task effect uses `Foglet.TUI.Command.task/2`, tags results with enough route or screen identity to dispatch success and failure messages back through the owning screen update loop.
   - Acceptance: Tests prove a successful task effect delivers a result message through sample-screen `update/3`, and a failing task produces a failure message that the same sample screen can handle.

6. **Navigation and route params**: Navigation effects initialize target screen state and carry route params.
   - Current: Navigation mostly changes `current_screen`, sometimes triggers App-specific loads, and selected board/thread/post context is held in top-level App fields.
   - Target: Navigation can set a target route or screen key, initialize target screen state through `init/1`, and make route params available through `Foglet.TUI.Context`.
   - Acceptance: Tests navigate to a sample screen with params such as board, thread, post, or origin and verify the initialized screen state and generated context observe those params.

7. **State struct convention**: Phase 34 establishes first-class screen-state conventions without requiring every screen family to complete migration.
   - Current: Some screens use state structs, some use maps, and App still stores or mutates screen-specific top-level fields.
   - Target: The convention for stateful screens is explicit: each stateful screen owns a state struct or documented local state type; stateless screens declare that they do not store local state; representative example code demonstrates the convention.
   - Acceptance: A representative stateful sample or foundation screen uses a first-class state struct, while the spec explicitly leaves full state migration for phases 35-39.

8. **Preservation boundary**: Existing untouched TUI behavior remains green while the new foundation is introduced.
   - Current: Existing tests cover App init/update/view behavior, command task wrapping, screen key handlers, render fixtures, and screen-specific state paths.
   - Target: Phase 34 adds the runtime foundation without adding a legacy/new dual-runtime fallback path and without breaking existing App init/update/view behavior for untouched screens.
   - Acceptance: Existing targeted TUI tests for App, Command, and at least one current screen or render smoke path pass after the foundation is added.

## Boundaries

**In scope:**
- Define the new `Foglet.TUI.Screen` contract around `init/1`, `update/3`, and `render/2`.
- Add `Foglet.TUI.Context` with user, session, session pid, terminal size, route params, and domain override data.
- Add `Foglet.TUI.Effect` values or documented shapes for navigation, tasks, modals, publish/session operations, terminal/session updates, and quit.
- Add App/runtime helpers for current route lookup, current screen-state access, screen-state initialization, context construction, and generic effect interpretation.
- Prove task effects use `Foglet.TUI.Command.task/2` and route success/failure through screen `update/3`.
- Establish state-struct conventions with representative example coverage.
- Preserve existing TUI App behavior for untouched screens during this foundation phase.

**Out of scope:**
- Migrating Login, Register, Verify, or MainMenu/oneliners - Phase 35 owns auth and home screen migration.
- Migrating BoardList or ThreadList - Phase 36 owns board/thread directory migration.
- Migrating PostReader, PostComposer, or NewThread - Phase 37 owns post and composer migration.
- Migrating Account, Moderation, or Sysop - Phase 38 owns account/operator workbench migration.
- Removing all screen-specific App state/result clauses - Phase 39 owns final App shell simplification after migrations.
- Adding an end-user browser UI - Foglet remains SSH-first and Phoenix browser surfaces are operational infrastructure.
- Replacing Raxol or introducing per-screen processes - the new contract adapts the existing runtime and keeps the App/Raxol process as runtime owner.
- Adding new BBS product capabilities or visual redesigns - this phase is architectural runtime work only.

## Constraints

- The primary product surface remains SSH/TUI; no browser-facing user workflow is introduced.
- Raxol remains the rendering and lifecycle runtime.
- Screens may request domain work through effects, but durable behavior and authorization remain in `Foglet.*` contexts.
- Task effects must use `Foglet.TUI.Command.task/2` so domain work stays off the Raxol lifecycle/update path.
- No old-screen fallback layer is added. Existing untouched screen paths may remain in place until their owning migration phases, but the new foundation must not depend on an adapter that hides incomplete migration.
- Existing App init/update/view behavior, modal precedence, SizeGate behavior, session hooks, and command/task delivery must remain compatible for untouched screens.
- Phase 34 is a foundation phase; complete screen family migrations and final App shell deletion are intentionally deferred to phases 35-39.

## Acceptance Criteria

- [ ] `Foglet.TUI.Screen` exposes and documents `init/1`, `update/3`, and `render/2` over screen-local state and `Foglet.TUI.Context`.
- [ ] `Foglet.TUI.Context` can be built from App runtime data and does not expose screen-specific App fields such as `board_list`, `posts`, or `recent_oneliners`.
- [ ] `Foglet.TUI.Effect` covers navigation, tasks, modals, publish/session operations, terminal/session updates, and quit.
- [ ] App/runtime tests prove representative effects are interpreted generically without naming a production screen.
- [ ] Task-effect tests prove success and failure messages return through sample-screen `update/3`.
- [ ] Navigation-effect tests prove target screen initialization and route params are available to the target context.
- [ ] A representative stateful screen or sample uses a first-class state struct, and full screen migration is deferred explicitly.
- [ ] Existing targeted TUI App/Command tests and at least one current screen or render smoke path pass.

## Ambiguity Report

| Dimension           | Score | Min   | Status | Notes |
|---------------------|-------|-------|--------|-------|
| Goal Clarity        | 0.88  | 0.75  | met    | Runtime foundation, not full screen migration |
| Boundary Clarity    | 0.78  | 0.70  | met    | Later screen migrations and App cleanup are excluded |
| Constraint Clarity  | 0.78  | 0.65  | met    | No dual-runtime fallback; existing behavior remains green |
| Acceptance Criteria | 0.78  | 0.70  | met    | Pass/fail tests lock the foundation behavior |
| **Ambiguity**       | 0.18  | <=0.20| met    | Gate passed after round 1 |

Status: met = meets minimum, below = below minimum (planner treats as assumption)

## Interview Log

| Round | Perspective | Question summary | Decision locked |
|-------|-------------|------------------|-----------------|
| 1 | Researcher | What concrete deliverable should Phase 34 prove before screen migrations begin? | Runtime foundation: contract, context, effects, helpers, focused tests, and one minimal representative path. |
| 1 | Researcher | How strict should STATE-01 be in this foundation phase? | Lock conventions plus representative examples; leave every screen's full state migration to later phases. |
| 1 | Researcher | What compatibility boundary applies while the milestone is mid-migration? | Do not add a dual-runtime fallback; existing App init/update/view and untouched screen behavior must remain green. |

---

*Phase: 34-runtime-contract-effects*
*Spec created: 2026-04-28*
*Next step: $gsd-discuss-phase 34 - implementation decisions (how to build what's specified above)*
