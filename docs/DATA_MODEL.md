# Foglet Data Model

Concrete Ecto schemas for Foglet's core entities. This is the contract between the domain code and the database. Migrations follow these schemas; departures happen via deliberate migration, not drift.

Scope note: this document covers the schemas needed through Milestone 9 (search, upvotes, oneliners, profile polish). Milestone-10+ additions (email digest subscriptions, Oban job tables) are called out at the end but not fleshed out.

---

## Conventions

- **Primary keys:** UUID v7 via `--binary-id`. Schema files declare `@primary_key {:id, Ecto.UUID, autogenerate: true}` and `@foreign_key_type Ecto.UUID` at the top of each module (or via a shared `Foglet.Schema` macro).
- **Timestamps:** `timestamps(type: :utc_datetime_usec)` everywhere. UTC, microsecond precision, no timezone drift.
- **Soft deletes:** a nullable `deleted_at :utc_datetime_usec` column on entities we don't hard-delete (posts, threads, users). Queries filter `where: is_nil(x.deleted_at)` by default via scope helpers.
- **Enum-like fields:** stored as Postgres enums where the set is small and stable (e.g., user role, sanction kind). Stored as strings with a `Ecto.Enum` cast where we might add values (e.g., notification kind).
- **JSON blobs:** `:map` columns backed by `jsonb`. Used sparingly — only for genuinely open-ended data (user preferences, notification payloads, configuration values).
- **`citext` extension** is enabled in the first migration. Required for case-insensitive handles.
- **Generated columns** (Postgres `GENERATED ALWAYS AS ... STORED`) are used for the full-text search `tsvector` on posts.

A shared schema module cuts boilerplate:

```elixir
defmodule Foglet.Schema do
  defmacro __using__(_) do
    quote do
      use Ecto.Schema
      import Ecto.Changeset
      @primary_key {:id, Ecto.UUID, autogenerate: true}
      @foreign_key_type Ecto.UUID
      @timestamps_opts [type: :utc_datetime_usec]
    end
  end
end
```

Every schema below assumes `use Foglet.Schema` at the top.

---

## 1. Accounts

### `Foglet.Accounts.User`

Table: `users`

```elixir
schema "users" do
  field :handle, :string          # citext in DB; display case preserved
  field :email, :string           # citext in DB
  field :password_hash, :string
  field :confirmed_at, :utc_datetime_usec

  field :role, Ecto.Enum, values: [:user, :mod, :sysop], default: :user

  # Classic profile fields
  field :location, :string
  field :tagline, :string
  field :real_name, :string       # optional, kept private

  # Denormalized counters
  field :post_count, :integer, default: 0
  field :last_seen_at, :utc_datetime_usec

  # Preferences
  field :theme, :string, default: "default"
  field :handle_color, :string, default: "#FFFFFF"
  field :show_in_last_callers, :boolean, default: true
  field :email_digest, Ecto.Enum, values: [:off, :daily, :weekly], default: :off
  field :timezone, :string, default: "Etc/UTC"
  field :preferences, :map, default: %{}

  # Lifecycle
  field :status, Ecto.Enum, values: [:active, :pending, :rejected, :suspended], default: :active
  field :deleted_at, :utc_datetime_usec

  has_many :ssh_keys, Foglet.Accounts.SSHKey
  has_many :posts, Foglet.Posts.Post
  has_many :board_subscriptions, Foglet.Boards.Subscription
  has_many :sent_messages, Foglet.DMs.Message, foreign_key: :sender_id
  has_many :received_messages, Foglet.DMs.Message, foreign_key: :recipient_id
  has_many :sanctions, Foglet.Moderation.Sanction

  timestamps()
end
```

**Migration notes:**

- `handle` and `email` are `citext` columns, both `NOT NULL`, both unique.
- A unique index on `handle` and another on `email` — case-insensitive by virtue of `citext`.
- `role` as a Postgres enum: `CREATE TYPE user_role AS ENUM ('user', 'mod', 'sysop');`
- `status` is a string-backed `Ecto.Enum`, not a Postgres enum, with lifecycle values `:active`, `:pending`, `:rejected`, and `:suspended`.
- Partial index on `last_seen_at` for "who's been around recently" queries: `WHERE deleted_at IS NULL`.
- A tombstone user row is inserted in seeds — id fixed, handle like `[deleted]`. Post anonymization rewrites `user_id` to this row.
- `handle_color` is a typed account preference column. New rows default to `#FFFFFF`; the feature migration backfills null existing rows to `#FFFFFF` and leaves already-valid custom values untouched on rerun. The column may be `NULL` only when a user intentionally clears the preference so renderers can fall back to normal theme/default handle styling. Non-null values must match `#RRGGBB` case-insensitively.
- Rejected users remain non-deleted rows. A rejected registration reserves its handle and email and is distinct from soft deletion.

**Changesets:**

- `registration_changeset/2` — handle, email, password. Validates handle format (length, allowed characters — alphanumeric + `_`/`-`, classic BBS feel), hashes password with Argon2.
- `profile_changeset/2` — location, tagline, real_name, theme, handle_color, preferences. Never touches handle or email.
- `password_changeset/2` — separate, requires current password re-entry.
- `role_changeset/2` — sysop-only pathway.

**Anonymization flow** (on account deletion):

1. Rewrite `user_id` on all `posts`, `direct_messages` authored by the user to the tombstone user.
2. Delete `ssh_keys`, `board_subscriptions`, `board_read_pointers`, `thread_read_pointers`, `notifications`, `oneliners`, `upvotes`, unread DMs to the user; detach/anonymize `last_callers.user_id` and clear public caller visibility while retaining audit rows until retention cleanup.
3. Zero the user row: clear profile fields, set `deleted_at`, randomize email to prevent re-registration conflicts.
4. Keep the row (rather than hard-deleting) so foreign key references remain valid.

### `Foglet.Accounts.SSHKey`

Table: `ssh_keys`

```elixir
schema "ssh_keys" do
  field :label, :string           # user-chosen nickname for the key
  field :public_key, :string      # OpenSSH authorized_keys format
  field :fingerprint, :string     # SHA256, computed server-side
  field :last_used_at, :utc_datetime_usec

  belongs_to :user, Foglet.Accounts.User

  timestamps()
end
```

**Migration notes:**

- Unique index on `fingerprint` — a given public key registers exactly once across the whole instance.
- Unique index on `(user_id, label)` — a user's keys have distinct labels.
- `public_key` stored as text; fingerprint computed from it at insert time and validated to match on update.

### `Foglet.Accounts.UserToken`

Table: `user_tokens` — generated by `phx.gen.auth`, kept roughly as-is.

Used for email confirmation, password reset, and CLI-client session tokens. Standard Phoenix auth shape:

```elixir
schema "user_tokens" do
  field :token, :binary
  field :context, :string         # "confirm", "reset_password", "cli_session"
  field :sent_to, :string         # email for confirm/reset

  belongs_to :user, Foglet.Accounts.User

  timestamps(updated_at: false)
end
```

Unique index on `(context, token)`. Cleanup job purges expired tokens.

---

## 2. Boards and Categories

### `Foglet.Boards.Category`

Table: `categories`

```elixir
schema "categories" do
  field :name, :string
  field :description, :string
  field :display_order, :integer, default: 0
  field :archived, :boolean, default: false

  has_many :boards, Foglet.Boards.Board

  timestamps()
end
```

Categories are presentation-only — they group boards on the main menu. Small table, rarely changes, sysop-editable.

### `Foglet.Boards.Board`

Table: `boards`

```elixir
schema "boards" do
  field :slug, :string            # url/command-friendly, unique
  field :name, :string            # display name
  field :description, :string
  field :display_order, :integer, default: 0

  # Message number allocation — mirrors what Foglet.Boards.Server holds in memory
  field :next_message_number, :integer, default: 1

  # Policy
  field :readable_by, Ecto.Enum, values: [:public, :members], default: :public
  field :postable_by, Ecto.Enum, values: [:members, :mods_only, :sysop_only], default: :members
  field :archived, :boolean, default: false
  field :default_subscription, :boolean, default: false
  field :required_subscription, :boolean, default: false

  belongs_to :category, Foglet.Boards.Category

  has_many :threads, Foglet.Threads.Thread
  has_many :posts, Foglet.Posts.Post
  has_many :subscriptions, Foglet.Boards.Subscription

  timestamps()
end
```

**Migration notes:**

- Unique index on `slug`.
- Index on `(category_id, display_order)` for menu rendering.
- `required_subscription` has a check constraint named `boards_required_subscription_requires_default_subscription`; it may be true only when `default_subscription` is true.
- `next_message_number` is the persisted source of truth. The `Foglet.Boards.Server` loads it at startup, allocates in memory, and writes through on every post insert inside the same transaction.

**Why persist `next_message_number` on the board row instead of deriving it?**

- Soft-deleted posts still occupy a number; `MAX(message_number) + 1` would be wrong after deletion.
- A dedicated counter avoids a table scan on every post and is trivially transactional.
- The Board server is single-writer per board, so there's no contention on this column.

### `Foglet.Boards.Subscription`

Table: `board_subscriptions`

```elixir
schema "board_subscriptions" do
  belongs_to :user, Foglet.Accounts.User
  belongs_to :board, Foglet.Boards.Board
  field :subscribed_at, :utc_datetime_usec

  timestamps(updated_at: false)
end
```

Unique index on `(user_id, board_id)`. Presence of row = subscribed.

### `Foglet.Boards.ReadPointer`

Table: `board_read_pointers`

```elixir
schema "board_read_pointers" do
  belongs_to :user, Foglet.Accounts.User
  belongs_to :board, Foglet.Boards.Board
  field :last_read_message_number, :integer, default: 0
  field :last_read_at, :utc_datetime_usec

  timestamps(updated_at: false)
end
```

Unique index on `(user_id, board_id)`. Updated with upserts — `INSERT ... ON CONFLICT (user_id, board_id) DO UPDATE`.

---

## 3. Threads and Posts

### `Foglet.Threads.Thread`

Table: `threads`

First-class threads with titles (per decision 4.3).

```elixir
schema "threads" do
  field :title, :string
  field :locked, :boolean, default: false
  field :sticky, :boolean, default: false
  field :deleted_at, :utc_datetime_usec

  # Denormalized for cheap list rendering
  field :post_count, :integer, default: 1
  field :last_post_at, :utc_datetime_usec

  belongs_to :board, Foglet.Boards.Board
  belongs_to :created_by, Foglet.Accounts.User
  belongs_to :first_post, Foglet.Posts.Post

  has_many :posts, Foglet.Posts.Post

  timestamps()
end
```

**Migration notes:**

- Composite index on `(board_id, sticky DESC, last_post_at DESC)` for thread-list rendering with stickies on top.
- Partial index for active threads: `WHERE deleted_at IS NULL`.
- `first_post_id` is a circular FK with `posts`; use `references(..., on_delete: :nilify_all)` and create the thread then the post then update the thread in a transaction. Or insert the post without a thread first and set `thread_id` after — pick one convention and stick to it. (Recommendation: create thread with `first_post_id = NULL`, create post, update thread, all in one `Ecto.Multi`.)

### `Foglet.Posts.Post`

Table: `posts`

```elixir
schema "posts" do
  field :message_number, :integer     # per-board sequence
  field :body, :string                # markdown source
  field :body_rendered, :string       # cached terminal-safe render (optional; can be derived)
  field :deleted_at, :utc_datetime_usec
  field :deletion_reason, :string     # set by mod action; null for self-delete

  # Denormalized counters
  field :upvote_count, :integer, default: 0
  field :edit_count, :integer, default: 0
  field :last_edited_at, :utc_datetime_usec

  belongs_to :thread, Foglet.Threads.Thread
  belongs_to :board, Foglet.Boards.Board
  belongs_to :user, Foglet.Accounts.User
  belongs_to :reply_to, Foglet.Posts.Post

  has_many :edits, Foglet.Posts.Edit
  has_many :upvotes, Foglet.Posts.Upvote

  timestamps()
end
```

**Migration notes:**

- Unique index on `(board_id, message_number)` — the core invariant.
- Index on `(thread_id, inserted_at)` for linear thread rendering.
- Index on `(user_id, inserted_at DESC) WHERE deleted_at IS NULL` for user profile activity.
- Full-text search: a generated `body_tsv tsvector GENERATED ALWAYS AS (to_tsvector('english', body)) STORED` column with a GIN index.
- `board_id` is denormalized from `thread.board_id` for fast per-board queries. Maintained by always inserting both together; a check constraint or a trigger enforces consistency.

**Insertion flow** (inside `Foglet.Boards.Server`):

```
Ecto.Multi.new()
|> Multi.run(:allocate_number, fn repo, _ ->
    # Atomic increment on boards.next_message_number
  end)
|> Multi.insert(:post, fn %{allocate_number: n} -> Post.changeset(..., message_number: n) end)
|> Multi.update(:thread, bump_counters)
|> Multi.update(:user, increment_post_count)
|> Repo.transaction()
```

The Board server serializes this — only one allocation at a time per board — so the DB-level uniqueness constraint is a safety net, not the primary enforcement.

### `Foglet.Posts.Edit`

Table: `post_edits`

```elixir
schema "post_edits" do
  field :previous_body, :string
  field :reason, :string            # optional edit note
  field :edited_at, :utc_datetime_usec

  belongs_to :post, Foglet.Posts.Post
  belongs_to :edited_by, Foglet.Accounts.User

  timestamps(updated_at: false)
end
```

Unbounded history per post. Insert-only; never mutated. `previous_body` is the body *before* this edit — so the sequence of (edit_1, edit_2, edit_3, current post body) reconstructs the full timeline.

Index on `(post_id, edited_at DESC)`.

### `Foglet.Posts.Upvote`

Table: `upvotes`

```elixir
schema "upvotes" do
  belongs_to :user, Foglet.Accounts.User
  belongs_to :post, Foglet.Posts.Post

  timestamps(updated_at: false)
end
```

Unique index on `(user_id, post_id)`. Toggling is insert/delete. The `posts.upvote_count` denormalization is maintained by the upvote-insert/delete code paths, not by triggers — keeps control in the application.

---

## 4. Thread read pointers

### `Foglet.Threads.ReadPointer`

Table: `thread_read_pointers`

```elixir
schema "thread_read_pointers" do
  belongs_to :user, Foglet.Accounts.User
  belongs_to :thread, Foglet.Threads.Thread
  belongs_to :last_read_post, Foglet.Posts.Post
  field :last_read_at, :utc_datetime_usec

  timestamps(updated_at: false)
end
```

Unique index on `(user_id, thread_id)`. Upsert on write.

Both board and thread pointers exist (per decision 4.5). The board pointer is the primary "is there anything new in this board" signal; the thread pointer lets us compute *which* post to drop you at when you open a thread you've partially read.

---

## 5. Direct Messages

### `Foglet.DMs.Message`

Table: `direct_messages`

```elixir
schema "direct_messages" do
  field :body, :string
  field :read_at, :utc_datetime_usec
  field :deleted_by_sender_at, :utc_datetime_usec
  field :deleted_by_recipient_at, :utc_datetime_usec

  belongs_to :sender, Foglet.Accounts.User
  belongs_to :recipient, Foglet.Accounts.User

  timestamps()
end
```

**Migration notes:**

- Indexes on `(recipient_id, inserted_at DESC)` for inbox rendering and `(sender_id, inserted_at DESC)` for sent-items.
- Partial index on unread: `(recipient_id) WHERE read_at IS NULL AND deleted_by_recipient_at IS NULL`.
- Dual soft-delete — each side can remove a DM from their own view without affecting the other party. Hard delete only when both sides have removed it (a background job can sweep these if desired, or just let them accumulate).
- Full-text search on `body` if DM search is ever added (currently out of scope per 9.2).

---

## 6. Chat

### `Foglet.Chat.Message`

Table: `chat_messages`

```elixir
schema "chat_messages" do
  field :room_key, :string          # "lobby" | "board:<slug>"
  field :body, :string
  field :kind, Ecto.Enum, values: [:message, :system, :action], default: :message

  belongs_to :user, Foglet.Accounts.User

  timestamps(updated_at: false)
end
```

**Migration notes:**

- Index on `(room_key, inserted_at DESC)` — the only query pattern is "recent messages in room."
- Bounded retention: a scheduled Oban job deletes messages older than N days (sysop-configurable, default 30). Chat is ephemeral-ish; this is not a forum.
- `kind: :system` for join/leave announcements, mod actions visible in-room, etc. `:action` for `/me`-style messages.

Chat room state in memory (the active GenServer) is authoritative for "who's here right now." The database is just scrollback.

---

## 7. Oneliners

### `Foglet.Oneliners.Entry`

Table: `oneliners`

```elixir
schema "oneliners" do
  field :body, :string              # length-limited at changeset level (e.g., 120 chars)
  field :hidden, :boolean, default: false
  field :hidden_reason, :string

  belongs_to :user, Foglet.Accounts.User
  belongs_to :hidden_by, Foglet.Accounts.User

  timestamps(updated_at: false)
end
```

**Migration notes:**

- Index on `(inserted_at DESC) WHERE hidden = false` — main-menu rendering reads the top N.
- The `Foglet.Oneliners` GenServer holds a ring buffer of the recent visible entries for zero-DB-hit main menu rendering. Writes go DB-first, then update the ring buffer via PubSub.
- Mods can hide oneliners (soft-hide, not delete) — the audit trail matters.

---

## 8. Notifications

### `Foglet.Notifications.Notification`

Table: `notifications`

```elixir
schema "notifications" do
  field :kind, Ecto.Enum,
    values: [:mention, :reply, :dm, :mod_action, :thread_update],
    default: :mention

  field :payload, :map              # kind-specific structured data
  field :read_at, :utc_datetime_usec

  belongs_to :user, Foglet.Accounts.User           # recipient
  belongs_to :actor, Foglet.Accounts.User          # who caused it (nullable for system events)

  timestamps(updated_at: false)
end
```

**Payload shapes** (documented in module, enforced in changesets):

- `:mention` — `%{post_id: "...", thread_id: "...", board_id: "...", snippet: "..."}`
- `:reply` — same shape; distinguished only by kind
- `:dm` — `%{message_id: "...", preview: "..."}`
- `:mod_action` — `%{action_id: "...", action_kind: "warn" | ..., reason: "..."}`
- `:thread_update` — same post-target shape; emitted to the thread creator for a new post when no more-specific `:reply` or `:mention` notification already owns the same post/recipient dedupe key

**Migration notes:**

- Partial index on `(user_id, inserted_at DESC) WHERE read_at IS NULL` — unread count is a hot query.
- Index on `(user_id, inserted_at DESC)` for the full inbox view.
- Retention: a cleanup job deletes read notifications older than N days.

---

## 9. Moderation

### `Foglet.Moderation.BoardModerator`

Table: `board_moderators`

```elixir
schema "board_moderators" do
  belongs_to :user, Foglet.Accounts.User
  belongs_to :board, Foglet.Boards.Board
  belongs_to :assigned_by, Foglet.Accounts.User

  timestamps(updated_at: false)
end
```

Unique index on `(user_id, board_id)`. Existence of a row grants mod powers on that board. Global mods get a different mechanism (currently only sysops have global reach; expand later if needed).

### `Foglet.Moderation.Report`

Table: `reports`

```elixir
schema "reports" do
  field :target_kind, Ecto.Enum, values: [:post, :user, :dm, :chat_message, :oneliner]
  field :target_id, Ecto.UUID     # polymorphic reference; application-enforced
  field :reason, :string
  field :notes, :string

  field :status, Ecto.Enum,
    values: [:open, :resolved, :dismissed],
    default: :open
  field :resolved_at, :utc_datetime_usec
  field :resolution_note, :string

  belongs_to :reporter, Foglet.Accounts.User
  belongs_to :resolved_by, Foglet.Accounts.User

  timestamps()
end
```

**Migration notes:**

- Index on `status WHERE status = 'open'` — the mod queue only cares about open reports.
- `target_id` is deliberately not a foreign key because the target type varies. Application code validates existence when creating a report.
- A second index on `(reporter_id, inserted_at DESC)` for rate-limiting abusive reporters.

### `Foglet.Moderation.Action`

Table: `mod_actions`

```elixir
schema "mod_actions" do
  field :kind, Ecto.Enum, values: [
    :warn, :mute, :temp_ban, :perm_ban, :unban,
    :delete_post, :undelete_post,
    :lock_thread, :unlock_thread,
    :sticky_thread, :unsticky_thread,
    :move_thread,
    :hide_oneliner
  ]

  field :target_kind, Ecto.Enum, values: [:user, :post, :thread, :oneliner]
  field :target_id, Ecto.UUID
  field :reason, :string
  field :metadata, :map, default: %{}    # kind-specific extras

  belongs_to :mod, Foglet.Accounts.User
  belongs_to :related_report, Foglet.Moderation.Report

  timestamps(updated_at: false)
end
```

Append-only log. No updates, no deletes — ever. Visible to all mods (per decision 7.4).

**Metadata examples:**

- `:temp_ban` — `%{expires_at: "...", duration: "7d"}`
- `:move_thread` — `%{from_board_id: "...", to_board_id: "..."}`
- `:delete_post` — `%{board_id: "...", message_number: 4471}`

Index on `(inserted_at DESC)` for the audit log view and `(mod_id, inserted_at DESC)` for per-mod activity.

### `Foglet.Moderation.Sanction`

Table: `user_sanctions`

Active sanctions against users. A user can have multiple active sanctions of different kinds (e.g., a warn *and* a mute), but typically one at a time.

```elixir
schema "user_sanctions" do
  field :kind, Ecto.Enum, values: [:warn, :mute, :temp_ban, :perm_ban]
  field :reason, :string
  field :expires_at, :utc_datetime_usec   # null = indefinite
  field :lifted_at, :utc_datetime_usec    # null = still active
  field :lifted_reason, :string

  belongs_to :user, Foglet.Accounts.User
  belongs_to :issued_by, Foglet.Accounts.User
  belongs_to :lifted_by, Foglet.Accounts.User
  belongs_to :related_action, Foglet.Moderation.Action

  timestamps()
end
```

**Migration notes:**

- Partial index on active sanctions: `(user_id) WHERE lifted_at IS NULL AND (expires_at IS NULL OR expires_at > now())`.
- A background job periodically marks expired sanctions as lifted (sets `lifted_at = expires_at`, `lifted_reason = "expired"`), so the "active" query stays simple.
- Authorization middleware consults active sanctions on every post/DM/chat attempt.

---

## 10. Last callers and SSH access rules

### `Foglet.SSH.LastCaller`

Table: `last_callers`
```elixir
schema "last_callers" do
  field :interface, Ecto.Enum, values: [:ssh, :cli, :telnet]
  field :peer_ip, :string              # raw IPv4/IPv6, operator-only, retention-bounded
  field :peer_port, :integer
  field :outcome, Ecto.Enum, values: [
    :accepted, :denied, :rate_limited, :over_global_limit, :auth_gate_denied, :failed
  ]
  field :reason, :string               # terse operator-safe reason, no exception payloads
  field :policy_key, :string
  field :session_id, :string
  field :public_visible, :boolean, default: false
  field :occurred_at, :utc_datetime_usec
  field :disconnected_at, :utc_datetime_usec
  field :metadata, :map, default: %{}

  belongs_to :user, Foglet.Accounts.User

  timestamps(updated_at: false)
end
```

**Migration notes:**

- Index on `(occurred_at DESC) WHERE public_visible = true AND outcome = 'accepted'` — the login-sequence "last callers" list hits this.
- `public_visible` is captured from `users.show_in_last_callers` for accepted user calls. It controls classic public caller-history display only; operator/security audit rows remain durable until retention cleanup.
- Raw `peer_ip`/`peer_port` are retained for a code-defined default 90 days and then redacted by the owning context cleanup API. Rows may remain for aggregate/history purposes after raw IP redaction.
- Account deletion/anonymization detaches `user_id` and clears public visibility for this user's caller rows rather than deleting the operator/security audit record immediately.
- Never store raw passwords, public-key material, invite/reset/verification tokens, post/chat content, or raw exception payloads in `last_callers` fields or metadata.

### `Foglet.SSH.AccessRule`

Table: `ssh_access_rules`
```elixir
schema "ssh_access_rules" do
  field :mode, Ecto.Enum, values: [:allow, :deny]
  field :address, :string             # exact IPv4/IPv6 or CIDR
  field :enabled, :boolean, default: true
  field :reason, :string
  field :comment, :string

  belongs_to :created_by, Foglet.Accounts.User

  timestamps()
end
```

Rules are operator-managed allow/deny entries. Deny rules win over allow rules. When allowlist mode is enabled by the SSH hot path, a source must match an enabled `:allow` rule and must not match an enabled `:deny` rule; allowlisted sources still do not bypass per-IP throttles or global active-connection caps.

### `Foglet.Accounts.IdentityRule`

Table: `identity_policy_rules`
```elixir
schema "identity_policy_rules" do
  field :kind, Ecto.Enum, values: [:reserved_handle, :banned_handle, :banned_email, :banned_email_domain]
  field :value, :string             # operator-entered value, trimmed for display
  field :normalized_value, :string  # canonical comparison key
  field :enabled, :boolean, default: true
  field :reason, :string
  field :comment, :string

  belongs_to :created_by, Foglet.Accounts.User
  belongs_to :updated_by, Foglet.Accounts.User

  timestamps()
end
```

Identity rules are the account-identity counterpart to SSH IP access rules and are surfaced to operators in the same ACCESS policy neighborhood. They are enforced by `Foglet.Accounts.IdentityPolicy` at registration/account identity mutation boundaries; anonymous denial copy is intentionally terse and does not expose policy contents.

Normalization and matching contract:

- `reserved_handle` and `banned_handle` trim input and compare with Foglet's handle format/case rules (`[A-Za-z0-9_-]`, length/format validation remains on `Foglet.Accounts.User`). Case variants compare equal via lowercase `normalized_value`.
- `banned_email` trims input and compares exact normalized email address case-insensitively.
- `banned_email_domain` trims an optional leading `@`, lowercases the domain, and blocks both the exact domain and subdomains. `example.com` blocks `user@example.com` and `user@mail.example.com`; it does not block `user@badexample.com` because matching is exact or dot-boundary suffix only.
- Creating a rule reports matching existing non-deleted users for sysop review but does not mutate, suspend, lock, rename, or delete those users.

**Migration notes:**

- Check constraint on `kind` for the four supported rule types.
- Unique index on `(kind, normalized_value)` prevents duplicate active/inactive rows with the same canonical rule identity.
- Index on `(enabled, kind)` supports registration enforcement without exposing full lists to anonymous callers.

---

## 11. Site counters

### `Foglet.SiteCounters.Counter`

Table: `site_counters`

```elixir
schema "site_counters" do
  field :name, :string       # e.g. "bbs_calls"
  field :value, :integer, default: 0

  timestamps()
end
```

Durable, low-cardinality site-wide counters whose values must survive VM restarts and deploys.
The initial counter row may be absent; `Foglet.SiteCounters.get_call_count/0` treats that as `0`, and `increment_call_count/0` bootstraps the row with an atomic Postgres upsert.

**Migration notes:**

- Unique index on `name`.
- Check constraint `value >= 0`.
- `Foglet.SiteCounters` is the public domain boundary; callers do not write this table directly.
- The BBS call counter key is `bbs_calls`. It is distinct from `Foglet.SSH.CLIHandler.Counter`, which remains VM-local active-connection state only.
- Rollback is reversible by dropping `site_counters`; doing so intentionally discards accumulated counter values and operational recovery is restoring the table from backup before rollback.

---

## 12. Configuration

### `Foglet.Config.Entry`

Table: `configuration`

Runtime-editable sysop configuration. Never stores secrets.

```elixir
schema "configuration" do
  field :key, :string               # e.g., "registration_mode", "rate_limits_posts_per_day"
  field :value, :map                # jsonb; wrapped to allow any JSON type
  field :description, :string

  belongs_to :updated_by, Foglet.Accounts.User

  timestamps()
end
```

Unique index on `key`. Values are always wrapped as maps (`%{"v" => 42}`) to avoid jsonb's quirks with bare scalars.

**Keys we expect** (documented in a `Foglet.Config` module with typed accessors):

Keys use `snake_case` separators. This is the canonical form.

Seeded by `priv/repo/seeds.exs`:

- `registration_mode` — `"open" | "invite_only" | "sysop_approved"`
- `invite_code_generators` — `"sysop_only" | "mods" | "any_user"`
- `max_post_length` — integer (characters)
- `max_thread_title_length` — integer (characters)
- `require_email_verification` — boolean
- `guest_mode_enabled` — boolean; defaults enabled and gates intentional read-only Guest Mode
- `email_verify_resend_cooldown_seconds` — integer

> Programmatic access: `Foglet.Config.Schema` declares the seeded keys with their types, defaults, and constraints. `Foglet.Config` exposes typed accessors (e.g., `registration_mode/0`, `max_post_length/0`, `require_email_verification?/0`, `guest_mode_enabled?/0`).

Aspirational (not yet seeded):

- `rate_limits_posts_per_day_new_user` — integer
- `rate_limits_new_user_period_days` — integer
- `login_banner_body` — string (CP437 or UTF-8)
- `news_bulletins` — array of `%{title, body, posted_at}`
- `themes_available` — array of theme names
- `chat_retention_days` — integer
- `last_callers_retention_days` — integer
- `oneliners_max_length` — integer
- `archive_enabled` — boolean (read-only mode)

Sysop TUI edits hit this table; application code reads via a cached accessor (`Foglet.Config.get!/1`) backed by an ETS table invalidated on write.

---

## 13. Entity relationship diagram

```
                          categories
                              │
                              │ 1:N
                              ▼
                           boards ──────────────┐
                          /  │  \                │
                      1:N/ 1:N  \1:N              │ 1:N
                        /    │    \                ▼
            subscriptions    │   moderators     threads ─────┐
                   │        │                      │  \      │
                   │        │ 1:N                  │   \1:N  │1:1
                   ▼        ▼                      │    \    │
                 users ──▶ read_pointers           │     ▼   ▼
                 │ │ \      (board)                │  posts ─┘
                 │ │  \                            │  /│
                 │ │   \─▶ read_pointers           │ / │1:N
                 │ │       (thread) ───────────────┘/  │
                 │ │                                   ▼
                 │ │                                post_edits
                 │ │                                upvotes
                 │ │
                 │ └─▶ ssh_keys
                 │     user_tokens
                 │     sanctions
                 │     last_callers
                 │
                 ├─▶ direct_messages (sender/recipient)
                 ├─▶ chat_messages
                 ├─▶ oneliners
                 ├─▶ notifications (user/actor)
                 ├─▶ reports (reporter/resolver)
                 └─▶ mod_actions (mod)
```

---

## 14. Indexes summary

Critical indexes to create explicitly (beyond those implied by unique constraints and foreign keys):

| Table | Index | Purpose |
|---|---|---|
| `users` | unique `handle` (citext) | handle uniqueness |
| `users` | unique `email` (citext) | email uniqueness |
| `users` | `last_seen_at DESC WHERE deleted_at IS NULL` | recent-activity queries |
| `ssh_keys` | unique `fingerprint` | key dedup across instance |
| `boards` | `(category_id, display_order)` | menu rendering |
| `boards` | unique `slug` | slug lookups |
| `threads` | `(board_id, sticky DESC, last_post_at DESC) WHERE deleted_at IS NULL` | thread list |
| `posts` | unique `(board_id, message_number)` | core BBS invariant |
| `posts` | `(thread_id, inserted_at)` | thread reading |
| `posts` | `(user_id, inserted_at DESC) WHERE deleted_at IS NULL` | profile activity |
| `posts` | GIN on `body_tsv` | full-text search |
| `post_edits` | `(post_id, edited_at DESC)` | edit history |
| `upvotes` | unique `(user_id, post_id)` | prevent double-upvotes |
| `board_subscriptions` | unique `(user_id, board_id)` | subscription state |
| `board_read_pointers` | unique `(user_id, board_id)` | upsert target |
| `thread_read_pointers` | unique `(user_id, thread_id)` | upsert target |
| `direct_messages` | `(recipient_id, inserted_at DESC)` | inbox |
| `direct_messages` | `(recipient_id) WHERE read_at IS NULL AND deleted_by_recipient_at IS NULL` | unread count |
| `chat_messages` | `(room_key, inserted_at DESC)` | scrollback |
| `oneliners` | `(inserted_at DESC) WHERE hidden = false` | main menu |
| `notifications` | `(user_id, inserted_at DESC) WHERE read_at IS NULL` | unread count |
| `notifications` | `(user_id, inserted_at DESC)` | full inbox |
| `reports` | `(inserted_at) WHERE status = 'open'` | mod queue |
| `mod_actions` | `(inserted_at DESC)` | audit log |
| `user_sanctions` | `(user_id) WHERE lifted_at IS NULL AND (expires_at IS NULL OR expires_at > now())` | active sanction check |
| `last_callers` | `(occurred_at DESC) WHERE public_visible = true AND outcome = 'accepted'` | login sequence |
| `last_callers` | `(user_id, occurred_at DESC)` | operator user/IP audit |
| `last_callers` | `(outcome, occurred_at DESC)` | operator security audit |
| `ssh_access_rules` | `(enabled, mode)` | SSH policy evaluation |
| `site_counters` | unique `name` | atomic upsert target for durable site counters |
| `configuration` | unique `key` | config lookup |

---

## 15. Consistency and invariants

A few invariants the application enforces that aren't captured by FK or uniqueness alone:

1. **Message number monotonicity per board** — enforced by the `Foglet.Boards.Server` serializing allocations. DB-level uniqueness is the backstop.
2. **`posts.board_id == posts.thread.board_id`** — denormalization must stay consistent. Enforced by insertion code; a check constraint is possible but awkward without a trigger.
3. **Thread's `first_post_id` points to a post with `reply_to_id = NULL` in that thread** — the root post has no parent.
4. **A thread's `post_count` and `last_post_at`** — maintained by the same `Ecto.Multi` that inserts/deletes posts. Never derived on read.
5. **`users.post_count`** — incremented on post insert, decremented on hard delete (never on soft delete, because soft-deleted posts still count for the user's history in most views; revisit if this feels wrong).
6. **A user cannot have two active sanctions of the same kind** — application-enforced in the sanction issue code path. No DB constraint; the sanction table is audit-heavy and we allow overlaps in principle.
7. **Chat retention** — a periodic job, not a DB-level TTL. Postgres has no native TTL; Oban handles it.

---

## 16. Deferred (beyond Milestone 9)

The following are acknowledged but not specified here:

- **Email digest subscriptions and send log** (Milestone 10) — likely a `digest_subscriptions` table and an append-only `digest_sends` log for idempotency.
- **Oban tables** — `oban_jobs`, `oban_peers` etc., created by the Oban migration. Not part of the domain model.
- **Data export artifacts** (Milestone 11) — probably synthesized on demand, not stored. Revisit if exports are large enough to warrant background generation and download links.
- **Door game state** (Milestone 14) — per-game schemas, designed when the first game is chosen.
- **CLI session tokens** — covered by `user_tokens.context = "cli_session"`; no new table needed.

---

## 17. Open questions

Flagging for later decision, not blocking on today:

- **Should `posts.body_rendered` be persisted?** Caching the terminal-ready rendering avoids redoing markdown-to-ANSI on every read, but invalidation on theme changes is messy. Leaning toward *not* persisting — render on read, cache in ETS per-session.
- **Retention window for `post_edits`.** Unbounded is simple; if storage ever matters, we can age out old revisions. Probably fine forever at hobby scale.
- **Polymorphic `target_id` in `reports` and `mod_actions`.** Works fine without a database-level constraint, but foreign key integrity is lost. Acceptable tradeoff for v1; revisit if it causes pain.
- **Full-text search language.** Hardcoded `'english'` in the generated tsvector column. If the sysop wants a different language, this becomes a migration. Probably fine to defer until someone asks.
