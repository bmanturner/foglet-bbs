---
phase: 29
slug: sysop-tab-lifecycle-bodies
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-27
---

# Phase 29 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from `29-RESEARCH.md` Validation Architecture section.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit (Elixir built-in) |
| **Config file** | `test/test_helper.exs`; per-test setup via `use FogletBbs.DataCase, async: false` |
| **Quick run command** | `rtk mix test test/foglet_bbs/tui/screens/sysop_test.exs test/foglet_bbs/accounts_test.exs --max-failures 1` |
| **Full suite command** | `rtk mix test` |
| **Phase-gate command** | `rtk mix precommit` (compile-warnings-as-errors + format + Credo + Sobelow + Dialyzer + tests) |
| **Estimated runtime** | quick ~30s; full ~3-5 min; precommit ~5-8 min |

---

## Sampling Rate

- **After every task commit:** Run quick command (`rtk mix test test/foglet_bbs/tui/screens/sysop_test.exs test/foglet_bbs/accounts_test.exs --max-failures 1`)
- **After every plan wave:** Run `rtk mix test test/foglet_bbs/tui/`
- **Before `/gsd-verify-work`:** `rtk mix precommit` must be green
- **Max feedback latency:** 30 seconds for per-task sampling

---

## Per-Task Verification Map

> Filled by planner; each task gets a row mapping its REQ-ID(s) to an automated command. The grid below is the TEMPLATE — `gsd-planner` must extend it with per-task rows during plan generation.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 29-01-XX | 01 | 1 | SYSOP-01, SYSOP-02 | — | tagged-enum total coverage; `Press any key` absent | unit + grep | `rtk mix test test/foglet_bbs/tui/screens/sysop_test.exs` | ✅ | ⬜ pending |
| 29-02-XX | 02 | 2 | SYSOP-02, SYSOP-05 | EoP / hidden keybind ≠ auth | retry round-trip; forbidden distinct; users gating | unit + render-smoke | `rtk mix test test/foglet_bbs/tui/screens/sysop_test.exs test/foglet_bbs/accounts_test.exs` | ✅ | ⬜ pending |
| 29-03-XX | 03 | 2 | SYSOP-03, SYSOP-04 | InfoDisclosure / operator copy | Esc reseed; Enter persist + Saved.; description regex | integration + grep | `rtk mix test test/foglet_bbs/tui/screens/sysop/site_form_test.exs test/foglet_bbs/config/schema_test.exs` | ✅ / ❌ W0 (schema_test extension) | ⬜ pending |
| 29-04-XX | 04 | 3 | SYSOP-06, SYSOP-07 | — | invites focus + revoke gating; 1-N Jump consistency | render-smoke + grep | `rtk mix test test/foglet_bbs/tui/screens/shared/invites_surface_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/foglet_bbs/config/schema_test.exs` — extend (or create) to assert the SYSOP-04 grep regex `(D-\d+|REQ-[A-Z]+-\d+|Phase \d+|Pitfall \d+|deliverable)/i` over `Foglet.Config.Schema.entries()` for the 5 `@site_keys` descriptions
- [ ] `test/foglet_bbs/accounts_test.exs` — add `describe "valid_status_transitions/1"` block (4 tests, one per `from_status`)
- [ ] `test/foglet_bbs/tui/screens/sysop_test.exs` — add `describe` blocks for: lifecycle tagged enum round-trip, tab-switch auto-load, retry re-dispatch, forbidden panel + retry suppression, USERS gating with focused `:active`, USERS injected `:invalid_transition` from→to copy
- [ ] `test/foglet_bbs/tui/screens/shared/invites_surface_test.exs` — extend with focus-highlight assertion at 80×24 (focused row tokens differ from unfocused)
- [ ] `test/foglet_bbs/tui/layout_smoke_test.exs` — add `1-N Jump` substring assertions for Account / Moderation / Sysop at 64×22 and 80×24, INVITES-visible and INVITES-hidden contexts
- [ ] Grep tests (mix-task style or dedicated `grep_test.exs`):
  - No `"Press any key"` literal in `lib/foglet_bbs/tui/screens/sysop.ex`
  - No `Raxol.Core.Runtime.Command.task` substring under `lib/foglet_bbs/tui/screens/sysop/` or in `sysop.ex`
  - No `{"1-6", "Jump"}` literal in `moderation.ex` or `account.ex`
  - `@site_keys` description regex (mirrors SYSOP-04 schema test)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Visible row-highlight contrast for INVITES focus at 80×24 over a real SSH client | SYSOP-06 | ANSI rendering can pass programmatic substring tests but be visually faint depending on terminal theme | After Plan 4 lands, run `rtk mix foglet.tui.render sysop` (with INVITES tab active) at `--width 80 --height 24` and confirm focused row contrasts. If unconvincing, exercise via real SSH session. |
| Site Esc field reversion is visually obvious (no inline copy) | SYSOP-03 (D-20/D-21) | Verifies the SPEC-amendment lands as user-perceptible behavior, not just test-asserted state | After Plan 3 lands, edit a Site field via SSH, press Esc, confirm field reverts to saved value with no status row appearing. |

*All other Phase 29 behaviors have automated verification.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (5 test-file extensions + grep tests)
- [ ] No watch-mode flags in commands
- [ ] Feedback latency < 30s for per-task sampling
- [ ] `nyquist_compliant: true` set in frontmatter once planner has filled the per-task grid

**Approval:** pending
