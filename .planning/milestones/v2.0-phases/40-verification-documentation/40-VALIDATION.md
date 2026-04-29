---
phase: 40
slug: verification-documentation
status: complete
nyquist_compliant: true
wave_0_complete: true
created: 2026-04-29
updated: 2026-04-29
---

# Phase 40 — Validation Strategy

> Per-phase validation contract for close-gate execution.

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit / Mix |
| **Config file** | `mix.exs`, `test/test_helper.exs` |
| **Quick run command** | `rtk mix test test/foglet_bbs/tui/screens/account_test.exs` |
| **Full suite command** | `rtk mix test` |
| **Estimated runtime** | Focused tests: seconds to minutes; full precommit: longer Dialyzer-inclusive gate |

## Sampling Rate

- **After blocker-fix tasks:** Run the focused file or files named by the task.
- **After legacy callback cleanup:** Run App runtime tests plus affected screen tests.
- **After breadcrumb/render work:** Run breadcrumb tests, layout smoke tests, and targeted `rtk mix foglet.tui.render` checks.
- **Before `$gsd-verify-work`:** `rtk mix test` and `rtk mix precommit` must be green or a blocker must be documented with evidence.
- **Max feedback latency:** Keep ordinary implementation tasks under one focused test command before broad gates.

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 40-01-01 | 01 | 1 | VERIFY-05 | — | N/A | regression | `rtk mix test test/foglet_bbs/tui/screens/account_test.exs` | yes | complete |
| 40-01-02 | 01 | 1 | VERIFY-05 | — | N/A | static/type | `rtk mix dialyzer` | yes | complete |
| 40-02-01 | 02 | 2 | VERIFY-03 | — | N/A | runtime contract | `rtk mix test test/foglet_bbs/tui/app_runtime_contract_test.exs test/foglet_bbs/tui/app_struct_test.exs test/foglet_bbs/tui/app_test.exs` | yes | complete |
| 40-03-01 | 03 | 2 | VERIFY-01 | — | N/A | chrome/layout | `rtk mix test test/foglet_bbs/tui/widgets/chrome/breadcrumb_migration_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` | yes | complete |
| 40-04-01 | 04 | 3 | VERIFY-02 | — | N/A | screen reducers | `rtk mix test test/foglet_bbs/tui/screens` | yes | complete |
| 40-05-01 | 05 | 4 | VERIFY-04 | — | N/A | docs/static | `rtk rg -n "screen contract|Foglet.TUI.Context|Foglet.TUI.Effect|init/1|update/3|render/2" lib/foglet_bbs/tui lib/foglet_bbs/tui/widgets/README.md` | yes | complete |
| 40-05-02 | 05 | 4 | VERIFY-01, VERIFY-05 | — | N/A | full gate | `rtk mix test && rtk mix precommit` | yes | complete |

## Wave 0 Requirements

- [x] Existing infrastructure covers the phase requirements. No new test framework is needed.
- [x] Phase 40 created evidence/summary artifacts mapping Phase 39 carry-forward items to closure evidence.

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Render smoke evidence table | VERIFY-01 | The commands are automated, but final evidence is a human-readable table of screen/size/result. | Run the targeted `rtk mix foglet.tui.render` commands and record result/delta notes in the Phase 40 summary. |
| Pre-existing blocker disposition | VERIFY-05 | Only a human can approve a remaining non-blocking pre-existing issue. | If any final gate fails, record command output, reason it is pre-existing/non-regressed, owner, and approval status. |

## Validation Sign-Off

- [x] All planned task groups have focused automated verification commands.
- [x] Sampling continuity avoids three consecutive implementation tasks without automated verification.
- [x] No watch-mode flags are required.
- [x] `nyquist_compliant: true` set in frontmatter.
- [x] Full suite and precommit results recorded during execution.

**Approval:** complete
