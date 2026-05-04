<!-- generated-by: gsd-doc-writer -->
# Configuration

Foglet BBS uses a three-layer configuration model. Choose the layer that matches the change you are making — they are not interchangeable.

| Layer | Where it lives | When it applies | Who can change it |
|-------|----------------|-----------------|-------------------|
| Compile-time | `config/config.exs`, `config/dev.exs`, `config/prod.exs`, `config/test.exs` | Baked into the release; requires recompile to change | Developers (code review) |
| Deploy-time | `config/runtime.exs` (reads environment variables at boot) | Set per deployment; requires restart to change | Operators (env vars / secrets manager) |
| Runtime DB-backed | `configuration` table, accessed via `Foglet.Config` (ETS-cached) | Live; takes effect on next read after cache invalidation | Sysops (in-app, actor-aware) |

**Secrets policy:** Secrets (database URLs, `SECRET_KEY_BASE`, SMTP passwords, etc.) live in environment variables consumed by `config/runtime.exs`. They are **never** stored in the DB-backed `configuration` table. The runtime layer is for sysop-tunable behavior, not credentials.

## Layer 1 — Compile-time configuration

Files in `config/` are evaluated at compile time and frozen into the release. They control wiring that cannot change at runtime: which adapter Phoenix uses, which features Raxol enables, log formats, etc.

### `config/config.exs` — base configuration

| Key | Value | Notes |
|-----|-------|-------|
| `:foglet_bbs, :ecto_repos` | `[FogletBbs.Repo]` | Ecto repository list |
| `:foglet_bbs, :generators` | `timestamp_type: :utc_datetime, binary_id: true` | Generator defaults |
| `:foglet_bbs, FogletBbsWeb.Endpoint` | `adapter: Bandit.PhoenixAdapter`, `pubsub_server: FogletBbs.PubSub`, `live_view: [signing_salt: ...]` | Phoenix endpoint base |
| `:foglet_bbs, Foglet.Mailer` | `adapter: Swoosh.Adapters.Local` | Default mailer; production overrides at runtime |
| `:foglet_bbs, :ssh_port` | `2222` | Default SSH listen port |
| `:foglet_bbs, :start_ssh_daemon` | `true` | Whether the SSH daemon supervisor starts on boot |
| `:raxol, :features` | map | Enables/disables Raxol subsystems (`performance_monitoring: false` works around a Raxol 2.4.0 startup crash) |
| `:logger, :default_formatter` | `format: "$time $metadata[$level] $message\n"` | Log format |

### `config/dev.exs`

- `FogletBbs.Repo`: `username: "postgres"`, `password: "postgres"`, `hostname: "localhost"`, `database: "foglet_bbs_dev"`, `pool_size: 10`.
- `FogletBbsWeb.Endpoint`: binds to `127.0.0.1`, includes a default `secret_key_base` (development-only — overridden by `runtime.exs` if `DATABASE_URL`/etc. are set), `code_reloader: true`, `debug_errors: true`.
- `:foglet_bbs, :log_verify_codes` set to `true` — logs email verification codes to the console. **Compile-time flag, never set in prod/test.**
- `:logger, level: :info` — suppresses Raxol Buffer.Writer debug noise.
- `:foglet_bbs, dev_routes: true` — enables the LiveDashboard and Swoosh mailbox preview routes.

### `config/prod.exs`

- `FogletBbsWeb.Endpoint`: `force_ssl: [rewrite_on: [:x_forwarded_proto], exclude: [paths: ["/up"], hosts: ["localhost", "127.0.0.1"]]]`. Note that `:force_ssl` must be set at compile time.
- `:logger, level: :info` — no debug logs in production.

### `config/test.exs`

- `FogletBbs.Repo`: uses `Ecto.Adapters.SQL.Sandbox`, database name suffixed with `MIX_TEST_PARTITION` for partitioned CI runs, `pool_size: System.schedulers_online() * 2`.
- `FogletBbsWeb.Endpoint`: `port: 4002`, `server: false`, fixed test `secret_key_base`.
- `Foglet.Mailer` adapter is `Swoosh.Adapters.Test` (captures emails for assertions).
- `:foglet_bbs, :start_ssh_daemon` set to `false` — tests start the SSH supervisor explicitly via `start_supervised!/1` with test-specific options.
- `:argon2_elixir, t_cost: 1, m_cost: 8` — fast, deliberately insecure password hashing for tests only.

## Layer 2 — Deploy-time configuration (`config/runtime.exs`)

`config/runtime.exs` runs after compilation and before the supervision tree starts. It is the single place environment variables are read.

In `:dev`, `runtime.exs` first sources `.env.local` via `Dotenvy` and copies any new keys into the process environment (real env vars take precedence over file values).

### Environment variables

| Variable | Required | Default | Used in | Description |
|----------|----------|---------|---------|-------------|
| `DATABASE_URL` | **Required in `:prod`** (raises if missing); optional in `:dev` | — | `runtime.exs` | Ecto repo URL, e.g. `ecto://USER:PASS@HOST/DATABASE` |
| `SECRET_KEY_BASE` | **Required in `:prod`** (raises if missing) | — | `runtime.exs` | Cookie/token signing secret; generate with `mix phx.gen.secret` |
| `PHX_SERVER` | Optional | (unset) | `runtime.exs` | When set, configures the endpoint with `server: true` (used by `mix release` deployments) |
| `PHX_HOST` | Optional (`:prod`) | `"example.com"` | `runtime.exs` | Public hostname for the Phoenix endpoint URL |
| `PORT` | Optional | `4000` | `runtime.exs` | HTTP port for the Phoenix endpoint |
| `POOL_SIZE` | Optional (`:prod`) | `10` | `runtime.exs` | Ecto connection pool size |
| `ECTO_IPV6` | Optional (`:prod`) | (false) | `runtime.exs` | When `"true"` or `"1"`, adds `:inet6` to the Repo socket options |
| `DNS_CLUSTER_QUERY` | Optional (`:prod`) | (unset) | `runtime.exs` | DNS query string for libcluster-style discovery (`:foglet_bbs, :dns_cluster_query`) |
| `FOGLET_SSH_PORT` | Optional | `2222` (compile-time default) | `runtime.exs` | Overrides `:foglet_bbs, :ssh_port` in any environment |
| `FOGLET_GUEST_MODE_ENABLED` | Optional | enabled / `true` | `runtime.exs` | Expected FOG-583 boot-time override for Guest Mode. Use false-like values to close read-only guest browsing for that boot; if your build has not wired this env var yet, use the DB-backed `guest_mode_enabled` setting instead. |
| `SSH_HOST_KEY_DIR` | Optional (`:prod`) | `"priv/ssh"` | `runtime.exs` | Directory containing SSH host key files (set under `:foglet_bbs, :ssh, host_key_dir`) |
| `FOGLET_MAIL_FROM` | Optional | (unset) | `runtime.exs` | Sets `:foglet_bbs, :mail_from` (envelope sender for outbound mail) |
| `FOGLET_SMTP_RELAY` or `FOGLET_SMTP_HOST` | Optional | (unset) | `runtime.exs` | When either is set, swaps `Foglet.Mailer` to `Swoosh.Adapters.SMTP` and applies the SMTP credentials below |
| `FOGLET_SMTP_PORT` | Optional (when SMTP enabled) | `587` | `runtime.exs` | SMTP port |
| `FOGLET_SMTP_USERNAME` | Optional (when SMTP enabled) | (unset) | `runtime.exs` | SMTP username |
| `FOGLET_SMTP_PASSWORD` | Optional (when SMTP enabled) | (unset) | `runtime.exs` | SMTP password |
| `FOGLET_SMTP_SSL` | Optional (when SMTP enabled) | (false) | `runtime.exs` | `"true"` or `"1"` enables implicit SSL |
| `FOGLET_SMTP_TLS` | Optional (when SMTP enabled) | `if_available` | `runtime.exs` | Atom passed to Swoosh: `always`, `never`, or `if_available` |
| `FOGLET_SMTP_AUTH` | Optional (when SMTP enabled) | `if_available` | `runtime.exs` | Atom passed to Swoosh: `always`, `never`, or `if_available` |
| `MIX_TEST_PARTITION` | Optional (test only) | (unset) | `config/test.exs` | Suffix appended to the test database name for partitioned CI |

### `.env.local` (development convenience)

In `:dev`, `runtime.exs` calls `Dotenvy.source([".env.local", System.get_env()])` and copies any keys it finds into the process environment. The file is optional. Real environment variables take precedence over file values.

<!-- VERIFY: a checked-in .env.local.example template — none was found in the repo root -->

### Mailer adapter selection

The mailer adapter is chosen by **layer**, not by a single config key:

- **Compile-time default** (`config/config.exs`): `Foglet.Mailer` uses `Swoosh.Adapters.Local`. Outbound mail is captured in the local mailbox and visible at `/dev/mailbox` when `dev_routes` is enabled.
- **Test override** (`config/test.exs`): `Swoosh.Adapters.Test`. Mail is captured in-process for assertions.
- **Runtime override** (`config/runtime.exs`): If `FOGLET_SMTP_RELAY` or `FOGLET_SMTP_HOST` is set, the adapter is swapped to `Swoosh.Adapters.SMTP` with the credentials shown in the table above. This is the production path.

The runtime DB-backed key `delivery_mode` (see Layer 3) is a separate, orthogonal switch: it controls whether the application **attempts** to send mail at all, regardless of which Swoosh adapter is wired up. With `delivery_mode = "no_email"`, code paths in `Foglet.Accounts.Verification`, password reset, and related flows short-circuit before calling `Foglet.Mailer.deliver/1`.

### SSH host keys

The SSH daemon expects a host key in the directory referenced by `:foglet_bbs, :ssh, host_key_dir` (default `"priv/ssh"`, overridable via `SSH_HOST_KEY_DIR`). Erlang's `:ssh_file.host_key/2` is invoked via `Foglet.SSH.KeyCB`; it looks for one of the standard host key filenames (`ssh_host_ed25519_key`, `ssh_host_rsa_key`, etc.) — see `lib/foglet_bbs/ssh/host_key.ex` and `lib/foglet_bbs/ssh/daemon_owner.ex` for the exact list.

The repository ships `priv/ssh/ssh_host_ed25519_key` and its `.pub` companion for development. **Production deployments should provide their own host key**, mounted into the directory referenced by `SSH_HOST_KEY_DIR`. Treat the host key as a secret (filesystem permissions, secrets manager, etc.).

<!-- VERIFY: the procedure your deployment platform uses to mount the SSH host key files into the running container/release -->

## Layer 3 — Runtime DB-backed configuration (`Foglet.Config`)

`Foglet.Config` is a read-through ETS cache (`:foglet_config` table) over the `configuration` Postgres table. Sysops change these values live without a restart; the next read after a write sees the new value.

See `docs/DATA_MODEL.md` §11 for the schema-level narrative.

### API

All functions live in `Foglet.Config`:

| Function | Purpose | Failure modes |
|----------|---------|---------------|
| `get!(key)` | Read a value; raises `Ecto.NoResultsError` if the key is not in the DB | Re-raises DB errors |
| `get(key, default)` | Read a value; returns `default` on missing key | Re-raises DB errors |
| `fetch(key)` | Stdlib-shaped lookup; returns `{:ok, value}` or `:error` on miss | Re-raises DB errors |
| `put!(key, value, updated_by_id \\ nil)` | **Trusted** writer for seeds, Mix tasks, test setup. Raises `Foglet.Config.UnknownKeyError` or `Foglet.Config.InvalidValueError` on schema violations. Pass `nil` for non-actor paths. | Raises on validation/DB errors |
| `put(actor, key, value)` | **Actor-aware** writer for interactive callers (sysop TUI, future API). Returns tagged tuples; never raises. Requires `Bodyguard.permit(Foglet.Authorization, :edit_config, actor, :site)`. | `{:error, :forbidden \| :unknown_key \| :invalid_value \| :db_error}` |
| `invalidate(key)` | Drop the key from ETS so the next read re-queries the DB | — |
| `init_cache/0` | Idempotently create the ETS table; called from `FogletBbs.Application.start/2` | — |

Reads stay permissive (no schema check) because rows on the `configuration` table may pre-date the schema. Writes via `put!/3` and `put/3` always validate against `Foglet.Config.Schema` before touching the DB or ETS — failed validations leave both untouched.

### Typed accessors

Prefer the typed accessor over a raw `get!/1` call so callers get a stable function name, dialyzer types, and a docstring linking back to the spec:

| Accessor | Returns |
|----------|---------|
| `registration_mode/0` | `String.t()` |
| `invite_code_generators/0` | `String.t()` |
| `max_post_length/0` | `integer()` |
| `max_thread_title_length/0` | `integer()` |
| `delivery_mode/0` | `String.t()` |
| `require_email_verification?/0` | `boolean()` |
| `guest_mode_enabled?/0` | `boolean()` |
| `email_verify_resend_cooldown_seconds/0` | `integer()` |
| `invite_generation_per_user_limit/0` | `non_neg_integer()` |

### Schematized keys (`Foglet.Config.Schema`)

These keys are the currently-seeded, validated configuration surface. `Schema` is a pure-data module (no Ecto/Repo dependency) so it can be loaded by tests and docs without booting the database layers.

| Key | Type | Default | Constraints | Description |
|-----|------|---------|-------------|-------------|
| `registration_mode` | string | `"open"` | enum: `open`, `invite_only`, `sysop_approved` | Account registration policy (D-02/D-03) |
| `invite_code_generators` | string | `"sysop_only"` | enum: `sysop_only`, `mods`, `any_user` | Who may generate invite codes (D-04) |
| `max_post_length` | integer | `8192` | min: 1 | Maximum post body length in characters (D-31) |
| `max_thread_title_length` | integer | `60` | min: 1 | Maximum thread title length (D-13) |
| `delivery_mode` | string | `"no_email"` | enum: `email`, `no_email` | Outbound transactional delivery mode (MAIL-01). When `"no_email"`, mail-sending code paths short-circuit. |
| `require_email_verification` | boolean | `false` | — | When false, new registrations skip verify; existing `confirmed_at: nil` users gain access on login (Phase 6 D-01). Cannot be `true` while `delivery_mode = "no_email"`. |
| `email_verify_resend_cooldown_seconds` | integer | `60` | min: 1 | Minimum seconds between resend-code presses on the Verify screen (Phase 6 D-02) |
| `invite_generation_per_user_limit` | integer | `0` | min: 0 | Per-user invite generation cap when `invite_code_generators = "any_user"` (INVT-07 D-04). `0` means unlimited. |
| `guest_mode_enabled` | boolean | `true` | — | Controls whether unauthenticated visitors can choose read-only guest browsing from the Login menu. |

`Schema.validate/2` returns `:ok`, `{:error, {:unknown_key, key}}`, or `{:error, %{reason: reason, expected: expected, got: value}}` where `reason` is one of `:type_mismatch`, `:not_in_enum`, `:below_min`, `:above_max`. The `:above_max` clause is reserved for future keys with maximum bounds — no current key uses it.

### Adding a new schematized key

1. Add the entry to `@entries` in `lib/foglet_bbs/config/schema.ex` (key, type, default, description, optional `enum` / `min` / `max`).
2. Seed the default value in `priv/repo/seeds.exs`.
3. Add a typed accessor on `Foglet.Config` that calls `get!/1`.
4. Test validation, persistence, ETS cache invalidation, and any consuming UI (sysop site form, etc.).

Do not scatter raw `Foglet.Config.get!/1` calls with string keys across the codebase — go through a typed accessor.

## Per-environment overrides

The standard layering applies in this order (later wins):

1. `config/config.exs` (always loaded)
2. `config/{dev,test,prod}.exs` (selected by `MIX_ENV`)
3. `config/runtime.exs` (env vars, runs at boot)
4. `Foglet.Config` writes (live, persisted in Postgres)

Common patterns:

- **Dev secrets locally:** put credentials in `.env.local` (gitignored). `Dotenvy` loads them in `:dev` only.
- **Prod secrets:** set the corresponding `FOGLET_*`, `DATABASE_URL`, `SECRET_KEY_BASE`, etc. in the deployment platform's secret manager.
- **Sysop-tunable behavior:** change via `Foglet.Config.put/3` from the sysop TUI screen (no restart, no env var, no deploy).

<!-- VERIFY: deployment platform-specific instructions for setting environment variables and secrets — these depend on the host (Fly.io / Railway / bare metal / etc.) and are not encoded in the repo -->
