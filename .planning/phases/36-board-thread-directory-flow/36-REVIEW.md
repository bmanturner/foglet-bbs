---
phase: 36-board-thread-directory-flow
reviewed: 2026-04-28T21:10:43Z
depth: standard
files_reviewed: 13
files_reviewed_list:
  - lib/foglet_bbs/tui/app.ex
  - lib/foglet_bbs/tui/render_fixtures.ex
  - lib/foglet_bbs/tui/screens/board_list.ex
  - lib/foglet_bbs/tui/screens/board_list/state.ex
  - lib/foglet_bbs/tui/screens/main_menu.ex
  - lib/foglet_bbs/tui/screens/thread_list.ex
  - lib/foglet_bbs/tui/screens/thread_list/state.ex
  - test/foglet_bbs/tui/app_runtime_contract_test.exs
  - test/foglet_bbs/tui/app_test.exs
  - test/foglet_bbs/tui/layout_smoke_test.exs
  - test/foglet_bbs/tui/screens/board_list_test.exs
  - test/foglet_bbs/tui/screens/main_menu_test.exs
  - test/foglet_bbs/tui/screens/thread_list_test.exs
findings:
  critical: 2
  warning: 0
  info: 0
  total: 2
status: issues_found
---

# Phase 36: Code Review Report

**Reviewed:** 2026-04-28T21:10:43Z
**Depth:** standard
**Files Reviewed:** 13
**Status:** issues_found

## Summary

Reviewed the App runtime routing, main menu, board directory, thread directory, render fixtures, and listed tests. The reducer-level tests cover each screen in isolation, but the app-level directory flow has two blocking integration breaks: opening a board never starts the thread load, and opening a thread never bridges into PostReader's legacy top-level state/load contract.

## Critical Issues

### CR-01: Opening a Board Leaves ThreadList Permanently Loading

**File:** `lib/foglet_bbs/tui/screens/board_list.ex:102`
**Issue:** Activating a board emits only `Effect.navigate(:thread_list, %{...})`. `App.apply_effect/2` handles navigation by setting `current_screen`, `route_params`, clearing the modal, and initializing the target state, but it returns no commands and does not call `ThreadList.update(:load, ...)` (`lib/foglet_bbs/tui/app.ex:146-157`). The initialized ThreadList state therefore stays `status: :loading` with `threads: nil` forever after the real BoardList -> ThreadList flow. The existing tests assert the raw navigate effect but do not apply it through App, so this regression is missed.
**Fix:**
```elixir
# In BoardList.update/3, include the ThreadList-owned load effect after navigation.
thread_state = ThreadList.State.from_context(%{context | route_params: params})
{thread_state, load_effects} = ThreadList.update(:load, thread_state, %{context | route_params: params})

{local_state,
 [Effect.navigate(:thread_list, params) | load_effects]}
```

Alternatively, make `App.apply_effect/2` dispatch `:load` for new-contract screens after `init_route_screen_state/3`, then add an App-level test that presses Enter on a loaded BoardList and asserts a `:load_threads` command is returned and routed back to `screen_state[:thread_list]`.

### CR-02: Opening a Thread Never Loads Posts or Sets PostReader Context

**File:** `lib/foglet_bbs/tui/screens/thread_list.ex:94`
**Issue:** Entering a selected thread emits only `Effect.navigate(:post_reader, params)`. PostReader is still a legacy screen: it has `render/1` and `handle_key/2`, no `init/1`, and it relies on top-level `state.current_board`, `state.current_thread`, `state.posts`, and `{:load_posts, thread_id}` orchestration. `App.apply_effect/2` stores the thread only in `route_params` and `init_route_screen_state/3` is a no-op for PostReader because there is no `init/1` (`lib/foglet_bbs/tui/app.ex:1025-1033`). The result is a PostReader that renders "Loading..." indefinitely, cannot seed read pointers through `load_posts/2`, and builds an empty flush context on Q because `build_flush_context/1` reads `state.current_thread` and `state.current_board` (`lib/foglet_bbs/tui/screens/post_reader.ex:182-193`, `lib/foglet_bbs/tui/screens/post_reader.ex:538-541`).
**Fix:**
```elixir
# In App.apply_effect/2 or a PostReader-specific navigation helper:
state =
  case screen do
    :post_reader ->
      state
      |> Map.put(:current_board, params[:board])
      |> Map.put(:current_thread, params[:thread])
      |> Map.put(:posts, nil)

    _ ->
      state
  end

commands =
  case {screen, params[:thread_id]} do
    {:post_reader, thread_id} when is_binary(thread_id) ->
      elem(do_update({:load_posts, thread_id}, state), 1)

    _ ->
      []
  end
```

Keep the exact shape aligned with the existing App command pipeline, and add an App-level integration test that routes from a loaded ThreadList through Enter, asserts `current_thread/current_board` are set, asserts a `:load_posts` command is emitted, and verifies a returned `:posts_loaded` result populates `posts` and `screen_state[:post_reader]`.

---

_Reviewed: 2026-04-28T21:10:43Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
