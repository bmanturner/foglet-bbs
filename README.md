# Foglet BBS

[![CI](https://github.com/bmanturner/foglet-bbs/actions/workflows/ci.yml/badge.svg)](https://github.com/bmanturner/foglet-bbs/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE.md)
[![Elixir](https://img.shields.io/badge/elixir-1.19.5--otp--28-purple.svg)](.tool-versions)
[![Erlang/OTP](https://img.shields.io/badge/erlang%2Fotp-28.3.1-red.svg)](.tool-versions)
[![Status](https://img.shields.io/badge/status-public%20beta-orange.svg)](README.md)

Foglet is a small, self-hostable bulletin board system for people who still like the feeling of dialing into a place.

The main door is SSH. The interface is a terminal UI. Phoenix is present, but the web surface is a lobby, docs shelf, and operational shell — not a browser forum.

Try the public beta:

```bash
ssh bbs.foglet.io
```

Source: <https://github.com/bmanturner/foglet-bbs>

## What Foglet is

Foglet is an SSH-first BBS built with Elixir/OTP, Phoenix, Postgres, and a modern terminal UI. It is meant to feel old-network without pretending to be old software: small communities, named boards, readable threads, a sysop in charge, and enough modern plumbing to keep the place reliable.

## What exists today

Current Foglet builds include:

- SSH-served terminal UI with account registration, login, verification, password reset, and account management flows.
- Password authentication and SSH public-key authentication.
- In-TUI SSH key management, including adding and removing public keys from an account.
- Boards, threads, posts, replies, edits, soft deletion, read pointers, board subscriptions, and per-board message numbering.
- Board-scoped chat rooms where the sysop enables them, with ephemeral or permanent storage backends.
- Board news/feed surfaces backed by sysop-managed RSS or Atom sources.
- BBS Mail for direct user-to-user messages, including hide/report actions.
- Door games through native Elixir, external PTY, and classic dropfile manifests.
- Oneliners for short public notes.
- Moderation and sysop workflows for users, boards, configuration, subscriptions, invites, verification, reset tokens, identity policy, SSH IP access rules, and oneliners where implemented.
- One active session per user: a new login promotes the new connection and closes the older session.
- Phoenix endpoint, health check, docs, LiveDashboard in development, PubSub, telemetry, mail plumbing, and other operational infrastructure.

The web page is intentionally just a lobby/window into the SSH BBS plus public documentation. It is not an end-user web client.

## Quick paths

### Look around

Use a normal SSH client:

```bash
ssh bbs.foglet.io
```

For local development, start the app and connect to the development SSH port:

```bash
ssh localhost -p 2222
```

Foglet also supports SSH public-key login after an account has a public key on file. Your ssh-agent can knock on a bulletin board.

### Run it locally

The shortest development path is:

```bash
git clone git@github.com:bmanturner/foglet-bbs.git
cd foglet-bbs
docker compose up -d postgres
mix setup
mix phx.server
```

Then connect:

```bash
ssh localhost -p 2222
```

The repo's `.tool-versions` file is the source of truth for Elixir and Erlang/OTP versions. `mix setup` installs dependencies, prepares the database, runs seeds, and configures the project's git hooks path.

If you already run Postgres locally, or if port `5432` is occupied, use the full setup docs instead of guessing at environment variables.

## Read more

Foglet serves public docs at `/docs` when the Phoenix endpoint is running. These pages are generated from `priv/docs/**`.

Start here:

- [`/docs/start-here/overview`](priv/docs/start-here/overview.md) — what Foglet is and whether you are in the right place.
- [`/docs/start-here/requirements`](priv/docs/start-here/requirements.md) — required tools, services, and terminal basics.
- [`/docs/start-here/quickstart`](priv/docs/start-here/quickstart.md) — fastest useful path from clone to SSH login.

Install and connect:

- [`/docs/installation/manual-setup`](priv/docs/installation/manual-setup.md) — manual local setup.
- [`/docs/installation/connect-over-ssh`](priv/docs/installation/connect-over-ssh.md) — SSH connection and authentication notes.
- [`/docs/configuration/environment`](priv/docs/configuration/environment.md) — environment variables and runtime configuration.

Operate the BBS:

- [`/docs/operations/mix-tasks`](priv/docs/operations/mix-tasks.md) — operator and break-glass Mix tasks.
- [`/docs/operations/health-and-logs`](priv/docs/operations/health-and-logs.md) — health checks and logs.
- [`/docs/operations/troubleshooting`](priv/docs/operations/troubleshooting.md) — common recovery paths.

Understand or contribute:

- [`/docs/concepts/architecture`](priv/docs/concepts/architecture.md) — OTP, Phoenix, SSH, TUI, and persistence boundaries.
- [`/docs/concepts/data-model`](priv/docs/concepts/data-model.md) — durable state and message-number invariants.
- [`/docs/advanced/development`](priv/docs/advanced/development.md) — development workflow.
- [`docs/VOICE_AND_TONE.md`](docs/VOICE_AND_TONE.md) — Foglet's product voice and copy checklist.

## Operator notes

Foglet's detailed operator guidance lives in the docs linked above. Keep secrets in environment/runtime configuration, not DB-backed runtime config.

Useful task families live under `lib/mix/tasks/` and are documented in the Mix tasks page. Examples include user creation and status changes, invite creation and inspection, verification-code inspection, reset-token inspection and expiry, board subscription management, board-chat inspection, identity policy rules, SSH IP access rules, TUI rendering, QA mode, and `foglet.doctor`.

## Repository layout

- `lib/foglet_bbs/` — `Foglet.*` domain code and `FogletBbs.*` Phoenix infrastructure. The boundary is by module name, not by path.
- `lib/foglet_bbs_web/` — `FogletBbsWeb.*` endpoint, router, controllers, telemetry, and web views.
- `lib/mix/tasks/` — operator and break-glass Mix tasks.
- `priv/docs/` — public docs served from `/docs`.
- `docs/` — project and contributor documentation.
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

For deeper context on namespaces, persistence invariants, authorization scopes, SSH/TUI ownership, and workflow conventions, read [`priv/docs/advanced/development.md`](priv/docs/advanced/development.md) and `docs/DEVELOPMENT.md` before non-trivial changes.

## License

Copyright 2026 Brendan Turner

Licensed under the Apache License, Version 2.0. See `LICENSE.md` for details.
