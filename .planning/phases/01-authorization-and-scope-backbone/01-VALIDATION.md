---
phase: 1
slug: authorization-and-scope-backbone
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-23
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Seed data sourced from `01-RESEARCH.md` §"Validation Architecture".

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit (built-in Elixir, no separate version pin) |
| **Config file** | `test/test_helper.exs` |
| **Quick run command** | `mix test test/foglet_bbs/authorization_test.exs` |
| **Full suite command** | `mix test` |
| **Estimated runtime** | ~{to fill at Wave 0} seconds |

---

## Sampling Rate

- **After every task commit:** `mix test test/foglet_bbs/authorization_test.exs --failed`
- **After every plan wave:** `mix test`
- **Before `/gsd-verify-work`:** `mix test` green + `mix precommit` green
- **Max feedback latency:** to be measured after Wave 0 scaffolding lands

---

## Per-Task Verification Map

> Filled in by gsd-planner per task (each task must name an automated verify command
> or a Wave 0 dependency that will create one).

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| {to be filled by planner} | | | | | | | | | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/foglet_bbs/authorization_test.exs` — NEW file, covers MODR-02 and MODR-03 policy matrix (see RESEARCH Pattern 5)
- [ ] `test/foglet_bbs/authorization/bodyguard_passthrough_test.exs` — NEW file, A4 smoke test asserting `Bodyguard.permit/4` preserves `{:error, :forbidden}` reason
- [ ] `test/foglet_bbs/boards/boards_test.exs` — add forbidden-path tests for `create_board/3`, `update_board/3`, `archive_board/2` (existing file)
- [ ] `test/foglet_bbs/config/config_test.exs` — add forbidden-path test for new actor-aware `Config.put/4` (existing file)
- [ ] `mix.exs` — add `{:bodyguard, "~> 2.4"}` dependency; run `mix deps.get`

*No new test framework install needed — ExUnit and FogletBbs.DataCase already exist.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| — | — | — | — |

*All phase behaviors have automated verification — Phase 1 is pure module + function-clause matrix + tuple-return domain functions, fully unit-testable.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (new authorization tests + Bodyguard dep)
- [ ] No watch-mode flags in any task command
- [ ] Feedback latency under the project's target (measure after Wave 0)
- [ ] `nyquist_compliant: true` set in frontmatter once planner fills the Per-Task Verification Map

**Approval:** pending
