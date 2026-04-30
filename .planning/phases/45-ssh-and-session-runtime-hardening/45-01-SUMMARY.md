---
phase: 45
plan: 45-01
subsystem: ssh
tags: [ssh, pubkey-stash, ttl, ets]
requires: []
provides: [pubkey-stash-ttl-sweep]
affects: [foglet.ssh.pubkey_stash]
tech-stack:
  added: []
  patterns: [ets-timestamp-ttl, deterministic-test-clock]
key-files:
  created: []
  modified:
    - lib/foglet_bbs/ssh/pubkey_stash.ex
    - test/foglet_bbs/ssh/cli_handler_test.exs
decisions:
  - D-01: TTL/sweep belongs inside PubkeyStash; ETS remains ephemeral, no durable storage.
  - D-02: put/2 and pop/1 stay compatible; put/3 and pop/2 added only for deterministic tests.
  - D-03: Missing or expired stash entries still become guest sessions.
metrics:
  duration: ~10m
  completed: 2026-04-30
requirements: [SSH-01]
---

# Phase 45 Plan 01: Pubkey Stash TTL And Sweep Summary

Bound `Foglet.SSH.PubkeyStash` against orphaned key offers with a five-minute
TTL on every entry, an expiry-aware `pop/2` that deletes stale entries on read,
and an explicit `sweep/2` that removes expired entries and returns the count.
`put/2` and `pop/1` keep the existing call-site shape so `KeyCB` and
`CLIHandler` are not touched, and missing or expired entries still fall through
to guest sessions.

## What Changed

### `lib/foglet_bbs/ssh/pubkey_stash.ex`

- Added `@ttl_ms :timer.minutes(5)`.
- Entries are now stored as `{peer_key, public_key, inserted_at_ms}`. `put/2`
  delegates to `put/3` with `System.monotonic_time(:millisecond)`; `put/3` is a
  test-only injection point.
- `pop/1` delegates to `pop/2` with the current monotonic time. `pop/2` uses
  `:ets.take/2`, returns `{:ok, public_key}` when `now_ms - inserted_at_ms <=
  @ttl_ms`, returns `:miss` when expired (entry is taken either way), and
  treats legacy two-tuple entries as compatible during rollout.
- Added `sweep/2` using `:ets.select_delete/2` with a match spec that selects
  entries where `inserted_at_ms < now_ms - ttl_ms`. Returns the deletion count.
- Module doc rewritten to describe the TTL/sweep contract and reaffirm guest
  fallback semantics.

### `test/foglet_bbs/ssh/cli_handler_test.exs`

- Added a `setup` block in the `PubkeyStash correlation` describe that resets
  the stash ETS table before each test using a new `reset_pubkey_stash!/0`
  helper (delete + `PubkeyStash.init/0`).
- Existing `put/2`+`pop/1` compatibility test retained.
- New test: `sweep` past the TTL window deletes one stale entry and a
  follow-up `pop` returns `:miss`.
- New test: `sweep` removes only the stale entry, the fresh entry remains
  consumable exactly once via `pop`.
- New test: an expired entry returns `:miss` from `pop(peer, now_ms)` without
  a prior sweep, confirming CLIHandler will fall back to guest when stash
  entries are stale.

## Verification

- `rtk mix test test/foglet_bbs/ssh/cli_handler_test.exs` — 16 tests, 0
  failures (3 new TTL behavior tests, all existing tests still green).
- `rtk mix compile --warnings-as-errors` — no foglet_bbs warnings; only
  pre-existing raxol/Mogrify warnings remain (out of scope).
- Acceptance greps satisfied:
  - `@ttl_ms`, `def put(peer_key, public_key, now_ms)`, `def sweep` all match.
  - `def pop(:unknown)`, `def pop(peer_key)`, `def pop(peer_key, now_ms)` all
    match.
  - `:ets.take` and `:ets.select_delete` both match (destructive read and
    sweep deletion paths).
  - Test file contains `sweep(`, `:timer.minutes(5)`, and `pop(peer, ...
    minutes` references.

## Threat Model Outcomes

- **T-45-01 (medium):** Mitigated. `pop/2` checks `now_ms - inserted_at_ms <=
  @ttl_ms` and returns `:miss` for expired entries. The expired entry is
  deleted by `:ets.take/2` regardless of TTL outcome, so a stale offer cannot
  be consumed by a later connection from the same peer tuple.
- **T-45-02 (low):** Mitigated. `put/2` and `pop/1` keep their public arities
  and behavior; `KeyCB.is_auth_key/3` and `CLIHandler.resolve_pubkey_user/1`
  call sites are unchanged. The internal three-tuple shape is encapsulated,
  and legacy two-tuple entries still resolve via `pop/2` for safety during
  rollout.

## Deviations from Plan

None - plan executed exactly as written.

## Commits

- `37fe0442` feat(45-01): bound pubkey stash with TTL and sweep
- `850071bb` test(45-01): cover pubkey stash TTL sweep and expiry

## Self-Check: PASSED

- `lib/foglet_bbs/ssh/pubkey_stash.ex` — modified (verified via grep).
- `test/foglet_bbs/ssh/cli_handler_test.exs` — modified (verified via grep).
- Commits `37fe0442` and `850071bb` present in `git log`.
