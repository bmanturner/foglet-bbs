---
phase: 46
plan: 01
subsystem: domain-boards
tags: [cleanup, dead-code, supervisor]
requires: []
provides:
  - "Single source of truth for board boot: Foglet.Boards.boot_board_servers/0"
affects:
  - "lib/foglet_bbs/boards/supervisor.ex (12 lines smaller)"
tech-stack:
  added: []
  patterns: ["dead-code deletion (no replacement; canonical impl already in place)"]
key-files:
  created: []
  modified:
    - "lib/foglet_bbs/boards/supervisor.ex"
decisions:
  - "Pre-existing failures in test/foglet_bbs/tui/app_test.exs are out of scope for DOM-01 (deletion of an unused stub) and were logged to deferred-items.md for plan 46-04 (QUAL-03) triage."
metrics:
  duration: "~6 minutes (post deps.get)"
  completed: 2026-04-29
requirements:
  - DOM-01
---

# Phase 46 Plan 01: Delete Misleading boot_board_servers/0 Stub — Summary

Deleted the no-op `Foglet.Boards.Supervisor.boot_board_servers/0` stub (and its `@doc` block) at `lib/foglet_bbs/boards/supervisor.ex:35-46`; canonical impl `Foglet.Boards.boot_board_servers/0` in `lib/foglet_bbs/boards.ex:40` is unchanged and is the single source of truth called by `FogletBbs.Application.start/2`.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Delete the boot_board_servers/0 stub and its @doc block | `24652c32` | `lib/foglet_bbs/boards/supervisor.ex` |
| 2 | Run precommit + test floor (D-14 cadence gate) | n/a (verification only) | n/a |

## Lines Deleted

- `lib/foglet_bbs/boards/supervisor.ex` pre-deletion: 47 lines
- `lib/foglet_bbs/boards/supervisor.ex` post-deletion: 34 lines
- Net: **−13 lines** (12 lines from the stub block + 1 surrounding blank line collapsed by the editor)

The deleted block (`@doc` + `def boot_board_servers do … :ok end`) was deleted as a single unit per Pitfall 4 (a dangling `@doc` would be a compile error).

## Caller Verification

Performed before and after the deletion:

| Check | Result |
|-------|--------|
| `grep -n "def boot_board_servers" lib/foglet_bbs/boards/supervisor.ex` | 0 matches (correct — stub removed) |
| `grep -n "def boot_board_servers" lib/foglet_bbs/boards.ex` | 1 match at line 40 (real impl untouched) |
| `grep -n "Foglet.Boards.boot_board_servers" lib/foglet_bbs/application.ex` | 1 match at line 32 (caller untouched) |
| `grep -rn "Foglet.Boards.Supervisor.boot_board_servers" lib/ test/` | 0 matches (no caller broken) |

## Cadence Gate (D-14)

| Gate | Result |
|------|--------|
| `rtk mix compile --warnings-as-errors` | exit 0 (clean — no dangling `@doc`, no broken caller) |
| `rtk mix precommit` | exit 0 (compile-warnings-as-errors, deps.unlock --unused, format, credo --strict, sobelow --exit Low, dialyzer all clean) |
| `rtk mix test` (full suite) | exit 0; summary: `1 property, 2225 tests, 5 failures` |

**Test count:** 2225 tests is **+64 above the v2.0 baseline floor of 2161** — D-14 count floor satisfied.

**Failure count:** 5 failures observed in the full suite, all in `Foglet.TUI.AppTest`. Verified pre-existing against the base commit `a66ef4a7` (running the same test file with the unmodified supervisor.ex shows the same family of failures, deterministic across seeds 0 and 1). DOM-01 deletes an unused stub in `Foglet.Boards.Supervisor` that has no relationship to `Foglet.TUI.AppTest`; causal isolation holds. Logged to `deferred-items.md` for plan 46-04 (QUAL-03) triage.

The plan introduced **0 new test regressions and 0 new dialyzer warnings** (the deleted function had no `@spec`, so QUAL-01 buckets B/C are unaffected).

## Deviations from Plan

None — plan executed exactly as written. The pre-existing AppTest failures were detected during the cadence gate, verified against the phase base commit to be unrelated to DOM-01, and routed to deferred-items.md per the SCOPE BOUNDARY rule (only auto-fix issues directly caused by the current task's changes).

## Pointer

Closes CONCERNS.md Tech Debt heading at line 89 — disposition will be applied in plan 46-04 (QUAL-03).

## Self-Check: PASSED

- `lib/foglet_bbs/boards/supervisor.ex` — FOUND, post-deletion content verified.
- Commit `24652c32` — FOUND in `git log` (`24652c32 refactor(46-01): delete misleading boot_board_servers/0 stub`).
- `.planning/phases/46-domain-cleanup-and-final-quality-gate/deferred-items.md` — created.
