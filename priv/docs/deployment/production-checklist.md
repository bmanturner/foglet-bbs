%{
  title: "Production checklist",
  weight: 10
}
---

Use this checklist before you put a Foglet BBS instance on the public network.
Foglet runs one OTP release with two listeners: SSH for callers and Phoenix for
health, docs, and supporting infrastructure. Postgres is durable state; ETS and
processes are rebuilt at boot.

The commands below are examples for operators. Run them from your own release or
platform shell, and keep secret values out of shell history, tickets, and logs.

## Required runtime configuration

Production boot fails unless these are present:

- `DATABASE_URL` points at a Postgres database.
- `SECRET_KEY_BASE` is set to a generated Phoenix secret.

Set these for any real public instance:

- `PHX_HOST` is the public HTTP hostname. The fallback is `example.com`; do not
  rely on it.
- `PHX_SERVER=true` when starting an OTP release through `bin/foglet_bbs start`.
  The checked-in release `bin/server` wrapper sets it for you.
- `PORT` is the Phoenix HTTP port. The default is `4000`.
- `FOGLET_SSH_PORT` is the internal SSH daemon port. The Docker image exposes
  `2222`; Fly maps public port `22` to internal `2222`.
- `SSH_HOST_KEY_DIR` points at persistent storage. Fly sets this to `/data/ssh`.

Generate `SECRET_KEY_BASE` with:

```sh
mix phx.gen.secret
```

Do not store secret values in the database-backed configuration table. That
surface is for live site policy, not credentials.

## Persistent storage

Back up these before you accept callers:

- Postgres database. This holds users, roles, boards, threads, posts, read
  pointers, invites, tokens, and DB-backed runtime configuration.
- SSH host keys in `SSH_HOST_KEY_DIR`. Losing or rotating these keys changes the
  server fingerprint every caller has trusted.
- Platform secret store values such as `DATABASE_URL`, `SECRET_KEY_BASE`, and
  SMTP credentials.
- `/data` when you rely on files there for host keys, door manifests, or door
  state.

The repository contains a development host key under `priv/ssh`. Do not use it
as a public production identity.

## Database and release seed

The release helper in `FogletBbs.Release` is the production-safe path:

```sh
/app/bin/foglet_bbs eval FogletBbs.Release.migrate
/app/bin/foglet_bbs eval FogletBbs.Release.seed
```

`seed/0` runs all migrations and then the production-safe seed files listed in
`lib/foglet_bbs/release.ex`: configuration defaults and the tombstone user.

Do not run `priv/repo/seeds.exs` against a real production database. That file is
for local/demo setup and creates known test accounts and sample content.

## Network checks

Open the listeners your deployment actually exposes:

- SSH: public port `22` on Fly, or your chosen forwarded port elsewhere.
- HTTP: the Phoenix endpoint port behind TLS or a reverse proxy. The app defaults
  to internal port `4000`.

Smoke check both surfaces after deploy:

```sh
curl -fsS https://bbs.example.net/up
ssh -p 22 bbs.example.net
```

The SSH path is the product. The Phoenix endpoint is not an end-user web BBS;
it serves docs, health, and supporting operational surfaces.

## Mail and account recovery

SMTP is optional, but password resets and verification mail need it. Set:

- `FOGLET_MAIL_FROM`
- `FOGLET_SMTP_RELAY` or `FOGLET_SMTP_HOST`
- `FOGLET_SMTP_PORT`
- `FOGLET_SMTP_USERNAME`
- `FOGLET_SMTP_PASSWORD`
- `FOGLET_SMTP_SSL`, `FOGLET_SMTP_TLS`, and `FOGLET_SMTP_AUTH` if your relay
  requires non-default transport settings

If you do not configure SMTP, document how sysops will handle account recovery
before you open registration.

## Health, logs, and rollback

Before promotion, confirm:

- `/up` responds through the public HTTP path.
- SSH accepts a connection and reaches the welcome/login flow.
- A sysop or approved test account can reach the board list.
- Logs show the Repo connected and no repeated supervisor restarts.
- You know the previous app image or release tarball.
- You have a restorable database backup before schema-changing deploys.

Prefer forward fixes for production data. If you must roll back a migration, run
`FogletBbs.Release.rollback(FogletBbs.Repo, version)` only after verifying the
running app version expects that older schema.

## Not production-ready by default

Treat these as explicit operator decisions, not defaults:

- Multi-node SSH serving. DNS clustering is wired, but per-board processes and
  SSH host-key sharing are not a public v1 scaling promise.
- External telemetry exporters. Metrics are defined; no Prometheus, StatsD,
  Sentry, or vendor reporter is configured by this repo.
- Untrusted Door Games in Docker/Fly. The image runs the release as `nobody` and
  does not provide a separate restricted runtime user for doors.
- `docker-compose.yml` as a production stack. It only starts local Postgres.
