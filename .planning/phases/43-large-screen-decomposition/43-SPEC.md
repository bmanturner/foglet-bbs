# Phase 43: Large Screen Decomposition - Specification

**Created:** 2026-04-29
**Ambiguity score:** 0.195 (gate: <= 0.20)
**Requirements:** 6 locked

## Goal

PostReader, Sysop, Login, MainMenu, NewThread, and Account expose clear reducer-facing screen modules, sibling state owners, and sibling render entry points so maintainers can change rendering or reducer behavior without reading unrelated code paths.

## Background

The v2.1 concerns audit identifies oversized TUI screen modules with mixed reducer and render responsibilities: PostReader, Sysop, Login, MainMenu, NewThread, and Account. Current scouting shows sibling state modules already exist for all six named screens, and Sysop/Account already delegate some tab or surface behavior to submodules. The remaining gap is that render helpers, reducer clauses, task result handling, cache-warming, and tab/body rendering still live together in the top-level screen modules. `lib/foglet_bbs/tui/SCREEN_CONTRACT.md` already defines the desired contract: screens own local state, reducers return effects, and render paths are pure over loaded state. Phase 43 turns that convention into a clearer module shape for the six audited screens.

## Requirements

1. **All audited screens decomposed**: PostReader, Sysop, Login, MainMenu, NewThread, and Account must each receive the agreed decomposition treatment.
   - Current: The audited top-level screen files still contain mixed reducer and render helper code, with file sizes ranging from roughly 522 to 901 lines in current scouting.
   - Target: Each named screen has a top-level reducer-facing module, a sibling `State` module, and a sibling `Render` module or equivalent render entry point under `lib/foglet_bbs/tui/screens/<screen>/`.
   - Acceptance: A verifier can list all six named screens and find the screen module, state owner, and render entry point for each one by module and file name.

2. **Render helpers extracted**: Rendering logic for each named screen must move out of the top-level reducer-facing module.
   - Current: Top-level screen modules define screen callbacks beside private `render_*` helpers and body/tab rendering functions.
   - Target: Top-level screen modules call the sibling render entry point from `render/2`; detailed body, tab, and component layout helpers live in the render module or existing screen-owned surface modules.
   - Acceptance: `render/2` in each top-level named screen delegates to the render entry point, and top-level screen modules no longer contain detailed private render helper families for their screen body.

3. **Reducer boundary preserved**: Reducer behavior remains testable through the canonical `init/1`, `update/3`, and `render/2` screen contract.
   - Current: Reducer clauses and helper functions are colocated with render helpers, which makes behavioral tests harder to target without touching render paths.
   - Target: Screen modules retain the reducer-facing public callbacks and may keep reducer helpers only when they are not render-specific; domain work still flows through `Foglet.TUI.Effect` and owning `Foglet.*` contexts.
   - Acceptance: Focused tests can exercise key handling, task results, modal submit handling, route entry, or subscriptions for decomposed screens without invoking render helpers.

4. **State ownership remains explicit**: The local state owner for each named screen must be discoverable and continue to be the single place for screen-local struct shape.
   - Current: All six named screens have sibling state modules, but maintainers still need to inspect top-level screen modules to understand which state fields feed render-only concerns.
   - Target: State structs remain in sibling `state.ex` files, and any new render module consumes those structs without owning durable mutations, subscriptions, tasks, or context-side effects.
   - Acceptance: Each render entry point accepts the screen state and `Foglet.TUI.Context` or derived render model, and no render module performs Repo calls, PubSub subscription changes, task starts, or durable domain writes.

5. **Behavior stability proved**: Existing TUI behavior must remain stable through reducer/effect tests and render smoke verification.
   - Current: The milestone has layout smoke patterns and per-screen tests, but the decomposition itself can accidentally change input handling or render wiring.
   - Target: Each decomposed screen has focused reducer/effect coverage for behavior touched by the split, and render smoke coverage or `mix foglet.tui.render` verification for the screen still succeeds after extraction.
   - Acceptance: The phase evidence names reducer/effect tests and render smoke or CLI render checks for all six screens; tests must not be pure text-presence assertions.

6. **Documentation updated**: The screen decomposition pattern must be documented for future TUI work.
   - Current: `SCREEN_CONTRACT.md` documents screen callbacks and state, and the widget README references stateful widget conventions, but the large-screen render extraction target is not captured as a maintenance pattern.
   - Target: TUI documentation states when a screen should use sibling `state.ex` and `render.ex` modules, what the top-level screen module should retain, and what render modules must not do.
   - Acceptance: A maintainer reading TUI docs can identify the expected module ownership split and the purity constraints for render modules without opening the phase plan.

## Boundaries

**In scope:**
- Decompose PostReader, Sysop, Login, MainMenu, NewThread, and Account.
- Add or use sibling `Render` modules, plus existing or adjusted sibling `State` modules.
- Preserve top-level screen modules as the reducer-facing public screen contract.
- Add focused reducer/effect tests for behavior affected by the extraction.
- Add or update render smoke evidence for the six named screens.
- Update TUI documentation for the decomposition pattern.

**Out of scope:**
- Changing user-facing TUI workflows or adding browser workflows - this phase is maintenance hardening only.
- Solving PostReader eager loading, render-cache eviction, or content-query invariants - those are Phase 44 concerns.
- Extracting App routing, modal, subscription, or effect runtime helpers - that is Phase 42.
- Replacing Raxol or changing shared widget contracts - v2.1 hardens the current Raxol-based TUI.
- Broad domain context rewrites - screen decomposition must keep domain mutations in owning `Foglet.*` contexts.
- Golden snapshot tests that assert only static text exists - project testing rules reject pure text-presence tests.

## Constraints

- Use the canonical `Foglet.TUI.Screen` callbacks: `init/1`, `update/3`, `render/2`, and optional `subscriptions/2`.
- Render modules must remain pure over already-loaded screen state and context-derived render data.
- Route colors and display styling through `Foglet.TUI.Theme` and existing widgets.
- Keep durable side effects in `Foglet.*` contexts and runtime work behind `Foglet.TUI.Effect`.
- Preserve SSH-first terminal UI behavior; no end-user browser surface is introduced.
- Prefer existing screen submodule patterns already present in Sysop, Account, and sibling `State` modules.

## Acceptance Criteria

- [ ] PostReader has a reducer-facing screen module, sibling state owner, and sibling render entry point.
- [ ] Sysop has a reducer-facing screen module, sibling state owner, and sibling render entry point.
- [ ] Login has a reducer-facing screen module, sibling state owner, and sibling render entry point.
- [ ] MainMenu has a reducer-facing screen module, sibling state owner, and sibling render entry point.
- [ ] NewThread has a reducer-facing screen module, sibling state owner, and sibling render entry point.
- [ ] Account has a reducer-facing screen module, sibling state owner, and sibling render entry point.
- [ ] Top-level `render/2` callbacks for the six screens delegate to render entry points instead of containing detailed body render helper families.
- [ ] Reducer/effect tests cover behavior touched by decomposition for each named screen without invoking render helpers.
- [ ] Render smoke verification or `rtk mix foglet.tui.render` evidence covers each named screen after decomposition.
- [ ] TUI documentation describes the large-screen state/render/reducer ownership pattern.
- [ ] `rtk mix precommit` passes after implementation.

## Ambiguity Report

| Dimension           | Score | Min   | Status | Notes |
|---------------------|-------|-------|--------|-------|
| Goal Clarity        | 0.88  | 0.75  | met    | All six audited screens and target ownership shape are named. |
| Boundary Clarity    | 0.82  | 0.70  | met    | In-scope and out-of-scope lists separate decomposition from Phase 42 and Phase 44. |
| Constraint Clarity  | 0.68  | 0.65  | met    | Screen contract, render purity, SSH-first, and testing constraints are explicit. |
| Acceptance Criteria | 0.78  | 0.70  | met    | Per-screen and cross-cutting verification checks are pass/fail. |
| **Ambiguity**       | 0.195 | <=0.20| met    | Gate passed after round 1. |

Status: met = meets minimum, below = planner treats as assumption

## Interview Log

| Round | Perspective | Question summary | Decision locked |
|-------|-------------|------------------|-----------------|
| 1 | Researcher | Which screens must be decomposed? | All six audited screens: PostReader, Sysop, Login, MainMenu, NewThread, and Account. |
| 1 | Researcher | What decomposition boundary is required? | Use a reducer-facing screen module, sibling State, and sibling Render entry point; deeper splits only when already implied. |
| 1 | Researcher | What proof is required? | Focused reducer/effect tests plus render smoke verification for every decomposed screen. |

---

*Phase: 43-large-screen-decomposition*
*Spec created: 2026-04-29*
*Next step: $gsd-discuss-phase 43 - implementation decisions (how to build what is specified above)*
