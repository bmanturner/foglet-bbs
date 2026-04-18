---
phase: 3
slug: ssh-server-tui
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-18
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit (built-in) |
| **Config file** | `test/test_helper.exs` (exists) |
| **Quick run command** | `mix test test/foglet_bbs/tui/ test/foglet_bbs/sessions/ test/foglet_bbs/ssh/ --no-start` |
| **Full suite command** | `mix test` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `mix test test/foglet_bbs/tui/ test/foglet_bbs/sessions/ test/foglet_bbs/ssh/ --no-start`
- **After every plan wave:** Run `mix test`
- **Before `/gsd-verify-work`:** Full suite must be green + `mix precommit`
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 3-xx-01 | 01 | 0 | SSH-01 | Host key MITM | Host key persists across restarts | unit | `mix test test/foglet_bbs/ssh/supervisor_test.exs` | ❌ W0 | ⬜ pending |
| 3-xx-02 | 01 | 0 | SSH-02 | Brute force via SSH | authenticate_by_password/2 called from pwdfun | unit | `mix test test/foglet_bbs/ssh/key_cb_test.exs` | ❌ W0 | ⬜ pending |
| 3-xx-03 | 01 | 0 | SSH-03 | — | is_auth_key/3 returns true for registered key | unit | `mix test test/foglet_bbs/ssh/key_cb_test.exs` | ❌ W0 | ⬜ pending |
| 3-xx-04 | 02 | 0 | SSH-04 | — | Login-or-register shown for nil user_id context | unit | `mix test test/foglet_bbs/tui/app_test.exs` | ❌ W0 | ⬜ pending |
| 3-xx-05 | 02 | 0 | SSH-05 | Session hijack via reconnect | Second session replaces old; old notified | unit | `mix test test/foglet_bbs/sessions/session_test.exs` | ❌ W0 | ⬜ pending |
| 3-xx-06 | 02 | 1 | SSH-06 | — | terminal_size updated on :window_change | unit | `mix test test/foglet_bbs/tui/app_test.exs` | ❌ W0 | ⬜ pending |
| 3-xx-07 | 03 | 1 | SSH-07 | — | Each screen renders without crash | unit | `mix test test/foglet_bbs/tui/` | ❌ W0 | ⬜ pending |
| 3-xx-08 | 03 | 1 | SSH-08 | — | Key events dispatch correct update messages | unit | `mix test test/foglet_bbs/tui/app_test.exs` | ❌ W0 | ⬜ pending |
| 3-xx-09 | 04 | 2 | SSH-09 | — | Read pointer advances and flushes on screen transition | unit | `mix test test/foglet_bbs/tui/app_test.exs` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/foglet_bbs/ssh/supervisor_test.exs` — stubs for SSH-01 host key loading
- [ ] `test/foglet_bbs/ssh/key_cb_test.exs` — stubs for SSH-02, SSH-03 auth callbacks
- [ ] `test/foglet_bbs/sessions/session_test.exs` — stubs for SSH-05 one-session rule
- [ ] `test/foglet_bbs/sessions/supervisor_test.exs` — stubs for session lifecycle
- [ ] `test/foglet_bbs/tui/app_test.exs` — stubs for SSH-04, SSH-06, SSH-07, SSH-08, SSH-09
- [ ] `test/foglet_bbs/tui/screens/` directory — per-screen view test stubs

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| SSH client connects and reaches main menu | SSH-01 | Requires live SSH daemon + real client | `ssh -p 2222 user@localhost` — confirm main menu appears |
| Host key survives server restart | SSH-01 | Requires process restart cycle | Stop/start server; reconnect — `~/.ssh/known_hosts` fingerprint must be unchanged |
| Password auth via real SSH client | SSH-02 | Requires real SSH handshake | `ssh -p 2222 handle@localhost` with correct password — must reach main menu |
| Pubkey auth (no password prompt) | SSH-03 | Requires key negotiation | `ssh -i ~/.ssh/id_ed25519 -p 2222 handle@localhost` — no password prompt |
| Guest registration complete flow | SSH-04 | Multi-step TUI interaction | Connect without credentials; complete registration wizard; email code entry |
| Concurrent session replacement notification | SSH-05 | Two live terminals required | Open two SSH sessions as same user; old session must show replacement message |
| Terminal resize adaptation | SSH-06 | Live PTY required | Resize terminal window during SSH session; TUI must re-layout |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
