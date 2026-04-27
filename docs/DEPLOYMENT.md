<!-- generated-by: gsd-doc-writer -->
# Deployment

Foglet BBS ships as a single OTP release containing both the Erlang `:ssh`
daemon (the primary product surface) and the Phoenix endpoint (operational
infrastructure: PubSub, telemetry, LiveDashboard). This guide covers the
verifiable build, release, and runtime mechanics in this repository. Anything
deployment-platform-specific beyond what is committed here is marked with a
`VERIFY` comment and should be confirmed against your operations runbook.

## Deployment Targets

The repository contains configuration for two deployment shapes:

- **Docker** — `Dockerfile` builds a Debian-based release image. Exposes
  ports `2222` (SSH) and `4000` (HTTP). Declares a `/data` volume for
  persistent state. `docker-compose.yml` is also present for local
  container runs.
- **Fly.io** — `fly.toml` defines an `iad`-region deployment of the
  `foglet-bbs` app, with a `foglet_data` volume mounted at `/data`,
  an HTTP service on internal port `4000` (force-HTTPS, health check
  on `/up`), and a TCP service on internal port `2222` exposed
  publicly on port `22`. CI deploys via
  `.github/workflows/fly-deploy.yml` on pushes to the `prod` branch
  using `flyctl deploy --remote-only --app foglet-bbs`.

Other targets (bare metal, Kubernetes, Render, etc.) are not configured in
this repo.

> The library at `vendor/raxol` ships its own deployment notes under
> `docs/raxol/cookbook/SSH_DEPLOYMENT.md` and
> `docs/raxol/deployment/FLY_IO.md`. Those are vendored library docs and
> are **not** the canonical deployment guide for Foglet BBS — prefer this
> document and `fly.toml`.

## Build Pipeline

### Release build

The OTP release is produced by `mix release`, invoked inside the
`Dockerfile` builder stage:

```dockerfile
ENV MIX_ENV="prod"
COPY rel rel
RUN mix release
```

Release configuration:

- `rel/env.sh.eex` exports Fly-aware env vars when `FLY_APP_NAME` is set
  (`DNS_CLUSTER_QUERY`, `RELEASE_NODE`, `ERL_AFLAGS=-proto_dist inet6_tcp`,
  `ECTO_IPV6=true`) and otherwise defaults `RELEASE_NODE` to
  `foglet_bbs@$(hostname)`.
- `rel/overlays/bin/` contains additional release scripts (e.g.
  `bin/server`, `bin/migrate` made executable by the Dockerfile).

Runtime image (`Dockerfile` final stage):

- Base: `debian:trixie-slim`
- Installed: `libstdc++6 openssl libncurses6 locales ca-certificates openssh-client`
- Locale: `en_US.UTF-8`
- User: `nobody`
- Volume: `/data` (mounted persistent storage)
- `CMD ["/app/bin/server"]`

### CI build / test

`.github/workflows/ci.yml` runs on every push and pull request against
ephemeral `postgres:16`. Steps: `mix deps.get`, `mix format --check-formatted`,
`mix compile --warnings-as-errors`, `mix credo --strict`, `mix hex.audit`,
`mix sobelow --exit Low`, `mix dialyzer`, `mix test`. The toolchain version
comes from `.tool-versions` (strict).

### Fly deploy pipeline

`.github/workflows/fly-deploy.yml`:

1. Trigger: push to the `prod` branch.
2. `actions/checkout@v4`.
3. `superfly/flyctl-actions/setup-flyctl@master`.
4. `flyctl deploy --remote-only --app foglet-bbs` with
   `FLY_API_TOKEN` from repository secrets.

### Release migrations and seed

`fly.toml`'s `[deploy] release_command` runs migrations and the production
config seed before the new release accepts traffic:

```text
/app/bin/foglet_bbs eval "
  Ecto.Migrator.with_repo(FogletBbs.Repo, fn repo ->
    Ecto.Migrator.run(repo, :up, all: true)
    priv = :foglet_bbs |> :code.priv_dir() |> List.to_string()
    Code.eval_file(Path.join(priv, \"repo/seeds/config.exs\"))
  end)
"
```

`lib/foglet_bbs/release.ex` exposes the equivalent helpers for direct use
in any deploy environment (Docker, bare metal, etc.):

| Function | Purpose |
| --- | --- |
| `FogletBbs.Release.migrate/0` | Runs `Ecto.Migrator` `up :all` for every configured repo. Ensures `:ssl` is started first. |
| `FogletBbs.Release.rollback/2` | Runs `Ecto.Migrator` `down to: version` for the given repo. |

> Do **not** run `priv/repo/seeds.exs` against a production database — it
> creates demo users with known passwords and sample content. Only
> `priv/repo/seeds/config.exs` is safe for production (and is what the Fly
> release command runs).

## Environment Setup

The full list of environment variables and config keys lives in
[`docs/CONFIGURATION.md`](./CONFIGURATION.md). Variables that **must** be
set for a production deployment to start:

- `DATABASE_URL` — required (`config/runtime.exs` raises if missing in
  `:prod`).
- `SECRET_KEY_BASE` — required (`config/runtime.exs` raises if missing in
  `:prod`). Generate with `mix phx.gen.secret`.
- `PHX_HOST` — externally-visible hostname for the Phoenix endpoint.
  Defaults to `example.com`; set this for any real deployment.
- `PHX_SERVER=true` — required to actually start the HTTP listener under
  releases.
- `PORT` — HTTP port (defaults to `4000`).
- `FOGLET_SSH_PORT` — SSH daemon port (defaults to `2222` in `fly.toml`).
- `SSH_HOST_KEY_DIR` — directory holding the SSH host key. Defaults to
  `priv/ssh` in `:prod` runtime config; **must** point at a persistent
  volume in production (see below).

Optional integrations (SMTP relay, DNS clustering) are described in
`docs/CONFIGURATION.md`.

### SSH host key persistence — critical

The Erlang SSH daemon presents a host key to clients on every connection.
If that key changes between deploys, every existing user gets the
"REMOTE HOST IDENTIFICATION HAS CHANGED" warning and is locked out until
they purge their `known_hosts` entry.

To prevent this:

- `priv/ssh/ssh_host_ed25519_key` is committed to this repo as the
  development host key. **Do not** ship that key as your production
  identity.
- In production, set `SSH_HOST_KEY_DIR` to a path on a persistent volume
  that survives redeploys. On Fly.io, `fly.toml` sets it to `/data/ssh`,
  and `/data` is backed by the `foglet_data` volume.
- Generate the production host key once, place it in
  `${SSH_HOST_KEY_DIR}` (e.g. `ssh_host_ed25519_key` and
  `ssh_host_ed25519_key.pub`), and back the directory up.

> Per the comment in `fly.toml`: Fly Volumes are per-Machine and
> region-local. If you scale beyond one SSH-serving Machine in a region,
> you must intentionally share/copy host keys across them so users see a
> single stable fingerprint. Multi-node SSH clustering is **not** a v1
> feature — see `docs/ARCHITECTURE.md`.

### Database

- Postgres is required; `FogletBbs.Repo` is the only configured Ecto repo.
- `POOL_SIZE` defaults to `10`.
- `ECTO_IPV6=true` switches `socket_options` to `[:inet6]` (set by
  `rel/env.sh.eex` automatically on Fly).
- TLS to the database is **commented out** in `config/runtime.exs`
  (`# ssl: true,`). Enable it explicitly if your provider requires SSL.
  <!-- VERIFY: whether production Postgres requires TLS in your environment -->

### Phoenix endpoint vs SSH

These are two distinct listeners running inside the same release:

| Listener | Default port | Purpose |
| --- | --- | --- |
| Erlang `:ssh` daemon (`Foglet.SSH.Supervisor`) | `2222` (or `FOGLET_SSH_PORT`) | Primary product — Raxol TUI sessions. |
| Phoenix endpoint (`FogletBbsWeb.Endpoint` via Bandit) | `4000` (or `PORT`) | Operational infra: PubSub, channels, LiveDashboard, health (`/up`). **Not** an end-user web UI. |

Phoenix's `:url` is configured for `port: 443, scheme: "https"` in prod;
TLS termination happens in front of the app (Fly's `force_https = true`
HTTP service does this on Fly).
<!-- VERIFY: TLS termination strategy for non-Fly deployments — typically a load balancer or reverse proxy in front of port 4000 -->

LiveDashboard is gated by the sysop role (see `docs/ARCHITECTURE.md`); do
not assume the endpoint is unauthenticated just because there is no
end-user web UI.

## Telemetry & Monitoring

Wired up in this repo (`lib/foglet_bbs_web/telemetry.ex`):

- `:telemetry_poller` runs periodic measurements every 10s.
- Metric definitions exist for Phoenix endpoint/router/socket/channel
  events, Ecto repo query timings, and BEAM VM (memory, run queues).
- **No reporter is attached.** The metrics are defined but not exported
  to any backend — `Telemetry.Metrics.ConsoleReporter` is commented out,
  and there is no Prometheus, StatsD, or vendor reporter configured.

There is **no Sentry / error-tracking dependency** in `mix.exs` and no
`Sentry` references in `lib/` or `config/`. `docs/ARCHITECTURE.md` mentions
Sentry as optional; nothing is wired up today.

LiveDashboard is mounted by `FogletBbsWeb.Endpoint` and is the primary
in-process observability surface for sysops.

<!-- VERIFY: external monitoring/alerting (PagerDuty, Grafana, Datadog, log aggregator) integration — not configured in the repo -->
<!-- VERIFY: log shipping target — Fly's built-in log stream is implicit; any aggregator beyond that is environment-specific -->

## Rollback Procedure

### Application rollback

- **Fly.io:** `fly releases --app foglet-bbs` to list, then
  `fly deploy --image <previous-image-ref> --app foglet-bbs` or
  `fly machines update <id> --image <ref>` to pin a Machine to a prior
  release. <!-- VERIFY: exact rollback command preferred by your team — Fly's UI also offers a one-click rollback per release -->
- **Docker:** redeploy the previous image tag.
- **Bare metal release:** keep the previous `_build/prod/rel/foglet_bbs`
  tarball and swap the symlink, then restart.

### Database rollback

`FogletBbs.Release.rollback(FogletBbs.Repo, version)` runs
`Ecto.Migrator.run(repo, :down, to: version)`. On Fly:

```sh
fly ssh console --app foglet-bbs -C \
  '/app/bin/foglet_bbs eval "FogletBbs.Release.rollback(FogletBbs.Repo, 20260101000000)"'
```

Schema rollbacks are rarely safe in isolation — coordinate with the
application rollback so the running release expects the older schema.

## Backup & Restore

<!-- VERIFY: production database backup strategy — Fly Postgres ships with daily snapshots by default, but retention, off-site copies, and restore drills are operations decisions not encoded in this repo -->
<!-- VERIFY: SSH host key backup — `${SSH_HOST_KEY_DIR}` contents must be backed up out-of-band; losing the host key forces every user to re-trust the server -->
<!-- VERIFY: foglet_data volume backup — the Fly volume holds /data/ssh, /data/.config, and HOME state; back up at the volume layer if you rely on anything beyond the host key -->

## Operational Notes

- **Clustering / multi-node:** `DNS_CLUSTER_QUERY` is wired through
  `dns_cluster` and `rel/env.sh.eex` sets it on Fly to
  `${FLY_APP_NAME}.internal`, but multi-node operation is explicitly
  not a v1 target (see `docs/ARCHITECTURE.md`). Per-board GenServers
  and SSH host-key sharing both have to be designed before scaling
  past one SSH-serving Machine.
  <!-- VERIFY: whether multi-node clustering is intended for any production environment yet -->
- **Zero-downtime deploys:** `fly.toml` declares `kill_signal = "SIGTERM"`
  and `kill_timeout = "30s"`, and the HTTP service auto-starts/stops
  Machines. The SSH service has `min_machines_running = 1` and
  `auto_stop_machines = "off"` to keep at least one SSH Machine warm.
  <!-- VERIFY: whether in-flight SSH sessions are gracefully drained on deploy — the SIGTERM/30s timeout is the only signal in fly.toml; explicit drain coordination is not implemented in the repo -->
- **TLS:** Fly's `[http_service]` does HTTPS termination
  (`force_https = true`). For non-Fly deployments, terminate TLS upstream
  or uncomment the `https:` block in `config/runtime.exs` and provide
  cert/key paths via env.
  <!-- VERIFY: certificate issuance and renewal mechanism for non-Fly deployments -->
- **Health check:** Fly checks `GET /up` every 15s with a 30s grace
  period. The endpoint is provided by the standard Phoenix dev/prod
  router. Ensure any reverse proxy outside Fly is configured to hit the
  same path.

## See Also

- `docs/CONFIGURATION.md` — canonical environment variable and runtime
  config reference.
- `docs/ARCHITECTURE.md` — listener layout, LiveDashboard auth, and
  scaling boundaries.
- `README.md` — local development setup.
