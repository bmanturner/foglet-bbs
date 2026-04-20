---
phase: 6
plan: "03"
title: "Verify screen — independent resend cooldown + config-driven duration (VERIFY-02)"
subsystem: tui/verify
tags: [verify, cooldown, two-timer, anti-spam, config-driven]
dependency_graph:
  requires: ["06-01", "06-02"]
  provides: ["VERIFY-02"]
  affects: ["lib/foglet_bbs/tui/screens/verify.ex", "test/foglet_bbs/tui/screens/verify_test.exs"]
tech_stack:
  added: []
  patterns:
    - "Two-timer independence: separate cooldown?/1 and resend_cooldown?/1 predicates reading distinct fields"
    - "Config-driven duration: Foglet.Config.get/2 with default 60 for sysop tunability"
    - "2-arity cooldown_modal/2 taking explicit DateTime + prefix string for shared formatting"
key_files:
  created: []
  modified:
    - lib/foglet_bbs/tui/screens/verify.ex
    - test/foglet_bbs/tui/screens/verify_test.exs
decisions:
  - "Two timers not one: invalid-attempts = anti-brute-force; resend = anti-spam. Sharing one timer caused wrong cross-blocking (D-10)"
  - "cooldown_modal/2 takes DateTime field directly, not verify_state map, so caller specifies which cooldown to report"
  - "resend_cooldown_until: nil literal in all 6 init sites, not @default_vs constant — plan rationale: readability cost of indirection outweighs DRY gain"
  - "D-09 preserved: successful resend still clears cooldown_until + attempts as a clean-slate signal"
metrics:
  duration: "~28 minutes"
  completed: "2026-04-20T19:37:08Z"
  tasks_completed: 4
  tasks_total: 4
  files_modified: 2
---

# Phase 6 Plan 03: Verify Screen Independent Resend Cooldown (VERIFY-02) Summary

Two-timer resend cooldown split in verify.ex: `resend_cooldown_until` is now independent from `cooldown_until` so hitting invalid 5x does not block resend and resending once does not block code entry.

## Tasks Completed

| Task | Description | Commit |
|------|-------------|--------|
| 1 | Add `resend_cooldown_until: nil` to all 6 verify_state literals + update @moduledoc | 1f1b3f0 |
| 2 | Refactor `cooldown_modal/1` to `cooldown_modal/2` + add `resend_cooldown?/1` helper + fix `resend_code/1` gate | d072dd6 |
| 3 | Update `resend_code_raw/1` to read `Foglet.Config.get("email_verify_resend_cooldown_seconds", 60)` and set `resend_cooldown_until` | 34ecdf6 |
| 4 | Add VERIFY-02 two-timer describe block (5 new tests) + update all test fixtures | 42ecf23 |

## What Was Built

### `lib/foglet_bbs/tui/screens/verify.ex`

**@moduledoc** now documents both cooldown fields with their independence property (D-10).

**New `resend_cooldown?/1`** private predicate (two clause-heads) mirrors the existing `cooldown?/1` but reads `vs.resend_cooldown_until`. Returns `false` for `nil`, `true` when the DateTime is in the future.

**`cooldown_modal/2`** replaces the old `cooldown_modal/1`. Takes an explicit `%DateTime{}` field value and a binary prefix string. Pattern-matched on `%DateTime{}` to fail fast at dev-time rather than silently producing a bad diff result. The message format is `"<prefix> Wait Ns."`.

**VERIFY-02 bug fix in `resend_code/1`**: was gating on `cooldown?/1` (invalid-attempts timer); now correctly gates on `resend_cooldown?/1`. This was the core bug where a user who hit invalid 5x could not resend.

**`resend_code_raw/1` success branch**:
- Reads `Foglet.Config.get("email_verify_resend_cooldown_seconds", 60)` — sysop-tunable without redeploy.
- Sets `resend_cooldown_until: DateTime.add(now, cooldown_seconds, :second)`.
- Preserves D-09 locked behavior: also clears `cooldown_until: nil`, `attempts: 0`, `buffer: ""` — successful resend is a clean-slate event.

**All 6 literal `verify_state` initialisations** updated to include `resend_cooldown_until: nil`.

### `test/foglet_bbs/tui/screens/verify_test.exs`

All existing inline `%{buffer: ..., cooldown_until: ...}` literals updated with `resend_cooldown_until: nil` for schema consistency.

New `describe "resend cooldown — VERIFY-02 two-timer model"` block with five tests:
1. Successful resend sets `resend_cooldown_until` using config-driven duration (90s fixture, ±1s drift allowance).
2. Blocked resend returns `:error` modal without mutating `resend_cooldown_until`.
3. Invalid-attempts cooldown (`cooldown_until` set, `resend_cooldown_until: nil`) does NOT block resend — confirms independence direction 1.
4. Resend cooldown (`resend_cooldown_until` set, `cooldown_until: nil`) does NOT block typing a char — confirms independence direction 2.
5. Missing config key (row deleted from DB) defaults resend cooldown to 60s.

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None. All behavior is wired end-to-end.

## Threat Flags

None. No new network endpoints, auth paths, file access patterns, or schema changes introduced. `resend_cooldown_until` is a purely in-memory per-session field; no DB migration needed.

## Self-Check: PASSED

Files exist:
- `lib/foglet_bbs/tui/screens/verify.ex` — FOUND
- `test/foglet_bbs/tui/screens/verify_test.exs` — FOUND

Commits exist:
- `1f1b3f0` (Task 1) — FOUND
- `d072dd6` (Task 2) — FOUND
- `34ecdf6` (Task 3) — FOUND
- `42ecf23` (Task 4) — FOUND

All 21 tests pass (16 existing + 5 new). `mix compile --warnings-as-errors` clean for `verify.ex`. `mix format --check-formatted` clean for both files.
