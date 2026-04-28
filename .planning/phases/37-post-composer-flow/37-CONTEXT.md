# Phase 37: Post & Composer Flow - Context

**Gathered:** 2026-04-28 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

PostReader, PostComposer, and NewThread move to screen-owned `init/1`,
`update/3`, and `render/2` flows over screen-local state plus
`Foglet.TUI.Context`. This phase preserves existing post reading, reply
composition, and new-thread behavior while removing post/composer local-flow
ownership from `Foglet.TUI.App`. It does not change durable post/thread/board
domain behavior, redesign composer or reader visuals, migrate account/operator
screens, remove unrelated legacy App machinery, or add browser-facing product
workflows.
</domain>

<spec_lock>
## Specification Lock

`.planning/phases/37-post-composer-flow/37-SPEC.md` locks 9 requirements and
the phase boundaries. Downstream agents MUST read it before planning. Do not
duplicate or reinterpret the requirements from memory; use the SPEC as the
source of truth for what must be delivered and what remains out of scope.
</spec_lock>

<decisions>
## Implementation Decisions

### PostReader Ownership
- **D-01:** `Foglet.TUI.Screens.PostReader` should become a new-contract
  screen whose local state owns loaded posts, loading/error status, selected
  post index, viewport state, render cache, selected board/thread route data,
  and pending read-pointer data.
- **D-02:** Expand `Foglet.TUI.Screens.PostReader.State` beyond
  `selected_post_index`, `viewport`, and `render_cache`; App top-level `posts`,
  `read_position`, and `current_thread` must stop being the source of truth for
  PostReader behavior after this phase.
- **D-03:** PostReader should consume post-load success/failure, empty loads,
  active-thread PubSub refresh, navigation keys, reply navigation, and back
  navigation through `PostReader.update/3`, not through App-specific
  `do_update/2` clauses.

### Read-Pointer Flush Semantics
- **D-04:** Read-pointer advancement remains local and monotonic: entering a
  loaded thread seeds the first visible post, navigation advances pending read
  data, and pending state is flushed on exit through a task effect.
- **D-05:** A successful read-pointer flush clears only the flushed pending
  entry from PostReader local state.
- **D-06:** A failed read-pointer flush must leave pending read data available
  for retry. Do not preserve App's current behavior if it would discard failed
  pending read state.
- **D-07:** Flush context must be built from route params and screen-local
  board/thread/post identity, not from App `current_board` or `current_thread`
  as canonical state.

### PostComposer Ownership
- **D-08:** `Foglet.TUI.Screens.PostComposer` should expose `init/1`,
  `update/3`, and `render/2` around its existing `PostComposer.State`, with
  local fields for thread/board/reply route data, draft input state, edit/
  preview mode, validation errors, submission status/result, and cancel origin.
- **D-09:** Reply submission should move from synchronous `handle_key/2` domain
  calls to `Foglet.TUI.Effect.task/3`, returning
  `{:screen_task_result, :post_composer, op, result}` into
  `PostComposer.update/3`.
- **D-10:** Successful reply submission should navigate back to PostReader with
  route params and request a PostReader-owned reload that preserves the current
  jump-to-last behavior after the reload completes.
- **D-11:** PostComposer should continue to preserve markdown preview,
  soft-wrapping, max-length enforcement, empty-body validation,
  missing-user denial, thread-locked/posting-denied errors, and origin-aware
  cancel behavior without using App `composer_draft` or App `current_thread` as
  source of truth.

### NewThread Ownership
- **D-12:** `Foglet.TUI.Screens.NewThread` should expose `init/1`, `update/3`,
  and `render/2` around its existing `NewThread.State`, with local fields for
  board picker state, active-board count, selected board, title/body input
  state, edit/preview mode, validation errors, submission status/result, and
  cancel origin.
- **D-13:** Subscribed-board loading and create-thread submission should move
  from App-owned or synchronous screen paths to task effects whose results are
  consumed by `NewThread.update/3`.
- **D-14:** Successful thread creation should navigate to ThreadList with
  selected board route data and a selection intent for the new thread or first
  row, then request a ThreadList-owned reload through the Phase 36 route/effect
  boundary.
- **D-15:** NewThread should preserve existing board picker behavior, no-active
  and no-subscribed-board empty states, title/body focus switching, edit/
  preview toggling, validation errors, max-length behavior, and origin-aware
  cancel behavior.

### App Boundary
- **D-16:** Remove or reduce App clauses for `:load_posts`, `:posts_loaded`,
  `:flush_read_pointers`, `:read_pointers_flushed`,
  `:load_boards_for_new_thread`, and `:boards_for_new_thread_loaded` so App no
  longer mutates PostReader, PostComposer, or NewThread local state directly.
- **D-17:** App remains responsible for generic runtime concerns only: Raxol
  callbacks, modal and SizeGate precedence, current route storage, screen-state
  storage helpers, context construction, generic effect interpretation, command
  dispatch, session lifecycle, and PubSub forwarding.
- **D-18:** PubSub topic derivation and active-thread refresh for PostReader/
  PostComposer should use route params or screen-local identity rather than App
  `current_thread` as canonical state.
- **D-19:** Temporary compatibility with Phase 39 cleanup is acceptable only if
  it is narrow, explicitly named, and does not make App the owner of Phase 37
  flow state.

### Testing And Preservation
- **D-20:** Migrate PostReader, PostComposer, and NewThread tests toward
  `init/1` and `update/3` reducer/effect assertions over local state, route
  params, task effects, task results, and navigation effects.
- **D-21:** App tests should prove generic task/effect routing and absence of
  Phase 37 local-flow mutation, not reassert old post/composer App clauses.
- **D-22:** Preserve keyboard behavior, resize-gate draft preservation,
  markdown rendering, soft wrapping, render cache behavior, empty/loading
  states, policy denial messages, reply jump-to-last, new-thread selection
  after reload, PubSub refresh, and canonical render smoke coverage.
- **D-23:** Avoid brittle tests that only assert text presence. Use state,
  effects, task results, route params, domain-result handling, and render
  smoke/layout contracts where appropriate.

### the agent's Discretion
- Exact reducer message names and task op atoms are flexible if they are
  screen-owned, route through the Phase 34 task-result contract, and remain
  easy to test.
- Exact state field names are flexible if the three target screen states own
  every local data item named in the SPEC and no longer depend on App top-level
  post/composer fields as truth.
- Planners may split PostReader, PostComposer, and NewThread migration into
  multiple plans, but every split must preserve terminal behavior at each step.

### Folded Todos
None.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Locked Phase Scope
- `.planning/phases/37-post-composer-flow/37-SPEC.md` - Locked Phase 37
  requirements, boundaries, constraints, and acceptance criteria.
- `.planning/ROADMAP.md` - v2.0 phase sequencing, Phase 37 goal, and dependency
  notes.
- `.planning/PROJECT.md` - SSH-first product boundary and v2.0 milestone
  intent.
- `.planning/REQUIREMENTS.md` - v2.0 screen ownership requirements and Phase 37
  requirement mapping.

### Runtime Foundation And Prior Decisions
- `.planning/phases/34-runtime-contract-effects/34-CONTEXT.md` - Prior locked
  decisions for `Foglet.TUI.Context`, `Foglet.TUI.Effect`, route params,
  task-result routing, and state conventions.
- `.planning/phases/34-runtime-contract-effects/34-SPEC.md` - Phase 34
  foundation requirements that Phase 37 builds on.
- `.planning/phases/35-auth-home-screens/35-CONTEXT.md` - Prior migration
  decisions for screen-owned reducers, App boundary cleanup, and testing style.
- `.planning/phases/36-board-thread-directory-flow/36-CONTEXT.md` - Prior
  locked decisions for BoardList/ThreadList route params, task effects, and
  temporary Phase 37 compatibility bridges.
- `lib/foglet_bbs/tui/screen.ex` - New screen behavior contract and
  transitional callbacks.
- `lib/foglet_bbs/tui/context.ex` - Narrow screen-facing runtime context.
- `lib/foglet_bbs/tui/effect.ex` - Explicit effect constructors and task
  effect shape.
- `lib/foglet_bbs/tui/app.ex` - App runtime shell, generic effect
  interpretation, route helpers, legacy post/composer clauses to migrate away
  from, PubSub topic derivation, and task-result routing.

### Target Screens And Widgets
- `lib/foglet_bbs/tui/screens/post_reader.ex` - Current PostReader render/key
  behavior, post loading seams, read-pointer logic, reply/back navigation, and
  render cache warming.
- `lib/foglet_bbs/tui/screens/post_reader/state.ex` - Existing PostReader
  state seed to expand.
- `lib/foglet_bbs/tui/screens/post_composer.ex` - Current reply composer
  render/key/submit/cancel behavior and synchronous reply submission path.
- `lib/foglet_bbs/tui/screens/post_composer/state.ex` - Existing PostComposer
  state shape.
- `lib/foglet_bbs/tui/screens/new_thread.ex` - Current board picker, compose,
  validation, cancel, and synchronous create-thread behavior.
- `lib/foglet_bbs/tui/screens/new_thread/state.ex` - Existing NewThread state
  shape.
- `lib/foglet_bbs/tui/screens/thread_list.ex` - ThreadList handoff behavior for
  opening PostReader and composing a new thread.
- `lib/foglet_bbs/tui/widgets/composer/editor_frame.ex` - Shared composer
  shell used by PostComposer and NewThread.
- `lib/foglet_bbs/tui/widgets/compose.ex` - MultiLineInput integration and
  composer input rendering.
- `lib/foglet_bbs/tui/widgets/post/post_card.ex` and
  `lib/foglet_bbs/tui/widgets/post/markdown_body.ex` - Existing post display
  and markdown rendering contracts.
- `lib/foglet_bbs/tui/render_fixtures.ex` - Canonical render fixture setup that
  still references App top-level post/composer fields.

### Domain APIs
- `lib/foglet_bbs/posts.ex` - Reply creation and post listing APIs.
- `lib/foglet_bbs/threads.ex` - Thread listing, creation, and thread read
  pointer APIs.
- `lib/foglet_bbs/boards.ex` - Board directory/subscription APIs and board read
  pointer advancement.
- `lib/foglet_bbs/boards/server.ex` - Per-board message-number allocation for
  thread/post creation.

### Tests And Codebase Maps
- `test/foglet_bbs/tui/screens/post_reader_test.exs` - Existing PostReader
  loading, navigation, render cache, read-pointer, and reply/back coverage to
  migrate to reducer/effect assertions.
- `test/foglet_bbs/tui/screens/post_composer_test.exs` - Existing reply
  composer edit/preview/input/submit/cancel coverage.
- `test/foglet_bbs/tui/screens/new_thread_test.exs` - Existing new-thread
  board picker, compose, validation, submit, and cancel coverage.
- `test/foglet_bbs/tui/app_runtime_contract_test.exs` - Generic route,
  context, effect, and task-result routing proof.
- `test/foglet_bbs/tui/app_test.exs` - Existing App runtime and legacy
  post/composer assertions to update.
- `test/foglet_bbs/tui/layout_smoke_test.exs` - Canonical post/composer render
  smoke harness.
- `.planning/codebase/ARCHITECTURE.md` - Current TUI/App/domain/PubSub state
  flow map.
- `.planning/codebase/CONVENTIONS.md` - Elixir module, state, docs, specs, and
  precommit conventions.
- `.planning/codebase/STRUCTURE.md` - Source/test layout and state-module
  placement conventions.
- `.planning/codebase/TESTING.md` - ExUnit, TUI, and render smoke testing
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
- `PostReader.State`, `PostComposer.State`, and `NewThread.State` already
  exist, so this phase should expand and adapt them instead of inventing new
  storage patterns.
- Existing composer widgets already centralize MultiLineInput rendering,
  markdown preview, counters, and editor framing.

### Established Patterns
- New-contract screens receive local state plus `Foglet.TUI.Context`; they do
  not receive `%Foglet.TUI.App{}` for local decisions.
- Domain side effects stay in contexts (`Foglet.Posts`, `Foglet.Threads`,
  `Foglet.Boards`) and are requested from screens through task effects.
- App owns runtime concerns, not screen-local loaded data, drafts, validation
  status, or task-result lifecycle.
- TUI tests mirror source paths and should assert reducer state/effects, task
  results, route params, and render smoke contracts before relying on render
  text.
- Existing post/composer visible behavior is preservation work, not redesign.

### Integration Points
- `lib/foglet_bbs/tui/app.ex` currently contains the Phase 37 local-flow
  handlers to remove or reduce: `{:load_boards_for_new_thread}`,
  `{:boards_for_new_thread_loaded, ...}`, `{:load_posts, ...}`,
  `{:posts_loaded, ...}`, `{:flush_read_pointers, ...}`,
  `{:read_pointers_flushed, ...}`, and active-thread refresh handling.
- `App.route_screen_update/3` is the generic hook for migrated screens to
  receive key/task/update messages.
- `App.init_route_screen_state/3`, `App.context_for_screen_key/2`, and
  `App.apply_effects/2` are the runtime helpers planners should reuse rather
  than inventing parallel dispatch.
- `App.build_pubsub_topics/1` currently derives post-reader/post-composer
  thread topics from `current_thread`; Phase 37 needs route-param or
  screen-state based derivation for post/composer flows.
- `Foglet.TUI.RenderFixtures` and `test/foglet_bbs/tui/layout_smoke_test.exs`
  currently seed post/composer screens through App top-level fields; render
  fixtures may need narrow updates after ownership moves.
</code_context>

<specifics>
## Specific Ideas

- User confirmed the assumptions-mode pass without corrections.
- No visual redesign, new composer features, domain behavior changes, or
  browser workflows were added during discussion.
- No external research is required; the relevant runtime behavior is local in
  Phase 34-36 artifacts and the Foglet/Raxol codebase.
</specifics>

<deferred>
## Deferred Ideas

None - analysis stayed within phase scope.
</deferred>

---

*Phase: 37-post-composer-flow*
*Context gathered: 2026-04-28*
