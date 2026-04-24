---
phase: 04
slug: shared-invite-surface-activation
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-04-23
---

# Phase 04 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit built into Elixir 1.19.5 |
| **Config file** | `test/test_helper.exs`; Ecto SQL sandbox manual mode |
| **Quick run command** | `mix test test/foglet_bbs/tui/screens/shared/invites_surface_test.exs test/foglet_bbs/tui/screens/account_test.exs test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/screens/sysop_test.exs` |
| **Full suite command** | `mix test` |
| **Estimated runtime** | ~30 seconds for focused files; full suite runtime varies by local database state |

---

## Sampling Rate

- **After every task commit:** Run the focused file touched by the task plus `test/foglet_bbs/tui/screens/shared/invites_surface_test.exs`
- **After every plan wave:** Run Account, Moderation, Sysop, shared invites, shell visibility, and accounts invite tests
- **Before `$gsd-verify-work`:** `mix precommit` must be green
- **Max feedback latency:** 60 seconds for focused checks

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 04-01-01 | 01 | 1 | INVT-01 | T-04-01 | Visibility remains advisory; domain authorization is rechecked by `Foglet.Accounts` | screen unit | `mix test test/foglet_bbs/tui/screens/account_test.exs test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/screens/sysop_test.exs` | ✅ | ⬜ pending |
| 04-01-02 | 01 | 1 | INVT-01 | T-04-02 | Shared invite rows do not disclose data outside `Accounts.list_invites/1` | render unit | `mix test test/foglet_bbs/tui/screens/shared/invites_surface_test.exs` | ✅ | ⬜ pending |
| 04-02-01 | 02 | 1 | MODR-04 | T-04-03 | Moderator invite generation succeeds only under `mods` policy and uses `Accounts.create_invite/1` | DB-backed screen/action | `mix test test/foglet_bbs/tui/screens/moderation_test.exs` | ✅ | ⬜ pending |
| 04-03-01 | 03 | 1 | SYSO-05 | T-04-04 | Sysop invite generation succeeds under `sysop_only` and `mods` policies and uses `Accounts.create_invite/1` | DB-backed screen/action | `mix test test/foglet_bbs/tui/screens/sysop_test.exs` | ✅ | ⬜ pending |
| 04-04-01 | 04 | 2 | INVT-01, MODR-04, SYSO-05 | T-04-01 / T-04-02 / T-04-03 / T-04-04 | Shared implementation is reused across Account, Moderation, and Sysop without duplicated lifecycle flows | integration/regression | `mix precommit` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/foglet_bbs/tui/screens/shared/invites_actions_test.exs` — covers shared load/generate/revoke/error behavior if a new action module is added.
- [ ] `test/foglet_bbs/tui/screens/shared/invites_surface_test.exs` — replace scaffold expectations with live row/status/error/key-hint expectations.
- [ ] `test/foglet_bbs/tui/screens/account_test.exs` — policy matrix and thin delegation checks for Account `INVITES`.
- [ ] `test/foglet_bbs/tui/screens/moderation_test.exs` — moderator policy and unlimited generation checks.
- [ ] `test/foglet_bbs/tui/screens/sysop_test.exs` — sysop policy and unlimited generation checks.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Terminal rendering fit for live invite rows across narrow SSH dimensions | INVT-01 | Existing test helpers can assert text and command state, but final terminal layout should be visually scanned once real rows replace scaffold text | Start the TUI, open each allowed `INVITES` tab, and confirm rows, status labels, error text, and key hints do not overlap at the project minimum terminal size |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 60s for focused checks
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-04-23
