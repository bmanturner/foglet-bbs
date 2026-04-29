---
phase: 38-account-operator-workbenches
reviewed: 2026-04-29T02:21:12Z
depth: standard
files_reviewed: 9
files_reviewed_list:
  - lib/foglet_bbs/tui/app.ex
  - lib/foglet_bbs/tui/screens/account.ex
  - lib/foglet_bbs/tui/screens/moderation.ex
  - lib/foglet_bbs/tui/screens/sysop.ex
  - lib/foglet_bbs/tui/screens/main_menu.ex
  - test/foglet_bbs/tui/app_test.exs
  - test/foglet_bbs/tui/screens/account_test.exs
  - test/foglet_bbs/tui/screens/moderation_test.exs
  - test/foglet_bbs/tui/screens/sysop_test.exs
findings:
  critical: 1
  warning: 1
  info: 0
  total: 2
status: issues_found
---

# Phase 38: Code Review Report

**Reviewed:** 2026-04-29T02:21:12Z
**Depth:** standard
**Files Reviewed:** 9
**Status:** issues_found

## Summary

Reviewed the Phase 38 TUI app routing, account, moderation, sysop, main menu, and matching test files. The reviewed source paths mostly route privileged work through existing context/action boundaries, but the test suite is not currently shippable: two reviewed tests still drive removed App messages, and the app test setup repeatedly falls through to DB-backed config reads without sandbox ownership.

Focused verification run:

`rtk mix test test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/screens/account_test.exs test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/screens/sysop_test.exs`

Result: 350 tests, 2 failures.

## Critical Issues

### CR-01: BLOCKER - Reviewed Account Tests Drive Removed App Messages And Fail

**File:** `test/foglet_bbs/tui/screens/account_test.exs:1229`

**Issue:** The BL-01 tests call `App.update({:open_oneliner_composer}, state)` and later `{:oneliner_created, ...}` / `{:open_hide_oneliner_modal, ...}` / `{:oneliner_hidden, ...}`. Those messages are not handled by `lib/foglet_bbs/tui/app.ex`; the current MainMenu path opens forms via key events and handles async results through `{:screen_task_result, :main_menu, :submit_oneliner | :submit_hide_oneliner, ...}`. As a result, `with_modal` has no modal, Enter is routed to the main menu, and both tests fail with `submitting.modal == nil`. This blocks the focused Phase 38 test suite.

**Fix:**
Drive the current MainMenu/App contract instead of the removed legacy messages. For example:

```elixir
{with_modal, []} = App.update({:key, %{key: :char, char: "O"}}, state)
# fill/submit the ModalForm as needed
{after_error, []} =
  App.update(
    {:screen_task_result, :main_menu, :submit_oneliner,
     {:ok, {:error, :same_user_latest_visible}}},
    submitting
  )
```

For hide-oneliner coverage, seed a hideable selected oneliner, open the form through `H`, and assert the `:submit_hide_oneliner` task-result path. Remove the obsolete `:open_*` and `:oneliner_*` message assertions from this reviewed file.

## Warnings

### WR-01: WARNING - App Tests Miss Invite Config Seeding And Produce Sandbox Ownership Warnings

**File:** `test/foglet_bbs/tui/app_test.exs:82`

**Issue:** The App test setup seeds several ETS config keys but omits `invite_code_generators`. Phase 38 navigation/view tests then render Account/Moderation/Sysop surfaces whose visibility checks call `ShellVisibility.invites_visible?/2`; with no session policy and no ETS value, that falls through to `Foglet.Config.invite_code_generators/0`, causing repeated Ecto sandbox ownership warnings in this async `ExUnit.Case`. The warning is rescued by production code, so tests can pass while hiding accidental DB-backed config access in TUI render paths.

**Fix:**
Seed the invite policy in the App test setup, or include it in the fake session contexts that render operator shells:

```elixir
setup do
  Config.init_cache()
  :ets.insert(:foglet_config, {"registration_mode", "open"})
  :ets.insert(:foglet_config, {"delivery_mode", "no_email"})
  :ets.insert(:foglet_config, {"require_email_verification", false})
  :ets.insert(:foglet_config, {"email_verify_resend_cooldown_seconds", 60})
  :ets.insert(:foglet_config, {"invite_code_generators", "sysop_only"})
  :ok
end
```

---

_Reviewed: 2026-04-29T02:21:12Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
