---
phase: 02-sysop-config-and-board-management
plan: 01
subsystem: config
tags: [config, schema, invt-07, sysop]
requires: []
provides:
  - "invite_generation_per_user_limit schema key"
  - "Foglet.Config.invite_generation_per_user_limit/0 typed accessor"
affects:
  - "SITE tab iteration (Plan 03): @site_keys will now include invite_generation_per_user_limit"
key_files:
  created: []
  modified:
    - lib/foglet_bbs/config/schema.ex
    - lib/foglet_bbs/config.ex
    - test/foglet_bbs/config_test.exs
decisions:
  - "Seeding handled via existing priv/repo/seeds/config.exs delegation (Schema.entries/0 iteration) — no explicit edit to priv/repo/seeds.exs needed. See Deviations."
metrics:
  duration_min: 6
  completed: "2026-04-23"
---

# Phase 02 Plan 01: invite_generation_per_user_limit Schema Key Summary

INVT-07 schema entry added with typed accessor and full put/3 test coverage; seed row auto-inserted via existing Schema.entries/0 delegation in priv/repo/seeds/config.exs.

## Tasks Completed

| Task | Name                                                             | Commit  |
| ---- | ---------------------------------------------------------------- | ------- |
| RED  | Add failing test for typed accessor                              | (see git log `test(02-01): add failing test`) |
| 1    | Schema entry + typed accessor                                    | (see git log `feat(02-01): add invite_generation_per_user_limit`) |
| 2    | INVT-07 put/3 describe block (6 cases)                           | (see git log `test(02-01): add INVT-07 put/3 coverage`) |

## Files Modified

- `lib/foglet_bbs/config/schema.ex` — appended :integer entry (default 0, min 0) for `invite_generation_per_user_limit`.
- `lib/foglet_bbs/config.ex` — added `invite_generation_per_user_limit/0` typed accessor alongside the other six.
- `test/foglet_bbs/config_test.exs` — added typed-accessor test and new `describe "invite_generation_per_user_limit (INVT-07)"` with six cases (accepts 0, accepts positive, rejects negative, rejects non-integer, rejects mod, rejects nil).

## Key Decisions

- **0 as unlimited sentinel (D-04):** Followed plan-spec; `min: 0` allows the sentinel while rejecting negatives.
- **Accessor return type `non_neg_integer()`:** Matches the schema's `min: 0` constraint precisely.
- **Test setup reuses existing `@test_keys = Map.keys(Schema.defaults())`:** New key flows automatically into per-test ETS invalidation — no test infra changes needed.

## Deviations from Plan

### [Rule 3 — Architectural mismatch] Seeds handled via existing delegation, not direct `seeds.exs` edit

- **Found during:** Task 1 `read_first` review.
- **Issue:** Plan Task 1 step 3 and acceptance criterion `grep -q 'invite_generation_per_user_limit' priv/repo/seeds.exs` both assume the top-level `priv/repo/seeds.exs` contains a per-key schematized seed block.
- **Reality:** `priv/repo/seeds.exs` delegates config seeding via `Code.eval_file(Path.join(__DIR__, "seeds/config.exs"))`. `priv/repo/seeds/config.exs` iterates `Schema.entries()` and calls `Config.put!/3` for each key. Adding the schema entry in Task 1 therefore auto-produces a seeded row — no edit to `seeds.exs` or `seeds/config.exs` was needed.
- **Fix applied:** Relied on the existing iteration. Verified by running `MIX_ENV=test mix run priv/repo/seeds/config.exs` which logged `[seed] inserted config invite_generation_per_user_limit = 0` on first run and `already present` on re-run.
- **Plan acceptance-criterion grep is therefore expected-to-fail** for `seeds.exs`; the behavior (key present in `configuration` table after seed) is satisfied.
- **Files modified:** none beyond the plan's intended scope.

## Verification

- `mix test test/foglet_bbs/config_test.exs` → 41 tests, 0 failures.
- `mix precommit` → all stages passed (compile --warnings-as-errors, format, credo --strict, sobelow, dialyzer with 78 pre-existing skipped ignore entries; 0 new errors).

## Self-Check: PASSED

- `lib/foglet_bbs/config/schema.ex` contains `invite_generation_per_user_limit`: FOUND.
- `lib/foglet_bbs/config.ex` contains `def invite_generation_per_user_limit`: FOUND.
- `test/foglet_bbs/config_test.exs` contains `invite_generation_per_user_limit (INVT-07)`: FOUND.
- All three per-task commits present on worktree branch.
