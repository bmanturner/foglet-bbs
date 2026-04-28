# Phase 37: Post & Composer Flow - Specification

**Created:** 2026-04-28
**Ambiguity score:** 0.13 (gate: <= 0.20)
**Requirements:** 9 locked

## Goal

PostReader, PostComposer, and NewThread own post loading, read state, drafts, submissions, route data, async results, and navigation decisions through the Phase 34 screen update-loop contract, without App-level post/composer flow ownership.

## Background

Phase 34 added `Foglet.TUI.Screen.init/1`, `update/3`, and `render/2`, `Foglet.TUI.Context`, and explicit `Foglet.TUI.Effect` values. Phase 35 migrated auth/home screens, and Phase 36 migrates board/thread directory ownership before this phase.

The current post and composer screens already have first-class state structs: `PostReader.State`, `PostComposer.State`, and `NewThread.State`. They still run through the transitional legacy path: `render/1`, `handle_key/2`, and App-shaped state. `Foglet.TUI.App` still stores and mutates post/composer flow data through top-level fields such as `current_thread`, `posts`, `read_position`, and `composer_draft`, and still owns task/result clauses for `{:load_posts, ...}`, `{:posts_loaded, ...}`, `{:flush_read_pointers, ...}`, `{:read_pointers_flushed, ...}`, `{:load_boards_for_new_thread}`, and `{:boards_for_new_thread_loaded, ...}`. PostReader currently builds read-pointer flush context from App `current_board` and `current_thread`; thread activity refresh and thread PubSub subscriptions also depend on App `current_thread`.

PostComposer and NewThread keep drafts and widget state in local structs, but submit/cancel paths still mutate App fields directly and call domain modules synchronously from screen key handlers. NewThread board loading is App-owned, and successful thread creation writes App `current_board` and legacy ThreadList state before dispatching `{:load_threads, board.id}`. Phase 37 moves these flows behind the screen reducer/effect boundary while preserving existing terminal behavior.

## Requirements

1. **PostReader contract migration**: `Foglet.TUI.Screens.PostReader` initializes, updates, and renders through screen-local state plus `Foglet.TUI.Context`.
   - Current: PostReader exposes a `State` struct but receives broad App state in `render/1` and `handle_key/2`, while loaded posts live in App `posts`.
   - Target: PostReader exposes `init/1`, `update/3`, and `render/2`; its local state stores loaded posts, loading/error status, selected post index, viewport state, render cache, selected board/thread route data, and pending read-pointer data.
   - Acceptance: Reducer tests initialize PostReader from route params, request post loading, consume successful and empty post loads, render without App-shaped `posts`, and preserve selected index/viewport/cache in local state.

2. **PostReader read-pointer ownership**: PostReader owns local read tracking and flush request/result handling without App `read_position`.
   - Current: PostReader advances `state.read_position` keyed by App `current_thread.id`; Q builds a flush context from App `current_board/current_thread`; App dispatches the flush task and clears `read_position` on `:read_pointers_flushed`.
   - Target: PostReader records the latest visible post in local state, emits a task effect or runtime-compatible effect to flush board and thread read pointers on exit, and handles flush success/failure through `update/3` without App mutating per-thread read state.
   - Acceptance: Tests prove entry seeds the first visible post as read, N/P/Page navigation advances local pending read data, Q emits a flush request with user id, board id, thread id, last post id, and last message number, success clears only the flushed pending read data, and failure leaves pending data available for retry.

3. **PostReader navigation and live refresh**: PostReader owns reply/back navigation and thread activity refresh through route params and effects.
   - Current: Reply writes `current_screen`, `composer_draft`, and `screen_state[:post_composer]`; back writes `current_screen`, clears App `posts`, and emits `{:flush_read_pointers, ctx}`; App refreshes posts on `{:thread_activity, thread_id, _}` by comparing App `current_thread.id`.
   - Target: Reply emits navigation to `:post_composer` with reply/thread/board route data and initialized composer state; back emits navigation to `:thread_list` plus the read-pointer flush request; thread activity for the active thread is routed into PostReader update logic using route params or screen state.
   - Acceptance: Tests prove reply navigation carries reply target and origin, Q navigates back to ThreadList and does not clear App `posts`, unrelated thread activity is ignored, active thread activity requests a post reload, and PubSub topic derivation no longer depends on App `current_thread` for PostReader.

4. **PostComposer contract migration**: `Foglet.TUI.Screens.PostComposer` owns reply draft editing, preview state, validation errors, submission results, and cancel origin through the new update-loop contract.
   - Current: PostComposer uses `PostComposer.State` for widget data but handles keys through App-shaped state, reads App `current_thread`, mutates App `composer_draft`, opens App modals directly, and calls `Foglet.Posts.create_reply/4` synchronously.
   - Target: PostComposer exposes `init/1`, `update/3`, and `render/2`; its local state stores thread/board/reply route data, draft input state, edit/preview mode, validation/submission status, errors, and origin; reply submission happens through a task effect and the result returns to PostComposer update logic.
   - Acceptance: Tests prove edit/preview toggling, multiline input changes, empty body validation, max-length validation, missing-user denial, thread-locked/posting-denied errors, successful submission result handling, and cancel-origin navigation all operate without App `composer_draft` or App `current_thread`.

5. **PostComposer post-submit behavior**: Reply submission preserves the existing reload-and-jump behavior through screen-owned effects.
   - Current: Successful reply creation navigates to PostReader, deletes composer state, and emits `{:load_posts, thread.id, jump_last: true}`; App consumes `jump_last: true` in `{:posts_loaded, ...}` and sets PostReader selected index to the last post.
   - Target: Successful reply submission navigates to PostReader with route params and emits a PostReader load/reload request that selects the last post after the reload completes.
   - Acceptance: Tests prove a successful reply causes PostReader to reload the same thread, selects the newest post after the load result, clears only the completed composer local state, and preserves the existing markdown preview and soft-wrapping behavior.

6. **NewThread contract migration**: `Foglet.TUI.Screens.NewThread` owns board picker state, compose drafts, validation errors, board-load results, thread submission results, and cancel origin through the new update-loop contract.
   - Current: NewThread uses a local `State` struct but receives App state; App owns `:load_boards_for_new_thread` and `:boards_for_new_thread_loaded`; submit calls `Foglet.Threads.create_thread/3` synchronously and writes App `current_board` plus legacy ThreadList state.
   - Target: NewThread exposes `init/1`, `update/3`, and `render/2`; it requests subscribed-board loading via a task effect, consumes board-load success/failure locally, stores title/body input state and selected board locally, and submits new threads through a task effect whose result returns to NewThread update logic.
   - Acceptance: Tests prove board load request, board-load success with active-board count, empty subscribed-board state, board selection, title/body focus switching, edit/preview toggling, validation errors, create-thread success/failure result handling, and cancel-origin navigation all operate without App writing NewThread local state.

7. **NewThread post-submit navigation**: NewThread successful submission returns to ThreadList through route params and screen-owned reload effects.
   - Current: A successful create-thread path writes App `current_board`, sets `screen_state[:thread_list]` to a map with selected index 0, deletes NewThread state, and emits `{:load_threads, board.id}`.
   - Target: A successful create-thread result navigates to ThreadList with selected board route data and a selection intent for the new thread or first row, then requests a ThreadList-owned reload through the established route/effect boundary from Phase 36.
   - Acceptance: Tests prove successful thread creation deletes only completed NewThread local state, navigates to ThreadList with board identity in route params, requests ThreadList reload without App `current_board`, and preserves the existing "new thread appears selected after reload" behavior.

8. **App post/composer flow ownership removal**: App no longer owns migrated post/composer local-flow clauses or state mutation.
   - Current: App owns load/result/flush/new-thread board clauses and top-level fields for post/composer flows; it mutates PostReader and NewThread screen state directly for loaded results and compatibility.
   - Target: PostReader, PostComposer, and NewThread work routes through generic screen update/effect/task handling. Any remaining App involvement is generic runtime interpretation, modal/SizeGate precedence, route storage, PubSub forwarding, session lifecycle, or explicitly named transition compatibility for later Phase 39 cleanup.
   - Acceptance: A code-level check or App test proves App no longer handles `:posts_loaded`, `:load_posts`, `:flush_read_pointers`, `:read_pointers_flushed`, `:load_boards_for_new_thread`, or `:boards_for_new_thread_loaded` by mutating post/composer local state, and App no longer mutates `posts`, `read_position`, `composer_draft`, or `current_thread` for migrated flows.

9. **Full feature parity and documentation**: Existing post reading, reply composition, and new-thread behavior remains stable while ownership moves.
   - Current: Tests cover PostReader loading/navigation/scrolling/cache/read-pointer seams, PostComposer edit/preview/input/submit/cancel behavior, NewThread board picking/composition/submit behavior, resize-gate draft preservation, PubSub refresh, and render smoke paths through a mix of App-shaped and screen-level tests.
   - Target: Equivalent coverage asserts screen-local state and effects instead of App top-level fields, canonical render smoke checks still pass, and target module docs/state docs describe screen-owned reducer boundaries.
   - Acceptance: Targeted PostReader/PostComposer/NewThread reducer tests, relevant App runtime tests, and canonical post/composer render smoke checks pass; docs and module comments no longer describe App as the owner of post/composer flow state.

## Boundaries

**In scope:**
- Migrate PostReader post data, loading/error status, selected post index, viewport state, render cache, read-pointer pending state, post-load results, read-pointer flush requests, and thread-activity refresh into PostReader local state/update.
- Migrate PostComposer draft input, reply target, edit/preview mode, validation errors, submission status/results, reply success navigation, and cancel origin into PostComposer local state/update.
- Migrate NewThread board picker, board-load results, active-board count, selected board, title/body drafts, edit/preview mode, validation errors, submission status/results, success navigation, and cancel origin into NewThread local state/update.
- Replace App `current_thread`, `posts`, `read_position`, and `composer_draft` as sources of truth for migrated post/composer flows with route params and screen-local state.
- Preserve full existing feature behavior: markdown rendering, soft wrapping, render cache behavior, viewport scrolling, read-pointer monotonicity, reply jump-to-last, locked/thread policy denials, empty-state messages, edit/preview toggles, keyboard behavior, resize-gate draft preservation, and PubSub refresh.
- Update focused PostReader/PostComposer/NewThread reducer tests and relevant App runtime tests to assert generic effect/task routing and screen-owned state.
- Update target screen docs and state modules to describe the new ownership boundary.

**Out of scope:**
- Changing durable post, thread, board, read-pointer, or authorization domain behavior - context modules remain authoritative.
- Visual redesign of PostReader, PostComposer, NewThread, PostCard, MarkdownBody, EditorFrame, MultiLineInput, or chrome widgets - this phase is an ownership/runtime migration.
- Migrating Account, Moderation, or Sysop screens - Phase 38 owns account/operator workbench migration.
- Removing all remaining legacy App screen-specific fields and clauses unrelated to post/composer flows - Phase 39 owns final App shell simplification.
- Introducing new composer features such as attachments, autosave persistence, quoting redesign, or rich-text editing - not required for SCREEN-04.
- Adding browser-facing post, reply, or thread workflows - Foglet remains SSH/TUI-first.

## Constraints

- The primary product surface remains SSH/TUI; no end-user Phoenix browser flow is introduced.
- Screens must use the Phase 34 screen contract: `init/1`, `update/3`, `render/2`, screen-local state, and `Foglet.TUI.Context`, not broad App-shaped state for local flow ownership.
- Domain side effects remain in `Foglet.Posts`, `Foglet.Threads`, `Foglet.Boards`, authorization contexts, and related domain modules.
- Async domain work requested by PostReader/PostComposer/NewThread must use the Phase 34 task-effect path through `Foglet.TUI.Command.task/2` or an equivalent generic effect interpreted by App.
- Task success/failure for migrated post/composer flows must return through the requesting screen's `update/3`.
- Read pointers are monotonic persisted user state; advancing and flushing them must remain at least as durable as the current behavior, and failed flushes must not silently discard pending local read data.
- Modal precedence, SizeGate behavior, session lifecycle, and generic effect interpretation remain App/runtime responsibilities.
- Existing render contracts should remain stable except where minimal adaptation is required by the ownership migration.
- Route params and screen-local state must carry enough board/thread/post identity for navigation, PubSub topic derivation, post reloads, reply submission, new-thread success navigation, and read-pointer flushing without App `current_thread` or App `current_board` as the source of truth.

## Acceptance Criteria

- [ ] PostReader can be initialized, updated, and rendered through `init/1`, `update/3`, and `render/2` with loaded posts, selected index, viewport, render cache, thread route data, and pending read-pointer state stored locally.
- [ ] PostReader handles post load success/failure, empty post lists, thread activity refresh, reply navigation, back navigation, and read-pointer flush success/failure through PostReader update logic.
- [ ] PostReader read-pointer behavior remains monotonic: first visible post is seeded on entry, visible post navigation advances pending read data, successful flush clears it, and failed flush keeps it for retry.
- [ ] PostComposer can be initialized, updated, and rendered through `init/1`, `update/3`, and `render/2` with draft input, reply target, mode, errors, submission status, and origin stored locally.
- [ ] PostComposer handles validation, posting-denied/thread-locked failures, successful reply task results, cancel-origin navigation, markdown preview, max-length enforcement, and reload/jump-to-last behavior without App `composer_draft` or App `current_thread`.
- [ ] NewThread can be initialized, updated, and rendered through `init/1`, `update/3`, and `render/2` with board picker data, active-board count, selected board, title/body input state, mode, errors, submission status, and origin stored locally.
- [ ] NewThread handles board load success/failure, no-subscribed-board and no-active-board empty states, validation failures, successful thread task results, cancel-origin navigation, and ThreadList reload handoff without App writing NewThread state.
- [ ] App post/composer local-flow clauses are removed or reduced to generic effect/task routing that does not mutate PostReader, PostComposer, or NewThread local state directly.
- [ ] PubSub topic derivation and thread activity refresh work from route params or screen-local state for PostReader/PostComposer, without App `current_thread` as the source of truth.
- [ ] Existing keyboard behavior, resize-gate draft preservation, markdown rendering, soft wrapping, render cache behavior, empty/loading states, policy denial messages, and render smoke checks remain covered.
- [ ] Targeted PostReader/PostComposer/NewThread reducer tests, relevant App runtime tests, and canonical post/composer render smoke checks pass.
- [ ] Target screen docs and state modules describe the new screen-owned ownership boundary.

## Ambiguity Report

| Dimension           | Score | Min   | Status | Notes |
|---------------------|-------|-------|--------|-------|
| Goal Clarity        | 0.93  | 0.75  | met    | Full migration of PostReader, PostComposer, and NewThread is locked. |
| Boundary Clarity    | 0.86  | 0.70  | met    | App flow-ownership removal is required; broader Phase 39 shell cleanup and visual redesign are excluded. |
| Constraint Clarity  | 0.82  | 0.65  | met    | Phase 34 contract, SSH/TUI surface, domain boundaries, task effects, route data, and read-pointer durability are locked. |
| Acceptance Criteria | 0.82  | 0.70  | met    | Pass/fail reducer ownership, read-pointer parity, submit/reload behavior, App clause removal, and feature parity checks are specified. |
| **Ambiguity**       | 0.13  | <=0.20| met    | Gate passed after round 1. |

Status: met = meets minimum, below = below minimum (planner treats as assumption)

## Interview Log

| Round | Perspective | Question summary | Decision locked |
|-------|-------------|------------------|-----------------|
| 1 | Researcher | What is the locked core deliverable for Phase 37? | Full ownership: PostReader, PostComposer, and NewThread all migrate to init/update/render and own their listed local state, results, and navigation handoffs. |
| 1 | Researcher | How strict should App field removal be? | Remove App flow ownership for post/composer flows; only generic runtime behavior or explicitly named compatibility may remain. |
| 1 | Researcher | Which preservation concern must be non-negotiable? | Full feature parity is required, with read-pointer monotonicity and retry behavior explicitly called out. |
| 1 | Gate | Ambiguity score reached 0.13. Proceed? | User selected "Yes, write SPEC". |

---

*Phase: 37-post-composer-flow*
*Spec created: 2026-04-28*
*Next step: $gsd-discuss-phase 37 - implementation decisions (how to build what's specified above)*
