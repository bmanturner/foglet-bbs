---
phase: 40-verification-documentation
fixed_at: 2026-04-29T16:17:02Z
review_path: .planning/phases/40-verification-documentation/40-REVIEW.md
iteration: 1
findings_in_scope: 3
fixed: 3
skipped: 0
status: all_fixed
---

# Phase 40: Code Review Fix Report

**Fixed at:** 2026-04-29T16:17:02Z
**Source review:** .planning/phases/40-verification-documentation/40-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 3
- Fixed: 3
- Skipped: 0

## Fixed Issues

### CR-01: Successful password and verification auth bypass session promotion

**Files modified:** `lib/foglet_bbs/tui/app.ex`, `lib/foglet_bbs/tui/screens/login.ex`, `lib/foglet_bbs/tui/screens/register.ex`, `lib/foglet_bbs/tui/screens/verify.ex`
**Commit:** f1f37ad6
**Applied fix:** Final login, registration-to-main-menu, and verification success paths now emit `{:promote_session, user}`. The legacy `{:set_user, user}` App message delegates to the same promotion path so one-session-per-user replacement is preserved if any older caller still emits it.

### CR-02: User and screen PubSub subscriptions never update after initial mount

**Files modified:** `lib/foglet_bbs/tui/app.ex`, `lib/foglet_bbs/tui/pub_sub_forwarder.ex`, `test/foglet_bbs/tui/app_test.exs`
**Commit:** 347b0a3b, 9c779ca4, c7f45d4f
**Applied fix:** Verified in `vendor/raxol/lib/raxol/core/runtime/events/dispatcher.ex` that `setup_subscriptions/1` is called during dispatcher initialization and not after model updates. App subscriptions now install stable clock and PubSub forwarder subscriptions at startup. `PubSubForwarder` owns a dispatcher-specific control topic and refreshes Phoenix topic membership when App state changes the current user, route, or screen-declared topic interest.

### WR-01: Session-promotion tests assert the bypassed behavior

**Files modified:** `test/foglet_bbs/tui/screens/login_test.exs`, `test/foglet_bbs/tui/screens/register_test.exs`, `test/foglet_bbs/tui/screens/verify_test.exs`
**Commit:** 1cad4eaa
**Applied fix:** Updated login, registration, and verification success tests to assert `{:promote_session, user}` instead of `{:set_user, user}`.

## Skipped Issues

None.

## Verification

- `rtk mix test test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/app_runtime_contract_test.exs` — 144 tests, 0 failures
- `rtk mix test test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/tui/screens/register_test.exs test/foglet_bbs/tui/screens/verify_test.exs` — 114 tests, 0 failures
- `rtk mix test test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/tui/screens/register_test.exs test/foglet_bbs/tui/screens/verify_test.exs test/foglet_bbs/tui/app_runtime_contract_test.exs test/foglet_bbs/tui/app_test.exs` — 258 tests, 0 failures
- `rtk mix precommit` — passed

---

_Fixed: 2026-04-29T16:17:02Z_
_Fixer: the agent (gsd-code-fixer)_
_Iteration: 1_
