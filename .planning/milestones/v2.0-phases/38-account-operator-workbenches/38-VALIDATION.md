---
phase: 38
slug: account-operator-workbenches
status: complete
nyquist_compliant: true
wave_0_complete: true
created: 2026-04-29
updated: 2026-04-29
---

# Phase 38 — Validation Strategy

> Per-phase validation contract for Account, Moderation, and Sysop reducer migration.

## Test Infrastructure

| Property | Value |
|----------|-------|
| Framework | ExUnit / Mix |
| Quick run command | `rtk mix test test/foglet_bbs/tui/screens/account_test.exs` |
| Operator workbench command | `rtk mix test test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/screens/sysop_test.exs` |
| App integration command | `rtk mix test test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/app_runtime_contract_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` |

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | Evidence | Status |
|---------|------|------|-------------|-----------|-------------------|----------|--------|
| 38-01-01 | 01 | 1 | SCREEN-05 | reducer/effect | `rtk mix test test/foglet_bbs/tui/screens/account_test.exs` | `38-VERIFICATION.md` verifies Account reducer/effect ownership; Phase 40 account suite passed 62 tests. | complete |
| 38-02-01 | 02 | 1 | SCREEN-06 | reducer/effect | `rtk mix test test/foglet_bbs/tui/screens/moderation_test.exs` | `38-02-SUMMARY.md` records 50 tests passing; `38-VERIFICATION.md` verifies Moderation workspace and invite ownership. | complete |
| 38-03-01 | 03 | 1 | SCREEN-06 | reducer/effect | `rtk mix test test/foglet_bbs/tui/screens/sysop_test.exs` | `38-03-SUMMARY.md` records 103 tests passing; `38-VERIFICATION.md` verifies Sysop lifecycle, retry, nested forms, modal, and invite ownership. | complete |
| 38-04-01 | 04 | 2 | SCREEN-05, SCREEN-06 | integration | `rtk mix test test/foglet_bbs/tui/screens/account_test.exs test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/screens/sysop_test.exs test/foglet_bbs/tui/app_test.exs` | `38-04-SUMMARY.md` records 395 passed with two pre-existing BL-01 failures; Phase 40 later records account suite, full suite, and precommit passing. | complete |

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Result |
|----------|-------------|------------|--------|
| None | SCREEN-05, SCREEN-06 | Reducer/effect ownership and App routing are covered by automated tests and phase verification. | N/A |

## Validation Sign-Off

- [x] Account reducer/effect ownership has focused tests and later full close-gate evidence.
- [x] Moderation reducer/effect ownership has focused tests and phase verification evidence.
- [x] Sysop reducer/effect ownership has focused tests and phase verification evidence.
- [x] App integration routes workbench task results through generic screen task routing.
- [x] `nyquist_compliant: true` set in frontmatter.

**Approval:** complete
