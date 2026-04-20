---
phase: 5
slug: terminal-size-gate
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-20
---

# Phase 5 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit (Elixir stdlib) — already configured |
| **Config file** | `test/test_helper.exs` (exists) |
| **Quick run command** | `mix test test/foglet_bbs/tui/size_gate_test.exs test/foglet_bbs/tui/app_test.exs` |
| **Full suite command** | `mix precommit` (alias: `mix test` + `mix format --check-formatted` + `mix credo` + `mix compile --warnings-as-errors`) |
| **Estimated runtime** | ~15s targeted, ~60s full |

---

## Sampling Rate

- **After every task commit:** Run quick run command (targeted test files)
- **After every plan wave:** Run full suite (`mix precommit`)
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 15s

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 05-01-01 | 01 | 1 | FRAME-03 | — | N/A (render-time branch, no security boundary) | unit | `mix test test/foglet_bbs/tui/size_gate_test.exs` | ❌ W0 | ⬜ pending |
| 05-01-02 | 01 | 1 | FRAME-03 | — | N/A | unit | `mix test test/foglet_bbs/tui/app_test.exs` | ✅ | ⬜ pending |
| 05-02-01 | 02 | 2 | FRAME-03 | — | N/A | unit | `mix test test/foglet_bbs/tui/app_test.exs` | ✅ | ⬜ pending |
| 05-02-02 | 02 | 2 | FRAME-03 | — | N/A | unit | `mix test test/foglet_bbs/tui/app_test.exs` | ✅ | ⬜ pending |
| 05-02-03 | 02 | 2 | FRAME-03 | — | N/A | unit | `mix test test/foglet_bbs/tui/app_test.exs` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/foglet_bbs/tui/size_gate_test.exs` — new file, created as part of Plan 01 Task 01 (tests written alongside module; no separate Wave 0 scaffold needed because the module and its tests ship together)

*All other test files (`app_test.exs`) already exist and are covered by existing ExUnit infrastructure.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Visual centering of gate message | FRAME-03 | Raxol rendering is terminal-dependent; automated assertion can verify the element tree but not the pixel layout | 1. SSH to local BBS instance (`mix foglet.ssh.up` or equivalent). 2. Open an iTerm pane, resize below 60 cols. 3. Confirm four-line message is visible and centered. 4. Resize back to full; confirm prior screen re-appears. |
| No flicker during iTerm drag | FRAME-03 + Pitfall 4 | Flicker is a per-frame render artifact; only observable in a real terminal | 1. Log in, open any screen with content (e.g., board list). 2. Drag iTerm window below/above 60×20 threshold repeatedly. 3. Confirm no visible flicker, no border fragments, no stale frames. |
| Composer draft survives resize in live session | FRAME-03 + Pitfall 4 | Requires a live SSH session with multi-line input; regression test in `app_test.exs` covers the state-preservation path but not the full Raxol runtime | 1. Log in, start a new thread (`[C]` from main menu). 2. Type 3 lines of body content. 3. Drag terminal below 60×20. 4. Drag back. 5. Confirm body content intact, cursor position preserved. |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify (all 5 tasks have automated tests)
- [ ] Wave 0 covers all MISSING references (size_gate_test.exs is MISSING but created in Plan 01 Task 01)
- [ ] No watch-mode flags (all commands are one-shot `mix test`)
- [ ] Feedback latency < 15s (quick run command well within)
- [ ] `nyquist_compliant: true` set in frontmatter (flip after Plan 01 Task 01 creates the test file)

**Approval:** pending
