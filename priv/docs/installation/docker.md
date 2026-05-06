%{
  title: "Docker",
  weight: 20
}
---

This page covers the Docker shape that exists in the repository: a production
OTP release image plus a local Postgres Compose service. Foglet does not yet
ship a full production `docker compose up` stack for app plus database.

## What the image contains

`Dockerfile` builds a Debian-based Elixir release:

- builder image: `hexpm/elixir` with Elixir `1.19.5` and OTP `28.1.1` build
  arguments by default.
- runner image: Debian `trixie` slim.
- runtime user: `nobody`.
- release command: `/app/bin/server`.
- exposed ports: `2222` for SSH and `4000` for HTTP.
- persistent volume: `/data`.

The image also installs runtime tools needed by current features, including
OpenSSH client utilities, Python 3, curl, unzip, and libraries required by the
release. Door-game support uses `/data/door-manifests` for operator-managed
manifests and `/data/usurper` for the bundled Usurper Reborn data directory.

## Build the image

From the repository root:

```bash
docker build -t foglet-bbs:local .
```

The build downloads the public Usurper Reborn Linux x64 release and verifies it
against the SHA256 pinned in `Dockerfile`. If that upstream download is
unavailable, the image build fails before producing a runner image.

## Required runtime environment

A production container must receive at least:

| Variable | Required | Purpose |
| --- | --- | --- |
| `DATABASE_URL` | yes | Ecto connection string for Postgres. |
| `SECRET_KEY_BASE` | yes | Phoenix secret used for signing and encryption. |
| `PHX_HOST` | recommended | Public HTTP host used by the endpoint URL config. Defaults to `example.com` if omitted. |
| `PORT` | optional | HTTP listen port. Defaults to `4000`. |
| `FOGLET_SSH_PORT` | optional | SSH listen port. Defaults to `2222`. |
| `SSH_HOST_KEY_DIR` | recommended | Directory containing persistent SSH host keys. Use `/data/ssh` in the release image. |
| `FOGLET_DEFAULT_TIMEZONE` | optional | IANA timezone for new users and guest sessions. |
| `FOGLET_GUEST_MODE_ENABLED` | optional | `true`, `false`, `1`, or `0`. Invalid values stop startup. |

Generate `SECRET_KEY_BASE` outside the container or with a temporary local Mix
environment:

```bash
mix phx.gen.secret
```

Do not commit the generated value.

## Persistent paths

Mount `/data` on durable storage:

```bash
-v foglet-data:/data
```

That path is used for:

- `/data/ssh` — SSH host keys when `SSH_HOST_KEY_DIR=/data/ssh`.
- `/data/.config` — runtime home/config data for the non-root release user.
- `/data/door-manifests` — door-game manifest JSON files.
- `/data/usurper` — bundled Usurper Reborn SQLite/runtime data.

The database is not stored in the Foglet container. Run Postgres separately and
point `DATABASE_URL` at it.

## Run migrations

The image includes a release helper script:

```bash
docker run --rm \
  --env DATABASE_URL='ecto://USER:PASS@HOST/DB' \
  --env SECRET_KEY_BASE='replace-me' \
  --env SSH_HOST_KEY_DIR='/data/ssh' \
  -v foglet-data:/data \
  foglet-bbs:local \
  /app/bin/migrate
```

`/app/bin/migrate` calls `FogletBbs.Release.migrate/0`, which runs database
migrations and the production config seed files. It does not run the development
seed file with sample users or QA fixtures.

## Run the server

```bash
docker run --rm \
  --env DATABASE_URL='ecto://USER:PASS@HOST/DB' \
  --env SECRET_KEY_BASE='replace-me' \
  --env PHX_HOST='bbs.example.net' \
  --env PORT='4000' \
  --env FOGLET_SSH_PORT='2222' \
  --env SSH_HOST_KEY_DIR='/data/ssh' \
  -p 4000:4000 \
  -p 2222:2222 \
  -v foglet-data:/data \
  foglet-bbs:local
```

Then check:

```bash
curl -fsS http://localhost:4000/up
ssh localhost -p 2222
```

If you expose SSH on public port `22`, map the host port explicitly:

```bash
-p 22:2222
```

That bind usually requires root privileges or host-level port-forwarding.

## Local Postgres Compose service

The repository's Compose file is only a local Postgres convenience:

```bash
docker compose -f docker-compose.yml up -d postgres
```

It starts `postgres:16` with development credentials. It does not start Foglet.
Use it for local source setup, not as a production deployment recipe.

## Caveats

- Keep `/data/ssh` stable across deploys. Losing it changes the SSH server
  identity and makes users re-trust the host.
- Keep database backups separate from the Foglet container volume.
- The release runs as `nobody`; mounted paths must be writable by that user.
- The bundled door-game manifest catalog is operator-facing configuration. Only
  mount manifests you have reviewed.
