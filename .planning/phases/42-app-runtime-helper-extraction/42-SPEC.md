# Phase 42: App Runtime Helper Extraction - Specification

**Created:** 2026-04-29
**Ambiguity score:** 0.18 (gate: <= 0.20)
**Requirements:** 6 locked

## Goal

`Foglet.TUI.App` keeps the App struct and Raxol callback entry points while route plumbing, modal runtime behavior, subscription topic refresh, and generic effect interpretation move behind narrow, tested runtime helper APIs.

## Background

`Foglet.TUI.App` is still the concentrated TUI shell module. It owns route encoding, screen-state lookup and initialization, context construction, route-entry dispatch, modal overlay rendering and modal key handling, dynamic PubSub topic calculation and refresh, and interpretation of generic `%Foglet.TUI.Effect{}` values. The current tests already name these runtime contracts through `test/foglet_bbs/tui/app_runtime_contract_test.exs` and `test/foglet_bbs/tui/app_test.exs`, but the implementation surface is still centralized in `lib/foglet_bbs/tui/app.ex`.

Phase 42 starts from the intended post-Phase-41 baseline: the screen contract cleanup and first-class modal-submit effect path are complete. This phase is not responsible for finishing Phase 41's modal-submit migration; it is responsible for making the App shell maintainable after that migration by extracting four runtime concerns into helper modules with clear ownership.

## Requirements

1. **Routing helper**: Route encoding, screen-key derivation, screen-state access, context construction, screen module resolution, screen initialization, route-entry dispatch, and screen reducer routing must be owned by a routing helper with a narrow public API.
   - Current: These responsibilities live directly in `Foglet.TUI.App` through helpers such as `current_route/1`, `screen_key/1`, `build_context/1`, `screen_state_for/2`, `put_screen_state/3`, `init_route_screen_state/3`, `route_screen_update/3`, `context_for_screen_key/2`, and `screen_module_for/2`.
   - Target: Maintainers can find and test route/state plumbing in one routing helper module while `Foglet.TUI.App` delegates to it from Raxol callbacks and effect handling.
   - Acceptance: A focused routing-helper test proves current route encoding, screen-key derivation, context route params, route-owned screen reinitialization, route-entry dispatch, and domain screen-module override fallback without requiring direct tests against private functions in `Foglet.TUI.App`.

2. **Modal runtime helper**: Modal overlay rendering, modal dismissal, confirm callbacks, form submit routing, and modal failure visibility must be owned by a modal helper without screen-specific business logic.
   - Current: `Foglet.TUI.App` renders modal overlays, intercepts keys while `state.modal` is present, handles confirm/info/error/warning/form modal key behavior, clears modal state, and creates generic form-submit failure modals inline.
   - Target: Maintainers can find modal runtime behavior in one modal helper that only depends on App shell state, modal values, theme/widget rendering, and generic effect/routing callbacks.
   - Acceptance: Focused tests prove modal key precedence over screen reducers, confirm yes/no callback behavior, info/error/warning dismissal keys, form submit effect routing to the target screen reducer, and visible failure behavior for invalid form submit targets.

3. **Subscription helper**: Stable runtime subscriptions, user topics, screen-declared topics, and dynamic PubSub topic refresh must be owned by a subscription helper.
   - Current: `Foglet.TUI.App.subscribe/1` builds heartbeat, chrome clock, PubSub forwarder, and initial route-enter subscriptions inline; `build_pubsub_topics/1`, `screen_declared_topics/1`, and `refresh_dynamic_subscriptions/2` also live in App.
   - Target: Maintainers can find subscription construction and topic diffing in one helper while App calls it from `subscribe/1` and after `update/2`.
   - Acceptance: Tests prove unauthenticated subscriptions, heartbeat gating by `session_pid`, user-level topics, screen `subscriptions/2` topics, initial route-enter subscription inclusion, and refresh only when topic lists change.

4. **Effect helper**: Generic effect interpretation must be owned by an effect helper while durable domain mutations remain in owning `Foglet.*` contexts or screen-requested tasks.
   - Current: `Foglet.TUI.App.apply_effect/2` and `apply_effects/2` inline navigation, modal, modal-submit, session, terminal, publish, quit, and task-effect behavior.
   - Target: Maintainers can find generic effect interpretation in one helper that delegates navigation and modal-submit routing through the routing/modal helpers and leaves domain work inside context functions invoked by tasks.
   - Acceptance: Tests prove every existing effect type still returns the same state/command/message behavior: navigation dispatches route entry, modal open/dismiss works, modal submit reaches target `update/3`, session effects update or notify the session process, terminal resize updates state through the existing resize path, publish broadcasts through PubSub, quit returns a quit command, and task results wrap success/error for screen routing.

5. **App shell delegation**: `Foglet.TUI.App` must remain the Raxol application entry point but stop being the owner of the extracted runtime logic.
   - Current: App contains the struct, Raxol callbacks, message normalization, update dispatch, view dispatch, subscription construction, helper functions, and generic effect interpretation.
   - Target: App keeps the struct, `init/1`, `update/2`, `view/1`, `subscribe/1`, message normalization, and high-level shell message dispatch; detailed route, modal, subscription, and generic effect behavior is delegated to helpers.
   - Acceptance: `Foglet.TUI.App` no longer defines private helper clusters for route plumbing, modal key/render logic, PubSub topic construction/refresh, or generic effect interpretation, except thin delegation functions kept only for backward-compatible public test seams when necessary.

6. **Behavior preservation and verification**: Existing TUI runtime behavior must remain stable through helper-level tests and App-level contract coverage.
   - Current: Runtime behavior is covered by App contract tests and broader App tests, but helper boundaries do not exist yet.
   - Target: Existing behavior remains intact, and new tests make each extracted helper's ownership falsifiable without relying on text-presence assertions.
   - Acceptance: Existing `test/foglet_bbs/tui/app_runtime_contract_test.exs` coverage still passes or is migrated to helper-level contract tests with equivalent behavioral assertions; `rtk mix precommit` passes after implementation.

## Boundaries

**In scope:**
- Create routing, modal, subscription, and effect runtime helper modules under the `Foglet.TUI.App` runtime boundary.
- Move route encoding, screen state plumbing, context building, screen module resolution, screen reducer dispatch, and route-entry dispatch out of `Foglet.TUI.App`.
- Move modal overlay rendering, modal key precedence, modal dismissal/confirm/form behavior, and generic modal-submit failure visibility out of `Foglet.TUI.App`.
- Move subscription construction, PubSub topic derivation, screen `subscriptions/2` delegation, and dynamic topic refresh out of `Foglet.TUI.App`.
- Move generic `%Foglet.TUI.Effect{}` interpretation out of `Foglet.TUI.App`, preserving existing effect semantics.
- Add or migrate behavioral tests for each helper boundary and keep App-level Raxol callback behavior covered.

**Out of scope:**
- Completing Phase 41's legacy screen-contract or modal-submit migration - Phase 42 assumes the intended post-Phase-41 baseline.
- Decomposing large screen modules such as PostReader, Sysop, Login, MainMenu, NewThread, or Account - covered by Phase 43.
- Changing screen reducer contracts, route param shapes, or the target `{:modal_submit, kind, payload}` reducer message shape - this phase extracts ownership, not screen APIs.
- Adding new TUI screens, widgets, end-user workflows, or browser workflows - v2.1 is stability and maintenance hardening.
- Moving durable domain mutations into runtime helpers - domain side effects stay in `Foglet.*` contexts and screen-requested task functions.
- Replacing Raxol subscriptions, `PubSubForwarder`, or `InitialRouteEnterForwarder` - this phase may relocate wiring, not change the subscription mechanism.
- Adding tests that only assert the presence or absence of rendered text - project testing standards forbid that style.

## Constraints

- Phase 42 is planned against the post-Phase-41 code shape, including a first-class modal-submit effect.
- `Foglet.TUI.App` remains the Raxol application module and owns the App struct fields.
- Helper APIs must be narrow enough that a maintainer can identify which helper owns routing, modal, subscription, or effect behavior from module names and public functions.
- Helper modules must not introduce durable domain writes, render-time data loading, or process-dictionary handoffs.
- Modal ownership stays App-shell-owned; screens request modal work through effects or screen-local state where already established.
- Route-owned screen reinitialization behavior for `:thread_list`, `:post_reader`, `:post_composer`, and `:new_thread` must be preserved unless a later plan explicitly changes the route model.
- Dynamic subscription refresh must continue to use `Foglet.TUI.PubSubForwarder.refresh/1` only when effective topic lists change.
- Use `rtk` for project commands and run `rtk mix precommit` after implementation.

## Acceptance Criteria

- [ ] A routing helper owns current route encoding, screen keys, screen-state reads/writes, context construction, screen module resolution, route initialization, route-entry dispatch, and screen reducer routing.
- [ ] A modal helper owns modal overlay rendering, modal key precedence, dismiss/confirm behavior, form submit routing, and generic modal failure visibility.
- [ ] A subscription helper owns stable runtime subscription construction, PubSub topic derivation, screen `subscriptions/2` delegation, and dynamic topic refresh.
- [ ] An effect helper owns interpretation of all existing `%Foglet.TUI.Effect{}` types while delegating route/modal operations through the relevant helpers.
- [ ] `Foglet.TUI.App` keeps the struct and Raxol callbacks but delegates the extracted runtime concerns through the helper APIs.
- [ ] Existing App runtime contract behavior is preserved by migrated or additional behavioral tests; no coverage relies only on rendered text presence.
- [ ] `rtk mix precommit` passes after implementation.

## Ambiguity Report

| Dimension           | Score | Min   | Status | Notes |
|---------------------|-------|-------|--------|-------|
| Goal Clarity        | 0.88  | 0.75  | met    | App keeps shell callbacks/struct; four runtime concerns move to helpers. |
| Boundary Clarity    | 0.82  | 0.70  | met    | Phase starts after Phase 41 and excludes screen decomposition/new behavior. |
| Constraint Clarity  | 0.75  | 0.65  | met    | Public helper APIs, current route/modal/subscription/effect semantics, and App ownership are locked. |
| Acceptance Criteria | 0.78  | 0.70  | met    | Helper-specific behavioral tests and precommit are required. |
| **Ambiguity**       | 0.18  | <=0.20| met    | Gate passed after round 1. |

Status: met = dimension meets minimum, below = planner treats as assumption.

## Interview Log

| Round | Perspective | Question summary | Decision locked |
|-------|-------------|------------------|-----------------|
| 1 | Researcher | What baseline should Phase 42 assume given Phase 41 is partially executed? | Spec Phase 42 against the intended post-Phase-41 state, including modal-submit effects being complete. |
| 1 | Researcher | What is the target deliverable for extracted App runtime helpers? | Each routing/modal/subscription/effect helper exposes a narrow documented public API covered by focused tests. |
| 1 | Researcher | How much behavior should remain directly in `Foglet.TUI.App`? | App keeps the struct and Raxol callbacks while delegating route, modal, subscription, and generic effect logic. |

---

*Phase: 42-app-runtime-helper-extraction*
*Spec created: 2026-04-29*
*Next step: $gsd-discuss-phase 42 - implementation decisions (how to build what's specified above)*
