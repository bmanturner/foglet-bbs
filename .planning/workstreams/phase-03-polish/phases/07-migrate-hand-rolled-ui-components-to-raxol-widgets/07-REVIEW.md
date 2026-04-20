---
phase: 07-migrate-hand-rolled-ui-components-to-raxol-widgets
reviewed: 2026-04-20T00:00:00Z
depth: standard
files_reviewed: 9
files_reviewed_list:
  - lib/foglet_bbs/tui/widgets/modal.ex
  - lib/foglet_bbs/tui/app.ex
  - test/foglet_bbs/tui/widgets/modal_test.exs
  - lib/foglet_bbs/tui/widgets/post/markdown_body.ex
  - lib/foglet_bbs/tui/widgets/post/post_card.ex
  - test/foglet_bbs/tui/widgets/post/markdown_body_test.exs
  - test/foglet_bbs/tui/widgets/post/post_card_test.exs
  - lib/foglet_bbs/tui/screens/post_reader.ex
  - test/foglet_bbs/tui/screens/post_reader_test.exs
findings:
  critical: 0
  warning: 3
  info: 5
  total: 8
status: issues_found
---

# Phase 07: Code Review Report

**Reviewed:** 2026-04-20T00:00:00Z
**Depth:** standard
**Files Reviewed:** 9
**Status:** issues_found

## Summary

Phase 07 migrates three hand-rolled UI surfaces onto Raxol widgets: a theme-aware
Modal adapter (07-01), additive line-renderers on the post widgets for Viewport
consumption (07-02), and a PostReader scroll state replacement built on
`Raxol.UI.Components.Display.Viewport` (07-03).

Overall the implementation is solid and well-tested. The code correctly delegates
clamping to the Viewport, threads theme slots through every branch, and preserves
backward-compatible screen_state migration via `get_screen_state/1`. No critical
correctness or security issues were found. All pattern matches are on well-known
shapes, no user input reaches `String.to_atom`, and no raw SQL / shell / eval
vectors exist in these files.

Three warnings are worth addressing before calling the phase done:

1. A real state/render divergence in `PostReader.render_post_content/5` where
   the render-time viewport clamp is silently discarded (WR-01).
2. Weak `assert _ = expr` assertions in Modal and PostReader tests that fail
   to verify the stated contract (WR-02).
3. An ordering fragility in `scroll_post/2` where `:set_visible_height` is
   applied after `:set_children`, making the intermediate clamp dependent on
   the default visible_height (WR-03).

Info items cover minor duplication, magic numbers, and a redundant
`Viewport.init/1` call on every `get_screen_state/1` invocation.

## Warnings

### WR-01: Render-time viewport clamp is discarded; state can drift from rendered scroll position

**File:** `lib/foglet_bbs/tui/screens/post_reader.ex:83-85`
**Issue:**
`render_post_content/5` applies `{:set_visible_height, available_height}` and
`{:set_children, body_lines}` to a local `vp` but never writes the result back
to `state.screen_state[:post_reader].viewport`. The Viewport `update/2` clauses
all re-clamp `scroll_top` against the new bounds (see
`vendor/raxol/lib/raxol/ui/components/display/viewport.ex:73-104`). If the terminal
resizes between keypresses, or if content_height differs from what warm_viewport
captured, the rendered scroll_top may be clamped to a smaller value than
`ss.viewport.scroll_top`. The next j/k press will reconcile (because
`scroll_post/2` re-applies both updates before `:scroll_by`), but until then the
visible content and the stored state disagree. This is benign in practice today
because the content does not change on resize, but the invariant is not obvious
and is easy to break.

**Fix:** Either (a) document that render-time clamping is intentionally
ephemeral and guard against drift with an equality assertion in tests, or
(b) write the clamped viewport back into `screen_state` by making `render/1`
return a `{view, updated_state}` pair — Raxol does not currently support this,
so option (a) is preferred. At minimum, add an inline comment next to the
discarded `_ = vp` binding spelling out why the clamp is discarded and what
downstream flow (next j/k press) makes it self-correcting. A regression test
that resizes between renders and asserts the rendered scroll_top cannot exceed
`max(0, content_height - visible_height)` would lock the invariant down.

```elixir
# lib/foglet_bbs/tui/screens/post_reader.ex:79-85
# Wire visible_height and children for this frame. render_post_content
# is a read-only function — the Viewport state built here is transient,
# not written back into screen_state. State-writing happens in
# scroll_post / advance_post / load_posts via warm_viewport.
#
# INVARIANT: If terminal height shrinks between renders, the render-time
# set_visible_height clamp may temporarily show a smaller scroll_top than
# state holds. The next j/k press calls scroll_post/2 which re-applies
# both updates and writes the clamped result back, reconciling state.
{vp, []} = Viewport.update({:set_visible_height, available_height}, ss.viewport)
{vp, []} = Viewport.update({:set_children, body_lines}, vp)
body_rendered = Viewport.render(vp, %{})
```

### WR-02: `assert _ = expr` is a no-op assertion — Modal and PostReader tests do not verify non-nil results

**File:** `test/foglet_bbs/tui/widgets/modal_test.exs:32, 36, 40, 44`
**File:** `test/foglet_bbs/tui/screens/post_reader_test.exs:97, 101`
**Issue:**
The pattern `assert _ = Modal.render(...)` binds the result to `_` and asserts
the match succeeded. Since `_` matches anything (including `nil`), this is
functionally equivalent to just calling the function — it only guards against
exceptions, not the stated "returns a non-nil view element" contract. The
`MarkdownBodyTest` and `PostCardTest` files use `refute is_nil(result)` for
exactly these assertions; Modal and PostReader should match that style.

Test names like `"returns a non-nil view element for :info"` and `"render/1
with posts loaded does not crash"` (the latter is at least accurate for the
no-op assertion, but the former is misleading).

**Fix:**
```elixir
# test/foglet_bbs/tui/widgets/modal_test.exs:30-50
describe "render/2 (Phase 7 thin adapter)" do
  test "returns a non-nil view element for :info" do
    result = Modal.render(%{type: :info, message: "Hello"}, theme())
    refute is_nil(result)
  end

  test "returns a non-nil view element for :error" do
    result = Modal.render(%{type: :error, message: "Oh no"}, theme())
    refute is_nil(result)
  end

  test "returns a non-nil view element for :confirm" do
    result = Modal.render(%{type: :confirm, message: "Delete?"}, theme())
    refute is_nil(result)
  end

  test "defaults type to :info when omitted" do
    result = Modal.render(%{message: "No type given"}, theme())
    refute is_nil(result)
  end

  # ...
end
```

And in `post_reader_test.exs`:

```elixir
test "render/1 with posts loaded does not crash", %{state: state} do
  {s, _} = PostReader.load_posts(state, "t1")
  result = PostReader.render(s)
  refute is_nil(result)
end

test "render/1 with no posts shows loading message", %{state: state} do
  result = PostReader.render(state)
  refute is_nil(result)
  # Ideally also: assert flatten_text(result) =~ "Loading posts..."
end
```

### WR-03: `scroll_post/2` applies `:set_visible_height` AFTER `:set_children`, leaking the default `visible_height: 10` into the intermediate clamp

**File:** `lib/foglet_bbs/tui/screens/post_reader.ex:386-391`
**Issue:**
The sequence inside `scroll_post/2` is:

```elixir
ss = warm_cache(ss, state, post, w)
ss = warm_viewport(ss, state, post, w)      # calls set_children with old visible_height
{new_vp, []} = Viewport.update({:set_visible_height, available_height}, ss.viewport)
{new_vp, []} = Viewport.update({:scroll_by, delta}, new_vp)
```

`warm_viewport` calls `{:set_children, body_lines}` which re-clamps `scroll_top`
against `state.visible_height` (defaults to `10` from `Viewport.init/1` on first
call, then whatever was last set). If `available_height != 10` and the post has
between `available_height` and `10` lines, the `set_children` clamp will use the
wrong bound, clamp to 0 (or a stale value), and then `set_visible_height`
re-clamps. The final `scroll_by(delta)` then operates on a potentially-off
base. In practice this does not cause visible bugs because the immediately-following
`set_visible_height` + `scroll_by` both re-clamp, and a 1-line delta cannot
produce a scroll_top greater than the correct max_scroll. But the ordering is
fragile: a future change that introduces a larger delta (e.g. `:scroll_by, 10`
for page-down) combined with a shrunken terminal could produce surprising
intermediate states.

**Fix:** Apply `:set_visible_height` before `:set_children`, or bundle them into a
single `:update_props` call which clamps once against the final bounds:

```elixir
# lib/foglet_bbs/tui/screens/post_reader.ex:386-391
ss = warm_cache(ss, state, post, w)

# Apply visible_height first so set_children's clamp uses the correct bound.
{vp, []} = Viewport.update({:set_visible_height, available_height}, ss.viewport)
ss = %{ss | viewport: vp}
ss = warm_viewport(ss, state, post, w)  # now set_children clamps against available_height

{new_vp, []} = Viewport.update({:scroll_by, delta}, ss.viewport)
ss = %{ss | viewport: new_vp}
```

Alternatively, collapse into a single `:update_props` call which clamps once at
the end (see `Viewport.update({:update_props, props}, state)` at
`vendor/raxol/lib/raxol/ui/components/display/viewport.ex:106-135`).

Regardless of the fix chosen, add a test that scrolls on a post whose line count
is between `Viewport.init` default (10) and `available_height` after resize, to
lock in the intended behavior.

## Info

### IN-01: `author_line/1`, `get_handle/1`, `get_time_ago/1` are duplicated between PostCard and PostReader

**File:** `lib/foglet_bbs/tui/screens/post_reader.ex:418-440`
**File:** `lib/foglet_bbs/tui/widgets/post/post_card.ex:156-178`
**Issue:**
The identical three helper functions appear in both modules. PostReader's comment
acknowledges this is intentional ("Kept private here to avoid broadening
PostCard's public surface for a single caller.") but the maintenance burden is
real: a bug fix in one will drift from the other. The underlying motive — keep
PostCard's API small — is reasonable, but a one-liner `@doc false` function on
PostCard or a shared `Foglet.TUI.Widgets.Post.Header` module would cost nothing
and remove the duplication.

**Fix:** Extract to a shared private module or expose `PostCard.author_line/1`
with `@doc false`. If kept duplicated, add a comment pointing each copy at the
other and a test that exercises both paths with the same inputs and asserts
identical output to catch drift.

### IN-02: Magic number `10` for chrome overhead appears twice in PostReader

**File:** `lib/foglet_bbs/tui/screens/post_reader.ex:68, 381`
**Issue:**
`available_height = max(h - 10, 5)` appears in both `render_post_content/5` and
`scroll_post/2`. The `10` represents the chrome overhead (ScreenFrame border
top+bottom, status bar, key bar, post header 2 lines + divider). If that
overhead changes — e.g. ScreenFrame adds a title bar — one call site could be
updated without the other.

**Fix:** Extract to a module attribute:

```elixir
# The ScreenFrame chrome + post header + divider consumes ~10 rows from
# the terminal height. Adjust if ScreenFrame layout changes.
@chrome_overhead 10
@min_body_height 5

defp available_body_height(h), do: max(h - @chrome_overhead, @min_body_height)
```

### IN-03: `Viewport.init/1` runs on every `get_screen_state/1` call

**File:** `lib/foglet_bbs/tui/screens/post_reader.ex:236-263`
**Issue:**
`default_screen_state/0` calls `Viewport.init/1` unconditionally, and
`get_screen_state/1` calls `default_screen_state/0` unconditionally before
merging. In the steady state (after load_posts), the merge discards the fresh
viewport and keeps `existing.viewport`, so the `Viewport.init/1` result is
thrown away. `render/1` calls `get_screen_state/1`, so this runs on every frame.

`Viewport.init/1` is cheap (one map construction, one call to
`:erlang.unique_integer/1`), but the wasted unique integer allocation is an
unnecessary side effect on the hot path.

**Fix:** Either (a) memoize `default_screen_state/0` via module attribute after
removing the unique-integer id (pin it to `"post_reader_vp"` which is already
hardcoded), or (b) only call `default_screen_state/0` when `existing == %{}`:

```elixir
defp get_screen_state(state) do
  case get_in(state.screen_state, [:post_reader]) do
    nil ->
      default_screen_state()

    existing ->
      existing
      |> Map.drop([:scroll_offset])
      |> ensure_viewport()
  end
end

defp ensure_viewport(%{viewport: _} = ss), do: Map.put_new(ss, :render_cache, %{})
                                               |> Map.put_new(:selected_post_index, 0)

defp ensure_viewport(ss) do
  {:ok, vp} = Viewport.init(%{id: "post_reader_vp", children: [],
                              visible_height: 10, scroll_top: 0, show_scrollbar: false})
  ss |> Map.put(:viewport, vp)
     |> Map.put_new(:render_cache, %{})
     |> Map.put_new(:selected_post_index, 0)
end
```

### IN-04: `render_tuples_as_lines/4` accepts but ignores `opts` — the `_ = opts` trick is subtle

**File:** `lib/foglet_bbs/tui/widgets/post/markdown_body.ex:110-117`
**Issue:**
The function signature takes `opts \\ []` for "signature parity" with
`render_tuples/4`, but the body explicitly ignores it with `_ = opts`. This is
fine but the `_ = opts` pattern is easy to miss when reading the function
quickly, and tests already confirm the opts are ignored. A more explicit
approach: drop the default and use `_opts` in the head.

**Fix:**
```elixir
@spec render_tuples_as_lines([tuple_entry()], pos_integer(), Theme.t(), keyword()) :: [any()]
def render_tuples_as_lines(tuples, width, %Theme{} = theme, _opts \\ [])
    when is_list(tuples) and is_integer(width) and width > 0 do
  tuples
  |> group_by_newline()
  |> Enum.map(fn group -> line_group_to_row(group, theme) end)
end
```

This accomplishes the same thing with one fewer line and makes the "ignored"
status visible in the signature.

### IN-05: `render_body_lines/5` post parameter is also unused (`_ = post`)

**File:** `lib/foglet_bbs/tui/widgets/post/post_card.ex:110-114`
**Issue:**
Same pattern as IN-04 — `post` is bound then ignored via `_ = post`. Same fix:
rename to `_post` in the head. The `@spec post_like()` constraint still
provides type safety via Dialyzer if the caller passes a truly wrong shape
elsewhere.

**Fix:**
```elixir
@spec render_body_lines(
        post_like(),
        [MarkdownBody.tuple_entry()],
        pos_integer(),
        Theme.t(),
        keyword()
      ) :: [any()]
def render_body_lines(_post, tuples, width, %Theme{} = theme, opts \\ [])
    when is_list(tuples) and is_integer(width) and width > 0 do
  MarkdownBody.render_tuples_as_lines(tuples, width, theme, body_opts(opts))
end
```

---

_Reviewed: 2026-04-20T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
