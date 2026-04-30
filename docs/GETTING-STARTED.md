<!-- generated-by: gsd-doc-writer -->
# Getting Started

This guide gets a new contributor or operator from a fresh clone to a working
local Foglet BBS — running the app and connecting to it over SSH — in roughly
ten minutes.

For deeper development workflow, see [DEVELOPMENT.md](DEVELOPMENT.md). For
runtime configuration knobs and environment variables, see
[CONFIGURATION.md](CONFIGURATION.md).

## Prerequisites

Foglet BBS is an SSH-first BBS built on Elixir/Phoenix with a Raxol terminal
UI and a Postgres datastore. You will need:

| Tool | Version | Notes |
|------|---------|-------|
| Elixir | `1.19.5-otp-28` | Pinned in `.tool-versions`. `mix.exs` requires `~> 1.17`, but `.tool-versions` is the source of truth. |
| Erlang/OTP | `28.3.1` | Pinned in `.tool-versions`. |
| PostgreSQL | running locally or via Docker Compose | Default credentials in `config/dev.exs` are `postgres`/`postgres` on `localhost`, database `foglet_bbs_dev`. The included `docker-compose.yml` starts a matching Postgres 16 service. |
| SSH client | any modern OpenSSH | Used to connect to the BBS once it is running. |

If you use `asdf` (or another `.tool-versions`-aware version manager), running
`asdf install` from the repo root will install the pinned Elixir and Erlang
versions.

## 1. Clone and choose a database

```bash
git clone <your-fork-or-origin-url> foglet_bbs
cd foglet_bbs
```

If you already have a local Postgres that matches `config/dev.exs`, run the
setup alias now:

```bash
mix setup
```

If you want the repository-managed Postgres instance instead, start it before
running setup:

```bash
docker compose up -d postgres
mix setup
```

By default Compose publishes Postgres on `localhost:5432`, matching
`config/dev.exs`. If that port is already occupied, choose another host port
and point Ecto at it:

```bash
POSTGRES_PORT=55432 docker compose up -d postgres
DATABASE_URL=ecto://postgres:postgres@localhost:55432/foglet_bbs_dev mix setup
```

The `setup` alias defined in `mix.exs` runs:

1. `mix deps.get` — fetch Hex and path-based dependencies (Raxol is vendored
   under `vendor/raxol`).
2. `mix ecto.setup` — create the database, run migrations, and seed.
3. `cmd git config core.hooksPath .githooks` — wire up the repo's git hooks.

If you prefer to run the database steps explicitly (or need to re-seed), use
the `ecto.setup` alias on its own:

```bash
mix ecto.setup
```

That alias chains `ecto.create`, `ecto.migrate`, and `run priv/repo/seeds.exs`.

### What the seeds create

`priv/repo/seeds.exs` is idempotent and safe to re-run. On first run it
inserts:

- A **tombstone user** (`[deleted]`) used as the post-anonymization target
  when accounts are deleted.
- **Default configuration entries** (delegated to `priv/repo/seeds/config.exs`).
- A **`General` category** and a default **`general` board** marked as
  `default_subscription: true` so new users are auto-subscribed.
- Two seed users for development:
  - `sysop` — promoted to the `:sysop` role and confirmed.
  - `foglet` — a regular member, confirmed.
- A few sample threads and posts in the `general` board (a sticky welcome
  thread, "Introduce Yourself", and "General Chat") so the TUI has content
  to navigate on first run.

> The seed users share the password `seedpassword123!`. This is a well-known
> dev fixture — never run `mix run priv/repo/seeds.exs` against a production
> database.

### Optional: verify the environment

A `mix foglet.doctor` task is available to confirm Elixir/Erlang versions,
Postgres reachability, the `citext` extension, the SSH host key, and required
environment variables:

```bash
mix foglet.doctor
```

## 2. Run the application

Start the Phoenix endpoint and the SSH daemon together:

```bash
mix phx.server
```

Or, with an interactive shell attached:

```bash
iex -S mix phx.server
```

Two listeners come up:

- **Phoenix endpoint** on `http://localhost:4000` — serves LiveDashboard,
  PubSub, and infrastructure endpoints. The browser surface is intentionally
  minimal; the product is the SSH TUI.
- **SSH daemon** on port **`2222`** — the primary product surface. The port
  is set in `config/config.exs` (`config :foglet_bbs, :ssh_port, 2222`) and
  can be overridden at runtime via `FOGLET_SSH_PORT`. The daemon is gated by
  `config :foglet_bbs, :start_ssh_daemon, true`.

## 3. Connect via SSH

Use any SSH client to connect to the running daemon. The handle you supply as
the SSH user is the BBS handle.

```bash
ssh -p 2222 sysop@localhost
```

Two flows are possible on first connect, owned by
`Foglet.SSH.CLIHandler`:

- **Public-key authentication.** If the offered public key matches a
  registered `Foglet.Accounts.SSHKey` row (via
  `Accounts.authenticate_by_public_key/1`), the session starts as that user.
- **No matching key (guest).** The connection is accepted and a session is
  started without an associated user. The TUI's login/register screens
  (`lib/foglet_bbs/tui/screens/login.ex` and `register.ex`) let the visitor
  authenticate with handle + password or create a new account.

Sign in as `sysop` with the seed password `seedpassword123!` to land on a
fully-configured account, or as `foglet` for a regular-member view.

> Host key trust: the first connection prompts your SSH client to accept the
> server's host key, which lives under `priv/ssh` (configurable via
> `SSH_HOST_KEY_DIR`). This is normal — accept it once and your client will
> remember it.

## 4. Create or promote your own account

Two Mix tasks back the operator account-management workflow.

### Create a user

`mix foglet.user.create` (see `lib/mix/tasks/foglet.user.create.ex`) creates
an auto-confirmed account. All three flags are required:

```bash
mix foglet.user.create \
  --handle bman \
  --email bman@example.com \
  --password 'a-strong-password'
```

### Assign a role

`mix foglet.user.promote` (see `lib/mix/tasks/foglet.user.promote.ex`) sets
the role on an existing user. Valid roles are `user`, `mod`, and `sysop`.
The handle is positional; the role is a flag:

```bash
mix foglet.user.promote bman --role sysop
```

A few related helpers also live in `lib/mix/tasks/` for operator and QA
break-glass workflows:

- `mix foglet.user.status` — change a user's account status.
- `mix foglet.users.approve` / `mix foglet.users.reject` — approve or reject a pending user.
- `mix foglet.user.reset_password` — issue an operator-assisted reset token.
- `mix foglet.reset_token.inspect` — issue a fresh no-email reset token for QA inspection.
- `mix foglet.reset_token.expire` — force the latest reset token outside its validity window.
- `mix foglet.user.verification_code` — issue a no-email verification code.
- `mix foglet.verification.inspect` — inspect the latest unexpired no-email verification code.
- `mix foglet.invites.create` / `list` / `inspect` / `revoke` — manage invite codes.
- `mix foglet.qa.mode` — set registration, verification, and delivery-mode config for QA matrix runs.
- `mix foglet.board_subscriptions` — operator-side subscription management.

Run any task with no arguments for its usage banner.

## 5. A brief TUI tour

Once you are logged in over SSH you will land on the Main Menu. The keybinds
shown in the seeded welcome thread cover the core flow:

- **`B`** — Browse boards. Select the `General` board to see the seeded
  threads.
- **Enter** on a thread — Open the thread reader (post-by-post navigation
  with stable per-board message numbers).
- **`R`** while reading — Compose a reply.
- **`C`** from a board view — Start a new thread.

Screen modules under `lib/foglet_bbs/tui/screens/` (e.g. `main_menu.ex`,
`board_list.ex`, `thread_list.ex`, `post_reader.ex`, `post_composer.ex`,
`new_thread.ex`, `account.ex`, `sysop.ex`) own screen-local rendering and
key handling. Global navigation lives in `Foglet.TUI.App`.

## Common setup issues

| Symptom | Likely cause and fix |
|---------|----------------------|
| `mix setup` fails on `ecto.create` with a connection error | Postgres is not running or credentials in `config/dev.exs` (`postgres`/`postgres` on `localhost`) do not match your local Postgres. Start Postgres with `docker compose up -d postgres`, or set `DATABASE_URL` to your running database. |
| `docker compose up -d postgres` fails because port `5432` is allocated | Another local database is already using the default port. Start this project's database on another host port, for example `POSTGRES_PORT=55432 docker compose up -d postgres`, then run Mix commands with `DATABASE_URL=ecto://postgres:postgres@localhost:55432/foglet_bbs_dev`. |
| `citext extension` check fails in `mix foglet.doctor` | Connect to your Postgres as a superuser and run `CREATE EXTENSION IF NOT EXISTS citext;` against the `foglet_bbs_dev` database. |
| `ssh -p 2222 ...` hangs or refuses the connection | The SSH daemon did not start. Confirm `mix phx.server` is running, that `config :foglet_bbs, :start_ssh_daemon, true` has not been overridden, and that nothing else is bound to port `2222` (override with `FOGLET_SSH_PORT=2200`). |
| Compiler complains about Elixir/Erlang versions | Your runtime does not match `.tool-versions` (Elixir `1.19.5-otp-28`, Erlang `28.3.1`). Install the pinned versions via `asdf install` or your version manager of choice. |
| Seeds skip threads with "general board not found" | The Phase-2 seed (default board) failed earlier in the run. Re-run `mix ecto.reset` to drop and rebuild from scratch. |

## Next steps

- **[DEVELOPMENT.md](DEVELOPMENT.md)** — day-to-day development workflow,
  test commands, and the `mix precommit` checklist.
- **[CONFIGURATION.md](CONFIGURATION.md)** — runtime configuration via
  `Foglet.Config`, environment variables, and per-environment overrides.
- **[ARCHITECTURE.md](ARCHITECTURE.md)** — system overview, contexts, and
  the SSH/TUI/Phoenix boundaries.
