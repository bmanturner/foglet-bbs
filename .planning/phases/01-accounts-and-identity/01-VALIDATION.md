---
phase: 1
slug: accounts-and-identity
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-18
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit (built-in) |
| **Config file** | `test/test_helper.exs` |
| **Quick run command** | `mix test test/foglet_bbs/accounts/` |
| **Full suite command** | `mix test` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `mix test test/foglet_bbs/accounts/`
- **After every plan wave:** Run `mix test`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 1-01-01 | 01 | 1 | IDNT-01 | — | Case-insensitive handle uniqueness enforced | unit | `mix test test/foglet_bbs/accounts/user_test.exs` | ❌ W0 | ⬜ pending |
| 1-01-02 | 01 | 1 | IDNT-02 | — | Password hashed with Argon2; plaintext never stored | unit | `mix test test/foglet_bbs/accounts/user_test.exs` | ❌ W0 | ⬜ pending |
| 1-01-03 | 01 | 1 | IDNT-03 | — | Password reset token single-use and expiry enforced | unit | `mix test test/foglet_bbs/accounts/user_token_test.exs` | ❌ W0 | ⬜ pending |
| 1-02-01 | 02 | 1 | IDNT-04 | — | Role promotion persisted correctly | unit | `mix test test/foglet_bbs/accounts/user_test.exs` | ❌ W0 | ⬜ pending |
| 1-02-02 | 02 | 2 | IDNT-05 | — | Deleted user posts rewritten to tombstone; PII removed | unit | `mix test test/foglet_bbs/accounts/user_test.exs` | ❌ W0 | ⬜ pending |
| 1-03-01 | 03 | 2 | IDNT-06 | — | SSH public key stored and associated correctly | unit | `mix test test/foglet_bbs/accounts/ssh_key_test.exs` | ❌ W0 | ⬜ pending |
| 1-04-01 | 04 | 3 | IDNT-07 | — | mix foglet.user.create creates a valid account | integration | `mix test test/mix/tasks/foglet_user_create_test.exs` | ❌ W0 | ⬜ pending |
| 1-04-02 | 04 | 3 | IDNT-08 | — | mix foglet.user.promote assigns correct role | integration | `mix test test/mix/tasks/foglet_user_promote_test.exs` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/foglet_bbs/accounts/user_test.exs` — stubs for IDNT-01, IDNT-02, IDNT-04, IDNT-05
- [ ] `test/foglet_bbs/accounts/user_token_test.exs` — stubs for IDNT-03
- [ ] `test/foglet_bbs/accounts/ssh_key_test.exs` — stubs for IDNT-06
- [ ] `test/mix/tasks/foglet_user_create_test.exs` — stubs for IDNT-07
- [ ] `test/mix/tasks/foglet_user_promote_test.exs` — stubs for IDNT-08

*All test files are new — existing infrastructure (ExUnit, Ecto sandbox) covers phase requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Password reset email delivery | IDNT-03 | Requires SMTP config or Swoosh adapter in dev | Start server, request reset, confirm email arrives and link works |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
