# Phase 44: PostReader And Content Query Hardening - Pattern Map

## PATTERN MAPPING COMPLETE

## Target Files

| File | Role | Closest existing analog |
|------|------|-------------------------|
| `lib/foglet_bbs/posts.ex` | Add tombstone-capable bounded reader-window query | Current `Foglet.Posts.list_posts/1`; `Foglet.Threads.list_threads/1,2` query style |
| `lib/foglet_bbs/posts/reader_window.ex` | Optional small result struct for window metadata | Existing context structs such as `Foglet.Threads.ThreadEntry` |
| `lib/foglet_bbs/tui/screens/post_reader/state.ex` | Add bounded-window metadata beside active `posts` | Current `PostReader.State` local reducer state shape |
| `lib/foglet_bbs/tui/screens/post_reader.ex` | Switch load, navigation, and thread-activity effects to bounded windows | Current `Effect.task(:load_posts, :post_reader, fun)` and `advance_local_post/3` reducer paths |
| `lib/foglet_bbs/tui/screens/post_reader/render.ex` | Active pure render boundary for purity guard | Phase 43 render extraction pattern |
| `lib/foglet_bbs/query_helpers.ex` | Shared deleted-row helper boundary if needed | Existing `not_deleted/1` and `active_boards/1` helpers |
| `test/foglet_bbs/tui/screens/post_reader_test.exs` | Fake-domain bounded-state, navigation, cache, render-purity tests | Existing fake domain modules and `PostReader.update/3` structural assertions |
| `test/foglet_bbs/posts/posts_test.exs` | Reader-window domain query tests | Current Board Server-backed post creation and tombstone tests |
| `test/foglet_bbs/threads/threads_test.exs` | Thread list soft-delete policy tests | Current `list_threads/1,2` unread annotation tests |
| `test/foglet_bbs/boards/boards_test.exs` | Board directory/unread soft-delete summary tests | Current `board_directory_for/1` and `unread_counts/1` tests |

## Existing Boundary Pattern

PostReader already follows the reducer/render split created by Phase 43:

```elixir
@impl true
@spec update(term(), State.t(), Context.t()) :: {State.t(), [Effect.t()]}
def update(message, %State{} = state, %Context{} = context) do
  ...
end

@impl true
@spec render(State.t(), Context.t()) :: any()
def render(%State{} = state, %Context{} = context), do: Render.render(state, context)
```

Keep domain querying in `Foglet.Posts`, reducer effects and state mutation in
`Foglet.TUI.Screens.PostReader`, and rendering in
`Foglet.TUI.Screens.PostReader.Render`.

## Bounded Query Pattern

Use a message-number cursor scoped to the thread. Do not use offset paging or
screen-local slicing of a full list.

```elixir
from p in Post,
  where: p.thread_id == ^thread_id,
  where: p.message_number > ^after_message_number,
  order_by: [asc: p.message_number],
  limit: ^(limit + 1),
  preload: [:user]
```

For `:before` and `:last` modes, a descending query may be used internally, but
the returned `posts` must be normalized to ascending reader order before
PostReader stores them.

## Result Shape Pattern

Either a documented map or a small struct is acceptable. The plan recommends a
struct for grep-friendly metadata:

```elixir
%Foglet.Posts.ReaderWindow{
  posts: posts,
  first_message_number: first_number,
  last_message_number: last_number,
  has_previous?: has_previous?,
  has_next?: has_next?,
  direction: :initial
}
```

Keep `%PostReader.State{}.posts` as the active bounded window and add metadata
beside it. Do not replace `posts` with an unrelated collection abstraction.

## Reducer Effect Pattern

Current code emits:

```elixir
Effect.task(:load_posts, :post_reader, fn -> posts_mod.list_posts(thread_id) end)
```

Phase 44 should emit a bounded operation such as:

```elixir
Effect.task(:load_posts_window, :post_reader, fn ->
  posts_mod.list_reader_window(thread_id, direction: :initial, limit: @reader_window_size)
end)
```

Task result handling should accept the window result, assign `window.posts` to
`%State{}.posts`, assign metadata fields, seed pending read position for the
selected post, and warm cache/viewport at the current terminal width.

## Cache Eviction Pattern

Keep cache writes in reducer/state plumbing:

```elixir
defp cache_for_current_width(render_cache, width) do
  render_cache
  |> Enum.reject(fn {{_post_id, cached_width}, _tuples} -> cached_width != width end)
  |> Map.new()
end
```

Call this before inserting `{post.id, width}` in `warm_cache/4`. Render fallback
may parse for display, but must not write state.

## Test Patterns

Prefer structural assertions:

- fake posts module raises on `list_posts/1` for large-thread tests;
- fake posts module sends `{:reader_window_requested, opts}` to the test process;
- assert `length(loaded.posts) < 1000`;
- assert selected post IDs and pending read-pointer metadata after boundary navigation;
- assert render-cache keys have `elem(key, 1) == current_width`;
- assert source guard scans `post_reader/render.ex` as the active render boundary.

Avoid pure assertions that only check for static rendered copy.

## Verification Greps

```bash
rtk rg -n "def list_reader_window|defmodule Foglet\\.Posts\\.ReaderWindow" lib/foglet_bbs/posts.ex lib/foglet_bbs/posts
rtk rg -n "list_posts\\(thread_id\\)" lib/foglet_bbs/tui/screens/post_reader.ex
rtk rg -n "list_reader_window|load_posts_window|has_previous\\?|has_next\\?" lib/foglet_bbs/tui/screens/post_reader.ex lib/foglet_bbs/tui/screens/post_reader/state.ex
rtk rg -n "post_reader/render\\.ex|forbidden_patterns" test/foglet_bbs/tui/screens/post_reader_test.exs
rtk rg -n "not_deleted\\(\\)|is_nil\\(.*deleted_at" lib/foglet_bbs/threads.ex lib/foglet_bbs/boards.ex lib/foglet_bbs/query_helpers.ex
```
