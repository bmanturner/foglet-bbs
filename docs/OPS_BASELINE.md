# Operations Baseline

This baseline supersedes the pre-repository FOG-8 deploy/runbook artifact for
deploy target, release mechanics, rollback, smoke checks, host key persistence,
and secret handling. It is intentionally grounded in the files committed to this
repository and should be read with `docs/DEPLOYMENT.md`.

## Canonical Artifacts

| Area | Canonical artifact | Operational meaning |
| --- | --- | --- |
| Image build | `Dockerfile` | Builds a Debian-based OTP release image, runs as `nobody`, exposes SSH `2222` and HTTP `4000`, declares `/data` as persistent storage, and packages Python 3 for the door PTY helper. It does not currently provide a distinct restricted door user inside the container. |
| Local database | `docker-compose.yml` | Provides local `postgres:16` only. It is not a production app stack. |
| Production target | `fly.toml` | Fly.io is the committed deploy target: app `foglet-bbs`, region `iad`, HTTP health on `/up`, SSH TCP service on public port `22`, and persistent `foglet_data` mounted at `/data`. |
| Release scripts | `rel/env.sh.eex`, `rel/overlays/bin/server`, `rel/overlays/bin/migrate` | Defines release node/env behavior, starts the Phoenix server for releases, and exposes migration execution inside the release. |
| Runtime config | `config/runtime.exs` | Reads deploy-time env vars and secrets, requires `DATABASE_URL` and `SECRET_KEY_BASE` in prod, configures HTTP port, SSH port, SMTP, Repo, endpoint, and `SSH_HOST_KEY_DIR`. |
| Deploy workflow | `.github/workflows/fly-deploy.yml` | Deploys on pushes to `prod` with `flyctl deploy --remote-only --app foglet-bbs` and `FLY_API_TOKEN` from repository secrets. |
| Quality gate | `.github/workflows/ci.yml` | Runs format, compile warnings-as-errors, Credo, Hex audit, Sobelow, Dialyzer, and ExUnit against Postgres before merge/deploy promotion. |
| Operator guide | `docs/DEPLOYMENT.md` | Canonical operator-facing deployment, environment, telemetry, rollback, backup, and health-check guide. |

## FOG-8 Assumption Review

Still valid:

- Foglet deploys as a single OTP release containing both SSH and Phoenix
  operational infrastructure.
- Runtime configuration and secrets must come from environment variables or the
  deployment platform secret store, not from checked-in files or the DB-backed
  `configuration` table.
- Rollback planning must cover both code-only rollback and schema rollback, and
  destructive database recovery requires explicit CTO approval.
- Smoke checks must prove the SSH listener, welcome/login path, board-list path,
  process health, and telemetry/log visibility before a release is accepted.
- SSH host key persistence is release-critical because changing it breaks
  client trust for returning users.

Superseded by committed artifacts:

- The first deploy target is no longer a generic single Linux VM with
  `systemd`. The canonical committed target is Fly.io via `fly.toml` and
  `.github/workflows/fly-deploy.yml`. Docker remains the release image format
  and a portable fallback, but no `systemd` unit is committed.
- The runtime filesystem baseline is `/data`, not an unspecified VM path.
  `Dockerfile` declares `/data`, and Fly mounts `foglet_data` at `/data`.
- The SSH host key path is `SSH_HOST_KEY_DIR`, set to `/data/ssh` by `fly.toml`
  for Fly. `config/runtime.exs` falls back to `priv/ssh` only if the env var is
  unset; that fallback is not acceptable as a production identity.
- The deploy migration path is Fly's `[deploy] release_command`, plus the
  release helper in `lib/foglet_bbs/release.ex` and `rel/overlays/bin/migrate`,
  not an external ad hoc migration script.
- Telemetry has definitions but no external reporter. LiveDashboard and platform
  logs are the current baseline; Prometheus, OTLP, Sentry, PagerDuty, or other
  exporters are future integration choices until wired in code/config.

## FOG-14 Review Guidance

FOG-14 should be reviewed against the canonical artifacts above, not against the
earlier systemd-oriented artifact stubs.

Review as valid if it:

- Treats Fly.io as the first deploy target and Docker as the release image path.
- Uses `docs/DEPLOYMENT.md` as the operator guide rather than inventing a second
  deployment procedure.
- Keeps secrets in Fly secrets, GitHub Actions secrets, or process env only.
- Preserves `/data/ssh` host key persistence and documents backup expectations.
- Uses the existing CI workflow as the pre-deploy quality gate and the Fly deploy
  workflow as the promotion mechanism.
- Names the rollback path for application image rollback and schema rollback.

Request changes if it:

- Reintroduces `systemd` as the primary target without a new issue and CTO
  approval.
- Stores secret values, database passwords, host private keys, or tokens in
  docs, comments, repo config, or examples.
- Treats `docker-compose.yml` as a production deployment topology.
- Assumes a telemetry exporter or alerting backend that is not committed.
- Changes ports, host key behavior, migration behavior, or release startup
  without updating `Dockerfile`, `fly.toml`, `config/runtime.exs`, and
  `docs/DEPLOYMENT.md` together.

## External Door Sandbox Operations Baseline

FOG-823/FOG-829 adds the deployment contract for the stronger external-door
hardening baseline. The supported baseline is restricted OS user plus per-door
process-group cleanup. The process-group side is a POSIX runtime behavior owned
by the door PTY helper; the restricted-user side is an operator/runtime capability
that must fail closed when unavailable.

Operational requirements:

- Keep the Foglet app user and restricted door user distinct. Suggested names are
  `foglet` for the release user and `foglet-door` for external/classic door
  processes.
- Door executables and working directories must be absolute, operator-owned, and
  readable/executable only by the restricted door identity or a narrow door group.
- The restricted door user must not be able to read app secrets, database URLs,
  SMTP credentials, Fly/GitHub tokens, SSH host private keys, or backups.
- Door launch must fail closed if a manifest/config says a restricted user is
  required but the runtime cannot switch uid/gid before exec.
- Process cleanup evidence should include normal exit, timeout, and disconnect
  paths terminating the helper-owned process group.

Container caveat:

The committed Dockerfile runs the full release as `nobody`. That is good for the
app container baseline, but it means the current image cannot safely switch a
door to a separate restricted OS user without a new approved runtime shape
(privileged helper, retained root entrypoint that drops privileges, file
capabilities, user namespace strategy, or equivalent). Until that decision is
made and implemented, Docker/Fly support process-group cleanup but not the
restricted-user half of the approved sandbox baseline. Treat this as a blocker
for untrusted third-party doors and a caveat for first-party reviewed demo doors.

Rollback / incident notes:

- Prefer disabling external/classic door manifests over weakening the sandbox.
- If a bad sandbox config blocks legitimate reviewed doors, roll back to the
  previous config/image and verify the SSH listener, welcome/login flow, board
  listing, supervisor health, and log signal before re-enabling doors.
- Destructive cleanup on shared hosts requires explicit incident approval; use
  targeted restricted-user/process-group cleanup only.

## Smoke Checks

Minimum release smoke evidence:

1. HTTP health: `GET https://$PHX_HOST/up` returns success through the deployed
   endpoint.
2. SSH listener: `ssh -p 22 $PHX_HOST` reaches the Foglet SSH daemon and shows
   the expected welcome/login flow. Use a non-production test account or an
   approved operational account; do not paste credentials into logs or issue
   comments.
3. TUI path: authenticate and reach the board list or main menu without a crash.
4. Runtime health: LiveDashboard or `fly logs --app foglet-bbs` shows the app
   booted cleanly, the Repo connected, and no repeated supervisor restarts.
5. Telemetry/log visibility: confirm Phoenix/Ecto/BEAM telemetry definitions are
   active through LiveDashboard or local release observation; external reporter
   evidence is only required after a reporter is configured.

## Rollback Expectations

Application rollback:

- Fly: list releases with `fly releases --app foglet-bbs`, then redeploy or pin a
  previous image according to the team-approved Fly rollback path.
- Docker fallback: redeploy the previous image tag.
- Bare release fallback: keep the previous release tarball/symlink and restart
  after switching back.

Database rollback:

- Prefer forward fixes for production data when possible.
- Before running `FogletBbs.Release.rollback(FogletBbs.Repo, version)`, verify a
  restorable database backup and confirm the running app version expects the
  target schema.
- Any destructive rollback, restore, or manual data repair requires CTO approval
  and should name the exact migration/version and backup being used.

## Host Key Persistence

Production SSH identity must survive deploys:

- Generate production host keys once.
- Store private host keys only on persistent, access-controlled storage.
- On Fly, mount them under `/data/ssh` because `fly.toml` sets
  `SSH_HOST_KEY_DIR=/data/ssh` and mounts `foglet_data` at `/data`.
- Back up the host key directory out of band.
- If scaling beyond one SSH-serving machine, deliberately copy/share the same
  host key material or plan a user-visible fingerprint rotation.

## Secrets Handling

- Required prod secrets are `DATABASE_URL` and `SECRET_KEY_BASE`; optional SMTP
  credentials are read from `FOGLET_SMTP_*` env vars.
- `FLY_API_TOKEN` belongs in GitHub Actions repository secrets only.
- Do not commit `.env.local`, production host private keys, database URLs,
  session tokens, SMTP passwords, or Fly tokens.
- Docs and examples may name variables, secret references, and commands, but
  must not include actual secret values.

## Ownership

Per the revised FOG-17 ownership map, the Ops Specialist owns `Dockerfile`,
`docker-compose.yml`, `fly.toml`, `rel/`, `config/runtime.exs`, `config/prod.exs`,
`.github/workflows/fly-deploy.yml`, `docs/DEPLOYMENT.md`, and operational
sections of `docs/CONFIGURATION.md`.

Cross-specialist review is required when ops changes alter:

- OTP supervision or release startup: Elixir/OTP Runtime Specialist.
- Migrations, rollback safety, seed data, or database connectivity: Domain/Data
  Specialist.
- CI gates, release evidence, or smoke coverage: QA Specialist.
- Operator-facing docs wording: Writing/Tone/Docs Specialist.

