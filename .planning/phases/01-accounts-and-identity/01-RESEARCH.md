# Phase 1: Accounts & Identity - Research

**Researched:** 2026-04-18
**Domain:** Elixir/Phoenix accounts context, Ecto schemas/migrations, Argon2 password hashing, ETS caching, Mix tasks
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**D-01:** Token-generation only in Phase 1 — generate and store verification/reset tokens in `user_tokens`; no email is sent. Swoosh is wired in Phase 10; at that point the `Accounts.deliver_user_confirmation_instructions/2` and `Accounts.deliver_user_reset_password_instructions/2` functions gain a mailer call.

**D-02:** Sysop-created accounts (`mix foglet.user.create`) are auto-confirmed — `confirmed_at` is set to `DateTime.utc_now()` at insert time. No verification token is generated for sysop-created accounts.

**D-03:** Password reset entrypoint in Phase 1 is a sysop Mix task: `mix foglet.user.reset_password <handle>`. Prints the reset URL (with token) to stdout. No user self-service reset until Phase 10 wires in email delivery.

**D-04:** `mix foglet.user.create` uses CLI flags — all required fields passed as flags:
```
mix foglet.user.create --handle bman --email bman@example.com --password secret123
```
Fully scriptable; works in CI and Dockerfile entrypoints. Missing required flags print usage and exit non-zero.

**D-05:** `mix foglet.user.promote` uses positional handle + `--role` flag:
```
mix foglet.user.promote bman --role sysop
```
Valid roles: `user`, `mod`, `sysop`.

**D-06:** `mix foglet.user.reset_password` uses positional handle:
```
mix foglet.user.reset_password bman
```
Generates a reset token, prints the URL to stdout. Token format follows the same `UserToken` pattern used for email confirmation.

**D-07:** Hand-roll the Accounts context against `docs/DATA_MODEL.md`. Do NOT run `mix phx.gen.auth` — the data model is more opinionated than phx.gen.auth output (UUID v7, custom changesets, tombstone pattern, Argon2 already configured). Use phx.gen.auth source as a reference for token hashing patterns only.

**D-08:** `Foglet.Schema` macro module created from day one at `lib/foglet_bbs/schema.ex`. Every schema in this phase and all future phases uses `use Foglet.Schema` instead of repeating `@primary_key`, `@foreign_key_type`, and `@timestamps_opts` boilerplate. See `docs/DATA_MODEL.md` §Conventions for the macro definition.

**D-09:** Default registration mode: `sysop_approved` — stored as `registration.mode = "sysop_approved"` in the `configuration` table, seeded in `priv/repo/seeds.exs`.

**D-10:** Phase 1 scope for configuration: create the `configuration` table migration, the `Foglet.Config.Entry` schema, and the `Foglet.Config` module with:
  - `get!/1` typed accessor
  - ETS-backed cache (invalidated on write)
  - Seed `registration.mode`, `registration.require_email_verification = false`
  The enforcement of `registration.mode` in the SSH guest flow is wired in Phase 3.

### Claude's Discretion

- Token expiry durations (email confirmation, password reset) — use Phoenix auth defaults (e.g., 7 days for confirmation, 1 day for reset) unless DATA_MODEL.md specifies otherwise
- Handle validation regex — DATA_MODEL.md says "alphanumeric + `_`/`-`"; choose length bounds (e.g., 2–20 chars)
- ETS table name for config cache
- Error message copy in Mix tasks

### Deferred Ideas (OUT OF SCOPE)

- Email delivery for verification and reset — Phase 10 (Swoosh configured, templates written)
- SSH key management UI — Phase 3 (TUI). Phase 1 is schema + storage layer only.
- Registration mode enforcement — Phase 3 (SSH guest flow gates on `registration.mode`)
- Invite-only registration (invite code infrastructure) — not in roadmap yet
- User self-service password reset (no Mix task) — Phase 10 when email is wired
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| IDNT-01 | User can create an account with email and password (Argon2-hashed) | `Foglet.Accounts` context with `registration_changeset/2` using `Argon2.hash_pwd_salt/1`; `users` migration with citext |
| IDNT-02 | User receives an email verification link after signup | Token generation in `user_tokens` with context `"confirm"`; delivery deferred to Phase 10; sysop accounts auto-confirmed |
| IDNT-03 | User has a permanent, case-preserving handle that is unique case-insensitively (citext) | `citext` column on `users.handle`; `Ecto.Changeset.validate_format/3` + `unique_constraint/2` |
| IDNT-04 | User can add SSH public keys to their account from inside the TUI | `ssh_keys` schema and `Foglet.Accounts` storage functions; TUI deferred to Phase 3 |
| IDNT-05 | Sysop can create accounts via `mix foglet.user.create` | `Mix.Tasks.Foglet.User.Create` with `OptionParser.parse!/2` using `strict:` switch list |
| IDNT-06 | Sysop can assign roles (user / mod / sysop) via `mix foglet.user.promote` | `Mix.Tasks.Foglet.User.Promote` with positional handle + `--role` flag; `role_changeset/2` |
| IDNT-07 | User account can be deleted with post-anonymization | Multi-step `Ecto.Multi` transaction: rewrite posts, delete associated records, zero user row |
| IDNT-08 | User can reset their password | `Mix.Tasks.Foglet.User.ResetPassword`; token generated via `UserToken.build_email_token/2` with context `"reset_password"`; URL printed to stdout |
</phase_requirements>

---

## Summary

Phase 1 builds the `Foglet.Accounts` context and `Foglet.Config` module from scratch, hand-rolled against `docs/DATA_MODEL.md`. The M0 scaffold gives us a clean slate: no existing schemas, no migrations yet, just `FogletBbs.Repo`, `FogletBbs.Application`, and the `mix foglet.doctor` task as a reference. Argon2 (`argon2_elixir ~> 4.0`, locked at 4.1.3) is already in the dependency tree via comeonin. PostgreSQL with the `citext` extension is required — `mix foglet.doctor` already validates both are present.

The key engineering decisions are already locked in CONTEXT.md. The work is structured, not exploratory: create `Foglet.Schema` macro, write migrations for `users`/`ssh_keys`/`user_tokens`/`configuration`, implement the `Foglet.Accounts` context functions that Phase 3 will call, build three Mix tasks using `OptionParser`, seed the tombstone user and default config, and wire the `Foglet.Config` ETS cache into the application supervision tree.

One important constraint: `mix precommit` does NOT run tests — it runs compile, deps.unlock --unused, format, and credo --strict. Tests are run separately with `mix test`. This matters for the wave commit strategy: precommit is the gate before each git commit; a separate `mix test` run is required for wave-level validation.

**Primary recommendation:** Follow DATA_MODEL.md schemas exactly, use phx.gen.auth templates (available at `deps/phoenix/priv/templates/phx.gen.auth/`) as the reference for token-hashing patterns only (`:crypto.hash(:sha256, ...)` + `Base.url_encode64/2`), and implement the ETS config cache as a named table started in `FogletBbs.Application` before other children.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| User schema / changesets | Database / Storage | — | Core persistence layer; schema drives all other layers |
| Password hashing | API / Backend | — | Security-sensitive; must happen server-side in Accounts context |
| Token generation and storage | API / Backend | Database / Storage | Application generates token, DB stores hashed form |
| Role management | API / Backend | — | `role_changeset/2` is a sysop-only pathway, enforced in context |
| SSH key storage | Database / Storage | — | Schema + fingerprint uniqueness only in Phase 1; auth logic in Phase 3 |
| Account deletion / anonymization | API / Backend | Database / Storage | Multi-step `Ecto.Multi` transaction coordinated in context |
| Config ETS cache | API / Backend | — | Application-level in-memory cache, started in supervision tree |
| Configuration persistence | Database / Storage | — | `configuration` table; ETS is the read layer, DB is source of truth |
| Mix task CLI interface | — | API / Backend | Tasks are thin wrappers that call into `Foglet.Accounts` context |

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `ecto_sql` | ~> 3.13 (locked) | Migrations, Repo queries | Project already has this; standard Phoenix Ecto integration |
| `postgrex` | >= 0.0.0 (locked) | Postgres adapter | Project already wired |
| `argon2_elixir` | ~> 4.0 (locked at 4.1.3) | Password hashing via `Argon2.hash_pwd_salt/1` and `Argon2.verify_pass/2` | Already in deps; M0 decision |

[VERIFIED: mix.lock — argon2_elixir 4.1.3 confirmed in project]

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `:crypto` (OTP built-in) | OTP 28.3.1 | Token hashing — `:crypto.hash(:sha256, raw_token)` | Used in `UserToken.build_email_token/2` and verification queries |
| `Ecto.Multi` | ecto_sql | Multi-step atomic transactions | Account deletion (anonymization), any operation touching multiple tables |
| `:ets` (OTP built-in) | OTP 28.3.1 | In-memory config cache for `Foglet.Config` | Named table, started before application children |

[VERIFIED: deps/argon2_elixir/lib/argon2.ex — confirms `hash_pwd_salt/1` and `verify_pass/2` are the public API]

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `OptionParser.parse!/2` in Mix tasks | Interactive prompts | CLI flags chosen (D-04) — scriptable, CI-friendly |
| Hand-rolled Accounts context | `mix phx.gen.auth` | D-07 locks this — phx.gen.auth schema doesn't match UUID v7 / tombstone / custom changeset needs |
| ETS config cache | Database read on every config access | ETS is zero-latency; config table changes infrequently |

**Installation:** No new packages needed. All dependencies are already in `mix.exs`.

---

## Architecture Patterns

### System Architecture Diagram

```
Mix Task CLI
  (create/promote/reset_password)
         |
         | calls
         v
Foglet.Accounts (context)
  |           |           |
  v           v           v
User        SSHKey    UserToken
changeset   insert    build_email_token
  |                       |
  v                       v
Repo.insert/update    Repo.insert (hashed token stored)
  |
  v
PostgreSQL
  users (citext handle/email, argon2 password_hash)
  ssh_keys (fingerprint unique)
  user_tokens (context, hashed binary token)
  configuration (key/value jsonb, ETS-cached on read)

                          ^
                          | cache invalidated on write
                  Foglet.Config
                  (ETS named table :foglet_config)
                          |
                          | started in
                  FogletBbs.Application
                  supervision tree
```

### Recommended Project Structure
```
lib/foglet_bbs/
├── schema.ex                    # Foglet.Schema macro (use this everywhere)
├── accounts.ex                  # Foglet.Accounts context — public API
├── accounts/
│   ├── user.ex                  # Foglet.Accounts.User schema + changesets
│   ├── ssh_key.ex               # Foglet.Accounts.SSHKey schema
│   └── user_token.ex            # Foglet.Accounts.UserToken schema + token helpers
├── config.ex                    # Foglet.Config — ETS cache + typed get!/1
├── config/
│   └── entry.ex                 # Foglet.Config.Entry schema
lib/mix/tasks/
├── foglet.user.create.ex        # Mix.Tasks.Foglet.User.Create
├── foglet.user.promote.ex       # Mix.Tasks.Foglet.User.Promote
└── foglet.user.reset_password.ex # Mix.Tasks.Foglet.User.ResetPassword
priv/repo/migrations/
├── TIMESTAMP_create_citext_extension.exs
├── TIMESTAMP_create_users.exs
├── TIMESTAMP_create_ssh_keys.exs
├── TIMESTAMP_create_user_tokens.exs
└── TIMESTAMP_create_configuration.exs
priv/repo/seeds.exs              # tombstone user + default config entries
test/foglet_bbs/accounts/
├── accounts_test.exs            # context function tests
├── user_test.exs                # changeset tests
└── user_token_test.exs          # token build/verify tests
test/mix/tasks/
├── foglet_user_create_test.exs
├── foglet_user_promote_test.exs
└── foglet_user_reset_password_test.exs
```

### Pattern 1: Foglet.Schema Macro
**What:** A shared schema macro that eliminates UUID/timestamp boilerplate from every schema
**When to use:** Every schema in the project — required by D-08

```elixir
# Source: docs/DATA_MODEL.md §Conventions (authoritative) +
#         deps/phoenix/priv/templates/phx.gen.auth/schema.ex (reference)
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

Note: DATA_MODEL.md specifies `Ecto.UUID` (not `:binary_id`). The config.exs already sets `generators: [binary_id: true]` which generates migration columns as `:binary_id`. Both resolve to the same Postgres `uuid` type; the distinction is only in the Elixir type adapter. Use `Ecto.UUID` in the schema macro and `:binary_id` in migrations (per the generator config).

[VERIFIED: deps/phoenix/priv/templates/phx.gen.auth/schema.ex — confirms this pattern; docs/DATA_MODEL.md §Conventions — specifies Ecto.UUID]

### Pattern 2: Token Generation (phx.gen.auth reference pattern)
**What:** Generate a random token, store its SHA256 hash in the DB, return the raw token to the caller
**When to use:** Password reset tokens, email confirmation tokens — any context where the token itself must not be reconstructable from the DB

```elixir
# Source: deps/phoenix/priv/templates/phx.gen.auth/ (reference only per D-07)
# UserToken module pattern:
@hash_algorithm :sha256
@rand_size 32

def build_email_token(user, context) do
  build_hashed_token(user, context, user.email)
end

defp build_hashed_token(user, context, sent_to) do
  token = :crypto.strong_rand_bytes(@rand_size)
  hashed_token = :crypto.hash(@hash_algorithm, token)

  {Base.url_encode64(token, padding: false),
   %Foglet.Accounts.UserToken{
     token: hashed_token,
     context: context,
     sent_to: sent_to,
     user_id: user.id
   }}
end

def verify_email_token_query(token, context) do
  case Base.url_decode64(token, padding: false) do
    {:ok, decoded_token} ->
      hashed_token = :crypto.hash(@hash_algorithm, decoded_token)
      days = days_for_context(context)
      query =
        from token in by_token_and_context_query(hashed_token, context),
          join: user in assoc(token, :user),
          where: token.inserted_at > ago(^days, "day") and token.sent_to == user.email,
          select: user
      {:ok, query}
    :error ->
      :error
  end
end

defp days_for_context("confirm"), do: 7
defp days_for_context("reset_password"), do: 1
```

[VERIFIED: deps/phoenix/priv/templates/phx.gen.auth/context_functions.ex — confirms pattern; hexdocs.pm/phoenix — build_email_token usage]

### Pattern 3: Argon2 Password Hashing
**What:** Hash on write with `hash_pwd_salt/1`, verify on read with `verify_pass/2`
**When to use:** `password_changeset/2` and `authenticate_by_password/2`

```elixir
# Source: deps/argon2_elixir/lib/argon2.ex [VERIFIED]
# In User changeset (hash on put_change):
defp put_password_hash(changeset) do
  case get_change(changeset, :password) do
    nil -> changeset
    password ->
      changeset
      |> put_change(:password_hash, Argon2.hash_pwd_salt(password))
      |> delete_change(:password)
  end
end

# In Accounts context (verify on authenticate):
def authenticate_by_password(handle, password) do
  user = get_user_by_handle(handle)
  cond do
    user && Argon2.verify_pass(password, user.password_hash) -> {:ok, user}
    user -> {:error, :invalid_credentials}
    true ->
      Argon2.no_user_verify()  # timing-safe dummy hash to prevent user enumeration
      {:error, :invalid_credentials}
  end
end
```

**Test configuration:** In `config/test.exs`, add:
```elixir
config :argon2_elixir, t_cost: 1, m_cost: 8
```
This makes tests fast without changing the algorithm. [ASSUMED — standard phx.gen.auth recommendation; not yet in project's test.exs]

### Pattern 4: OptionParser in Mix Tasks
**What:** Parse CLI flags with strict mode — unknown options raise rather than silently ignored
**When to use:** All three Mix tasks in this phase

```elixir
# Source: hexdocs.pm/elixir/1.19.3/OptionParser.html [VERIFIED]
# For mix foglet.user.create (D-04):
def run(args) do
  {opts, _rest, _invalid} =
    OptionParser.parse!(args,
      strict: [handle: :string, email: :string, password: :string]
    )

  handle  = Keyword.fetch!(opts, :handle)
  email   = Keyword.fetch!(opts, :email)
  password = Keyword.fetch!(opts, :password)
  # ...
rescue
  OptionParser.ParseError ->
    Mix.shell().error("Usage: mix foglet.user.create --handle HANDLE --email EMAIL --password PASSWORD")
    exit({:shutdown, 1})
end

# For mix foglet.user.promote (D-05) — positional handle + --role flag:
def run(args) do
  {opts, [handle | _], _invalid} =
    OptionParser.parse!(args, strict: [role: :string])
  role = Keyword.fetch!(opts, :role)
  # ...
end
```

[VERIFIED: hexdocs.pm/elixir/1.19.3/OptionParser.html — `strict:` vs `switches:` behavior]

### Pattern 5: ETS-Backed Config Cache
**What:** Named ETS table for config key/value caching; started in application supervision tree, invalidated on write
**When to use:** `Foglet.Config` module

```elixir
# Application supervision tree addition:
# lib/foglet_bbs/application.ex
defp init_config_cache do
  :ets.new(:foglet_config, [:set, :named_table, :public, read_concurrency: true])
end

# Called before Supervisor.start_link/2, or as a first child:
# In start/2:
# _ = :ets.new(:foglet_config, [:set, :named_table, :public, read_concurrency: true])

# Foglet.Config.get!/1:
def get!(key) do
  case :ets.lookup(:foglet_config, key) do
    [{^key, value}] -> value
    [] ->
      entry = Repo.get_by!(Foglet.Config.Entry, key: key)
      :ets.insert(:foglet_config, {key, entry.value})
      entry.value
  end
end

# On write — invalidate the key:
def put!(key, value, updated_by_user_id) do
  # ... DB update ...
  :ets.delete(:foglet_config, key)
end
```

[ASSUMED — ETS pattern is standard Elixir; specific implementation details (read_concurrency, :public vs :protected) are discretionary]

### Pattern 6: Migration for User Role Enum
**What:** Postgres `CREATE TYPE` for the `user_role` enum, referenced in the `users` table
**When to use:** `users` migration

```elixir
# Source: docs/DATA_MODEL.md §1 Accounts (authoritative)
# In migration:
def up do
  execute("CREATE TYPE user_role AS ENUM ('user', 'mod', 'sysop')")
  # ... create table ...
end

def down do
  drop table(:users)
  execute("DROP TYPE user_role")
end
```

Use `def up/def down` instead of `def change` when `execute/1` with DDL is involved, because `change` cannot auto-reverse custom SQL.

[VERIFIED: Ecto migration pattern for custom types — standard practice; docs/DATA_MODEL.md specifies the enum values]

### Anti-Patterns to Avoid

- **`Ecto.Changeset.validate_number/2` with `:allow_nil`:** This option does not exist (CLAUDE.md constraint). Don't use it for any numeric fields.
- **`changeset[:field]` access syntax on structs:** Structs don't implement Access. Use `Ecto.Changeset.get_field/2` or `changeset.data.field`. (CLAUDE.md constraint)
- **Nesting modules in the same file:** Each schema, context, and task must be its own file. (CLAUDE.md constraint)
- **`String.to_atom/1` on CLI input (handle, role):** Memory leak risk. Use pattern matching on known strings or `Ecto.Enum` cast. (CLAUDE.md constraint)
- **Listing `user_id` in `cast` calls:** Fields set programmatically must not be castable. Set them explicitly on the struct. (CLAUDE.md constraint)
- **`Process.sleep/1` in tests:** Use `start_supervised!/1` for process lifecycle; `:sys.get_state/1` for synchronization. (CLAUDE.md constraint)
- **Using `def change` with `execute/1` in migrations:** Use `def up/def down` instead — `change` cannot reverse raw SQL.
- **Skipping `Argon2.no_user_verify()` on "user not found" path:** Timing side-channel reveals user existence. Always call this in the false branch.
- **`OptionParser.parse!/2` with `switches:` instead of `strict:`:** `switches:` mode allows unknown flags silently. Use `strict:` for task inputs so unknown flags raise an error.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Password hashing | Custom bcrypt/sha integration | `Argon2.hash_pwd_salt/1` + `Argon2.verify_pass/2` | Memory-hard, timing-safe, includes salt; the library handles all parameters |
| Constant-time comparison | Custom string compare | `Plug.Crypto.secure_compare/2` or Argon2's built-in verify | Naive comparison is vulnerable to timing attacks |
| Token generation | UUID or timestamp-based | `:crypto.strong_rand_bytes(32)` + `:crypto.hash(:sha256, ...)` | Cryptographically random; SHA256 hash stored, raw token returned — can't reconstruct from DB |
| Dummy hash (user not found) | `false` return | `Argon2.no_user_verify()` | Prevents timing-based user enumeration |
| Case-insensitive handle uniqueness | Manual lowercasing in Elixir | `citext` Postgres column type | DB enforces it; display case preserved in stored value |
| Concurrent-safe config cache invalidation | GenServer wrapping ETS | `:ets.delete/2` on write + `:ets.insert/2` on miss | ETS `:set` with `:public` and `read_concurrency: true` handles this natively for read-heavy workloads |

**Key insight:** In the password/token domain, custom implementations introduce subtle security bugs. The phx.gen.auth templates exist precisely because these patterns are easy to get wrong.

---

## Common Pitfalls

### Pitfall 1: `def change` with `execute/1` in Migration
**What goes wrong:** Migration runs successfully on `mix ecto.migrate` but fails or errors on `mix ecto.rollback` because Ecto can't auto-reverse SQL statements.
**Why it happens:** `def change` generates a reverse migration automatically, but `execute/1` produces opaque SQL.
**How to avoid:** Any migration that calls `execute/1` (for CREATE TYPE, CREATE EXTENSION, etc.) must use `def up/def down` with explicit reversal.
**Warning signs:** Migration file contains `execute/1` inside `def change`.

### Pitfall 2: citext Extension Not Enabled
**What goes wrong:** Migration fails with `ERROR: type "citext" does not exist`.
**Why it happens:** citext must be created before the first table that uses it; it's a separate migration.
**How to avoid:** First migration should be `execute "CREATE EXTENSION IF NOT EXISTS citext"`. The `mix foglet.doctor` task already checks for it, but that's after the fact.
**Warning signs:** `mix foglet.doctor` is passing but migration was run manually against a fresh DB.

### Pitfall 3: Postgres Enum Type in Migrations
**What goes wrong:** Rolling back a migration fails because the `user_role` enum type can't be dropped while tables reference it.
**Why it happens:** FK and column constraints hold references to the type.
**How to avoid:** In `def down`, drop the table before dropping the type: `drop table(:users)` then `execute "DROP TYPE user_role"`.
**Warning signs:** Mix task output shows `ERROR: cannot drop type user_role because other objects depend on it`.

### Pitfall 4: ETS Table Created Before Application Starts
**What goes wrong:** Tests that call `Foglet.Config.get!` fail with `:ets.lookup` `ArgumentError: argument error` because the table doesn't exist.
**Why it happens:** The ETS table is created in `FogletBbs.Application.start/2` but tests may call Config functions directly before the full application starts.
**How to avoid:** In test support, either ensure the application is started (it typically is via `ExUnit.start()`), or use `start_supervised!` to start a config-aware process. Alternatively, create the table with `if :ets.whereis(:foglet_config) == :undefined` guard in the application start.
**Warning signs:** `** (ArgumentError) argument error` with `:ets.lookup/2` in stack trace during tests.

### Pitfall 5: Mix Task Without `Application.ensure_all_started`
**What goes wrong:** `mix foglet.user.create` crashes because `FogletBbs.Repo` is not started.
**Why it happens:** Mix tasks don't start the application by default; the Repo (GenServer) isn't running.
**How to avoid:** Add `Application.ensure_all_started(:foglet_bbs)` at the start of `run/1`. See `foglet.doctor` as reference — it uses `Application.ensure_all_started(:postgrex)`.
**Warning signs:** `** (exit) exited in: GenServer.call(FogletBbs.Repo, ...)` with `:noproc`.

### Pitfall 6: Handle Validation Must Handle Binary Comparison for citext
**What goes wrong:** Checking handle uniqueness in the changeset with `unsafe_validate_unique/3` before insert may not detect case-insensitive collisions because Elixir-level comparison is case-sensitive.
**Why it happens:** `unsafe_validate_unique` runs a DB query, so it does use citext — but if you add an Elixir-level uniqueness check, it will miss `"Bman"` when `"bman"` exists.
**How to avoid:** Rely exclusively on `unique_constraint(:handle)` (DB-level) and `unsafe_validate_unique(:handle, ...)` (query-level pre-check). Never add an Elixir-level case-sensitive string comparison for handle uniqueness.
**Warning signs:** Two users with `"bman"` and `"Bman"` existing in the DB.

### Pitfall 7: Tombstone User Fixed UUID Must Be Stable
**What goes wrong:** Seeds run multiple times (CI, fresh installs) insert duplicate tombstone users, or anonymization fails because the known UUID doesn't match the inserted row.
**Why it happens:** `Repo.insert!` on re-run creates a new row with a new auto-generated UUID.
**How to avoid:** Use `Repo.insert!` with an explicit `id` field set to a hardcoded UUID string, wrapped in an `on_conflict: :nothing` clause. Or use `Repo.get_by` first and only insert if absent.
**Warning signs:** Anonymization rewrites `user_id` to a UUID that no longer exists, causing FK violations.

---

## Code Examples

### Tombstone User Seed Pattern
```elixir
# Source: docs/DATA_MODEL.md §1 Accounts (anonymization flow) + standard Ecto pattern
# priv/repo/seeds.exs
import Ecto.Query
alias FogletBbs.Repo
alias Foglet.Accounts.User

@tombstone_id "00000000-0000-0000-0000-000000000001"

unless Repo.get(User, @tombstone_id) do
  Repo.insert!(%User{
    id: @tombstone_id,
    handle: "[deleted]",
    email: "tombstone@localhost",
    password_hash: "invalid-not-a-real-hash",
    confirmed_at: DateTime.utc_now(),
    role: :user
  })
end
```

### Configuration Seed Pattern
```elixir
# priv/repo/seeds.exs — seeding default config entries
alias Foglet.Config.Entry

default_config = [
  {"registration.mode", %{"v" => "sysop_approved"}, "Account registration policy"},
  {"registration.require_email_verification", %{"v" => false}, "Require email verification on signup"}
]

Enum.each(default_config, fn {key, value, description} ->
  case Repo.get_by(Entry, key: key) do
    nil ->
      Repo.insert!(%Entry{key: key, value: value, description: description})
    _existing ->
      :ok
  end
end)
```

### Account Deletion / Anonymization Pattern
```elixir
# Source: docs/DATA_MODEL.md §1 Accounts (anonymization flow) [VERIFIED]
def delete_user(user) do
  tombstone_id = Application.get_env(:foglet_bbs, :tombstone_user_id)

  Ecto.Multi.new()
  |> Ecto.Multi.update_all(:rewrite_posts, fn _ ->
    from(p in Foglet.Posts.Post, where: p.user_id == ^user.id)
  end, set: [user_id: tombstone_id])
  |> Ecto.Multi.delete_all(:delete_ssh_keys,
    from(k in Foglet.Accounts.SSHKey, where: k.user_id == ^user.id))
  |> Ecto.Multi.delete_all(:delete_tokens,
    from(t in Foglet.Accounts.UserToken, where: t.user_id == ^user.id))
  |> Ecto.Multi.update(:zero_user, User.deletion_changeset(user))
  |> Repo.transaction()
end

# deletion_changeset/1 — clears PII, sets deleted_at, randomizes email
def deletion_changeset(user) do
  user
  |> change(%{
    deleted_at: DateTime.utc_now(),
    location: nil,
    tagline: nil,
    real_name: nil,
    email: "deleted-#{user.id}@localhost",
    password_hash: "invalid"
  })
end
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `bcrypt_elixir` for passwords | `argon2_elixir ~> 4.0` (Argon2id default) | phx.gen.auth now recommends Argon2 | Memory-hard; better resistance to GPU cracking |
| `phx.gen.auth` generates everything | Hand-roll for opinionated data models | Ongoing — phx.gen.auth 1.8 still generates web routes and sessions | D-07 locked this — phx.gen.auth output doesn't fit UUID v7 / tombstone / SSH-only pattern |
| `Ecto.UUID` vs `:binary_id` in migrations | Use `:binary_id` in migrations, `Ecto.UUID` in schemas | Ecto 3.x | The generator config (`binary_id: true`) drives migration output; schema macro uses `Ecto.UUID` |
| Naked `:ets.new/2` in module | Create in application start before supervision tree | OTP best practice | Guarantees table exists before any process tries to read it |

**Deprecated/outdated:**
- `comeonin` directly: Still in the dependency tree (transitive dep of argon2_elixir) but use `Argon2` module directly, not `Comeonin` functions — the deprecated `add_hash/2` functions are in comeonin, not `Argon2`.
- `Bcrypt.hash_pwd_salt/1` for new projects using argon2_elixir: Don't mix libraries.

---

## Runtime State Inventory

Step 2.5 SKIPPED — this is a greenfield phase with no existing user data, configuration entries, or named schema to rename. The `priv/repo/migrations/` directory has only `.formatter.exs`. No runtime state to audit.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Elixir | Runtime | Yes | 1.19.5 | — |
| OTP | Runtime | Yes | 28.3.1 | — |
| PostgreSQL | Ecto Repo | No (not running) | — | Must start before `mix ecto.migrate` |
| citext extension | `users` migration | Unknown (DB not running) | — | `CREATE EXTENSION IF NOT EXISTS citext` in migration |
| ssh-keygen | SSH key fingerprint generation in tests | Yes | /usr/bin/ssh-keygen | — |

**Missing dependencies with fallback:**
- PostgreSQL is not running in this shell session. Plans must include verification that `mix foglet.doctor` passes (which checks citext + postgres) before running migrations.

**Note:** `mix foglet.doctor` already exists and validates postgres + citext. The plan should use it as the pre-migration gate.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | ExUnit (built-in Elixir) |
| Config file | `test/test_helper.exs` |
| Quick run command | `mix test test/foglet_bbs/accounts/` |
| Full suite command | `mix test` |
| Precommit gate | `mix precommit` (compile + credo + format — does NOT run tests) |

**Important:** `mix precommit` does not include `test`. Tests are a separate step. Wave commits should run `mix precommit` then `mix test` (or targeted test files) to validate.

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| IDNT-01 | `registration_changeset/2` creates user with hashed password | unit | `mix test test/foglet_bbs/accounts/user_test.exs` | No — Wave 0 |
| IDNT-01 | Duplicate email rejected (citext) | unit | `mix test test/foglet_bbs/accounts/user_test.exs` | No — Wave 0 |
| IDNT-02 | `build_email_token/2` with context "confirm" creates UserToken | unit | `mix test test/foglet_bbs/accounts/user_token_test.exs` | No — Wave 0 |
| IDNT-03 | Duplicate handle rejected case-insensitively | unit | `mix test test/foglet_bbs/accounts/user_test.exs` | No — Wave 0 |
| IDNT-03 | Handle with invalid chars rejected | unit | `mix test test/foglet_bbs/accounts/user_test.exs` | No — Wave 0 |
| IDNT-04 | `register_ssh_key/2` stores key with computed fingerprint | unit | `mix test test/foglet_bbs/accounts/accounts_test.exs` | No — Wave 0 |
| IDNT-04 | Duplicate fingerprint across users rejected | unit | `mix test test/foglet_bbs/accounts/accounts_test.exs` | No — Wave 0 |
| IDNT-05 | `mix foglet.user.create --handle ... --email ... --password ...` succeeds | integration | `mix test test/mix/tasks/foglet_user_create_test.exs` | No — Wave 0 |
| IDNT-05 | Missing required flag exits non-zero | integration | `mix test test/mix/tasks/foglet_user_create_test.exs` | No — Wave 0 |
| IDNT-06 | `mix foglet.user.promote bman --role sysop` updates role | integration | `mix test test/mix/tasks/foglet_user_promote_test.exs` | No — Wave 0 |
| IDNT-06 | Invalid role string rejected | integration | `mix test test/mix/tasks/foglet_user_promote_test.exs` | No — Wave 0 |
| IDNT-07 | `delete_user/1` rewrites posts to tombstone, clears PII | unit | `mix test test/foglet_bbs/accounts/accounts_test.exs` | No — Wave 0 |
| IDNT-08 | `mix foglet.user.reset_password bman` prints URL with token | integration | `mix test test/mix/tasks/foglet_user_reset_password_test.exs` | No — Wave 0 |

### Sampling Rate
- **Per task commit:** `mix precommit && mix test test/foglet_bbs/accounts/`
- **Per wave merge:** `mix precommit && mix test`
- **Phase gate:** `mix precommit && mix test` — full suite green before verification

### Wave 0 Gaps
- [ ] `test/foglet_bbs/accounts/user_test.exs` — changeset + schema tests (IDNT-01, IDNT-03)
- [ ] `test/foglet_bbs/accounts/user_token_test.exs` — token build/verify (IDNT-02, IDNT-08)
- [ ] `test/foglet_bbs/accounts/accounts_test.exs` — context function tests (IDNT-04, IDNT-07)
- [ ] `test/mix/tasks/foglet_user_create_test.exs` — Mix task integration (IDNT-05)
- [ ] `test/mix/tasks/foglet_user_promote_test.exs` — Mix task integration (IDNT-06)
- [ ] `test/mix/tasks/foglet_user_reset_password_test.exs` — Mix task integration (IDNT-08)
- [ ] Add `config :argon2_elixir, t_cost: 1, m_cost: 8` to `config/test.exs` (makes password tests fast)
- [ ] `test/support/accounts_fixtures.ex` — shared user/key creation helpers

---

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | Yes | Argon2id via `argon2_elixir ~> 4.0`; `Argon2.no_user_verify()` on user-not-found path |
| V3 Session Management | No (Phase 1 has no sessions) | — |
| V4 Access Control | Partial | `role` enum; role changes only via `role_changeset/2` (sysop pathway, Mix task only in Phase 1) |
| V5 Input Validation | Yes | `Ecto.Changeset` validates handle format, email format, password length; OptionParser `strict:` rejects unknown flags |
| V6 Cryptography | Yes | `:crypto.strong_rand_bytes(32)` for tokens; `:crypto.hash(:sha256, ...)` for storage; never hand-rolled |

### Known Threat Patterns for This Stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| User enumeration via timing (login) | Information disclosure | `Argon2.no_user_verify()` in the "user not found" branch |
| Token forgery / DB reconstruction | Tampering | Store SHA256 hash; return raw token — hash cannot be reversed to recover raw token |
| Handle squatting / case collision | Tampering | `citext` unique index; case-insensitive at DB level |
| Password too long (bcrypt-style length DoS) | Denial of service | Validate `password` max 72 bytes in changeset (phx.gen.auth reference shows this for bcrypt; for Argon2 the limit is higher but a 1000-char password is still worth rejecting at the application layer for sanity) |
| Atom exhaustion via `String.to_atom` on CLI input | Denial of service | Use pattern matching on known strings for role; `Ecto.Enum` cast rejects unknown values |
| PII leak in tombstone anonymization | Information disclosure | Verify `deletion_changeset/1` clears: email (randomized), `real_name`, `location`, `tagline`; sets `deleted_at`; invalidates `password_hash` |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Argon2 test config (`t_cost: 1, m_cost: 8`) is not yet in `config/test.exs` | Standard Stack / Pitfalls | Tests will be slow (10+ seconds per password hash) but will still pass |
| A2 | ETS table should use `:public` + `read_concurrency: true` for config cache | Code Examples | Stricter `:protected` access would still work but requires a GenServer wrapper for reads from other processes |
| A3 | Token expiry: 7 days for confirmation, 1 day for reset | Code Examples | If DATA_MODEL.md specified different durations (it doesn't — these are "Claude's Discretion" per CONTEXT.md), these values would need changing |
| A4 | Handle length bounds: 2–20 characters | Standard Stack | CONTEXT.md marks this as Claude's Discretion; any reasonable bounds work |
| A5 | Tombstone user UUID should be `00000000-0000-0000-0000-000000000001` | Code Examples | Any stable hardcoded UUID works; the exact value is arbitrary but must be consistent between seeds and application code |

---

## Open Questions

1. **Should password max length be validated in changeset?**
   - What we know: Argon2 has no 72-byte truncation issue (unlike bcrypt). phx.gen.auth validates `max: 72` for bcrypt compatibility, but for Argon2 longer passwords are genuinely hashed.
   - What's unclear: Whether an application-level max (e.g., 1000 chars) should be imposed to prevent Argon2 DoS via extremely long passwords (memory-hard + very long input = real CPU/memory cost).
   - Recommendation: Validate `max: 256` as a sensible upper bound. This is Claude's discretion per CONTEXT.md.

2. **ETS table ownership in tests**
   - What we know: ETS named tables created in `Application.start/2` exist for the test suite's lifetime (application is started by ExUnit). But some test files may bypass the application start.
   - What's unclear: Whether `FogletBbs.DataCase` properly guarantees the ETS table exists.
   - Recommendation: Add a guard in the `Foglet.Config` module: if the table doesn't exist on `get!/1`, create it first (defensive init). Or document that all Config tests require `use FogletBbs.DataCase`.

---

## Sources

### Primary (HIGH confidence)
- `docs/DATA_MODEL.md` — authoritative schema definitions, changeset names, anonymization flow, ETS pattern, config keys
- `deps/phoenix/priv/templates/phx.gen.auth/` — token hashing reference patterns (migration.ex, schema.ex, context_functions.ex)
- `deps/argon2_elixir/lib/argon2.ex` — confirmed `hash_pwd_salt/1`, `verify_pass/2`, `no_user_verify/0` API
- `lib/mix/tasks/foglet.doctor.ex` — confirmed Mix task module naming, boilerplate, `Application.ensure_all_started` pattern
- `mix.exs` / `mix.lock` — confirmed dependency versions and existing aliases
- `test/support/data_case.ex` — confirmed sandbox setup, `errors_on/1` helper pattern
- `config/config.exs` — confirmed `generators: [binary_id: true]` setting
- Context7 `/websites/hexdocs_pm_elixir_1_19_3` — OptionParser.parse!/2 strict mode behavior

### Secondary (MEDIUM confidence)
- Context7 `/phoenixframework/phoenix` — token build/verify pattern (build_email_token, SHA256 approach)
- Context7 `/websites/hexdocs_pm_ecto` — citext migration pattern (`execute "CREATE EXTENSION IF NOT EXISTS citext"`)
- Context7 `/phoenixframework/phoenix` — `days_for_context` private function pattern for token expiry

### Tertiary (LOW confidence)
- A1: Argon2 test config recommendation (standard practice but not verified against this project's existing test.exs)

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — verified against mix.lock, deps/ source, and DATA_MODEL.md
- Architecture: HIGH — DATA_MODEL.md is authoritative; phx.gen.auth templates verified as reference
- Pitfalls: HIGH — sourced from Ecto/Elixir/OTP behavior, CLAUDE.md constraints, and pattern analysis
- Token patterns: HIGH — verified against phx.gen.auth source templates in deps/

**Research date:** 2026-04-18
**Valid until:** 2026-05-18 (stable ecosystem — Ecto/Phoenix/Argon2 don't change rapidly)

## Project Constraints (from CLAUDE.md)

The following CLAUDE.md directives apply to this phase and must be honored by the planner:

| Directive | Impact on Phase 1 |
|-----------|------------------|
| `use Layouts.app flash={@flash}` in LiveViews | Not applicable — no LiveViews in Phase 1 |
| No `flash_group` outside layouts.ex | Not applicable |
| Use `<.icon>` for icons, not Heroicons modules | Not applicable — no web UI |
| Use `mix precommit` alias for quality gate | Each commit must pass `mix precommit` (compile + credo + format) |
| Use `Req` for HTTP; avoid httpoison/tesla | Not applicable — no HTTP calls in Phase 1 |
| Lists do not support index access `list[i]` | Applies to any list iteration in Mix tasks or changeset code |
| Bind result of `if`/`case`/`cond` to variable outside block | Applies to socket assigns pattern (not in Phase 1, but guard for tests) |
| Never nest multiple modules in same file | Each schema, context, and task must be a separate file |
| Never use map access syntax on structs (`changeset[:field]`) | Use `Ecto.Changeset.get_field/2` or `changeset.data.field` |
| `validate_number/2` does not support `:allow_nil` | Avoid this option on any numeric changeset validations |
| Fields set programmatically must not be in `cast` | `user_id`, `fingerprint`, `confirmed_at` must be set explicitly, not cast |
| Use `start_supervised!/1` in tests | All process-starting tests must use this |
| Avoid `Process.sleep/1` in tests | Use `Process.monitor` + `assert_receive` or `:sys.get_state/1` |
| `Ecto.Schema` fields use `:string` even for text columns | `field :body, :string` not `field :body, :text` |
| Run `mix ecto.gen.migration migration_name` to generate migrations | Never create migration files manually without the task |
| Remember Phoenix router scope alias when creating routes | Not applicable — no web routes in Phase 1 |
| Predicate functions must not start with `is_` (use `?` suffix) | Applies to any boolean helper functions in Accounts context |
