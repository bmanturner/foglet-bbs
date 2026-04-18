# Phase 3: SSH Server & TUI - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-18
**Phase:** 03-ssh-server-tui
**Areas discussed:** Registration mode, TUI rendering layer, Guest flow shape, Post composer UX

---

## Registration Mode

| Option | Description | Selected |
|--------|-------------|----------|
| Open signup | Anyone can register. Email verification gates posting. | |
| Sysop-approved | Pending state; sysop approves before login. | |
| Invite-only | Invite code required to register. | |
| All three, configurable | All modes supported, runtime-configurable. | ✓ |

**User's choice:** All three modes supported, configurable via runtime config table (Foglet.Config ETS cache).

---

| Option | Description | Selected |
|--------|-------------|----------|
| Open signup | Default lowest-barrier. | ✓ |
| Sysop-approved | Sysop in control from day one. | |
| Invite-only | Smallest surface. | |

**User's choice:** Open signup as default.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Runtime config table | Editable from sysop TUI without redeploy. | ✓ |
| Environment variable only | Requires redeploy to change. | |

**User's choice:** Runtime config table.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Sysop only | Simple, explicit. | |
| Sysop and mods | More delegation. | |
| Any registered user | Viral spread. | |
| Configurable, default sysop | Flexible, safe default. | ✓ |

**User's choice:** Configurable who can generate invite codes, default sysop-only.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Queue in sysop TUI (Phase 8) stub | Phase 3 persists pending only. | ✓ |
| Email notification | Requires email (Phase 10). | |
| Mix task in Phase 3 | Adds mix foglet.user.approve now. | |

**User's choice:** Phase 8 stub — Phase 3 just persists pending accounts and blocks login.

---

## TUI Rendering Layer

| Option | Description | Selected |
|--------|-------------|----------|
| Raw ANSI custom widget layer | Maximum control, no dependency. | |
| Owl library | Elixir TUI library. | |
| Ratatouille | Elm-arch Elixir TUI. | |
| Raxol (user-specified) | Elm Architecture, SSH-native, OTP GenServer. | ✓ |

**User's choice:** Raxol v2.4.0. Integration: our `:ssh.daemon/1` with Raxol's `CLIHandler` as `ssh_cli` option.

---

| Option | Description | Selected |
|--------|-------------|----------|
| One Raxol app per screen | Clean separation. | |
| Single app, router-style (conductor pattern) | User's articulated mental model. | ✓ |

**User's choice:** Single `Foglet.TUI.App` as conductor. screens/* = scores, widgets/* = instruments, doors/* = guest performers. `process_component/2` used sparingly for genuinely independent sub-experiences.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Session GenServer owns all state | Consistent with ARCHITECTURE.md. | |
| State tripartite (user-defined) | Domain→Postgres, Session→GenServer, UI→Raxol model. | ✓ |

**User's choice:** Three-layer state: Domain state in Postgres, session identity/policy in Session GenServer, UI state in Raxol model. Session starts Raxol app via `Raxol.Core.RuntimeApplication`. PubSub for system events. Session pings Raxol for heartbeat/`last_seen_at`.

---

| Option | Description | Selected |
|--------|-------------|----------|
| lib/foglet_bbs_web/tui/ | Near web/interface layer. | |
| lib/foglet_bbs/tui/ | Domain-level placement. | ✓ |

**User's choice:** `lib/foglet_bbs/tui/` with `app.ex`, `screens/`, `widgets/`, `doors/`.

---

Other decisions in this area:
- Raxol version: 2.4.0 (pinned explicitly)
- Theming: hardcode single green-on-black default; Phase 4 adds stubs
- Keyboard: single-key shortcuts everywhere; status bar shows keys
- Error UX: modal error/alert widget
- Testing: unit test `update/2` and `view/1` directly — no SSH harness in Phase 3

---

## Guest Flow Shape

| Option | Description | Selected |
|--------|-------------|----------|
| Login-or-register prompt | Immediate menu on unauthenticated connect. | ✓ |
| Login prompt first, register on failure | Slightly awkward for new visitors. | |
| Browse-as-guest first | Not in Phase 3 scope. | |

**User's choice:** Login-or-register prompt immediately. When registration disabled, `[R]` option hidden.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Handle → email → password | Phase 1 token URL-based. | |
| Code in wizard (alphanumeric) | User preference. | ✓ |

**User's choice:** Short alphanumeric verification code (e.g. `XK7P2Q`). Replaces URL-based tokens from Phase 1. `user_tokens` table repurposed. 15-minute expiry, 5 attempts then cooldown.

Registration wizard: in `invite_only` mode: invite code → handle → email → password → verify code. In `open`/`sysop_approved`: handle → email → password → verify code.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Hold session open + poll DB | Code prompt stays up. | ✓ |
| Disconnect with 'check your email' | Session ends after registration. | |

**User's choice:** Hold session open. Code prompt in BBS session. Dev: console log. Prod: emailed (Phase 10).

---

| Option | Description | Selected |
|--------|-------------|----------|
| Disconnect with message (sysop-approved pending) | Clean. Email notification in Phase 10. | ✓ |
| Hold session open | Could be very long wait. | |

**User's choice:** Disconnect with pending message. Email notification deferred to Phase 10.

---

| Option | Description | Selected |
|--------|-------------|----------|
| 'Registration is closed' message then disconnect | Clear. | |
| Login screen only — no register option shown | Cleaner menu. | ✓ |

**User's choice:** Hide `[R]` option from login-or-register menu when registration disabled.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Optional SSH key during registration | Convenient for power users. | |
| No — defer to in-TUI key management | IDNT-04 scope. | ✓ |

**User's choice:** No SSH keys during registration. Defer to in-TUI key management after login.

---

## Post Composer UX

| Option | Description | Selected |
|--------|-------------|----------|
| Raxol multi-line text input widget | Consistent, scrollable, built-in. | ✓ |
| External editor ($EDITOR) | Complex SSH framing issues. | |
| Line-by-line BBS-style | Authentic but poor UX. | |

**User's choice:** Raxol built-in multi-line scrollable text input widget.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Full-screen with header and key bar | Clean, full context. | ✓ |
| Inline panel at bottom of thread view | Cramped at 80×24. | |

**User's choice:** Full-screen composer with header (thread title + replying-to context), quote excerpt (first ~5 lines, dimmed), text area, key bar.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Tab toggles edit/preview | Preview before send. | ✓ |
| No preview in Phase 3 | Simpler. | |

**User's choice:** Tab toggles raw Markdown / rendered ANSI preview.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Ctrl+S sends | Low accidental-submit risk. | ✓ |
| Ctrl+Enter | Terminal compat concerns. | |

**User's choice:** Ctrl+S to submit.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Configurable, default 8192 chars | Sysop-adjustable. | ✓ |
| Hardcoded 4096 chars | Simpler. | |

**User's choice:** Configurable via runtime config (`max_post_length`), default 8192.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Show quoted excerpt above text area | Context for reply. | ✓ |
| Header only (replying to @handle) | Minimal. | |

**User's choice:** Show first ~5 lines of reply-to post, dimmed, above text area.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Confirm discard if content entered | Avoid accidental loss. | |
| Ctrl+C cancels immediately | BBS-traditional. | ✓ |

**User's choice:** Ctrl+C cancels immediately, no warning.

---

## Claude's Discretion

- SSH host key storage and generation on first boot
- Session reconnect grace window (default ~30s, no user config in Phase 3)
- Read pointer advance timing (on page-through, flush on screen transition)
- Board/thread/post list ordering and display density
- Navigation routing between screens inside `Foglet.TUI.App`

## Deferred Ideas

- Browse-as-guest (read-only without account) — not in Phase 3 requirements
- SSH key collection during registration — IDNT-04 post-login scope
- Full multi-theme support — Phase 4 stubs, full themes later
- E2E SSH test harness — ARCHITECTURE.md §12 future goal
- Invite code generation by mods/any user — config key wired, grant levels later
