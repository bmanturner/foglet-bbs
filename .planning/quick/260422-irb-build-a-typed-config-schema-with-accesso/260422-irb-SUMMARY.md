---
quick_id: 260422-irb
phase: quick-260422-irb
plan: 01
status: complete
completed: 2026-04-22
duration_seconds: 581
tasks_completed: 3
tasks_total: 3
requirements: [260422-irb]
tags: [config, schema, validation, typed-accessors, elixir, ecto]
dependency_graph:
  requires: []
  provides:
    - "Foglet.Config.Schema (pure data source of truth for 6 schematized keys)"
    - "Foglet.Config.UnknownKeyError / Foglet.Config.InvalidValueError"
    - "Foglet.Config.fetch/1 ({:ok, value} | :error)"
    - "Foglet.Config strict put!/3 (Schema-validated)"
    - "Six typed accessors on Foglet.Config"
  affects:
    - "priv/repo/seeds.exs (config block regenerated from Schema)"
    - "lib/foglet_bbs/accounts.ex (post_login_screen/1 callsite)"
    - "lib/foglet_bbs/ssh/cli_handler.ex (build_context/3 callsites × 2)"
    - "lib/foglet_bbs/tui/screens/verify.ex (resend_cooldown_seconds/0 callsite)"
    - "docs/DATA_MODEL.md §11 (canonical snake_case note)"
    - "test/foglet_bbs/config_test.exs (rewritten against real schema keys)"
    - "test/foglet_bbs/accounts/accounts_test.exs (missing-key test updated)"
    - "test/foglet_bbs/tui/screens/verify_test.exs (missing-key test updated)"
tech_stack:
  added: []
  patterns:
    - "Plain-data schema module with @entries + derived @spec_map for O(1) lookup"
    - "defexception + @impl message/1 with reason-dispatch clauses"
    - "Map.fetch/2-shaped {:ok, value} | :error for structured missing-key checks"
    - "@type alias to keep Dialyzer success typings aligned with public @spec"
key_files:
  created:
    - "lib/foglet_bbs/config/schema.ex"
    - "lib/foglet_bbs/config/unknown_key_error.ex"
    - "lib/foglet_bbs/config/invalid_value_error.ex"
    - "test/foglet_bbs/config/schema_test.exs"
  modified:
    - "lib/foglet_bbs/config.ex"
    - "lib/foglet_bbs/accounts.ex"
    - "lib/foglet_bbs/ssh/cli_handler.ex"
    - "lib/foglet_bbs/tui/screens/verify.ex"
    - "priv/repo/seeds.exs"
    - "docs/DATA_MODEL.md"
    - "test/foglet_bbs/config_test.exs"
    - "test/foglet_bbs/accounts/accounts_test.exs"
    - "test/foglet_bbs/tui/screens/verify_test.exs"
decisions:
  - "fetch/1 returns {:ok, value} | :error (stdlib-canonical, per D-03/RESEARCH.md)"
  - "validate/2 error payload is a map (%{reason, expected, got}), not a keyword — lets put!/3 pattern-match without destructuring"
  - "Missing schema key = raise Ecto.NoResultsError (per D-03: seeds authoritative; permissive fallback removed)"
  - "@type entry/0 introduced so Dialyzer accepts entries/0 / fetch_spec/1 specs without a contract_supertype warning"
  - "DATA_MODEL.md §11 gains a pointer to Foglet.Config.Schema (planner Claude's-Discretion bullet taken)"
metrics:
  duration: "581s (~10 minutes)"
  completed: "2026-04-22"
---

# Quick Task 260422-irb: Typed Config Schema Summary

## One-liner

Established `Foglet.Config.Schema` as the pure-data source of truth for 6 runtime-editable sysop config keys, added strict `put!/3` validation with structured exceptions, introduced stdlib-canonical `fetch/1` (`{:ok, value} | :error`), exposed 6 typed accessors, regenerated `priv/repo/seeds.exs` from the schema, and migrated all 4 callsites off the permissive fallback paths.

## What Was Built

### 1. Pure-data schema layer (Task 1)

Three new files under `lib/foglet_bbs/config/`, one module per file per the project gotcha list:

- **`schema.ex`** — declares `@entries` (a compile-time literal list of 6 spec maps) plus a derived `@spec_map` for O(1) lookup. Public API: `entries/0`, `fetch_spec/1`, `defaults/0`, `validate/2`. `validate/2` returns `:ok | {:error, {:unknown_key, key}} | {:error, %{reason, expected, got}}` — the map shape avoids ugly keyword destructuring at the `put!/3` raise site. Zero Ecto/Repo deps, so the module is trivial to load from tests, docs, or IEx introspection. Includes a `@typedoc @type entry/0` alias that Dialyzer accepts as a match for the success typing of `@entries`.
- **`unknown_key_error.ex`** — `defexception [:key]` with `@impl message/1` pointing the reader at `Foglet.Config.Schema`.
- **`invalid_value_error.ex`** — `defexception [:key, :reason, :expected, :got]` with one `message/1` clause per reason atom (`:type_mismatch`, `:not_in_enum`, `:below_min`, `:above_max`). The `:above_max` clause is intentionally retained even though no current key uses it — reserved for future schematized keys with maximum bounds, documented in the moduledoc.

**Tests added:** `test/foglet_bbs/config/schema_test.exs` — 32 tests across `describe` blocks covering `entries/0`, per-key spec matches, `fetch_spec/1` shape, `defaults/0`, the full `validate/2` matrix (every bullet from the plan's `<behavior>` block), and `Exception.message/1` for all four `reason` atoms.

### 2. Foglet.Config integration (Task 2)

Additions to `lib/foglet_bbs/config.ex`:

- **`fetch/1`** — rescues `Ecto.NoResultsError` from `get!/1` to return `:error`, matching `Map.fetch/2 / Keyword.fetch/2 / Access.fetch/2`. Reuses `get!/1` so the ETS caching path is shared.
- **Validated `put!/3`** — runs `Schema.validate/2` before any DB or ETS work. Unknown keys raise `UnknownKeyError`; type/enum/range violations raise `InvalidValueError` with the full `{key, reason, expected, got}` payload. The DB is never touched on rejection. The existing ETS/DB logic moved verbatim into a private `do_put!/3`.
- **Six typed accessors** — `registration_mode/0`, `invite_code_generators/0`, `max_post_length/0`, `max_thread_title_length/0`, `require_email_verification?/0` (predicate `?` suffix per Elixir naming convention and D-04), `email_verify_resend_cooldown_seconds/0`. Each has `@spec + @doc`, and each is a one-liner that delegates to `get!/1`.

**Tests rewritten:** `test/foglet_bbs/config_test.exs` — 26 tests. Drops all `test.key.*` dot-form fixtures. Uses real schema keys (`registration_mode`, `max_post_length`, `require_email_verification`) for round-trip / cache / invalidation tests. Adds `describe "fetch/1"` (present + missing + cache-on-present), `describe "put!/3 validation"` (UnknownKeyError, type/enum/range InvalidValueError, DB-untouched-on-rejection), and `describe "typed accessors"` (one test per accessor, including `function_exported?` assertion on the `?`-suffixed name). Setup derives `@test_keys` from `Schema.defaults/0` so the ETS-invalidation isolation list stays in sync with the source of truth.

### 3. Wiring + gate (Task 3)

- **`priv/repo/seeds.exs`** — the inline 13-line `default_config` tuple list is replaced by a 14-line `Enum.each(Schema.entries(), ...)` block. Description-on-first-insert behaviour preserved exactly (D-07); re-seeding an already-seeded DB is still a no-op.
- **`lib/foglet_bbs/accounts.ex`** — `post_login_screen/1` calls `Foglet.Config.require_email_verification?()` directly.
- **`lib/foglet_bbs/ssh/cli_handler.ex`** — `build_context/3` drops the two `try ... rescue _ -> default end` paranoid fallbacks; calls `Foglet.Config.registration_mode()` and `Foglet.Config.max_post_length()` inline at the use sites. Net 13 lines removed.
- **`lib/foglet_bbs/tui/screens/verify.ex`** — `resend_cooldown_seconds/0` replaced the `case + guard` block with a single call to `Foglet.Config.email_verify_resend_cooldown_seconds()`. The `is_integer(n) and n > 0` guard is redundant — Schema's `min: 0` enforces the non-negative contract on writes, and the value flows only into `DateTime.add/3` (never a divisor).
- **`docs/DATA_MODEL.md` §11 line 686** — "aspirational and is deprecated" note replaced by "This is the canonical form." A blockquote pointer to `Foglet.Config.Schema` / typed accessors was added immediately after the seeded-keys list (planner's-discretion bullet taken).

## Precommit Gate Result

`mix precommit` passes end-to-end:

| Check | Result |
|---|---|
| `compile --warnings-as-errors` | Clean on Foglet-side modules (Raxol-vendored warnings are pre-existing and unchanged) |
| `format` | All 9 touched files formatted |
| `credo --strict` | 1171 mods/funs across 147 files, found no issues |
| `sobelow` | Scan complete, no findings |
| `dialyzer` | Total errors: 67, Skipped: 67, Unnecessary Skips: 0 — `done (passed successfully)` |

Full test suite: **885 tests, 0 failures** (1 property).

## Tests Added / Rewritten

| File | Added | Rewritten | Net |
|---|---|---|---|
| `test/foglet_bbs/config/schema_test.exs` | 32 | — | +32 (new file) |
| `test/foglet_bbs/config_test.exs` | +13 (fetch/1 + put!/3 validation + typed accessors) | 13 (cache tests migrated to real schema keys) | 26 total (was 10) |
| `test/foglet_bbs/accounts/accounts_test.exs` | — | 1 (missing-key test → asserts raise instead of :verify) | unchanged count |
| `test/foglet_bbs/tui/screens/verify_test.exs` | — | 1 (missing-key test → asserts raise instead of 60s default) | unchanged count |

## Deviations from Plan

### Auto-fixed issues

**1. [Rule 1 — Bug] Cross-test ETS leak in ConfigTest**
- **Found during:** Task 3 `mix test` full suite.
- **Issue:** `test/foglet_bbs/config/config_seed_test.exs` mutates `max_thread_title_length` to `300` and never invalidates the ETS entry on exit. Since `:foglet_config` is process-global (Ecto sandbox only rolls back the DB), the stale cached `300` survived into `Foglet.ConfigTest`'s typed-accessor test, which expects the seeded default `60`.
- **Fix:** Widened `Foglet.ConfigTest`'s `@test_keys` from a hand-curated 3-key list to `Map.keys(Schema.defaults())` — now all 6 schematized keys are ETS-invalidated in both `setup` and `on_exit`. This keeps the isolation list in sync with the source of truth and absorbs any future additions to the schema.
- **Commit:** `c7e9a91`.

**2. [Rule 1 — Bug] Tests asserted the old permissive-fallback contract that the migration intentionally removes**
- **Found during:** Task 3 `mix test` full suite.
- **Issue:** Two tests explicitly asserted the old "missing config key → silently falls back to a safe default" behaviour:
  - `test/foglet_bbs/accounts/accounts_test.exs:100` — "missing config key defaults to :verify for unconfirmed users".
  - `test/foglet_bbs/tui/screens/verify_test.exs:283` — "missing config key defaults resend cooldown to 60s".

  Both tests pre-dated the typed-accessor migration. Once `accounts.ex`/`verify.ex` switched to typed accessors (which call `get!/1` — raising on missing), the tests began exercising a contract that no longer exists.
- **Fix:** Rewrote each test to assert `Ecto.NoResultsError` is raised. Per the plan's Task 3 rationale (D-03, RESEARCH.md): a missing schema key now signals a mis-configured app — the raise is the correct loud failure mode. Added explanatory comments in each test referencing the quick-task ID so a future reader understands why the contract changed.
- **Commit:** `c7e9a91`.

**3. [Rule 3 — Blocking] Dialyzer contract_supertype on Schema.entries/0 / fetch_spec/1**
- **Found during:** Task 3 `mix precommit`.
- **Issue:** Dialyzer inferred the success typing of `@entries` as a highly narrowed literal union type (exact key strings, exact enum lists, exact default values). The declared `@spec entries() :: [map()]` is technically a supertype, which Dialyzer flags as `contract_supertype`.
- **Fix:** Introduced a module-level `@typedoc @type entry/0` capturing the documented shape (`%{key, type, default, description, enum, min, max}`) and updated both `entries/0` and `fetch_spec/1` specs to return `[entry()]` / `{:ok, entry()} | :error`. Dialyzer now accepts the specs without a warning, and public callers get a richer type to reason about. The plan's `<action>` block for Task 1 explicitly anticipated a credo/dialyzer note about exhaustiveness and allowed in-place remediation, so this is on-plan.
- **Commit:** `c7e9a91`.

### Planner-discretion choices taken

- Inlined `Foglet.Config.registration_mode()` / `.max_post_length()` directly into the `%{session_context: ...}` map literal in `cli_handler.ex` rather than retaining local `reg_mode =` / `max_post_length =` bindings — produced the smaller, more readable diff (net 13 lines removed).
- Added the optional `> Programmatic access: Foglet.Config.Schema ...` blockquote to `docs/DATA_MODEL.md` §11 (planner's-discretion bullet explicitly allowed).

## Commits

| Task | Hash | Type | Summary |
|---|---|---|---|
| 1 | `df9927b` | feat | add Foglet.Config.Schema + exception modules |
| 2 | `6953664` | feat | wire Schema into Foglet.Config |
| 3 | `c7e9a91` | refactor | seed from Schema + migrate callsites |

## Quick-task status: complete

All three tasks executed, all acceptance criteria met, `mix precommit` green, full test suite green (885 / 885), no known deferred issues.

## Self-Check: PASSED

- `lib/foglet_bbs/config/schema.ex` — exists
- `lib/foglet_bbs/config/unknown_key_error.ex` — exists
- `lib/foglet_bbs/config/invalid_value_error.ex` — exists
- `test/foglet_bbs/config/schema_test.exs` — exists
- Commit `df9927b` — in git log
- Commit `6953664` — in git log
- Commit `c7e9a91` — in git log
