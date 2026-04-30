---
phase: 47-bound-unbounded-list-queries-drop-chrome-v1-shims-and-reduce
reviewed: 2026-04-30T00:00:00Z
depth: standard
iteration: 5
files_reviewed: 36
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
  - lib/foglet_bbs/tui/screens/login.ex
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
  - lib/foglet_bbs/tui/widgets/README.md
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
findings:
  blocker: 0
  warning: 2
  info: 3
  total: 5
status: issues_found
---

# Phase 47: Code Review Report (Iteration 5 — fresh pass)

**Reviewed:** 2026-04-30
**Depth:** standard
**Status:** issues_found

## Summary

Iteration-4 fixes have all landed (verified via `git log` and re-reading
each file): WR-01, WR-02, WR-03, WR-04, IN-02, IN-03, IN-04, IN-05 are
resolved at the file level; IN-01 was correctly skipped per the prior
reviewer's own recommendation. The phase deliverables — bounded
`list_threads/{1,2,3}` (`@page_size = 50`, `@max_page_size = 500`), the
removal of Chrome v1 shims, and the per-mode Login decomposition into
`Login.{Menu, LoginForm, ResetRequest, ResetConsume, Render}` — are
intact and well-factored. The shared `Foglet.TUI.Screens.Shared.AppStateBridge`
extraction collapsed the previously-duplicated five-copy bridge into a
single helper, and the prior `TODO(WR-01)` in-source markers are gone.

This fresh pass surfaces a small set of new findings: a missing
fall-through clause in `Register.handle_register_result/2` that crashes
on an unanticipated `:verify` delivery shape (the same class of bug
WR-02 fixed for Login), a silent empty-result on `dispatch_thread_load`
when the configured threads module exports no compatible arity, and
three Info items around inconsistencies and selection edge cases.

No security, data-loss, or authorization issues were identified.

## Warnings

### WR-01: `Register.handle_register_result/2` does not match all `:verify` delivery shapes

**File:** `lib/foglet_bbs/tui/screens/register.ex:392-398, 411-414`

**Issue:** `register_user/3` is a `with` chain whose success branch
returns `{:ok, user, screen, delivery_or_nil}` where `delivery_or_nil`
is whatever `Verification.deliver_verification_code/1` returned wrapped
in the `{:ok, _}` shape. `LoginForm.login_success_result/3`
(`login/login_form.ex:186-193`) shows that
`deliver_verification_code/1` can in principle return four distinct
success-side shapes (`{:ok, :attempted}`, `{:error, :unavailable}`,
`{:error, :delivery_failed}`, `{:error, %Ecto.Changeset{}}`).

`register_user/3` only consumes `{:ok, delivery_or_nil}`, so any
`{:error, ...}` from delivery short-circuits the with and is forwarded
verbatim to `handle_register_result/2`. That is fine and is matched by
the `{:error, :unavailable}` and `{:error, _delivery_error}` clauses at
lines 434/443.

What is NOT fine: if delivery ever returns `{:ok, :something_else}` —
e.g., a future `{:ok, :queued}`, `{:ok, :rate_limited}`, or any test
fixture that returns a non-`:attempted` ok-shape — `register_user/3`
binds `delivery_or_nil = :something_else`, returns
`{:ok, user, :verify, :something_else}`, and
`handle_register_result/2` has no matching clause. Today's clause set
is:

- `{:ok, :pending_approval, _user}`
- `{:ok, user, :verify, :attempted}`
- `{:ok, user, :main_menu, _delivery}`
- `{:error, %Ecto.Changeset{}}`
- `{:error, :unavailable}`
- `{:error, _delivery_error}`

A `{:ok, user, :verify, _other}` shape raises `FunctionClauseError`,
which then surfaces as the generic `{:task_error, :register, _}` modal
("Something went wrong while trying to register…"). Same class of
defect as Phase 47 WR-02 in Login: an unanticipated success-shape
silently becomes a fault.

**Fix:** Add a catch-all that mirrors the verify path:

```elixir
defp handle_register_result(state, {:ok, user, :verify, _delivery}) do
  # Treat any non-:attempted verify delivery the same as :attempted —
  # the user is registered, hand them off to the verify screen.
  {RegisterState.put(state, RegisterState.default()),
   [Effect.session({:set_current_user, user}), Effect.navigate(:verify, %{})]}
end
```

Place it AFTER the explicit `{:ok, user, :verify, :attempted}` clause
so the explicit shape still matches first. Optionally `Logger.warning`
the unknown shape so operators see the breadcrumb.

---

### WR-02: `ThreadList.dispatch_thread_load/3` silently returns `[]` for misconfigured `threads_mod`

**File:** `lib/foglet_bbs/tui/screens/thread_list.ex:283-296`

**Issue:** When the resolved `threads_mod` is loadable but exports
neither `list_threads/2` nor `list_threads/1`, the `cond` falls through
to `true -> []`. The screen then transitions to `status: :empty` and
renders "No threads in this board yet. Press [C] to compose." There is
no `Logger.warning`, no `last_error`, and no telemetry signal.

This is reachable when a domain-override map (e.g., a test fixture or a
typo in `session_context.domain[:threads]`) points at a module that
doesn't conform to the threads-mod contract. Today's tests use
`FakeThreads` adapters that DO export `list_threads/1`, so the
fallthrough is unreachable in tests — but the production override path
in `domain_module/2` (`thread_list.ex:266-273`) accepts any atom.

The pre-existing comment at lines 275-282 acknowledges the dispatch
exists "for minimal test adapter modules" but does not address what
happens when neither arity is exported. Compare to
`Routing.maybe_known_screen_module/2`
(`app/routing.ex:227-241`), which both `Logger.error`s and falls back
to `MainMenu` for unknown screens — a similar misconfiguration class
that takes care to surface itself.

**Fix:** Add a `Logger.warning` to the fall-through branch and (still
return `[]` to preserve current empty-render behavior) tag
`last_error: :threads_mod_unsupported` so the diagnosis shows up in
logs and screen telemetry:

```elixir
true ->
  require Logger
  Logger.warning(
    "[ThreadList] threads_mod #{inspect(threads_mod)} exports neither " <>
      "list_threads/1 nor list_threads/2; returning empty result"
  )
  []
```

This matches the diagnostic-rather-than-silent posture already adopted
by `Posts.normalize_reader_direction/1` (WR-04 fix at `posts.ex:175-182`)
and `reader_rows_around/3`'s WR-06 branch (`posts.ex:237-245`).

## Info

### IN-01: `Routing.maybe_known_screen_module/2` returns implicit `nil` when screen unknown and not active

**File:** `lib/foglet_bbs/tui/app/routing.ex:227-241`

**Issue:** When the `screen` atom is not in `known_screens()` AND
`active_route?` is false, the `if active_route?` block has no `else`
clause, so the function returns `nil`. Callers (`route_screen_update/3`
at line 105, `render_screen/1` at line 163) handle the `nil` case
defensively via `Code.ensure_loaded?(nil)` (which returns `false`), so
this is not a live crash today.

The implicit-nil return is a quiet behavior — there is no Logger
breadcrumb when an unknown screen is referenced from a non-active path
(e.g., a stale subscription pointing at a dead screen). Compare to the
`active_route?` branch at lines 232-238 which `Logger.error`s before
falling back to MainMenu. The asymmetry means a typo in a non-active
route silently no-ops while a typo in the active route is loudly
logged.

**Fix:** Make the no-match branch explicit and emit a `Logger.debug` (not
warning — non-active paths are intentionally tolerant of unknown
screens for partial-screen-state cleanup), or just add an explicit
`else: nil` clause so the return shape is obvious to readers:

```elixir
if active_route? do
  require Logger
  Logger.error("[TUI.App.Routing] no screen module for #{inspect(screen)}; falling back to :main_menu")
  Screens.MainMenu
else
  nil
end
```

No-action acceptable; this is a code-clarity nit, not a correctness
defect.

---

### IN-02: `PostReader.place_selection_after_load/4` lands on index 0 when read pointer is past the loaded window

**File:** `lib/foglet_bbs/tui/screens/post_reader.ex:385-409`

**Issue:** The selection-placement chain is:

1. `index_of_message_number(posts, read_pointer_msg_no)` — exact match
2. `index_of_first_message_number_at_or_after(posts, read_pointer_msg_no)` — first ≥ pointer (WR-04 fallback)
3. `selected_index_after_window_load(ss, window, posts)` — generic fallback (returns 0 unless intent overrides)

When `read_pointer_msg_no` is greater than every loaded
`message_number` in `posts` (e.g., the user's pointer is at message 300
but the `:around` window only loaded 250-280 because the thread tail
was concentrated there, or the pointer is otherwise past the end of
what loaded), step 2 returns nil and step 3 falls back to index 0. The
user lands at the START of a window that is BEHIND their pointer —
arguably a worse outcome than landing at the end.

In practice the `:around` direction in
`Posts.list_reader_window/2` centers the window on
`around_message_number`, so this case is unlikely outside of soft-deleted
tail posts or stale pointers. But the contract for "if you saw it, you
read it" is broken in this corner: the user re-enters past their
read-up-to point and lands BEFORE it.

**Fix:** When step 2 returns nil and the pointer is past
`window_last_message_number`, prefer the last index (`length(posts) - 1`)
over the generic fallback:

```elixir
defp place_selection_after_load(%State{} = ss, window, posts, read_pointer_msg_no) do
  selected_index =
    if is_integer(read_pointer_msg_no) do
      index_of_message_number(posts, read_pointer_msg_no) ||
        index_of_first_message_number_at_or_after(posts, read_pointer_msg_no) ||
        if pointer_past_window_tail?(window, read_pointer_msg_no),
          do: max(length(posts) - 1, 0),
          else: selected_index_after_window_load(ss, window, posts)
    else
      selected_index_after_window_load(ss, window, posts)
    end

  %{ss | selected_post_index: selected_index}
end

defp pointer_past_window_tail?(window, pointer) do
  case Map.get(window, :last_message_number) do
    last when is_integer(last) -> pointer > last
    _ -> false
  end
end
```

This is unlikely to trigger in production; logging as Info rather than
Warning.

---

### IN-03: `LoginForm.handle_task_result/3` `{:ok, result}` clause re-wraps state via `app_state_from_local` even on the success path

**File:** `lib/foglet_bbs/tui/screens/login/login_form.ex:46-52, 277-279`

**Issue:** Both clauses of `handle_task_result/3` now route through
`app_state_from_local(local_state, ctx) |> ... |> local_result(local_state)`.
On the `{:error, reason}` path this is necessary — the modal effect
needs the App-state shell. On the `{:ok, result}` path,
`handle_login_result/2` operates on the App-state shell and writes back
through `LoginState.put`, so the wrap/unwrap is required there too. But
the round-trip `local_state → app_state → handle_login_result →
{state, effects} → LoginState.get(state) → local_state'` does extra
work where `handle_login_result/2` could in principle just take and
return the local-state map directly — `LoginForm` is the per-mode
reducer, the App-state shell only gets in the way.

This is a refactor-shape comment, not a defect. Today's wrap/unwrap is
correct because `domain_module/2` and `LoginState.put/2` are both
written against the wrapped App-state. Flagging because the same
wrap/unwrap pattern repeats in `Login.update/3:54-58`,
`Register.update/3:76-81`, and `Verify.update/3` — the
`AppStateBridge.from_context/4` factoring (WR-04 iteration 4) hid the
duplication but did not eliminate the need to wrap on every key
dispatch. Future cleanup could push the per-mode reducers to operate on
local state directly with explicit context-passing for `domain` and
`session_context` reads.

**Fix:** No change required for Phase 47. Track as backlog if the
per-mode-reducer pattern proliferates further.

---

_Reviewed: 2026-04-30_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
_Iteration: 5 — fresh pass against post-iteration-4 code state_
