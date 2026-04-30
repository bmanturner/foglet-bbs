---
phase: 46
slug: domain-cleanup-and-final-quality-gate
status: draft
nyquist_compliant: false
wave_0_complete: true
created: 2026-04-29
---

# Phase 46 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit (Elixir/Mix) + Dialyzer + Credo + Sobelow |
| **Config file** | `mix.exs`, `.dialyzer_ignore.exs`, `.credo.exs` |
| **Quick run command** | `rtk mix test` |
| **Full suite command** | `rtk mix precommit` (compile-warnings-as-errors → format → Credo → Sobelow → Dialyzer → test) |
| **Estimated runtime** | ~60–180 seconds (Dialyzer-bound; PLT cached) |

---

## Sampling Rate

- **After every task commit:** Run `rtk mix test`
- **After every plan completes:** Run `rtk mix precommit`
- **Before `/gsd-verify-work`:** `rtk mix precommit` must be green AND test count must be ≥ baseline (1 property + 2161 tests, 0 failures)
- **Max feedback latency:** ~180 seconds (full precommit)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 46-01-* | 01 (DOM-01) | 1 | DOM-01 | — | N/A | static + supervisor smoke | `rtk mix compile --warnings-as-errors && rtk mix test test/foglet_bbs/boards/` | ✅ | ⬜ pending |
| 46-02-* | 02 (DOM-02) | 2 | DOM-02 | — | N/A | docs (no behavior change) | `rtk mix docs 2>/dev/null \|\| rtk mix compile --warnings-as-errors` + `grep -n "Transaction strategy" lib/foglet_bbs/boards/server.ex` | ✅ | ⬜ pending |
| 46-03-* | 03 (QUAL-01) | 3 | QUAL-01 | — | N/A | static analysis | `rtk mix dialyzer` + `rtk mix precommit` | ✅ | ⬜ pending |
| 46-04-* | 04 (QUAL-03) | 4 | QUAL-03 | — | N/A | doc-grep | `grep -c "^\*\*Disposition:\*\*" .planning/codebase/CONCERNS.md` (must equal heading count, 17) | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. No new test files, fixtures, or framework installs needed.

- ExUnit configured (`test/test_helper.exs`)
- Dialyzer PLT cached (`_build/`)
- Existing tests cover transitively: `test/foglet_bbs/boards/`, `test/foglet_bbs/sessions/supervisor_test.exs`, `test/foglet_bbs/ssh/supervisor_test.exs`

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| `.dialyzer_ignore.exs` line count strictly smaller after QUAL-01 | QUAL-01 (D-08) | Exact end-state count is not pre-locked; depends on which `:contract_supertype` specs resist narrowing | `wc -l .dialyzer_ignore.exs` before vs. after; record delta in plan SUMMARY |
| CONCERNS.md `**Disposition:**` line count equals `### ` heading count | QUAL-03 (D-09) | Grep-verifiable but headings should be cross-referenced for accuracy against phase 41–45 SUMMARYs | `grep -c "^### " .planning/codebase/CONCERNS.md` must equal `grep -c "^\*\*Disposition:\*\*" .planning/codebase/CONCERNS.md` |

---

## Validation Sign-Off

- [x] All tasks have automated verify (`rtk mix precommit` + grep checks)
- [x] Sampling continuity: every plan ends with `rtk mix precommit && rtk mix test`
- [x] Wave 0 covers all MISSING references (none — existing infra suffices)
- [x] No watch-mode flags
- [x] Feedback latency < 180s
- [ ] `nyquist_compliant: true` set in frontmatter (planner sets after coverage map filled)

**Approval:** pending
