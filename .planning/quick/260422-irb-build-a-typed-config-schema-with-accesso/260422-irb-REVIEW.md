---
phase: quick-260422-irb
reviewed: 2026-04-22T00:00:00Z
depth: quick
files_reviewed: 13
files_reviewed_list:
  - lib/foglet_bbs/config/schema.ex
  - lib/foglet_bbs/config/unknown_key_error.ex
  - lib/foglet_bbs/config/invalid_value_error.ex
  - lib/foglet_bbs/config.ex
  - priv/repo/seeds.exs
  - lib/foglet_bbs/accounts.ex
  - lib/foglet_bbs/ssh/cli_handler.ex
  - lib/foglet_bbs/tui/screens/verify.ex
  - docs/DATA_MODEL.md
  - test/foglet_bbs/config/schema_test.exs
  - test/foglet_bbs/config_test.exs
  - test/foglet_bbs/accounts/accounts_test.exs
  - test/foglet_bbs/tui/screens/verify_test.exs
findings:
  critical: 0
  warning: 2
  info: 5
  total: 7
status: issues_found
---

# Quick 260422-irb: Code Review Report

**Reviewed:** 2026-04-22
**Depth:** quick
**Files Reviewed:** 13
**Status:** issues_found (advisory only — non-blocking)

## Summary

Clean, well-scoped change. The schema/validation/accessor split lands where the plan said it would, `put!/3` validates before any DB work, seeds still carry description on first insert, and the three callsite migrations read cleanly. `mix precommit` is green with 885 tests. Findings below are refinement suggestions, not correctness problems — the two Warnings flag a narrow ETS-race window and a brittleness trap for future string-type keys; everything else is Info.

No `String.to_atom/1` misuse. No secrets. No block-rebind, multi-module-file, or struct-Access gotchas. Seed ordering and the description-on-first-insert pathway are intact. DATA_MODEL.md §11 update is coherent with the new schema module.

## Warnings

### WR-01: Schema.validate/2 does not reject binaries containing null bytes or non-UTF-8 data

**File:** `lib/foglet_bbs/config/schema.ex:161`
**Issue:** The string-type clause is `when is_binary(value)`, which admits any binary — including invalid UTF-8 and embedded nulls. For enum-bounded keys (`registration_mode`, `invite_code_generators`) this is harmless because the enum check rejects anything not in the allow-list. But if a future string-typed schema entry has no enum (e.g. a free-form `motd`), an arbitrary binary would pass validation and be stored as jsonb, with the downstream consumer discovering the problem. Worth a guard now while the surface is small.
**Fix:**
```elixir
defp check(%{type: :string} = spec, value) when is_binary(value) do
  if String.valid?(value), do: check_enum(spec, value),
    else: {:error, %{reason: :type_mismatch, expected: :string, got: value}}
end
```
Alternative: defer until the first non-enum string key is added, and flag this in `Schema`'s moduledoc as a known gap so it doesn't get forgotten.

### WR-02: `do_put!/3` has a brief cache-inconsistency window between DB write and invalidate

**File:** `lib/foglet_bbs/config.ex:164-187`
**Issue:** The sequence is (1) `Repo.insert!`/`Repo.update!`, (2) `invalidate(key)`. Between those two steps, a concurrent reader can still serve the stale value from ETS; even after step (2), a reader that races between `:ets.delete` and the next `:ets.insert` in `get!/1` can re-populate the cache with the fresh DB value — that's fine. The actual narrow hazard is a different interleaving:
1. Process A `do_put!` DB-writes new value V2, hasn't invalidated yet.
2. Process B misses ETS (first read ever), reads DB → sees V2, inserts {key, V2}.
3. Process A invalidates → deletes {key, V2}.
4. Process C misses, reads DB → sees V2, inserts {key, V2}. Net effect: correct.

So the "stale after invalidate" case actually resolves itself because the DB is already the new truth by step (2). **The real issue** is if `Repo.insert!/Repo.update!` succeeds but the process crashes between the DB write and `invalidate(key)` — the ETS table then keeps the old value until some other writer invalidates or the table is rebuilt. In practice this is extremely narrow (one-line window, no rescue/exit between them), and the next `put!` for the same key will invalidate regardless.
**Fix:** Either accept as a known narrow race and document it in the `put!/3` moduledoc, or invalidate first and let `get!/1` re-read from DB on the next hit:
```elixir
defp do_put!(key, value, updated_by_id) do
  init_cache()
  invalidate(key)  # drop stale cache first
  wrapped = %{"v" => value}
  entry =
    case Repo.get_by(Entry, key: key) do
      nil -> ... Repo.insert!()
      existing -> ... Repo.update!()
    end
  invalidate(key)  # drop any racing re-read that beat the write
  entry
end
```
The double-invalidate pattern is the conventional write-through-cache fix; the extra ETS delete is cheap. Non-blocking — the current code is correct under the assumption that `put!/3` runs to completion.

## Info

### IN-01: `get/2` rescue swallows non-NoResults Ecto errors cleanly, but `fetch/1` inherits the same shape by going through `get!/1`

**File:** `lib/foglet_bbs/config.ex:74-96`
**Issue:** Both `get/2` and `fetch/1` rescue only `Ecto.NoResultsError`, so DB outages correctly propagate. Fine as-is. Worth noting in the `fetch/1` moduledoc (which already does say "DB errors … propagate as exceptions") that this is the *only* converted error — the current phrasing "only a missing-key miss" is already correct. No change needed; flagged only because `fetch/1` is new and reviewers may want to confirm the rescue boundary is intentional.
**Fix:** None — documentation already covers this.

### IN-02: `@defaults_map` is unused outside `defaults/0` and could be inlined

**File:** `lib/foglet_bbs/config/schema.ex:108-109`
**Issue:** Two module attributes — `@spec_map` (used by `fetch_spec/1`) and `@defaults_map` (used only by `defaults/0`). The former is justified (O(1) lookup vs O(n) scan of `@entries`); the latter is called rarely and always returns the full map, so the attribute is pure memoization overhead. Keeping both is fine for symmetry.
**Fix:** Optional — inline `Map.new(@entries, &{&1.key, &1.default})` into `defaults/0`, or leave for symmetry. No behavioral change either way.

### IN-03: Typed accessors don't document their raise behaviour

**File:** `lib/foglet_bbs/config.ex:138-160`
**Issue:** Each `@doc` says what the value means but not that the accessor raises `Ecto.NoResultsError` if the seed row is missing (because they delegate to `get!/1`). Callers migrating from `Foglet.Config.get/2` (which had a default) may be surprised. The moduledoc does cover this generically ("`get!/1`, `get/2`, `fetch/1` stays permissive") but per-accessor docs don't.
**Fix:** Add one sentence to each accessor's `@doc`, e.g.:
```elixir
@doc """
Account registration policy (D-02/D-03).
Raises `Ecto.NoResultsError` if the config row is missing — seeds must run first.
"""
```
Or a single sentence in the "Typed accessors" section comment at line 131.

### IN-04: `verify.ex` lost its type-narrowing defensive check silently

**File:** `lib/foglet_bbs/tui/screens/verify.ex:277-279`
**Issue:** The previous `resend_cooldown_seconds/0` body was:
```elixir
case Foglet.Config.get("email_verify_resend_cooldown_seconds", 60) do
  n when is_integer(n) and n > 0 -> n
  _ -> 60
end
```
The new body is just `Foglet.Config.email_verify_resend_cooldown_seconds()`. That's correct *now* because `Schema.validate/2` enforces `type: :integer, min: 0`, and `DateTime.add/3` accepts 0 (no cooldown) fine. But two observations:
1. The old code rejected `0` (`n > 0`), the new code accepts it. That's a behavioural change — 0-second resend cooldown is now possible. Per Schema, `min: 0` is inclusive and intentional, so this is the correct new behaviour. Worth confirming with the product spec (D-02) that 0 is truly allowed.
2. If a legacy DB row pre-dates the schema and holds a non-integer or negative value, the accessor will return it raw (read path is permissive by design). `DateTime.add/3` will then raise on a string. The old defensive fallback masked this.
**Fix:** None required given the "read path stays permissive because rows may pre-date the schema" policy, but consider noting in the `Foglet.Config` moduledoc that legacy rows that fail accessor type contracts will propagate raises at use sites. If the product decision is "0 cooldown disallowed", bump `min:` to 1 in Schema.

### IN-05: Seeds description-update step silently swallows a put!/3 validation failure assumption

**File:** `priv/repo/seeds.exs:44-60`
**Issue:** The first-insert path does:
```elixir
Config.put!(key, default, nil)
Entry |> Repo.get_by!(key: key) |> ...change(%{description: description}) |> Repo.update!()
```
`Config.put!` now validates. If a future entry in `@entries` has a `default` that doesn't pass `Schema.validate/2` (e.g., typo where the default isn't in the `enum`), seeds will raise with `InvalidValueError` — which is *good*, because it catches schema self-consistency bugs at first seed. Worth adding a one-line test: `for {key, default} <- Schema.defaults(), do: assert Schema.validate(key, default) == :ok` — and in fact `test/foglet_bbs/config/schema_test.exs:156-161` already does exactly this. Nothing to fix; confirmed the safety net exists.
**Fix:** None. Flagged as a positive confirmation that the invariant has a test.

### IN-06: `Schema.check/2` type-mismatch clause relies on catch-all ordering

**File:** `lib/foglet_bbs/config/schema.ex:161-168`
**Issue:** The three positive clauses (`:string + is_binary`, `:integer + is_integer`, `:boolean + is_boolean`) are followed by a catch-all that extracts `%{type: type}` and emits `:type_mismatch`. Two defensive observations:
1. If `type` in a future entry is something unexpected (say `:float`), none of the positive clauses match, and the catch-all reports `{:type_mismatch, expected: :float, got: <value>}` — misleading because the real problem is an unsupported schema type, not a mismatched value. This is a self-inflicted foot-gun if someone adds a new type to the `@type entry` typespec without extending `check/2`.
2. The fix is cheap: add a compile-time check or a specific raise for unknown types. Dialyzer should catch typespec drift but won't catch "forgot to add a clause."
**Fix:**
```elixir
defp check(%{type: type}, _value) when type not in [:string, :integer, :boolean] do
  raise ArgumentError, "Schema: unsupported type #{inspect(type)} — extend check/2"
end
```
Place before the catch-all. Or expose the allowed-types list as a module attribute and assert on it in `entries/0`. Low priority — Dialyzer + the explicit typespec reduce the risk substantially.

---

## Summary table

| ID | Severity | File | Concern |
|----|----------|------|---------|
| WR-01 | Warning | schema.ex:161 | Invalid UTF-8/null bytes pass string validation (future-risk for non-enum string keys) |
| WR-02 | Warning | config.ex:164-187 | Narrow ETS staleness window if `put!/3` crashes between DB write and invalidate |
| IN-01 | Info | config.ex:74-96 | `fetch/1`/`get/2` rescue boundary — confirmed correct |
| IN-02 | Info | schema.ex:108-109 | `@defaults_map` is borderline overhead; fine to keep |
| IN-03 | Info | config.ex:138-160 | Typed accessors don't document the raise-on-missing-seed semantics |
| IN-04 | Info | verify.ex:277-279 | Lost defensive fallback; new `min: 0` allows 0s cooldown (product check) |
| IN-05 | Info | seeds.exs:44-60 | Seeds rely on schema self-consistency — already tested, no action needed |
| IN-06 | Info | schema.ex:161-168 | Catch-all `:type_mismatch` misreports unknown schema types |

---

_Reviewed: 2026-04-22_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: quick_
