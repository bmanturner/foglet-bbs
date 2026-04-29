---
phase: 37
reviewed: 2026-04-29T01:14:53Z
depth: standard
files_reviewed: 17
files_reviewed_list:
  - lib/foglet_bbs/tui/app.ex
  - lib/foglet_bbs/tui/render_fixtures.ex
  - lib/foglet_bbs/tui/screens/post_reader.ex
  - lib/foglet_bbs/tui/screens/post_reader/state.ex
  - lib/foglet_bbs/tui/screens/post_composer.ex
  - lib/foglet_bbs/tui/screens/post_composer/state.ex
  - lib/foglet_bbs/tui/screens/new_thread.ex
  - lib/foglet_bbs/tui/screens/new_thread/state.ex
  - lib/foglet_bbs/tui/screens/thread_list.ex
  - lib/foglet_bbs/tui/screens/thread_list/state.ex
  - test/foglet_bbs/tui/app_runtime_contract_test.exs
  - test/foglet_bbs/tui/app_test.exs
  - test/foglet_bbs/tui/layout_smoke_test.exs
  - test/foglet_bbs/tui/screens/post_reader_test.exs
  - test/foglet_bbs/tui/screens/post_composer_test.exs
  - test/foglet_bbs/tui/screens/new_thread_test.exs
  - test/foglet_bbs/tui/screens/thread_list_test.exs
findings:
  critical: 1
  warning: 1
  info: 0
  total: 2
status: issues
---

# Phase 37: Code Review Report

**Reviewed:** 2026-04-29T01:14:53Z
**Depth:** standard
**Files Reviewed:** 17
**Status:** issues

## Summary

Reviewed the Phase 37 post reader, post composer, new thread, ThreadList handoff, App routing, render fixtures, and focused tests. The implementation has a blocker in route-local state reuse: navigating to the same migrated screen with different route params keeps stale reducer state, so loads can target the previous board/thread. I also found a flush task-result shape that hides read-pointer flush failures from the local reducer.

## Critical Issues

### CR-01: BLOCKER - Route-local screen state is reused across different route params

**File:** `lib/foglet_bbs/tui/app.ex:781`

**Issue:** `init_route_screen_state/3` skips initialization whenever any local state already exists for a screen key. That is incorrect for routed Phase 37 screens because the local state owns route identity. After leaving PostReader, the `:post_reader` state remains in `screen_state`; opening a different thread calls `maybe_dispatch_route_entry/3`, but `PostReader.update(:load, ...)` uses the stale `state.thread_id` at `post_reader.ex:75-80`, not the new route params. The same stale-state path affects ThreadList: `ThreadList.update(:load, ...)` uses the old `state.board_id` at `thread_list.ex:36-45`, so NewThread's success navigation with `select_thread_id` at `new_thread.ex:550-557` can reload the previous board and lose the intended selection. PostComposer's post-submit `load_intent: :jump_last` navigation at `post_composer.ex:445-453` is also vulnerable when an old PostReader state exists.

**Fix:** Reinitialize or reconcile route-owned local state whenever route params change for routed screens. A conservative fix is to always replace local state for the Phase 37 routed screens on navigation:

```elixir
defp init_route_screen_state(%__MODULE__{} = state, screen, params) do
  key = screen_key(screen)
  module = screen_module_for(state, key)

  cond do
    key in [:thread_list, :post_reader, :post_composer, :new_thread] and
        Code.ensure_loaded?(module) and function_exported?(module, :init, 1) ->
      put_screen_state(state, key, module.init(build_context(state, params)))

    screen_state_for(state, key) != nil ->
      state

    Code.ensure_loaded?(module) and function_exported?(module, :init, 1) ->
      put_screen_state(state, key, module.init(build_context(state, params)))

    true ->
      state
  end
end
```

Add regression coverage that opens thread A, leaves to ThreadList, opens thread B, and proves the PostReader load task uses thread B. Add a second case for NewThread success navigating to ThreadList with `select_thread_id` while an old ThreadList state already exists.

## Warnings

### WR-01: WARNING - Read-pointer flush failures are wrapped as successes and ignored

**File:** `lib/foglet_bbs/tui/screens/post_reader.ex:122`

**Issue:** `flush_effect/2` returns `{:error, reason}` from the task function when either pointer advance fails (`post_reader.ex:840-845`). App task handling wraps all task returns in `{:ok, fun.()}`, so the reducer receives `{:task_result, :flush_read_pointers, {:ok, {:error, reason}}}`. The current clauses only handle `{:ok, {:read_pointers_flushed, thread_id}}`, `{:ok, thread_id}`, and outer `{:error, reason}` at `post_reader.ex:122-135`; the wrapped inner error falls through to the catch-all and leaves `last_error` unset. Pending read state is preserved, but the failure is invisible to the reducer.

**Fix:** Handle wrapped inner errors explicitly:

```elixir
def update(
      {:task_result, :flush_read_pointers, {:ok, {:error, reason}}},
      %State{} = state,
      %Context{}
    ) do
  {%{state | last_error: reason}, []}
end
```

Add a reducer test for a flush task result shaped as `{:ok, {:error, reason}}` and assert the pending read position remains while `last_error` records the failure.

---

_Reviewed: 2026-04-29T01:14:53Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
