# Foglet Architecture

This document describes the shape of the system: the major components, how they talk to each other, the supervision tree, and the core data model. It's written to be a reference for development, not a marketing document. Expect it to evolve as decisions firm up.

---

## 1. System overview

Foglet is a single OTP application (`:foglet`) running on the BEAM. It exposes two network-facing interfaces:

1. **SSH server** — the primary user interface. Each connection drives a TUI.
2. **Phoenix endpoint** — serves Phoenix Channels (for the future Go CLI client) and LiveDashboard (sysop-only observability). Not used for an end-user web UI.

Both interfaces terminate into the same domain core: boards, threads, posts, sessions, presence, chat, moderation. There is one source of truth for domain state (Postgres) and one source of truth for ephemeral state (ETS, via Phoenix Presence and local tables).

```
┌───────────────────────────────────────────────────────────────┐
│                          User clients                         │
│   SSH terminal          Go CLI (future)        Sysop browser  │
└────────┬─────────────────────┬──────────────────────┬─────────┘
         │                     │                      │
         │ SSH                 │ WSS (Channels)       │ HTTPS
         │                     │                      │
┌────────▼──────────┐ ┌────────▼────────┐ ┌───────────▼─────────┐
│  SSH Server       │ │ Phoenix Endpoint│ │ LiveDashboard       │
│  (:ssh app)       │ │   Channels      │ │ (sysop auth only)   │
│                   │ │                 │ │                     │
│  Per-connection   │ │  Per-socket     │ │                     │
│  Session process  │ │  Channel process│ │                     │
└────────┬──────────┘ └────────┬────────┘ └─────────────────────┘
         │                     │
         │  Both map to a single logical "session"
         │                     │
┌────────▼─────────────────────▼────────────────────────────────┐
│                      Session Layer                            │
│   Foglet.Sessions — one GenServer per active user session     │
│   Enforces one-session-per-user rule                          │
└────────┬──────────────────────────────────────────────────────┘
         │
┌────────▼──────────────────────────────────────────────────────┐
│                      Domain Core                              │
│   Accounts · Boards · Threads · Posts · Messages              │
│   Chat · Moderation · Notifications · Search                  │
│   Pure-ish Elixir modules; Ecto for persistence               │
└────────┬───────────────────────────┬──────────────────────────┘
         │                           │
┌────────▼─────────┐       ┌─────────▼──────────┐
│  PostgreSQL      │       │  ETS + Presence    │
│  (Ecto)          │       │  (ephemeral state) │
│  source of truth │       │  presence, caches, │
│  for all         │       │  rate limits,      │
│  domain data     │       │  oneliners buffer  │
└──────────────────┘       └────────────────────┘
```

---

## 2. Supervision tree (target)

The OTP supervision tree is the real blueprint of a BEAM system. This is the target shape; it will be built up in stages as the roadmap progresses.

```
Foglet.Application
├── Foglet.Repo                        (Ecto repo)
├── Phoenix.PubSub (:foglet_pubsub)
├── Foglet.Presence                    (Phoenix Presence)
├── Foglet.Sessions.Supervisor         (DynamicSupervisor)
│     └── Foglet.Sessions.Session × N  (one per active user)
├── Foglet.Boards.Supervisor           (DynamicSupervisor)
│     └── Foglet.Boards.Server × N     (one per board; owns message-number sequence)
├── Foglet.Chat.Supervisor             (DynamicSupervisor)
│     ├── Foglet.Chat.Lobby            (global chat room)
│     └── Foglet.Chat.Room × N         (per-board chat rooms)
├── Foglet.Oneliners                   (GenServer — recent oneliners ring buffer)
├── Foglet.RateLimiter                 (ETS-backed rate limits)
├── Foglet.Notifications.Supervisor
│     ├── Foglet.Notifications.Dispatcher
│     └── Foglet.Notifications.EmailDigest (scheduled)
├── Foglet.SSH.Supervisor              (wraps the :ssh daemon)
├── FogletWeb.Endpoint                 (Phoenix — Channels + LiveDashboard)
├── Foglet.Jobs                        (Oban or similar — background jobs)
└── Foglet.Telemetry                   (metrics reporter)
```

Key choices:

- **Session processes are global.** A Session is registered by user ID via `Registry` or `:global`. Any attempt to open a second session for a user finds the existing one and either replaces it or rejects the new login (configurable; default is "replace and notify the old session").
- **Board servers own their message-number sequence.** Each board has a dedicated GenServer responsible for allocating the next per-board message number. Writes go through the Board server, which persists to Postgres and bumps its in-memory counter. This avoids Postgres-side sequence gymnastics and makes the sequence testable in isolation.
- **Chat rooms are GenServers, not DB-heavy.** Chat history is persisted for scrollback (bounded) but the live room is a process holding recent messages and a subscriber list via PubSub.
- **The SSH and Phoenix interfaces are peers.** Neither is a wrapper around the other. Both funnel into the Session layer.

---

## 3. Connection lifecycle

### SSH connection

1. Erlang `:ssh` daemon accepts the connection.
2. Authentication: SSH pubkey (matched against the user's registered keys) or password (falls back to Argon2-checked password from the DB). New users can't yet SSH in — account creation happens via a separate flow (see §9).
3. On auth success, Foglet starts a `Foglet.Sessions.Session` process (or replaces an existing one) and hands the SSH channel to it.
4. The Session process runs the login sequence: banner, news of the day, last callers, then the main menu.
5. Input bytes from SSH flow into the Session; output bytes (ANSI-escaped TUI frames) flow back out.
6. The Session subscribes to relevant PubSub topics (user-specific notifications, subscribed-board activity, chat rooms if in chat).
7. On disconnect, the Session process terminates and Presence updates fire.

### Phoenix Channel (CLI client — future)

1. CLI client opens a WSS connection to `FogletWeb.Endpoint`.
2. Authenticates via token (obtained via a CLI login flow that exchanges credentials for a token).
3. Joins channels: `user:<id>` for personal events, `board:<id>` for boards they're viewing, `chat:<room>` for chat rooms.
4. A Session process is started/adopted the same way as SSH. The Session is *how* the client gets rendered state; the Channels are *how* data flows.
5. Client-side rendering is the CLI's job; server pushes structured events, not ANSI.

---

## 4. The Session layer

The Session process is the heart of user state. It is:

- **Long-lived** for the duration of a user's presence on the BBS.
- **Singular** per user (enforcing the one-session rule).
- **Interface-agnostic** — it holds state like "current board," "in chat," "unread counts," and receives input from either SSH or Channels.
- **The PubSub subscriber** on the user's behalf.

Session state includes:

- `user_id`, `handle`
- Current "location" (main menu, viewing board X, in thread Y, in chat lobby, composing DM…)
- Active subscriptions (which PubSub topics are we on right now)
- Read-pointer working copies (flushed to Postgres on transition)
- Session-specific preferences (theme, terminal size from NAWS, capabilities)
- Rate-limit state references

Sessions survive transient disconnects when possible — a reconnecting SSH client can adopt an existing Session if it arrives within a short grace window.

---

## 5. Data model (sketch)

This is not the final schema — that goes in `DATA_MODEL.md` when we get there. This is the topology.

**Core entities**

- `users` — id, handle (citext, unique), email, password_hash, location, tagline, join date, last_seen_at, post_count, deleted_at, preferences (jsonb)
- `ssh_keys` — id, user_id, public_key, label, created_at
- `categories` — id, name, display_order
- `boards` — id, category_id, slug, name, description, created_at, moderator_scope
- `board_subscriptions` — user_id, board_id, subscribed_at
- `board_read_pointers` — user_id, board_id, last_read_message_number
- `threads` — id, board_id, title, created_by_user_id, first_post_id, last_post_at, locked, sticky, message_count
- `thread_read_pointers` — user_id, thread_id, last_read_post_id
- `posts` — id, thread_id, board_id, message_number (per-board sequence), user_id, reply_to_post_id, body (markdown), created_at, edited_at, deleted_at
- `post_edits` — id, post_id, previous_body, edited_at, edited_by
- `upvotes` — user_id, post_id, created_at
- `direct_messages` — id, sender_id, recipient_id, body, sent_at, read_at
- `oneliners` — id, user_id, body, posted_at
- `chat_messages` — id, room_key, user_id, body, sent_at (bounded retention)
- `notifications` — id, user_id, kind, payload (jsonb), created_at, read_at
- `reports` — id, reporter_id, target_kind, target_id, reason, resolved_at, resolved_by
- `mod_actions` — id, mod_user_id, action_kind, target_kind, target_id, reason, created_at
- `user_sanctions` — id, user_id, kind (warn/mute/temp_ban/perm_ban), reason, expires_at, issued_by, created_at
- `last_callers` — id, user_id, connected_at, disconnected_at, interface (ssh/cli), visible (per user opt-in)
- `configuration` — key, value (jsonb) — sysop-editable runtime config

**Key relationships**

- A `post` belongs to a `thread`, which belongs to a `board`, which belongs to a `category`.
- `message_number` is unique within a board and assigned by the Board server.
- `thread.first_post_id` points to the root post (for first-class thread identity).
- `reply_to_post_id` is optional metadata; it does not affect ordering.
- Read pointers exist at both board and thread granularity (both were requested).

**Notable choices**

- `handle` is a `citext` column for case-insensitive uniqueness with preserved display case.
- `posts.deleted_at` is a soft-delete; the post stays in the DB so thread coherence and message numbers are preserved.
- Anonymization on account deletion is a scheduled operation that rewrites post authorship to a tombstone user and clears profile fields on `users`.
- Full-text search indexes live on `posts.body` (generated tsvector column + GIN index).

---

## 6. Ephemeral state (ETS)

Things that live in memory only:

- **Presence** — Phoenix Presence tracks online users across channels and SSH sessions. CRDT-merged across nodes.
- **Rate limiters** — token buckets keyed by user and action (post, DM, signup attempts from IP).
- **Oneliners ring buffer** — recent N oneliners for fast main-menu rendering; DB is authoritative for history.
- **Chat room backlogs** — recent messages per room, for scrollback on join.
- **Session registry** — quick lookup of the Session process for a given user.

Nothing in ETS is required for correctness — losing it on restart is acceptable. Presence re-converges as users reconnect.

---

## 7. The SSH layer

Foglet uses Erlang's built-in `:ssh` application rather than a third-party library. Notes:

- The SSH daemon's host key is persisted (typically `priv/ssh/host_key`) and must survive deploys — otherwise every user gets a host-key-changed warning.
- Authentication callbacks are implemented to check against Foglet's own user store (keys and passwords).
- Each accepted SSH connection spawns a shell handler, which initializes a Session and pumps bytes.
- Terminal size is obtained via the PTY request and updated via window-change messages (this is the SSH equivalent of telnet's NAWS).
- The TUI renderer assumes an 80×24 baseline and adapts when the terminal is larger — ANSI art regions stay 80-wide and centered; list views and message reading use the full width.

CP437-to-Unicode translation is handled at the render layer; stored ANSI art is kept as-is on disk and translated on output.

---

## 8. Configuration philosophy

Foglet is a platform. Sysops choose:

- How registration works (open with email verification / invite-only / sysop-approved)
- What the initial board and category layout looks like (defaults shipped; editable)
- Login banner, news bulletins, oneliner policy
- Available themes
- Rate-limit thresholds
- Whether telnet is enabled (future)
- Email delivery (SMTP credentials or disabled)
- Sentry DSN (optional)

Configuration layering:

1. **Compile-time defaults** in `config/config.exs` — sensible out-of-the-box values.
2. **Deploy-time config** via environment variables read in `config/runtime.exs` — credentials, toggles, host info.
3. **Runtime config** stored in the `configuration` table, editable through the sysop admin TUI without redeploy.

Secrets never go in the DB. Everything else is fair game.

---

## 9. Account creation flow

Since there's no web UI, new-user signup can't happen through a browser form. Two supported paths:

1. **SSH-based signup.** A connection without a valid key/password falls through to a "new user" guest flow where the guest can register an account (handle, email, password). Email verification link is sent; account is usable once verified. If the sysop has configured invite-only or sysop-approved mode, the flow adjusts accordingly.
2. **Sysop-provisioned accounts.** `mix foglet.user.create` for the sysop's own bootstrap account and for out-of-band provisioning.

Post-registration, users can add SSH keys from inside the TUI.

---

## 10. Sysop interface

Sysops and moderators are users with elevated roles. Admin affordances live in two places:

- **Inside the SSH TUI** — moderation actions, user management, board/category editing, banner/news editing, oneliner moderation, report queue. This is the day-to-day workspace.
- **Mix tasks on the server** — `mix foglet.user.create`, `mix foglet.user.promote`, `mix foglet.config.set`, `mix foglet.archive` (read-only mode). For install, bootstrap, and break-glass scenarios.

Phoenix LiveDashboard is exposed on the Phoenix endpoint, guarded by an admin-only plug. It's for observing the running system (process counts, ETS table sizes, request telemetry), not for operating the BBS.

---

## 11. Multi-node considerations

Foglet can run as a single node (typical deployment) or as a clustered set (Fly.io regions, redundancy). The BEAM makes this mostly free:

- Phoenix PubSub and Presence are cluster-aware.
- The Session registry uses `:global` or `Horde` for cross-node uniqueness.
- Postgres is the only hard-state dependency; one DB, many BEAM nodes.
- The SSH daemon binds per-node; users connect to whichever node accepts them.

This is not a v1 concern. Single-node is the default and must be rock-solid before clustering is exercised.

---

## 12. Testing strategy (direction)

- **Unit tests** for domain modules — boards, threads, posts, moderation logic. Ecto sandbox for isolation.
- **Process tests** for the Board server, Session, chat rooms. These are where OTP bugs hide.
- **End-to-end TUI tests** — drive a simulated SSH client through a scripted session. A small harness that speaks the SSH protocol and asserts against rendered frames.
- **Property-based tests** (StreamData) for the message-number sequence and read-pointer logic.

---

## 13. Out of scope

Called out explicitly so these don't creep in:

- Web UI for end users
- Federation (ActivityPub, FidoNet bridges, etc.)
- File upload areas
- Mobile app
- Paid features, monetization, marketplace
- Voice or video

If any of these come back on the table, they come back via a deliberate decision, not drift.