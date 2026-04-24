---
phase: 05
slug: account-preferences-and-live-session-refresh
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-04-24
---

# Phase 05 - Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit via `mix test` |
| **Config file** | `mix.exs` / `test/test_helper.exs` |
| **Quick run command** | `mix test test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/sessions/session_test.exs test/foglet_bbs/tui/screens/account_test.exs` |
| **Full suite command** | `mix precommit` |
| **Estimated runtime** | ~120 seconds quick, ~900 seconds full |

---

## Sampling Rate

- **After every task commit:** Run `mix test` for the directly touched test file(s).
- **After every plan wave:** Run `mix test test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/sessions/session_test.exs test/foglet_bbs/tui/screens/account_test.exs`.
- **Before `$gsd-verify-work`:** `mix precommit` must be green.
- **Max feedback latency:** 15 minutes for full precommit, under 3 minutes for targeted tests.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 05-01-01 | 01 | 1 | ACCT-03, ACCT-04, ACCT-05 | T-05-01 | Invalid timezone, time format, and theme values are rejected at the Accounts boundary. | unit/integration | `mix test test/foglet_bbs/accounts/accounts_test.exs` | ✅ | ⬜ pending |
| 05-01-02 | 01 | 1 | ACCT-02 | T-05-02 | Private profile fields are bounded and blanks normalize to nil without casting unrelated account fields. | unit/integration | `mix test test/foglet_bbs/accounts/accounts_test.exs` | ✅ | ⬜ pending |
| 05-02-01 | 02 | 1 | ACCT-06 | T-05-03 | Session preference refresh happens through a public Session API, not direct GenServer state mutation. | unit | `mix test test/foglet_bbs/sessions/session_test.exs` | ✅ | ⬜ pending |
| 05-03-01 | 03 | 2 | ACCT-02, ACCT-03, ACCT-04, ACCT-05 | T-05-04 | Account form errors are visible and failed saves do not persist or refresh session state. | TUI unit | `mix test test/foglet_bbs/tui/screens/account_test.exs` | ✅ | ⬜ pending |
| 05-03-02 | 03 | 2 | ACCT-05 | T-05-05 | Unsaved theme preview affects Account rendering only; cancel/revert leaves saved user and session theme unchanged. | TUI unit | `mix test test/foglet_bbs/tui/screens/account_test.exs` | ✅ | ⬜ pending |
| 05-04-01 | 04 | 2 | ACCT-06 | T-05-03 | Successful Account save updates current_user, session_context, and Session GenServer state together. | integration | `mix test test/foglet_bbs/tui/screens/account_test.exs test/foglet_bbs/sessions/session_test.exs` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Existing ExUnit infrastructure covers the phase.
- [ ] Planner must include targeted tests before or alongside implementation tasks for Accounts, Session, and Account TUI behavior.
- [ ] Planner must include dependency verification after adding Timex, using `mix deps.get` if needed and `mix compile --warnings-as-errors`.

---

## Manual-Only Verifications

All phase behaviors have automated verification. Manual exploratory SSH/TUI smoke testing may supplement but must not replace ExUnit coverage.

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 15 minutes
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-04-24
