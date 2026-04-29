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
  critical: 0
  warning: 0
  info: 0
  total: 0
status: clean
remediated_findings:
  critical: 1
  warning: 1
remediation_commit: 9795ce2
---

# Phase 35: Code Review Report

**Reviewed:** 2026-04-28T20:39:33Z
**Depth:** standard
**Files Reviewed:** 15
**Status:** clean after remediation

## Summary

Reviewed the listed App, auth/home screen reducers, render fixtures, state modules, and focused tests. The initial pass found one blocker and one warning. Both were remediated in `9795ce2` by moving optional startup/reset domain work out of synchronous reducer/init paths and into the existing screen task-result boundary.

## Remediation

- `9795ce2` removes synchronous authenticated startup oneliner loading from `App.init/1`; initial MainMenu screen state is created without calling the domain boundary, and existing navigation/session paths still request bounded oneliner load tasks.
- `9795ce2` converts password reset delivery and reset-token consumption to `Effect.task/3` operations and handles their results through Login's `:reset_request` and `:reset_token` reducer clauses.
- Verification after remediation:
  - `rtk mix test test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/tui/app_test.exs` - passed
  - `rtk mix test test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/tui/screens/register_test.exs test/foglet_bbs/tui/screens/verify_test.exs test/foglet_bbs/tui/screens/main_menu_test.exs test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/layout_smoke_test.exs && rtk mix compile --warnings-as-errors` - passed
  - `rtk rg -n "defp do_update\\(\\{:(register_wizard|verify_event|login_result|load_oneliners|oneliners_loaded|open_oneliner_composer|submit_oneliner|oneliner_created|open_hide_oneliner_modal|submit_hide_oneliner|oneliner_hidden)" lib/foglet_bbs/tui/app.ex` - no matches
  - `rtk mix precommit` - blocked by unrelated `lib/foglet_bbs/tui/screens/thread_list.ex` alias-order Credo issue outside Phase 35.

## Remediated Critical Issues

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

## Remediated Warnings

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
