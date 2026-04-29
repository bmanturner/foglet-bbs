# Phase 37: Post & Composer Flow - Research

**Researched:** 2026-04-28
**Question:** What do I need to know to plan Phase 37 well?

## RESEARCH COMPLETE

Phase 37 is a continuation of the Phase 34-36 screen ownership migration. The
work is not a product redesign; it is a boundary migration for three existing
TUI flows:

- `Foglet.TUI.Screens.PostReader`
- `Foglet.TUI.Screens.PostComposer`
- `Foglet.TUI.Screens.NewThread`

The primary implementation risk is partial ownership. App must not continue to
own post lists, read-pointer pending state, composer drafts, board picker
results, or submit results for these flows after the phase, except for generic
runtime concerns and narrow transition compatibility that is explicitly named.

## Source Scope

Mandatory inputs for planning:

- `.planning/phases/37-post-composer-flow/37-SPEC.md`
- `.planning/phases/37-post-composer-flow/37-CONTEXT.md`
- `.planning/ROADMAP.md`
- `.planning/REQUIREMENTS.md`
- `lib/foglet_bbs/tui/app.ex`
- `lib/foglet_bbs/tui/screen.ex`
- `lib/foglet_bbs/tui/context.ex`
- `lib/foglet_bbs/tui/effect.ex`
- `lib/foglet_bbs/tui/screens/post_reader.ex`
- `lib/foglet_bbs/tui/screens/post_reader/state.ex`
- `lib/foglet_bbs/tui/screens/post_composer.ex`
- `lib/foglet_bbs/tui/screens/post_composer/state.ex`
- `lib/foglet_bbs/tui/screens/new_thread.ex`
- `lib/foglet_bbs/tui/screens/new_thread/state.ex`
- `lib/foglet_bbs/tui/screens/thread_list.ex`
- `lib/foglet_bbs/tui/screens/thread_list/state.ex`
- `test/foglet_bbs/tui/screens/post_reader_test.exs`
- `test/foglet_bbs/tui/screens/post_composer_test.exs`
- `test/foglet_bbs/tui/screens/new_thread_test.exs`
- `test/foglet_bbs/tui/app_test.exs`
- `test/foglet_bbs/tui/app_runtime_contract_test.exs`
- `test/foglet_bbs/tui/layout_smoke_test.exs`

## Current Architecture

### Runtime Contract Already Exists

`Foglet.TUI.Screen` defines the target callbacks:

- `init/1`
- `update/3`
- `render/2`

`Foglet.TUI.Context` carries current user, session context, session pid,
terminal size, route, route params, and domain overrides. `Foglet.TUI.Effect`
provides generic navigation, task, modal, publish, session, terminal, and quit
effects.

`Foglet.TUI.App.apply_effect/2` already handles:

- `Effect.navigate/2` by setting route params, initializing target screen state,
  and dispatching route-entry loads where needed.
- `Effect.task/3` by wrapping task output as
  `{:screen_task_result, screen_key, op, {:ok, result}}` or
  `{:screen_task_result, screen_key, op, {:error, reason}}`.
- `{:screen_task_result, key, op, result}` by routing to
  `module.update({:task_result, op, result}, local_state, context)`.

This means Phase 37 should use the same approach already used by BoardList and
ThreadList instead of adding new App-specific messages.

### ThreadList Is The Closest Migration Analog

`Foglet.TUI.Screens.ThreadList` is the best local pattern:

- `State.from_context/1` extracts route params into local state.
- `update(:load, state, context)` emits an `Effect.task/3`.
- `update({:task_result, :load_threads, result}, state, context)` owns loaded
  rows, status, and selection.
- navigation to PostReader uses route params containing `:board`, `:board_id`,
  `:thread`, and `:thread_id`.

PostReader should mirror this shape for post loads, active-thread refresh, and
reply/back navigation.

### App Still Owns The Phase 37 Flows

`Foglet.TUI.App` currently has post/composer ownership in these areas:

- top-level fields: `current_thread`, `posts`, `read_position`,
  `composer_draft`
- route compatibility:
  `maybe_seed_legacy_route_context/3` warms `current_board`, `current_thread`,
  and `posts` for PostReader
- route entry:
  `maybe_dispatch_route_entry/3` dispatches `{:load_posts, thread_id}`
- NewThread board loading:
  `{:load_boards_for_new_thread}` and
  `{:boards_for_new_thread_loaded, boards, active_board_count}`
- PostReader loading:
  `{:load_posts, thread_id, opts}` and `{:posts_loaded, posts, opts}`
- Read-pointer flush:
  `{:flush_read_pointers, ctx}` and `{:read_pointers_flushed, thread_id}`
- PubSub refresh:
  `{:thread_activity, thread_id, _event}` compares against
  `state.current_thread.id`

The plan should remove or reduce these clauses so they do not mutate
PostReader, PostComposer, or NewThread local state.

## Target Screen Research

### PostReader

Current state module only stores:

- `selected_post_index`
- `viewport`
- `render_cache`

Phase 37 must expand it to own:

- board identity and optional board struct
- thread identity and optional thread struct
- loaded posts
- loading, loaded, empty, and error status
- selected post index
- viewport and render cache
- pending read-pointer data keyed by thread id or stored as a current pending
  entry
- any reload intent such as `jump_last`

Important existing behavior to preserve:

- `load_posts/2` seeds first visible post as read.
- advancing posts updates pending read data with `last_read_post_id` and
  `last_read_message_number`.
- `prepare_after_load/3` warms render cache and viewport.
- `Q` builds a flush context with user id, board id, thread id,
  last-read post id, and message number.
- failed flushes must not discard pending read data.
- `R` opens PostComposer with reply target and origin.
- active thread PubSub refresh reloads posts.

Recommended reducer messages:

- `:load`
- `{:task_result, :load_posts, {:ok, posts}}`
- `{:task_result, :load_posts, {:error, reason}}`
- `{:task_result, :flush_read_pointers, {:ok, flushed_ctx_or_thread_id}}`
- `{:task_result, :flush_read_pointers, {:error, reason}}`
- `{:thread_activity, thread_id, event}`
- `{:key, key_event}`

Recommended effect ops:

- `:load_posts`
- `:flush_read_pointers`

Recommended route params:

- `%{board: board, board_id: board_id, thread: thread, thread_id: thread_id}`
- Reply navigation should include enough data for PostComposer:
  `%{origin: :post_reader, board: board, board_id: board_id, thread: thread,
  thread_id: thread_id, reply_to: post}`

### PostComposer

Current state module already owns:

- `mode`
- `reply_to`
- `error`
- `input_state`
- `origin`

Phase 37 should expand or adapt it to own:

- board identity and optional board struct
- thread identity and optional thread struct
- reply target
- submission status, such as `:idle | :submitting | {:error, reason} |
  {:submitted, post}`
- cancel origin

Current submit path calls `posts_mod.create_reply/4` synchronously from
`handle_key/2`, reads `state.current_thread`, sets `current_screen`, clears
`composer_draft`, deletes local state, and returns `{:load_posts, thread.id,
jump_last: true}`. This should become:

- validation remains synchronous inside `update/3`
- valid submit emits `Effect.task(:submit_reply, :post_composer, fn -> ... end)`
- task result success emits navigation to PostReader with route params and a
  reload or reload-intent effect
- task result failure updates local error or modal effect according to existing
  UX

The existing editor and preview rendering should remain delegated to:

- `Foglet.TUI.Widgets.Composer.EditorFrame`
- `Foglet.TUI.Widgets.Compose`
- `Foglet.TUI.Widgets.Post.MarkdownBody`

### NewThread

Current state module already owns:

- board step vs compose step
- board list
- active board count
- selected board index
- selected board
- title input state
- body input state
- focus
- edit/preview mode
- error
- origin

Phase 37 should expand or adapt it to own:

- board-load status
- submission status
- submit result
- route-derived cancel origin

Current board load is App-owned through
`{:load_boards_for_new_thread}` and `{:boards_for_new_thread_loaded, ...}`.
Current create-thread submit calls `Foglet.Threads.create_thread/3`
synchronously, writes `current_board`, writes a legacy ThreadList selection map,
deletes NewThread state, and emits `{:load_threads, board.id}`.

The target path should be:

- `init/1` reads `%{origin: origin, board: board, board_id: board_id}` if
  present, otherwise starts at board picker with loading status.
- `update(:load, state, context)` emits
  `Effect.task(:load_boards_for_new_thread, :new_thread, fn -> ... end)`.
- `update({:task_result, :load_boards_for_new_thread, {:ok, {boards,
  active_board_count}}}, state, context)` stores results locally.
- valid submit emits `Effect.task(:create_thread, :new_thread, fn -> ... end)`.
- create-thread success emits `Effect.navigate(:thread_list, %{board: board,
  board_id: board.id, select_thread_id: thread.id})` plus a ThreadList reload
  effect or a route param that ThreadList consumes.

ThreadList currently stores only `selected_index`; to support "select the new
thread after reload" robustly, the plan should either extend
`ThreadList.State` with a `selection_intent` or `select_thread_id` field and
apply it after load, or document a narrow index-0 compatibility if the domain
sort guarantee is enough. The SPEC allows either new-thread id or first-row
intent, but the former is less brittle.

## Planning Recommendations

Recommended plan split:

1. PostReader local-state and load/read-pointer ownership.
2. PostReader navigation, active-thread refresh, and App post-load cleanup.
3. PostComposer contract, async reply submission, and reload/jump handoff.
4. NewThread contract, board loading, async create-thread, and ThreadList
   selection intent.
5. App cleanup, render fixtures, smoke tests, and integrated verification.

This split keeps PostReader read-pointer behavior isolated before composer
success paths depend on PostReader reload semantics. It also avoids mixing the
NewThread-to-ThreadList handoff with reply-to-PostReader behavior.

## Key Risks And Pitfalls

- Do not keep App `posts` as the source of truth for PostReader after adding
  `PostReader.State.posts`; that would create split ownership.
- Do not clear pending read data on failed flush. This is an explicit behavior
  change from any App path that deletes `read_position` unconditionally.
- Do not rebuild viewport/render cache inside render as a state mutation.
  Existing PostReader comments require render helpers to remain pure.
- Do not route task results back as legacy tuples such as `{:posts_loaded, ...}`
  or `{:boards_for_new_thread_loaded, ...}`. Use
  `{:screen_task_result, key, op, result}` through `Effect.task/3`.
- Do not let composer submit paths call domain contexts synchronously from key
  handlers.
- Do not add browser-facing workflows.
- Do not write tests that only check text presence. Use reducer state, effects,
  task result messages, route params, and focused render smoke/layout contracts.

## Validation Architecture

Use existing ExUnit and TUI smoke infrastructure.

Quick feedback commands:

- `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs`
- `rtk mix test test/foglet_bbs/tui/screens/post_composer_test.exs`
- `rtk mix test test/foglet_bbs/tui/screens/new_thread_test.exs`
- `rtk mix test test/foglet_bbs/tui/app_runtime_contract_test.exs test/foglet_bbs/tui/app_test.exs`
- `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs`

Full finish command:

- `rtk mix precommit`

Required automated checks by behavior:

- PostReader reducer tests for `init/1`, `:load`, post-load success/failure,
  empty load, navigation keys, reply/back effects, active-thread refresh, and
  flush success/failure.
- PostReader state tests proving pending read data is seeded on entry, advances
  monotonically, clears only after successful flush, and survives failed flush.
- PostComposer reducer tests for edit/preview toggling, input, validation,
  missing user, async submit task emission, submit success, submit error,
  cancel origin, markdown preview, and max length.
- NewThread reducer tests for board load request/result/error, empty board
  states, board selection, title/body focus, edit/preview toggling, validation,
  async create-thread task emission, success navigation, error handling, and
  cancel origin.
- App runtime tests proving the old App clauses no longer mutate Phase 37 local
  state and generic task routing is sufficient.
- Layout smoke tests for PostReader, PostComposer, and NewThread at supported
  terminal sizes.

Manual verification is not required for this phase if the reducer and smoke
coverage above is implemented.

## Open Planning Questions

- Whether ThreadList should gain an explicit `select_thread_id` route param or
  whether NewThread success can rely on the existing newest-first sort and
  select index 0. Prefer explicit `select_thread_id` if it can be kept small.
- Whether PostReader should store pending read data as a map keyed by thread id
  or as a single current pending entry. A map is closer to existing
  `read_position`; a single current entry is simpler if PostReader owns only one
  active thread at a time.
- Whether App route-entry dispatch for PostReader should call
  `route_screen_update(state, :post_reader, :load)` directly or whether
  navigation effects into PostReader should include a separate explicit load
  effect. Prefer route-entry dispatch for consistency with ThreadList.
