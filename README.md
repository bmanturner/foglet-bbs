<!-- generated-by: gsd-doc-writer -->
# Foglet BBS

Foglet is an SSH-first bulletin board system built with Elixir, Phoenix,
Postgres, and a terminal UI served over SSH. Accounts, boards, threads, posts,
oneliners, subscriptions, moderation, and sysop workflows all live in the
terminal experience.

Phoenix is operational infrastructure for the endpoint, PubSub, telemetry,
LiveDashboard, mail delivery plumbing, and future structured clients. It is
not a user-facing browser workflow for v1.2 pre-alpha.

## Status

Foglet is **pre-alpha** software (v1.2). The current focus is gap closure:
making the offered SSH/TUI flows honest and operational before broader launch
work. Treat anything beyond what this README describes as design context
rather than supported product surface.

## Requirements

- Elixir `~> 1.17` and a matching Erlang/OTP release
- PostgreSQL (any currently supported major version)
- An SSH client for connecting to the running BBS

This repository uses [`rtk`](https://github.com/) as the local command prefix.
All examples below use `rtk` in front of `mix` and other dev tooling.

## Quick Start

Clone the repo, install dependencies, and create the database:

```bash
git clone <your-fork-or-remote-url> foglet_bbs
cd foglet_bbs
rtk mix setup
```

`mix setup` runs `deps.get`, `ecto.create`, `ecto.migrate`, `run priv/repo/seeds.exs`,
and configures the project's git hooks path.

Start the application:

```bash
rtk mix phx.server
```

Phoenix and the SSH daemon both come up under the OTP supervision tree. The
default SSH port is `2222` (override with the `FOGLET_SSH_PORT` environment
variable).

## Connecting

Connect with any standard SSH client:

```bash
ssh USERNAME@localhost -p 2222
```

Foglet supports both **SSH key** and **password** authentication. Users may
register and add SSH keys through the in-TUI account workflows. Once a key is
registered, subsequent sessions can authenticate without a password.

Only one active session per user is allowed; opening a second session will
promote the new connection and close the older one.

## Operator Notes

### Delivery Modes

Foglet stores the active delivery mode in runtime configuration as
`delivery_mode`.

**Email mode** (`delivery_mode=email`): registration verification, password
reset, and account-status notices may be delivered through the configured
mail adapter. SMTP host, port, username, password, and adapter settings
belong in environment/runtime config (`config/runtime.exs` or deployment
environment variables) and **not** in DB-backed runtime config.

**no-email mode** (`delivery_mode=no_email`): no outbound email is sent.
Operators retrieve reset tokens or verification codes through break-glass
Mix tasks and communicate them out-of-band.

### Break-Glass Mix Tasks

Run these from the application release or source checkout against the same
database and runtime environment as the running node:

```bash
rtk mix foglet.user.reset_password HANDLE
rtk mix foglet.user.verification_code HANDLE
rtk mix foglet.user.status HANDLE --actor SYSOP --status active
rtk mix foglet.board_subscriptions list --user HANDLE
```

- `foglet.user.reset_password HANDLE` — generates a raw reset token for
  operator-assisted SSH reset handling. Does not send email and does not
  produce a browser reset URL.
- `foglet.user.verification_code HANDLE` — generates a verification code for
  no-email operation. In email mode, prefer the normal Login or Verify
  resend flow.
- `foglet.user.status HANDLE --actor SYSOP --status STATUS` — changes user
  status through the same Accounts authorization boundary as TUI workflows.
  Valid statuses are `active`, `rejected`, and `suspended`.
- `foglet.board_subscriptions list --user HANDLE` — lists a user's board
  subscription directory. Also supports `subscribe` and `unsubscribe` actions
  with `--board BOARD_SLUG`. Required-subscription and archived-board rules
  still route through `Foglet.Boards`.

Additional operator tasks live in `lib/mix/tasks/`, including
`foglet.user.create`, `foglet.user.promote`, and `foglet.doctor`.

## Launch Caveats

The following are **not** v1.2 pre-alpha capabilities. Foglet should not be
operated as though they exist yet:

- No end-user web UI. Browser-facing Phoenix surfaces are operational
  infrastructure only.
- No browser admin console.
- No webhook notifications.
- No email digests.
- No delivery retry queues or outbound delivery logs.
- No full case-management moderation.

## Repository Layout

- `lib/foglet_bbs/` — `Foglet.*` domain code (Accounts, Boards, Threads, Posts,
  Sessions, SSH, TUI, Authorization, Config) plus `FogletBbs.*` Phoenix
  infrastructure (Application, Repo, Mailer, etc.). Both namespaces coexist in
  this directory; the boundary is by module name, not by path.
- `lib/foglet_bbs_web/` — `FogletBbsWeb.*` Phoenix endpoint, telemetry,
  LiveDashboard.
- `lib/mix/tasks/` — operator break-glass Mix tasks.
- `docs/` — project documentation. See
  [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) and
  [`docs/DATA_MODEL.md`](docs/DATA_MODEL.md).
- `docs/raxol/` — **vendored** Raxol library documentation. These are
  upstream library docs, not Foglet-specific content.
- `vendor/raxol/` — vendored Raxol TUI library source.
- `AGENTS.md` — agent/contributor context describing namespaces, boundaries,
  and workflow conventions.

## Development

The project finish line is:

```bash
rtk mix precommit
```

`precommit` runs `compile --warnings-as-errors`, `deps.unlock --unused`,
`format`, `credo --strict`, `sobelow --exit Low`, and `dialyzer`.

Run the test suite with:

```bash
rtk mix test
```

`mix test` ensures the test database is created and migrated, seeds runtime
config, and then runs the suite.

For deeper context on namespaces, persistence invariants, authorization
scopes, SSH/TUI ownership, and workflow conventions, read
[`AGENTS.md`](AGENTS.md) before non-trivial changes.

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
