# Codebase Structure

**Analysis Date:** 2026-04-18

## Directory Layout

```
foglet_bbs/
├── .claude/                    # Project instructions and guidelines
├── .github/                    # GitHub workflows (empty, CI/CD placeholder)
├── .planning/                  # GSD planning output
│   └── codebase/              # Architecture docs (this directory)
├── config/                     # Environment-specific configuration
│   ├── config.exs             # Base configuration
│   ├── dev.exs                # Development overrides
│   ├── test.exs               # Test overrides
│   ├── prod.exs               # Production overrides
│   └── runtime.exs            # Runtime configuration (secrets, env vars)
├── docs/                       # Project documentation
│   └── DATA_MODEL.md          # Data model overview
├── lib/                        # Application source code
│   ├── foglet_bbs/            # Core business logic
│   │   ├── application.ex     # OTP application entry point
│   │   └── repo.ex            # Ecto repository (database access)
│   ├── foglet_bbs_web/        # Web layer (HTTP, WebSockets)
│   │   ├── controllers/       # HTTP request handlers
│   │   │   └── error_json.ex # Error response formatting
│   │   ├── endpoint.ex        # Phoenix endpoint (HTTP server setup)
│   │   ├── router.ex          # HTTP routing
│   │   ├── telemetry.ex       # Metrics and observability
│   │   ├── gettext.ex         # Internationalization support
│   │   └── foglet_bbs_web.ex # Web layer macro definitions
│   ├── foglet_bbs.ex          # Core application documentation
│   └── mix/
│       └── tasks/
│           └── foglet.doctor.ex # Development environment verification
├── priv/                       # Private assets and runtime files
│   ├── gettext/               # Translation files
│   │   └── en/LC_MESSAGES/    # English translations
│   ├── repo/                  # Database migrations and seeds
│   │   ├── migrations/        # Database migration files (empty)
│   │   └── seeds.exs          # Seed data (empty)
│   └── static/                # Static assets served to clients
│       ├── favicon.ico
│       └── robots.txt
├── test/                       # Test files
│   ├── foglet_bbs_web/
│   │   └── controllers/
│   │       └── error_json_test.exs # Error handling tests
│   └── test_helper.exs        # Test configuration
├── .credo.exs                 # Code linting rules
├── .env.example               # Environment variables template
├── .formatter.exs             # Code formatter configuration
├── .gitignore                 # Git ignore rules
├── .tool-versions             # asdf version pinning
├── docker-compose.yml         # PostgreSQL dev container
├── mix.exs                    # Project definition and dependencies
├── mix.lock                   # Dependency lock file
├── CLAUDE.md                  # Project guidelines (Phoenix, Elixir, Ecto)
└── README.md                  # Project overview and feature roadmap
```

## Directory Purposes

**`lib/foglet_bbs/`:**
- Purpose: Core business logic and domain modeling
- Contains: Contexts (user auth, boards, threads, messages), schemas, database queries
- Key files: `application.ex` (OTP supervision), `repo.ex` (database)
- Current state: Minimal scaffolding; contexts not yet defined

**`lib/foglet_bbs_web/`:**
- Purpose: HTTP and WebSocket handling
- Contains: Router, controllers, channels, error handling, telemetry
- Key files: `endpoint.ex` (HTTP server), `router.ex` (routing), `telemetry.ex` (metrics)
- Current state: Framework setup complete; domain routes not yet defined

**`config/`:**
- Purpose: Application configuration
- Contains: Environment-specific settings (dev, test, prod) and runtime secrets
- Key files: `config.exs` (base), `runtime.exs` (secrets from env vars)
- Pattern: Configuration layered by environment; `runtime.exs` loads last for production

**`priv/repo/`:**
- Purpose: Database schema evolution and initial data
- Contains: Migration files and seed scripts
- Key files: `migrations/` (empty), `seeds.exs` (empty)
- Pattern: Migrations named with timestamps; one migration per feature

**`test/`:**
- Purpose: Automated test suite
- Contains: Unit tests, integration tests, test helpers
- Key files: `test_helper.exs` (ExUnit setup), `*_test.exs` (test files)
- Pattern: Tests co-located with source in `test/` mirror of `lib/`

**`priv/static/`:**
- Purpose: Served static assets
- Contains: Favicons, robots.txt, future CSS/JS
- Served by: `Plug.Static` middleware in endpoint

**`priv/gettext/`:**
- Purpose: Internationalization (translations)
- Contains: `.po` files with translations, `.pot` template
- Pattern: `priv/gettext/{language}/LC_MESSAGES/*.po`

**`lib/mix/tasks/`:**
- Purpose: Custom Mix tasks for project-specific commands
- Contains: `foglet.doctor` for environment verification
- Pattern: `Mix.Tasks.{Namespace}.{Command}` module naming

## Key File Locations

**Entry Points:**
- `lib/foglet_bbs/application.ex` - OTP application start point; defines supervision tree
- `lib/foglet_bbs_web/endpoint.ex` - HTTP server setup; request pipeline
- `lib/foglet_bbs_web/router.ex` - Route definitions for HTTP/WebSocket
- `mix.exs` - Project definition and dependency manifest

**Configuration:**
- `config/config.exs` - Base configuration (loaded by all environments)
- `config/runtime.exs` - Production-only secrets and env var loading
- `.env.example` - Template for required environment variables
- `.tool-versions` - Version pins for asdf (Elixir 1.19.5-otp-28, Erlang 28.3.1)

**Core Logic:**
- `lib/foglet_bbs/repo.ex` - Database connection and query interface
- `lib/foglet_bbs_web/telemetry.ex` - Metrics collection setup
- `lib/foglet_bbs_web/controllers/error_json.ex` - JSON error responses

**Testing:**
- `test/test_helper.exs` - ExUnit configuration; test database setup
- `config/test.exs` - Test-specific configuration (test database, endpoints)
- `test/foglet_bbs_web/controllers/error_json_test.exs` - Error handling tests

## Naming Conventions

**Files:**
- `snake_case.ex` for modules - e.g., `user_context.ex` for `FogletBbs.UserContext`
- `snake_case_test.exs` for tests - matches corresponding module file
- `schema_name.ex` for Ecto schemas - e.g., `user.ex` for `FogletBbs.User`

**Directories:**
- `lib/{app_name}/` for core application
- `lib/{app_name}_web/` for web layer
- `lib/{app_name}_web/{controllers,channels}/` for web components
- `test/{app_name}/{path_matching_lib}/` mirrors `lib/` structure

**Modules:**
- `FogletBbs.*` for core domains
- `FogletBbs.Repo` for database access
- `FogletBbsWeb.*` for HTTP/WebSocket handling
- `FogletBbsWeb.ErrorJSON` for error serialization

**Functions:**
- `snake_case` for all function names
- Public API functions exported without `_` prefix
- Private helper functions with `_` prefix or `defp`
- Query functions follow pattern: `list_*`, `get_*`, `create_*`, `update_*`, `delete_*`

**Variables:**
- `snake_case` for all variable names
- Pattern matching on tuples: `{:ok, data}` or `{:error, reason}`
- Struct updates preserve field naming (via Ecto)

## Where to Add New Code

**New Feature (e.g., user registration):**
- Primary code: `lib/foglet_bbs/users/user_context.ex` (public API)
- Schemas: `lib/foglet_bbs/users/user.ex` (Ecto schema)
- Tests: `test/foglet_bbs/users/user_context_test.exs`
- Routes (if HTTP): `lib/foglet_bbs_web/router.ex` (add route)
- Controller (if HTTP): `lib/foglet_bbs_web/controllers/user_controller.ex`
- Controller tests: `test/foglet_bbs_web/controllers/user_controller_test.exs`

**New Domain Context (e.g., `Boards`):**
- Directory structure:
  ```
  lib/foglet_bbs/boards/
  ├── board.ex           # Ecto schema
  ├── board_context.ex   # Public API
  └── queries/           # Internal query modules (optional)
  
  test/foglet_bbs/boards/
  └── board_context_test.exs
  ```

**New Web Component (channel, live view):**
- Channel: `lib/foglet_bbs_web/channels/{domain}_channel.ex`
- Channel tests: `test/foglet_bbs_web/channels/{domain}_channel_test.exs`
- Configuration: Add socket route in `lib/foglet_bbs_web/router.ex`

**Utilities & Helpers:**
- Shared helpers: `lib/foglet_bbs/helpers/` or domain-specific `lib/foglet_bbs/{domain}/helpers.ex`
- Web utilities: `lib/foglet_bbs_web/helpers/`
- Mix tasks: `lib/mix/tasks/foglet.{command}.ex`

**Migrations:**
- Create with: `mix ecto.gen.migration {migration_name}`
- Files placed in: `priv/repo/migrations/{timestamp}_{name}.exs`
- Pattern: One logical change per migration; reversible up/down

## Special Directories

**`_build/`:**
- Purpose: Compiled output and build artifacts
- Generated: Yes (created during `mix compile`)
- Committed: No (in `.gitignore`)

**`deps/`:**
- Purpose: External dependencies
- Generated: Yes (created during `mix deps.get`)
- Committed: No (in `.gitignore`)

**`.git/`:**
- Purpose: Git repository metadata
- Generated: Yes (created during `git init`)
- Committed: N/A

**`.planning/`:**
- Purpose: GSD orchestrator output
- Generated: Yes (created by `/gsd-map-codebase`)
- Committed: Yes (tracked in version control)

**`priv/ssh/`:**
- Purpose: SSH host keys for SSH daemon (Milestone 3+)
- Generated: Yes (created on first startup)
- Committed: No (sensitive, in `.gitignore`)

## Organization Patterns

**Context Directory Structure (emerging pattern):**
```
lib/foglet_bbs/{domain}/
├── {domain}_context.ex    # Public API (create, list, delete, etc.)
├── {schema}.ex            # Ecto schema
├── queries.ex             # Internal query helpers (optional)
└── helpers.ex             # Domain-specific utilities (optional)
```

**Web Layer Structure (established):**
```
lib/foglet_bbs_web/
├── controllers/           # HTTP request handlers
├── channels/              # WebSocket handlers (future)
├── router.ex              # All routes defined here
├── endpoint.ex            # HTTP server configuration
└── telemetry.ex           # Metrics collection
```

---

*Structure analysis: 2026-04-18*
