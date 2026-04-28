---
phase: 35-auth-home-screens
reviewed: 2026-04-28T20:39:33Z
depth: standard
files_reviewed: 15
files_reviewed_list:
  - lib/foglet_bbs/tui/app.ex
  - lib/foglet_bbs/tui/render_fixtures.ex
  - lib/foglet_bbs/tui/screens/login.ex
  - lib/foglet_bbs/tui/screens/main_menu.ex
  - lib/foglet_bbs/tui/screens/main_menu/state.ex
  - lib/foglet_bbs/tui/screens/register.ex
  - lib/foglet_bbs/tui/screens/register/state.ex
  - lib/foglet_bbs/tui/screens/verify.ex
  - lib/foglet_bbs/tui/screens/verify/state.ex
  - test/foglet_bbs/tui/app_test.exs
  - test/foglet_bbs/tui/layout_smoke_test.exs
  - test/foglet_bbs/tui/screens/login_test.exs
  - test/foglet_bbs/tui/screens/main_menu_test.exs
  - test/foglet_bbs/tui/screens/register_test.exs
  - test/foglet_bbs/tui/screens/verify_test.exs
findings:
  critical: 1
  warning: 1
  info: 0
  total: 2
status: issues_found
---

# Phase 35: Code Review Report

**Reviewed:** 2026-04-28T20:39:33Z
**Depth:** standard
**Files Reviewed:** 15
**Status:** issues_found

## Summary

Reviewed the listed App, auth/home screen reducers, render fixtures, state modules, and focused tests. The new screen-owned reducer model is mostly consistent, but two paths still bypass the App task/error boundary and can take down or stall the live SSH TUI during routine auth flows.

## Critical Issues

### CR-01: BLOCKER - Authenticated App Startup Can Crash On Optional Oneliner Load

**File:** `lib/foglet_bbs/tui/app.ex:1163`

**Issue:** `maybe_init_initial_screen_state/1` calls `oneliners_mod.list_recent_visible(5)` synchronously during `App.init/1` for authenticated users. Unlike the new `Effect.task` path at `app.ex:215-234`, this call is not protected by the task wrapper, so a transient Repo error, bad domain override, or any exception from the oneliner context crashes initialization before the TUI starts. An optional main-menu panel should not prevent an already-authenticated SSH session from opening.

**Fix:**
```elixir
defp maybe_init_initial_screen_state(%{current_screen: :main_menu, current_user: user} = state)
     when not is_nil(user) do
  main_menu_state =
    state
    |> build_context()
    |> Screens.MainMenu.init()
    |> Map.put(:oneliner_status, :loading)

  put_screen_state(state, :main_menu, main_menu_state)
end
```

Then trigger the existing `:load_oneliners` task through the same `route_screen_update/3` path used by navigation/set-user, or add a one-shot startup message that dispatches `{:screen_task_result, :main_menu, :load_oneliners, ...}` via `Effect.task`. Keep the data load inside `Foglet.TUI.Command.task/2` so failures become screen-local errors instead of init crashes.

## Warnings

### WR-01: WARNING - Password Reset Domain Calls Still Run Inside The Key Reducer

**File:** `lib/foglet_bbs/tui/screens/login.ex:683`

**Issue:** The login screen moved normal login, register, verify submit, verify resend, and oneliner work to `Effect.task`, but password reset request and token consumption still call the domain boundary directly from `update/3` (`Verification.request_password_reset_delivery/1` at line 683, `Verification.active_sysop_contact_emails/0` through line 703, and `Verification.consume_reset_token/2` at line 739). Any Repo/config/mail exception here bypasses the App task wrapper and can crash the live reducer while the user is pressing Enter. Even when it does not crash, these calls run on the UI process instead of returning a task result like the rest of the Phase 35 auth reducers.

**Fix:** Convert both reset submissions to task effects and handle their results through the existing `:reset_request` and `:reset_token` task-result clauses.

```elixir
effect =
  Effect.task(:reset_request, :login, fn ->
    case Foglet.Config.delivery_mode() do
      "email" ->
        _ = Verification.request_password_reset_delivery(email)
        {:ok, :email_dispatched}

      "no_email" ->
        {:ok, {:no_email_operator_assisted, Verification.active_sysop_contact_emails()}}
    end
  end)

{:update, LoginState.put(state, %{login_ss | error: nil}), [effect]}
```

Do the same for `consume_reset_token/2`, mapping task errors to the generic reset-token failure copy rather than letting reducer execution raise.

---

_Reviewed: 2026-04-28T20:39:33Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
