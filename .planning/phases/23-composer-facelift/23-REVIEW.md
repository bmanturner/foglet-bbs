---
phase: 23-composer-facelift
reviewed: 2026-04-25T22:18:59Z
depth: standard
files_reviewed: 9
files_reviewed_list:
  - lib/foglet_bbs/tui/screens/new_thread.ex
  - test/foglet_bbs/tui/screens/new_thread_test.exs
  - lib/foglet_bbs/tui/widgets/composer/editor_frame.ex
  - test/foglet_bbs/tui/widgets/composer/editor_frame_test.exs
  - lib/foglet_bbs/tui/widgets/README.md
  - test/foglet_bbs/tui/layout_smoke_test.exs
  - lib/foglet_bbs/tui/screens/post_composer.ex
  - test/foglet_bbs/tui/app_test.exs
  - test/foglet_bbs/tui/screens/post_composer_test.exs
findings:
  critical: 1
  warning: 0
  info: 0
  total: 1
status: issues_found
---

# Phase 23: Code Review Report

**Reviewed:** 2026-04-25T22:18:59Z
**Depth:** standard
**Files Reviewed:** 9
**Status:** issues_found

## Summary

Reviewed the Phase 23 composer shell, the PostComposer and NewThread migrations, and the added test coverage. The shared `EditorFrame` remains presentation-only and PostComposer preserves its existing max-length enforcement. NewThread now renders a configured body budget, but it still allows submission of bodies over that limit, creating an inconsistent and user-visible regression from the configured `max_post_length` contract.

## Critical Issues

### CR-01: NewThread Shows Body Limit But Does Not Enforce It

**File:** `lib/foglet_bbs/tui/screens/new_thread.ex:328`

**Issue:** `render_compose_step/2` displays a body budget using `max_body_length(state)` at lines 101-104, but `do_submit/2` only rejects blank bodies before calling `threads_mod.create_thread/3`. Unlike `PostComposer`, the NewThread body input is never clipped during editing and never rejected on submit when it exceeds the configured `max_post_length`. The domain changeset still permits up to 65,535 characters, so a deployment configured for a lower TUI limit, such as 1,000 characters, will accept oversized root posts even while the UI marks the counter as over limit. This breaks the runtime limit contract and can create posts the reply composer would not allow.

**Fix:**

```elixir
defp do_submit(state, ss) do
  title = String.trim(ss.title_input_state.raxol_state.value)
  body = ss.body_input_state.value
  board = ss.board
  max = max_body_length(state)

  cond do
    title == "" ->
      {:update, put_ss(state, %{ss | error: "Title cannot be empty."}), []}

    String.trim(body) == "" ->
      {:update, put_ss(state, %{ss | error: "Post body cannot be empty."}), []}

    String.length(body) > max ->
      {:update,
       put_ss(state, %{ss | error: "Post body exceeds maximum length of #{max} characters."}),
       []}

    true ->
      do_create_thread(state, ss, title, body, board)
  end
end
```

Add a focused test in `test/foglet_bbs/tui/screens/new_thread_test.exs` that sets `session_context: %{max_post_length: 5}`, enters a longer body, presses Ctrl+S, and asserts the screen remains `:new_thread` with an inline error and no `{:load_threads, _}` command.

---

_Reviewed: 2026-04-25T22:18:59Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
