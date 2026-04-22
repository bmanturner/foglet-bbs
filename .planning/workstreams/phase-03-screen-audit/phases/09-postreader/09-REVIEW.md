---
phase: 09-postreader
reviewed: 2026-04-22T16:45:00Z
depth: standard
files_reviewed: 2
files_reviewed_list:
  - lib/foglet_bbs/tui/screens/post_reader.ex
  - test/foglet_bbs/tui/screens/post_reader_test.exs
findings:
  critical: 0
  warning: 3
  info: 4
  total: 7
status: issues_found
---

# Phase 09: Code Review Report — PostReader

**Reviewed:** 2026-04-22T16:45:00Z
**Depth:** standard
**Files Reviewed:** 2
**Status:** issues_found

## Summary

Both files are in good shape after plan-02 changes. The `@default_terminal_size` module attribute is declared once (line 61) and referenced at all five call sites. `init_screen_state/1` is public with an `@spec` and `@doc`, `defp default_screen_state/0` is gone, and `get_screen_state/1` uses `init_screen_state([])`. The moduledoc "Screen state" section names `init_screen_state/1`. Load-absorb semantics, render-purity boundary, and viewport scroll are all correctly implemented and tested.

Three warnings from the prior review remain open — none were addressed by plan-02, which was scoped to the three audit-rubric gaps only. Two of these (WR-01 and WR-02) combine to create a scenario where a DB flush failure is undetectable by the caller and the local read-pointer is cleared regardless. WR-03 is a nil-key map lookup that is currently benign but could silently produce a bad flush context if `read_position[nil]` ever gets populated.

Four info items: the `p2_state/1` test fixture still falls back to real `Foglet.Markdown` in all `p2_state`-based tests, the purity-guard scope-tracking regex has a non-monotonic edge case, the two fake-posts modules are redundant, and the test file's nested `defmodule` blocks technically violate the CLAUDE.md convention (though this is the standard ExUnit fake pattern).

---

## Warnings

### WR-01: `flush_read_pointers/2` silently swallows domain errors

**File:** `lib/foglet_bbs/tui/screens/post_reader.ex:283-284`

**Issue:** The return values of `flush_board_pointer/3` and `flush_thread_pointer/3` are discarded at lines 283-284. When a domain module returns `{:error, reason}` (DB unavailability, auth failure), `flush_read_pointers/2` still returns `{state_with_cleared_pointer, []}` — the local read-pointer is cleared even though the flush never reached the DB. The caller (`TUI.App.do_update`) has no signal that the flush failed.

**Fix:** Capture results and condition the pointer-clear on success, or at minimum log:

```elixir
board_result  = flush_board_pointer(boards_mod, user_id, flush_ctx)
thread_result = flush_thread_pointer(threads_mod, user_id, flush_ctx)

ok? =
  board_result in [:skip, nil] or match?({:ok, _}, board_result)
  and (thread_result in [:skip, nil] or match?({:ok, _}, thread_result))

if ok? do
  new_rp = clear_read_position(state.read_position, flush_ctx[:thread_id])
  {%{state | read_position: new_rp}, []}
else
  require Logger
  Logger.warning("flush_read_pointers: flush failed — board: #{inspect(board_result)}, thread: #{inspect(thread_result)}")
  {state, []}
end
```

At minimum, wrap the calls in `_ =` and add a `Logger.warning` so failures appear in production logs.

---

### WR-02: `flush_board_pointer/3` and `flush_thread_pointer/3` return `nil` when their condition is falsy

**File:** `lib/foglet_bbs/tui/screens/post_reader.ex:294-309`

**Issue:** Both `flush_board_pointer/3` (lines 294-302) and `flush_thread_pointer/3` (lines 306-309) use a bare `if` with no `else` branch. When `ctx[:board_id]` or `ctx[:thread_id]` is falsy, Elixir's `if` returns `nil`, not `:skip` as the nil-`user_id` guard clause does (lines 292 and 304). This inconsistency means any code that inspects the return value (e.g. the WR-01 fix above) must handle both `:skip` and `nil` as "nothing happened," making the contract unclear.

**Fix:** Add an explicit `else :skip` to both functions:

```elixir
defp flush_board_pointer(boards_mod, user_id, ctx) do
  if ctx[:board_id] do
    boards_mod.advance_board_read_pointer(
      user_id,
      ctx[:board_id],
      ctx[:last_read_message_number] || 0
    )
  else
    :skip
  end
end

defp flush_thread_pointer(threads_mod, user_id, ctx) do
  if ctx[:thread_id] && ctx[:last_read_post_id] do
    threads_mod.advance_thread_read_pointer(user_id, ctx[:thread_id], ctx[:last_read_post_id])
  else
    :skip
  end
end
```

---

### WR-03: `build_flush_context/1` uses `nil` as a `Map.get/2` key when `current_thread` is absent

**File:** `lib/foglet_bbs/tui/screens/post_reader.ex:506-507`

**Issue:**

```elixir
thread_id = thread && thread.id
pos = Map.get(state.read_position, thread_id) || %{}
```

When `state.current_thread` is nil, `thread_id` is `nil` and `Map.get(state.read_position, nil)` silently returns whatever is stored under the `nil` key. In practice Q can only be pressed when the screen is active (which requires a current thread), but if any code path accidentally writes to `read_position[nil]`, `build_flush_context/1` would silently produce a flush context with stale or incorrect `last_read_post_id` / `last_read_message_number`.

**Fix:** Guard the lookup explicitly:

```elixir
pos =
  if thread_id do
    Map.get(state.read_position, thread_id, %{})
  else
    %{}
  end
```

---

## Info

### IN-01: `p2_state/1` fixture does not inject `domain` — render/navigation tests fall back to real `Foglet.Markdown`

**File:** `test/foglet_bbs/tui/screens/post_reader_test.exs:303`

**Issue:** `p2_state/1` sets `session_context: %{theme: theme()}` with no `domain` key. `parse_body/2` in the source uses `Domain.get(sc, :markdown)` and falls back to `Foglet.Markdown` when the key is absent. All `p2_state`-based tests that call `render/1` or navigate silently exercise the real production module. If `Foglet.Markdown` changes its contract or is unavailable, these tests will fail without a clear signal pointing to the fixture gap.

**Fix:** Add a `domain` key to the `p2_state/1` base fixture pointing to `FakeMarkdown` (already defined in the test module):

```elixir
session_context: %{theme: theme(), domain: %{markdown: FakeMarkdown}},
```

---

### IN-02: Purity-guard scope-tracking regex is non-monotonic for back-to-back `defp render_*` clauses

**File:** `test/foglet_bbs/tui/screens/post_reader_test.exs:250-261`

**Issue:** The `cond` inside the `Enum.reduce/3` at lines 246-263 uses `String.match?(line, ~r/^\s+defp render_/)` to enter render scope. Because `render_post_content/5` has two clauses (lines 82 and 87), the second clause re-triggers the "entering a render helper" branch rather than the "continue accumulating" branch. This re-accumulation is harmless for the current source, but the logic is non-monotonic: if a `defp render_*` function immediately follows another (without an intervening non-render `defp`), the second function's head line resets the `inside` state rather than maintaining it. A future `defp render_*` function added after `render_loading/1` would work correctly, but a second clause added to an existing `defp render_*` function continues to work only by coincidence of the regex order.

**Fix:** A more robust approach is a two-pass strategy: collect `{start_line, end_line}` ranges for each `defp render_*` function by scanning for matching `defp render_` heads and matching `end` keywords at the same indentation level, then check forbidden patterns only within those ranges. For the current source the existing test is sufficient.

---

### IN-03: `FakePosts` and `FakePostsForLoad` are structurally redundant

**File:** `test/foglet_bbs/tui/screens/post_reader_test.exs:6-63`

**Issue:** Both `FakePosts` (lines 6-25) and `FakePostsForLoad` (lines 44-63) implement `list_posts/1` returning a two-post list with identical structure. The only differences are the `inserted_at` source (`~U[...]` literal vs `DateTime.utc_now()`) and `message_number` values (`1/2` vs `5/6`). The `setup` block uses `FakePosts`; the `load_posts` describe blocks use `FakePostsForLoad`. Several tests in those blocks only care about `length/1` or read-position keys, not the specific message numbers.

**Fix:** Consolidate into a single `FakePosts` with a module attribute for `message_number` values, or add a comment on each module explaining why distinct fixtures are necessary so the intent is explicit.

---

### IN-04: Test file contains six nested `defmodule` blocks

**File:** `test/foglet_bbs/tui/screens/post_reader_test.exs:6-63`

**Issue:** The CLAUDE.md guideline states "Never nest multiple modules in the same file — causes cyclic dependency and compilation headaches." The test file defines six modules nested inside `PostReaderTest`: `FakePosts`, `FakeBoards`, `FakeThreads`, `FakeMarkdown`, `EmptyPosts`, and `FakePostsForLoad`. While nested modules in test files are the standard Elixir/ExUnit pattern for lightweight fakes and do not carry the same cyclic-dependency risk as production code, the guideline does not exempt test files.

**Fix:** If the CLAUDE.md guideline is intended to apply strictly to all files, move the fake modules to a shared `test/support/fakes/` file. If test files are considered exempt, annotate the CLAUDE.md guideline to make the exemption explicit. The current approach is standard ExUnit practice and carries no practical risk.

---

_Reviewed: 2026-04-22T16:45:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
