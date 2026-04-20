# Foglet BBS

## What This Is

A self-hostable, terminal-native bulletin board system built on Elixir/Phoenix and delivered over SSH. Sysops install it on their own hardware or cloud host and run it for their community — users connect via SSH (or eventually a Go CLI client) and meet in a persistent, stateful space of boards, threads, chat, presence, and the unmistakable sense of *being somewhere* that defined the BBS era.

This is not a forum with a terminal option. It's a terminal BBS first, end to end.

## Core Value

Two users SSHing into the same BBS and feeling like they're actually *present* together — boards, unread counts, who's online, real-time chat, and the sense of place that makes a BBS a BBS, not just a message board.

## Requirements

### Validated

- ✓ Phoenix project scaffolded (no-assets, no-html, no-live, no-mailer baseline) — M0
- ✓ Ecto + PostgreSQL wired up, migrations working — M0
- ✓ CI pipeline via `mix precommit` (format, credo strict, test) — M0
- ✓ `.tool-versions` pinning Elixir 1.19.5 / Erlang OTP 28.3.1 — M0
- ✓ `config/runtime.exs` reading env vars; secrets kept out of repo — M0
- ✓ Dev database seed scaffold — M0
- ✓ Logger + basic Telemetry wired — M0
- ✓ `mix foglet.doctor` sanity-check task — M0
- ✓ Oban included for background job processing — M0
- ✓ Argon2 (`argon2_elixir`) configured for password hashing — M0

### Active

**Milestone 1 — Accounts & Identity**
- [ ] `users` schema: citext handle (case-insensitive uniqueness, display-case preserved), email, Argon2 password hash, roles (user/mod/sysop)
- [ ] `ssh_keys` schema (placeholder — not yet used in auth)
- [ ] `phx.gen.auth` adapted for Foglet's shape (domain modules only — no web routes)
- [ ] Account creation, password verification, email verification token generation
- [ ] `mix foglet.user.create` and `mix foglet.user.promote` Mix tasks
- [ ] Account deletion with post-anonymization scaffolding
- [ ] Tests for account lifecycle

**Milestone 2 — Domain Core: Boards, Threads, Posts**
- [ ] `categories`, `boards`, `threads`, `posts` schemas and migrations
- [ ] `Foglet.Boards.Server` GenServer for per-board message-number allocation (DynamicSupervisor)
- [ ] Thread creation (always creates a root post), post creation, edit (with edit history), soft-delete
- [ ] Markdown parsing and rendering to terminal-friendly representation
- [ ] `board_subscriptions`, `board_read_pointers`, `thread_read_pointers`
- [ ] Unread counts queries
- [ ] Property tests for message-number monotonicity under concurrent inserts
- [ ] Seeds for default category + board layout

**Milestone 3 — SSH Server & Minimal TUI** ✓ Complete 2026-04-19
- [x] `Foglet.SSH.Supervisor` wrapping `:ssh` daemon with persistent host key — Validated in Phase 03
- [x] SSH password auth and public-key auth against user store — Validated in Phase 03
- [x] Per-connection Session process (`Foglet.Sessions.Supervisor`), one-session-per-user enforcement — Validated in Phase 03
- [x] TUI framework: input handling, ANSI output, screen clearing, cursor control — Validated in Phase 03
- [x] Terminal size via PTY/window-change events — Validated in Phase 03 (gap closure 03-06)
- [x] TUI screens: login, main menu, board list, thread list, post reader, post composer — Validated in Phase 03
- [x] Read pointers advance as you read — Validated in Phase 03

**Milestone 4 — Presence, Online List, Login Sequence**
- [ ] Phoenix Presence integrated with Sessions; "who's online" updated live
- [ ] `last_callers` logged on disconnect (opt-in)
- [ ] Login sequence: ANSI banner → news of the day → last callers
- [ ] CP437-to-Unicode translation module with test fixtures
- [ ] User preferences (last-caller visibility opt-out, theme stub)

**Milestone 5 — Chat**
- [ ] `Foglet.Chat.Supervisor` with global lobby and per-board room processes (DynamicSupervisor)
- [ ] Chat message persistence with bounded retention; scrollback on join
- [ ] TUI chat screen with split layout (roster + message pane)
- [ ] `/commands` for chat (basic set: leave, whisper)

**Milestone 6 — DMs, Mentions, Notifications**
- [ ] `direct_messages` schema; DM composer and reader in TUI
- [ ] `@handle` mention detection in posts and chat
- [ ] `notifications` schema, dispatcher, and real-time delivery via PubSub to active Sessions
- [ ] Notification inbox in TUI with unread badge on main menu

**Milestone 7 — Moderation**
- [ ] `reports`, `mod_actions`, `user_sanctions` schemas
- [ ] Moderation actions: warn, mute, temp ban, permanent ban, delete post, lock/sticky/move thread
- [ ] Sanction enforcement in post/DM/chat paths
- [ ] Mod queue screen in TUI; per-board moderator assignments
- [ ] New-user rate limits (ETS-backed, configurable thresholds)

**Milestone 8 — Sysop Administration In-TUI**
- [ ] Sysop menu in TUI (role-gated)
- [ ] Category/board CRUD; banner and news-of-the-day editor
- [ ] User admin (view, promote/demote, sanction); oneliner moderation
- [ ] Runtime config editor backed by `configuration` table; site-wide broadcast

**Milestone 9 — Search, Upvotes, Oneliners, Profile Polish**
- [ ] Postgres full-text search (generated tsvector + GIN index on `posts.body`)
- [ ] Search scopes: within board, by user; search screen in TUI
- [ ] Upvote model with toggle and count display
- [ ] Oneliners ring buffer + shoutbox on main menu
- [ ] User profile screen with edit flow

**Milestone 10 — Email Notifications**
- [ ] Swoosh mailer re-enabled with SMTP config via env vars
- [ ] Opt-in email digests (daily/weekly/off) via Oban scheduled job
- [ ] Unsubscribe flow; digest and verification email templates

**Milestone 11 — Observability & Operations Polish**
- [ ] LiveDashboard mounted, sysop-only access plug
- [ ] Telemetry events across domain modules; optional Sentry integration
- [ ] `mix foglet.archive` read-only mode
- [ ] Data export: user self-serve download; sysop export for account-deletion fulfillment

**Milestone 12 — Public Release Prep**
- [ ] License file (MIT or Apache 2.0)
- [ ] `docs/SYSOP.md` install guide + configuration reference
- [ ] `docs/DEV.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`
- [ ] Version tagging, changelog, public repository

**Milestone 13 — Go CLI Client**
- [ ] Phoenix Channels authentication (token flow)
- [ ] Go CLI with Bubble Tea / Charm TUI; feature parity with SSH client
- [ ] Capability negotiation; prebuilt binary distribution per platform

**Milestone 14 — Door Games**
- [ ] Framework for in-session "applications" that take over screen and return to main menu
- [ ] First game (scoped small: daily trivia, word puzzle, or Hunt-the-Wumpus)
- [ ] Persistent game state per user; leaderboard integration

### Out of Scope

- End-user web UI — the product identity is terminal-first; a web UI would dilute this
- Federation (ActivityPub, FidoNet bridges, fediverse) — each instance is its own world
- File upload areas — not a hosting platform
- Mobile app — not near-term
- Voice/video — fundamentally different product category
- Paid/hosted offering — not planned
- Full GDPR compliance workflow — best-effort for now; explicit future decision required to change

## Context

Milestone 0 is complete: Phoenix scaffold with full dev tooling, Ecto/Postgres, CI pipeline, SSH scaffolding, Oban, and Argon2 are all wired in. The stack is locked and validated.

The architecture is designed around the BEAM's strengths: one long-lived GenServer per active user session, one GenServer per board (for message-number allocation), chat rooms as processes, Phoenix Presence for cross-node presence. The SSH interface and Phoenix Channels interface are peers — both funnel into the same Session layer.

This is a solo project. No coordination overhead; pace is set by available time.

The existing `docs/ARCHITECTURE.md` is the authoritative design reference. The `docs/ROADMAP.md` (now superseded by this GSD roadmap) defines build order by dependency.

## Constraints

- **Tech stack**: Elixir 1.19.5 / OTP 28.3.1 / Phoenix 1.8 / PostgreSQL — locked; not up for debate
- **Interface**: SSH TUI is the primary and only end-user interface — no web UI for users
- **SSH library**: Erlang's built-in `:ssh` application directly — avoids third-party SSH library overhead
- **Deployment**: Fly.io first; self-hosted hardware second — must work on both
- **Solo**: One developer — prefer clean, boring, well-understood patterns over clever abstractions

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Elixir/BEAM | Concurrency, fault tolerance, Phoenix Channels, Presence, and OTP supervision are the right substrate for a real-time, multi-user system | — Pending validation |
| SSH-only user interface | BBS identity is terminal-first; web UI would dilute the product and double the surface area | — Pending validation |
| `:ssh` Erlang app directly | Avoids third-party SSH library; Erlang's built-in app is mature and well-documented | — Pending validation |
| Board server owns message-number sequence | Avoids DB-side sequence gymnastics; makes sequence testable in isolation | — Pending validation |
| One session per user (singleton, replace-old) | Authentic BBS feel; prevents split-brain user state | — Pending validation |
| Oban for background jobs | Mature, PostgreSQL-backed, well-maintained; already included in scaffold | ✓ Good |
| Registration mode | Open signup vs invite-only vs sysop-approved — not yet decided | — Pending |
| License | MIT vs Apache 2.0 — mentioned as TBD in README | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-04-20 after Phase 2 (markdown rendering correctness) — v1.0.1 polish workstream*
