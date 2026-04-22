---
phase: 09-postreader
reviewed: 2026-04-22T14:18:02Z
depth: standard
files_reviewed: 2
files_reviewed_list:
  - lib/foglet_bbs/tui/screens/post_reader.ex
  - test/foglet_bbs/tui/screens/post_reader_test.exs
findings:
  critical: 0
  warning: 3
  info: 3
  total: 6
status: issues_found
---

# Phase 09: Code Review Report — PostReader

**Reviewed:** 2026-04-22T14:18:02Z
**Depth:** standard
**Files Reviewed:** 2
**Status:** issues_found

## Summary

Both files are well-structured and thoroughly documented. The screen-state lifecycle (load, navigate, scroll, flush, exit) is clearly separated, the render-purity boundary is enforced at both the code and test levels, and load-absorb semantics are explicitly tested. No security issues or data-loss paths were found.

Three warnings stand out: the fire-and-forget pattern in `flush_read_pointers/2` silently discards domain errors; the `flush_board_pointer/2` clause can fall through to `nil` without making its intent explicit; and `build_flush_context/2` silently passes a `nil` thread_id into the flush context when `state.current_thread` is nil, which causes `Map.get/2` to silently return the wrong value. Three info items cover dead code in `p2_state/1`, a missing `markdown` domain key in several test states, and a potential misleading path in the purity-guard test's `defp` scope-tracking regex.

---

## Warnings

### WR-01: `flush_read_pointers/2` silently swallows domain errors

**File:** `lib/foglet_bbs/tui/screens/post_reader.ex:277-278`

**Issue:** The return values of `flush_board_pointer/3` and `flush_thread_pointer/3` are discarded at lines 277–278. When the domain module returns `{:error, reason}` (e.g. DB unavailability, auth failure), `flush_read_pointers/2` still returns `{state_with_cleared_pointer, []}`, meaning the local read-pointer is cleared even though the flush never reached the DB. The caller (`TUI.App.do_update`) has no way to know the flush failed.

**Fix:** Capture and propagate errors, or at minimum log the failure and retain the local pointer:

```elixir
board_result  = flush_board_pointer(boards_mod, user_id, flush_ctx)
thread_result = flush_thread_pointer(threads_mod, user_id, flush_ctx)

if board_result == :skip or match?({:ok, _}, board_result) do
  new_rp = clear_read_position(state.read_position, flush_ctx[:thread_id])
  {%{state | read_position: new_rp}, []}
else
  # Retain pointer so the next flush can retry.
  require Logger
  Logger.warning("flush_read_pointers: board flush failed: #{inspect(board_result)}")
  {state, []}
end
```

At a minimum, wrap the calls in `_ =` and add a `Logger.warning` so failures are observable in production logs.

---

### WR-02: `flush_board_pointer/2` returns `nil` (not `:skip`) when `board_id` is absent

**File:** `lib/foglet_bbs/tui/screens/post_reader.ex:288-295`

**Issue:** The second clause of `flush_board_pointer/3` uses a bare `if` without an `else` branch (lines 289–295). When `ctx[:board_id]` is falsy the function returns `nil`, not `:skip` as the nil-`user_id` guard clause does. This is an inconsistency: callers that inspect the return value (e.g. in a future retry path or in WR-01's fix above) must handle both `:skip` and `nil` as "nothing happened." The same pattern applies to `flush_thread_pointer/3` at lines 300–303.

**Fix:** Add an explicit `else :skip` to both `if` expressions:

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

### WR-03: `build_flush_context/2` uses `nil` as a `Map.get/2` key when `current_thread` is absent

**File:** `lib/foglet_bbs/tui/screens/post_reader.ex:488-501`

**Issue:** Lines 490–492:

```elixir
thread_id = thread && thread.id
pos = Map.get(state.read_position, thread_id) || %{}
```

When `state.current_thread` is nil, `thread_id` is `nil` and `Map.get(state.read_position, nil)` silently returns whatever is stored under the `nil` key (defaulting to `%{}`). This is unlikely in practice (Q can only be pressed when the screen is active, which requires a current thread) but is invisible and could produce a flush context with incorrect `last_read_post_id`/`last_read_message_number` if any code path accidentally writes to `read_position[nil]`.

**Fix:** Guard the map lookup explicitly:

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

### IN-01: `p2_state/1` does not inject `domain` into `session_context` — several tests rely on real `Foglet.Markdown`

**File:** `test/foglet_bbs/tui/screens/post_reader_test.exs:303`

**Issue:** The base `p2_state/1` fixture sets `session_context: %{theme: theme()}` with no `domain` key. `parse_body/2` in the source uses `Domain.get(sc, :markdown)` and falls back to `Foglet.Markdown` when the key is absent. This means any `p2_state`-based test that calls `render/1` or navigates is silently exercising the real `Foglet.Markdown` module rather than a controlled fake. If that module changes contract or is unavailable, unrelated tests will break without a clear signal.

This is not a test-reliability bug today, but it means the tests are not fully isolated from the production Markdown module.

**Fix:** Add a `domain` key to the `p2_state/1` base fixture pointing to `FakeMarkdown` (already defined in the test module), or explicitly override it in the tests that call `render/1`:

```elixir
session_context: %{theme: theme(), domain: %{markdown: FakeMarkdown}},
```

---

### IN-02: Render-purity test scope regex can misclassify `defp render_loading/1`

**File:** `test/foglet_bbs/tui/screens/post_reader_test.exs:250-261`

**Issue:** The regex used to detect "entering a non-render defp" is:

```elixir
String.match?(line, ~r/^\s+defp [^r]|^\s+defp r[^e]|^\s+def /)
```

This matches `defp r<not-e>` to exit render scope, but `defp render_loading` starts with `defp render_l` — `r` followed by `e` — so the guard correctly keeps `render_loading` in-scope. However `defp render_post_content` triggers a fresh "entering a render helper" match at line 249 every time it appears, resetting the accumulation. The logic is subtly non-monotonic: it works for the current file but could give false negatives if two `defp render_*` functions are back-to-back (the second one restarts accumulation rather than continuing it). It also does not account for `def ` (public) render functions.

**Fix:** A simpler and more robust approach is to parse render-block content with a `defp render_` start sentinel and an `^  def ` (any `def`/`defp` at the same indent level) exit sentinel, or use a two-pass approach: collect all `defp render_*` source ranges by line number, then check forbidden patterns only in those ranges.

This is an info-level note because the current test correctly catches violations in the existing source.

---

### IN-03: `FakePosts` and `FakePostsForLoad` are redundant — two modules with identical structure

**File:** `test/foglet_bbs/tui/screens/post_reader_test.exs:6-63`

**Issue:** `FakePosts` (lines 6–25) and `FakePostsForLoad` (lines 44–63) both implement `list_posts/1` returning a two-element list with structurally identical post maps. The only difference is that `FakePostsForLoad` uses `DateTime.utc_now()` for `inserted_at` and has `message_number: 5/6` instead of `1/2`. The `setup` block uses `FakePosts` while the `load_posts` describe blocks use `FakePostsForLoad`, but several tests in those blocks only care about `length/1` or `read_position` keys — they do not depend on the specific `message_number` values from `FakePostsForLoad`.

**Fix:** Consolidate into a single `FakePosts` module and parameterize `message_number` via a module attribute, or keep them separate but add a comment explaining why distinct fixtures are necessary. The duplication is minor but makes it harder to reason about which fixture a test is relying on.

---

_Reviewed: 2026-04-22T14:18:02Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
