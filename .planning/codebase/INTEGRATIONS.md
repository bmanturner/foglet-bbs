# External Integrations

**Analysis Date:** 2026-04-29

Foglet BBS is a primarily self-hosted SSH bulletin board. The product surface is the terminal UI served over SSH. External integrations are intentionally minimal: Postgres for durable state, optional SMTP for transactional email, and Fly.io as the deploy target. No third-party identity providers, no analytics SDKs, no object stores, no external API SDKs.

## APIs & External Services

**No third-party API SDKs are imported.** A grep for SDK imports across `lib/` finds none. The only outbound network protocols spoken are:

- Postgres wire protocol (via `:postgrex`) — durable storage.
- SMTP (via `:gen_smtp` through `:swoosh`) — optional transactional email.
- Fly.io machine API — only used by the deploy GitHub Action (`flyctl`), not by the running app.

## Data Storage

**Databases:**
- PostgreSQL 16 (authoritative durable state — `AGENTS.md` and `docs/DATA_MODEL.md`).
  - Connection: `DATABASE_URL` env var (read in `config/runtime.exs`); local dev defaults to `postgres@localhost:5432/foglet_bbs_dev` in `config/dev.exs`. Test DB pattern: `foglet_bbs_test#{MIX_TEST_PARTITION}` in `config/test.exs`.
  - Driver: `:postgrex`.
  - ORM: `Ecto` `3.13.5` / `:ecto_sql` `3.13.5`. Repo: `FogletBbs.Repo` (`lib/foglet_bbs/repo.ex`).
  - Pool size: `POOL_SIZE` env (default `10`). IPv6 toggled by `ECTO_IPV6=true` (`maybe_ipv6` in `config/runtime.exs`).
  - Migrations: `priv/repo/migrations/` (timestamped Postgres migrations, including `citext` and the `user_role` enum in `20260418000001_create_citext_and_user_role.exs`).
  - Production migrations run via `Ecto.Migrator` in the Fly `release_command` (`fly.toml`), wrapped by `FogletBbs.Release.migrate/0` (`lib/foglet_bbs/release.ex`).

**ETS (in-process caches, ephemeral):**
- `Foglet.Config` ETS-backed read-through cache over the `configuration` table (`lib/foglet_bbs/config.ex`). Reconstructable on restart from Postgres.
- `Foglet.SSH.PubkeyStash` ETS table — pubkey-to-user correlation between `Foglet.SSH.KeyCB` and `Foglet.SSH.CLIHandler`.
- `Foglet.SSH.RateLimiter` — Hammer v7 ETS backend for per-IP throttling.
- `Foglet.SSH.CLIHandler` connection counter (initialized in `Foglet.SSH.Supervisor.init/1`).

**File Storage:**
- Local filesystem only. The Fly volume `foglet_data` is mounted at `/data`; SSH host keys persist at `/data/ssh` (`SSH_HOST_KEY_DIR=/data/ssh` in `fly.toml`). No S3/GCS/object-store integration.

**Caching:**
- ETS only (see above). No Redis or external cache.

## Authentication & Identity

**Auth Provider:**
- None. Authentication is fully in-process and persisted in Postgres.
  - Password auth: `Foglet.Accounts.User` + `:argon2_elixir` hashes (`lib/foglet_bbs/accounts/user.ex`).
  - SSH public-key auth: `Foglet.Accounts.SSHKey` (`lib/foglet_bbs/accounts/ssh_key.ex`); the `:ssh` daemon is configured `no_auth_needed: true` in `Foglet.SSH.Supervisor`, and the TUI login screen is the actual authentication boundary.
  - Tokens (email verify, password reset): `Foglet.Accounts.UserToken` (`lib/foglet_bbs/accounts/user_token.ex`), driven by `Foglet.Accounts.Verification` (`lib/foglet_bbs/accounts/verification.ex`).
  - Authorization: `Foglet.Authorization` implementing `Bodyguard.Policy`.
  - Session model: one-session-per-user, owned by `Foglet.Sessions.*` under `lib/foglet_bbs/sessions/` (`session.ex`, `supervisor.ex`, `preferences.ex`) with a `Registry` keyed by user.
- No OAuth, OIDC, SAML, Auth0, Clerk, Supabase Auth, or social login. Self-contained accounts only.

## Monitoring & Observability

**Error Tracking:**
- None wired up. The `.env.example` mentions `SENTRY_DSN` as a placeholder for "Milestone 10+", but no `:sentry`/`:sentry_phoenix` dependency exists in `mix.exs` or `mix.lock` and no `Sentry` references appear in `lib/` or `config/`.

**Logs:**
- Elixir `Logger` only. Format and metadata configured in `config/config.exs` (`format: "$time $metadata[$level] $message\n"`, `metadata: [:request_id]`). Dev format simplified in `config/dev.exs`. Test level is `:warning`.

**Metrics / Telemetry:**
- `:telemetry_metrics` + `:telemetry_poller` configured in `lib/foglet_bbs_web/telemetry.ex` (Phoenix endpoint, router dispatch, channels, Repo query timings, VM memory and run-queue lengths).
- `:phoenix_live_dashboard` mounted at `/dev/dashboard` in `lib/foglet_bbs_web/router.ex`, gated on the compile-time `:dev_routes` config (dev only). LiveDashboard request logger plug is mounted in `lib/foglet_bbs_web/endpoint.ex`.
- Raxol telemetry feature is enabled in `config/config.exs`; performance monitoring is explicitly disabled to avoid a known Raxol 2.4.0 startup crash (see comment in that file).

## CI/CD & Deployment

**Hosting:**
- Fly.io app `foglet-bbs` in region `iad` (`fly.toml`).
  - HTTP service: internal `4000`, `force_https = true`, `auto_stop_machines = "stop"`, health check `GET /up` every 15s.
  - SSH service: internal `2222` exposed on Fly port `22`, `auto_stop_machines = "off"`, `min_machines_running = 1` so the SSH daemon never cold-starts.
  - VM: `512mb` memory, shared CPU, 1 cpu, 256mb swap.
  - Volume `foglet_data` (1GB) mounted at `/data` for SSH host keys and `XDG_CONFIG_HOME`.
  - DB: managed via `fly postgres` (cluster `foglet-bbs-db`); attachment sets `DATABASE_URL` automatically.

**CI Pipeline:**
- `.github/workflows/ci.yml` (on every push and PR): provisions Postgres 16, runs `mix deps.get`, `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict`, `mix hex.audit`, `mix sobelow --exit Low`, `mix dialyzer`, `mix test` (with `DATABASE_URL=ecto://postgres:postgres@localhost/foglet_bbs_test`).
- `.github/workflows/fly-deploy.yml` (on push to `prod` branch): runs `flyctl deploy --remote-only --app foglet-bbs` with `FLY_API_TOKEN` from secrets. Concurrency-grouped under `fly-deploy-production`.

## Environment Configuration

**Required env vars (production):**
- `DATABASE_URL` — Postgres connection string (raises at boot if missing — `config/runtime.exs`).
- `SECRET_KEY_BASE` — Phoenix cookie/session secret (raises at boot if missing).
- `PHX_HOST` — public hostname (defaults to `example.com` if unset; `bbs.foglet.io` in `fly.toml`).
- `PHX_SERVER` — set to `true` to actually start the HTTP endpoint inside a release.

**Optional env vars:**
- `PORT` (default `4000`), `POOL_SIZE` (default `10`), `ECTO_IPV6` (`true`/`1` to use `:inet6`).
- `DNS_CLUSTER_QUERY` — DNS-based libcluster discovery via `:dns_cluster`.
- `FOGLET_SSH_PORT` (default `2222`), `SSH_HOST_KEY_DIR` (default `priv/ssh` dev / `/data/ssh` prod).
- `FOGLET_DEFAULT_TIMEZONE` — IANA tz name; validated at boot in `FogletBbs.Application.validate_default_timezone/0`.
- `FOGLET_MAIL_FROM` — default From address (`no-reply@foglet.io` on Fly).
- SMTP relay: `FOGLET_SMTP_RELAY` (or `FOGLET_SMTP_HOST`), `FOGLET_SMTP_PORT` (default `587`), `FOGLET_SMTP_USERNAME`, `FOGLET_SMTP_PASSWORD`, `FOGLET_SMTP_SSL`, `FOGLET_SMTP_TLS` (default `if_available`), `FOGLET_SMTP_AUTH` (default `if_available`). When any relay var is present, the runtime config swaps the Swoosh adapter from `Local` to `Swoosh.Adapters.SMTP`.

**Secrets location:**
- Local dev: `.env.local` (gitignored), loaded by `Dotenvy.source/1` in `config/runtime.exs`. `.env.example` documents the variable names with no values.
- Production: Fly secrets (`fly secrets set …`). The deploy CI uses `FLY_API_TOKEN` from GitHub repository secrets.
- Database-stored runtime config (Foglet.Config) is for non-secret operational toggles only — `AGENTS.md` explicitly forbids putting secrets there.

## Webhooks & Callbacks

**Incoming:**
- `GET /up` — Fly platform health check (`FogletBbsWeb.HealthController`, mounted in `lib/foglet_bbs_web/router.ex`).
- `GET /` — placeholder Phoenix home page (`PageController.home`).
- No third-party webhook receivers (no Stripe, GitHub, Slack, etc. webhook handlers).

**Outgoing:**
- SMTP delivery via `Foglet.Mailer.deliver/1` for verification codes, password resets, account approvals/rejections, and sysop notifications (`lib/foglet_bbs/accounts/email.ex`). Delivery is gated by the runtime config key `delivery_mode` (`"email"` vs `"no_email"`) — see `Foglet.Accounts.Verification.deliver_verification_code/1` and `request_password_reset_delivery/1`.
- No outbound HTTP API calls.

## Notable Non-Integrations

The following are commonly expected in similar Phoenix apps but are **deliberately not present** in Foglet BBS:

- No object storage (no `:ex_aws*`, no S3/GCS clients).
- No analytics or product-metrics SDKs (no PostHog, Segment, Amplitude).
- No payment processing (no Stripe, Paddle, etc.).
- No third-party auth (no Ueberauth, Auth0, Clerk, Supabase Auth, social login).
- No error-tracking SaaS (no Sentry, Honeybadger, AppSignal — `SENTRY_DSN` placeholder in `.env.example` is aspirational only).
- No CDN, search service, or vector DB integration.
- No browser-facing JS/CSS asset pipeline (no `assets/`, no esbuild/tailwind watchers — see empty `watchers: []` in `config/dev.exs`). Phoenix is intentionally infrastructure-only per `AGENTS.md`.

---

*Integration audit: 2026-04-29*
