---
phase: 25
slug: operator-console-conversion
status: planned
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-25
last_updated: 2026-04-25
---

# Phase 25 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Populated by planner from plans 01–05.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit (Elixir) |
| **Config file** | `test/test_helper.exs` |
| **Quick run command** | `rtk mix test --stale` |
| **Full suite command** | `rtk mix test` |
| **Layout smoke target** | `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` |
| **Finish-line gate** | `rtk mix precommit` |
| **Estimated runtime** | ~30 seconds (focused) / ~90 seconds (full + precommit) |

---

## Sampling Rate

- **After every task commit:** Run focused screen test (e.g., `rtk mix test test/foglet_bbs/tui/screens/account_test.exs --max-failures 1`).
- **After every plan wave:** Run `rtk mix test test/foglet_bbs/tui/screens/ test/foglet_bbs/tui/widgets/modal/ test/foglet_bbs/tui/widgets/display/ test/foglet_bbs/tui/layout_smoke_test.exs`.
- **Before `/gsd-verify-work`:** Full suite green plus `rtk mix precommit` green (Plan 05 Task 2).
- **Max feedback latency:** ~30 seconds for focused; ~90 seconds for wave merge.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 25-01-T1 | 01 | 1 | ACCOUNT-01, MOD-01, SYSOP-01 | n/a | Modal.Form back-tab event-shape parity | unit | `rtk mix test test/foglet_bbs/tui/widgets/modal/form_test.exs` | yes | ⬜ pending |
| 25-01-T2 | 01 | 1 | ACCOUNT-01 | n/a | Modal.Form `:enum` field_value accessor preserves prefs live preview path | unit | `rtk mix test test/foglet_bbs/tui/widgets/modal/form_test.exs` | yes | ⬜ pending |
| 25-01-T3 | 01 | 1 | ACCOUNT-01, MOD-01, SYSOP-01 | n/a | Layout-smoke `set_active_tab/2` helper proven against converted Sysop boards | unit (smoke) | `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs --only "sysop boards size contract"` | yes (extends) | ⬜ pending |
| 25-02-T1 | 02 | 2 | ACCOUNT-01 | n/a | Account PROFILE + PREFS render through Modal.Form; live preview preserved | unit + render | `rtk mix test test/foglet_bbs/tui/screens/account_test.exs` | yes | ⬜ pending |
| 25-02-T2 | 02 | 2 | ACCOUNT-01 | n/a | Account SSH_KEYS uses ConsoleTable; selection ownership in widget (D-05); empty-list arrow no-crash (Pitfall 3) | unit + render | `rtk mix test test/foglet_bbs/tui/screens/account_test.exs` | yes | ⬜ pending |
| 25-02-T3 | 02 | 2 | ACCOUNT-01 | n/a | Per-tab smoke at 64x22 / 80x24 for PROFILE / PREFS / SSH_KEYS | unit (smoke) | `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs --only "account profile size contract" --only "account prefs size contract" --only "account ssh_keys size contract"` | yes (extends) | ⬜ pending |
| 25-03-T1 | 03 | 2 | MOD-01 | n/a | LOG/USERS/BOARDS render KvGrid + Badge + ConsoleTable; LOG `selectable: false` (Pitfall 7) | unit + render | `rtk mix test test/foglet_bbs/tui/screens/moderation_test.exs` | yes | ⬜ pending |
| 25-03-T2 | 03 | 2 | MOD-01 | n/a | Shared InvitesSurface uses ConsoleTable; revoke contract preserved | unit + render | `rtk mix test test/foglet_bbs/tui/screens/moderation_test.exs` | yes | ⬜ pending |
| 25-03-T3 | 03 | 2 | MOD-01 | n/a | Per-tab smoke at 64x22 / 80x24 for LOG / USERS / BOARDS / INVITES | unit (smoke) | `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs --only "moderation log size contract" --only "moderation users size contract" --only "moderation boards size contract" --only "moderation invites size contract"` | yes (extends) | ⬜ pending |
| 25-04-T1 | 04 | 2 | SYSOP-01 | n/a | SITE + LIMITS via Modal.Form; SITE re-init preserves visible_keys/1 (Pitfall 6) | unit + render | `rtk mix test test/foglet_bbs/tui/screens/sysop_test.exs test/foglet_bbs/tui/screens/sysop/site_form_test.exs test/foglet_bbs/tui/screens/sysop/config_accountability_test.exs` | yes | ⬜ pending |
| 25-04-T2 | 04 | 2 | SYSOP-01 | n/a | USERS via ConsoleTable with status-transition dispatch; SYSTEM via KvGrid + metric badges; BOARDS destructive routes through commands.destructive (D-07) | unit + render | `rtk mix test test/foglet_bbs/tui/screens/sysop_test.exs` | yes | ⬜ pending |
| 25-04-T3 | 04 | 2 | SYSOP-01 | n/a | Per-tab smoke at 64x22 / 80x24 for SITE / LIMITS / BOARDS / USERS / SYSTEM | unit (smoke) | `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs --only "sysop site size contract" --only "sysop limits size contract" --only "sysop boards size contract" --only "sysop users size contract" --only "sysop system size contract"` | yes (extends) | ⬜ pending |
| 25-05-T1 | 05 | 3 | ACCOUNT-01, MOD-01, SYSOP-01 | n/a | All 12 converted tabs leak no color atoms (D-12) | unit | `rtk mix test test/foglet_bbs/tui/screens/account_test.exs test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/screens/sysop_test.exs --only describe:"Phase 25 theme hygiene (D-12)"` | yes (extends) | ⬜ pending |
| 25-05-T2 | 05 | 3 | ACCOUNT-01, MOD-01, SYSOP-01 | n/a | Workspace.Inspector deferral grep test (D-20) + `rtk mix precommit` finish-line gate (R8) | unit + finish-line | `rtk mix test test/foglet_bbs/tui/screens/sysop_test.exs --only describe:"Phase 25 Workspace.Inspector deferral (D-20)" && rtk mix precommit` | yes (extends) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `lib/foglet_bbs/tui/widgets/modal/form.ex` — handles both `%{key: :shift_tab}` and `%{key: :tab, shift: true}` for back-tab navigation (Plan 01 Task 1, Pitfall 1).
- [ ] `lib/foglet_bbs/tui/widgets/modal/form.ex` — exposes documented `field_value/2` accessor for `:enum` cycling so prefs can preserve `candidate_theme_id` live preview without a new field type or callback (Plan 01 Task 2, Pitfall 5 / A1).
- [ ] `test/support/foglet/tui/layout_smoke_helpers.ex` — `set_active_tab/2` helper exists and is proven by an example per-tab block in `layout_smoke_test.exs` (Plan 01 Task 3).

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Operator console TUI rendering | All Phase 25 reqs | Raxol terminal output requires SSH session for end-to-end visual review | Connect via SSH as operator, exercise PROFILE/PREFS/SSH_KEYS, LOG/USERS/BOARDS/INVITES, SITE/LIMITS/BOARDS/USERS/SYSTEM tabs at 64x22 and 80x24 terminal sizes; confirm primitives render and destructive emphasis reads distinctly from routine actions. |
| Live theme preview on prefs theme cycle | ACCOUNT-01 (D-03) | Live preview is a screen-state side effect best confirmed visually | In SSH session, navigate to Account > PREFS > theme field, press Down/Up arrows; confirm theme palette changes immediately without submit. |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s (focused); < 90s (wave merge)
- [ ] `nyquist_compliant: true` set in frontmatter (set by Plan 05 SUMMARY)

**Approval:** pending (set to `green` after Plan 05 Task 2 precommit pass)
