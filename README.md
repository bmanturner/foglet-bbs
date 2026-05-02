# Foglet BBS

Foglet is a small, self-hostable bulletin board system for people who still like the feeling of dialing into a place.

The main door is SSH. The interface is a terminal UI. Phoenix is present, but the web surface is a lobby and operational shell, not a browser forum.

Try the public pre-alpha:

```bash
ssh bbs.foglet.io
```

Source: https://github.com/bmanturner/foglet-bbs

## What Foglet is

Foglet is an SSH-first BBS built with Elixir/OTP, Phoenix, Postgres, and a modern terminal UI. It is meant to feel old-network without pretending to be old software: small communities, named boards, readable threads, a sysop in charge, and enough modern plumbing to keep the place reliable.

Foglet is not trying to be Discord, a social network, a web forum, or a hosted SaaS product. You run it yourself. Your users connect over SSH. The BBS lives in the terminal.

## What exists today

Current Foglet builds include:

- SSH-served terminal UI with account registration, login, verification, password reset, and account management flows.
- Password authentication and SSH public-key authentication.
- In-TUI SSH key management, including adding and removing public keys from an account.
- Boards, threads, posts, replies, edits, soft deletion, read pointers, board subscriptions, and per-board message numbering.
- Oneliners for short public notes.
- Moderation/sysop workflows for account, board, configuration, and oneliner administration where implemented.
- One active session per user: a new login promotes the new connection and closes the older session.
- Phoenix endpoint, health check, LiveDashboard, PubSub, telemetry, mail plumbing, and other operational infrastructure.

The web page is intentionally just a lobby/window into the SSH BBS. It is not an end-user web client.

## SSH public-key login

Foglet treats SSH keys as a first-class way to enter the BBS.

After an account has a public key on file, a user can connect with a normal SSH client and authenticate by key instead of typing a password every time. The key stays on the user's machine; Foglet stores the public half and checks it during SSH authentication.

That gives the project one of its signature textures: your ssh-agent can knock on a bulletin board.

Local development connection example:

```bash
ssh USERNAME@localhost -p 2222
```

Public pre-alpha connection:

```bash
ssh bbs.foglet.io
```

## Run Foglet locally

### Requirements

The repo's `.tool-versions` file is the source of truth for local language versions. At the time of this writing it specifies:

- Elixir `1.19.5-otp-28`
- Erlang/OTP `28.3.1`

You will also need:

- PostgreSQL, or Docker Compose for the included Postgres service.
- A standard SSH client.

### Clone

```bash
git clone git@github.com:bmanturner/foglet-bbs.git
cd foglet-bbs
```

### Set up the database

If you already have a local Postgres that matches `config/dev.exs`:

```bash
mix setup
```

To use the included Docker-backed Postgres instead:

```bash
docker compose up -d postgres
mix setup
```

If host port `5432` is already in use, set `POSTGRES_PORT` for Compose and `DATABASE_URL` for Mix:

```bash
POSTGRES_PORT=55432 docker compose up -d postgres
DATABASE_URL=ecto://postgres:postgres@localhost:55432/foglet_bbs_dev mix setup
```

`mix setup` gets dependencies, creates and migrates the database, runs seeds, and configures the project's git hooks path.

### Start the app

```bash
mix phx.server
```

Phoenix and the SSH daemon start under the OTP supervision tree. The default SSH port is `2222`; override it with `FOGLET_SSH_PORT`.

Then connect:

```bash
ssh USERNAME@localhost -p 2222
```

## Operator notes

Foglet stores the active delivery mode in runtime configuration as `delivery_mode`.

Email mode (`delivery_mode=email`) may send registration verification, password reset, and account-status notices through the configured mail adapter. SMTP host, port, username, password, and adapter settings belong in environment/runtime config, not in DB-backed runtime config.

No-email mode (`delivery_mode=no_email`) sends no outbound email. Operators retrieve reset tokens or verification codes through break-glass Mix tasks and communicate them out-of-band.

Useful operator tasks include:

```bash
mix foglet.user.reset_password HANDLE
mix foglet.user.verification_code HANDLE
mix foglet.user.status HANDLE --actor SYSOP --status active
mix foglet.board_subscriptions list --user HANDLE
```

More tasks live in `lib/mix/tasks/`, including `foglet.user.create`, `foglet.user.promote`, and `foglet.doctor`.

## What is intentionally not present yet

Do not operate Foglet as though these exist today:

- No end-user web forum UI.
- No browser admin console.
- No hosted service or managed Foglet cloud.
- No federation.
- No mobile app.
- No direct messages or private mail system.
- No @mention notification system.
- No email digests.
- No webhook notifications.
- No full case-management moderation suite.
- No delivery retry queues or outbound delivery logs.

## Repository layout

- `lib/foglet_bbs/` — `Foglet.*` domain code and `FogletBbs.*` Phoenix infrastructure. The boundary is by module name, not by path.
- `lib/foglet_bbs_web/` — `FogletBbsWeb.*` endpoint, router, controllers, telemetry, and web views.
- `lib/mix/tasks/` — operator and break-glass Mix tasks.
- `docs/` — project documentation, including `docs/ARCHITECTURE.md`, `docs/DATA_MODEL.md`, and `docs/DEVELOPMENT.md`.
- `docs/raxol/` — vendored Raxol documentation.
- `vendor/raxol/` — vendored Raxol TUI library source.

## Development

Run the full project finish line with:

```bash
mix precommit
```

`precommit` runs compile with warnings as errors, formatter, unused dependency checks, Credo, Sobelow, and Dialyzer.

Run the test suite with:

```bash
mix test
```

For deeper context on namespaces, persistence invariants, authorization scopes, SSH/TUI ownership, and workflow conventions, read `docs/DEVELOPMENT.md` before non-trivial changes.

## License

Copyright 2026 Brendan Turner

Licensed under the Apache License, Version 2.0. See `LICENSE` for details.
