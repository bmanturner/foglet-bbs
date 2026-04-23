---
phase: 00
slug: screen-shells-and-shared-surface-primitives
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-23
---

# Phase 00 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit via Mix aliases |
| **Config file** | `test/test_helper.exs` |
| **Quick run command** | `mix test test/foglet_bbs/tui/screens/account_test.exs` |
| **Full suite command** | `mix test` |
| **Estimated runtime** | ~10 seconds quick / ~120 seconds full |

---

## Sampling Rate

- **After every task commit:** Run the narrowest affected shell/shared-surface test file, starting with `mix test test/foglet_bbs/tui/screens/account_test.exs`
- **After every plan wave:** Run `mix test`
- **Before `$gsd-verify-work`:** `mix precommit` must be green
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 00-ACCT-01 | TBD | TBD | ACCT-01 | T-00-01 / V3,V5 | Account shell remains authenticated-only, read-only, and tab-stable | unit + layout smoke | `mix test test/foglet_bbs/tui/screens/account_test.exs` | ❌ W0 | ⬜ pending |
| 00-MODR-01 | TBD | TBD | MODR-01 | T-00-02 / V4,V5 | Moderation entry stays role-gated and non-operational in Phase 0 | unit + layout smoke | `mix test test/foglet_bbs/tui/screens/moderation_test.exs` | ❌ W0 | ⬜ pending |
| 00-SYSO-01 | TBD | TBD | SYSO-01 | T-00-03 / V4,V5 | Sysop entry stays role-gated and non-operational in Phase 0 | unit + layout smoke | `mix test test/foglet_bbs/tui/screens/sysop_test.exs` | ❌ W0 | ⬜ pending |
| 00-INVT-PRIM | TBD | TBD | Phase 0 Success Criterion 3 | T-00-04 / V4,V5 | Shared `INVITES` surface stays placeholder-only with no fake mutations | unit | `mix test test/foglet_bbs/tui/screens/shared/invites_surface_test.exs` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/foglet_bbs/tui/screens/account_test.exs` — covers ACCT-01 shell routing, tab switching, and read-only placeholders
- [ ] `test/foglet_bbs/tui/screens/moderation_test.exs` — covers MODR-01 shell routing, role-gated entry visibility, and tab-set rendering
- [ ] `test/foglet_bbs/tui/screens/sysop_test.exs` — covers SYSO-01 shell routing, role-gated entry visibility, and tab-set rendering
- [ ] `test/foglet_bbs/tui/screens/shared/invites_surface_test.exs` — covers shared placeholder/loading/error behavior and visibility helper logic
- [ ] Extend `test/foglet_bbs/tui/screens/main_menu_test.exs` — new menu items and role visibility assertions
- [ ] Extend `test/foglet_bbs/tui/app_test.exs` — screen routing, `screen_module_for/1`, and `screen_state` seeding for new shells
- [ ] Extend `test/foglet_bbs/tui/layout_smoke_test.exs` — Account, Moderation, and Sysop layout smoke coverage

*If none: "Existing infrastructure covers all phase requirements."*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| None | N/A | All Phase 0 shell behaviors should be automatable through screen render and key-handling tests | N/A |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
