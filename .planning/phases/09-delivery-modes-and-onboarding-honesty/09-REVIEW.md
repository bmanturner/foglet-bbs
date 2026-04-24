---
phase: 09-delivery-modes-and-onboarding-honesty
reviewed: 2026-04-24T17:28:25Z
depth: standard
files_reviewed: 25
files_reviewed_list:
  - config/config.exs
  - config/runtime.exs
  - config/test.exs
  - lib/foglet_bbs/accounts.ex
  - lib/foglet_bbs/accounts/email.ex
  - lib/foglet_bbs/config.ex
  - lib/foglet_bbs/config/schema.ex
  - lib/foglet_bbs/mailer.ex
  - lib/foglet_bbs/tui/screens/login.ex
  - lib/foglet_bbs/tui/screens/register.ex
  - lib/foglet_bbs/tui/screens/sysop/site_form.ex
  - lib/foglet_bbs/tui/screens/verify.ex
  - lib/mix/tasks/foglet.user.reset_password.ex
  - mix.exs
  - priv/repo/seeds/config.exs
  - test/foglet_bbs/accounts/accounts_test.exs
  - test/foglet_bbs/config/schema_test.exs
  - test/foglet_bbs/config_test.exs
  - test/foglet_bbs/tui/screens/delivery_copy_test.exs
  - test/foglet_bbs/tui/screens/login_test.exs
  - test/foglet_bbs/tui/screens/register_test.exs
  - test/foglet_bbs/tui/screens/sysop/site_form_test.exs
  - test/foglet_bbs/tui/screens/sysop_test.exs
  - test/foglet_bbs/tui/screens/verify_test.exs
  - test/mix/tasks/foglet_user_reset_password_test.exs
findings:
  critical: 0
  warning: 2
  info: 0
  total: 2
status: issues_found
---

# Phase 09: Code Review Report

**Reviewed:** 2026-04-24T17:28:25Z
**Depth:** standard
**Files Reviewed:** 25
**Status:** issues_found

## Summary

Reviewed the delivery-mode, email verification, runtime config, TUI onboarding, and reset-password changes. The email/no-email copy avoids browser workflows and secrets remain in OTP/runtime env config, but two onboarding paths can leave users unable to complete verification.

## Warnings

### WR-01: Seeded Defaults Create An Invalid No-Email Verification State

**File:** `lib/foglet_bbs/config/schema.ex:87`
**Issue:** `delivery_mode` defaults to `"no_email"` while `require_email_verification` defaults to `true` at line 98. The sysop editor explicitly rejects this combination in `lib/foglet_bbs/tui/screens/sysop/site_form.ex:226`, but `priv/repo/seeds/config.exs:21` seeds both defaults directly. With these defaults, open registration persists the user and then fails verification delivery in `lib/foglet_bbs/tui/screens/register.ex:367-387`, leaving a newly-created unverified account without a usable delivery path.
**Fix:** Make the seeded defaults match one of the combinations that the sysop form allows, or enforce the pair during seeding. The least surprising no-email default is:
```elixir
%{
  key: "require_email_verification",
  type: :boolean,
  default: false,
  description:
    "When false, new registrations skip verify and existing confirmed_at: nil users gain access on login (Phase 6 D-01)",
  enum: nil,
  min: nil,
  max: nil
}
```
If verification must remain enabled by default, set `delivery_mode` to `"email"` only when SMTP is configured and keep no-email installs from requiring email verification.

### WR-02: Login Verification Generates But Does Not Deliver The Code

**File:** `lib/foglet_bbs/tui/screens/login.ex:399`
**Issue:** When an existing active but unconfirmed user logs in and `post_login_screen/1` returns `:verify`, `start_verify_flow/2` calls `Accounts.build_verify_code/1`. That persists a code but does not send email; in normal builds `maybe_log_verify_code/2` is a no-op. By contrast, registration correctly calls `Accounts.deliver_verification_code/1` before moving to `:verify`. A user who returns after registration, or whose first delivery failed after account creation, lands on the verify screen with no newly-delivered code unless they know to press `R`.
**Fix:** Use the delivery-aware account boundary here, and only enter the verify screen after delivery was attempted. For example:
```elixir
defp start_verify_flow(state, user) do
  case Accounts.deliver_verification_code(user) do
    {:ok, :attempted} ->
      {:update,
       %{
         state
         | current_user: user,
           current_screen: :verify,
           screen_state: Map.delete(state.screen_state || %{}, :verify)
       }, []}

    {:error, :unavailable} ->
      {:update,
       %{state | modal: %Foglet.TUI.Modal{type: :error, message: "Email verification is unavailable because email delivery is disabled."}}, []}

    {:error, _reason} ->
      {:update,
       %{state | modal: %Foglet.TUI.Modal{type: :error, message: "Verification instructions could not be sent. Please try again later."}}, []}
  end
end
```
Keep test/dev raw-code logging behind an explicit test helper or compile-time dev flag if that path is still needed for local workflows.

---

_Reviewed: 2026-04-24T17:28:25Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
