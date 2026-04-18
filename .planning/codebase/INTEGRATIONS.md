# External Integrations

**Analysis Date:** 2026-04-18

## APIs & External Services

**SSH Server:**
- Erlang `:ssh` application - Built-in SSH daemon for terminal access
  - Configuration: `config/runtime.exs` (port and host key directory)
  - Port: Configurable via `SSH_PORT` env var (default: 2222)

## Data Storage

**Databases:**
- PostgreSQL 16+
  - Connection: `DATABASE_URL` environment variable
  - Client: Ecto + PostreX adapter (`postgrex` package)
  - Adapter: `Ecto.Adapters.Postgres`

**File Storage:**
- Local filesystem only - Static assets served from `priv/static/` via Plug.Static

**Caching:**
- ETS (Erlang Term Storage) - Built into BEAM, available for in-memory caching
- Phoenix Presence - Real-time user presence via PubSub (not external service)

## Authentication & Identity

**Auth Provider:**
- Custom implementation (bootstrapped from `mix phx.gen.auth`)
  - Password hashing: Argon2 via `argon2_elixir` package
  - Session storage: HTTP cookies (signed, configured in `lib/foglet_bbs_web/endpoint.ex`)
  - SSH public key authentication: Planned (Milestone 3+)
  - Single active session per user: Designed but not yet enforced

## Monitoring & Observability

**Error Tracking:**
- Sentry integration optional (env var: `SENTRY_DSN`)
  - Not yet configured in dependencies or application startup
  - Placeholder in `.env.example` for future use

**Logs:**
- Standard Elixir Logger to stdout
  - Format: `$time $metadata[$level] $message\n` with request IDs
  - Development: `[$level] $message` format (less verbose)
  - Production: `level: :info` (warnings and errors only)

**Metrics:**
- Telemetry infrastructure set up (`telemetry_metrics`, `telemetry_poller`)
- Metrics defined in `lib/foglet_bbs_web/telemetry.ex`:
  - Phoenix endpoint and router metrics (latency, duration)
  - Phoenix channel metrics (connection, join duration)
  - Database query metrics (total, decode, query, queue, idle times)
  - VM metrics (memory, run queue lengths)
- No reporters enabled by default (console reporter commented out)

## CI/CD & Deployment

**Hosting:**
- Primary target: Fly.io (with `SECRET_KEY_BASE` and database URL management)
- Secondary: Self-hosted hardware or Docker containers
- Reverse proxy / TLS: Delegated to sysop (not part of Foglet)

**CI Pipeline:**
- Not yet configured (pre-alpha stage)
- Recommended: GitHub Actions via `.github/workflows/` (directory exists but empty)

## Environment Configuration

**Required env vars:**
- `DATABASE_URL` - PostgreSQL connection string (format: `ecto://USER:PASS@HOST/DATABASE`)
- `SECRET_KEY_BASE` - Session/cookie signing key (generated via `mix phx.gen.secret`)
- `PHX_HOST` - Public hostname for URL generation
- `PHX_SERVER` - Enable HTTP server (required for releases)
- `SSH_PORT` - SSH daemon port (default: 2222)
- `SSH_HOST_KEY_DIR` - Directory path for SSH host keys (default: `priv/ssh`)

**Optional env vars:**
- `PORT` - HTTP server port (default: 4000)
- `POOL_SIZE` - Database connection pool size (default: 10)
- `ECTO_IPV6` - Enable IPv6 connections (default: false)
- `DNS_CLUSTER_QUERY` - DNS query for multi-node clustering (optional)
- `SENTRY_DSN` - Sentry error tracking endpoint (optional, not yet integrated)

**Secrets location:**
- Environment variables only (no secrets files checked in)
- `.env` file excluded from git (listed in `.gitignore`)
- `.env.example` provides template of required vars

## Webhooks & Callbacks

**Incoming:**
- None currently (pre-alpha, no external webhook integrations)

**Outgoing:**
- None currently (Sentry would be outgoing error reports when enabled)
- Email digests planned for notifications (Milestone 8+)

## Database Schema

**Current State:**
- No migration files present yet (scaffolding phase)
- `priv/repo/migrations/` directory exists but empty
- `.citext` PostgreSQL extension expected (checked by `mix foglet.doctor` task)
- Binary IDs configured as default: `generators: [binary_id: true]`

## Network Communication

**Protocols:**
- HTTP/HTTPS - Via Bandit adapter (modern HTTP server)
- SSH - Via Erlang `:ssh` application
- WebSocket - Phoenix Channels over WebSocket (for real-time features)
- DNS - Via `dns_cluster` for node discovery in distributed setups

---

*Integration audit: 2026-04-18*
