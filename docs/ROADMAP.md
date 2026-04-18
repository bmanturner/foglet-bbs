# Foglet Roadmap

This roadmap is organized by dependency — fundamentals first, features that depend on fundamentals after. Milestones are logical units of work, not calendar commitments. Each milestone should leave the system in a deployable, demoable state.

No target dates. The order is the commitment.

---

## Milestone 0 — Foundations

The scaffolding everything else sits on. Nothing user-facing.

- Phoenix project scaffolded (`mix phx.new foglet --no-assets --no-html --no-live --no-mailer`)
  - We re-enable the mailer later; start minimal
- Ecto + Postgres wired up, migrations working
- CI pipeline (format, credo, test) — even as a solo dev, this pays for itself
- `.tool-versions` pinning Elixir/Erlang/Postgres
- `config/runtime.exs` reading environment variables; secrets kept out of repo
- Dev database seed scaffold
- Logger configured, basic Telemetry wired
- A single `mix foglet.doctor` task that sanity-checks the environment

Exit criteria: `mix test` runs green with zero tests. `mix phx.server` boots cleanly.

---

## Milestone 1 — Accounts & identity

Users can exist. No interface yet; all via Mix tasks and iex.

- `users` schema with citext handle, email, Argon2 password
- `ssh_keys` schema (not yet used)
- `phx.gen.auth` generated and adapted for our shape (no web routes; just the domain modules and tokens)
- Account creation, password verification, email verification token generation
- Handle uniqueness (case-insensitive) and display-case preservation
- `mix foglet.user.create` — sysop creates accounts manually
- `mix foglet.user.promote` — assign sysop/mod roles
- `roles` on users (user / mod / sysop)
- Account deletion flow with post-anonymization scaffolding (the anonymize operation itself comes later, but the user row deletion path exists)
- Tests for account lifecycle

Exit criteria: you can create yourself as a sysop user at the command line.

---

## Milestone 2 — Domain core: boards, threads, posts

The data model that makes this a BBS. Still no interface.

- `categories`, `boards`, `threads`, `posts` schemas and migrations
- Per-board message-number allocation through a `Foglet.Boards.Server` GenServer (one per board, started via DynamicSupervisor, registered by board id)
- Board server supervision under `Foglet.Boards.Supervisor`
- Thread creation (always creates a root post)
- Post creation, edit (with `post_edits` history), soft-delete
- Markdown parsing and rendering to a terminal-friendly representation (stored raw; rendered at display time)
- `board_subscriptions`, `board_read_pointers`, `thread_read_pointers`
- Unread counts queries
- Property tests for message-number monotonicity under concurrent inserts
- Seeds for a default category + board layout

Exit criteria: you can script a conversation in iex — create users, subscribe them to boards, post threads, reply, edit, check unread counts.

---

## Milestone 3 — SSH server and minimal TUI

The first user-facing interface. Functional, not yet beautiful.

- `Foglet.SSH.Supervisor` wrapping `:ssh` daemon
- Persistent host key in `priv/ssh/`
- SSH password auth against the user store
- SSH public-key auth against `ssh_keys`
- Per-connection Session process via `Foglet.Sessions.Supervisor`
- Enforcement of one-session-per-user (replace-old-session-with-notify)
- Minimal TUI framework: input handling, ANSI escape output, screen clearing, cursor control
- Terminal size via PTY/window-change events
- Screens: login, main menu, board list, thread list, post reader, post composer
- Basic navigation: menu-driven with single-key shortcuts
- Read pointers advance as you read

Exit criteria: SSH in, read threads, post replies, come back tomorrow and see unread indicators working.

---

## Milestone 4 — Presence, online list, login sequence

The BBS feel starts here.

- Phoenix Presence integrated with Sessions
- "Who's online" view, updated live
- `last_callers` logged on disconnect (opt-in per user)
- Login sequence:
  - ANSI banner (sysop-configurable, CP437-translated if needed)
  - News of the day / bulletins (sysop-editable, plural)
  - Last callers display (those who opted in)
- CP437-to-Unicode translation module with test fixtures from the classic ANSI art corpus
- User preferences table and flow (opt in/out of last-caller visibility, choose theme — themes are a stub for now)

Exit criteria: connecting feels like *arriving somewhere*, not opening a form.

---

## Milestone 5 — Chat

Real-time synchronous interaction.

- `Foglet.Chat.Supervisor` with `Foglet.Chat.Lobby` and on-demand per-board `Foglet.Chat.Room` processes
- PubSub topics for each room
- Chat message persistence with bounded retention
- TUI chat screen with split layout (roster + message pane)
- Entering/leaving rooms updates Presence
- `/commands` for chat (nick color, leave, whisper — basic set)
- Chat history scrollback on join

Exit criteria: two SSH clients can hold a conversation in the lobby and in a board room.

---

## Milestone 6 — DMs, mentions, notifications

Asynchronous one-to-one and directed communication.

- `direct_messages` schema, DM composer and reader in TUI
- `@handle` mention detection in posts and chat
- `notifications` schema and dispatcher
- Notification kinds: mention, reply-to-your-post, new DM, subscribed-thread update, mod-action-on-your-content
- Notification inbox in the TUI (unread badge on main menu)
- Real-time notification delivery to the active Session via PubSub
- Notification read/unread state

Exit criteria: one user can mention another and both get a real-time in-BBS notification; DMs work end-to-end.

---

## Milestone 7 — Moderation

The unglamorous layer that keeps communities habitable.

- `reports` schema and "report this post/user" action in TUI
- `mod_actions` audit log, visible to all mods
- `user_sanctions` schema
- Moderation actions implemented: warn, mute, temp ban, permanent ban, delete post, lock thread, sticky thread, move thread
- Sanction enforcement in the post/DM/chat paths
- Mod queue screen in TUI (list open reports, act on them)
- Per-board moderator assignments
- New-user rate limits (configurable thresholds)
- Rate limiter module backed by ETS

Exit criteria: a mod can SSH in, see the report queue, and issue sanctions that take effect immediately.

---

## Milestone 8 — Sysop administration in-TUI

Day-to-day ops without leaving the terminal.

- Sysop menu in TUI (visible only to sysop role)
- Category/board CRUD
- Banner and news-of-the-day editor
- Oneliner moderation
- User admin (view, promote/demote, sanction)
- Runtime config editor backed by the `configuration` table
- Site-wide announcements (broadcast to all active Sessions)

Mix tasks remain for bootstrap and break-glass, but the day-to-day experience is inside the BBS.

Exit criteria: a sysop can run the entire BBS from their SSH session.

---

## Milestone 9 — Search, upvotes, oneliners, last-caller polish

The connective tissue features.

- Postgres full-text search with generated tsvector column on posts
- Search scopes: within current board, by user
- Search screen in TUI
- Upvote model, toggle from post reader, display counts
- Oneliners ring buffer + DB persistence, shoutbox on main menu
- User profile screen with handle, location, tagline, join date, post count, recent activity
- Profile editing

Exit criteria: all the "fill out the experience" features are in; the BBS feels complete to a solo user.

---

## Milestone 10 — Email notifications

External reach, opt-in only.

- Mailer re-enabled (`Swoosh`)
- SMTP configuration via environment variables
- Opt-in digest preferences per user (daily / weekly / off)
- Scheduled job (Oban) to compile and send digests
- Unsubscribe flow
- Templates for digest and verification emails

Exit criteria: a user can opt into a weekly digest and receive one; the sysop can disable email entirely.

---

## Milestone 11 — Observability and operations polish

For the sysop, not the user.

- LiveDashboard mounted on Phoenix endpoint, sysop-only access plug
- Telemetry events across domain modules
- Sentry integration (optional via env var)
- `mix foglet.archive` — read-only mode (login banner switches, posting disabled, reads work)
- Data export: user self-serve download of their posts and DMs
- Sysop data-export mix task for account-deletion fulfillment

Exit criteria: the sysop can operate the BBS confidently in production.

---

## Milestone 12 — Public release prep

Turning the private project into a shareable artifact.

- License file (MIT or Apache 2.0)
- README polish
- `docs/SYSOP.md` — full install guide, configuration reference, upgrade notes
- `docs/DEV.md` — contributor onboarding
- `CONTRIBUTING.md`
- `CODE_OF_CONDUCT.md` (reassessed — the survey said "wait and see"; public release is the trigger)
- Version tagging scheme, changelog
- Public repository

Exit criteria: someone other than you can install Foglet and stand up a BBS.

---

## Milestone 13 — Go CLI client (post-public)

The second frontend. Starts once SSH is stable.

- Phoenix Channels authentication (token issued from the TUI or CLI login)
- Client-side Channels library in Go
- Bubble Tea / Charm TUI architecture
- Feature parity target: boards, threads, posts, chat, DMs, notifications
- Capability negotiation on connect (true color, unicode width, OS integrations)
- Client distribution: prebuilt binaries per-platform

Exit criteria: the CLI can do everything the SSH client can, and feels better on a modern terminal.

---

## Milestone 14 — Door games

At least one. Preserves BBS identity.

- Framework for in-session "applications" that take over the screen and return to the main menu on exit
- First game: scoped small (e.g., daily trivia, word-of-the-day puzzle, or a Hunt-the-Wumpus clone)
- Persistent game state per user
- Leaderboard integration with the BBS profile

Exit criteria: there is a reason to come back to the BBS besides reading posts.

---

## Deferred ("maybe someday")

Explicitly out of the current roadmap. Revisit only with a deliberate decision.

- Telnet support
- Mobile app
- File upload areas
- Full GDPR compliance workflow (current: best-effort)
- Federation with other BBSes or the fediverse
- Voice/video
- Paid/hosted offering

---

## Working principles

- Each milestone ends deployable. No "big bang" integrations.
- Schema changes ship with migrations and rollbacks.
- Tests accompany features; regressions get a test before the fix.
- TUI changes include a screenshot (asciicast or text capture) in the PR description once public.
- Sysop-facing changes update `docs/SYSOP.md` in the same change.