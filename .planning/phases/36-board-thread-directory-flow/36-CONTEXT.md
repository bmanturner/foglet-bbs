# Phase 36: Board & Thread Directory Flow - Context

**Gathered:** 2026-04-28 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

BoardList and ThreadList move to screen-owned `init/1`, `update/3`, and
`render/2` flows over screen-local state plus `Foglet.TUI.Context`. This phase
preserves existing board/thread browsing behavior while removing BoardList and
ThreadList local-flow ownership from `Foglet.TUI.App`. It does not migrate
PostReader, PostComposer, NewThread internals, account/operator screens,
unrelated App machinery, durable board/thread domain behavior, visual design, or
browser-facing product workflows.
</domain>

<spec_lock>
## Specification Lock

`.planning/phases/36-board-thread-directory-flow/36-SPEC.md` locks 7
requirements and the phase boundaries. Downstream agents MUST read it before
planning. Do not duplicate or reinterpret the requirements from memory; use the
SPEC as the source of truth for what must be delivered and what remains out of
scope.
</spec_lock>

<decisions>
## Implementation Decisions

### BoardList Ownership
- **D-01:** `Foglet.TUI.Screens.BoardList` should become a new-contract screen
  whose local state owns the loaded directory, `BoardTree` cursor/expansion
  state, loading status, and subscription feedback.
- **D-02:** Expand `Foglet.TUI.Screens.BoardList.State` beyond `board_tree` and
  `feedback`; App top-level `board_list` must stop being the source of truth for
  BoardList rendering and reducer behavior.
- **D-03:** BoardList should consume directory load results, subscription
  success/failure results, and board-activity refresh messages through
  `BoardList.update/3`, not through App-specific `do_update/2` clauses.

### ThreadList Ownership
- **D-04:** Add a first-class `Foglet.TUI.Screens.ThreadList.State` module for
  selected board route data, loaded thread rows, selected index, loading/empty
  status, and any task-result lifecycle fields needed by focused tests.
- **D-05:** ThreadList local state should replace App top-level
  `current_thread_list` as the source of truth for directory rows and selection.
- **D-06:** ThreadList should consume thread-load results through
  `ThreadList.update/3` while preserving sticky-first/newest-first sorting,
  unread/sticky/locked row state, and selection clamping.

### Route Params And Navigation
- **D-07:** BoardList-to-ThreadList navigation should use
  `Foglet.TUI.Effect.navigate/2` with selected board route params and initialize
  ThreadList from those params.
- **D-08:** ThreadList-to-PostReader navigation should carry selected thread and
  board identity through route params/effects, while leaving any deeper
  PostReader migration to Phase 37.
- **D-09:** Preserve legacy top-level `current_board`/`current_thread` only as a
  temporary compatibility bridge where later unmigrated Phase 37 screens still
  require them. Do not treat those fields as the BoardList/ThreadList source of
  truth after Phase 36.
- **D-10:** Compose-from-ThreadList should carry selected board data and
  `origin: :thread_list` through navigation/route initialization, rather than
  reaching into App `current_board` as the canonical source.

### Task Effects And App Boundary
- **D-11:** Directory loads, thread loads, and subscribe/unsubscribe mutations
  should use `Foglet.TUI.Effect.task/3`, returning
  `{:screen_task_result, screen_key, op, result}` into the requesting screen
  reducer.
- **D-12:** Remove or reduce the App clauses for `{:load_boards}`,
  `{:boards_loaded, _}`, `{:subscribe_to_board, _}`,
  `{:unsubscribe_from_board, _}`, `{:board_subscription_changed, ...}`,
  `{:load_threads, _}`, and `{:threads_loaded, _}` so App no longer owns
  BoardList/ThreadList local data or feedback.
- **D-13:** App remains responsible for generic runtime concerns only: modal
  precedence, SizeGate, Raxol callbacks, session lifecycle, generic effect
  interpretation, command dispatch, and PubSub forwarding.

### Testing And Preservation
- **D-14:** Migrate BoardList and ThreadList tests toward reducer/effect
  assertions over `init/1`, `update/3`, and `render/2`, rather than asserting
  App-shaped state mutations.
- **D-15:** App tests should prove generic task-result routing and absence of
  BoardList/ThreadList local-flow mutation, not reassert old board/thread App
  clauses.
- **D-16:** Preserve category expand/collapse, board leaf navigation,
  subscribe/unsubscribe feedback, required-subscription protection, unread
  refresh behavior, thread sorting/metadata/glyphs, compose origin, Q-back
  behavior, SizeGate, modal precedence, and canonical board/thread render smoke.
- **D-17:** Avoid brittle tests that only assert text presence. Use state,
  effects, task results, route params, and render smoke/layout contracts where
  appropriate.

### the agent's Discretion
- Exact reducer message names are flexible if they are screen-owned and route
  through the Phase 34 screen update-loop contract.
- Exact ThreadList state field names are flexible if the state owns selected
  board route data, loaded rows, loading state, selection, and task-result
  lifecycle.
- Temporary compatibility writes for unmigrated Phase 37 screens are acceptable
  only when narrowly justified and documented as a bridge, not as BoardList or
  ThreadList ownership.

### Folded Todos
None.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Locked Phase Scope
- `.planning/phases/36-board-thread-directory-flow/36-SPEC.md` - Locked Phase
  36 requirements, boundaries, constraints, and acceptance criteria.
- `.planning/ROADMAP.md` - v2.0 phase sequencing, Phase 36 goal, and
  dependency notes.
- `.planning/PROJECT.md` - SSH-first product boundary and v2.0 milestone
  intent.
- `.planning/REQUIREMENTS.md` - v2.0 screen ownership requirements and Phase 36
  requirement mapping.

### Runtime Foundation And Prior Decisions
- `.planning/phases/34-runtime-contract-effects/34-CONTEXT.md` - Prior locked
  decisions for `Foglet.TUI.Context`, `Foglet.TUI.Effect`, route params,
  task-result routing, and state conventions.
- `.planning/phases/34-runtime-contract-effects/34-SPEC.md` - Phase 34
  foundation requirements that Phase 36 builds on.
- `.planning/phases/35-auth-home-screens/35-CONTEXT.md` - Prior migration
  decisions for screen-owned reducers, App boundary cleanup, and testing style.
- `lib/foglet_bbs/tui/screen.ex` - New screen behavior contract and transitional
  callbacks.
- `lib/foglet_bbs/tui/context.ex` - Narrow screen-facing runtime context.
- `lib/foglet_bbs/tui/effect.ex` - Explicit effect constructors and task
  effect shape.
- `lib/foglet_bbs/tui/app.ex` - App runtime shell, generic effect
  interpretation, route helpers, legacy BoardList/ThreadList clauses to migrate
  away from, PubSub topic derivation, and task-result routing.

### Target Screens And Widgets
- `lib/foglet_bbs/tui/screens/board_list.ex` - Current BoardList render/key
  behavior, directory load helper, navigation, and subscription command
  emission.
- `lib/foglet_bbs/tui/screens/board_list/state.ex` - Existing BoardList local
  state seed to expand.
- `lib/foglet_bbs/tui/screens/thread_list.ex` - Current ThreadList render/key
  behavior, load helper, selection, PostReader navigation, and compose origin
  handling.
- `lib/foglet_bbs/tui/widgets/list/board_tree.ex` - Board directory tree state,
  focused-entry lookup, expand/collapse, and board row rendering contract.
- `lib/foglet_bbs/tui/widgets/list/selection_list.ex` - ThreadList selection
  rendering primitive.
- `lib/foglet_bbs/tui/widgets/list/rich_row.ex` - Thread row metadata and
  unread/sticky/locked state-cluster rendering.
- `lib/foglet_bbs/tui/render_fixtures.ex` - Canonical render fixture setup that
  still references App top-level board/thread fields.

### Domain APIs
- `lib/foglet_bbs/boards.ex` - Board directory, subscription, unsubscribe, and
  required-subscription behavior.
- `lib/foglet_bbs/threads.ex` - Thread listing APIs, unread annotation, and
  `ThreadEntry` rows.

### Tests And Codebase Maps
- `test/foglet_bbs/tui/screens/board_list_test.exs` - Existing BoardList
  behavior coverage to migrate to reducer/effect assertions.
- `test/foglet_bbs/tui/screens/thread_list_test.exs` - Existing ThreadList
  behavior coverage to migrate to reducer/effect assertions.
- `test/foglet_bbs/tui/app_runtime_contract_test.exs` - Generic route,
  context, effect, and task-result routing proof.
- `test/foglet_bbs/tui/app_test.exs` - Existing App runtime and legacy
  PubSub/board/thread assertions to update.
- `test/foglet_bbs/tui/layout_smoke_test.exs` - Canonical TUI render smoke
  harness.
- `.planning/codebase/CONVENTIONS.md` - Elixir module, state, docs, specs, and
  precommit conventions.
- `.planning/codebase/STRUCTURE.md` - Source/test layout and state-module
  placement conventions.
- `.planning/codebase/TESTING.md` - ExUnit, TUI, OTP, and render smoke testing
  patterns.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Foglet.TUI.Screen` already defines the target `init/1`, `update/3`, and
  `render/2` callbacks while retaining transitional legacy callbacks.
- `Foglet.TUI.Context` already exposes current user, session context,
  terminal size, route params, and domain overrides without App screen storage.
- `Foglet.TUI.Effect.task/3` and `Foglet.TUI.App.apply_effect/2` already route
  task success/failure into `{:screen_task_result, screen_key, op, result}`.
- `Foglet.TUI.App` already has public helpers for `current_route/1`,
  `screen_key/1`, `screen_state_for/2`, `put_screen_state/3`,
  `build_context/1`, and effect interpretation.
- `BoardList.State` exists and can be expanded instead of inventing a new
  BoardList state pattern.
- `BoardTree` encapsulates cursor, expand/collapse, focused board lookup, and
  row rendering, so BoardList should store and drive it rather than duplicating
  tree internals.

### Established Patterns
- New-contract screens receive local state plus `Foglet.TUI.Context`; they do
  not receive `%Foglet.TUI.App{}` for local decisions.
- Domain side effects stay in contexts (`Foglet.Boards`, `Foglet.Threads`) and
  are requested from screens through task effects.
- App owns runtime concerns, not screen-local loaded data or feedback.
- TUI tests mirror source paths and should assert reducer state/effects, task
  results, and route params before relying on render text.
- Existing BoardList and ThreadList visible behavior is preservation work, not
  redesign.

### Integration Points
- `lib/foglet_bbs/tui/app.ex` currently contains the Phase 36 local-flow
  handlers to remove or reduce: `{:load_boards}`, `{:boards_loaded, _}`,
  `{:subscribe_to_board, _}`, `{:unsubscribe_from_board, _}`,
  `{:board_subscription_changed, ...}`, `{:load_threads, _}`,
  `{:threads_loaded, _}`, `put_board_list_feedback/2`, and board-activity
  refresh handling.
- `App.route_screen_update/3` is the generic hook for migrated screens to
  receive key/task/update messages.
- `App.init_route_screen_state/3`, `App.context_for_screen_key/2`, and
  `App.apply_effects/2` are the runtime helpers planners should reuse rather
  than inventing parallel dispatch.
- `App.build_pubsub_topics/1` currently derives the ThreadList board topic from
  `current_board`; Phase 36 needs route-param/screen-state based derivation for
  the directory flow.
- `Foglet.TUI.RenderFixtures` currently seeds board/thread screens through App
  top-level fields; render fixtures may need narrow updates after ownership
  moves.
</code_context>

<specifics>
## Specific Ideas

- User confirmed the assumptions-mode pass without corrections.
- No visual redesign, new board/thread product capability, domain behavior
  change, or browser workflow was added during discussion.
- No external research is required; the relevant runtime behavior is local in
  Phase 34/35 artifacts and the Foglet codebase.
</specifics>

<deferred>
## Deferred Ideas

None - analysis stayed within phase scope.
</deferred>

---

*Phase: 36-board-thread-directory-flow*
*Context gathered: 2026-04-28*
