# Technology Stack

**Analysis Date:** 2026-04-18

## Languages

**Primary:**
- Elixir 1.19.5 - Core application logic, business domains, web layer
- Erlang/OTP 28.3.1 - Runtime system providing concurrency primitives and BEAM

**Secondary:**
- SQL - PostgreSQL schema queries and migrations

## Runtime

**Environment:**
- Erlang/OTP 28.3.1 via BEAM virtual machine

**Package Manager:**
- Mix (Elixir's build tool and dependency manager)
- Lockfile: `mix.lock` (present, comprehensive)

## Frameworks

**Core:**
- Phoenix 1.8.5 - Web framework providing routing, channels, live views, HTTP handling
- Phoenix Live View - Real-time interactive UIs (configured but not yet in use for end-user features)
- Phoenix Presence - Real-time presence tracking for connected users
- Phoenix PubSub - Distributed publish-subscribe system

**Testing:**
- ExUnit (built-in Elixir test framework)
- Ecto SQL Sandbox adapter for test isolation

**Build/Dev:**
- Mix - Build, testing, and task running
- Credo 1.7 - Code linting and style checking (strict mode enabled)
- Dialyxir 1.4 - Static type analysis via Dialyzer
- Stream Data 1.0 - Property-based testing framework

## Key Dependencies

**Critical:**
- `postgrex >=0.0.0` - PostgreSQL JDBC adapter for Ecto
- `phoenix_ecto 4.5` - Ecto integration with Phoenix
- `ecto_sql 3.13` - SQL abstraction layer for Ecto ORM
- `argon2_elixir 4.0` - Argon2 password hashing (configured for auth)
- `oban 2.18` - Job processing and scheduling for background work
- `bandit 1.5` - HTTP server (Phoenix's default adapter in v1.8)

**Infrastructure:**
- `phoenix_live_dashboard 0.8.3` - Runtime monitoring and observability UI
- `telemetry_metrics 1.0` - Metrics collection infrastructure
- `telemetry_poller 1.0` - Periodic telemetry measurements
- `dns_cluster 0.2.0` - DNS-based node clustering for distributed deployments
- `gettext 1.0` - Internationalization framework
- `jason 1.2` - JSON encoder/decoder

## Configuration

**Environment:**
- Configured via `config/config.exs`, `config/dev.exs`, `config/test.exs`, `config/prod.exs`, and `config/runtime.exs`
- Critical production env vars required:
  - `DATABASE_URL` - PostgreSQL connection string
  - `SECRET_KEY_BASE` - Session/cookie signing key (generated via `mix phx.gen.secret`)
  - `PHX_HOST` - Public hostname for URL generation
  - `PHX_SERVER` - Enable HTTP server (set to `true` in releases)
  - `SSH_PORT` - SSH daemon port (default: 2222)
  - `SSH_HOST_KEY_DIR` - Directory for SSH host keys

**Build:**
- `.formatter.exs` - Elixir code formatter configuration (extends Phoenix, Ecto, Ecto SQL)
- `.credo.exs` - Credo linting rules (strict mode, 120-character line limit)
- `.tool-versions` - asdf version manager pinning (Elixir 1.19.5-otp-28, Erlang 28.3.1)

## Platform Requirements

**Development:**
- Elixir 1.19.5 (or compatible via asdf)
- Erlang/OTP 28.3.1
- PostgreSQL 16+ (Docker Compose provided in `docker-compose.yml`)
- Unix/Linux shell environment (tests use shell commands)

**Production:**
- PostgreSQL 16+ database
- Deployment target: Fly.io or self-hosted hardware (Docker recommended)
- HTTPS/SSL termination (reverse proxy or load balancer)
- SSH port exposure (2222 by default, configurable)

## Development Tooling

**Project Setup:**
- `mix setup` - Install deps and initialize database
- `mix phx.server` - Start development server with hot reloading
- `mix test` - Run test suite (creates test DB before running)
- `mix precommit` - Quality gate: compile, format, lint (Credo strict), test

**Observability:**
- Phoenix LiveDashboard available at `/dev/dashboard` in development (authentication-optional in prod)
- Telemetry metrics collection configured but no reporters enabled by default
- Sentry integration optional (env var: `SENTRY_DSN`, not yet configured)

---

*Stack analysis: 2026-04-18*
