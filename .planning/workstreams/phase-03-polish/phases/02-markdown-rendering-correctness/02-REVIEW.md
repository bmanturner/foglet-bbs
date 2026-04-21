---
phase: 02-markdown-rendering-correctness
reviewed: 2026-04-20T00:00:00Z
depth: standard
files_reviewed: 6
files_reviewed_list:
  - lib/foglet_bbs/tui/widgets/post/markdown_body.ex
  - lib/foglet_bbs/tui/widgets/post/post_card.ex
  - lib/foglet_bbs/tui/screens/post_reader.ex
  - test/foglet_bbs/tui/widgets/post/markdown_body_test.exs
  - test/foglet_bbs/tui/widgets/post/post_card_test.exs
  - test/foglet_bbs/tui/screens/post_reader_test.exs
findings:
  critical: 0
  warning: 3
  info: 2
  total: 5
status: issues_found
---

# Phase 02: Code Review Report

**Reviewed:** 2026-04-20
**Depth:** standard
**Files Reviewed:** 6
**Status:** issues_found

## Summary

The markdown rendering pipeline is well-structured and clearly motivated by the RENDER-01 and D-06 bug history. `MarkdownBody` correctly groups tuple streams by newline separators into logical lines and maps style atoms to theme slots. `PostCard` delegates cleanly and handles nil body/user/inserted_at gracefully. The test suite is comprehensive.

Three warnings were found: a logic gap in render-path cache warming (the cache is never populated during `render/1`, only during key events), direct field access on a potentially struct-typed value in `scroll_post`, and a module defined inside a test block that can cause recompile/conflict issues. Two info items cover a minor defensive redundancy and a misleading fallback string.

## Warnings

### WR-01: Render cache is never warmed via `render/1` — re-parses markdown on every frame

**File:** `lib/foglet_bbs/tui/screens/post_reader.ex:66`

**Issue:** `render_post_content/5` reads from the cache with `ss.render_cache[{post.id, w}]` and falls back to `parse_body/2` on a miss, but it **never writes the result back to the cache**. The `warm_cache/4` helper is only called from `advance_post/2` (line 259) and `scroll_post/2` (line 300). On initial render before any keypress — and on every subsequent render when the key events haven't run yet — the cache is always empty and `parse_body` is called redundantly on every frame redraw. For long markdown bodies this means re-parsing on every terminal refresh cycle.

**Fix:** Either warm the cache from inside `render_post_content`, or call `warm_cache` from `load_posts/2` after posts are fetched. The simplest approach is to warm the cache in `render_post_content` and return the updated screen state so the caller can store it:

```elixir
# Option A: warm inline during render (requires threading ss through render path)
defp render_post_content(state, ss, theme, w, h) do
  posts = state.posts
  total = length(posts)
  idx = ss.selected_post_index

  if idx >= total do
    # ... unchanged
  else
    post = Enum.at(posts, idx)
    available_height = max(h - 10, 5)
    ss = warm_cache(ss, state, post, w)          # <-- add this
    tuples = ss.render_cache[{post.id, w}]

    PostCard.render_from_tuples(post, tuples, w, theme,
      index: idx,
      total: total,
      scroll_offset: ss.scroll_offset,
      max_lines: available_height
    )
  end
end
```

Note that if `render/1` is pure (returns only the view element, not state), the warmed `ss` would need to be surfaced via a side-channel or the cache-write moved to `load_posts`. The core issue to resolve is the uncached re-parse on every render call.

---

### WR-02: `post.body` accessed via dot syntax on a value that may be an Ecto struct

**File:** `lib/foglet_bbs/tui/screens/post_reader.ex:293`

**Issue:** `PostCard.body_line_count(post.body)` accesses `:body` via dot syntax. Per project CLAUDE.md guidelines, map access syntax (`changeset[:field]`) must not be used on structs, and struct field access must use the direct dot form. That rule applies in reverse too: dot access on an Ecto struct is correct, but `post` here comes from `Enum.at(posts, ...)` where `posts` is loaded via `posts_mod.list_posts/1`. If `Foglet.Posts.list_posts/1` returns `%Foglet.Posts.Post{}` Ecto structs (which is the expected production shape), then `post.body` is correct. However, `post` is typed as a plain map in the test helpers and the `@post_like` type in `PostCard` explicitly uses `optional(:body)`. If a post struct were ever to not have `:body` in its schema (e.g., a struct returned from a different query without the field selected), this would raise `KeyError` rather than returning `nil`.

The safer pattern consistent with the rest of `PostCard` is to use `Map.get(post, :body)`:

```elixir
# post_reader.ex:293 — safer access
total_lines = PostCard.body_line_count(Map.get(post, :body))
```

---

### WR-03: `defmodule EmptyPosts` defined inside a test block

**File:** `test/foglet_bbs/tui/screens/post_reader_test.exs:522-524`

**Issue:** A module is defined inline inside a `test` block:

```elixir
test "empty posts list leaves read_position unchanged (no crash)" do
  defmodule EmptyPosts do
    def list_posts(_tid), do: []
  end
  # ...
end
```

Module definitions inside test blocks are compiled globally at compile time, not lazily at runtime. This means the module is defined once regardless of how many times the test runs, which causes a `redefining module` warning in Elixir. Across test runs with `--failed` or in watch mode, this can surface as a noisy warning or, in some Elixir versions, a compilation error when running tests concurrently (`async: true`).

**Fix:** Move `EmptyPosts` to the module level alongside `FakePosts`, `FakeBoards`, and `FakeMarkdown`:

```elixir
defmodule EmptyPosts do
  def list_posts(_tid), do: []
end
```

## Info

### IN-01: Redundant `max(scroll_offset, 0)` in `window_lines/3`

**File:** `lib/foglet_bbs/tui/widgets/post/markdown_body.ex:140`

**Issue:** The `window_lines/3` clause for integer `max_lines` applies `max(scroll_offset, 0)` before `Enum.drop`, but `scroll_offset` is already clamped to `>= 0` by callers (`PostReader.scroll_post/2` uses `|> max(0)`). The guard on the clause also matches any integer `scroll_offset` including negative values, so a negative offset would be silently treated as 0 rather than being rejected. This is purely defensive redundancy — not a bug — but it slightly obscures intent.

**Fix:** Either add a `when scroll_offset >= 0` guard to the clause for clarity, or remove the `max/2` call and document that callers are responsible for clamping:

```elixir
defp window_lines(lines, scroll_offset, max_lines)
     when is_integer(max_lines) and max_lines > 0 and scroll_offset >= 0 do
  lines
  |> Enum.drop(scroll_offset)
  |> Enum.take(max_lines)
end
```

---

### IN-02: "By @unknown" fallback is misleading when both user and inserted_at are absent

**File:** `lib/foglet_bbs/tui/widgets/post/post_card.ex:137`

**Issue:** The wildcard arm of `author_line/1` returns `"By @unknown"` when both `handle` and `when_str` are nil:

```elixir
_ -> "By @unknown"
```

This case fires when `post.user` is nil (or has no `:handle`) AND `post.inserted_at` is nil. The string "By @unknown" implies there is an author whose handle is "unknown", which is misleading — the data is simply absent. A neutral string would be more accurate.

**Fix:**

```elixir
_ -> "(post details unavailable)"
```

---

_Reviewed: 2026-04-20_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
