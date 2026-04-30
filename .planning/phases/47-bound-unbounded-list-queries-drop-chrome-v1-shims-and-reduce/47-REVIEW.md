---
phase: 47-bound-unbounded-list-queries-drop-chrome-v1-shims-and-reduce
reviewed: 2026-04-30T15:12:01Z
depth: standard
iteration: 6
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
  warning: 3
  info: 3
  total: 6
status: issues_found
---

# Phase 47: Code Review Report (Iteration 6 — fresh pass)

**Reviewed:** 2026-04-30T15:12:01Z
**Depth:** standard
**Status:** issues_found

## Summary

Iteration-5 fixes have all landed. The previously-flagged WR-01 (Register
verify-delivery catch-all), WR-02 (ThreadList unsupported `threads_mod`
gate), and IN-02 (PostReader pointer-past-window selection) are resolved
at the source level. The two skipped Info items (IN-01 routing nil-return
and IN-03 LoginForm app-state wrap shape) are tracked as no-action per the
prior reviewer's explicit guidance and remain that way here.

This fresh pass surfaces a **family of non-exhaustive `case`/clause bugs
in the post-auth screens** — the same defect class WR-01 fixed for
Register but not yet swept across siblings. `LoginForm.login_success_result/3`
has a non-exhaustive `case` on `deliver_verification_code/1`,
`Verify.handle_verify_resend_result/2` is non-exhaustive on the same call,
and `ResetRequest.dispatch_reset_request/3` has a non-exhaustive `case`
on `Foglet.Config.delivery_mode/0`. Each of these will raise
`CaseClauseError` on an unanticipated success/return shape, surfacing as
either a generic "unavailable" modal (Login — masks the real fault as a
network error) or a misleading "Please enter an email" modal
(ResetRequest — misdescribes a config-mode fault as user input error).

Three Info items: the Moderation `jump_hint/1` clause has no fallback for
`n <= 0`, the Account `jump_hint/1` has the same shape, and a small
correctness comment about `apply_flush_result` partial-failure handling.

No security, data-loss, or authorization issues were identified. Bounded
list queries (`@page_size = 50`, `@max_page_size = 500`) are correctly
applied at the SQL layer in `Threads.list_threads_query/3`.

## Warnings

### WR-01: `LoginForm.login_success_result/3` non-exhaustive case on `deliver_verification_code/1`

**File:** `lib/foglet_bbs/tui/screens/login/login_form.ex:186-193`

**Issue:** The `case verification_mod.deliver_verification_code(user)` has
exactly four explicit clauses:

```elixir
case verification_mod.deliver_verification_code(user) do
  {:ok, :attempted} -> {:ok, user, :verify, :attempted}
  {:error, :unavailable} -> {:ok, user, :verify, :unavailable}
  {:error, :delivery_failed} -> {:ok, user, :verify, :delivery_failed}
  {:error, %Ecto.Changeset{}} -> {:ok, user, :verify, :changeset_error}
end
```

This is the same class of defect that iteration-5 WR-01 fixed for
`Register.handle_register_result/2`. If `deliver_verification_code/1`
ever returns a shape outside the four listed (e.g., a future
`{:ok, :queued}`, `{:error, :rate_limited}`, an unexpected exception
return tuple, or a test fixture that returns `{:error, %SomeOther{}}`),
the case raises `CaseClauseError`. That exception propagates out of the
task closure to `Foglet.TUI.Command.task/2`'s rescue, which converts it
to `{:task_error, :login, formatted_stacktrace}`. The error is then
either:

1. Routed to `LoginForm.handle_task_result({:error, _}, …)` (the WR-01
   iteration-4 catch-all) which surfaces "Login is temporarily
   unavailable" — masking a contract drift between `Verification` and
   `LoginForm` as a transient service outage; OR
2. Routed to `App.do_update({:task_error, :login, reason}, state)` which
   shows a generic "Something went wrong while trying to login" modal.

Either way, the bug is silently re-categorized as a transient fault,
making the contract-drift breadcrumb invisible. This contradicts the
WR-02 (iteration 4) "surface unanticipated auth-error tuples" posture
applied a few lines above (`authenticate_login/5`'s `else` branch
explicitly logs unknown shapes).

**Fix:** Add an explicit catch-all that logs and falls back to
`:delivery_failed` (the closest existing semantic):

```elixir
defp login_success_result(verification_mod, user, :verify) do
  case verification_mod.deliver_verification_code(user) do
    {:ok, :attempted} -> {:ok, user, :verify, :attempted}
    {:error, :unavailable} -> {:ok, user, :verify, :unavailable}
    {:error, :delivery_failed} -> {:ok, user, :verify, :delivery_failed}
    {:error, %Ecto.Changeset{}} -> {:ok, user, :verify, :changeset_error}
    other ->
      Logger.warning(
        "[Login] unexpected deliver_verification_code shape #{inspect(other)}; " <>
          "treating as :delivery_failed"
      )
      {:ok, user, :verify, :delivery_failed}
  end
end
```

This mirrors the `authenticate_login/5` defensive treatment a few lines
up and the iteration-5 Register WR-01 fix for the symmetric register flow.

---

### WR-02: `Verify.handle_verify_resend_result/2` non-exhaustive on unexpected delivery shapes

**File:** `lib/foglet_bbs/tui/screens/verify.ex:241-268`

**Issue:** The `:verify_resend` task body calls
`verification_mod.deliver_verification_code(user)`
(`verify.ex:188-190`), the same call as Login WR-01 above. The result
handler has exactly three clauses:

```elixir
defp handle_verify_resend_result({:ok, :attempted}, vs) do … end
defp handle_verify_resend_result({:error, :unavailable}, vs) do … end
defp handle_verify_resend_result({:error, _reason}, vs) do … end
```

But `deliver_verification_code/1` is documented (per Login's
`login_success_result/3`) to also return `{:error, :delivery_failed}`
and `{:error, %Ecto.Changeset{}}`. Both of those match
`{:error, _reason}` so they are absorbed into the generic "Please try
again later" modal — that is OK.

The real gap is `{:ok, _other}` (e.g., a future `{:ok, :queued}` or any
non-`:attempted` ok shape). It does not match any clause and raises
`FunctionClauseError`. Propagation: the dispatch site is
`update({:task_result, :verify_resend, {:ok, result}}, …)`
(`verify.ex:138-140`) which calls `handle_verify_resend_result(result, …)`
directly — the FunctionClauseError raises out of `update/3` and crashes
the screen reducer. Routing's `route_screen_update/3` does not rescue,
so the crash propagates to the Raxol runtime.

This is the same class as iteration-5 Register WR-01 — an unanticipated
success shape silently becomes a fault. Worse than Register's case
because there is no `{:task_error, …}` modal fallback wired for
`:verify_resend` at the App level.

**Fix:** Add a catch-all clause for `{:ok, _other}` that mirrors the
iteration-5 Register fix:

```elixir
defp handle_verify_resend_result({:ok, _other}, vs) do
  require Logger

  Logger.warning(
    "[Verify] unexpected resend delivery shape; treating as :attempted"
  )

  modal = %Foglet.TUI.Modal{
    type: :info,
    message: "If email delivery is available, new verification instructions have been sent."
  }

  new_vs = VerifyState.after_resend(vs, resend_cooldown_seconds())
  {new_vs, [Effect.open_modal(modal)]}
end
```

The same gap exists in `handle_verify_submit_result/3` (`verify.ex:208-239`)
for `verify_email_code/2`'s success shape — only `{:ok, confirmed}` is
handled, not e.g. `{:ok, %User{}}` returned bare or `{:ok, user, _meta}`.
The four error clauses including the `{:error, _reason}` catch-all cover
the failure side, but the success side has no catch-all — a future shape
change there raises `FunctionClauseError` for the same reason.

---

### WR-03: `ResetRequest.dispatch_reset_request/3` non-exhaustive on `Foglet.Config.delivery_mode/0`

**File:** `lib/foglet_bbs/tui/screens/login/reset_request.ex:120-138`

**Issue:** The submit closure is:

```elixir
case Foglet.Config.delivery_mode() do
  "email" ->
    _ = verification_mod.request_password_reset_delivery(email)
    :email_dispatched

  "no_email" ->
    {:no_email_operator_assisted, verification_mod.active_sysop_contact_emails()}
end
```

There are exactly two clauses. If `Foglet.Config.delivery_mode/0` ever
returns any other string (e.g., `"disabled"`, `"smtp_only"`, a future
mode, a typo in the seeded config, or a Schema migration that admits a
new value), the case raises `CaseClauseError`. The exception propagates
out of the task closure, becomes a `{:task_error, :reset_request, …}`,
and is caught by `handle_task_result({:error, _reason}, …)` at lines
88-90 — which sets `error: @reset_invalid_email_message` ("Please enter
an email address (for example: name@example.test).").

The user is told their **email is malformed** when in fact the **server's
delivery mode is misconfigured**. This is a misleading error class
escalation — same iteration-1 / iteration-2 surface fault category that
WR-04 (Posts.normalize_reader_direction/1) and WR-06 (reader_rows_around)
addressed by adding `Logger.warning` + a defensible fallback.

**Fix:** Add a catch-all clause that logs and falls back to the safer
mode (no-email operator-assisted, since email is the riskier path that
might silently swallow the request):

```elixir
case Foglet.Config.delivery_mode() do
  "email" ->
    _ = verification_mod.request_password_reset_delivery(email)
    :email_dispatched

  "no_email" ->
    {:no_email_operator_assisted, verification_mod.active_sysop_contact_emails()}

  other ->
    require Logger
    Logger.warning(
      "[Login.ResetRequest] unknown delivery_mode #{inspect(other)}; " <>
        "treating as no_email"
    )
    {:no_email_operator_assisted, verification_mod.active_sysop_contact_emails()}
end
```

This preserves the user-facing behavior (operator-assisted copy) while
surfacing the misconfiguration in logs, instead of presenting the user
with a "your email is malformed" lie.

## Info

### IN-01: `Moderation.jump_hint/1` has no fallback clause for `n <= 0`

**File:** `lib/foglet_bbs/tui/screens/moderation.ex:222`

**Issue:** `jump_hint/1` is defined with a single guarded clause:

```elixir
defp jump_hint(n) when is_integer(n) and n > 0, do: "1-#{n}"
```

No fallback. The caller is `key_list/1`:

```elixir
%{key: jump_hint(length(tab_labels_from_tabs(ss.tabs))), label: "Jump", priority: 10}
```

In normal operation `synced_screen_state/1` rebuilds tabs from
`State.tab_labels(...)` so `ss.tabs` is well-formed and `length(...)`
returns 5 or 6. But the iteration-3 IN-03 fallback for
`tab_labels_from_tabs/1` (lines 399-403) explicitly defends against a
malformed `%Tabs{}` struct by returning `[]`. If that defensive clause
ever fires, `length([]) = 0`, and `jump_hint(0)` raises
`FunctionClauseError`. The IN-03 defense was added precisely so the
moderation screen does not crash — but `key_list/1` then crashes anyway,
defeating the fix.

This is reachable only if the `%Tabs{}` struct is corrupted between
`synced_screen_state/1` and `key_list/1` (which it is not in the current
call ordering), OR if `key_list/1` is ever called from a code path that
does not run `synced_screen_state/1` first. Today the only caller is
`render_authorized/1` which runs sync first, so this is latent — but the
IN-03 fallback is dead-code defense without this companion fix.

**Fix:** Add a fallback clause:

```elixir
defp jump_hint(n) when is_integer(n) and n > 0, do: "1-#{n}"
defp jump_hint(_), do: "1"
```

The same shape repeats in `Account.Render.jump_hint/1`
(`account/render.ex:70`) — see IN-02.

---

### IN-02: `Account.Render.jump_hint/1` has the same `n <= 0` gap

**File:** `lib/foglet_bbs/tui/screens/account/render.ex:70`

**Issue:** Same shape as IN-01:

```elixir
defp jump_hint(n) when is_integer(n) and n > 0, do: "1-#{n}"
```

The caller chain is `key_bar/1` → `tab_labels(ss)` → `length(...)` →
`jump_hint/1`. `tab_labels/1` is:

```elixir
defp tab_labels(%State{tabs: %Tabs{raxol_state: raxol_state}}) do
  raxol_state |> Map.get(:tabs, []) |> Enum.map(&Map.fetch!(&1, :label))
end
```

If `raxol_state.tabs` is `[]` (e.g., a transient state during tab
re-init), `tab_labels` returns `[]`, `length` is 0, and
`jump_hint(0)` crashes the render. Less likely than IN-01 because there
is no equivalent defensive `_unknown -> []` fallback feeding it (in
fact `Map.fetch!` will raise `KeyError` first if a tab map is missing
`:label`), but the defensive shape is still incomplete.

**Fix:** Same as IN-01:

```elixir
defp jump_hint(n) when is_integer(n) and n > 0, do: "1-#{n}"
defp jump_hint(_), do: "1"
```

Optionally apply the same shape to `tab_labels/1` to use
`Map.get(&1, :label, "?")` instead of `Map.fetch!` so a malformed tab
shape does not crash the screen.

---

### IN-03: `PostReader.apply_flush_result/4` clears no pointer state on partial failure

**File:** `lib/foglet_bbs/tui/screens/post_reader.ex:522-539`

**Issue:** The flush helper:

```elixir
defp apply_flush_result(state, flush_ctx, board_result, thread_result) do
  if flush_result_ok?(board_result) and flush_result_ok?(thread_result) do
    # clear pending_read_positions[thread_id]
  else
    Logger.warning("flush_read_pointers: flush failed — board: #{inspect(board_result)}, thread: #{inspect(thread_result)}")
    {state, []}
  end
end
```

The all-or-nothing invariant is:

- Both succeed → clear local pending read position (good).
- Either fails → keep entire local pending read position so the next
  transition retries.

Edge case: if `board_result` succeeds (`{:ok, _}`) and `thread_result`
fails, the next retry will re-attempt the **board** flush as well, even
though it already succeeded. `Boards.advance_board_read_pointer/3`
(verified in `boards.ex` for monotonicity) is idempotent against
move-forward, so a duplicate forward call is benign. But a duplicate
call against an already-advanced pointer is still wasteful — the screen
keeps re-issuing it on every transition until the thread flush
eventually succeeds.

**Fix:** No change required for Phase 47. Tracked here so the partial-
success cleanup is a deliberate decision rather than an oversight. If
flush failures become frequent in production, consider splitting the
clear into per-side atomic units (clear only the slot whose flush
succeeded) — but that is a Phase 48+ optimization, not a correctness
defect. The current "retry both" behavior is safe given the
monotonic-merge contract on both pointer rows.

---

_Reviewed: 2026-04-30T15:12:01Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
_Iteration: 6 — fresh pass against post-iteration-5 code state_
