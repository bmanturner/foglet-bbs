---
phase: 0
slug: cross-cutting-extractions-prelude
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-21
---

# Phase 0 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution. Derived from `00-RESEARCH.md` §6 (Validation Architecture — Nyquist).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit (built into Elixir — no separate install required) |
| **Config file** | `test/test_helper.exs` |
| **Quick run (theme)** | `mix test test/foglet_bbs/tui/theme_test.exs` |
| **Quick run (domain)** | `mix test test/foglet_bbs/tui/screens/domain_test.exs` |
| **Smoke integration** | `mix test test/foglet_bbs/tui/layout_smoke_test.exs` |
| **Full suite command** | `mix precommit` (compile --warnings-as-errors, format, credo --strict, sobelow, dialyzer, test) |
| **Estimated runtime** | ~60–120 seconds for `mix precommit` depending on Dialyzer cache warmth |

---

## Sampling Rate

- **After every task commit:** Run `mix test <affected file>` (the quick run for whichever module the task touched).
- **After every plan commit (00-01, 00-02, 00-03):** Run `mix precommit` — each atomic plan MUST commit green.
- **Before `/gsd-verify-work`:** `mix precommit` + both grep gates green.
- **Max feedback latency:** ~120 seconds (full precommit).

---

## Per-Task Verification Map

Task IDs are assigned by the planner. The table below anchors the AUDIT-0x requirements to automated commands so the planner can copy this shape into each task's `<automated>` block.

| Plan | Wave | Requirement | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|------|------|-------------|-----------------|-----------|-------------------|-------------|--------|
| 00-01 | 1 | AUDIT-01 | `Theme.from_state/1` returns `%Theme{}` on happy-path | unit | `mix test test/foglet_bbs/tui/theme_test.exs` | ❌ W0 (create) | ⬜ pending |
| 00-01 | 1 | AUDIT-01 | Missing `session_context` → `Theme.default()` | unit | `mix test test/foglet_bbs/tui/theme_test.exs` | ❌ W0 | ⬜ pending |
| 00-01 | 1 | AUDIT-01 | Missing `:theme` key → `Theme.default()` | unit | `mix test test/foglet_bbs/tui/theme_test.exs` | ❌ W0 | ⬜ pending |
| 00-01 | 1 | AUDIT-03 / AUDIT-15 | `mix precommit` green after 00-01 commit | CI | `mix precommit` | ✅ | ⬜ pending |
| 00-02 | 2 | AUDIT-02 | `Screens.Domain.get/2` returns `{:ok, module}` for each of `:boards \| :threads \| :posts \| :markdown` | unit | `mix test test/foglet_bbs/tui/screens/domain_test.exs` | ❌ W0 (create) | ⬜ pending |
| 00-02 | 2 | AUDIT-02 | Missing `session_context` → `{:error, :not_configured}` | unit | `mix test test/foglet_bbs/tui/screens/domain_test.exs` | ❌ W0 | ⬜ pending |
| 00-02 | 2 | AUDIT-02 | Missing `:domain` key → `{:error, :not_configured}` | unit | `mix test test/foglet_bbs/tui/screens/domain_test.exs` | ❌ W0 | ⬜ pending |
| 00-02 | 2 | AUDIT-02 | Unknown key → `{:error, :not_configured}` (no raise) | unit | `mix test test/foglet_bbs/tui/screens/domain_test.exs` | ❌ W0 | ⬜ pending |
| 00-02 | 2 | AUDIT-03 / AUDIT-15 | `mix precommit` green after 00-02 commit | CI | `mix precommit` | ✅ | ⬜ pending |
| 00-03 | 3 | AUDIT-04 | Grep gate #8 zero on `lib/foglet_bbs/tui/screens/*.ex` | grep | see below | ✅ | ⬜ pending |
| 00-03 | 3 | AUDIT-04 | Grep gate #9 zero on `lib/foglet_bbs/tui/screens/*.ex` | grep | see below | ✅ | ⬜ pending |
| 00-03 | 3 | AUDIT-01 (D-10) | Non-screen theme sites migrated (screen_frame, size_gate, app.ex modal) | grep | `rg 'session_context.*Map\\.get\\(:theme\\)' lib/foglet_bbs/tui/widgets/chrome/ lib/foglet_bbs/tui/app.ex` returns zero | ✅ | ⬜ pending |
| 00-03 | 3 | AUDIT-03 / AUDIT-15 | `mix precommit` green after 00-03 commit | CI | `mix precommit` | ✅ | ⬜ pending |
| 00-03 | 3 | D-08 invariant | Smoke tests pass unchanged | integration | `mix test test/foglet_bbs/tui/layout_smoke_test.exs` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

### Exact grep gate commands

```sh
# Gate #8 — inlined theme extraction
rg -n '\(Map\.get\(state, :session_context\) \|\| %\{\}\) \|> Map\.get\(:theme\)' lib/foglet_bbs/tui/screens/
# Expected after 00-03: no matches, exit 1

# Gate #9 — inlined domain lookup
rg -n 'get_in\(ctx, \[:domain,' lib/foglet_bbs/tui/screens/
# Expected after 00-03: no matches, exit 1

# Gate #7 — NOT Phase 0 scope (per D-09); resolved in Phases 5/6/7/8/9
```

---

## Wave 0 Requirements

- [ ] `test/foglet_bbs/tui/theme_test.exs` — created by 00-01-PLAN. `describe "from_state/1"` block with 3 tests (happy path + 2 fallbacks).
- [ ] `lib/foglet_bbs/tui/screens/domain.ex` + `test/foglet_bbs/tui/screens/domain_test.exs` — created by 00-02-PLAN. `describe "get/2"` with 4+ tests (happy path × 4 keys, missing session_context, missing `:domain` key, unknown key).
- [ ] No framework installation needed — ExUnit ships with OTP.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| D-08 byte-for-byte SSH render parity | Roadmap success criterion #5 | No snapshot testing (explicitly rejected in STACK.md) | SSH into a local foglet_bbs instance at default terminal size, capture one full screen render per phase pre- and post-00-03, diff visually. |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (theme_test.exs, domain.ex, domain_test.exs)
- [ ] No watch-mode flags in commands
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter after planner populates task IDs and execution confirms all rows green

**Approval:** pending

---

*Source of detail: `00-RESEARCH.md` §6 — Validation Architecture (Nyquist).*
