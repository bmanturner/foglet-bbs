%{
  title: "Data model",
  weight: 20
}
---

Foglet stores BBS state in Postgres through Ecto schemas. This page explains the
records operators will see reflected in the product: accounts, boards, threads,
posts, subscriptions, read pointers, invites, configuration, and supporting
activity records.

It is not a migration reference. When this page and the database disagree, the
running migrations and schemas win.

## Database conventions

Foglet uses UUID primary keys and UTC microsecond timestamps. Most schemas use a
shared `Foglet.Schema` helper so foreign keys and timestamps are consistent.

Several records are soft-deleted instead of removed. A soft delete keeps the row
for history and foreign-key integrity, then hides it from normal reading paths.
For example, deleted posts keep their board message numbers.

Case-insensitive account identifiers use `citext` in the database. Handles and
email addresses are unique without forcing callers to remember exact casing.

## Accounts

`users` stores caller accounts.

Important fields include:

- `handle`, the public BBS name.
- `email`, used for account flows when email is configured.
- `password_hash`, never the plain password.
- `role`: `user`, `mod`, or `sysop`.
- `status`: `active`, `pending`, `rejected`, or `suspended`.
- Profile fields such as `location`, `tagline`, and private `real_name`.
- Preferences such as timezone, theme, handle color, last-caller visibility,
  email digest setting, and a small preferences map.
- `deleted_at`, which marks an account as deleted without breaking old posts.

Registration mode changes the starting status. Open and invite-only registration
create active users. Sysop-approved registration creates pending users until a
sysop approves or rejects them.

Account deletion clears private fields, invalidates the password hash, hides the
user from last callers, and rewrites the email to a deleted local value. Post
history is preserved through a tombstone user path where implemented.

## SSH keys and tokens

Account support tables store:

- SSH public keys attached to users.
- User tokens for verification and password reset flows.
- Invite records and redemption metadata.

Invite codes are not stored as reusable plain secrets. The account code hashes
invite tokens and returns the raw token only to the caller when it is generated.
Operators should treat invite links and codes as credentials.

## Categories and boards

`categories` are top-level groupings. They have a name, optional description,
display order, and archived flag.

`boards` are discussion areas inside categories. They carry:

- `slug`, `name`, `description`, and `display_order`.
- `readable_by`: `public` or `members`.
- `postable_by`: `members`, `mods_only`, or `sysop_only`.
- `archived`, which removes the board from normal active-board flows.
- `default_subscription`, used when new accounts are subscribed to default
  boards after registration.
- `required_subscription`, which requires `default_subscription` and prevents
  normal unsubscribe.
- `next_message_number`, the persisted counter used alongside the board server.
- Board chat settings: enabled flag, storage mode, and ephemeral retention.

A required subscription must also be a default subscription. That rule is
checked in the board changeset and database constraint.

## Threads and posts

`threads` are titled discussions on a board. A thread stores its board,
creator, first post, `locked` and `sticky` flags, counters, last-post time, and
optional `deleted_at`.

`posts` are the actual messages. A post stores:

- `message_number`, stable within its board.
- `body` and optional rendered body.
- `thread_id`, `board_id`, and `user_id`.
- Optional `reply_to_id` for reply context.
- Soft deletion fields.
- Upvote and edit counters.
- Edit timing.

Thread creation creates a thread and its root post together through the board
server. Reply creation also routes through the board server. The board server is
the single allocator for per-board message numbers.

Message numbers are historical. Moving a thread can update denormalized board
references on posts, but existing message numbers are not renumbered. Deleted
posts keep their numbers. Foglet does not close gaps.

## Edits, upvotes, and search support

Post edits are tracked separately from the post row. The post row keeps the
current body plus edit counters and timestamps.

Upvotes are stored per user and post, with a counter denormalized onto the post
for fast display. The user-facing behavior is intentionally small: upvotes are a
lightweight signal, not a reputation system.

Post full-text search uses a generated Postgres column for the search vector.
That generated column is intentionally not written through the Ecto `Post`
schema; Postgres owns it.

## Subscriptions and read pointers

Board subscriptions connect users to boards. They drive subscribed-board views
and unread expectations.

Board read pointers track the last-read board message number per user and
board. Thread read pointers track the last-read post per user and thread.

Read pointers are monotonic user state. Normal UI-local scroll position is not
the same thing as persisted read state.

## Configuration

Database-backed configuration lives in a `configuration` table and is read
through `Foglet.Config`. The runtime cache is ETS-backed. Operators should treat
Postgres as the durable source and the cache as reconstructable process state.

Secrets do not belong in database-backed configuration. Deployment secrets such
as database URLs, secret keys, SMTP credentials, and SSH host-key storage are
environment or filesystem concerns.

## What is intentionally not here

This page does not document every internal table, test fixture, or planned
future table. Public docs should stay useful to sysops and callers. Contributor
schemas and migration details belong in the source and developer docs.
