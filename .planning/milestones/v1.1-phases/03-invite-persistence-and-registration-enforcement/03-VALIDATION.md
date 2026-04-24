---
phase: 03
slug: invite-persistence-and-registration-enforcement
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-04-24
---

# Phase 03 - Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit with Ecto SQL Sandbox through the existing Phoenix test setup |
| **Config file** | Existing project test support |
| **Quick run command** | `mix test test/foglet_bbs/accounts/invite_test.exs test/foglet_bbs/accounts/invite_registration_test.exs` |
| **Full suite command** | `mix test` |
| **Estimated runtime** | ~30 seconds for focused tests; full suite depends on local DB state |

---

## Sampling Rate

- **After every task commit:** Run `mix test test/foglet_bbs/accounts/invite_test.exs test/foglet_bbs/accounts/invite_registration_test.exs`
- **After every plan wave:** Run `mix test`
- **Before `$gsd-verify-work`:** `mix precommit` must be green
- **Max feedback latency:** 60 seconds for focused tests

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 03-01-01 | 01 | 1 | INVT-02 | T-03-01 | Invite codes are high-entropy generated values with unique DB enforcement | integration | `mix test test/foglet_bbs/accounts/invite_test.exs` | No - Wave 0 | pending |
| 03-01-02 | 01 | 1 | INVT-03 | T-03-02 | Status is derived from persisted consumed/revoked timestamps | integration | `mix test test/foglet_bbs/accounts/invite_test.exs` | No - Wave 0 | pending |
| 03-01-03 | 01 | 1 | INVT-04 | T-03-03 | Generate/revoke side effects enforce `Foglet.Authorization` in the Accounts context | integration | `mix test test/foglet_bbs/accounts/invite_test.exs` | No - Wave 0 | pending |
| 03-02-01 | 02 | 2 | INVT-05 | T-03-04 | Invite-only registration rejects unavailable codes with an `invite_code` changeset error | integration | `mix test test/foglet_bbs/accounts/invite_registration_test.exs` | No - Wave 0 | pending |
| 03-02-02 | 02 | 2 | INVT-05 | T-03-05 | Invite consumption is atomic with user creation and prevents double redemption | integration/concurrency | `mix test test/foglet_bbs/accounts/invite_registration_test.exs` | No - Wave 0 | pending |

---

## Wave 0 Requirements

- [ ] `test/foglet_bbs/accounts/invite_test.exs` - covers INVT-02, INVT-03, and INVT-04.
- [ ] `test/foglet_bbs/accounts/invite_registration_test.exs` - covers INVT-05 and transactional redemption.
- [ ] `test/support/accounts_fixtures.ex` - invite helpers plus sysop/mod/user actors if existing fixtures do not already cover them.
- [ ] Dependency verification that `Foglet.Config.invite_generation_per_user_limit/0` exists after Phase 2 lands.

---

## Manual-Only Verifications

All phase behaviors have automated verification.

---

## Validation Sign-Off

- [x] All tasks have automated verify commands or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all missing references
- [x] No watch-mode flags
- [x] Feedback latency target < 60s for focused tests
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-04-24
