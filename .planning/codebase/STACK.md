# Technology Stack

**Analysis Date:** 2026-04-29

## Languages

**Primary:**
- Elixir `~> 1.17` (pinned at `1.19.5-otp-28` via `.tool-versions`) — application code, contexts, schemas, TUI, mix tasks
- Erlang/OTP `28.3.1` (pinned via `.tool-versions`; runtime asserts `>= 27.3.3` in `lib/foglet_bbs/ssh/supervisor.ex` to guard against CVE-2025-32433) — provides the `:ssh`, `:public_key`, and `:crypto` apps that Foglet builds the SSH daemon on top of

**Secondary:**
- HEEx / EEx — Phoenix templates under `lib/foglet_bbs_web/controllers/page_html/`
- SQL — Postgres-flavored migrations under `priv/repo/migrations/`
- Shell — pre-commit hook at `.githooks/pre-commit`

## Runtime

**Environment:**
- Erlang/OTP 28 BEAM VM, Elixir 1.19 release built via `mix release` (see `Dockerfile`, `rel/env.sh.eex`).
- Production runs as a Mix release named `foglet_bbs` on Debian Trixie slim images.
- Two listeners: SSH on TCP `2222` (front door) and Phoenix HTTP on `4000` (LiveDashboard, `/up` health, future structured clients).

**Package Manager:**
- Mix (built into Elixir).
- Lockfile: `mix.lock` is committed and authoritative. `mix deps.unlock --unused` is enforced as part of the `precommit` alias in `mix.exs`.

## Frameworks

**Core:**
- `:phoenix` `1.8.5` — endpoint, router, PubSub, telemetry plumbing (`lib/foglet_bbs_web/`). Per `AGENTS.md` Phoenix is infrastructure only; SSH/TUI is the product surface.
- `:phoenix_ecto` `4.7.0` — Ecto integration (CheckRepoStatus plug in `lib/foglet_bbs_web/endpoint.ex`).
- `:phoenix_live_dashboard` `0.8.7` — `/dev/dashboard` route in `lib/foglet_bbs_web/router.ex` (dev-only behind `dev_routes`).
- `:phoenix_live_view` `1.1.28` — pulled in transitively by LiveDashboard; not used for end-user UI.
- `:bandit` `1.10.4` — HTTP server adapter (`Bandit.PhoenixAdapter` set in `config/config.exs`).
- `:ecto` `3.13.5` / `:ecto_sql` `3.13.5` — schemas, changesets, migrations (`Foglet.Schema` is the shared base in `lib/foglet_bbs/schema.ex`).
- `:postgrex` (resolved through `mix.lock`) — Postgres driver.
- `:raxol` `2.4.0` (vendored at `vendor/raxol/`, pulled with `path:` in `mix.exs`) — terminal UI runtime that powers `Foglet.TUI.App`. Feature flags are configured in `config/config.exs` (database/web_interface/plugins/audit disabled; pubsub/terminal_driver/telemetry on).

**Testing:**
- ExUnit (built into Elixir) — see `test/test_helper.exs` and `test/support/`.
- `:stream_data` `1.3.0` (`only: [:dev, :test]`) — property-based testing.
- `Ecto.Adapters.SQL.Sandbox` — concurrent test isolation (`config/test.exs`).
- Swoosh `Swoosh.Adapters.Test` for mail assertions in tests (`config/test.exs`).
- Synthetic TUI fixtures: `lib/foglet_bbs/tui/render_fixtures.ex` (used by `mix foglet.tui.render`).

**Build/Dev:**
- `:dialyxir` `1.4.7` (`only: [:dev, :test]`) — Dialyzer wrapper. PLT cache is keyed in CI (`.github/workflows/ci.yml`). Ignore list: `.dialyzer_ignore.exs`. Flags: `[:error_handling, :underspecs, :unmatched_returns, :unknown]` (`mix.exs`).
- `:credo` `1.7.18` (`only: [:dev, :test]`) — strict static analysis driven by `.credo.exs`.
- `:sobelow` `0.13` — security-focused static analysis. Config: `.sobelow-conf`. Run with `--exit Low` in CI and precommit.
- `mix hex.audit` — runs in CI for advisory checks.
- `:dotenvy` `1.1.1` — loads `.env.local` at runtime in dev (see `config/runtime.exs`).
- Git pre-commit hook (`.githooks/pre-commit`) chains to `mix precommit`. Wired up by `mix setup` via `cmd git config core.hooksPath .githooks` (`mix.exs`).

## Key Dependencies

**Critical:**
- `:argon2_elixir` `4.1.3` — password hashing for `Foglet.Accounts.User`. Lowered cost in `config/test.exs` (`t_cost: 1, m_cost: 8`) for fast tests; production uses library defaults.
- `:bodyguard` `2.4.3` — policy authorization. Single policy module: `Foglet.Authorization` (`lib/foglet_bbs/authorization.ex`). Stable scope shapes are `:site` and `{:board, board_id}`.
- `:hammer` `7.3.0` — ETS-backed rate limiting. Used by `Foglet.SSH.RateLimiter` (`lib/foglet_bbs/ssh/rate_limiter.ex`) for per-IP SSH connection throttling (10 connections / 60s, fail-open on errors).
- `:oban` `2.21.1` — background job processing dependency listed in `mix.exs`. (No active Oban workers found in `lib/`; included for future use, not currently scheduled in `FogletBbs.Application`.)
- `:mdex` `0.12.1` — CommonMark parser used by `Foglet.Markdown` (`lib/foglet_bbs/markdown.ex`) to render post bodies into Raxol-friendly `{text, style}` tuples. Strips raw ANSI from user input.
- `:swoosh` `1.25.0` — outbound transactional mail (`Foglet.Mailer` in `lib/foglet_bbs/mailer.ex`, builders in `lib/foglet_bbs/accounts/email.ex`).
- `:gen_smtp` `1.3.0` — SMTP backend that pairs with `Swoosh.Adapters.SMTP` in production.
- `:timex` `3.7` — IANA timezone validation (`Timex.Timezone.exists?/1` is called at boot in `lib/foglet_bbs/application.ex`).
- `:bodyguard`, `:phoenix_ecto`, `:dns_cluster` `0.2.0` — DNS-based clustering wired into `FogletBbs.Application` via `DNS_CLUSTER_QUERY`.

**Infrastructure:**
- `:telemetry_metrics` `~> 1.0`, `:telemetry_poller` `~> 1.0` — VM/Phoenix/Repo metrics defined in `lib/foglet_bbs_web/telemetry.ex`.
- `:gettext` `1.0.2` — i18n backend at `lib/foglet_bbs_web/gettext.ex` (translations under `priv/gettext/`).
- `:jason` `1.4.4` — JSON encoder/decoder; configured as `phoenix.json_library` in `config/config.exs`.

## Configuration

**Environment:**
- Compile-time: `config/config.exs`, `config/dev.exs`, `config/prod.exs`, `config/test.exs`.
- Runtime: `config/runtime.exs` is the single place env vars are read (`PORT`, `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`, `ECTO_IPV6`, `POOL_SIZE`, `DNS_CLUSTER_QUERY`, `FOGLET_SSH_PORT`, `SSH_HOST_KEY_DIR`, `FOGLET_DEFAULT_TIMEZONE`, `FOGLET_MAIL_FROM`, `FOGLET_SMTP_*`).
- `.env.example` documents required/optional env vars. `.env.local` exists locally; loaded in dev via `Dotenvy.source/1` at runtime (real env wins). Never read in code paths outside `config/runtime.exs`.
- Database-backed runtime config: the `configuration` table fronted by `Foglet.Config` (read-through ETS cache, `lib/foglet_bbs/config.ex`). Schemas live under `lib/foglet_bbs/config/`. Seeded from `priv/repo/seeds/config.exs`.

**Build:**
- `mix.exs` — deps, aliases (`setup`, `ecto.setup`, `ecto.reset`, `test`, `precommit`).
- `.formatter.exs` — `import_deps: [:ecto, :ecto_sql, :phoenix]`, formats `config/`, `lib/`, `test/`, `priv/*/seeds.exs`, and migrations.
- `.credo.exs`, `.sobelow-conf`, `.dialyzer_ignore.exs`.
- `Dockerfile` (multi-stage Hex Elixir builder + Debian Trixie runner) and `.dockerignore`.
- `rel/env.sh.eex`, `rel/overlays/` — release tweaks.
- `fly.toml` — Fly.io deployment manifest.

## Platform Requirements

**Development:**
- Erlang/OTP `28.3.1`, Elixir `1.19.5` (managed via `asdf` / `mise` reading `.tool-versions`).
- Postgres 16 (provided by `docker-compose.yml`: `postgres:16` on `localhost:5432`, db `foglet_bbs_dev`).
- `mix setup` bootstraps deps, ecto, and the git hooks path.

**Production:**
- Fly.io app `foglet-bbs`, region `iad`, single VM with attached `foglet_data` volume mounted at `/data` (host SSH keys live in `/data/ssh`). See `fly.toml`.
- TLS terminated by Fly for HTTP (`force_https = true`); SSH exposed on Fly port `22` mapped to internal `2222`.
- Postgres provided by `fly postgres` cluster `foglet-bbs-db`; `DATABASE_URL` injected by `fly postgres attach`.
- Release migrations and config seeds run via `release_command` in `fly.toml` calling `Ecto.Migrator` and `priv/repo/seeds/config.exs`.
- CI: GitHub Actions `.github/workflows/ci.yml` runs format, compile (warnings-as-errors), credo, hex.audit, sobelow, dialyzer, test against an ephemeral Postgres 16 service.
- Deploy: `.github/workflows/fly-deploy.yml` triggers `flyctl deploy --remote-only` on push to the `prod` branch.

---

*Stack analysis: 2026-04-29*
