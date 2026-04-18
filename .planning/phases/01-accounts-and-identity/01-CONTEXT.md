# Phase 1: Accounts & Identity - Context

**Gathered:** 2026-04-18
**Status:** Ready for planning

<domain>
## Phase Boundary

Build the `Foglet.Accounts` context — users, SSH keys, user tokens, Mix tasks for sysop
account management (create, promote, reset_password), and account deletion with
post-anonymization. No web routes; no TUI. SSH keys schema and storage only (used in auth
starting Phase 3). Sysop bootstraps accounts via Mix tasks; user self-service deferred.

Also: create the `configuration` table and `Foglet.Config` module with typed accessor
and ETS cache, seeded with `registration.mode = 'sysop_approved'`. Enforcement of that
mode is wired in Phase 3 (SSH guest flow).

</domain>

<decisions>
## Implementation Decisions

### Email verification & password reset (IDNT-02, IDNT-08)

- **D-01:** Token-generation only in Phase 1 — generate and store verification/reset tokens
  in `user_tokens`; no email is sent. Swoosh is wired in Phase 10; at that point the
  `Accounts.deliver_user_confirmation_instructions/2` and
  `Accounts.deliver_user_reset_password_instructions/2` functions gain a mailer call.
- **D-02:** Sysop-created accounts (`mix foglet.user.create`) are **auto-confirmed** —
  `confirmed_at` is set to `DateTime.utc_now()` at insert time. No verification token
  is generated for sysop-created accounts.
- **D-03:** Password reset entrypoint in Phase 1 is a sysop Mix task:
  `mix foglet.user.reset_password <handle>`. Prints the reset URL (with token) to stdout.
  No user self-service reset until Phase 10 wires in email delivery.

### Mix task interface (IDNT-05, IDNT-06, IDNT-08)

- **D-04:** `mix foglet.user.create` uses **CLI flags** — all required fields passed as flags:
  ```
  mix foglet.user.create --handle bman --email bman@example.com --password secret123
  ```
  Fully scriptable; works in CI and Dockerfile entrypoints. Missing required flags print
  usage and exit non-zero.
- **D-05:** `mix foglet.user.promote` uses **positional handle + `--role` flag**:
  ```
  mix foglet.user.promote bman --role sysop
  ```
  Valid roles: `user`, `mod`, `sysop`.
- **D-06:** `mix foglet.user.reset_password` uses **positional handle**:
  ```
  mix foglet.user.reset_password bman
  ```
  Generates a reset token, prints the URL to stdout. Token format follows the same
  `UserToken` pattern used for email confirmation.

### Auth layer implementation (IDNT-01 through IDNT-08)

- **D-07:** **Hand-roll the Accounts context against `docs/DATA_MODEL.md`**. Do NOT
  run `mix phx.gen.auth` — the data model is more opinionated than phx.gen.auth output
  (UUID v7, custom changesets, tombstone pattern, Argon2 already configured). Use
  phx.gen.auth source as a reference for token hashing patterns only.
- **D-08:** **`Foglet.Schema` macro module created from day one** at
  `lib/foglet_bbs/schema.ex`. Every schema in this phase and all future phases uses
  `use Foglet.Schema` instead of repeating `@primary_key`, `@foreign_key_type`, and
  `@timestamps_opts` boilerplate. See `docs/DATA_MODEL.md` §Conventions for the macro
  definition.

### Registration mode (config table)

- **D-09:** Default registration mode: **`sysop_approved`** — stored as
  `registration.mode = "sysop_approved"` in the `configuration` table, seeded in
  `priv/repo/seeds.exs`.
- **D-10:** Phase 1 scope for configuration: create the `configuration` table migration,
  the `Foglet.Config.Entry` schema, and the `Foglet.Config` module with:
  - `get!/1` typed accessor
  - ETS-backed cache (invalidated on write)
  - Seed `registration.mode`, `registration.require_email_verification = false`
  The enforcement of `registration.mode` in the SSH guest flow is wired in Phase 3.

### Claude's Discretion

- Token expiry durations (email confirmation, password reset) — use Phoenix auth defaults
  (e.g., 7 days for confirmation, 1 day for reset) unless DATA_MODEL.md specifies otherwise
- Handle validation regex — DATA_MODEL.md says "alphanumeric + `_`/`-`"; choose length
  bounds (e.g., 2–20 chars)
- ETS table name for config cache
- Error message copy in Mix tasks

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Schema + Data Model
- `docs/DATA_MODEL.md` — Authoritative schema definitions for `users`, `ssh_keys`,
  `user_tokens`, `configuration`; changeset names; anonymization flow; indexes;
  consistency invariants. READ IN FULL before planning migrations or contexts.
- `docs/DATA_MODEL.md` §1 (Accounts) — User, SSHKey, UserToken schemas and migration notes
- `docs/DATA_MODEL.md` §11 (Configuration) — Foglet.Config.Entry schema; ETS cache pattern;
  expected config keys including `registration.mode`
- `docs/DATA_MODEL.md` §Conventions — Foglet.Schema macro; UUID v7; utc_datetime_usec;
  soft-delete; citext

### Requirements
- `.planning/REQUIREMENTS.md` IDNT-01 through IDNT-08 — acceptance criteria for this phase
- `.planning/ROADMAP.md` §Phase 1 — Success criteria (5 items) and dependencies

### Project constraints
- `.planning/PROJECT.md` §Constraints — Stack locked; SSH-only; Argon2; no web UI for users

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `lib/foglet_bbs/repo.ex` — Ecto repo; use for all database operations
- `lib/foglet_bbs/application.ex` — OTP supervision tree; ETS table for config cache
  should be started here (or as a child of the application supervisor)
- `lib/mix/tasks/foglet.doctor.ex` — Reference for Mix task boilerplate and module naming
  conventions (`Mix.Tasks.Foglet.*`)

### Established Patterns
- `Foglet.Repo` — single repo, no multi-repo setup
- Mix tasks live in `lib/mix/tasks/foglet.{command}.ex` with module `Mix.Tasks.Foglet.{Command}`
- Tests mirror lib structure: `test/foglet_bbs/accounts/` for context tests,
  `test/mix/tasks/` for task tests
- `mix precommit` is the quality gate: format + Credo strict + test — must pass before commit

### Integration Points
- `application.ex` supervision tree — ETS table for Foglet.Config cache goes here as a
  named table started before application processes that read config
- Future phases consume: `Foglet.Accounts.authenticate_by_password/2` (Phase 3 SSH auth),
  `Foglet.Accounts.get_user_by_public_key/1` (Phase 3 key auth),
  `Foglet.Accounts.get_user!/1` (throughout)

</code_context>

<specifics>
## Specific Ideas

- "CLI flags for Mix tasks" — sysop experience should feel like a real server tool, not an
  interactive wizard. `--handle`, `--email`, `--password` flags; print the created handle
  and UUID to stdout on success.
- `mix foglet.user.promote bman --role sysop` — terse, positional handle; mirrors how
  sysop tooling feels in production Elixir apps (e.g., `bin/server rpc "..."`)
- The tombstone user (`[deleted]`) seeded in `priv/repo/seeds.exs` with a fixed UUID — plan
  for this in the seed file so anonymization works correctly from day one

</specifics>

<deferred>
## Deferred Ideas

- Email delivery for verification and reset — Phase 10 (Swoosh configured, templates written)
- SSH key management UI — Phase 3 (TUI). Phase 1 is schema + storage layer only.
- Registration mode enforcement — Phase 3 (SSH guest flow gates on `registration.mode`)
- Invite-only registration (invite code infrastructure) — not in roadmap yet; add to backlog
  if sysop-approved proves too restrictive
- User self-service password reset (no Mix task) — Phase 10 when email is wired

</deferred>

---

*Phase: 01-accounts-and-identity*
*Context gathered: 2026-04-18*
