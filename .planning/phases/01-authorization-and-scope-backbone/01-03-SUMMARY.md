---
phase: 01-authorization-and-scope-backbone
plan: "03"
subsystem: config
tags:
  - authorization
  - config
  - actor-aware
  - bodyguard
  - elixir
dependency_graph:
  requires:
    - "01-01 (Foglet.Authorization / Bodyguard.permit/4)"
  provides:
    - "Foglet.Config.put/3 — actor-aware non-bang config writer returning tagged tuples"
  affects:
    - "Phase 2 (Sysop Config and Board Management) — TUI sysop config editor uses put/3 as its write API"
    - "Phase 3+ — any interactive caller needing a clean case-match API over config mutations"
tech_stack:
  added: []
  patterns:
    - "Non-bang variant alongside bang variant (Map.fetch/fetch! pattern)"
    - "Bodyguard.permit/4 authorization guard at function top before any DB or ETS touch"
    - "with :ok <- Bodyguard.permit(...) do ... end — short-circuit on forbidden"
    - "Schema.validate/2 error shapes collapsed to tagged atom tuples for interactive callers"
    - "TDD RED/GREEN — failing tests committed before implementation"
key_files:
  created: []
  modified:
    - lib/foglet_bbs/config.ex
    - test/foglet_bbs/config_test.exs
decisions:
  - "New put/3 added alongside existing put!/3 rather than modifying it — seeds and 20+ test call sites depend on the raise contract; mixing bang semantics with {:error, :forbidden} would create an incoherent return surface"
  - "Schema.validate/2 runs AFTER Bodyguard.permit — unauthorized callers get {:error, :forbidden} without learning schema details (information disclosure mitigation T-01-18)"
  - "Validation error details collapsed to {:error, :unknown_key} / {:error, :invalid_value} atoms — Phase 2 TUI re-validates at form level; the per-field reason/expected/got payload is not needed at the interactive API boundary"
  - "actor && actor.id used in do_put! call — defensive against nil actor reaching that branch after future refactors; Bodyguard rejects nil before this point in practice"
metrics:
  duration: "~7 minutes"
  completed: "2026-04-23"
  tasks_completed: 2
  files_created: 0
  files_modified: 2
  tests_added: 8
---

# Phase 1 Plan 03: Actor-Aware Foglet.Config.put/3 Summary

**One-liner:** New `Foglet.Config.put/3` wraps `do_put!` behind a `Bodyguard.permit(:edit_config)` guard, returning tagged tuples for all failure modes — sysop permitted, mod/user/nil forbidden, validation errors atom-tagged — while leaving `put!/3` completely untouched.

## What Was Built

### Task 1 — RED: Failing tests (commit f72e6cd)

Appended a new `describe "put/3 (actor-aware, D-19)"` block to `test/foglet_bbs/config_test.exs` with 8 test cases:

- Sysop can write a valid key/value and read it back via `get!/1`
- Sysop can update an existing value
- Regular user is forbidden — DB value unchanged
- `nil` actor is forbidden
- Mod actor is forbidden (mod is NOT granted `:edit_config` per Plan 01)
- Unknown key returns `{:error, :unknown_key}` (no raise)
- Invalid value returns `{:error, :invalid_value}` (no raise)
- Forbidden path does NOT insert or update any `Entry` row

Also added `alias Foglet.Accounts.User` for actor fixture helpers. All 8 new tests failed with `UndefinedFunctionError` — RED phase confirmed.

### Task 1 — GREEN: Implementation (commit 688e567)

Added `Foglet.Config.put/3` to `lib/foglet_bbs/config.ex` after the existing `put!/3` and before `invalidate/1`:

```elixir
@spec put(Foglet.Accounts.User.t() | nil, String.t(), term()) ::
        {:ok, Entry.t()}
        | {:error, :forbidden}
        | {:error, :unknown_key}
        | {:error, :invalid_value}
def put(actor, key, value) when is_binary(key) do
  with :ok <- Bodyguard.permit(Foglet.Authorization, :edit_config, actor, :site) do
    case Schema.validate(key, value) do
      :ok -> {:ok, do_put!(key, value, actor && actor.id)}
      {:error, {:unknown_key, ^key}} -> {:error, :unknown_key}
      {:error, %{reason: _reason}} -> {:error, :invalid_value}
    end
  end
end
```

`put!/3` was not modified — signature, body, and raise contract are identical to before. All 34 config tests pass at GREEN.

### Task 2 — Precommit gate (no new commit, formatter style commit fdce14d)

`mix precommit` passed all gates: `compile --warnings-as-errors`, `format`, `credo --strict`, `sobelow`, and `dialyzer`. The formatter expanded the `@spec` union type to one-variant-per-line and wrapped one long assertion line — committed as `style(01-03)`.

## Deviations from Plan

None — plan executed exactly as written. The formatter reformatting after precommit was committed separately as `style(01-03)` per the task commit protocol — format-only change, behavior unchanged.

## Known Stubs

None. `put/3` is fully wired: it calls `Bodyguard.permit/4` (live policy module from Plan 01), `Schema.validate/2` (existing validation), and `do_put!/3` (existing DB write with ETS invalidation). No placeholder values or TODO markers.

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns, or schema changes introduced. `put/3` is a pure domain function. All STRIDE threats from the plan's threat model are mitigated:

| Threat | Mitigation | Status |
|--------|-----------|--------|
| T-01-14 Elevation of Privilege | `Bodyguard.permit(:edit_config, actor, :site)` before any DB touch; test asserts regular-user/nil/mod → `{:error, :forbidden}` | Mitigated |
| T-01-15 Tampering (forbidden leaks writes) | `do_put!/3` only called in `with` success branch; test asserts `Repo.aggregate(Entry, :count)` unchanged on forbidden path | Mitigated |
| T-01-16 DoS (raises into interactive callers) | Validation errors returned as tagged tuples; no raise on unknown-key or invalid-value paths | Mitigated |
| T-01-17 Tampering (accidental put!/3 modification) | `put!/3` body and signature unchanged; done check confirmed | Mitigated |
| T-01-18 Info Disclosure (schema details to unauthorized) | Validation only runs after authorization passes; unauthorized callers see only `{:error, :forbidden}` | Mitigated |

## Self-Check: PASSED

| Item | Status |
|------|--------|
| `lib/foglet_bbs/config.ex` — `put/3` implementation | FOUND |
| `lib/foglet_bbs/config.ex` — `put!/3` unchanged | FOUND |
| `test/foglet_bbs/config_test.exs` — `put/3 (actor-aware, D-19)` describe block | FOUND |
| f72e6cd (Task 1 RED) | FOUND |
| 688e567 (Task 1 GREEN) | FOUND |
| fdce14d (Task 2 style/precommit) | FOUND |
| `mix precommit` exit 0 | PASSED |
| All 34 config tests pass | PASSED |
| Full suite 1020 tests, 0 failures | PASSED |
