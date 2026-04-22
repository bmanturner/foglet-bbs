---
quick_id: 260422-irb
phase: quick-260422-irb
verified: 2026-04-22T00:00:00Z
status: passed
score: 11/11 must-haves verified
overrides_applied: 0
---

# Quick Task 260422-irb: Typed Config Schema Verification Report

**Task goal:** Build a typed config schema (`Foglet.Config.Schema`) as the source of truth for runtime-editable sysop config. Add typed accessors, strict write-time validation, `fetch/1` with stdlib-canonical `{:ok, v} | :error` return, regenerate seeds from the schema, and distinguish "missing config key" from "DB failed" without conflating them in `get/2`.

**Verified:** 2026-04-22
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | `Schema.entries/0` returns exactly 6 spec maps with the locked key set | VERIFIED | `lib/foglet_bbs/config/schema.ex:49-106` — 6 literal maps in `@entries` with keys `registration_mode`, `invite_code_generators`, `max_post_length`, `max_thread_title_length`, `require_email_verification`, `email_verify_resend_cooldown_seconds`. Confirmed by grep count (6 matches on `^\s*%{`). |
| 2 | `Schema.validate/2` returns `:ok` / `{:error, %{reason, expected, got}}` / `{:error, {:unknown_key, key}}` | VERIFIED | `schema.ex:150-155` dispatches to private `check/2` on hit and `{:error, {:unknown_key, key}}` on miss. `check/2`/`check_enum/2`/`check_range/2` (lines 161-191) produce `%{reason, expected, got}` maps for `:type_mismatch`, `:not_in_enum`, `:below_min`, `:above_max`. 32 tests in `test/foglet_bbs/config/schema_test.exs` exercise the matrix. |
| 3 | `Config.fetch/1` returns `{:ok, value}` on present key and `:error` on `Ecto.NoResultsError` | VERIFIED | `lib/foglet_bbs/config.ex:92-96` — body is `{:ok, get!(key)}` with `rescue Ecto.NoResultsError -> :error`. `@spec fetch(String.t()) :: {:ok, term()} | :error` on line 91 matches the `Map.fetch/2` stdlib shape. |
| 4 | `Config.put!/3` raises `UnknownKeyError` when key not in Schema | VERIFIED | `config.ex:111-120` — case on `Schema.validate(key, value)`; `{:error, {:unknown_key, ^key}}` branch on line 115 does `raise UnknownKeyError, key: key`. DB is not touched on this path (raise precedes `do_put!/3`). |
| 5 | `Config.put!/3` raises `InvalidValueError` on type/enum/range violations | VERIFIED | `config.ex:118-119` — `{:error, %{reason, expected, got}}` branch raises `InvalidValueError` with the full structured payload preserved. |
| 6 | `Config.put!/3` still succeeds (DB upsert + ETS invalidation) for valid values | VERIFIED | `config.ex:112-113` — `:ok` branch delegates to private `do_put!/3` (lines 164-187) which performs the original upsert + `invalidate/1` logic unchanged. Test suite (885/0 per SUMMARY) covers behavioural round-trips. |
| 7 | Six typed accessors exist with `@spec` + `@doc`; boolean uses `?` suffix | VERIFIED | `config.ex:138-160` — `registration_mode/0`, `invite_code_generators/0`, `max_post_length/0`, `max_thread_title_length/0`, `require_email_verification?/0`, `email_verify_resend_cooldown_seconds/0`. Each has a `@doc` and `@spec` immediately above; grep confirms 6 `def` lines. `?` appears only on the boolean accessor (line 156). |
| 8 | `priv/repo/seeds.exs` iterates `Schema.entries/0` with description-on-first-insert | VERIFIED | `priv/repo/seeds.exs:15` aliases `Foglet.Config.Schema`; lines 44-60 do `Enum.each(Schema.entries(), ...)` with `case Repo.get_by(Entry, key: key)` branching — `nil` path calls `Config.put!/3` then sets description via changeset, `_existing` path logs "already present" without touching description (D-07 preserved). |
| 9 | The 4 identified callsites use typed accessors | VERIFIED | `lib/foglet_bbs/accounts.ex:172` uses `Foglet.Config.require_email_verification?()`. `lib/foglet_bbs/ssh/cli_handler.ex:344` uses `Foglet.Config.registration_mode()` and line 345 uses `Foglet.Config.max_post_length()`. `lib/foglet_bbs/tui/screens/verify.ex:278` uses `Foglet.Config.email_verify_resend_cooldown_seconds()`. All old `get/2` / try-rescue patterns removed. |
| 10 | `docs/DATA_MODEL.md` §11 line 686 states snake_case is canonical | VERIFIED | `docs/DATA_MODEL.md:686` now reads `Keys use snake_case separators. This is the canonical form.` No remaining "aspirational" / "deprecated" language in the file (grep returned no matches). Optional programmatic-access blockquote added at line 697 (planner's-discretion bullet taken — noted in SUMMARY). |
| 11 | `mix precommit` passes and full test suite is green | VERIFIED | Executor reported 885 tests / 0 failures and `mix precommit` clean across compile/format/credo/sobelow/dialyzer. Task instructions accept this as the test-passing truth without re-running. Commits `df9927b`, `6953664`, `c7e9a91` present in `git log`. |

**Score:** 11/11 truths verified.

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `lib/foglet_bbs/config/schema.ex` | Pure data module — `@entries`, `@spec_map`, `entries/0`, `fetch_spec/1`, `validate/2`, `defaults/0` | VERIFIED | 192 LOC, `defmodule Foglet.Config.Schema`, zero `alias`/`require` pointing at `Repo` or `Ecto`, `@spec_map = Map.new(@entries, &{&1.key, &1})` derived at compile time, all 4 public functions have `@spec` + `@doc`. |
| `lib/foglet_bbs/config/unknown_key_error.ex` | `defexception [:key]` with `@impl message/1` | VERIFIED | 15 LOC, `defexception [:key]` on line 7, `@impl true def message/1` returns an informative string containing the key and a remediation pointer to `Foglet.Config.Schema`. |
| `lib/foglet_bbs/config/invalid_value_error.ex` | `defexception [:key, :reason, :expected, :got]` with 4 `message/1` clauses | VERIFIED | 36 LOC, `defexception [:key, :reason, :expected, :got]` on line 11, one `message/1` clause per `:type_mismatch`, `:not_in_enum`, `:below_min`, `:above_max`. `@impl true` declared on the first clause and carries to the others (matches project style). |
| `lib/foglet_bbs/config.ex` | Adds `fetch/1`, validated `put!/3`, 6 typed accessors; preserves `get!/1`, `get/2`, `init_cache/0`, `invalidate/1` | VERIFIED | 191 LOC. All original public API retained (init_cache/0 lines 37-46, get!/1 lines 54-67, get/2 lines 74-78, invalidate/1 lines 125-129). `fetch/1` lines 92-96, validated `put!/3` lines 110-121 delegates to private `do_put!/3` (164-187). Six typed accessors lines 138-160. 12 `@spec` blocks total. |
| `priv/repo/seeds.exs` | Config block regenerated from `Schema.entries/0` | VERIFIED | Lines 44-60 — `Enum.each(Schema.entries(), ...)`. Alias added line 15. Description-on-first-insert retained. |
| `test/foglet_bbs/config_test.exs` | Rewritten against real schema keys; fetch/1, validation, typed-accessor tests | VERIFIED | 26 test blocks across 33 describe/test lines. `describe "fetch/1"` (line 104), `describe "put!/3 validation"` (line 131), `describe "typed accessors"` (line 208). No `test.key.*` fixtures remain (grep across `test/` returned no matches). |
| `docs/DATA_MODEL.md` | §11 line 686 updated; "deprecated" note removed | VERIFIED | Line 686 — "Keys use snake_case separators. This is the canonical form." No remaining `aspirational` / `deprecated` language anywhere in the file. |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `config.ex` put!/3 | `schema.ex` validate/2 | `Schema.validate(key, value)` gates DB write | WIRED | `config.ex:111` — `case Schema.validate(key, value) do`. Only `:ok` branch reaches `do_put!/3`. |
| `config.ex` put!/3 | `UnknownKeyError`, `InvalidValueError` | `raise` on validate/2 error tuple | WIRED | `config.ex:116` raises `UnknownKeyError`; `config.ex:119` raises `InvalidValueError` with full structured payload. Both aliased at top (lines 24, 26). |
| `config.ex` fetch/1 | `get!/1` + NoResultsError rescue | rescue clause converts exception → `:error` | WIRED | `config.ex:92-96` — body returns `{:ok, get!(key)}` with `rescue Ecto.NoResultsError -> :error`. |
| `seeds.exs` | `Schema.entries/0` | `Enum.each` over entries with put!/3 + description | WIRED | `seeds.exs:44` — `Enum.each(Schema.entries(), ...)`; `:nil` branch calls `Config.put!/3` then sets description via changeset. |
| `accounts.ex` post_login_screen/1 | `Config.require_email_verification?/0` | direct call replaces get/2 | WIRED | `accounts.ex:172` — `Foglet.Config.require_email_verification?() == false ->`. Old `get("require_email_verification", true)` pattern removed. |
| `cli_handler.ex` | `Config.registration_mode/0`, `Config.max_post_length/0` | direct calls replace try/rescue | WIRED | `cli_handler.ex:344-345` — inlined into session-context map literal. Try/rescue blocks removed per SUMMARY (net 13 LOC). |
| `verify.ex` resend_cooldown_seconds/0 | `Config.email_verify_resend_cooldown_seconds/0` | direct call replaces get/2 + integer guard | WIRED | `verify.ex:278` — single-line body. Redundant `is_integer(n) and n > 0` guard removed (Schema's `min: 0` enforces the contract). |

### Data-Flow Trace (Level 4)

Not applicable. This phase is library-internal (schema module, exceptions, strict put!/3 validation, accessors) — no UI artifacts render dynamic data fetched from an external source. The data flow is covered behaviourally by the rewritten test suite (26 tests in `config_test.exs` + 32 in `schema_test.exs`), which the executor confirmed green (885/0 overall).

### Behavioral Spot-Checks

Skipped — per task instructions, `mix precommit` passed with 885 tests / 0 failures per the executor report, accepted as the test-passing truth without rerunning. Re-running tests or starting an IEx session would exceed the 10-second spot-check budget.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|---|---|---|---|---|
| 260422-irb | 260422-irb-PLAN.md | Typed config schema with accessors and validation | SATISFIED | All 11 must-have truths verified (see table above). |

### Anti-Patterns Found

None. Grep for `TODO|FIXME|XXX|HACK|PLACEHOLDER|placeholder` across the 4 new/modified core source files (`schema.ex`, `unknown_key_error.ex`, `invalid_value_error.ex`, `config.ex`) returned no matches. The `:above_max` clause in `InvalidValueError` is intentionally retained for future schematized keys with maximum bounds and is documented in the moduledoc — not a dead-code concern.

### Human Verification Required

None. All artifacts, key links, and observable truths are programmatically verifiable. The executor performed IEx smoke checks implicitly via `mix precommit` + full test suite; human visual verification is not required for a pure-library refactor.

### Gaps Summary

No gaps. Every must_have listed in `260422-irb-PLAN.md` frontmatter has a concrete, located artifact or behaviour in the codebase. The plan's three auto-fix deviations documented in SUMMARY (cross-test ETS leak, tests asserting old permissive-fallback contract, Dialyzer contract_supertype) are in-flight corrections that the plan explicitly anticipated — not gaps.

---

_Verified: 2026-04-22_
_Verifier: Claude (gsd-verifier)_
