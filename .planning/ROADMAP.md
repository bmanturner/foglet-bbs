# Roadmap: Foglet BBS v2.0

**Milestone:** v2.0 TUI Runtime Shell & Screen Update Loops
**Created:** 2026-04-28
**Phase numbering:** Continued from previous milestone; starts at Phase 34.

## Overview

v2.0 turns `Foglet.TUI.App` into a small Raxol/process shell and moves screen-local behavior into screen-owned mini update loops. The milestone is a full migration: every current screen must use the new `init/update/render` boundary before the App shell cleanup is complete. No old-screen fallback path is part of the deliverable.

## Phase Summary

| Phase | Name | Goal | Requirements |
|-------|------|------|--------------|
| 34 | 3/3 | Complete    | 2026-04-28 |
| 35 | 2/4 | In Progress|  |
| 36 | Board & Thread Directory Flow | Migrate BoardList and ThreadList, including directory loads, subscription feedback, and route params. | SCREEN-03 |
| 37 | Post & Composer Flow | Migrate PostReader, PostComposer, and NewThread, including post loads, read-pointer flushes, drafts, and submit results. | SCREEN-04 |
| 38 | Account & Operator Workbenches | Migrate Account, Moderation, and Sysop with nested forms, tab lifecycle loads, invites, retries, and save results. | SCREEN-05, SCREEN-06 |
| 39 | App Shell Simplification | Remove screen-specific App state/result manipulation and finalize route/context/subscription/modal shell ownership. | STATE-02, STATE-03, STATE-04, APP-01, APP-02, APP-03, APP-04 |
| 40 | Verification & Documentation | Prove the full migration with reducer, App-shell, render, and precommit coverage; document the new screen pattern. | VERIFY-01, VERIFY-02, VERIFY-03, VERIFY-04, VERIFY-05 |

**Coverage:**
- v2.0 requirements: 26 total
- Requirements mapped: 26
- Unmapped: 0

## Phase Details

### Phase 34: Runtime Contract & Effects

**Goal:** Establish the new screen runtime foundation without adding an old-screen fallback path.

**Requirements:** RUNTIME-01, RUNTIME-02, RUNTIME-03, EFFECT-01, EFFECT-02, EFFECT-03, EFFECT-04, STATE-01

**Scope:**
- Revise `Foglet.TUI.Screen` around `init/1`, `update/3`, and `render/2`.
- Add `Foglet.TUI.Context` to carry user/session/terminal/route/domain data to screens.
- Add `Foglet.TUI.Effect` and constructors or documented tuple shapes for generic runtime effects.
- Add App/runtime helpers for route lookup, current screen state access, state initialization, context construction, and effect interpretation.
- Establish the first state struct conventions for screen modules.

**Success criteria:**
1. A screen can be initialized, updated, and rendered through the new contract in focused tests.
2. App can interpret navigation, task, modal, session, publish, and quit effects without screen-specific effect clauses.
3. Task effects run off-process through existing TUI command plumbing.
4. Screen state is stored by route/screen key and remains local to the owning screen struct.
5. Existing App init/update/view behavior remains green for at least one migrated smoke path.

**Planned execution:**

**Wave 1**
- `34-01` - Contract and data types: `Foglet.TUI.Screen`, `Foglet.TUI.Context`, `Foglet.TUI.Effect`, and focused contract tests.

**Wave 2 *(blocked on Wave 1 completion)***
- `34-02` - App runtime helpers and generic effect interpretation for navigation, task routing, route params, and screen-local state access.

**Wave 3 *(blocked on Waves 1-2 completion)***
- `34-03` - State convention documentation, preservation checks, and targeted runtime foundation verification.

**Cross-cutting constraints:**
- No runtime old-screen vs new-screen fallback detector or compatibility layer is added.
- New screen callbacks use screen-local state plus `Foglet.TUI.Context`, not `%Foglet.TUI.App{}`.
- Task effects execute through `Foglet.TUI.Command.task/2` and route success/failure back through the requesting screen update loop.
- Existing App init/update/view behavior, modal precedence, SizeGate behavior, session hooks, command delivery, and at least one current smoke path remain green.

### Phase 35: Auth & Home Screens

**Goal:** Prove the pattern on entry and home flows by migrating Login, Register, Verify, and MainMenu/oneliners.

**Requirements:** SCREEN-01, SCREEN-02

**Scope:**
- Move Login local state and auth/reset result handling into `Login.update/3`.
- Move Register wizard events and Verify submit/resend events into screen-owned update handlers.
- Move MainMenu navigation, oneliner loads, oneliner composer requests, hide modal requests, and oneliner results into MainMenu state/update.
- Preserve modal precedence, Ctrl+C/quit behavior, session promotion, pending approval termination, and no-email reset honesty.

**Success criteria:**
1. Login, Register, Verify, and MainMenu no longer require App-specific result clauses for their local flows.
2. Auth task results and reset/verification errors are handled by the owning screen reducer.
3. MainMenu owns recent oneliners and selected oneliner state.
4. Existing auth/home tests and render fixtures pass after migration.

**Planned execution:**

**Wave 1**
- `35-01` - Login reducer migration for menu/form/reset/auth task ownership.
- `35-02` - Register and Verify reducer migration for onboarding and verification ownership.
- `35-03` - MainMenu state module and oneliner load/create/hide ownership.

**Wave 2 *(blocked on Wave 1 completion)***
- `35-04` - App local-flow cleanup, target screen docs, and integrated auth/home verification.

**Cross-cutting constraints:**
- Target screens must export `init/1`, `update/3`, and `render/2` without retaining legacy local-flow `handle_key/2` or `render/1` exports.
- Domain side effects remain in Accounts, Verification, Oneliners, and authorization contexts; screens request work through task effects.
- App remains the generic runtime/modal/effect interpreter and routes async results through `{:screen_task_result, screen_key, op, result}`.
- Modal precedence, SizeGate behavior, session routing, quit, pending approval termination, reset honesty, verification failures, and oneliner role gating remain covered.

### Phase 36: Board & Thread Directory Flow

**Goal:** Migrate board and thread browsing so directory state and async loads belong to BoardList/ThreadList.

**Requirements:** SCREEN-03

**Scope:**
- Move board directory data, tree state, subscription feedback, and board activity refresh handling into BoardList state/update.
- Move thread list data, selected thread state, compose navigation, and thread load results into ThreadList state/update.
- Represent selected board/thread route params without relying on App-level `current_board` and `current_thread_list` fields.
- Preserve category Enter expand/collapse, board leaf navigation, subscribe/unsubscribe feedback, and unread refresh behavior.

**Success criteria:**
1. BoardList owns `boards_loaded` and subscription result handling.
2. ThreadList owns `threads_loaded` handling and compose navigation origin.
3. App does not reset BoardList trees or write ThreadList selection data.
4. BoardList/ThreadList behavior tests and canonical render smoke checks pass.

### Phase 37: Post & Composer Flow

**Goal:** Migrate post reading and composition so post data, read state, drafts, and submit results are screen-owned.

**Requirements:** SCREEN-04

**Scope:**
- Move post load results, selected post index, render cache warming, viewport state, and read-pointer flush requests into PostReader state/update.
- Move reply composer drafts, edit/preview state, submit result handling, and post-submit navigation into PostComposer state/update.
- Move new-thread board picker state, compose drafts, board-load results, submit results, and cancel origin into NewThread state/update.
- Preserve markdown rendering, soft wrapping, read-pointer monotonicity, locked/thread policy denials, and existing compose keyboard behavior.

**Success criteria:**
1. PostReader owns `posts_loaded` and read-pointer-result behavior.
2. PostComposer and NewThread own draft state and submission result handling.
3. App no longer warms post render caches or writes composer state.
4. PostReader/composer/new-thread tests and render smoke checks pass.

### Phase 38: Account & Operator Workbenches

**Goal:** Migrate the dense workbenches after the task/effect model is proven on simpler flows.

**Requirements:** SCREEN-05, SCREEN-06

**Scope:**
- Move Account profile/prefs save requests and result handling into Account update logic.
- Keep local theme preview, SSH key actions, invites state, field focus, form errors, and status messages screen-owned.
- Move Moderation workspace loading/results, tab state, table state, and invites behavior into Moderation update logic.
- Move Sysop tab lifecycle loads/results, retry behavior, boards/users/limits/system subviews, nested forms, invites, and revoke flows into Sysop update logic.

**Success criteria:**
1. Account owns profile/prefs save success/error updates and SSH/invite tab state.
2. Moderation owns workspace snapshot/error handling and tab-local state.
3. Sysop owns all lifecycle tab loaded/error slots and retry dispatch.
4. App no longer has account/moderation/sysop loaded-result clauses.
5. Account, Moderation, Sysop, and nested form tests pass.

### Phase 39: App Shell Simplification

**Goal:** Delete the central screen-specific machinery and leave App as a runtime shell.

**Requirements:** STATE-02, STATE-03, STATE-04, APP-01, APP-02, APP-03, APP-04

**Scope:**
- Remove top-level App fields that are screen-owned, such as board/thread/post/oneliner/composer data where migration made them obsolete.
- Remove screen-specific result handlers from `Foglet.TUI.App`.
- Remove helper functions that mutate individual screen state structs from App.
- Finalize route/context/subscription derivation and modal handling semantics.
- Update render fixtures and chrome helpers that previously read `state.screen_state` directly.

**Success criteria:**
1. `Foglet.TUI.App` contains no screen-specific loaded-result handlers for migrated screens.
2. Screen-local helper modules no longer require the full App struct to read/write their state.
3. PubSub subscriptions derive from route/context/screen interests without App mutating screen internals.
4. Modal and SizeGate precedence remain App-owned and tested.
5. App module is materially smaller and reads as a shell over runtime concerns.

### Phase 40: Verification & Documentation

**Goal:** Prove the full migration and leave a clear path for future screen work.

**Requirements:** VERIFY-01, VERIFY-02, VERIFY-03, VERIFY-04, VERIFY-05

**Scope:**
- Add or update reducer/effect tests for every migrated screen family.
- Add App-shell tests for generic effect interpretation and absence of screen-specific state mutation.
- Run canonical TUI render smoke tests and targeted `mix foglet.tui.render` checks.
- Document the new screen contract and migration/add-screen pattern.
- Run `mix precommit`; document any pre-existing blockers if they remain.

**Success criteria:**
1. Existing behavior tests pass for migrated screens.
2. App-shell tests enforce generic effect handling.
3. Render smoke coverage passes for supported terminal sizes.
4. `lib/foglet_bbs/tui/widgets/README.md` or an adjacent TUI doc links to the screen contract guidance.
5. `mix precommit` passes or a concrete pre-existing blocker is documented with evidence.

## Dependency Notes

- Phase 34 must land before any screen migration.
- Phases 35-37 should land before operator workbench migration so the effect/task model is proven on smaller flows.
- Phase 39 must wait until all screens are migrated.
- Phase 40 is the milestone close gate and should not introduce new architecture scope.

---
*Roadmap created: 2026-04-28*
