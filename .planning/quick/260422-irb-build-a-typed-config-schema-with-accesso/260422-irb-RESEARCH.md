# Quick Task 260422-irb: Typed Config Schema — Research

**Researched:** 2026-04-22
**Domain:** Elixir/Phoenix runtime config with typed accessors and write-time validation
**Confidence:** HIGH

## Summary

The locked design in CONTEXT.md (plain data module for `Foglet.Config.Schema`, explicit typed accessors on `Foglet.Config`, `fetch/1` for structured missing-key checks, strict `put!/3` validation, custom exceptions) matches canonical Elixir naming conventions and stdlib patterns verbatim. No fundamental direction change is needed. This research nails down the exact shapes — `fetch/1` returns `{:ok, value} | :error` (not `{:error, :not_found}`), `defexception` uses a `message/1` callback for structured fields, and specs live in a compile-time list constructed from `@spec_definitions` that feed both `@entries` (runtime-accessible) and `@types` (for a map-based validator).

**Primary recommendation:** Build `Foglet.Config.Schema` as a module with a literal spec list compiled into `@entries` plus a `@spec_map` for O(1) `fetch_spec/1` lookup. Use `Map.fetch/2`-shaped `{:ok, value} | :error` for `Foglet.Config.fetch/1` (stdlib-canonical per the Elixir naming conventions doc). Use two `defexception` modules — `UnknownKeyError` and `InvalidValueError` — each with structured fields and a custom `message/1` callback. Test carve-out: Option B (rewrite the `test.key.*` fixtures to use a schematized test-only key or scope the cache tests against real schema keys); it's cleaner than maintaining a `put_raw!/3` escape hatch that would live only for tests.

## User Constraints (from CONTEXT.md)

### Locked Decisions

- **Canonical key form:** `snake_case` (matches DATA_MODEL.md §11, seeds, all callers).
- **Schema module shape:** Plain data module. `Foglet.Config.Schema` exposes a list of specs (`%{key, type, default, description, enum: nil, min: nil, max: nil}`) plus simple public functions (`entries/0`, `fetch_spec/1`, `validate/2`, `defaults/0`).
- **Typed accessors:** Explicit functions on `Foglet.Config` (one per key), not macro-generated. Pattern: `def registration_mode, do: get!("registration_mode")`.
- **Error contract:** Add `Foglet.Config.fetch/1` returning `{:ok, value} | {:error, :not_found}` per CONTEXT.md (but see Section "Error Contract" below — stdlib idiom is actually `:error`, not `{:error, :not_found}`; flagging this for planner). Keep `get!/1` (raises `Ecto.NoResultsError`) and `get/2` (returns default on missing).
- **Write validation:** Strict. `put!/3` validates against `fetch_spec/1`:
  - Unknown key → raise `Foglet.Config.UnknownKeyError`.
  - Type mismatch / constraint violation → raise `Foglet.Config.InvalidValueError` with structured fields.
- **Scope:** Only the 6 currently-seeded keys schematized. Aspirational keys deferred.
- **DATA_MODEL.md §11:** Drop the "`.` form deprecated" note on line 686.

### Claude's Discretion

- Exact shape of `Foglet.Config.Schema.validate/2` return: `:ok | {:error, reason}` vs raising. Recommend `:ok | {:error, reason}` so `put!/3` is the single raising surface (matches `Ecto.Changeset` split: the changeset stays pure, the `!` at the repo layer raises).
- Whether typed accessors cache a compile-time default when DB is absent. Recommend: **no**. `get!/1` raising is the correct signal that seeds haven't run.
- Module doc structure; `docs/ARCHITECTURE.md` pointer update at planner's discretion.

### Deferred Ideas (OUT OF SCOPE)

- Aspirational keys (`rate_limits_posts_per_day_new_user`, `archive_enabled`, `themes_available`, etc.).
- Runtime editor UI / sysop TUI for editing values.
- DB value migration (no key renames).
- Broader refactor of the 6 current call sites beyond swap-to-typed-accessor where it clarifies.

## Project Constraints (from CLAUDE.md)

- `mix precommit` is the authoritative gate (`compile --warnings-as-errors`, `format`, `credo --strict`, `sobelow`, `dialyzer`). Plans must make the code pass all of these.
- **No `String.to_atom/1` on external input.** The schema's `type` field and any enum lookups must stay as atoms hardcoded in source, not derived from user strings.
- **Block expressions rebind, don't mutate** — `if`/`case` inside `put!/3` must bind the whole expression.
- **Structs don't implement `Access`** — the schema struct (if used) must be accessed via `spec.field`, never `spec[:field]`.
- Never nest multiple modules in the same file — `Foglet.Config.Schema`, `Foglet.Config.UnknownKeyError`, and `Foglet.Config.InvalidValueError` each get their own file under `lib/foglet_bbs/config/`.

## Validation Approach Recommendation

**Use a plain compile-time list + a derived `@spec_map` for O(1) lookup.** Do **not** route validation through `Ecto.Changeset.cast/4` with a runtime-built types map.

### Why plain data wins over Ecto.Changeset routing

| Concern | Plain data (`@entries` + `@spec_map`) | Ecto.Changeset.cast/4 routing |
|---|---|---|
| Error messages | Custom `InvalidValueError` with `{key, expected, got, reason}` — formatted for sysops directly. | Changeset errors use `{"is invalid", [...]}` form, must be translated for a raise path. Adds a format step. |
| Coupling | Schema is pure data. Doc-generatable, introspectable, testable with zero deps. | Couples the Schema module to Ecto and to a runtime type map build per call. |
| Enum + range constraints | One `validate_value/2` function handles all constraints; 6 keys is trivial. | Need `validate_inclusion/3` and `validate_number/3` per field, assembled dynamically from the spec — more moving parts for the same outcome. |
| Recompile blast radius | Changing the spec list recompiles only `Foglet.Config.Schema`. | Same — but we've pulled in Ecto's validation module graph for nothing. |

**Source:** [Map.fetch/2 canonical pattern](https://hexdocs.pm/elixir/Map.html) `[CITED]` — the stdlib uses exactly this shape for typed lookup without an Ecto layer.

### Recommended validate/2 shape

```elixir
# lib/foglet_bbs/config/schema.ex
defmodule Foglet.Config.Schema do
  @moduledoc "Source of truth for runtime-editable config (see docs/DATA_MODEL.md §11)."

  @entries [
    %{
      key: "registration_mode",
      type: :string,
      default: "open",
      description: "Account registration policy (D-02/D-03): open | invite_only | sysop_approved",
      enum: ~w(open invite_only sysop_approved),
      min: nil,
      max: nil
    },
    # ... five more
  ]

  @spec_map Map.new(@entries, &{&1.key, &1})

  @spec entries() :: [map()]
  def entries, do: @entries

  @spec fetch_spec(String.t()) :: {:ok, map()} | :error
  def fetch_spec(key) when is_binary(key), do: Map.fetch(@spec_map, key)

  @spec defaults() :: %{optional(String.t()) => term()}
  def defaults, do: Map.new(@entries, &{&1.key, &1.default})

  @spec validate(String.t(), term()) :: :ok | {:error, term()}
  def validate(key, value) when is_binary(key) do
    case fetch_spec(key) do
      {:ok, spec} -> check(spec, value)
      :error -> {:error, {:unknown_key, key}}
    end
  end

  defp check(%{type: :string} = s, v) when is_binary(v), do: check_enum(s, v)
  defp check(%{type: :integer} = s, v) when is_integer(v), do: check_range(s, v)
  defp check(%{type: :boolean}, v) when is_boolean(v), do: :ok
  defp check(%{type: t}, v), do: {:error, {:type_mismatch, expected: t, got: v}}

  defp check_enum(%{enum: nil}, _), do: :ok
  defp check_enum(%{enum: allowed}, v) do
    if v in allowed, do: :ok, else: {:error, {:not_in_enum, expected: allowed, got: v}}
  end

  defp check_range(%{min: nil, max: nil}, _), do: :ok
  defp check_range(%{min: min}, v) when is_integer(min) and v < min,
    do: {:error, {:below_min, min: min, got: v}}
  defp check_range(%{max: max}, v) when is_integer(max) and v > max,
    do: {:error, {:above_max, max: max, got: v}}
  defp check_range(_, _), do: :ok
end
```

**Notes on the shape:**
- `@entries` is a literal list — the compiler evaluates it at compile time, and every read (`entries/0`) returns the same allocated list. Per [Elixir module-attribute docs](https://hexdocs.pm/elixir/Kernel.html) `[CITED]`, this is the idiomatic pattern for compile-time configuration inside a module.
- `@spec_map` is derived once at compile time from `@entries` via `Map.new/2`. O(1) `fetch_spec/1` without repeated list scans.
- Recompile-friendly: changing any spec re-evaluates both attributes; there's no runtime state to drift.
- Using plain maps (not a `defstruct`) sidesteps the CLAUDE.md gotcha about structs + Access.

## Error Contract Sketch

### fetch/1 return shape — **STDLIB CANON IS `:error`, NOT `{:error, :not_found}`**

**This diverges from CONTEXT.md's "Error contract" bullet.** Raising a flag for the planner/discuss-phase.

From [Elixir naming conventions](https://hexdocs.pm/elixir/naming-conventions.html) `[CITED: https://hexdocs.pm/elixir/naming-conventions.html]`:

> When you see the functions `get`, `fetch`, and `fetch!` for key-value data structures, you can expect the following behaviours:
> - `get` returns a default value (which itself defaults to `nil`) if the key is not present, or returns the requested value.
> - **`fetch` returns `:error` if the key is not present, or returns `{:ok, value}` if it is.**
> - `fetch!` raises if the key is not present, or returns the requested value.
>
> Examples: `Map.get/2`, `Map.fetch/2`, `Map.fetch!/2`, `Keyword.get/2`, `Keyword.fetch/2`, `Keyword.fetch!/2`

**`Map.fetch/2`, `Keyword.fetch/2`, `Access.fetch/2` all return `{:ok, value} | :error`** — not a tagged error tuple. CONTEXT.md's `{:error, :not_found}` is a reasonable project choice but it would be the first module in `lib/foglet_bbs/` to deviate from stdlib convention, which would surprise future callers and Dialyzer-literate reviewers.

**Recommendation (planner to confirm with user):** Match stdlib. Use `{:ok, value} | :error`. One-line callsite impact is the same (`case Config.fetch(key) do`), and it keeps us inside the guard rail that Elixir docs explicitly spell out.

If the project prefers tagged errors for internal consistency, document the divergence in the moduledoc so future readers don't assume Map-like semantics.

```elixir
@spec fetch(String.t()) :: {:ok, term()} | :error
def fetch(key) when is_binary(key) do
  {:ok, get!(key)}
rescue
  Ecto.NoResultsError -> :error
end
```

### Exception modules

Per [defexception docs](https://hexdocs.pm/elixir/Kernel.html) `[CITED]`, the canonical shape is `defexception [:fields]` plus a `message/1` callback for a structured exception. Two small modules, one per file:

```elixir
# lib/foglet_bbs/config/unknown_key_error.ex
defmodule Foglet.Config.UnknownKeyError do
  @moduledoc "Raised when Foglet.Config.put!/3 is called with a key not in Foglet.Config.Schema."
  defexception [:key]

  @impl true
  def message(%__MODULE__{key: key}) do
    "unknown config key #{inspect(key)} — add it to Foglet.Config.Schema or use Foglet.Config.Entry directly"
  end
end
```

```elixir
# lib/foglet_bbs/config/invalid_value_error.ex
defmodule Foglet.Config.InvalidValueError do
  @moduledoc "Raised when a config value fails schema validation."
  defexception [:key, :reason, :expected, :got]

  @impl true
  def message(%__MODULE__{key: key, reason: :type_mismatch, expected: expected, got: got}),
    do: "config #{inspect(key)} expected #{inspect(expected)}, got #{inspect(got)}"

  def message(%__MODULE__{key: key, reason: :not_in_enum, expected: allowed, got: got}),
    do: "config #{inspect(key)}=#{inspect(got)} is not one of #{inspect(allowed)}"

  def message(%__MODULE__{key: key, reason: :below_min, expected: min, got: got}),
    do: "config #{inspect(key)}=#{inspect(got)} is below minimum #{inspect(min)}"

  def message(%__MODULE__{key: key, reason: :above_max, expected: max, got: got}),
    do: "config #{inspect(key)}=#{inspect(got)} is above maximum #{inspect(max)}"
end
```

**Raise site in `Foglet.Config.put!/3`:**

```elixir
case Schema.validate(key, value) do
  :ok -> :ok
  {:error, {:unknown_key, ^key}} ->
    raise Foglet.Config.UnknownKeyError, key: key
  {:error, {reason, details}} ->
    raise Foglet.Config.InvalidValueError,
      key: key,
      reason: reason,
      expected: Keyword.get(details, :expected) || Keyword.get(details, :min) || Keyword.get(details, :max) || Keyword.get(details, :allowed),
      got: Keyword.fetch!(details, :got)
end
```

(Planner: the details-keyword destructuring is ugly; cleaner to have `Schema.validate/2` return already-shaped `%{key, reason, expected, got}` maps. Confirm in PLAN.)

## Typed Accessor Pattern Recommendation

**Explicit functions are correct for 6 keys.** Macro-generation would hide the `@spec` and `@doc` annotations behind metaprogramming for no gain. From [Elixir naming conventions](https://hexdocs.pm/elixir/naming-conventions.html) `[CITED]`: the `?`-suffix convention applies to predicate functions returning a boolean — use `require_email_verification?/0`, not `require_email_verification/0`.

Gotchas confirmed:
- **Dialyzer:** Plain functions with `@spec` generate clean specs. Macro-generated functions work but `@spec` attached via `unquote` has bitten projects before — sticking to hand-written definitions avoids the footgun.
- **ExDoc:** `@doc` above each function produces one module-page entry per accessor. With six keys, that's a clean API surface. Macro-generated funcs require `@doc` per generated function inside the macro, which is awkward.

```elixir
# lib/foglet_bbs/config.ex  (additions)
@doc "Account registration policy (D-02/D-03)."
@spec registration_mode() :: String.t()
def registration_mode, do: get!("registration_mode")

@doc "Whether new registrations must verify email before gaining access (Phase 6 D-01)."
@spec require_email_verification?() :: boolean()
def require_email_verification?, do: get!("require_email_verification")
```

For the other four: `invite_code_generators/0` (string), `max_post_length/0` (integer), `max_thread_title_length/0` (integer), `email_verify_resend_cooldown_seconds/0` (integer).

## Test Carve-Out Recommendation

**Recommend Option B (rewrite the fixtures) over Option A (internal `put_raw!/3`).**

The existing `test.key.string | test.key.integer | test.key.bool | test.key.missing` fixtures exist to exercise ETS cache behaviour (round-trip, invalidation-on-write, cache-staleness-before-invalidate). That behaviour is independent of schema validation. Two cleanish options for the rewrite:

**B1 — Use real schema keys for cache tests.** Each cache test uses one real schematized key (e.g., `"registration_mode"` for string, `"max_post_length"` for integer, `"require_email_verification"` for boolean). Pros: no API surface area added. Cons: test data mutates real seeded config; setup must reset to defaults after each test (easy in DataCase since Ecto sandbox rolls back).

**B2 — Add a `config_test_only` schematized key.** Add one key to `Foglet.Config.Schema` whose purpose is to give tests a mutable surface. Feels hacky; pollutes the production schema. **Avoid.**

**B3 (discard) — Option A, `put_raw!/3`.** Adding a private-but-callable escape hatch for tests is a code smell. Dialyzer + Credo will not flag it, but it expands the write surface forever for a narrow testing need.

**Recommendation: B1.** The Ecto sandbox already gives test isolation; reusing real schema keys is the smallest change and validates the full `put!/3 → ETS invalidation → DB` path that the tests already exercise.

Tests will also need new cases:
- `put!/3` with unknown key raises `Foglet.Config.UnknownKeyError`.
- `put!/3` with wrong type for a schema key raises `Foglet.Config.InvalidValueError`.
- `put!/3` with an invalid enum value raises `Foglet.Config.InvalidValueError`.
- `fetch/1` on missing key returns `:error` (or `{:error, :not_found}` depending on the planner's call).
- `fetch/1` on present key returns `{:ok, value}`.
- Each typed accessor returns the seeded default in a fresh DB.

## Seeds Regeneration Pattern Recommendation

**Put the helper in `priv/repo/seeds.exs`, not in `Foglet.Config.Schema`.**

`Foglet.Config.Schema` stays pure (no `Repo` or `Ecto` dependency). The seeds file is where side effects belong. Recommended block:

```elixir
# priv/repo/seeds.exs (replaces current default_config block lines 43-73)

alias Foglet.Config.Schema

Enum.each(Schema.entries(), fn spec ->
  %{key: key, default: default, description: description} = spec

  case Repo.get_by(Entry, key: key) do
    nil ->
      Config.put!(key, default, nil)

      # put!/3 doesn't touch description; set it on first insert
      Entry
      |> Repo.get_by!(key: key)
      |> Ecto.Changeset.change(%{description: description})
      |> Repo.update!()

      IO.puts("  [seed] inserted config #{key} = #{inspect(default)}")

    _existing ->
      IO.puts("  [seed] config #{key} already present")
  end
end)
```

**Why not in `Foglet.Config.Schema`:** keeping the schema module side-effect-free means it can be loaded by tests, docs, and any future read-only introspection tool without pulling in `Repo`. The moment you add `def seed!/0` to it, you either leak `Repo` as a dep or have to pass it in — both worse than keeping the 12-line helper inline in seeds.

**Alternative worth noting (planner may prefer):** A `Foglet.Config.Seeder` module under `lib/foglet_bbs/config/seeder.ex` that wraps the iteration. Pros: seedable from IEx for manual reset in dev. Cons: another module. For 12 lines of code used once, inline wins.

## Pitfalls and Gotchas

- **CONTEXT.md's `{:error, :not_found}` diverges from stdlib canon** (`Map.fetch`, `Keyword.fetch`, `Access.fetch` all return bare `:error`). See "Error Contract" section. Planner or discuss-phase should confirm with user before locking. `[CITED: https://hexdocs.pm/elixir/naming-conventions.html]`
- **`String.to_atom/1` trap:** Schema `type` values are atoms (`:string`, `:integer`, `:boolean`) hardcoded in source. Never derive them from user input. CLAUDE.md flags this explicitly and sobelow catches the obvious cases, but a lazy "convert the type field to atom for dispatch" helper is the shape this mistake takes.
- **Don't nest exception modules inside `Foglet.Config`** — CLAUDE.md gotcha about cyclic-deps. Each gets its own file.
- **Struct + Access gotcha:** If you change the spec shape from a map to a struct, callers doing `spec[:key]` break silently on Dialyzer-free code. Stick to maps unless there's a compelling reason to enforce field presence at compile time.
- **Block rebind:** `put!/3`'s validation case doesn't "mutate" — bind the whole validated-value expression, per CLAUDE.md.
- **`unique_constraint` in Entry.changeset:** Unchanged — still correct. New schema validation sits *above* the Ecto layer; Entry still guards key uniqueness at the DB level.
- **ETS table race on boot:** Already handled by `init_cache/0` idempotency. New accessors that call `get!/1` inherit this for free — no new race surface.
- **Seeds run order:** The config-block iteration must come *before* any code that reads config at seed time. Currently the block is at lines 43-73, before the board/thread seeds; keep that order.
- **Description drift:** `put!/3` intentionally doesn't touch `description`. Seeds set it on first insert only. If a sysop edits description in the DB later, re-seeding won't clobber it. This is load-bearing behaviour — don't "fix" it in the rewrite.
- **Dialyzer + explicit `@spec`:** Every new public function gets a `@spec`. Dialyzer is in `mix precommit` — missing specs on `Foglet.Config.fetch/1` or any typed accessor will fail CI.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|---|---|---|---|
| Spec declarations | `Foglet.Config.Schema` (pure data) | — | Single source of truth, no deps. |
| Validation logic | `Foglet.Config.Schema` (pure) | — | Returns `:ok | {:error, reason}`; no side effects. |
| DB persistence | `Foglet.Config.Entry` + Ecto | `FogletBbs.Repo` | Unchanged. |
| Cache + read-through | `Foglet.Config` (ETS) | — | Unchanged. |
| Raise-on-invalid-write | `Foglet.Config.put!/3` | `Foglet.Config.UnknownKeyError` / `InvalidValueError` | Single raising surface, per CONTEXT.md Claude's-discretion recommendation. |
| Structured missing check | `Foglet.Config.fetch/1` | — | `{:ok, value} | :error` (stdlib-canonical). |
| Typed accessors | `Foglet.Config` (explicit funcs) | — | Six hand-written funcs; no macros. |
| Seeding | `priv/repo/seeds.exs` | `Foglet.Config.Schema.entries/0` | Side effects stay in seeds. |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|---|---|---|
| — | No `[ASSUMED]` tags in this research. | — | — |

All recommendations are cited to Elixir's official naming-conventions, Kernel, Map, Access, and Application docs, or grounded in the files already read (`config.ex`, `entry.ex`, `seeds.exs`, `config_test.exs`, `DATA_MODEL.md`, `CLAUDE.md`).

## Open Questions

1. **`fetch/1` return shape divergence from stdlib.**
   - What we know: CONTEXT.md locks `{:ok, value} | {:error, :not_found}`; stdlib canon is `{:ok, value} | :error`.
   - What's unclear: Did the user intentionally pick the tagged-error shape, or was it an oversight?
   - Recommendation: Surface in discuss-phase or planner note. One-line effort either way; correcting later is a small breaking change but not risky.

2. **Test carve-out choice.** CONTEXT.md explicitly hands this to the planner. Research recommends B1 (reuse real schema keys) over A (`put_raw!/3`). Planner decides.

3. **Shape of `Schema.validate/2` error tuples.** The research sketches `{:error, {reason, keyword}}`. A cleaner shape is `{:error, %{reason: :type_mismatch, expected: :integer, got: "foo"}}` — one-line change, removes the ugly keyword-extract at the `put!/3` raise site. Planner to pick; doesn't change the plan's task count.

## Sources

### Primary (HIGH confidence)
- [Elixir Naming Conventions — `get`, `fetch`, `fetch!`](https://hexdocs.pm/elixir/naming-conventions.html) — canonical return shapes.
- [Map.fetch/2](https://hexdocs.pm/elixir/Map.html) — `{:ok, value} | :error` pattern confirmed.
- [Access.fetch/2](https://hexdocs.pm/elixir/Access.html) — same pattern for the behaviour-level interface.
- [Kernel.defexception/1](https://hexdocs.pm/elixir/Kernel.html) — `defexception [:fields]` + `exception/1` + `message/1` callback shape.
- [Exception callbacks](https://hexdocs.pm/elixir/Exception.html) — `message/1` is the right override for structured fields.
- [Application.compile_env/3 and module attributes](https://hexdocs.pm/elixir/Application.html) — confirms the `@entries` compile-time-list pattern is idiomatic for static config-inside-a-module.

### Local project sources
- `/Users/brendan.turner/Dev/personal/foglet_bbs/CLAUDE.md` — precommit gates, String.to_atom warning, structs-don't-implement-Access, block-rebind gotcha.
- `/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/config.ex` — current `get!`, `get`, `put!`, `init_cache`, `invalidate`.
- `/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/config/entry.ex` — Ecto schema unchanged by this task.
- `/Users/brendan.turner/Dev/personal/foglet_bbs/priv/repo/seeds.exs` lines 42-75 — current default_config loop, description-on-first-insert pattern.
- `/Users/brendan.turner/Dev/personal/foglet_bbs/test/foglet_bbs/config_test.exs` — `test.key.*` fixtures and ETS-cache-behaviour tests.
- `/Users/brendan.turner/Dev/personal/foglet_bbs/docs/DATA_MODEL.md` §11 lines 662-709 — key list and deprecated-note line 686.

## Metadata

- Standard stack: HIGH — all patterns cited to hexdocs.pm/elixir.
- Error contract: HIGH — naming conventions doc is explicit; `{:error, :not_found}` divergence is flagged for user confirmation.
- Test carve-out: MEDIUM — recommendation is sound but planner should confirm B1 doesn't conflict with any sandbox-sharing concern in `FogletBbs.DataCase`.
- Pitfalls: HIGH — all cited to CLAUDE.md or Elixir docs.

**Research date:** 2026-04-22
**Valid until:** Schema stable (Elixir 1.19 stdlib patterns don't drift).
