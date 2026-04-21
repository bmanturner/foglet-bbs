---
phase: 1
slug: login
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-04-21
---

# Phase 1 — Login — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit (Elixir built-in) |
| **Config file** | `test/test_helper.exs` (standard) |
| **Quick run command** | `mix test test/foglet_bbs/tui/screens/login_test.exs` |
| **Full suite command** | `mix precommit` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `mix test test/foglet_bbs/tui/screens/login_test.exs`
- **After every plan wave:** Run `mix precommit`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 01-01-01 | 01-01 | 1 | LOGIN-01, LOGIN-03, LOGIN-05 | — | TextInput state correctly initialized and accessed; Config.get safety documented per D-07 | unit | `mix test test/foglet_bbs/tui/screens/login_test.exs` | ✅ W0 | ⬜ pending |
| 01-01-02 | 01-01 | 1 | LOGIN-04 | — | All auth branches preserved in with chain | unit | `mix test test/foglet_bbs/tui/screens/login_test.exs` | ✅ W0 | ⬜ pending |
| 01-01-03 | 01-01 | 1 | LOGIN-02, LOGIN-06 | — | Deleted functions not present, grep gates return zero | grep + unit | See grep gates below | ✅ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [x] `test/foglet_bbs/tui/screens/login_test.exs` — existing coverage for all LOGIN-01..06 behaviors
- [x] `test/test_helper.exs` — standard ExUnit configuration
- [ ] Extend `login_test.exs` with `init_screen_state/1` test (new function for Task 1)

*Existing infrastructure covers all phase requirements. Extend with init_screen_state/1 test only.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Visual parity with pre-migration login form | LOGIN-01 | TUI rendering is visual; automated tests verify behavior not exact column alignment | Run SSH session, navigate to login form, verify inline label+TextInput matches `"Handle:   value█"` format |

*All other phase behaviors have automated verification.*

---

## AUDIT-05 Grep Gates (from REQUIREMENTS.md)

| Gate # | Pattern | Command | Expected After Phase |
|--------|---------|---------|---------------------|
| 1 | Named color atoms | `rg ':red\|:green\|:cyan\|:yellow\|:blue\|:magenta\|:white\|:black' lib/foglet_bbs/tui/screens/login.ex` | Zero |
| 2 | Hex literals | `rg '"#[0-9a-fA-F]{6}"' lib/foglet_bbs/tui/screens/login.ex` | Zero |
| 3 | Raw ANSI escapes | `rg '\\e\[|\\x1b' lib/foglet_bbs/tui/screens/login.ex` | Zero |
| 8 | Inlined theme extraction | `rg '\(Map\.get\(state, :session_context\) \|\| %\{\}\) \|> Map\.get\(:theme\)' lib/foglet_bbs/tui/screens/login.ex` | Zero (already migrated in Phase 0) |
| 9 | Inlined domain lookup | `rg 'get_in\(.*\[:domain,' lib/foglet_bbs/tui/screens/login.ex` | Zero (N/A for Login) |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 5s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
