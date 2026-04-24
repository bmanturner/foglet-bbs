---
phase: 14
slug: launch-hygiene-and-operator-notes
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-24
---

# Phase 14 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit with project Mix aliases |
| **Config file** | `test/test_helper.exs` |
| **Quick run command** | `rtk mix test test/foglet_bbs/tui/screens/sysop_test.exs test/foglet_bbs/tui/screens/sysop/site_form_test.exs test/foglet_bbs/config test/mix/tasks` |
| **Full suite command** | `rtk mix test` |
| **Estimated runtime** | ~60 seconds targeted, full suite varies with DB/setup |

---

## Sampling Rate

- **After every task commit:** Run the targeted command for touched areas plus `rtk mix format --check-formatted` when formatting is affected.
- **After every plan wave:** Run `rtk mix test` for behavior changes spanning contexts, screens, tasks, or docs-backed copy tests.
- **Before `$gsd-verify-work`:** `rtk mix precommit` must pass.
- **Max feedback latency:** 120 seconds for targeted test feedback.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 14-01-01 | 01 | 1 | HYGN-01 | T-14-01 | Non-sysop config mutation remains blocked by context authorization | screen/unit | `rtk mix test test/foglet_bbs/tui/screens/sysop_test.exs test/foglet_bbs/tui/screens/sysop/site_form_test.exs test/foglet_bbs/config` | partial | pending |
| 14-02-01 | 02 | 1 | HYGN-02 | T-14-02 | Terminal and task copy do not claim unsupported browser, webhook, digest, or full case-management behavior | context/screen/task | `rtk mix test test/foglet_bbs/accounts test/foglet_bbs/boards test/foglet_bbs/posts test/foglet_bbs/threads test/foglet_bbs/tui/screens test/mix/tasks` | partial | pending |
| 14-03-01 | 03 | 2 | HYGN-03 | T-14-03 | Operator notes distinguish SMTP mode from no-email mode and do not expose secrets through DB-backed config | doc/audit | `rg -n "SMTP|no-email|no_email|delivery_mode|break-glass|SSH-first|docs/" README.md` | yes | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

- [ ] Add or update a config accountability test or ledger that classifies every `Foglet.Config.Schema.entries/0` key with a launch-facing reason.
- [ ] Add launch-copy audit evidence for forbidden claims across TUI screens, Mix tasks, and `README.md`.
- [ ] Add README verification for SMTP mode, no-email mode, break-glass tasks, SSH-first operation, launch caveats, and nested-doc status.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Operator can understand current launch caveats from root README | HYGN-03 | Documentation clarity needs human review in addition to grep checks | Read `README.md` after edits and confirm it does not imply browser admin, webhook notifications, email digests, delivery retry queues, or full case-management moderation for v1.2. |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies.
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify.
- [ ] Wave 0 covers all missing references.
- [ ] No watch-mode flags.
- [ ] Feedback latency < 120s for targeted feedback.
- [ ] `nyquist_compliant: true` set in frontmatter once execution proves coverage.

**Approval:** pending
