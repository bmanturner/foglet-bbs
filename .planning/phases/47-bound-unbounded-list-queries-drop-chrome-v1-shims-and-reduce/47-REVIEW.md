---
phase: 47-bound-unbounded-list-queries-drop-chrome-v1-shims-and-reduce
reviewed: 2026-04-30T00:00:00Z
depth: standard
files_reviewed: 36
files_reviewed_list:
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
  - lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex
  - lib/foglet_bbs/tui/widgets/chrome/status_bar.ex
  - .dialyzer_ignore.exs
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
  critical: 0
  warning: 4
  info: 5
  total: 9
status: issues_found
---

# Phase 47: Code Review Report

**Reviewed:** 2026-04-30
**Depth:** standard
**Files Reviewed:** 36
**Status:** issues_found

## Summary

Phase 47 lands three goals cleanly: (R3/R4) `Foglet.Threads.list_threads/{1,2,3}` is now bounded by `@page_size = 50` with a `@max_page_size = 500` ceiling and a defensive non-positive fallback; (R1) Chrome v1 widget shims are gone and `ScreenFrame` is the single chrome surface; (R5) `login.ex` is split into `Login.{Menu, LoginForm, ResetRequest, ResetConsume, Render}` per-mode reducers. Diff-resident defects are mostly minor — no security or data-loss blockers were found.

The most concerning items are around error handling in `LoginForm.handle_task_result` (network/system errors are silently mapped to "Invalid credentials"), an unhandled fall-through in `authenticate_login`'s `with` chain, and an unguarded `state.screen_state` write in `PostReader.load_posts/2`. None are introduced exclusively by this phase, but they live in the diff and the post-fix iteration of REVIEW.md is the appropriate place to record them.

A handful of WR/IN findings from the prior REVIEW iteration have been fixed (BL-01, WR-01, WR-03, WR-04, WR-05, WR-06, WR-07, WR-08, IN-01..IN-05) — those are not re-reported here. The `TODO(WR-01)` markers for the duplicated `app_state_from_local/2` bridge across four sibling screens remain unresolved and are flagged below.

## Warnings

### WR-01: `LoginForm.handle_task_result/3` masks all task errors as `:invalid_credentials`

**File:** `lib/foglet_bbs/tui/screens/login/login_form.ex:52-57`

**Issue:** Any `{:error, _reason}` returned by Raxol's task pipeline — including network failures, GenServer crashes, timeouts, or unhandled exceptions inside `authenticate_login/5` — is reduced to `{:error, :invalid_credentials}` and rendered to the user as "Invalid credentials." This conflates two distinct conditions:

1. The user typed the wrong password (legitimate auth failure).
2. The Foglet backend has a bug (e.g., the `WithClauseError` from the unhandled fall-through flagged in WR-02 below; an `Auth.authenticate_by_password/2` raise; an Ecto pool timeout).

Effects: (a) users see misleading copy that suggests credential entry error when the system is broken; (b) operators lose a fault signal because no `Logger.error` fires here — the only Logger call in the App-side pipeline (`app.ex:373-383`, `:task_error`) does not reach this clause because `LoginForm.handle_task_result` is invoked via `:task_result` dispatch, not `:task_error`.

**Fix:**
```elixir
def handle_task_result({:error, reason}, local_state, %Context{} = _ctx) do
  require Logger
  Logger.error("[Login] login task crashed: #{inspect(reason)}")

  modal = %Foglet.TUI.Modal{
    type: :error,
    message: "Login is temporarily unavailable. Please try again."
  }

  {local_state, [Effect.open_modal(modal)]}
end
```

Reserve `{:error, :invalid_credentials}` for the explicit `{:ok, {:error, :invalid_credentials}}` shape returned by `authenticate_login/5` itself.

---

### WR-02: `authenticate_login/5` `with` chain has unhandled fall-through cases

**File:** `lib/foglet_bbs/tui/screens/login/login_form.ex:130-146`

**Issue:** The `with` chain matches `{:ok, user}` and `:active`. The `else` clause covers only:

- `{:error, :invalid_credentials}`
- `status when status in [:pending, :rejected, :suspended]`

But `Foglet.Accounts.User.status` is an atom that can in principle take other values (e.g., `:unverified`, `:locked`, future additions, or a misshapen test fixture). Any value that is not `:active`, `:pending`, `:rejected`, or `:suspended` will raise `WithClauseError`. The crash is then swallowed by the `{:error, _reason}` clause flagged in WR-01 above and rendered as "Invalid credentials" — silently misclassifying the bug.

Additionally, if `Auth.authenticate_by_password/2` ever returns an error tuple other than `{:error, :invalid_credentials}` (e.g., `{:error, :rate_limited}`, `{:error, :unavailable}`), the same `WithClauseError` fires.

**Fix:** Add a generic else clause for unanticipated status atoms and unanticipated auth errors so the bug is surfaced instead of masked:

```elixir
else
  {:error, :invalid_credentials} ->
    {:error, :invalid_credentials}

  status when status in [:pending, :rejected, :suspended] ->
    {:error, status}

  {:error, other} ->
    require Logger
    Logger.error("[Login] unexpected auth error: #{inspect(other)}")
    {:error, :invalid_credentials}

  other ->
    require Logger
    Logger.error("[Login] unexpected user status: #{inspect(other)}")
    {:error, :invalid_credentials}
end
```

---

### WR-03: `PostReader.load_posts/2` writes to `state.screen_state` without nil-guard

**File:** `lib/foglet_bbs/tui/screens/post_reader.ex:316`

**Issue:** `load_posts/2` ends with:

```elixir
{%{state | screen_state: Map.put(state.screen_state, :post_reader, ss)}, []}
```

`Map.put/3` raises `BadMapError` when the first argument is `nil`. `apply_flush_result/4` (line 501) uses the safer `Map.put(state.screen_state || %{}, :post_reader, new_ss)` and `get_screen_state/1` (line 545-546) accepts the no-`screen_state` case — but the write at line 316 does not.

`load_posts/2` is documented (READER-02) as a "stable callable entry point" for tests and direct invocation; that contract gets exercised with partial fixtures whose `screen_state` is `nil`. The defensive treatment from line 501 was not propagated here.

**Fix:**
```elixir
{%{state | screen_state: Map.put(state.screen_state || %{}, :post_reader, ss)}, []}
```

Audit the rest of the module for any other `state.screen_state`-as-map writes that lack the `|| %{}` guard.

---

### WR-04: `app_state_from_local/2` duplicated across four sibling screen modules; drift already started

**Files:**
- `lib/foglet_bbs/tui/screens/login.ex:84-95`
- `lib/foglet_bbs/tui/screens/login/login_form.ex:247-258`
- `lib/foglet_bbs/tui/screens/login/render.ex:51-62`
- `lib/foglet_bbs/tui/screens/register.ex:313-324`
- `lib/foglet_bbs/tui/screens/verify.ex:294-305`

**Issue:** Five near-identical copies of the App-state bridge helper sit in this diff. `TODO(WR-01)` markers exist in four of them acknowledging the duplication and noting drift has already begun (the comment at `login_form.ex:240-246` calls out that `:session_pid` is missing from `login/reset_consume`'s call site, which is why `reset_consume.ex` does not have the helper at all — it accesses the wrapped state passed by `Login.update/3`).

Adding any new App-state field — e.g., `:modal`, `:flash`, `:flags` — requires touching all five sites in lockstep. Equally, the duplicated `domain_module/2` helpers in the same screens (`login_form.ex:266-277`, `reset_consume.ex:144-153`, `reset_request.ex:152-161`, `register.ex:476-486`, `verify.ex:307-316`) all share the same shape and default mapping.

This is not a correctness bug today but is a maintenance hazard explicitly acknowledged in-source.

**Fix:** Extract to `Foglet.TUI.Screens.Shared.AppStateBridge` (or similar) with a `from_context/3` function taking `(local_state, context, screen_atom)` that returns the canonical App-state map. Co-locate `domain_module/2` (or move it to `Foglet.TUI.Screens.Domain`, where it belongs anyway). Update all five sites in one PR.

This fix can be deferred (the TODO markers indicate that consciously) but should be tracked as a real backlog item — Linear ticket or similar — rather than left as inline TODO comments.

## Info

### IN-01: `Threads.move_thread/2` hard-pattern-matches `Repo.update_all` return shape

**File:** `lib/foglet_bbs/threads.ex:336-340`

**Issue:** `{_count, nil} = Repo.update_all(...)` will raise `MatchError` if Ecto ever returns a different shape (e.g., a future Ecto version, or a wrapped adapter). The comment at lines 333-335 explicitly states this is intentional — "fail loudly rather than silently swallow it." The match is correct against today's Postgres adapter contract (`{integer, nil}` when no `:returning` is passed).

This is intentional defensive code, not a defect. However, the pattern `_ = Repo.update_all(...)` would be equally safe and would not couple the code to a specific Ecto contract. Keeping the strict match is reasonable; the comment is clear about why. Logging this as Info rather than asking for a change.

**Fix:** No change required. If the codebase prefers loose contracts elsewhere, consider replacing with `_ = Repo.update_all(...)` for consistency.

---

### IN-02: `Posts.create_reply/4` returns `:posting_not_allowed` for "thread does not exist"

**File:** `lib/foglet_bbs/posts.ex:56-57`

**Issue:** The `cond` clause `not match?(%Thread{board_id: ^board_id}, thread)` returns `:posting_not_allowed` for three distinct conditions: (a) thread not found (`nil` from `safe_get`), (b) thread belongs to a different board, (c) thread is not a `%Thread{}` struct. Conflating "not found" with "not allowed" can be deliberate security-information-hiding, but today the reader has to deduce the intent from `safe_get/2`'s nil-on-miss behavior.

**Fix:** Add a one-line comment near line 56 stating that this clause intentionally folds three failure modes into a single error to avoid leaking thread existence to callers that lack post-creation permission. Or, if the obscuring is not intentional, split into `:thread_not_found | :thread_in_other_board | :posting_not_allowed`.

---

### IN-03: `PostReader` `:on_route_enter` `:load` path does not honor read-pointer position

**File:** `lib/foglet_bbs/tui/screens/post_reader.ex:78-104, 324-332, 641-644`

**Issue:** Two distinct load paths exist:

1. `load_posts/2` (line 299) — the test-seam / direct-invocation path — uses `load_window_opts/2` which selects `:around` when a read pointer is available.
2. `update(:load, %State{thread_id: …}, ctx)` (line 90) — the reducer path used by `:on_route_enter` — uses `load_direction/1`, which only checks `load_intent` and never inspects `pending_read_positions`. It always emits `:initial` or `:last`.

The two paths give different selection behavior on the same state. A user re-entering a thread via the reducer path will land at index 0 (`:initial` window) even when their read pointer is at message 150 in a 200-post thread. The test-seam path correctly anchors on the pointer.

This may be intentional (the reducer path is fresh-load semantics; the App-callback path is pointer-aware). But the inconsistency is undocumented and partially breaks the "if you saw it, you read it" promise in the moduledoc when the reducer path is exercised.

**Fix:** Either:
- Make `update(:load, …)` consult `state.pending_read_positions[thread_id]` and emit `direction: :around, around_message_number: …` like `load_posts/2` does, **or**
- Document explicitly in the moduledoc that route-entry loads are always anchor-free and that pointer-driven load is only available through the `load_posts/2` callback path.

---

### IN-04: `Posts.list_reader_window` `:previous` direction with nil cursor returns ambiguous `has_next?`

**File:** `lib/foglet_bbs/posts.ex:115-128`

**Issue:** When called with `direction: :previous` and no `:before_message_number`, `cursor = nil`, and the desc query returns the last `limit + 1` posts unfiltered. `has_next?` is then computed as `posts != [] and reader_has_next?(thread_id, posts, nil)`. `reader_has_next?(_, [_|_], _)` returns `true`, so the function reports `has_next?: true` for the tail of the thread when there is no actual "next" window. Callers that rely on `has_next?` to enable pagination affordances will draw a "Next" hint that goes nowhere.

This is unlikely to be hit in production because `PostReader.load_adjacent_window/3` always passes a valid `before_message_number` for `:previous`. But the public API contract permits the nil case (per `Keyword.get(opts, :before_message_number, nil)`), and the result is misleading.

**Fix:** Mirror the BL-01 fix from `:next` — only consider `has_next?` true when there's a positive cursor:

```elixir
:previous ->
  cursor = Keyword.get(opts, :before_message_number, nil)
  rows = reader_rows(thread_id, before_message_number: cursor, order: :desc, limit: limit + 1)
  {window_rows, extra} = Enum.split(rows, limit)
  posts = Enum.reverse(window_rows)
  has_next? =
    posts != [] and is_integer(cursor) and cursor > 0 and
      reader_has_next?(thread_id, posts, cursor)
  reader_window(posts, direction, extra != [], has_next?)
```

---

### IN-05: `SessionAlias.promote_session/2` proceeds with current_user update even when session_pid is missing

**File:** `lib/foglet_bbs/tui/app/session_alias.ex:23-51`

**Issue:** When `state.session_pid` is not a pid, the function logs a warning and skips the call to `Foglet.Sessions.Supervisor.promote_guest_session/3` — but it still updates `state.current_user`, mutates `session_context.user`/`user_id`, and emits a `navigate(:main_menu)` effect. This leaves the session in a half-promoted state: the TUI thinks it's authenticated (so subsequent `permit?` checks may pass), but no row in the Session GenServer reflects this user. SSH-05 (one-session-per-user) cannot be enforced, and presence/heartbeat telemetry is silently lost.

This is reachable in tests (which often build `%App{}` without a session_pid) and theoretically reachable in production if `init/1` ran before the SSH layer attached the pid. Today no test asserts the half-state behavior, and production wires the pid before `set_user` fires, so this is more of an "isolation hazard" than a live bug.

**Fix:** Decide whether the no-pid case should be a no-op (refuse to promote) or proceed (current behavior). Either way, document it explicitly. If proceeding is correct, expand the `Logger.warning` text to explain the consequence (telemetry will be missing, one-session-per-user cannot be enforced), not just that it happened.

---

_Reviewed: 2026-04-30_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
