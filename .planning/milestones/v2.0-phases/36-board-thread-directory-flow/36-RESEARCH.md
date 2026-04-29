# Phase 36: Board & Thread Directory Flow - Research

**Researched:** 2026-04-28
**Status:** Complete

## Research Question

What does Phase 36 need in order to migrate BoardList and ThreadList from
App-owned directory flows to screen-owned `init/1`, `update/3`, and `render/2`
reducers without changing board/thread browsing behavior?

## Phase Summary

Phase 36 is an ownership migration over the existing SSH/TUI board directory
experience. Durable board, subscription, thread, post, authorization, and read
pointer behavior stays in the domain contexts. The work is to move directory
data, selection state, route identity, async task requests, and async task
results into BoardList and ThreadList local state.

The most important runtime constraint is inherited from Phase 34: App routes
keys and rendering through the new reducer path only when the target screen
exports `update/3` and `render/2` without the legacy `handle_key/2` and
`render/1` callbacks. Plans must therefore migrate each target screen fully
across the boundary before deleting the matching App-owned clauses.

## Source Artifacts Read

- `.planning/phases/36-board-thread-directory-flow/36-SPEC.md`
- `.planning/phases/36-board-thread-directory-flow/36-CONTEXT.md`
- `.planning/REQUIREMENTS.md`
- `.planning/STATE.md`
- `.planning/ROADMAP.md`
- `.planning/phases/34-runtime-contract-effects/34-CONTEXT.md`
- `.planning/phases/35-auth-home-screens/35-CONTEXT.md`
- `lib/foglet_bbs/tui/screen.ex`
- `lib/foglet_bbs/tui/context.ex`
- `lib/foglet_bbs/tui/effect.ex`
- `lib/foglet_bbs/tui/app.ex`
- `lib/foglet_bbs/tui/screens/board_list.ex`
- `lib/foglet_bbs/tui/screens/board_list/state.ex`
- `lib/foglet_bbs/tui/screens/thread_list.ex`
- `lib/foglet_bbs/tui/widgets/list/board_tree.ex`
- `test/foglet_bbs/tui/app_runtime_contract_test.exs`
- `test/foglet_bbs/tui/app_test.exs`
- `test/foglet_bbs/tui/screens/board_list_test.exs`
- `test/foglet_bbs/tui/screens/thread_list_test.exs`
- `test/foglet_bbs/tui/layout_smoke_test.exs`

## Current Architecture Findings

### Phase 34 Runtime Foundation Is Present

`Foglet.TUI.Context` carries route params, terminal size, current user,
session context, and domain overrides without exposing broad App local storage.
`Foglet.TUI.Effect.navigate/2` initializes route state and target screen state.
`Foglet.TUI.Effect.task/3` lets screens request domain work; App wraps task
success/failure as `{:screen_task_result, screen_key, op, result}` and re-routes
that to screen `update/3` as `{:task_result, op, result}`.

The generic App helpers already exist:

- `App.current_route/1`
- `App.screen_key/1`
- `App.screen_state_for/2`
- `App.put_screen_state/3`
- `App.build_context/1`
- `App.apply_effect/2`
- `App.apply_effects/2`

Phase 36 should reuse these helpers rather than adding a parallel board/thread
dispatcher.

### App Still Owns Board And Thread Directory Flow

`Foglet.TUI.App` still has top-level directory fields and board/thread clauses:

- `board_list`
- `current_board`
- `current_thread_list`
- `{:load_boards}`
- `{:boards_loaded, boards}`
- `{:subscribe_to_board, board_id}`
- `{:unsubscribe_from_board, board_id}`
- `{:board_subscription_changed, action, result}`
- `{:load_threads, board_id}`
- `{:threads_loaded, threads}`
- board activity refresh on `:board_list`
- ThreadList board PubSub topic derivation from `current_board`

These are the clauses Phase 36 should remove or reduce to generic routing once
BoardList and ThreadList own their reducer flows. App may keep compatibility
bridges for unmigrated Phase 37 screens, but those bridges must not be the
source of truth for BoardList/ThreadList.

### New-Contract Activation Rules Matter

`App.do_update({:key, key_event}, state)` calls `route_screen_update/3` only if
`new_contract_screen?/2` returns true. That helper requires a module to export
`update/3` and not export `handle_key/2`. Rendering has the same shape:
`render/2` wins only after `render/1` is gone.

Therefore BoardList and ThreadList plans must explicitly remove or stop
exporting legacy callbacks when each screen is migrated. Adding new callbacks
beside old callbacks will compile but leave production on the old path.

## Screen Findings

### BoardList

BoardList already has `Foglet.TUI.Screens.BoardList.State`, but it stores only
`board_tree` and `feedback`. The loaded directory itself still lives in App
top-level `board_list`, and `BoardList.render/1`, `handle_key/2`, and
`load_boards/1` all receive App-shaped state.

The target local state should include:

- `directory`
- `board_tree`
- `status` such as `:loading`, `:loaded`, `:empty`, or `{:error, reason}`
- `feedback`
- optional task lifecycle fields such as `last_op`

BoardList should request directory loads through `Effect.task(:load_boards,
:board_list, fun)` and consume `{:task_result, :load_boards, result}` inside
`BoardList.update/3`. Subscribe and unsubscribe should similarly be screen task
effects with ops such as `:subscribe_to_board` and `:unsubscribe_from_board`.
Success results should set feedback and request a BoardList-owned reload.
Required-subscription refusal can stay synchronous when the focused tree entry
already declares `required_subscription?: true`.

Category Enter, left, and right should update only the local `BoardTree` state.
Board leaf Enter should emit `Effect.navigate(:thread_list, params)` where
params include enough board identity for ThreadList init, ThreadList PubSub
topic derivation, compose origin, and the later PostReader handoff.

### ThreadList

ThreadList has no first-class state module today. Its selected index lives in a
map under `screen_state[:thread_list]`, while rows live in App top-level
`current_thread_list` and selected board lives in App top-level `current_board`.

Add `lib/foglet_bbs/tui/screens/thread_list/state.ex` with fields such as:

- `board`
- `board_id`
- `threads`
- `selected_index`
- `status` such as `:loading`, `:loaded`, `:empty`, or `{:error, reason}`
- optional task lifecycle fields such as `last_op`

`ThreadList.init/1` should read selected board route params and initialize
selection to `0`. It should either start in `:loading` and rely on a reducer
message to request load, or return a state that `update/3` can drive through an
explicit initial message. Thread loading must use `Effect.task(:load_threads,
:thread_list, fun)` and consume `{:task_result, :load_threads, result}` inside
`ThreadList.update/3`.

ThreadList should preserve sticky-first/newest-first ordering before rendering
or selecting. The current private sorting logic can be retained, but tests
should assert against reducer state and selected thread effects rather than
App `current_thread_list` or `current_thread`.

Thread Enter should emit navigation to `:post_reader` with selected thread and
board route params. If Phase 37 still needs a compatibility bridge to load
posts, keep it narrow and documented. Compose should emit navigation to
`:new_thread` with selected board data and `origin: :thread_list`, while
leaving NewThread internals to Phase 37.

## Integration Findings

### PubSub Topic Derivation

`App.build_pubsub_topics/1` currently subscribes ThreadList to `board:<id>` only
when `state.current_board` is set. Phase 36 should derive the ThreadList board
topic from route params or ThreadList local state instead. BoardList can keep
the aggregate `boards` subscription, but board activity refresh should route as
a BoardList update message or a BoardList task effect when BoardList is active.

### Render Fixtures And Smoke Tests

`Foglet.TUI.RenderFixtures` and `test/foglet_bbs/tui/layout_smoke_test.exs`
currently seed board/thread screens through App top-level fields. Plans should
include fixture/smoke updates so canonical render checks exercise the new local
state shape. These tests should remain layout-contract tests, not text-only
behavior tests.

### Domain Module Dispatch

BoardList can keep using `Foglet.TUI.Screens.Domain` or Context domain data to
resolve `:boards`. ThreadList should preserve the current fallback behavior:
prefer `list_threads/2` with user id when available, fall back to
`list_threads/1` and annotate `has_unread: false` when needed. Bind only the
domain module, user id, board id, and input values into task closures; do not
capture the full App state.

## Recommended Plan Split

1. Expand BoardList state and migrate BoardList loading, tree, navigation, and
   subscription reducer behavior.
2. Add ThreadList state and migrate ThreadList loading, selection, sorting,
   navigation, and compose origin behavior.
3. Remove or reduce App board/thread directory ownership, update PubSub topic
   derivation and render fixtures, and prove generic routing plus smoke tests.

This split lets BoardList and ThreadList reducer work proceed independently in
Wave 1, then performs App cleanup after both screens have local ownership.

## Risks And Mitigations

| Risk | Mitigation |
|------|------------|
| Adding `update/3` without removing `handle_key/2` leaves production on the legacy path. | Each migrated screen task must remove legacy callback exports and include an App routing test proving keys reach `update/3`. |
| Adding `render/2` without removing `render/1` leaves production rendering on the legacy path. | Each screen plan must verify render uses local state plus `Context`. |
| BoardList reload resets tree state unintentionally. | BoardList tests must cover when tree should preserve cursor/expansion and when a changed directory should rebuild safely. |
| ThreadList selection points past the end after reload. | ThreadList load-result handling must clamp `selected_index` to `0..length(threads)-1`, with empty list selecting `0`. |
| Route params lack enough identity for downstream screens. | Route params should include board id/name/slug and selected thread id/title/board id as needed for ThreadList, PostReader compatibility, and NewThread origin. |
| App compatibility bridges reintroduce BoardList/ThreadList ownership. | Any remaining writes to `current_board`, `current_thread`, or PostReader/NewThread state must be narrowly documented as Phase 37 compatibility, not directory source of truth. |
| Text-only tests miss ownership regressions. | Use reducer state/effect assertions, task-result assertions, PubSub topic assertions, and render smoke/layout contracts. |

## Validation Architecture

Phase 36 validation should use existing ExUnit infrastructure. The quick loop
should run the affected screen, App, runtime-contract, and layout smoke tests.
The full phase gate should add compile with warnings as errors.

Quick command:

`rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs test/foglet_bbs/tui/screens/thread_list_test.exs test/foglet_bbs/tui/app_runtime_contract_test.exs test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/layout_smoke_test.exs`

Full command:

`rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs test/foglet_bbs/tui/screens/thread_list_test.exs test/foglet_bbs/tui/app_runtime_contract_test.exs test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/layout_smoke_test.exs && rtk mix compile --warnings-as-errors`

Validation should assert:

- BoardList `init/1`, `update/3`, and `render/2` own directory rows, loading
  state, empty state, `BoardTree`, feedback, subscription results, and board
  activity refresh.
- BoardList category Enter updates local tree state without task or navigation
  effects; board leaf Enter emits `Effect.navigate(:thread_list, params)`.
- ThreadList `init/1`, `update/3`, and `render/2` own selected board route
  data, loaded rows, loading/empty state, selected index, task results, and
  selection clamping.
- ThreadList preserves sticky-first/newest-first ordering and
  unread/sticky/locked row state.
- ThreadList Enter and Compose emit navigation/effects with selected board and
  thread route data without relying on App `current_board` or
  `current_thread_list`.
- App routes board/thread task results through `{:screen_task_result, key, op,
  result}` and no longer owns BoardList/ThreadList local-flow mutation.
- PubSub topic derivation for ThreadList uses route params or screen state, not
  App `current_board` as the directory source of truth.
- Canonical board/thread render smoke checks pass at supported terminal sizes.

## Implementation Notes For Planning

- Read `36-SPEC.md` and `36-CONTEXT.md` before writing any implementation plan.
- Treat `SCREEN-03` as the requirement ID for every plan.
- Keep SSH/TUI as the only end-user product surface.
- Do not move domain behavior into screens; screen task closures call
  `Foglet.Boards` and `Foglet.Threads`.
- Preserve Phase 37 compatibility where needed for PostReader/NewThread, but
  label it explicitly as temporary.

## RESEARCH COMPLETE
