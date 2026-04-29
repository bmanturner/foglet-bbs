# Requirements: Foglet BBS v2.0

**Defined:** 2026-04-28
**Milestone:** v2.0 TUI Runtime Shell & Screen Update Loops
**Core Value:** A user can SSH into a living, reliable BBS and participate in conversations through a terminal-native experience that feels like arriving somewhere.

## v2.0 Requirements

### Runtime Contract

- [x] **RUNTIME-01**: A screen can define `init/1`, `update/3`, and `render/2` callbacks that operate on screen-local state and `Foglet.TUI.Context`.
- [x] **RUNTIME-02**: `Foglet.TUI.App` can route normalized input, subscription, and task-result messages to the active screen without requiring the screen to receive the full App struct.
- [x] **RUNTIME-03**: `Foglet.TUI.Context` exposes current user, session context, session pid, terminal size, route params, and domain overrides needed by screens without exposing App internals.

### Effects

- [x] **EFFECT-01**: Screens can request navigation, tasks, modal operations, publish/session operations, terminal-size/session updates, and quit through explicit `Foglet.TUI.Effect` values.
- [x] **EFFECT-02**: `Foglet.TUI.App` interprets effects generically and converts task effects into off-process `Foglet.TUI.Command.task/2` work.
- [x] **EFFECT-03**: Task success and failure messages are routed back through screen `update/3` so async result handling belongs to the screen that requested the work.
- [x] **EFFECT-04**: Navigation effects initialize target screen state and support route parameters such as selected board, thread, post, or origin.

### Screen State Ownership

- [x] **STATE-01**: Every stateful screen has a first-class state struct, and stateless screens are explicit about not storing local state.
- [x] **STATE-02**: Board lists, thread lists, posts, composer drafts, oneliner rows, tab lifecycle slots, and form feedback live in the owning screen state rather than in screen-specific App fields.
- [ ] **STATE-03**: Screen-local helper modules no longer read or write `state.screen_state[:screen]` through the App struct once their owning screen is migrated.
- [x] **STATE-04**: `Foglet.TUI.App` stores screen states by route/screen key and does not manipulate individual screen struct fields after migration.

### Screen Migration

- [x] **SCREEN-01**: Login, Register, and Verify own auth/onboarding key handling, local state, task requests, and auth/verification results through the new update loop.
- [x] **SCREEN-02**: MainMenu owns oneliner state, composer/hide modal requests, oneliner task results, and menu navigation through the new update loop.
- [x] **SCREEN-03**: BoardList and ThreadList own board/thread directory state, subscription feedback, selection state, navigation effects, and async load results through the new update loop.
- [x] **SCREEN-04**: PostReader, PostComposer, and NewThread own post loading, read-pointer flush requests, composer drafts, board picker state, reply/new-thread submission results, and navigation through the new update loop. (Complete in Phase 37 Plan 05.)
- [ ] **SCREEN-05**: Account owns profile, preferences, SSH keys, invite tab state, save results, local theme preview, and form errors through the new update loop.
- [ ] **SCREEN-06**: Moderation and Sysop own tab lifecycle loading, retry behavior, nested form/subview state, invites behavior, and loaded/error results through the new update loop.

### App Shell Simplification

- [x] **APP-01**: `Foglet.TUI.App` owns only runtime shell responsibilities: Raxol callbacks, message normalization, SizeGate/modal precedence, current route, screen state storage, context construction, effect interpretation, subscriptions, session runtime hooks, and rendering dispatch.
- [ ] **APP-02**: `Foglet.TUI.App` no longer has screen-specific loaded-result clauses such as board, thread, post, moderation, sysop, account, or oneliner result handlers after migration.
- [x] **APP-03**: PubSub subscriptions are derived from route/context or screen-declared interests without reintroducing screen-specific state mutation in App.
- [ ] **APP-04**: Modal handling remains App-level for overlay precedence, while screen-owned modal requests flow through generic modal effects.

### Verification

- [ ] **VERIFY-01**: Existing TUI behavior tests and canonical render smoke tests pass for migrated screens at supported terminal sizes.
- [ ] **VERIFY-02**: Screen reducer tests prove key handling, task result handling, and effect emission for each migrated screen family.
- [ ] **VERIFY-03**: App-shell tests prove effects are interpreted generically and screen-specific state fields are not mutated by App.
- [ ] **VERIFY-04**: Documentation explains how to add or migrate a screen using `Context`, `Effect`, and the new screen callbacks.
- [ ] **VERIFY-05**: `mix precommit` runs after the full migration and any pre-existing blockers are explicitly documented if they remain.

## Future Requirements

### Runtime Extensions

- **FUTURE-01**: Screens can declare subscription interests directly if route-derived PubSub topics become insufficient.
- **FUTURE-02**: Route history/back-stack behavior can be added if future flows need more than explicit navigation effects.
- **FUTURE-03**: A typed route module can replace route atoms if route params become complex enough to justify it.

## Out of Scope

| Feature | Reason |
|---------|--------|
| New BBS product capabilities | v2.0 is an architecture milestone for ownership and runtime shape. |
| End-user web UI | Foglet remains SSH-first; Phoenix browser surface is operational infrastructure. |
| Replacing Raxol | The refactor adapts Foglet's screen boundary to the existing runtime. |
| Per-screen processes | The App/Raxol process remains the runtime owner; screens are pure reducers. |
| Email/webhook notification delivery | Dormant seeds do not match this milestone. |
| Visual redesign of screens | Render contracts should remain stable except where minimal adaptation is required. |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| RUNTIME-01 | Phase 34 | Complete |
| RUNTIME-02 | Phase 34 | Complete |
| RUNTIME-03 | Phase 34 | Complete |
| EFFECT-01 | Phase 34 | Complete |
| EFFECT-02 | Phase 34 | Complete |
| EFFECT-03 | Phase 34 | Complete |
| EFFECT-04 | Phase 34 | Complete |
| STATE-01 | Phase 34 | Complete |
| STATE-02 | Phase 39 | Complete |
| STATE-03 | Phase 39 | Pending |
| STATE-04 | Phase 39 | Complete |
| SCREEN-01 | Phase 35 | Complete |
| SCREEN-02 | Phase 35 | Complete |
| SCREEN-03 | Phase 36 | Complete |
| SCREEN-04 | Phase 37 | Complete |
| SCREEN-05 | Phase 38 | Pending |
| SCREEN-06 | Phase 38 | Pending |
| APP-01 | Phase 39 | Complete |
| APP-02 | Phase 39 | Pending |
| APP-03 | Phase 39 | Complete |
| APP-04 | Phase 39 | Pending |
| VERIFY-01 | Phase 40 | Pending |
| VERIFY-02 | Phase 40 | Pending |
| VERIFY-03 | Phase 40 | Pending |
| VERIFY-04 | Phase 40 | Pending |
| VERIFY-05 | Phase 40 | Pending |

**Coverage:**
- v2.0 requirements: 26 total
- Mapped to phases: 26
- Unmapped: 0

---
*Requirements defined: 2026-04-28*
*Last updated: 2026-04-28 after v2.0 requirements definition*
