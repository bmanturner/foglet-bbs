# Phase 36: Board & Thread Directory Flow - Specification

**Created:** 2026-04-28
**Ambiguity score:** 0.14 (gate: <= 0.20)
**Requirements:** 7 locked

## Goal

BoardList and ThreadList own board/thread directory state, route data, async load results, feedback, and navigation decisions through the Phase 34 screen update-loop contract, without App-level board/thread list state mutation.

## Background

Phase 34 added the runtime foundation: `Foglet.TUI.Screen` can expose `init/1`, `update/3`, and `render/2`; `Foglet.TUI.Context` carries route params, terminal/session data, and domain overrides; `Foglet.TUI.Effect` provides navigation, task, modal, publish, session, terminal, and quit effects; and `Foglet.TUI.App` can route `{:screen_task_result, screen_key, op, result}` into screen reducers.

The current BoardList and ThreadList still use the legacy `render/1` and `handle_key/2` path over an App-shaped state. `BoardList.State` exists but only stores `board_tree` and feedback; the loaded board directory lives in App's top-level `board_list`. App owns `{:load_boards}`, `{:boards_loaded, boards}`, subscription task dispatch, subscription result handling, board-list feedback insertion, and board-activity refresh. Board leaf Enter writes `current_board`, switches `current_screen`, resets ThreadList selection under `screen_state`, and emits `{:load_threads, board.id}`.

ThreadList has no first-class state module. Its selected index lives under `screen_state[:thread_list]`, while loaded rows live in App's top-level `current_thread_list`. App owns `{:load_threads, board_id}` and `{:threads_loaded, threads}`. ThreadList Enter writes App's `current_thread`, switches to PostReader, initializes PostReader state, and emits `{:load_posts, thread.id}`. Compose from ThreadList writes NewThread state directly and uses `current_board` as the selected board. App PubSub topic selection still uses `current_board` for ThreadList board subscriptions.

Phase 36 migrates these two directory screens to the new reducer/effect boundary before Phase 37 migrates post reading and composition. The user-facing board and thread browsing behavior must stay stable while ownership moves.

## Requirements

1. **BoardList directory ownership**: `Foglet.TUI.Screens.BoardList` owns board directory loading, loaded directory data, loading/empty state, tree state, and render input through screen-local state and `update/3`.
   - Current: App stores loaded rows in top-level `board_list`, handles `{:boards_loaded, boards}`, and resets BoardList tree state when new rows arrive.
   - Target: BoardList has a first-class local state shape that stores directory rows, tree state, loading status, and feedback; BoardList requests directory loads through task effects and consumes results through `BoardList.update/3`.
   - Acceptance: Focused BoardList reducer tests prove initial load request, successful `:boards_loaded` result, empty directory result, loading render branch, and tree preservation/reset behavior without App writing `board_list` or mutating `screen_state[:board_list]` directly.

2. **BoardList subscription and unread refresh ownership**: BoardList owns subscribe/unsubscribe requests, subscription result feedback, and board activity refresh handling.
   - Current: BoardList key handling emits `{:subscribe_to_board, board_id}` and `{:unsubscribe_from_board, board_id}` tuples; App dispatches the tasks, handles `{:board_subscription_changed, ...}`, writes feedback into BoardList state, and refreshes boards after success. App also refreshes boards on `{:board_activity, board_id, event}` while on BoardList.
   - Target: BoardList `update/3` emits task effects for subscription changes, handles success and failure task results, sets feedback locally, and requests board directory reloads when subscription changes or board activity requires unread counts to refresh.
   - Acceptance: Tests drive subscribe success, unsubscribe success, required-subscription refusal, archived-board failure, generic failure, and board-activity refresh through BoardList `update/3`; App has no board-specific feedback/result clauses for these flows.

3. **Board route params and board navigation**: BoardList represents selected board navigation through route params and ThreadList initialization, not App top-level `current_board`.
   - Current: Board leaf Enter writes `state.current_board`, changes `current_screen` to `:thread_list`, resets `screen_state[:thread_list]`, and emits `{:load_threads, board.id}`.
   - Target: Board leaf Enter emits navigation to `:thread_list` with selected board route params and initializes ThreadList local state from those params; category Enter and left/right still only expand or collapse the tree.
   - Acceptance: Tests prove category Enter expands/collapses without navigation or task effects, board leaf Enter emits a route-param-bearing navigation effect, ThreadList starts with selected index 0 for the selected board, and BoardList no longer writes App `current_board`.

4. **ThreadList directory ownership**: `Foglet.TUI.Screens.ThreadList` owns selected board identity, thread load state, loaded thread rows, selected index, sorting input, and task results through a first-class state module and `update/3`.
   - Current: ThreadList state is a map containing only `selected_index`; App stores loaded rows in top-level `current_thread_list` and handles `{:threads_loaded, threads}`.
   - Target: ThreadList has a typed local state module that stores selected board route data, thread rows, loading status, and selected index; ThreadList requests thread loads through task effects and consumes `:threads_loaded` results through `ThreadList.update/3`.
   - Acceptance: Focused ThreadList reducer tests prove init from board route params, initial thread-load request, successful load result, empty list result, selection clamp behavior, sticky-first/newest-first sorting input, and unread/sticky/locked row state without App `current_thread_list`.

5. **Thread navigation and compose origin**: ThreadList owns thread selection, PostReader navigation handoff, and compose-from-board origin data without App top-level directory fields.
   - Current: ThreadList Enter writes App `current_thread`, switches to `:post_reader`, initializes PostReader state, and emits `{:load_posts, thread.id}`. Compose writes NewThread state directly and derives the selected board from App `current_board`.
   - Target: ThreadList Enter emits navigation and task effects using selected thread route params and thread id; compose emits navigation to `:new_thread` with origin `:thread_list` and selected board route data. Phase 37 remains responsible for migrating PostReader, PostComposer, and NewThread internals.
   - Acceptance: Tests prove Enter on a selected thread emits the post-reader navigation/load handoff without writing App `current_thread`; `C` from ThreadList carries selected board and `origin: :thread_list` into NewThread route/local state; `Q` returns to BoardList and requests a BoardList-owned refresh.

6. **App board/thread clause removal**: App no longer owns board/thread directory local-flow clauses or state fields after this phase.
   - Current: App has BoardList/ThreadList-specific handlers for `{:load_boards}`, `{:boards_loaded, _}`, `{:subscribe_to_board, _}`, `{:unsubscribe_from_board, _}`, `{:board_subscription_changed, ...}`, `{:load_threads, _}`, `{:threads_loaded, _}`, and board-activity refresh, and its struct includes `board_list`, `current_board`, and `current_thread_list`.
   - Target: Board/thread directory work routes through generic screen update/effect/task handling; route params and screen state replace App top-level `board_list`, `current_board`, and `current_thread_list` for BoardList/ThreadList. Any remaining App involvement is generic runtime interpretation, modal/SizeGate precedence, PubSub forwarding, or transition compatibility required by unmigrated post screens.
   - Acceptance: A code-level check or focused App test proves BoardList/ThreadList task results route through `{:screen_task_result, screen_key, op, result}` into the owning reducer, and App no longer mutates BoardList tree state, ThreadList selection, `board_list`, `current_board`, or `current_thread_list` for these flows.

7. **Behavior preservation and documentation**: Existing board/thread user-facing behavior and migration documentation remain accurate after ownership moves.
   - Current: Tests cover BoardList tree rendering, category expand/collapse, board leaf navigation, subscription commands/feedback, required subscription refusal, ThreadList sorting, metadata, row glyphs, compose origin, and domain dispatch. Docs and module comments still describe legacy App-shaped render/handle_key ownership in places.
   - Target: The same behavior passes through reducer/effect tests and canonical render smoke checks, and module docs/state modules describe BoardList/ThreadList as screen-owned reducers over `Foglet.TUI.Context`.
   - Acceptance: Existing BoardList and ThreadList behavior tests are updated to assert screen-local state/effects instead of App top-level fields, layout smoke checks for board/thread screens pass, and target module docs no longer describe App as the owner of board/thread directory state.

## Boundaries

**In scope:**
- Migrate BoardList board directory data, loading state, tree state, feedback, subscription requests, subscription results, and board-activity refresh to BoardList local state/update.
- Migrate ThreadList selected board route data, loaded thread rows, selected index, thread load request/result handling, and empty/loading state to ThreadList local state/update.
- Represent BoardList-to-ThreadList and ThreadList-to-PostReader selected board/thread identity with route params and screen-local state rather than App top-level directory fields.
- Preserve category Enter expand/collapse, left/right tree navigation, board leaf navigation, subscribe/unsubscribe feedback, required subscription protection, unread refresh, ThreadList sorting, thread selection, compose origin, and Q-back behavior.
- Update focused BoardList/ThreadList screen tests and relevant App runtime tests to assert reducer/effect ownership and generic task-result routing.
- Update BoardList/ThreadList docs and state modules to describe the new ownership boundary.

**Out of scope:**
- Migrating PostReader, PostComposer, or NewThread internals - Phase 37 owns post and composer migration.
- Migrating Account, Moderation, or Sysop - Phase 38 owns account/operator workbench migration.
- Removing all remaining legacy App screen-specific fields and clauses unrelated to board/thread directory flows - Phase 39 owns final App shell simplification.
- Changing durable board, subscription, thread, post, read-pointer, or authorization domain behavior - context modules remain the domain boundary.
- Visual redesign of BoardList, ThreadList, BoardTree, RichRow, ScreenFrame, or KeyBar - this phase is an ownership/runtime migration.
- Adding browser-facing board or thread workflows - Foglet remains SSH/TUI-first.

## Constraints

- The primary product surface remains SSH/TUI; no end-user Phoenix browser flow is introduced.
- Screens must use the Phase 34 screen contract: `init/1`, `update/3`, `render/2`, screen-local state, and `Foglet.TUI.Context`, not broad App-shaped state for local flow ownership.
- Domain side effects remain in `Foglet.Boards`, `Foglet.Threads`, authorization contexts, and related domain modules.
- Async domain work requested by BoardList/ThreadList must use the Phase 34 task-effect path through `Foglet.TUI.Command.task/2`.
- Task success/failure for migrated board/thread flows must return through the requesting screen's `update/3`.
- Modal precedence, SizeGate behavior, session lifecycle, and generic effect interpretation remain App/runtime responsibilities.
- Existing render contracts should remain stable except where minimal adaptation is required by the ownership migration.
- Route params must carry enough selected board/thread identity for route initialization and PubSub topic derivation without App `current_board` or `current_thread_list`.

## Acceptance Criteria

- [ ] BoardList can be initialized, updated, and rendered through `init/1`, `update/3`, and `render/2` with directory rows, loading state, tree state, and feedback stored in BoardList local state.
- [ ] BoardList handles board directory load success/failure, subscription success/failure, and board-activity refresh through BoardList `update/3` via screen-tagged task results.
- [ ] BoardList category expand/collapse and board leaf navigation behavior remain covered; board leaf navigation uses route params and does not write App `current_board`.
- [ ] ThreadList has a first-class local state module and stores selected board route data, loaded thread rows, loading state, and selected index outside App `current_thread_list`.
- [ ] ThreadList handles thread load results through ThreadList `update/3`, preserving sticky-first/newest-first sorting, unread/sticky/locked row state, and selection clamping.
- [ ] ThreadList Enter and compose flows emit navigation/task effects with selected thread/board route data and do not rely on App top-level board/thread directory fields.
- [ ] App board/thread local-flow clauses are removed or reduced to generic effect/task routing that does not mutate BoardList or ThreadList local state directly.
- [ ] PubSub topic derivation and board-activity refresh work from route params/screen state for BoardList/ThreadList, without `current_board` as the ThreadList source of truth.
- [ ] Targeted BoardList/ThreadList reducer tests, relevant App runtime tests, and canonical board/thread render smoke checks pass.
- [ ] Target screen docs and state modules describe the new screen-owned ownership boundary.

## Ambiguity Report

| Dimension           | Score | Min   | Status | Notes |
|---------------------|-------|-------|--------|-------|
| Goal Clarity        | 0.91  | 0.75  | met    | Full BoardList/ThreadList update-loop ownership is locked. |
| Boundary Clarity    | 0.87  | 0.70  | met    | Post/composer migration, operator screens, visual redesign, and durable domain changes are explicitly deferred. |
| Constraint Clarity  | 0.79  | 0.65  | met    | Phase 34 contract, SSH/TUI surface, domain boundaries, task effects, and route-param constraints are locked. |
| Acceptance Criteria | 0.84  | 0.70  | met    | Pass/fail reducer ownership, App clause removal, route-param handoff, and behavior preservation checks are specified. |
| **Ambiguity**       | 0.14  | <=0.20| met    | Gate passed after round 1. |

Status: met = meets minimum, below = below minimum (planner treats as assumption)

## Interview Log

| Round | Perspective | Question summary | Decision locked |
|-------|-------------|------------------|-----------------|
| 1 | Researcher | What is the core deliverable boundary for BoardList and ThreadList? | Full ownership: both screens own local state, async task results, route params, navigation effects, and feedback for their directory flows. |
| 1 | Researcher | How strict should route data replacement be? | Route params plus screen state are the source of truth for selected board/thread identity and loaded rows, not App top-level fields. |
| 1 | Researcher | Which behavior must be preserved explicitly? | All listed behavior is locked: category expand/collapse, board navigation, subscribe feedback, unread refresh, thread selection, compose origin, and render smoke. |

---

*Phase: 36-board-thread-directory-flow*
*Spec created: 2026-04-28*
*Next step: $gsd-discuss-phase 36 - implementation decisions (how to build what's specified above)*
