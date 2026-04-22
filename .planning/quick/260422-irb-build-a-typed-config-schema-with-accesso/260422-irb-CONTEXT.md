---
quick_id: 260422-irb
status: ready_for_planning
gathered: 2026-04-22
---

# Quick Task 260422-irb: Typed config schema with accessors and validation — Context

**Gathered:** 2026-04-22
**Status:** Ready for planning

<domain>
## Task Boundary

Build a typed config schema for `Foglet.Config` that serves as the single source of truth for runtime-editable sysop configuration. Today `Foglet.Config` is a good ETS read-through cache but is stringly-typed and permissive, and the error surface conflates "key missing" with "DB failed" when callers use `get/2` with a default.

**In scope:**
- `Foglet.Config.Schema` module — source of truth for the 6 currently-seeded keys (name, type, default, description, enum/range where applicable).
- Typed accessors (`Foglet.Config.registration_mode/0`, `Foglet.Config.max_post_length/0`, etc.).
- Write-time validation (`put!/3` validates against schema; unknown keys raise).
- `Foglet.Config.fetch/1` returning `{:ok, value} | :error` (stdlib-canonical, matches `Map.fetch/2`) so callers can distinguish "missing" from "DB down" (which still surfaces as an exception).
- Regenerate `priv/repo/seeds.exs` config block from the schema.
- Update `docs/DATA_MODEL.md` §11 to retire the "aspirational `.` form deprecated" note once snake_case is the clear canonical form.

**Out of scope:**
- Aspirational keys (rate_limits_posts_per_day_new_user, archive_enabled, themes_available, etc.) — schematize these in a later phase.
- Runtime editor UI / sysop TUI for editing values.
- Migration of DB values (no renames; we keep `registration_mode`, `max_post_length`, etc. as-is).
- Refactoring the 6 current call sites beyond swapping them to typed accessors where it clarifies intent.

**Existing touchpoints to honor:**
- `lib/foglet_bbs/config.ex` — current module with `get!/1`, `get/2`, `put!/3`, `invalidate/1`, `init_cache/0`.
- `lib/foglet_bbs/config/entry.ex` — Ecto schema for the `configuration` table (DB persistence layer, not touched except possibly the changeset's `validate_required`/`validate_length` rules).
- `priv/repo/seeds.exs:43-55` — current inline `default_config` list.
- Call sites: `lib/foglet_bbs/accounts.ex:172`, `lib/foglet_bbs/ssh/cli_handler.ex:340,347`, `lib/foglet_bbs/tui/screens/verify.ex:278`.
- Test file: `test/foglet_bbs/config_test.exs` currently uses dot-form test keys like `test.key.string` — these will be rewritten to use real schematized keys (e.g., `registration_mode`, `max_post_length`, `require_email_verification`) since strict validation will reject unknown keys on writes. Ecto sandbox provides test isolation.

</domain>

<decisions>
## Implementation Decisions

### Key naming (canonical form)
- **Decision:** `snake_case` is the canonical form. Matches DATA_MODEL.md §11, seeds, and all current callers.
- **Additional work:** Update `docs/DATA_MODEL.md` §11 to drop the "aspirational `.` form is deprecated" note (line 686) — now that snake_case is the clear canon, the hedge is no longer needed.
- **Test fixtures:** `test/foglet_bbs/config_test.exs` currently uses `test.key.string` style keys for ETS cache behaviour tests. These will be **rewritten** to use real schematized keys (`registration_mode`, `max_post_length`, `require_email_verification`) since strict write validation rejects unknown keys. Ecto sandbox provides test isolation — no production-schema pollution concern.

### Schema module shape
- **Decision:** Plain data module. `Foglet.Config.Schema` exposes a list of specs (`%{key, type, default, description, enum: nil, min: nil, max: nil}`) as module attributes plus simple public functions (`entries/0`, `fetch_spec/1`, `validate/2`, `defaults/0`).
- **Why:** A static list of ~6 keys does not justify macro machinery or an Ecto embedded_schema. Plain data is easy to iterate for seeds, validation, and future documentation.
- **Typed accessors** are defined explicitly on `Foglet.Config` (one function per key) rather than macro-generated. Six short functions is clearer than a metaprogramming layer. Pattern: `def registration_mode, do: get!("registration_mode")`.

### Error contract (missing vs DB failed vs malformed)
- **Decision:** Add `Foglet.Config.fetch/1` returning `{:ok, value} | :error` — matches Elixir stdlib canon (`Map.fetch/2`, `Keyword.fetch/2`, `Access.fetch/2`). DB errors continue to propagate as exceptions (callers that want to handle a DB outage can rescue `DBConnection.ConnectionError`).
- **Keep:** `get!/1` (raises `Ecto.NoResultsError` on missing, propagates DB errors) and `get/2` (returns default on `Ecto.NoResultsError`, propagates other errors — same as today).
- **Rationale:** Classic Elixir idiom; `fetch/1` gives callers the structured "is this set?" check without touching exception handling. Typed accessors call `get!/1` internally (a missing schema key means the seeds didn't run and the app is mis-configured — raising is correct). Stdlib-matching return shape avoids surprising Dialyzer-literate callers and future contributors.

### Write validation strictness
- **Decision:** Strict. `Foglet.Config.put!/3` validates the key against `Foglet.Config.Schema.fetch_spec/1`:
  - Unknown key → raise `Foglet.Config.UnknownKeyError`.
  - Type mismatch → raise `Foglet.Config.InvalidValueError` with the violated constraint (e.g., wrong type, failed enum, out of range).
- **Scope:** Only the 6 currently-seeded keys are schematized. Aspirational keys (listed in DATA_MODEL.md §11) are **not** schematized in this task — scheduling them is a later phase.
- **Test carve-out (locked):** Rewrite `test/foglet_bbs/config_test.exs` cache-behaviour tests to use real schema keys (e.g., `registration_mode` for string, `max_post_length` for integer, `require_email_verification` for boolean). No `put_raw!/3` escape hatch. Ecto sandbox rolls back so there is no cross-test pollution. Additional test coverage: `put!/3` raises on unknown key, on type mismatch, on enum violation; `fetch/1` returns `:error` on missing and `{:ok, value}` on present; each typed accessor returns the seeded default in a fresh DB.

### Claude's Discretion
- Exact shape of `Foglet.Config.Schema.validate/2` return (e.g., `:ok | {:error, reason}` vs throwing). Recommend `:ok | {:error, reason}` so `put!/3` is the single raising surface.
- Whether typed accessors cache a compile-time default when DB is absent (e.g., application boot before seeds). Recommend: no — `get!/1` already raises, which is the correct signal that seeds haven't run.
- Module doc structure and whether `docs/ARCHITECTURE.md` needs a pointer update. Small doc changes at planner's discretion.

</decisions>

<specifics>
## Specific Ideas

- The 6 schematized keys and their concrete specs (pulled from `priv/repo/seeds.exs:43-55` and DATA_MODEL.md):

  | Key | Type | Default | Constraint |
  |---|---|---|---|
  | `registration_mode` | `:string` | `"open"` | enum: `["open", "invite_only", "sysop_approved"]` |
  | `invite_code_generators` | `:string` | `"sysop_only"` | enum: `["sysop_only", "mods", "any_user"]` |
  | `max_post_length` | `:integer` | `8192` | min: 1 |
  | `max_thread_title_length` | `:integer` | `60` | min: 1 |
  | `require_email_verification` | `:boolean` | `true` | — |
  | `email_verify_resend_cooldown_seconds` | `:integer` | `60` | min: 0 |

- **Seeds regeneration:** `priv/repo/seeds.exs` should iterate `Foglet.Config.Schema.entries/0` and call `put!/3` + set `description` from the spec. The current inline `default_config` list is replaced.

- **Existing callers that already use well-named keys can switch to typed accessors** (nice-to-have, not blocking):
  - `accounts.ex:172`: `Foglet.Config.get("require_email_verification", true)` → `Foglet.Config.require_email_verification?/0` (with `?` suffix for bool accessors)
  - `ssh/cli_handler.ex:340`: `Foglet.Config.get!("registration_mode")` → `Foglet.Config.registration_mode/0`
  - `ssh/cli_handler.ex:347`: `Foglet.Config.get!("max_post_length")` → `Foglet.Config.max_post_length/0`
  - `verify.ex:278`: `Foglet.Config.get("email_verify_resend_cooldown_seconds", 60)` → `Foglet.Config.email_verify_resend_cooldown_seconds/0`

</specifics>

<canonical_refs>
## Canonical References

- `docs/DATA_MODEL.md` §11 "Configuration" (lines 662–709) — keys list and the deprecated `.` form note.
- `lib/foglet_bbs/config.ex` — module currently refactored here.
- `lib/foglet_bbs/config/entry.ex` — DB persistence layer; not restructured.
- `priv/repo/seeds.exs:43-55` — current default_config list; to be regenerated from schema.
- `test/foglet_bbs/config_test.exs` — round-trip tests; keep or adapt test key fixtures.
- `CLAUDE.md` — project guidelines (precommit: compile --warnings-as-errors, format, credo --strict, sobelow, dialyzer; avoid `String.to_atom` on external input).

</canonical_refs>
