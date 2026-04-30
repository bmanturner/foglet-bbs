---
phase: 47-bound-unbounded-list-queries-drop-chrome-v1-shims-and-reduce
reviewed: 2026-04-30T00:00:00Z
depth: standard
files_reviewed: 35
files_reviewed_list:
  - .dialyzer_ignore.exs
  - lib/foglet_bbs/posts.ex
  - lib/foglet_bbs/threads.ex
  - lib/foglet_bbs/tui/app.ex
  - lib/foglet_bbs/tui/app/routing.ex
  - lib/foglet_bbs/tui/app/screen_states.ex
  - lib/foglet_bbs/tui/app/session_alias.ex
  - lib/foglet_bbs/tui/screens/account/render.ex
  - lib/foglet_bbs/tui/screens/board_list.ex
  - lib/foglet_bbs/tui/screens/login/login_form.ex
  - lib/foglet_bbs/tui/screens/login/menu.ex
  - lib/foglet_bbs/tui/screens/login/render.ex
  - lib/foglet_bbs/tui/screens/login/reset_consume.ex
  - lib/foglet_bbs/tui/screens/login/reset_request.ex
  - lib/foglet_bbs/tui/screens/moderation.ex
  - lib/foglet_bbs/tui/screens/new_thread/render.ex
  - lib/foglet_bbs/tui/screens/post_composer.ex
  - lib/foglet_bbs/tui/screens/post_reader.ex
  - lib/foglet_bbs/tui/screens/post_reader/render.ex
  - lib/foglet_bbs/tui/screens/register.ex
  - lib/foglet_bbs/tui/screens/thread_list.ex
  - lib/foglet_bbs/tui/screens/verify.ex
  - lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex
  - lib/foglet_bbs/tui/widgets/chrome/status_bar.ex
  - test/foglet_bbs/posts/posts_test.exs
  - test/foglet_bbs/threads/threads_test.exs
  - test/foglet_bbs/tui/app/screen_states_test.exs
  - test/foglet_bbs/tui/app/session_alias_test.exs
  - test/foglet_bbs/tui/app_test.exs
  - test/foglet_bbs/tui/layout_smoke_test.exs
  - test/foglet_bbs/tui/screens/post_reader_test.exs
  - test/foglet_bbs/tui/widgets/chrome/breadcrumb_migration_test.exs
  - test/foglet_bbs/tui/widgets/chrome/screen_frame_test.exs
  - test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs
  - lib/foglet_bbs/tui/widgets/README.md
findings:
  blocker: 1
  warning: 8
  info: 5
  total: 14
status: issues_found
---

# Phase 47: Code Review Report

**Reviewed:** 2026-04-30
**Depth:** standard
**Files Reviewed:** 35
**Status:** issues_found

## Summary

Phase 47 bounds previously-unbounded list queries (`Threads.list_threads/*`),
extracts per-mode reducers from the Login screen, and trims the Dialyzer ignore
baseline. The bounded-query work itself is structurally correct: page size is
centralised in `@page_size`, both `list_threads/3` heads share a
`normalize_limit/1` helper, and a sibling `list_threads_query/3` is exposed for
SQL-level test inspection. However a few subtle defects survived the cleanup:

- **One BLOCKER**: `Posts.reader_has_next?/3` returns `true` when the
  `:previous` window has already exhausted the thread on its first page, which
  causes the reader to advertise a non-existent next window and fire a redundant
  load. Pre-Phase-47 code already had this latent issue; this phase changes the
  enclosing logic and ships it untouched.
- **WARNINGS**: identical/dead clauses (`reader_rows_around/3` int+nil
  variants), an arity-2 `domain_module/3` "unused parameter" pattern that
  silently shadows `default`, an unreachable `render/2` second clause on
  `BoardList`, an `app_state_from_local/2` helper duplicated verbatim across
  every login sub-reducer (D-14 calls this out but it's still drift-prone), a
  size-gated `update/2` race that can drop `current_user` updates, the
  `bottom_padding` arithmetic in `render_menu/3` that can create a negative
  duplication count under tiny terminals when SizeGate is bypassed, and the
  `index_of_message_number/2` short-circuit that picks index 0 for a `nil`
  pointer mid-thread.
- **INFO**: dead `Map.put(:select_thread_id, nil)` on a state where the field
  is already `nil`, a `dispatch_route_entry/3` public function with no in-tree
  callers, a `tab_labels_from_tabs/1` partial function (no fallback clause),
  duplicated `unwrap_task_result/1` across BoardList and Moderation, and an
  unused `_unused_default` pattern in `Moderation.domain_module/3`.

The bounded-list work is the right shape but lacks a `:limit > absolute_max`
clamp (e.g. someone passing `limit: 1_000_000` opts gets the unbounded scan
back). Document or enforce a ceiling.

## Blockers

### BL-01: `reader_has_next?/3` falsely advertises a next window after a fully-consumed `:previous` page

**File:** `lib/foglet_bbs/posts.ex:238-240`
**Issue:**
```elixir
defp reader_has_next?(_thread_id, [_ | _posts], _fallback_cursor), do: true
defp reader_has_next?(_thread_id, [], cursor) when is_integer(cursor), do: true
defp reader_has_next?(_thread_id, _posts, _cursor), do: false
```

This is called from the `:previous` branch of `list_reader_window/2`
(`posts.ex:121`) as the `has_next?` value for the returned window. When a user
pages backwards and the previous query returns *any* posts, `has_next?` is set
to `true` unconditionally — even when the reader is now positioned strictly
before the original cursor and there is in fact a next window available, the
result is conflated with the more dangerous case where `posts == []` (no
previous results) but `cursor` is a valid integer: the function still returns
`true`, telling the screen to render a "next" affordance and triggering
`PostReader.load_adjacent_window(:next)` even when no adjacent window exists.
The PostReader uses this exact field at `post_reader.ex:756` to gate
`load_adjacent_window`, so the false `true` produces a wasted DB round trip and
a flicker in `:loading` status.

The narrower bug: the `[]` clause requires only `is_integer(cursor)` (no `> 0`
guard, unlike `reader_has_previous?/3` on line 233) so even cursor `0` returns
`true`.

**Fix:**
```elixir
defp reader_has_next?(thread_id, posts, cursor)
defp reader_has_next?(_thread_id, [_ | _], _cursor), do: true
defp reader_has_next?(thread_id, [], cursor) when is_integer(cursor) do
  # Verify a next window actually exists rather than guessing from the cursor.
  Repo.exists?(
    from p in Post,
      where: p.thread_id == ^thread_id and p.message_number >= ^cursor
  )
end
defp reader_has_next?(_thread_id, _posts, _cursor), do: false
```

Or change the call site at `posts.ex:121` to pass `false` when the previous
window came back empty (no posts before the cursor → necessarily nothing
adjacent in the next direction at this position).

## Warnings

### WR-01: `app_state_from_local/2` duplicated verbatim across 5 modules

**File:** `lib/foglet_bbs/tui/screens/login/login_form.ex:241-252`
(also `login/render.ex:48-59`, `login/reset_consume.ex` (no copy here),
`register.ex:310-321`, `verify.ex:291-302`)
**Issue:** Every login-family screen re-implements the same shape-shift from
`local_state + Context` to App-state map. The `@moduledoc` references "Plan 05
D-14" as authority but provides no mechanism to keep the copies aligned. If a
new field is added to App-state (e.g., `:modal`, `:flash`), one of these will
miss it and the corresponding screen will subtly degrade. The
`session_pid` field is in some copies (login_form, register, verify) but not
others (`login/render.ex` includes it, `login/reset_consume.ex` is missing it
entirely because reset_consume only ever reads `:domain`). This drift already
exists.
**Fix:** Extract to `Foglet.TUI.Screens.Login.AppStateBridge.from_local/2` (or
similar) and call from each screen. Even if "Plan 05 D-14" intentionally
deferred this, leave a TODO with the decision link rather than shipping copies
silently.

### WR-02: `:set_user` dropped while SizeGate is engaged

**File:** `lib/foglet_bbs/tui/app.ex:252-272` and `app.ex:238`
**Issue:** `do_update({:key, _}, state)` swallows keys when `SizeGate.too_small?`
returns true (D-11). But there is no analogous protection for `:set_user`,
`:promote_session`, etc. — those flow through unconditionally, mutate
`current_user` and dispatch a `Foglet.TUI.Effect.navigate(:main_menu, %{})`,
and may attempt to render a screen that the gate would otherwise hide. The
race is small (the next `view/1` call still re-checks SizeGate) but the
intermediate `Effects.apply_effect` path will run `init_route_screen_state/3`
and any `:on_route_enter` effect, defeating the "screens are hidden" promise of
D-11. Either explicitly defer state-changing effects while gated, or document
why navigation effects are exempt.
**Fix:** Add a SizeGate check at the top of `do_update/2` that defers
`{:promote_session, _}` and similar to a queue, or explicitly comment why
non-key messages are exempt.

### WR-03: `BoardList.render/2` second clause is unreachable

**File:** `lib/foglet_bbs/tui/screens/board_list.ex:246`
**Issue:** The first `render/2` head pattern-matches `%State{} = local_state`,
which already covers every state created by `BoardList.init/1` (which always
returns `State.new/1`). The fallback `def render(local_state, %Context{} = context)`
calls `normalize_state/1` which itself only converts non-`%State{}` to
`State.new()` — but Routing's `render_local_state/4` always either returns the
stored `%State{}` or calls `module.init/1` (which returns `%State{}`). The
fallback can never fire in production and the `@spec` doesn't acknowledge it.
**Fix:** Either delete the fallback (state shape is now always `%State{}`) or
narrow the spec to `render(State.t() | nil, Context.t())` and add a guard so
Dialyzer can verify reachability.

### WR-04: `index_of_message_number/2` returns nil → `||` falls through to default index

**File:** `lib/foglet_bbs/tui/screens/post_reader.ex:367-373`
**Issue:**
```elixir
selected_index =
  (is_integer(read_pointer_msg_no) && index_of_message_number(posts, read_pointer_msg_no)) ||
    selected_index_after_window_load(ss, window, posts)
```

When `read_pointer_msg_no` is a valid integer but the post with that
`message_number` is **not** in the loaded window (e.g., the post was
soft-deleted, or the read pointer is stale and points to a moved post),
`index_of_message_number/2` returns `nil`. The `||` then falls back to
`selected_index_after_window_load`, which for a default `:initial` window picks
index 0 — silently dropping the user at the top of the thread instead of at
their bookmark. The intent in the inline comment ("land selection on the post
matching that message_number") is not satisfied; the user sees no error and no
indication their pointer was lost.
**Fix:** When the pointer is set but the post is not in the loaded window,
either land selection at the closest message_number ≥ pointer (find_index of
first `mn >= ptr`) or surface a status flag so the caller can show a "pointer
not in current window" notice.

### WR-05: `render_menu/3` can produce negative `bottom_padding` — defensively clamped to 0

**File:** `lib/foglet_bbs/tui/screens/login/render.ex:124-138`
**Issue:** `available = max(terminal_height - 8, 1)`; `top_padding = div(available, 2)`;
`bottom_padding = max(available - top_padding - 2, 0)`. When `available == 1`
(terminal_height ≤ 9), `top_padding == 0`, `bottom_padding == max(-1, 0) == 0`,
and the menu collapses to two text rows centered on the top. This is mostly
fine because `SizeGate` should have intercepted, but `render_menu/3` is also
reachable through `Routing.render_screen/1` which is called from
`view/1` → `Routing.render_screen` only when `not SizeGate.too_small?(state)`.
Verify `SizeGate.too_small?/1` rejects every height where this arithmetic
underflows — otherwise the screen renders no padding rows at all on a 5-line
terminal. The `max(_, 0)` guard prevents the crash but masks a contract
violation.
**Fix:** Either add a unit test for `render_menu/3` at terminal_height ∈ {2, 5,
8, 9, 10} confirming SizeGate gates everything below the contract minimum, or
collapse the `max(_, 0)` guard and let it crash if the gate ever lets a
too-small frame through (so the bug surfaces in dev).

### WR-06: `reader_rows_around/3` has two functionally-identical heads

**File:** `lib/foglet_bbs/posts.ex:162-199`
**Issue:** `reader_rows_around(thread_id, nil, limit)` (line 162) and
`reader_rows_around(thread_id, _around_message_number, limit)` (line 197) both
delegate to the same implementation when the message number is missing or
non-integer. The third clause is dead-ish: it only matches when
`around_message_number` is neither `nil` nor an integer (e.g., a binary, atom,
float). This is defensive but it silently coerces "I asked for around #abc" to
"give me the initial window" with no log line. If the caller is buggy
(stringified message_number), this hides it.
**Fix:** Either drop the third clause and let it FunctionClauseError on bad
input (callers always pass int|nil), or add a `Logger.warning` so unexpected
shapes are visible.

### WR-07: `Threads.list_threads/3` accepts unbounded limits via `:limit`

**File:** `lib/foglet_bbs/threads.ex:117-135` and `207-208`
**Issue:** `normalize_limit/1` only rejects non-positive integers — any
positive integer (e.g., `999_999`) is accepted and translates directly to a
SQL `LIMIT 999_999`. The whole point of Phase 47 R3/R4 was to *bound*
unbounded queries; without an upper clamp, a future call site (or an attacker
on a sysop-only direct call path) can re-introduce the unbounded scan that
this phase removed.
**Fix:**
```elixir
@max_page_size 500  # or whatever you consider safe
defp normalize_limit(limit) when is_integer(limit) and limit > 0,
  do: min(limit, @max_page_size)
defp normalize_limit(_limit), do: @page_size
```
And exercise `list_threads(board_id, nil, limit: 1_000_000)` in
`threads_test.exs` to assert the SQL `LIMIT` is at most `@max_page_size`.

### WR-08: `Moderation.domain_module/3` ignores its `default` parameter for the session-context fallback

**File:** `lib/foglet_bbs/tui/screens/moderation.ex:475-480`
**Issue:**
```elixir
defp domain_module(%Context{} = context, key, default) do
  Map.get(context.domain || %{}, key) ||
    (is_map(context.session_context) &&
       get_in(context.session_context, [:domain, key])) ||
    default
end
```

When `Map.get(context.domain || %{}, key)` returns `false` (extremely
unlikely, but a domain map containing `%{moderation: false}` would do it),
short-circuit `||` falls through to the `is_map(...)` clause, then to
`default`. More practically: when the session_context branch evaluates to
`false` (the `is_map(...)` guard) **and** `default` is `nil`, the call
silently returns `nil` and the eventual `Effect.task` body crashes with
`UndefinedFunctionError`. Compare with `BoardList.domain_module/2`
(`board_list.ex:455-466`), which routes through a typed default rather than
relying on `||` semantics. Switch to a `case`/`with` so each path explicitly
returns a module atom.
**Fix:**
```elixir
defp domain_module(%Context{} = context, key, default) do
  case Map.get(context.domain || %{}, key) do
    mod when is_atom(mod) and not is_nil(mod) -> mod
    _ -> session_context_domain(context, key, default)
  end
end

defp session_context_domain(%Context{session_context: sc}, key, default) when is_map(sc) do
  case get_in(sc, [:domain, key]) do
    mod when is_atom(mod) and not is_nil(mod) -> mod
    _ -> default
  end
end

defp session_context_domain(_context, _key, default), do: default
```

## Info

### IN-01: `apply_selection_intent` writes `select_thread_id: nil` onto state where it is already nil

**File:** `lib/foglet_bbs/tui/screens/thread_list.ex:342-346`
**Issue:** First clause matches `%State{select_thread_id: nil}`, then immediately
calls `Map.put(:select_thread_id, nil)`. Dead operation — the field is already
nil. Tiny perf nit but more importantly mildly confusing to read.
**Fix:** Delete the `Map.put` — return `select_index(state, ...)` directly.

### IN-02: `Routing.dispatch_route_entry/3` appears unused inside the listed files

**File:** `lib/foglet_bbs/tui/app/routing.ex:96-100`
**Issue:** Public `@spec`-d API but the only in-tree call path I can see uses
the `:initial_route_enter` → `route_screen_update(_, _, :on_route_enter)` flow
in `app.ex:316-322`, which calls `route_screen_update/3` directly, not
`dispatch_route_entry/3`. If `dispatch_route_entry/3` truly has no callers,
delete it; if it's intentional contract surface for a future caller, add a
`@doc` note explaining the seam.
**Fix:** Verify with `grep -rn dispatch_route_entry lib/ test/`. If unused,
delete or mark `@doc false` with rationale.

### IN-03: `tab_labels_from_tabs/1` has no fallback clause

**File:** `lib/foglet_bbs/tui/screens/moderation.ex:389-394`
**Issue:** Only matches `%Tabs{raxol_state: %{tabs: tabs}} when is_list(tabs)`.
If a corrupt `%Tabs{}` (raxol_state without `:tabs`, or non-list `:tabs`)
flows through, this raises FunctionClauseError instead of falling back to a
sane default. Used inside `render/1` so a corrupt tab state crashes the screen.
**Fix:** Add a fallback `defp tab_labels_from_tabs(_tabs), do: []` and have
the caller treat empty as "QUEUE only".

### IN-04: `unwrap_task_result/1` duplicated verbatim in BoardList and Moderation

**File:** `lib/foglet_bbs/tui/screens/board_list.ex:475-479` and
`lib/foglet_bbs/tui/screens/moderation.ex:470-473`
**Issue:** Same five-clause function exists in both modules. PostReader and
PostComposer pattern-match `:task_result` shapes inline instead, so the
project already has three different conventions for unwrapping the same
double-`:ok` Raxol task wrapping.
**Fix:** Move to `Foglet.TUI.Effect.unwrap_task_result/1` (or similar) and
import where used.

### IN-05: `register.ex` has two `registration_mode/1` heads with non-distinguishable signatures

**File:** `lib/foglet_bbs/tui/screens/register.ex:461-473`
**Issue:** `registration_mode(%Context{} = context)` and
`registration_mode(state)` (any term). The second is a true catchall — it
accepts a `%Context{}` too because the first clause is just a more specific
version of the second. The function bodies are identical except for which
field they access (`session_ctx/1` resolves both via `Map.get(state,
:session_context) || %{}` so even that doesn't matter). The two clauses
collapse to one.
**Fix:** Replace with:
```elixir
defp registration_mode(state) do
  case Map.get(session_ctx(state), :registration_mode) do
    nil -> Config.get("registration_mode", "open")
    mode -> mode
  end
end
```

---

_Reviewed: 2026-04-30_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
