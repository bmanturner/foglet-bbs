---
phase: 07-migrate-hand-rolled-ui-components-to-raxol-widgets
reviewed: 2026-04-21T00:00:00Z
depth: standard
files_reviewed: 9
files_reviewed_list:
  - lib/foglet_bbs/tui/app.ex
  - lib/foglet_bbs/tui/screens/post_reader.ex
  - lib/foglet_bbs/tui/widgets/modal.ex
  - lib/foglet_bbs/tui/widgets/post/markdown_body.ex
  - lib/foglet_bbs/tui/widgets/post/post_card.ex
  - test/foglet_bbs/tui/screens/post_reader_test.exs
  - test/foglet_bbs/tui/widgets/modal_test.exs
  - test/foglet_bbs/tui/widgets/post/markdown_body_test.exs
  - test/foglet_bbs/tui/widgets/post/post_card_test.exs
findings:
  critical: 0
  warning: 2
  info: 5
  total: 7
status: issues_found
---

# Phase 07: Code Review Report

**Reviewed:** 2026-04-21T00:00:00Z
**Depth:** standard
**Files Reviewed:** 9
**Status:** issues_found

## Summary

Phase 07 migrates hand-rolled TUI widgets (Modal, PostCard, MarkdownBody, PostReader scroll) to Raxol widget primitives while preserving Foglet module names (D-07 thin-adapter pattern). The migration is well-scoped and the decisions documented in `07-CONTEXT.md` (D-08 Modal keeps thin adapter, D-12 Viewport owns scroll, D-13 render_cache preserved, D-R1 Viewport children are flat lines) are implemented correctly. Tests exercise the scroll, cache, theme, and legacy-state migration paths thoroughly.

The code is clean overall — no critical bugs or security issues. Two warnings involve error-handling robustness around Viewport return shapes and a subtle rebind inside the render path. Five info-level items flag code duplication between PostReader and PostCard, unused parameters, and a minor contract inconsistency in `get_handle/1` between PostReader and PostComposer.

Run `mix precommit` per project conventions to confirm formatting, credo, and dialyzer pass cleanly.

## Warnings

### WR-01: Viewport.update/2 return-tuple match-assumption is fragile

**File:** `lib/foglet_bbs/tui/screens/post_reader.ex:83-84, 330, 346, 389-391`
**Issue:** Every `Viewport.update/2` call binds the result with a strict match on `{new_vp, []}`:

```elixir
{vp, []} = Viewport.update({:set_visible_height, available_height}, ss.viewport)
{vp, []} = Viewport.update({:set_children, body_lines}, vp)
# ...
{reset_vp, []} = Viewport.update({:scroll_to, 0}, ss.viewport)
# ...
{new_vp, []} = Viewport.update({:set_children, body_lines}, ss.viewport)
# ...
{new_vp, []} = Viewport.update({:set_visible_height, available_height}, ss.viewport)
{new_vp, []} = Viewport.update({:scroll_by, delta}, new_vp)
```

The vendored `Raxol.UI.Components.Display.Viewport.update/2` (`vendor/raxol/lib/raxol/ui/components/display/viewport.ex:73-137`) does return `{state, []}` today, but the `Raxol.UI.Components.Base.Component` behaviour contract defines commands as a list that *could* contain elements in future versions. If a Raxol upgrade ever makes Viewport emit any command (even a harmless log event), every render and every keypress in PostReader will raise `MatchError`, including the `render/1` hot path — turning a Raxol upgrade into a render-time crash.

Also note line 83-84 shadows the variable `vp` across two consecutive pattern-matched calls inside `render_post_content/5`, which is the one place this pattern runs every frame.

**Fix:** Discard the command list explicitly and bind only the state. Leaves intent clearer and survives a non-empty command list in future Raxol releases:

```elixir
# In render_post_content/5 (lines 83-84) — rename to avoid shadowing
{vp, _cmds} = Viewport.update({:set_visible_height, available_height}, ss.viewport)
{vp, _cmds} = Viewport.update({:set_children, body_lines}, vp)

# In warm_viewport/4 (line 330)
{new_vp, _cmds} = Viewport.update({:set_children, body_lines}, ss.viewport)

# In advance_post/2 (line 346)
{reset_vp, _cmds} = Viewport.update({:scroll_to, 0}, ss.viewport)

# In scroll_post/2 (lines 389-391)
{new_vp, _cmds} = Viewport.update({:set_visible_height, available_height}, ss.viewport)
{new_vp, _cmds} = Viewport.update({:scroll_by, delta}, new_vp)
```

If you want belt-and-suspenders safety for the runtime, consider a tiny helper:

```elixir
defp vp_update(msg, vp) do
  {new_vp, _cmds} = Viewport.update(msg, vp)
  new_vp
end
```

### WR-02: `handle_key/2` spec claims `:no_match` but `advance_post/2` / `scroll_post/2` never actually return `:no_match` when used via the `def handle_key` wrappers

**File:** `lib/foglet_bbs/tui/screens/post_reader.ex:93-106, 334-398`
**Issue:** The `@spec` declares `handle_key(map(), map()) :: {:update, map(), list()} | :no_match`. The helpers `advance_post/2` and `scroll_post/2` both return `:no_match` when `posts == []` or when the currently-selected post is `nil`. That return value then propagates up through the `handle_key(%{key: :char, char: c}, state) when c in ["j", "J"]` clauses unchanged.

Upstream in `TUI.App.do_update({:key, key_event}, state)` (`lib/foglet_bbs/tui/app.ex:339-350`), the handler matches:

```elixir
case screen_module.handle_key(key_event, state) do
  {:update, new_state, commands} -> ...
  :no_match -> global_key_handler(key_event, state)
end
```

A `:no_match` return will route the user's `j`/`k`/`n`/`p`/`space` to the global key handler. In `global_key_handler` (app.ex:697), unknown keys silently return `{state, []}`. Net effect: in the (rare but reachable) state where `state.posts == nil` but `state.screen_state[:post_reader]` is present — for example, immediately after `{:load_posts, thread_id}` fires a task but before `{:posts_loaded, posts}` lands — pressing `n`/`j`/`k`/`p` will escape the PostReader's own handler. This is fine for `n`/`p` (nothing to advance to) but means space-as-page-down (line 95) and page_down (line 96) also silently no-op instead of, say, showing a "Loading..." cue.

Reviewing `render_post_content/5:50-55` confirms the loading path *does* render "Loading posts..." — so the user sees the message. But the key dispatch still quietly drops the keypress instead of being explicitly absorbed.

**Fix:** Either (a) return `{:update, state, []}` from the empty-posts branch to explicitly absorb the key while loading, or (b) document the contract — `:no_match` on empty posts is intentional so global handlers (e.g., a future `?` help key) still work. Option (a) is safer because it prevents future global handlers from acting on PostReader-intended keys during loading:

```elixir
defp advance_post(state, _delta) when is_nil(state.posts) or state.posts == [] do
  {:update, state, []}
end

defp advance_post(state, delta) do
  # ... existing body ...
end

# Same pattern for scroll_post/2.
```

Keep the `:no_match` return reserved for keys this screen genuinely doesn't handle (which is what the `def handle_key(_key, _state), do: :no_match` clause on line 142 already does correctly).

## Info

### IN-01: `author_line/1`, `get_handle/1`, `get_time_ago/1` duplicated between PostReader and PostCard

**File:** `lib/foglet_bbs/tui/screens/post_reader.ex:418-440` and `lib/foglet_bbs/tui/widgets/post/post_card.ex:156-178`
**Issue:** The PostReader screen reimplements `author_line/1`, `get_handle/1`, and `get_time_ago/1` privately (post_reader.ex:418-440), even though the exact same three functions exist on PostCard (post_card.ex:156-178). The PostReader comment at line 415 says the duplication is intentional "to avoid broadening PostCard's public surface for a single caller" — but PostReader is the only consumer of PostCard anyway, and the duplication means a future format change (e.g., showing a timezone, abbreviating long handles) has to be made in two places.

PostReader also still uses the header builder inline (post_reader.ex:72-74) instead of calling `PostCard.render_from_tuples/5` — that call path uses the non-scrolling portion but PostCard's `assemble_card/4` already builds the same three lines. The current design ends up with PostCard owning the full card render and PostReader owning a parallel header render, which is the worst of both worlds for this function trio.

**Fix:** Promote `author_line/1` (and its private helpers) to a public `PostCard.author_line/1` — it's a pure formatter with no side effects. Then delete the three duplicates from post_reader.ex and call `PostCard.author_line(post)` on line 73. Four clauses for `get_handle`/`get_time_ago` become one call site each:

```elixir
# post_card.ex — promote to @doc false public function
@doc false
@spec author_line(post_like()) :: String.t()
def author_line(post) do
  handle = get_handle(post)
  when_str = get_time_ago(post)
  # ... existing body ...
end

# post_reader.ex line 73:
header_line_2 = text(PostCard.author_line(post), fg: theme.dim.fg)
```

### IN-02: `get_handle/1` contracts diverge across three modules

**File:** `lib/foglet_bbs/tui/widgets/post/post_card.ex:168-169`, `lib/foglet_bbs/tui/screens/post_reader.ex:430-431`, `lib/foglet_bbs/tui/screens/post_composer.ex:230-231`
**Issue:** Three private implementations of `get_handle/1` with different fallback behavior:

- `PostCard.get_handle/1` — returns `nil` on missing/blank handle, guard `is_binary(h) and h != ""`.
- `PostReader.get_handle/1` — identical to PostCard (guard + `nil` fallback).
- `PostComposer.get_handle/1` — returns the string `"unknown"` on missing handle, *no empty-string guard*.

The PostComposer version means a user with an empty-string handle (which is allowed by the guard-less pattern match `%{user: %{handle: h}}`) will render as `"@"` — a visible UI bug if that path is ever reached. The `User` schema presumably disallows empty handles, but that's a schema invariant, not a widget invariant.

**Fix:** Consolidate on the stricter PostCard version (exported via IN-01's fix) and have PostComposer call it, substituting `"unknown"` at the call site when the result is `nil`:

```elixir
# post_composer.ex line 42:
text("Replying to @#{PostCard.author_handle_or(ss.reply_to, "unknown")}:", fg: theme.dim.fg),
```

Or inline:

```elixir
defp display_handle(post), do: PostCard.get_handle(post) || "unknown"
```

This removes the divergent empty-string semantics.

### IN-03: Dead parameters `_w` / `_h` in `render_post_content/5` empty-posts clause

**File:** `lib/foglet_bbs/tui/screens/post_reader.ex:50-55`
**Issue:** The first `render_post_content/5` clause takes `_state, _ss, theme, _w, _h` — `state` and `ss` are unused on that branch (only `theme` is needed). The clause exists for the loading-posts case so the underscore prefixes are correct, but the arity-5 callsite passes them unconditionally. This is fine as-is, but worth noting that a simpler arity-1 helper `render_loading(theme)` would make the empty-posts branch self-evident without the four underscored parameters:

```elixir
defp render_loading(theme) do
  column style: %{gap: 0} do
    [text("Loading posts...", fg: theme.dim.fg)]
  end
end

defp render_post_content(%{posts: posts}, _ss, theme, _w, _h) when posts in [[], nil] do
  render_loading(theme)
end
```

### IN-04: `render_body_lines/5` ignores the `post` parameter

**File:** `lib/foglet_bbs/tui/widgets/post/post_card.ex:110-114`
**Issue:** `render_body_lines/5` accepts `post` and explicitly discards it with `_ = post`. The function then delegates entirely to `MarkdownBody.render_tuples_as_lines(tuples, width, theme, body_opts(opts))`. The `post` argument is only part of the signature for "parity with `render_from_tuples/5`" (per the `@doc`), but since tuples are already parsed at this point, the post is truly unused — no header, no author line, no body-caching.

This is a minor API smell — it asks every caller (just PostReader today) to pass an argument that does nothing. A caller could plausibly pass a stale or wrong post and it would still work.

**Fix:** Drop the parameter. Update PostReader's one call site at post_reader.ex:77 from `PostCard.render_body_lines(post, tuples, w, theme)` to `PostCard.render_body_lines(tuples, w, theme)`. The `@spec` and signature become:

```elixir
@spec render_body_lines([MarkdownBody.tuple_entry()], pos_integer(), Theme.t(), keyword()) :: [any()]
def render_body_lines(tuples, width, %Theme{} = theme, opts \\ [])
    when is_list(tuples) and is_integer(width) and width > 0 do
  MarkdownBody.render_tuples_as_lines(tuples, width, theme, body_opts(opts))
end
```

Tests in `post_card_test.exs:161, 169, 178, 187, 199, 202` update mechanically.

### IN-05: `_ = opts` pattern noise in `render_tuples_as_lines/4`

**File:** `lib/foglet_bbs/tui/widgets/post/markdown_body.ex:110-117`
**Issue:** `render_tuples_as_lines/4` documents that `opts` is accepted but ignored (Viewport handles windowing), then uses `_ = opts` to silence the compiler. This works but is less idiomatic than just naming the param with an underscore prefix:

```elixir
@spec render_tuples_as_lines([tuple_entry()], pos_integer(), Theme.t(), keyword()) :: [any()]
def render_tuples_as_lines(tuples, width, %Theme{} = theme, _opts \\ [])
    when is_list(tuples) and is_integer(width) and width > 0 do
  tuples
  |> group_by_newline()
  |> Enum.map(fn group -> line_group_to_row(group, theme) end)
end
```

Removes one line of noise and the `_ = opts` idiom, and conveys intent (the parameter is deliberately ignored) in the signature rather than the body.

---

_Reviewed: 2026-04-21T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
