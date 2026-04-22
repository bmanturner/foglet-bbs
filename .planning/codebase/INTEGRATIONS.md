# External Integrations

**Analysis Date:** 2026-04-22

## APIs & External Services

**None currently integrated.**

Future placeholders in configuration:
- SENTRY_DSN (error tracking, referenced in `config/runtime.exs` but not implemented)

## Data Storage

**Databases:**
- PostgreSQL (primary database)
  - Connection: DATABASE_URL (production) or configured in `config/dev.exs`
  - Client: Postgrex 0.22.0 (driver)
  - ORM: Ecto 3.13.5 / EctoSQL 3.13.5
  - Dev database: `foglet_bbs_dev`
  - Migrations: `priv/repo/migrations/`
  - Seeds: `priv/repo/seeds.exs`

**File Storage:**
- Local filesystem only (no S3, cloud storage, or file service)
- Static assets served from `priv/static/`

**Caching:**
- ETS (Erlang Term Storage)
  - Runtime config cache (`FogletBbs.Config` ETS table)
  - Pubkey stash for SSH authentication (`Foglet.SSH.PubkeyStash` ETS table)
  - Board server registry (`Foglet.BoardRegistry`)
  - Session registry (`Foglet.Sessions.Registry`)

**In-Memory Queuing:**
- Oban 2.21.1 (installed but not currently configured; available for job scheduling)

## Authentication & Identity

**Auth Provider:**
- Custom in-app authentication
  - Implementation: `lib/foglet_bbs/accounts.ex`
  - Password hashing: Argon2 (via argon2_elixir 4.1.3)
  - User tokens: SHA256 hashes stored in database (raw token returned to caller)
  - Session management: Custom registry-based sessions (`Foglet.Sessions.Registry`)
  - User model: `lib/foglet_bbs/accounts/user.ex`

**SSH Authentication:**
- Custom SSH daemon (Milestone 3+)
  - Module: `Foglet.SSH` (in `lib/foglet_bbs/ssh/`)
  - Public key authentication via pubkey stash (`Foglet.SSH.PubkeyStash`)
  - CLI handler via `Foglet.SSH.CLIHandler`
  - Port: Configurable via SSH_PORT env var (default 2222)
  - Host key directory: SSH_HOST_KEY_DIR env var (default `priv/ssh`)

## Monitoring & Observability

**Error Tracking:**
- None integrated (SENTRY_DSN env var available for future use)

**Logs:**
- Elixir Logger (stdlib)
- Development: `[$level] $message` format at :info level
- Production: :info level, no sensitive data
- Request tracking: Request IDs via Plug.RequestId middleware

**Metrics:**
- Telemetry hooks (telemetry 1.4.1)
- Metrics collection: telemetry_metrics 1.1.0
- Periodic polling: telemetry_poller 1.3.0
- Live Dashboard: Phoenix.LiveDashboard 0.8.7 (dev routes only)

**Distributed Tracing:**
- Not implemented (infrastructure present via telemetry, but no exporter)

## CI/CD & Deployment

**Hosting:**
- Self-hosted (no pre-configured cloud integrations)
- Can be deployed to any platform supporting Erlang/OTP:
  - Traditional VPS/dedicated servers
  - Container platforms (Docker-compatible)
  - Fly.io, Heroku, or similar (via `mix release`)

**CI Pipeline:**
- GitHub Actions configuration: `.github/workflows/` (if any)
- Local development: `mix precommit` for full QA (compile, format, credo, sobelow, dialyzer)

**Release Artifact:**
- `mix release` generates standalone Erlang release
- HTTP server: Bandit 1.10.4 (built-in adapter)

## Network & Clustering

**DNS Clustering:**
- dns_cluster 0.2.0 integrated for distributed node discovery
- Configured via DNS_CLUSTER_QUERY env var (optional)
- Default: :ignore (no clustering)

## Environment Configuration

**Required env vars (production):**
- `DATABASE_URL` - PostgreSQL connection string (format: `ecto://USER:PASS@HOST/DATABASE`)
- `SECRET_KEY_BASE` - Session/cookie signing key (generate via `mix phx.gen.secret`)
- `PHX_HOST` - Public hostname (e.g., `example.com`)

**Optional env vars:**
- `PORT` - HTTP server port (default: 4000)
- `POOL_SIZE` - Database connection pool size (default: 10)
- `ECTO_IPV6` - Enable IPv6 for database (default: false)
- `DNS_CLUSTER_QUERY` - DNS query for node clustering (default: unset)
- `FOGLET_SSH_PORT` or `SSH_PORT` - SSH daemon port (default: 2222)
- `SSH_HOST_KEY_DIR` - SSH host key directory (default: `priv/ssh`)
- `SENTRY_DSN` - Sentry error tracking (not yet integrated)
- `PHX_SERVER` - Enable HTTP server in release mode (default: false)

**Configuration validation:**
- `config/runtime.exs` enforces DATABASE_URL and SECRET_KEY_BASE in production
- Missing required vars raise runtime error on startup

**Secrets location:**
- Production: Environment variables (injected at runtime)
- Development: `config/dev.exs` (hardcoded for convenience)
- `.env.example` provided as template (`.env` files not committed)

## Webhooks & Callbacks

**Incoming:**
- SSH CLI protocol (custom)
  - Entry point: `Foglet.SSH` supervisor and handler
  - Protocol: SSH protocol with custom command processing

**Outgoing:**
- None implemented

## Pub/Sub & Real-Time Communication

**Pub/Sub System:**
- Phoenix.PubSub 2.2.0
  - Server name: FogletBbs.PubSub
  - Adapter: (default in-memory, suitable for single-node or clustered via Redis if needed)

**WebSocket:**
- LiveView over WebSocket (Phoenix.LiveView 1.1.28)
- Signing salt for LiveView: "UCDYsbrB" (in `config/config.exs`)

## Markdown Processing

**Markdown Engine:**
- Mdex 0.12.1 (Rust-based via rustler_precompiled)
  - Syntax highlighting via Lumis 0.4.0
  - Output format: HTML
  - Entry point: `lib/foglet_bbs/markdown.ex`

## Internationalization (i18n)

**Framework:**
- Gettext 1.0.2
- Translation files: `priv/gettext/`
- Locales: (check priv/gettext/ for available languages)

---

*Integration audit: 2026-04-22*
