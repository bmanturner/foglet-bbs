---
phase: 01-widget-foundation-theme-screen-chrome
reviewed: 2026-04-20T00:00:00Z
depth: standard
files_reviewed: 17
files_reviewed_list:
  - lib/foglet_bbs/ssh/cli_handler.ex
  - lib/foglet_bbs/time_ago.ex
  - lib/foglet_bbs/tui/screens/board_list.ex
  - lib/foglet_bbs/tui/screens/main_menu.ex
  - lib/foglet_bbs/tui/screens/new_thread.ex
  - lib/foglet_bbs/tui/screens/post_composer.ex
  - lib/foglet_bbs/tui/screens/post_reader.ex
  - lib/foglet_bbs/tui/screens/thread_list.ex
  - lib/foglet_bbs/tui/screens/verify.ex
  - lib/foglet_bbs/tui/theme.ex
  - lib/foglet_bbs/tui/widgets/chrome/key_bar.ex
  - lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex
  - lib/foglet_bbs/tui/widgets/chrome/status_bar.ex
  - lib/foglet_bbs/tui/widgets/list/list_row.ex
  - lib/foglet_bbs/tui/widgets/list/selection_list.ex
  - lib/foglet_bbs/tui/widgets/post/markdown_body.ex
  - lib/foglet_bbs/tui/widgets/post/post_card.ex
findings:
  critical: 0
  warning: 4
  info: 3
  total: 7
status: issues_found
---

# Phase 01: Code Review Report

**Reviewed:** 2026-04-20
**Depth:** standard
**Files Reviewed:** 17
**Status:** issues_found

## Summary

Phase 01 adds a solid foundation: `Foglet.TUI.Theme` with 9 palettes registered via
Raxol's theme registry, three chrome widgets (`ScreenFrame`, `StatusBar`, `KeyBar`), two
list widgets (`SelectionList`, `ListRow`), two post widgets (`PostCard`, `MarkdownBody`),
a `TimeAgo` utility, and the migration of all 9 TUI screens to use `ScreenFrame`.

The widget code itself is well-structured and the theme resolution fallback path (static
palettes when Raxol registry not yet populated) is a thoughtful touch for test
environments. No security vulnerabilities were found.

Four warnings are present — two logic bugs with observable runtime behavior, one potential
crash in `CLIHandler.build_context/3`, and one unguarded nil dereference in
`PostComposer.do_submit`. Three info items cover a documented-vs-implemented discrepancy
in `KeyBar`, a dead branch in `ListRow.truncate_title/2`, and a render-path cache miss in
`PostReader`.

---

## Warnings

### WR-01: Connection counter double-decrement when over-limit client disconnects

**File:** `lib/foglet_bbs/ssh/cli_handler.ex:88-89`, `lib/foglet_bbs/ssh/cli_handler.ex:206`

**Issue:** When `check_connection_limit/0` returns `:over_limit`, the function already
atomically decrements the counter back to its pre-increment value (line 420). The `:over_limit`
branch then sends a rejection message, calls `:ssh_connection.close/2`, and returns
`{:ok, state}`. The channel process stays alive, so when the SSH daemon later delivers
`{:ssh_cm, _, {:closed, _}}`, `handle_ssh_msg/2` fires and calls
`decrement_connection_count/0` a second time (line 206). Each rejected connection that
completes its close handshake decrements the counter by 1 below the true active count,
effectively raising the enforced limit by 1 per rejection cycle.

**Fix:** Track whether the limit was exceeded in the state struct and skip the decrement
in the `:closed` handler for that case. The simplest approach: add a boolean field to the
`defstruct`, set it on `:over_limit`, and guard in `:closed`:

```elixir
# In defstruct:
defstruct [
  :channel_id,
  :connection_ref,
  :peer,
  :session_pid,
  :lifecycle_pid,
  :width,
  :height,
  over_limit: false   # <-- add this
]

# In :over_limit branch:
new_state = %__MODULE__{over_limit: true, channel_id: channel_id, connection_ref: connection_ref}
{:ok, new_state}

# In :closed handler:
unless state.over_limit do
  _ = decrement_connection_count()
end
```

---

### WR-02: `build_context/3` crashes when a pubkey-authenticated user has been deleted

**File:** `lib/foglet_bbs/ssh/cli_handler.ex:319`

**Issue:** `Foglet.Accounts.get_user!(uid)` uses the bang form, which raises
`Ecto.NoResultsError` if the user row was deleted between `start_session/1` (which
stored the `user_id`) and the subsequent PTY channel-up that calls `build_context/3`.
This crash propagates out of `handle_ssh_msg/2` uncaught, killing the channel process
and leaving the SSH connection in a hung state for the client.

**Fix:** Use a non-raising lookup with a nil fallback:

```elixir
%{user_id: uid} ->
  case Foglet.Accounts.get_user(uid) do
    {:ok, user} -> user
    _ -> nil
  end
```

Or, if `Foglet.Accounts` does not have a non-bang `get_user/1`, wrap with a rescue:

```elixir
%{user_id: uid} ->
  try do
    Foglet.Accounts.get_user!(uid)
  rescue
    Ecto.NoResultsError -> nil
  end
```

---

### WR-03: Unguarded `state.current_user.id` access in `PostComposer.do_submit/3`

**File:** `lib/foglet_bbs/tui/screens/post_composer.ex:280`

**Issue:** `do_submit/3` accesses `state.current_user.id` directly without a nil guard.
If `current_user` is `nil` (a guest who somehow reaches the composer — not prevented at
the router level), this raises `%KeyError{key: :id, term: nil}`, crashing the TUI process
for that session.

By contrast, `NewThread.do_create_thread/5` (line 364-398) correctly checks
`user_id = state.current_user && state.current_user.id` and branches on `if user_id do`.

**Fix:** Apply the same guard pattern used in `new_thread.ex`:

```elixir
defp do_submit(state, ss, draft) do
  sc = Map.get(state, :session_context) || %{}
  posts_mod = get_in(sc, [:domain, :posts]) || Foglet.Posts
  thread = state.current_thread
  user_id = state.current_user && state.current_user.id

  if is_nil(user_id) do
    {:update,
     %{state | modal: %{type: :error, message: "You must be logged in to post."}}, []}
  else
    attrs = %{body: draft}
    reply_to_id = ss[:reply_to] && ss[:reply_to].id
    attrs = if reply_to_id, do: Map.put(attrs, :reply_to_id, reply_to_id), else: attrs

    case posts_mod.create_reply(thread.id, thread.board_id, user_id, attrs) do
      ...
    end
  end
end
```

---

### WR-04: `DateTime.add/3` crash when `email_verify_resend_cooldown_seconds` is stored as a string

**File:** `lib/foglet_bbs/tui/screens/verify.ex:238-250`

**Issue:** `Foglet.Config.get("email_verify_resend_cooldown_seconds", 60)` returns the
unwrapped JSON value stored in the DB. If an admin stored the value as a string (e.g.,
`"60"`) instead of an integer, the return is `"60"` rather than `60`. Passing a string to
`DateTime.add(now, "60", :second)` raises `ArgumentError`, crashing the resend handler.
All other `Config.get!` usages in the codebase add a type guard (`n when is_integer(n)`)
before using the value numerically — this call does not.

**Fix:** Add the same integer guard with fallback to default:

```elixir
cooldown_seconds =
  case Foglet.Config.get("email_verify_resend_cooldown_seconds", 60) do
    n when is_integer(n) and n > 0 -> n
    _ -> 60
  end
```

---

## Info

### IN-01: `KeyBar` implementation does not match its documented UI-SPEC contract

**File:** `lib/foglet_bbs/tui/widgets/chrome/key_bar.ex:33`

**Issue:** The module doc states the contract is "Key bracket: `theme.accent.fg`" and
"Description: `theme.dim.fg`" (separate colors). The implementation uses `theme.accent.fg`
for the full `"[KEY] Description"` string — the description text is not rendered in
`theme.dim.fg`. The visual result is that all hint text is accent-colored, reducing the
visual weight separation between key labels and their descriptions.

**Fix:** Split the hint into two `text/2` calls per pair:

```elixir
Enum.flat_map(keys, fn {k, d} ->
  [
    text("[#{k}] ", fg: theme.accent.fg, style: accent_style),
    text("#{d}  ", fg: theme.dim.fg)
  ]
end)
```

Note: splitting into separate `text/2` nodes requires either a `row` wrapper per hint or
careful placement. Alternatively, accept the single-color rendering and update the
module doc to match the actual behavior.

---

### IN-02: Dead branch in `ListRow.truncate_title/2` — clauses 2 and 3 are identical

**File:** `lib/foglet_bbs/tui/widgets/list/list_row.ex:145-149`

**Issue:** The `cond` has four branches. Branches 2 (`max_len >= @min_title_length`) and 3
(`max_len >= 2`) have byte-for-byte identical bodies:
`String.slice(title, 0, max_len - 1) <> @ellipsis`. The third branch is only reachable
when `2 <= max_len < 20`, which was presumably intended to behave differently (perhaps
truncating to a single char with `…`), but currently does the same thing as branch 2. The
docstring hints at distinct behavior for narrow terminals.

**Fix:** Either implement the intended narrow-terminal behavior or collapse to a single
branch:

```elixir
cond do
  title_len <= max_len ->
    title

  max_len >= 1 ->
    String.slice(title, 0, max(max_len - 1, 0)) <> @ellipsis

  true ->
    @ellipsis
end
```

---

### IN-03: Initial render in `PostReader` bypasses the render cache, re-parsing markdown on every frame

**File:** `lib/foglet_bbs/tui/screens/post_reader.ex:66`

**Issue:** `render_post_content/5` reads `ss.render_cache[{post.id, w}]` and falls back
to `parse_body/2` on a miss, but it does not write the result back to the cache. The cache
is only populated by `warm_cache/4` — which is called inside `advance_post/2` and
`scroll_post/2`. Until the user presses a navigation key (`n/p/j/k`), every render frame
calls `Foglet.Markdown.render/1` anew for the initial post. On a busy terminal with high
re-render rates this adds unnecessary parsing work per frame.

**Fix:** Call `warm_cache/4` from within `render_post_content/5` (or from `render/1`)
immediately after computing the initial post, and persist the updated `ss` to
`screen_state`. Alternatively, seed the cache in `load_posts/2` so it is populated before
the first render.

---

_Reviewed: 2026-04-20_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
