---
phase: 12
slug: account-ssh-key-management
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-04-24
---

# Phase 12 - Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit via Mix |
| **Config file** | `mix.exs` |
| **Quick run command** | `rtk mix test test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/accounts/ssh_key_test.exs test/foglet_bbs/tui/screens/account_test.exs test/foglet_bbs/ssh/cli_handler_test.exs` |
| **Full suite command** | `rtk mix precommit` |
| **Estimated runtime** | ~120 seconds |

---

## Sampling Rate

- **After every task commit:** Run the focused command for the touched subsystem from the map below.
- **After every plan wave:** Run `rtk mix test test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/accounts/ssh_key_test.exs test/foglet_bbs/tui/screens/account_test.exs test/foglet_bbs/ssh/cli_handler_test.exs`.
- **Before `$gsd-verify-work`:** `rtk mix precommit` must pass.
- **Max feedback latency:** 120 seconds for focused checks before full precommit.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 12-01-01 | 01 | 1 | KEYS-02, KEYS-03, KEYS-04 | T-12-01 / T-12-02 | Key mutations are scoped to the current user and duplicate key material is rejected. | unit | `rtk mix test test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/accounts/ssh_key_test.exs` | yes | pending |
| 12-01-02 | 01 | 1 | KEYS-05 | T-12-03 | Public-key authentication only accepts a registered key for an active user and updates `last_used_at` only on success. | unit | `rtk mix test test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/ssh/cli_handler_test.exs` | yes | pending |
| 12-02-01 | 02 | 2 | KEYS-01, KEYS-02, KEYS-03, KEYS-04 | T-12-04 | Account UI displays and mutates only the signed-in user's SSH keys through Accounts context APIs. | TUI unit | `rtk mix test test/foglet_bbs/tui/screens/account_test.exs` | yes | pending |
| 12-03-01 | 03 | 3 | KEYS-01, KEYS-02, KEYS-03, KEYS-04, KEYS-05 | T-12-05 | End-to-end focused coverage proves Account UI and SSH auth behavior satisfy all KEYS requirements. | integration/regression | `rtk mix test test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/accounts/ssh_key_test.exs test/foglet_bbs/tui/screens/account_test.exs test/foglet_bbs/ssh/cli_handler_test.exs` | yes | pending |

---

## Wave 0 Requirements

Existing ExUnit infrastructure covers all phase requirements.

---

## Manual-Only Verifications

All phase behaviors have automated verification.

---

## Validation Sign-Off

- [x] All tasks have automated verify commands or existing test infrastructure.
- [x] Sampling continuity: no 3 consecutive tasks without automated verify.
- [x] Wave 0 covers all missing references.
- [x] No watch-mode flags.
- [x] Feedback latency target is under 120 seconds for focused checks.
- [x] `nyquist_compliant: true` set in frontmatter.

**Approval:** approved 2026-04-24
