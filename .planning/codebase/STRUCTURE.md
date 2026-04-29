# Codebase Structure

**Analysis Date:** 2026-04-29

## Directory Layout

```
foglet_bbs/
├── lib/
│   ├── foglet_bbs.ex                # Top-level domain placeholder module
│   ├── foglet_bbs_web.ex            # Phoenix web macros (router/controller/etc.)
│   ├── foglet_bbs/                  # Application + Foglet domain code
│   │   ├── application.ex           # OTP root supervisor
│   │   ├── repo.ex                  # FogletBbs.Repo (Ecto/Postgres)
│   │   ├── schema.ex                # Foglet.Schema — UUID PK/FK + usec timestamps
│   │   ├── mailer.ex                # Swoosh mailer
│   │   ├── pub_sub.ex               # Foglet.PubSub topic constructors
│   │   ├── markdown.ex              # mdex-backed markdown renderer
│   │   ├── time_ago.ex              # Relative-time formatter
│   │   ├── query_helpers.ex         # Shared Ecto query helpers (not_archived/1, etc.)
│   │   ├── posting_policy.ex        # Pure can_post?/2 predicates
│   │   ├── mix_task_helpers.ex      # Shared helpers for foglet.* Mix tasks
│   │   ├── release.ex               # Release migration entrypoint
│   │   ├── authorization.ex         # Bodyguard.Policy
│   │   ├── accounts.ex              # Accounts context
│   │   ├── accounts/                # Account schemas + auth/verification/invites
│   │   ├── boards.ex                # Boards context
│   │   ├── boards/                  # Board schemas + Server + Supervisor
│   │   ├── threads.ex               # Threads context
│   │   ├── threads/                 # Thread schemas + entry/read pointer
│   │   ├── posts.ex                 # Posts context
│   │   ├── posts/                   # Post + Edit + Upvote schemas
│   │   ├── moderation.ex            # Moderation context
│   │   ├── moderation/              # ModAction schema
│   │   ├── oneliners.ex             # Oneliners context
│   │   ├── oneliners/               # Oneliner schemas
│   │   ├── config.ex                # Foglet.Config (ETS-backed runtime config)
│   │   ├── config/                  # Config.Entry, Schema, error structs
│   │   ├── sessions/                # Sessions Supervisor + Session GenServer + Preferences
│   │   ├── ssh/                     # SSH supervisor, daemon owner, CLIHandler, key CBs
│   │   └── tui/                     # Raxol app, screens, widgets, pubsub forwarder
│   ├── foglet_bbs_web/              # Phoenix infrastructure (no end-user UI)
│   │   ├── endpoint.ex
│   │   ├── router.ex
│   │   ├── telemetry.ex
│   │   ├── gettext.ex
│   │   └── controllers/             # PageController, HealthController, error_json
│   └── mix/
│       └── tasks/                   # foglet.* Mix tasks (operator + dev)
├── test/
│   ├── test_helper.exs
│   ├── support/                     # ConnCase, DataCase, fixtures, fakes
│   ├── foglet_bbs/                  # Mirrors lib/foglet_bbs/ for context tests
│   │   ├── tui/
│   │   │   ├── render_snapshots/
│   │   │   ├── screens/
│   │   │   ├── widgets/
│   │   │   └── *_test.exs
│   │   ├── boards/, threads/, posts/, accounts/, sessions/, ssh/, config/, …
│   │   └── *_test.exs               # Context-level tests
│   ├── foglet/                      # Cross-cutting tests not tied to one context
│   └── foglet_bbs_web/
│       └── controllers/
├── priv/
│   ├── repo/
│   │   ├── migrations/              # Timestamped Ecto migrations
│   │   ├── seeds.exs                # Top-level seed entry
│   │   └── seeds/                   # Modular seed scripts (e.g., config.exs)
│   ├── ssh/                         # Persisted ed25519 host keys
│   ├── gettext/
│   └── static/
├── config/
│   ├── config.exs                   # Compile-time config
│   ├── dev.exs / prod.exs / test.exs
│   └── runtime.exs                  # FOGLET_* env-driven runtime config
├── docs/
│   ├── ARCHITECTURE.md
│   ├── DATA_MODEL.md
│   ├── CONFIGURATION.md
│   ├── DEPLOYMENT.md
│   ├── DEVELOPMENT.md
│   ├── GETTING-STARTED.md
│   ├── ROADMAP.md
│   ├── TESTING.md
│   └── raxol/                       # Raxol-specific notes & widget gallery
├── vendor/
│   └── raxol/                       # Path-vendored Raxol fork (mix dep)
├── rel/                             # Release tooling
├── .planning/                       # GSD planning + codebase docs
├── mix.exs
├── mix.lock
├── Dockerfile
├── docker-compose.yml
├── fly.toml
├── AGENTS.md                        # Symlinked from CLAUDE.md
└── README.md
```

## Directory Purposes

**`lib/foglet_bbs/`:**
- Purpose: The application — Foglet domain code plus the OTP application module.
- Contains: `Foglet.*` contexts and supporting modules; `FogletBbs.Application`, `FogletBbs.Repo`.
- Key files: `application.ex` (supervision tree), `repo.ex`, `schema.ex`, `pub_sub.ex`, `authorization.ex`, every `<context>.ex`.

**`lib/foglet_bbs/<context>/`:**
- Purpose: Per-context schemas, helpers, and (for Boards/Sessions) GenServers + supervisors.
- Examples: `boards/board.ex`, `boards/category.ex`, `boards/server.ex`, `boards/supervisor.ex`, `boards/subscription.ex`, `boards/read_pointer.ex`.
- Pattern: One `<context>.ex` public-API module + a `<context>/` directory of schemas/helpers/processes. Naming mirrors the context's pluralisation (`accounts/`, `boards/`, `threads/`, `posts/`).

**`lib/foglet_bbs/tui/`:**
- Purpose: Raxol application, screens, widgets, and runtime glue.
- Contains: `app.ex` (the conductor), `screens/` (one module per screen plus a sibling `state.ex` for complex screens), `widgets/` (reusable display primitives organised by category — `chrome/`, `composer/`, `display/`, `input/`, `list/`, `modal/`, `post/`, `progress/`, `workspace/`, `shared/`, `sysop/`).
- Key files: `app.ex`, `effect.ex`, `theme.ex`, `pub_sub_forwarder.ex`, `screen.ex`, `session_context.ex`, `size_gate.ex`, `screens/SCREEN_CONTRACT.md`, `widgets/README.md`.

**`lib/foglet_bbs/ssh/`:**
- Purpose: SSH daemon supervision, key callbacks, channel handler.
- Key files: `supervisor.ex`, `daemon_owner.ex`, `cli_handler.ex`, `key_cb.ex`, `pubkey_stash.ex`, `host_key.ex`, `rate_limiter.ex`.

**`lib/foglet_bbs/sessions/`:**
- Purpose: Per-user session GenServer and supervisor.
- Key files: `supervisor.ex`, `session.ex`, `preferences.ex`.

**`lib/foglet_bbs_web/`:**
- Purpose: Phoenix infrastructure only — endpoint, router, controllers, telemetry, gettext.
- Contains: No LiveViews, no end-user pages. `PageController` is a placeholder; `HealthController` powers `/up`. LiveDashboard is mounted under `/dev/dashboard` in dev.
- Key files: `endpoint.ex`, `router.ex`, `telemetry.ex`, `controllers/page_controller.ex`, `controllers/health_controller.ex`.

**`lib/mix/tasks/`:**
- Purpose: Operator and developer Mix tasks.
- Key files: `foglet.user.create.ex`, `foglet.user.promote.ex`, `foglet.user.reset_password.ex`, `foglet.user.status.ex`, `foglet.user.verification_code.ex`, `foglet.board_subscriptions.ex`, `foglet.doctor.ex`, `foglet.tui.render.ex`.
- Naming: `foglet.<noun>.<verb>` convention (`mix foglet.user.create`).

**`test/foglet_bbs/`:**
- Purpose: Mirrors `lib/foglet_bbs/`. Test files are co-located by context.
- Pattern: `test/foglet_bbs/<context>/<unit>_test.exs`. TUI tests live under `test/foglet_bbs/tui/{screens,widgets}/`.
- Key files: `test/test_helper.exs`, `test/foglet_bbs/tui/layout_smoke_test.exs` (canonical visual-layout regression battery), `test/foglet_bbs/tui/app_test.exs` (the App reducer's contract).

**`test/support/`:**
- Purpose: ExUnit case helpers and shared fixtures.
- Compiled only in `:test`: `mix.exs:38` (`elixirc_paths(:test)` adds `"test/support"`).
- Key files: `data_case.ex` (sandboxed Repo case), `conn_case.ex` (Phoenix conn), `accounts_fixtures.ex`, `boards_fixtures.ex`, `fake_accounts.ex`, `fake_moderation.ex`, `fake_oneliners.ex`.

**`priv/repo/migrations/`:**
- Purpose: All Ecto migrations.
- Naming: `YYYYMMDDHHMMSS_<snake_case_description>.exs` (generated by `rtk mix ecto.gen.migration`).
- Pattern: One migration per logical change; never edit a committed migration.

**`priv/repo/seeds*`:**
- Purpose: Seed scripts. `seeds.exs` is the entry; `seeds/config.exs` is loaded specifically by the `test` alias (see `mix.exs:88`).

**`priv/ssh/`:**
- Purpose: Persisted SSH host keys (`ssh_host_ed25519_key`, `ssh_host_ed25519_key.pub`). Generated on first boot by `Foglet.SSH.HostKey.ensure!/1` and committed across deploys.

**`priv/static/`, `priv/gettext/`:**
- Purpose: Static assets for Phoenix and gettext PO files. Minimal — there is no end-user web UI.

**`config/`:**
- Purpose: Mix-managed application config.
- `config.exs`: compile-time defaults shared across envs.
- `dev.exs` / `prod.exs` / `test.exs`: per-env overrides.
- `runtime.exs`: production runtime config sourced from `FOGLET_*` env vars (see `docs/CONFIGURATION.md`).

**`docs/`:**
- Purpose: Long-form architecture / data-model / configuration / deployment / testing references that contributors must consult before non-trivial changes.
- Key files: `DATA_MODEL.md` (schemas / migrations / persistence invariants), `ARCHITECTURE.md`, `CONFIGURATION.md`, `DEVELOPMENT.md`, `TESTING.md`, `DEPLOYMENT.md`, `ROADMAP.md`, `raxol/getting-started/WIDGET_GALLERY.md`.

**`vendor/raxol/`:**
- Purpose: Path-vendored Raxol terminal-UI fork. Referenced from `mix.exs:64` as `{:raxol, path: "vendor/raxol"}`.
- Generated: No (committed source).
- Committed: Yes.

**`.planning/`:**
- Purpose: GSD command planning artefacts (PROJECT.md, ROADMAP.md, STATE.md, phases/, codebase/).
- Generated: Yes (by `/gsd-*` commands). Committed.

**`rel/`:**
- Purpose: Release configuration consumed by `mix release` and the Dockerfile.

## Key File Locations

**Entry Points:**
- `lib/foglet_bbs/application.ex`: OTP `Application.start/2` — boots the full supervision tree.
- `lib/foglet_bbs/ssh/cli_handler.ex`: SSH channel handler — the per-connection entry point for the TUI.
- `lib/foglet_bbs/tui/app.ex`: Raxol application module — the per-channel UI runtime.
- `lib/foglet_bbs_web/endpoint.ex`: Phoenix HTTP entry point.
- `lib/mix/tasks/foglet.tui.render.ex`: Static TUI inspection entry point.

**Configuration:**
- `config/config.exs`, `config/runtime.exs`, `config/dev.exs`, `config/prod.exs`, `config/test.exs`: Mix config.
- `lib/foglet_bbs/config.ex` + `lib/foglet_bbs/config/schema.ex`: Runtime DB-backed config + validation.
- `.tool-versions`, `.formatter.exs`, `.credo.exs`, `.dialyzer_ignore.exs`, `.sobelow-conf`: Tool configs.
- `mix.exs`, `mix.lock`: Build / dependency manifest.

**Core Logic:**
- `lib/foglet_bbs/boards/server.ex`: Per-board single-writer GenServer (the message-number invariant).
- `lib/foglet_bbs/sessions/session.ex`: Per-user session GenServer.
- `lib/foglet_bbs/authorization.ex`: Bodyguard policy.
- `lib/foglet_bbs/<context>.ex`: Public API for each context.

**Persistence:**
- `lib/foglet_bbs/repo.ex`: Ecto repo.
- `lib/foglet_bbs/schema.ex`: Shared schema defaults.
- `priv/repo/migrations/`: All migrations.

**Testing:**
- `test/test_helper.exs`: ExUnit boot.
- `test/support/data_case.ex`, `test/support/conn_case.ex`: Case templates.
- `test/foglet_bbs/tui/layout_smoke_test.exs`: TUI visual-regression battery.

## Naming Conventions

**Files:**
- Elixir source: `snake_case.ex` matching the module (`Foglet.Boards.Server` → `lib/foglet_bbs/boards/server.ex`).
- Tests: `<unit>_test.exs` mirroring the source path under `test/foglet_bbs/`.
- Migrations: `YYYYMMDDHHMMSS_<snake_case>.exs` (timestamped, sortable).
- Mix tasks: `foglet.<noun>.<verb>.ex` (e.g., `foglet.user.create.ex`).

**Modules:**
- Domain: `Foglet.<Aggregate>` (singular for namespace, plural for context — `Foglet.Boards`, `Foglet.Threads`, `Foglet.Posts`, `Foglet.Accounts`).
- Phoenix infra: `FogletBbs.*` and `FogletBbsWeb.*` (the OTP app's name + `Web` suffix).
- TUI screens: `Foglet.TUI.Screens.<ScreenName>` with sibling `Foglet.TUI.Screens.<ScreenName>.State` when state warrants its own module.
- TUI widgets: `Foglet.TUI.Widgets.<Category>.<Widget>` (e.g., `Foglet.TUI.Widgets.Chrome.StatusBar`).
- Schemas: singular under their context (`Foglet.Boards.Board`, `Foglet.Posts.Post`).
- Mix tasks: `Mix.Tasks.Foglet.<Noun>.<Verb>` (matching the file).

**Functions:**
- `snake_case`. Predicates end in `?` (`can_post?/2`, `require_email_verification?/0`).
- Context query helpers: `list_*`, `get_*` (raises), `get_*_by_*`, `fetch_*` (`{:ok, _} | :error`).
- Bang variants for trusted internal callers: `put!/3`, `get!/1`.
- Scope helpers: `scope_for/1` on each context that owns an authorization scope.

**Topic Strings:**
- Built only by `Foglet.PubSub`: `user:<uid>`, `board:<bid>`, `thread:<tid>`, `boards`. Never inline.

**ETS Tables:**
- Named atoms owned by their module (`:foglet_config`, `Foglet.SSH.PubkeyStash`, `Foglet.SSH.CLIHandler.Counter`).

**Database:**
- Tables: plural `snake_case` (`users`, `boards`, `posts`, `thread_read_pointers`, `mod_actions`, `configuration`).
- Primary keys: UUID v7 via `Foglet.Schema`.
- Timestamps: `inserted_at` / `updated_at` as `utc_datetime_usec`.

## Where to Add New Code

**New domain context (e.g., `Foglet.Notifications`):**
- Public API: `lib/foglet_bbs/notifications.ex`.
- Schemas + helpers: `lib/foglet_bbs/notifications/`.
- Tests: `test/foglet_bbs/notifications/` (mirror lib path).
- Migration: `rtk mix ecto.gen.migration create_notifications` → `priv/repo/migrations/<ts>_create_notifications.exs`.
- Authorization: extend `lib/foglet_bbs/authorization.ex` if new operator actions are introduced.
- PubSub topic: add a constructor to `lib/foglet_bbs/pub_sub.ex`.

**New TUI screen:**
- Module: `lib/foglet_bbs/tui/screens/<screen_name>.ex` exposing `update/3` + `render/2` (and optionally `subscriptions/2`).
- Sibling state (when warranted): `lib/foglet_bbs/tui/screens/<screen_name>/state.ex`.
- Routing: extend the `@type screen` union and the route table in `lib/foglet_bbs/tui/app.ex`.
- Tests: `test/foglet_bbs/tui/screens/<screen_name>_test.exs`; layout snapshot in `test/foglet_bbs/tui/layout_smoke_test.exs`.
- Theme: route any colors through `Foglet.TUI.Theme`.

**New TUI widget:**
- Pick a category subdir under `lib/foglet_bbs/tui/widgets/<category>/`. Stateless widgets expose render functions; stateful widgets expose `init/1` + `handle_event/2` + `render/2`.
- Tests: `test/foglet_bbs/tui/widgets/<category>/<widget>_test.exs`.
- See `lib/foglet_bbs/tui/widgets/README.md` and `docs/raxol/getting-started/WIDGET_GALLERY.md` first.

**New runtime config key:**
- Schema: extend `lib/foglet_bbs/config/schema.ex` with the spec.
- Default: seed in `priv/repo/seeds/config.exs`.
- Typed accessor: add to `lib/foglet_bbs/config.ex` (e.g., `def my_key, do: get!("my_key")`).
- Test: `test/foglet_bbs/config_test.exs` validation + cache invalidation.

**New Mix task:**
- Module: `lib/mix/tasks/foglet.<noun>.<verb>.ex` defining `Mix.Tasks.Foglet.<Noun>.<Verb>` with `use Mix.Task`.
- Use shared helpers from `lib/foglet_bbs/mix_task_helpers.ex`.
- Tests under `test/foglet_bbs/` (mirror by feature, not by task name).

**New Phoenix endpoint surface:**
- HTTP routes: extend `lib/foglet_bbs_web/router.ex`.
- Controllers: `lib/foglet_bbs_web/controllers/<name>_controller.ex` (+ accompanying view module if HTML).
- **Before adding any end-user browser workflow**, update `docs/ARCHITECTURE.md` and `AGENTS.md` first — current product surface is SSH-only.

**New schema / migration:**
- Generate: `rtk mix ecto.gen.migration <snake_case_name>`.
- Schema: `lib/foglet_bbs/<context>/<schema>.ex` using `use Foglet.Schema`.
- Changeset: keep on the schema module; programmatically set FKs before `cast/3`.
- Fixtures: `test/support/<context>_fixtures.ex` (compile-only-in-test).
- Read `docs/DATA_MODEL.md` first.

**Shared helper used in 2+ contexts:**
- Place in a top-level `lib/foglet_bbs/<helper>.ex` (e.g., `query_helpers.ex`, `posting_policy.ex`, `time_ago.ex`, `markdown.ex`). Avoid creating a `lib/foglet_bbs/utils/` grab-bag.

## Special Directories

**`vendor/raxol/`:**
- Purpose: Path-vendored Raxol terminal-UI library (mix path dep).
- Generated: No.
- Committed: Yes.
- Editing rules: Generally treat as read-only; upstream patches go upstream first when feasible.

**`priv/ssh/`:**
- Purpose: Persisted Ed25519 host keys for the SSH daemon.
- Generated: First-boot via `Foglet.SSH.HostKey.ensure!/1`.
- Committed: Yes (so deploys retain a stable host fingerprint).

**`priv/repo/migrations/`:**
- Purpose: Ecto migration history.
- Generated: By `rtk mix ecto.gen.migration`.
- Committed: Yes; never edit committed migrations.

**`.planning/`:**
- Purpose: GSD command artefacts (PROJECT, ROADMAP, STATE, per-phase planning under `phases/<NN-name>/`, codebase maps under `codebase/`).
- Generated: By `/gsd-*` commands.
- Committed: Yes.

**`_build/`, `deps/`, `.elixir_ls/`:**
- Purpose: Mix build outputs, fetched dependencies, ElixirLS cache.
- Generated: Yes (`rtk mix deps.get` / `rtk mix compile`).
- Committed: No (`.gitignore`).

**`erl_crash.dump`:**
- Purpose: BEAM crash dump artifact (present at repo root from a prior crash).
- Generated: Yes (auto on BEAM crash).
- Committed: No — should be deleted/gitignored.

---

*Structure analysis: 2026-04-29*
