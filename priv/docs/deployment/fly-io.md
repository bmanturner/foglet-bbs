%{
  title: "Fly.io",
  weight: 20
}
---

Foglet ships with a committed Fly.io deployment shape in `fly.toml`. It builds
the Docker release image, runs the Phoenix endpoint on internal port `4000`, and
runs the SSH daemon on internal port `2222` exposed publicly as port `22`.

Use this page as a starting point, then replace the sample app name, region, and
host with your own. Do not publish a public instance with the repository's
example host, app name, or development SSH host key.

## What the committed Fly config does

`fly.toml` currently defines:

- app name: `foglet-bbs`
- primary region: `iad`
- persistent volume: `foglet_data` mounted at `/data`
- HTTP service: internal port `4000`, forced HTTPS, health check `GET /up`
- SSH service: internal port `2222`, public port `22`, one machine kept running
- deploy release command: `/app/bin/foglet_bbs eval FogletBbs.Release.seed`
- SSH host key directory: `/data/ssh`
- Fly IPv6 database sockets: `ECTO_IPV6=true`

The GitHub Actions workflow `.github/workflows/fly-deploy.yml` deploys when the
`prod` branch is pushed:

```sh
flyctl deploy --remote-only --app foglet-bbs
```

It expects `FLY_API_TOKEN` to live in GitHub Actions secrets.

## One-time setup

Run these from an operator workstation with `flyctl` installed. Adjust names,
region, and host before running them.

```sh
fly auth login
fly launch --no-deploy --name foglet-bbs --region iad
fly volumes create foglet_data --size 1 --region iad --app foglet-bbs
fly postgres create --name foglet-bbs-db --region iad --initial-cluster-size 1 --volume-size 2
fly postgres attach foglet-bbs-db --app foglet-bbs --database-name foglet_bbs --database-user foglet_bbs
fly ips allocate-v4 --app foglet-bbs
fly secrets set SECRET_KEY_BASE="$(mix phx.gen.secret)" --app foglet-bbs
fly certs add bbs.example.net --app foglet-bbs
fly deploy --app foglet-bbs
```

`fly postgres attach` creates the app database/user and sets the app's
`DATABASE_URL` secret. You do not need to set `DATABASE_URL` manually unless you
use a database that was not attached this way.

After adding the certificate, point DNS at the records shown by:

```sh
fly certs show bbs.example.net --app foglet-bbs
```

## Required edits before public use

Change these in `fly.toml` or Fly configuration:

- `app` to your Fly app name.
- `PHX_HOST` to your public hostname.
- `FOGLET_MAIL_FROM` to a real sender address for your domain.
- `FOGLET_DEFAULT_TIMEZONE` if the site default should not be `America/Chicago`.
- `FOGLET_ENABLE_DEMO_DOORS` to `false` or remove it unless you intentionally
  want demo doors available on that instance.

Keep `SSH_HOST_KEY_DIR=/data/ssh` or another path on a persistent volume. If Fly
starts a replacement machine without the same host key material, callers will
see a changed SSH server fingerprint.

## Deploy behavior

Fly runs this before the new release accepts traffic:

```sh
/app/bin/foglet_bbs eval FogletBbs.Release.seed
```

That helper runs migrations and the production-safe seed files in
`lib/foglet_bbs/release.ex`. It does not run the full demo seed file.

To run a release-safe command inside the deployed app:

```sh
fly ssh console --app foglet-bbs -C '/app/bin/foglet_bbs eval "FogletBbs.Repo.query!(\"select 1\")"'
```

For local `mix` tasks pointed at Fly Postgres, open a proxy first and pass a
local `DATABASE_URL` for that command. Do not paste the real password into issue
comments or shared logs.

```sh
fly proxy 15432:5432 --app foglet-bbs-db
DATABASE_URL="postgres://foglet_bbs:<password>@localhost:15432/foglet_bbs?sslmode=disable" MIX_ENV=prod mix ecto.migrate
```

Prefer release commands inside Fly for production-safe operations. Local `mix`
commands use your workstation's source tree and toolchain, which may not match
the deployed image.

## Smoke checks

After deploy:

```sh
curl -fsS https://bbs.example.net/up
ssh -p 22 bbs.example.net
fly logs --app foglet-bbs
```

Confirm the HTTP health route succeeds, SSH reaches the Foglet welcome/login
flow, and logs do not show repeated Repo or supervisor failures.

## Rollback and recovery

List Fly releases:

```sh
fly releases --app foglet-bbs
```

Application rollback should use the team-approved Fly rollback path for your
app, such as redeploying a previous image reference or updating a machine to a
known-good image. Pair app rollback with schema expectations: if the old release
cannot run on the new schema, verify a backup and use
`FogletBbs.Release.rollback(FogletBbs.Repo, version)` deliberately.

Back up the Fly Postgres database and `/data/ssh` host-key directory out of band.
Losing the host key is a caller-visible trust event, not a normal deploy detail.

## Fly caveats

- Fly volumes are per-machine and region-local. If you scale beyond one
  SSH-serving machine, deliberately copy/share host keys or plan a visible
  fingerprint rotation.
- The HTTP service may auto-stop; the SSH TCP service is configured to keep one
  machine running.
- DNS clustering is wired through release env, but multi-node SSH behavior is
  not a public v1 promise.
- The Docker/Fly image runs as `nobody`. It does not currently provide the full
  restricted-user sandbox baseline for untrusted external Door Games.
