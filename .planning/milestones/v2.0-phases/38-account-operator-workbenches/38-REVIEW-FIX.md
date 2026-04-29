---
phase: 38-account-operator-workbenches
fixed_at: 2026-04-29T02:30:28Z
review_path: .planning/phases/38-account-operator-workbenches/38-REVIEW.md
iteration: 1
findings_in_scope: 2
fixed: 2
skipped: 0
status: all_fixed
---

# Phase 38: Code Review Fix Report

**Fixed at:** 2026-04-29T02:30:28Z
**Source review:** `.planning/phases/38-account-operator-workbenches/38-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 2
- Fixed: 2
- Skipped: 0

## Fixed Issues

### CR-01: Account tests still drive removed App messages

**Files modified:** `test/foglet_bbs/tui/screens/account_test.exs`
**Commit:** `11e5fe7`
**Applied fix:** Reworked the BL-01 account tests to open MainMenu modals through current `O`/`H` key events, seed a hideable oneliner through the MainMenu load result path, and drive async failures through `{:screen_task_result, :main_menu, :submit_oneliner | :submit_hide_oneliner, ...}`.

### WR-01: App tests omit invite_code_generators setup

**Files modified:** `test/foglet_bbs/tui/app_test.exs`
**Commit:** `ca2e52f`
**Applied fix:** Seeded `invite_code_generators` in the App test ETS config setup so operator shell visibility checks do not fall through to DB-backed config reads in async tests.

## Tests

`rtk mix format test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/screens/account_test.exs`

`rtk mix test test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/screens/account_test.exs test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/screens/sysop_test.exs`

Result: 350 tests, 0 failures.

---

_Fixed: 2026-04-29T02:30:28Z_
_Fixer: the agent (gsd-code-fixer)_
_Iteration: 1_
