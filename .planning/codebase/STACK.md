# Technology Stack

**Analysis Date:** 2026-04-22

## Languages

**Primary:**
- Elixir 1.19.5 - Primary application language

**VM:**
- Erlang OTP 28.3.1 - Underlying runtime for Elixir

## Runtime

**Environment:**
- Erlang/OTP 28.3.1

**Package Manager:**
- Mix (Elixir's built-in package manager)
- Lockfile: `mix.lock` (present)

## Frameworks

**Core Web:**
- Phoenix 1.8.5 - Web framework and HTTP server adapter

**Real-time & Pub/Sub:**
- Phoenix.LiveView 1.1.28 - Dynamic UI updates over WebSocket
- Phoenix.PubSub 2.2.0 - Pub/Sub messaging layer

**TUI/Terminal:**
- Raxol (vendor/raxol, local path dependency) 2.4.0 - Terminal UI framework
  - Raxol.Core 2.4.0 - Core TUI infrastructure
  - Raxol.LiveView 2.4.0 - LiveView integration for TUI
  - Raxol.Terminal 2.4.0 - Terminal driver
  - Raxol.Sensor 2.4.0 - Terminal sensor/monitoring
  - Raxol.MCP 2.4.0 - MCP protocol support
  - Raxol.Plugin 2.4.0 - Plugin system

**Database:**
- Ecto 3.13.5 - Database abstraction layer
- EctoSQL 3.13.5 - SQL support for Ecto
- Postgrex 0.22.0 - PostgreSQL driver

**Job Queue:**
- Oban 2.21.1 - Job queue system (installed but not currently configured)

**Markup/Rendering:**
- Mdex 0.12.1 - Markdown parser and renderer with syntax highlighting (via Lumis/Rustler)
- Phoenix.HTML 4.3.0 - HTML generation utilities

**HTTP Client:**
- Req 0.5 (optional, referenced in Raxol deps) - HTTP client library

## Testing & Development

**Testing:**
- ExUnit (Elixir stdlib) - Test framework (via `mix test`)
- StreamData 1.3.0 - Property-based testing

**Code Quality:**
- Credo 1.7.18 - Static analysis (linting)
- Dialyxir 1.4.7 - Type checking via Dialyzer
- Sobelow 0.14.1 - Security-focused static analysis

## Key Dependencies

**Critical:**
- postgrex 0.22.0 - PostgreSQL driver; required for Repo operations
- argon2_elixir 4.1.3 - Password hashing via Argon2; handles user authentication in `FogletBbs.Accounts`
- json 1.4.4 - JSON encoding/decoding; used by Phoenix for API responses

**Infrastructure:**
- dns_cluster 0.2.0 - DNS-based clustering for distributed deployments
- bandit 1.10.4 - HTTP server adapter (replaces Cowboy); Plug-compatible
- telemetry 1.4.1 - Metrics and observability hooks
- telemetry_metrics 1.1.0 - Metrics collection
- telemetry_poller 1.3.0 - Periodic metrics sampling

**Security & Auth:**
- comeonin 5.5.1 - Dependency of argon2_elixir; password handling utilities
- plug_crypto 2.1.1 - Encryption and signing utilities

**Utilities:**
- gettext 1.0.2 - Internationalization (i18n)
- uuid 1.1.8 - UUID generation
- toml 0.7.0 - TOML parsing
- yaml_elixir 2.12.1 - YAML parsing (for Raxol config)
- circular_buffer 1.0.0 - Circular buffer data structure (used by Raxol)
- clipboard 0.2.1 - Clipboard integration (TUI feature)

**Build & Compilation:**
- elixir_make 0.9.0 - Build support for native extensions
- rustler_precompiled 0.9.0 - Precompiled Rust bindings (mdex syntax highlighting)

## Configuration

**Environment:**
- Configured via `config/*.exs` files with environment-specific overrides
- Runtime config via `config/runtime.exs` for secrets and deployment parameters
- ETS cache initialization for runtime config (see `FogletBbs.Config`)

**Key Configuration Files:**
- `config/config.exs` - Base configuration; Ecto, Phoenix endpoint, Raxol features
- `config/dev.exs` - Development database (PostgreSQL localhost), live reload settings
- `config/prod.exs` - Force SSL, HSTS headers
- `config/runtime.exs` - Production runtime secrets (DATABASE_URL, SECRET_KEY_BASE, PORT, SSH_PORT, SENTRY_DSN)
- `config/test.exs` - Test-specific settings
- `.env.example` - Environment variable template for development

**Database Configuration:**
- Development: `foglet_bbs_dev` database on localhost via Postgrex
- Production: DATABASE_URL from environment (format: `ecto://USER:PASS@HOST/DATABASE`)
- Connection pooling: 10 in dev, configurable in prod (POOL_SIZE env var)
- IPv6 support via ECTO_IPV6 env var

## Platform Requirements

**Development:**
- Elixir 1.19.5 with OTP 28.3.1 (enforced via `.tool-versions`)
- PostgreSQL (development uses localhost)
- Mix (comes with Elixir)

**Production:**
- Elixir 1.19.5 with OTP 28.3.1
- PostgreSQL 9.5+ (typical Phoenix requirement)
- Environment variables: DATABASE_URL, SECRET_KEY_BASE, PHX_HOST (required); PORT, POOL_SIZE, SSH_PORT, SENTRY_DSN (optional)
- Deployment via `mix release` or direct `mix phx.server`
- SSH daemon (optional, disabled by setting `start_ssh_daemon: false`)

## Build & Deployment

**Release:**
- Standard Phoenix release via `mix release`
- Bandit web server (built-in, no need for external Cowboy setup)

**Aliases:**
- `mix setup` - Install deps, create DB, migrate, configure git hooks
- `mix ecto.setup` - Create, migrate, seed database
- `mix ecto.reset` - Drop and recreate database
- `mix test` - Run tests with automatic DB setup
- `mix precommit` - Run full quality checks (compile --warnings-as-errors, format, credo --strict, sobelow, dialyzer)

## Asset Pipeline

**No JavaScript Build Pipeline:**
- No assets/package.json or Node.js tooling
- TUI delivered via Raxol terminal framework (server-rendered over SSH)
- Web interface (if any) uses server-rendered HTML via Phoenix templates

## Observability

**Telemetry:**
- Telemetry events emitted via telemetry library
- Metrics collection via telemetry_metrics
- Live Dashboard available at development routes (`/dashboard`)

**Error Tracking (Future):**
- SENTRY_DSN env var in runtime.exs but not yet integrated (milestone 10+)

**Logging:**
- Elixir Logger with default formatter
- Development: `[$level] $message` format at `:info` level
- Production: `:info` level, no metadata
- Request IDs tracked in Phoenix request logging

---

*Stack analysis: 2026-04-22*
