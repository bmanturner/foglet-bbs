# Phase 6: ThreadList — Research

**Researched:** 2026-04-21
**Domain:** Elixir TUI screen audit — ThreadList correctness guard, preload contract coverage, initializer normalization, and loading-affordance decision
**Confidence:** HIGH (grounded in direct reads of `thread_list.ex`, `thread_list_test.exs`, `threads.ex`, `app.ex`, roadmap, requirements, and phase context)

## Summary

Phase 6 is a bounded audit pass on `lib/foglet_bbs/tui/screens/thread_list.ex`
plus targeted contract tests in `test/foglet_bbs/tui/screens/thread_list_test.exs`.
Current row metadata and sticky-then-recency sort behavior are already correct and
must remain unchanged. The non-negotiable correctness gap is module-load probing:
`function_exported?/3` is used without `Code.ensure_loaded/1`, so the intended
2-arity dispatch can be bypassed for unloaded modules.

Required deltas:

1. Add `Code.ensure_loaded/1` guard before `function_exported?/3` probes in `load_threads/2` (THREADS-02).
2. Add public `init_screen_state/1` and replace inline `%{selected_index: 0}` fallbacks (AUDIT-19 / THREADS-06).
3. Keep `load_threads/2` as test seam with `@doc false` and explicit App ownership comment (THREADS-03).
4. Evaluate and implement spinner-backed loading affordance for real async load state only (`current_thread_list == nil`) (THREADS-05 / AUDIT-10).
5. Add coverage proving `Threads.list_threads/2` returns rows with `created_by.handle` available (THREADS-04).

## Current Code Read

### `lib/foglet_bbs/tui/screens/thread_list.ex`

- Correctly renders thread row metadata (`@handle · post_count · time-ago`) through `ListRow.render_with_metadata/6`.
- Correctly keeps two-pass sort (`sticky` bucket + per-bucket recency) to avoid nil-recency pitfalls.
- Uses inline `%{selected_index: 0}` defaults in `render/1`, `handle_key/2`, and `move_selection/2`.
- Loading state currently shows static `"Loading..."` when sorted list is empty; this branch conflates loading and empty-list fallback behavior.
- `load_threads/2` probes `function_exported?/3` without `Code.ensure_loaded/1`.

### `lib/foglet_bbs/tui/app.ex`

- Production loading ownership for threads is in `do_update({:load_threads, board_id}, state)`.
- Screen-level `ThreadList.load_threads/2` remains a compatibility/test seam, not the production orchestrator.

### `lib/foglet_bbs/threads.ex`

- `list_threads/1` preloads `:created_by`.
- `list_threads/2` returns maps and explicitly batches/preloads `:created_by` via `preload_created_by/1`.
- Current tests do not directly lock `created_by.handle` on the row contract for the 2-arity path.

### `test/foglet_bbs/tui/screens/thread_list_test.exs`

- Already verifies metadata rendering and sort behavior.
- Already checks 2-arity vs 1-arity dispatch with fake modules, but not the `Code.ensure_loaded/1` guard path explicitly.
- Missing direct test that `Threads.list_threads/2` rows include `created_by.handle`.

## Evidence Snapshot

- `thread_list.ex` currently contains `function_exported?(threads_mod, :list_threads, 2)` and `(…, 1)` without load guard.
- `thread_list.ex` currently has no `init_screen_state/1` function.
- `threads.ex` has explicit `created_by` preload logic for both arities.

## Validation Architecture

### Automated checks

- Focused screen suite: `mix test test/foglet_bbs/tui/screens/thread_list_test.exs`
- Domain preload contract suite: `mix test test/foglet_bbs/threads_test.exs`
- Full quality gate: `mix precommit`
- Dead-code seam evidence: `rg -n "load_threads" lib test`
- Plan structure checks: `gsd-sdk query frontmatter.validate ... --schema plan` and `gsd-sdk query verify.plan-structure ...`

### Required behavior assertions

- Sticky-then-recency ordering remains unchanged.
- Row metadata still includes handle, post-count pluralization, and time-ago/new segment.
- 2-arity path selection remains preferred when available, now guarded by `Code.ensure_loaded/1`.
- Loading affordance appears only while load is in-flight (`current_thread_list == nil`).
- `created_by` preload contract is asserted by tests (not just implied by implementation).

## Risks and Landmines

- Do not collapse the two-pass sort into a single `order_by` approximation.
- Do not add new row gutters/secondary decorations (AUDIT-17 Region 3 reserved).
- Do not move production load ownership from App into the screen module.
- Do not add render-path state mutation.

## Recommended Plan Shape

One execute plan in Wave 1:

1. Screen updates (`init_screen_state/1`, load guard, spinner loading branch, seam docs) in `thread_list.ex`.
2. Tests that lock arity-dispatch correctness and preload contract in `thread_list_test.exs` and `threads_test.exs`.
3. Run full gate (`mix precommit`) and preserve scope fence.
