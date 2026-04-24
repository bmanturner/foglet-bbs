# Foglet BBS

> A self-hostable, terminal-native bulletin board system. A modern homage to the BBS era — built on Elixir, delivered over SSH, operated by sysops.

Foglet is a BBS platform you install on your own machine or cloud host and run for your community. Users connect over SSH (or a first-party CLI client) and meet each other in a persistent, stateful space: boards, threads, DMs, chat, presence, a login banner, and the unmistakable sense of *being somewhere* that made classic BBSes what they were.

This is not a forum with a terminal option. It's a terminal BBS first, end to end.

---

## Design stance

- **Terminal-native, not terminal-as-fallback.** The primary experience is a TUI served over SSH. There is no user-facing web UI. Aesthetic and UX decisions follow from that.
- **Self-hostable.** Each deployment is an independent instance run by a sysop. Foglet ships sensible defaults and exposes the levers sysops care about.
- **Concurrency and presence are first-class.** Built on the BEAM. Who's online, real-time chat, multi-node user sessions, and live board activity are table stakes, not features to graft on later.
- **Classic BBS ethos, modern foundations.** Handles are permanent. Sessions are singular. Message numbers are per-board. The sysop is the host, not a distant admin. Under the hood: Postgres, Ecto, Phoenix Channels, Argon2, OTP.

---

## Feature overview (target state)

**Access**
- SSH server with public-key and password auth
- First-party Go CLI client speaking Phoenix Channels
- Telnet considered for a later release (aesthetic/nostalgia; off by default)

**Identity**
- Email + password registration (Argon2)
- Permanent, case-preserving handles
- One active session per user
- SSH public keys registered against the account

**Message boards**
- Categories → Boards → Threads → Posts
- First-class threads with titles
- Linear replies with reply-to metadata
- Per-board sequential message numbers
- Read pointers: per-user per-board *and* per-user per-thread
- Opt-in board subscriptions with sensible defaults
- Markdown formatting
- Posts always editable; edit history preserved

**Social and presence**
- Who's online on the main menu
- Opt-in last-caller list
- Private messages
- Real-time chat: a global lobby plus per-board rooms
- Classic-style profiles (handle, location, tagline, join date, post count, recent activity)
- `@handle` mentions with notifications
- Simple upvotes on posts
- Oneliners / shoutbox on the main menu

**Moderation**
- Sysop plus per-board moderators
- Reporting from v1
- Actions: warn, mute, temp ban, permanent ban, delete post, lock thread, sticky thread, move thread between boards
- Mod action audit log visible to all mods
- New-user posting rate limits

**Aesthetic**
- Full CP437 / ANSI art rendering for classic .ANS files
- Login sequence: banner + news of the day + last callers
- Multiple user-selectable color themes

**Search**
- Postgres full-text search
- Scopes: within current board, by user (v1)

**Notifications**
- In-app: mentions, replies, DMs, mod actions on your content, subscribed thread updates
- Opt-in email digests (daily/weekly)

**Sysop tooling**
- Admin menus inside the SSH TUI for moderation and day-to-day ops
- Mix tasks (`mix foglet.*`) for install, config, user admin
- Phoenix LiveDashboard for runtime observability (sysop-only, not public)
- Sentry integration optional
- Read-only archive mode for winding a board down

**Door games**
- At least one text game, post-v1

---

## What Foglet is *not*

- Not a Discord alternative. Async boards are the center of gravity; chat is a feature, not the product.
- Not a federated system. Each instance is its own world. (Federation is explicitly out of scope.)
- Not a web forum. There is no end-user web interface and no plans for one.
- Not a mobile app. A client may come someday; it is not near-term.
- Not a file-sharing service. File upload areas are out of scope for the foreseeable future.

---

## Technology

| Layer | Choice |
|---|---|
| Language / runtime | Elixir on the BEAM |
| Framework | Phoenix (for Channels, PubSub, Presence, LiveDashboard) |
| Database | PostgreSQL via Ecto |
| In-memory state | ETS + Phoenix Presence |
| SSH server | Erlang `:ssh` application |
| TUI rendering | Custom (ANSI escape sequences, CP437 translation) |
| CLI client | Go (Bubble Tea / Charm) — post-SSH milestone |
| Password hashing | Argon2 (`argon2_elixir`) |
| Authentication scaffold | `mix phx.gen.auth` as the starting point |
| Deployment | Fly.io and arbitrary self-hosted hardware |
| Secrets | Environment variables via `config/runtime.exs` |

Reverse proxy, TLS, OS, and backup strategy are deliberately left to the sysop. Foglet runs where the sysop runs it.

---

## Status

Pre-alpha. Scaffolding and foundational work in progress. Source is private until stable; public release will be under the Apache License 2.0.

---

## License

Copyright 2026 Brendan Turner

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

  http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

---

## For sysops (future)

A dedicated `docs/SYSOP.md` will cover installation, configuration, moderation workflows, and operational concerns. Not drafted yet.

---

## For developers (future)

`ARCHITECTURE.md` describes the system design. `ROADMAP.md` describes the build order. `CONTRIBUTING.md` will arrive with the public source release.
