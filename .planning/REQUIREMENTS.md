# Requirements: Foglet BBS

**Defined:** 2026-04-18
**Core Value:** Two users SSHing into the same BBS and feeling like they're actually *present* together — boards, unread counts, who's online, real-time chat, and the sense of place that makes a BBS a BBS.

## v1 Requirements

### Identity

- [ ] **IDNT-01**: User can create an account with email and password (Argon2-hashed)
- [ ] **IDNT-02**: User receives an email verification link after signup
- [ ] **IDNT-03**: User has a permanent, case-preserving handle that is unique case-insensitively (`citext`)
- [ ] **IDNT-04**: User can add SSH public keys to their account from inside the TUI
- [ ] **IDNT-05**: Sysop can create accounts via `mix foglet.user.create`
- [ ] **IDNT-06**: Sysop can assign roles (user / mod / sysop) via `mix foglet.user.promote`
- [ ] **IDNT-07**: User account can be deleted with post-anonymization (rewrites authorship to tombstone user, clears profile fields)
- [ ] **IDNT-08**: User can reset their password

### Boards

- [ ] **BOARD-01**: Sysop can create Categories → Boards (hierarchical structure)
- [ ] **BOARD-02**: User can create a Thread (title + root post) in a board
- [ ] **BOARD-03**: User can reply to a thread (optional reply-to metadata; does not affect ordering)
- [ ] **BOARD-04**: User can edit their own posts; edit history preserved in `post_edits`
- [ ] **BOARD-05**: Posts support Markdown and render to a terminal-friendly representation
- [ ] **BOARD-06**: Per-board message numbers are sequential and allocated by `Foglet.Boards.Server` GenServer (not DB sequences)
- [ ] **BOARD-07**: User can subscribe to boards; default subscriptions set on signup
- [ ] **BOARD-08**: Per-user per-board read pointer tracks last-read message number
- [ ] **BOARD-09**: Per-user per-thread read pointer tracks last-read post
- [ ] **BOARD-10**: Unread counts are queryable per user per board and per thread
- [ ] **BOARD-11**: Posts support soft-delete (deleted_at); thread coherence and message numbers preserved
- [ ] **BOARD-12**: Threads can be locked, stickied, or moved between boards (by mods/sysop)

### SSH & TUI

- [ ] **SSH-01**: Erlang `:ssh` daemon accepts connections; persistent host key survives deploys
- [ ] **SSH-02**: User can authenticate via SSH password (Argon2-checked against user store)
- [ ] **SSH-03**: User can authenticate via SSH public key (matched against registered keys)
- [ ] **SSH-04**: New users can register an account through an SSH guest flow (no prior account required)
- [ ] **SSH-05**: One active session per user enforced; reconnecting replaces old session with notification
- [ ] **SSH-06**: Terminal size obtained via PTY/window-change; TUI adapts (80×24 baseline, wider views use full width)
- [ ] **SSH-07**: TUI supports: login screen, main menu, board list, thread list, post reader, post composer
- [ ] **SSH-08**: Navigation is menu-driven with single-key shortcuts throughout
- [ ] **SSH-09**: Read pointers advance automatically as user reads posts/threads

### Presence & Login Sequence

- [ ] **PRSNC-01**: Phoenix Presence tracks all online users; "who's online" shown on main menu, updated live
- [ ] **PRSNC-02**: Login sequence: ANSI banner → news of the day / bulletins → last callers
- [ ] **PRSNC-03**: Sysop can edit the login banner and news bulletins from inside the TUI
- [ ] **PRSNC-04**: Last callers logged on disconnect; user can opt out of appearing in the list
- [ ] **PRSNC-05**: CP437-to-Unicode translation handles classic `.ANS` ANSI art files
- [ ] **PRSNC-06**: User can select from multiple color themes (stub in M4; full themes later)

### Chat

- [ ] **CHAT-01**: Global chat lobby (`Foglet.Chat.Lobby`) available from main menu
- [ ] **CHAT-02**: Per-board chat rooms spawned on demand (`Foglet.Chat.Room`)
- [ ] **CHAT-03**: Chat messages persisted with bounded retention; scrollback available on join
- [ ] **CHAT-04**: TUI chat screen has split layout (roster pane + message pane)
- [ ] **CHAT-05**: Users entering/leaving rooms updates Presence
- [ ] **CHAT-06**: Basic `/commands` supported in chat (leave, whisper)

### Social

- [ ] **SOCL-01**: User can send a Direct Message to any other user
- [ ] **SOCL-02**: User can read received DMs; DM reader available from main menu
- [ ] **SOCL-03**: `@handle` mentions detected in posts and chat messages
- [ ] **SOCL-04**: User receives in-BBS notification when mentioned, replied to, or sent a DM
- [ ] **SOCL-05**: Notification inbox in TUI with unread badge on main menu; real-time delivery via PubSub
- [ ] **SOCL-06**: User can upvote posts; upvote count shown in post reader
- [ ] **SOCL-07**: User profile screen shows handle, location, tagline, join date, post count, recent activity
- [ ] **SOCL-08**: User can edit their profile (location, tagline)
- [ ] **SOCL-09**: Oneliners / shoutbox available on main menu; ring buffer backed by DB
- [ ] **SOCL-10**: User can post a oneliner; recent oneliners displayed on main menu

### Moderation

- [ ] **MODR-01**: User can report a post or user from the TUI
- [ ] **MODR-02**: Mods can view the open report queue in the TUI
- [ ] **MODR-03**: Mods can warn, mute, temp-ban, or permanently ban a user
- [ ] **MODR-04**: Mods can delete a post, lock a thread, sticky a thread, or move a thread
- [ ] **MODR-05**: Sanctions enforced immediately in post, DM, and chat paths
- [ ] **MODR-06**: All mod actions logged to `mod_actions` audit log, visible to all mods
- [ ] **MODR-07**: Per-board moderator assignments managed by sysop
- [ ] **MODR-08**: New-user posting rate limits (configurable thresholds, ETS-backed)

### Sysop Administration

- [ ] **SYSOP-01**: Sysop menu visible inside SSH TUI (role-gated to sysop)
- [ ] **SYSOP-02**: Sysop can create, edit, and delete categories and boards from TUI
- [ ] **SYSOP-03**: Sysop can promote/demote users and view account details from TUI
- [ ] **SYSOP-04**: Runtime configuration editable from TUI (backed by `configuration` table, no redeploy)
- [ ] **SYSOP-05**: Sysop can broadcast a site-wide announcement to all active sessions
- [ ] **SYSOP-06**: Phoenix LiveDashboard mounted on Phoenix endpoint, sysop-only access plug

### Search

- [ ] **SRCH-01**: User can search posts with Postgres full-text search (generated tsvector + GIN index)
- [ ] **SRCH-02**: Search scoped to: current board or by user
- [ ] **SRCH-03**: Search screen accessible from TUI

### Email

- [ ] **EMAIL-01**: User receives email verification on signup (Swoosh SMTP)
- [ ] **EMAIL-02**: User can opt into email digests (daily / weekly / off)
- [ ] **EMAIL-03**: Scheduled Oban job compiles and sends opt-in digests
- [ ] **EMAIL-04**: User can unsubscribe from email digests
- [ ] **EMAIL-05**: Sysop can disable email delivery entirely (env var toggle)

### Operations

- [ ] **OPS-01**: Telemetry events emitted across domain modules
- [ ] **OPS-02**: Optional Sentry integration (enabled via `SENTRY_DSN` env var)
- [ ] **OPS-03**: `mix foglet.archive` switches instance to read-only mode (login banner updated, posting disabled)
- [ ] **OPS-04**: User can download their own posts and DMs (data export)
- [ ] **OPS-05**: Sysop can export a user's data (for account-deletion fulfillment)

### Public Release

- [ ] **REL-01**: License file committed (MIT or Apache 2.0)
- [ ] **REL-02**: `docs/SYSOP.md` covers installation, configuration, moderation, and operations
- [ ] **REL-03**: `docs/DEV.md` covers contributor onboarding
- [ ] **REL-04**: `CONTRIBUTING.md` and `CODE_OF_CONDUCT.md` present
- [ ] **REL-05**: Version tagging scheme and changelog established; repository made public

### Go CLI Client

- [ ] **CLI-01**: Phoenix Channels authentication via token (CLI login flow)
- [ ] **CLI-02**: Go CLI client with Bubble Tea / Charm TUI matches SSH client feature parity (boards, threads, posts, chat, DMs, notifications)
- [ ] **CLI-03**: Capability negotiation on connect (true color, unicode width)
- [ ] **CLI-04**: Prebuilt binaries distributed per platform

### Door Games

- [ ] **GAME-01**: Framework for in-session "applications" that take over the screen and return to main menu on exit
- [ ] **GAME-02**: First game shipped (daily trivia, word puzzle, or Hunt-the-Wumpus clone — scoped small)
- [ ] **GAME-03**: Persistent per-user game state
- [ ] **GAME-04**: Leaderboard integrated with user profile

## v2 Requirements

*(None — full roadmap is in v1 scope. Deferred items below are explicitly out of scope.)*

## Out of Scope

| Feature | Reason |
|---------|--------|
| End-user web UI | Product identity is terminal-first; web UI dilutes this and doubles surface area |
| Federation | Each instance is its own world; ActivityPub/FidoNet bridges not planned |
| File upload areas | Not a hosting platform |
| Mobile app | Not near-term; a client may come someday |
| Telnet support | Aesthetic/nostalgia only; off by default if ever added; not in current roadmap |
| Voice/video | Fundamentally different product category |
| Paid/hosted offering | Not planned |
| Full GDPR compliance workflow | Best-effort for now; requires deliberate future decision |
| Multi-node clustering | Single-node must be rock-solid first; BEAM makes it possible later |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| IDNT-01 | Phase 1 | Pending |
| IDNT-02 | Phase 1 | Pending |
| IDNT-03 | Phase 1 | Pending |
| IDNT-04 | Phase 1 | Pending |
| IDNT-05 | Phase 1 | Pending |
| IDNT-06 | Phase 1 | Pending |
| IDNT-07 | Phase 1 | Pending |
| IDNT-08 | Phase 1 | Pending |
| BOARD-01 | Phase 2 | Pending |
| BOARD-02 | Phase 2 | Pending |
| BOARD-03 | Phase 2 | Pending |
| BOARD-04 | Phase 2 | Pending |
| BOARD-05 | Phase 2 | Pending |
| BOARD-06 | Phase 2 | Pending |
| BOARD-07 | Phase 2 | Pending |
| BOARD-08 | Phase 2 | Pending |
| BOARD-09 | Phase 2 | Pending |
| BOARD-10 | Phase 2 | Pending |
| BOARD-11 | Phase 2 | Pending |
| BOARD-12 | Phase 2 | Pending |
| SSH-01 | Phase 3 | Pending |
| SSH-02 | Phase 3 | Pending |
| SSH-03 | Phase 3 | Pending |
| SSH-04 | Phase 3 | Pending |
| SSH-05 | Phase 3 | Pending |
| SSH-06 | Phase 3 | Pending |
| SSH-07 | Phase 3 | Pending |
| SSH-08 | Phase 3 | Pending |
| SSH-09 | Phase 3 | Pending |
| PRSNC-01 | Phase 4 | Pending |
| PRSNC-02 | Phase 4 | Pending |
| PRSNC-03 | Phase 4 | Pending |
| PRSNC-04 | Phase 4 | Pending |
| PRSNC-05 | Phase 4 | Pending |
| PRSNC-06 | Phase 4 | Pending |
| CHAT-01 | Phase 5 | Pending |
| CHAT-02 | Phase 5 | Pending |
| CHAT-03 | Phase 5 | Pending |
| CHAT-04 | Phase 5 | Pending |
| CHAT-05 | Phase 5 | Pending |
| CHAT-06 | Phase 5 | Pending |
| SOCL-01 | Phase 6 | Pending |
| SOCL-02 | Phase 6 | Pending |
| SOCL-03 | Phase 6 | Pending |
| SOCL-04 | Phase 6 | Pending |
| SOCL-05 | Phase 6 | Pending |
| SOCL-06 | Phase 9 | Pending |
| SOCL-07 | Phase 9 | Pending |
| SOCL-08 | Phase 9 | Pending |
| SOCL-09 | Phase 9 | Pending |
| SOCL-10 | Phase 9 | Pending |
| MODR-01 | Phase 7 | Pending |
| MODR-02 | Phase 7 | Pending |
| MODR-03 | Phase 7 | Pending |
| MODR-04 | Phase 7 | Pending |
| MODR-05 | Phase 7 | Pending |
| MODR-06 | Phase 7 | Pending |
| MODR-07 | Phase 7 | Pending |
| MODR-08 | Phase 7 | Pending |
| SYSOP-01 | Phase 8 | Pending |
| SYSOP-02 | Phase 8 | Pending |
| SYSOP-03 | Phase 8 | Pending |
| SYSOP-04 | Phase 8 | Pending |
| SYSOP-05 | Phase 8 | Pending |
| SYSOP-06 | Phase 8 | Pending |
| SRCH-01 | Phase 9 | Pending |
| SRCH-02 | Phase 9 | Pending |
| SRCH-03 | Phase 9 | Pending |
| EMAIL-01 | Phase 10 | Pending |
| EMAIL-02 | Phase 10 | Pending |
| EMAIL-03 | Phase 10 | Pending |
| EMAIL-04 | Phase 10 | Pending |
| EMAIL-05 | Phase 10 | Pending |
| OPS-01 | Phase 11 | Pending |
| OPS-02 | Phase 11 | Pending |
| OPS-03 | Phase 11 | Pending |
| OPS-04 | Phase 11 | Pending |
| OPS-05 | Phase 11 | Pending |
| REL-01 | Phase 12 | Pending |
| REL-02 | Phase 12 | Pending |
| REL-03 | Phase 12 | Pending |
| REL-04 | Phase 12 | Pending |
| REL-05 | Phase 12 | Pending |
| CLI-01 | Phase 13 | Pending |
| CLI-02 | Phase 13 | Pending |
| CLI-03 | Phase 13 | Pending |
| CLI-04 | Phase 13 | Pending |
| GAME-01 | Phase 14 | Pending |
| GAME-02 | Phase 14 | Pending |
| GAME-03 | Phase 14 | Pending |
| GAME-04 | Phase 14 | Pending |

**Coverage:**
- v1 requirements: 85 total
- Mapped to phases: 85
- Unmapped: 0 ✓

---
*Requirements defined: 2026-04-18*
*Last updated: 2026-04-18 after roadmap creation*
