---
phase: 40-verification-documentation
reviewed: 2026-04-29T16:01:15Z
depth: standard
files_reviewed: 28
files_reviewed_list:
  - lib/foglet_bbs/tui/SCREEN_CONTRACT.md
  - lib/foglet_bbs/tui/app.ex
  - lib/foglet_bbs/tui/screen.ex
  - lib/foglet_bbs/tui/render_fixtures.ex
  - lib/foglet_bbs/tui/screens/login.ex
  - lib/foglet_bbs/tui/screens/register.ex
  - lib/foglet_bbs/tui/screens/verify.ex
  - lib/foglet_bbs/tui/screens/main_menu.ex
  - lib/foglet_bbs/tui/screens/board_list.ex
  - lib/foglet_bbs/tui/screens/account.ex
  - lib/foglet_bbs/tui/screens/moderation.ex
  - test/foglet_bbs/tui/app_runtime_contract_test.exs
  - test/foglet_bbs/tui/app_struct_test.exs
  - test/foglet_bbs/tui/app_test.exs
  - test/foglet_bbs/tui/layout_smoke_test.exs
  - test/foglet_bbs/tui/screens/login_test.exs
  - test/foglet_bbs/tui/screens/main_menu_test.exs
  - test/foglet_bbs/tui/screens/board_list_test.exs
  - test/foglet_bbs/tui/screens/thread_list_test.exs
  - test/foglet_bbs/tui/screens/post_reader_test.exs
  - test/foglet_bbs/tui/screens/post_composer_test.exs
  - test/foglet_bbs/tui/screens/new_thread_test.exs
  - test/foglet_bbs/tui/screens/account_test.exs
  - test/foglet_bbs/tui/screens/moderation_test.exs
  - test/foglet_bbs/tui/screens/sysop_test.exs
  - test/foglet_bbs/tui/widgets/chrome/breadcrumb_migration_test.exs
  - test/foglet_bbs/tui/widgets/chrome/screen_frame_test.exs
  - lib/foglet_bbs/tui/widgets/README.md
findings:
  critical: 2
  warning: 1
  info: 0
  total: 3
status: issues_found
---

# Phase 40: Code Review Report

**Reviewed:** 2026-04-29T16:01:15Z
**Depth:** standard
**Files Reviewed:** 28
**Status:** issues_found

## Summary

Reviewed the listed TUI contract, App shell, migrated screen modules, render fixtures, widget documentation, and focused tests. The implementation has two blocking runtime regressions: password/verification registration flows bypass one-session-per-user promotion, and App subscriptions are modeled as dynamic route/user state even though the runtime only starts them from the initial model.

## Critical Issues

### CR-01: Successful password and verification auth bypass session promotion

**File:** `lib/foglet_bbs/tui/screens/login.ex:227`, `lib/foglet_bbs/tui/screens/register.ex:409`, `lib/foglet_bbs/tui/screens/verify.ex:206`, `lib/foglet_bbs/tui/app.ex:496`

**Issue:** Auth-success paths emit `Effect.session({:set_user, user})`, and `App` handles that by only setting `current_user` and navigating to `:main_menu`. The code that enforces one-session-per-user is the separate `{:promote_session, user}` handler at `app.ex:632`, but the reviewed screens no longer emit that message. A user who logs in through the TUI or finishes email verification can therefore keep the guest session pid instead of promoting it through `Foglet.Sessions.Supervisor.promote_guest_session/2`, so existing sessions for the same user are not replaced.

**Fix:**
```elixir
# In final authentication success paths:
[Effect.session({:promote_session, user})]

# Or make the existing set_user path enforce the same invariant:
defp do_update({:set_user, user}, state) do
  do_update({:promote_session, user}, state)
end
```

### CR-02: User and screen PubSub subscriptions never update after initial mount

**File:** `lib/foglet_bbs/tui/app.ex:383`

**Issue:** `subscribe/1` computes heartbeat, clock, user PubSub, and active-screen topics from the current model. However, Raxol starts App subscriptions only once during dispatcher initialization from the initial model. That means a password-login session initialized as `:login` never installs `:main_menu_clock_tick` or `PubSubForwarder` for `user:<id>` after `{:set_user, user}`. Likewise, route-specific topics from `BoardList.subscriptions/2` and other screens are only active if that screen was the initial route; navigating to board/thread screens later will not subscribe to their topics.

**Fix:** Do not rely on `subscribe/1` for model-dependent topics unless the runtime has an explicit resubscribe mechanism. Keep only stable subscriptions there, then manage dynamic PubSub membership inside a long-lived forwarder that receives route/user updates from `App.update/2`, or add and call a runtime subscription-refresh API whenever `current_user`, `current_screen`, or route params change.

## Warnings

### WR-01: Session-promotion tests assert the bypassed behavior

**File:** `test/foglet_bbs/tui/screens/login_test.exs:1188`

**Issue:** The login tests are named and commented as `promote_session` coverage, but the assertions expect `{:set_user, returned_user}`. This lets CR-01 pass while preserving test names that imply the one-session-per-user invariant is protected.

**Fix:** Update the tests for login, register-to-main-menu, and verify-success flows to assert `{:promote_session, user}` or to assert that `App.update/2` calls the promotion path when handling final auth success.

---

_Reviewed: 2026-04-29T16:01:15Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
