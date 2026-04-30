---
phase: 46-domain-cleanup-and-final-quality-gate
plan: 02
subsystem: domain
tags: [boards, genserver, ecto-multi, repo-transaction, documentation, domain-cleanup]

# Dependency graph
requires:
  - phase: 46
    provides: "DOM-01 (Boards.Supervisor stub deletion) — leaves Foglet.Boards.Server as the canonical write-path module"
provides:
  - "Documented and locked rationale for Foglet.Boards.Server's direct Repo.transaction/1 + Ecto.Multi usage (intentional deviation from project-wide Repo.transact/1 convention)"
  - "Single-source-of-truth pointer pattern: inline comments above Repo.transaction call sites reference the @moduledoc instead of duplicating rationale"
affects: [46-03 (QUAL-01 Dialyzer narrowing), 46-04 (QUAL-03 baseline cleanup), future maintainers reading boards/server.ex]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Documented exception to Repo.transact/1 convention via moduledoc subheader"
    - "Inline pointer comments back to moduledoc (no duplication of rationale)"

key-files:
  created: []
  modified:
    - lib/foglet_bbs/boards/server.ex

key-decisions:
  - "Boards.Server.run_post_insert_multi/5 and run_thread_create_multi/4 keep direct Repo.transaction/1 + Ecto.Multi usage; Multi step labels :post and :thread_update are load-bearing for handle_call pattern matches and converting to Repo.transact/1 would require manually rebuilding the result map at every call site without observable behavior change"
  - "Inline comments above the two call sites reference @moduledoc rather than restating rationale (single-source-of-truth)"

patterns-established:
  - "DOM-02 documentation pattern: when a module is an intentional exception to a project-wide convention, add a level-2 moduledoc subheader explaining why, and place a one-line pointer comment above each affected call site that references back to the moduledoc"

requirements-completed: [DOM-02]

# Metrics
duration: ~10min
completed: 2026-04-29
---

# Phase 46 Plan 02: DOM-02 Boards.Server Transaction Strategy Documentation Summary

**Documented and locked Foglet.Boards.Server's direct Repo.transaction/1 + Ecto.Multi usage as an intentional deviation from the project-wide Repo.transact/1 convention, via @moduledoc subheader plus single-source-of-truth inline pointer comments.**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-04-29 (worktree session)
- **Completed:** 2026-04-29
- **Tasks:** 3
- **Files modified:** 2 (lib/foglet_bbs/boards/server.ex; deferred-items.md for pre-existing issue tracking)

## Accomplishments

- Added `## Transaction strategy` subheader to `Foglet.Boards.Server` @moduledoc, parallel in structure to existing `## Message number allocation` and `## Crash recovery (D-05)` subheaders.
- Added two single-line `# Multi step labels :post / :thread_update are load-bearing — see @moduledoc` pointer comments above the `|> Repo.transaction()` call at the end of `run_post_insert_multi/5` and `run_thread_create_multi/4`.
- Verified module still compiles with `--warnings-as-errors`; observable behavior unchanged (no Multi step renames, no spec changes, no body edits).
- Logged a pre-existing `mix credo --strict` warning (Logger metadata key in `lib/foglet_bbs/sessions/session.ex:196`) to `deferred-items.md` for plan 46-04 triage; it is unrelated to plan-02 scope.

## Task Commits

1. **Task 1: Add `## Transaction strategy` subheader to @moduledoc (D-01)** — `e99e24da` (docs)
2. **Task 2: Add inline pointer comments above lines 154 and 196 (D-02)** — `b54b14ad` (docs)
3. **Task 3: Run precommit + test floor (D-14 cadence gate)** — `049173ed` (docs; deferred-items log)

## Files Created/Modified

- `lib/foglet_bbs/boards/server.ex` — Added `## Transaction strategy` moduledoc subheader (~lines 28-46) and two inline pointer comments (now at lines 171 and 214, immediately preceding `|> Repo.transaction()` at lines 172 and 215).
- `.planning/phases/46-domain-cleanup-and-final-quality-gate/deferred-items.md` — Logged pre-existing credo --strict Logger metadata warning at `lib/foglet_bbs/sessions/session.ex:196`.

## Final moduledoc subheader text (verbatim)

```
  ## Transaction strategy

  This module is the intentional, locked deviation from `Repo.transact/1`,
  the project-wide convention for multi-row writes. The two write paths,
  `run_post_insert_multi/5` and `run_thread_create_multi/4`, end with
  `|> Repo.transaction()` directly so the success result preserves the
  `Ecto.Multi` step map.

  The Multi step labels `:post` and `:thread_update` are load-bearing.
  The `handle_call` clauses at lines 86-93 and 102-108 pattern-match on
  `{:ok, %{post: post}}` and `{:ok, %{thread_update: thread, post: post}}`
  to extract the success-side values; renaming or restructuring these
  labels would silently break message-number allocation. Converting to
  `Repo.transact/1` would require manually rebuilding the result map at
  every call site without changing observed behavior, and the `GenServer`
  reply contract is locked, so this divergence stays.
```

## Inline pointer comments

Both comment sites use the identical text and indentation (4 spaces, matching the pipe-operator column):

- **Line 171** (immediately above `|> Repo.transaction()` at line 172, end of `run_post_insert_multi/5`):
  ```
      # Multi step labels :post / :thread_update are load-bearing — see @moduledoc
  ```
- **Line 214** (immediately above `|> Repo.transaction()` at line 215, end of `run_thread_create_multi/4`):
  ```
      # Multi step labels :post / :thread_update are load-bearing — see @moduledoc
  ```

The pre-edit plan referenced lines 154 and 196 as the call-site lines; after Task 1's moduledoc insert (+17 lines) and Task 2's two comment inserts (+1 each), the calls now sit at lines 172 and 215. CONCERNS.md / SPEC line-number references in the planning corpus describe pre-edit state and remain accurate as point-in-time records.

## Cadence gate observations

- `rtk mix compile --warnings-as-errors` — exit 0 (no new warnings introduced by the moduledoc text or inline comments).
- `rtk mix format --check-formatted` — exit 0.
- `rtk mix sobelow --exit Low` — exit 0.
- `rtk mix credo --strict` — exit 16. Single warning: `Logger metadata key event, session_pid, user_id, handle, ssh_peer, replacement not found in Logger config. lib/foglet_bbs/sessions/session.ex:196`. **Pre-existing on baseline commit `c672accb`** — fires against unmodified `Foglet.Sessions.Session` code; impossible for plan-02's `boards/server.ex` doc edits to influence Logger metadata config in `Foglet.Sessions.Session`. Logged to `deferred-items.md` for plan 46-04 (QUAL-03) triage.
- `rtk mix test` — exit 2. Test summary: **`1 property, 2225 tests, 5 failures`**. All 5 failures are in `Foglet.TUI.AppTest` and match the deferred list previously logged in `deferred-items.md` from plan 46-01 (root cause: `Foglet.TUI.AppTest.FakePosts.list_reader_window/2` undefined — a test-fixture issue unrelated to `boards/server.ex`). 2225 tests is well above the D-14 floor of 2161; the 5 deferred failures are tracked for plan 46-04.

Failing tests recorded:
1. `update/2 (SSH-06, SSH-08) {:screen_task_result, :post_composer, :submit_reply, result} routes through PostComposer local state`
2. `update/2 (SSH-06, SSH-08) navigating to post_reader initializes local state and queues generic post loading`
3. `update/2 (SSH-06, SSH-08) navigating post_reader from one thread to another refreshes route-owned local state`
4. `PubSub message handlers (Audit #12) {:thread_activity, thread_id, event} on active :post_reader routes through local state`
5. `App-routed sysop screen tasks (Phase 38) {:navigate, :sysop} on SITE-active state emits no command (D-03 sync)`

These are a subset of the 13 pre-existing `Foglet.TUI.AppTest` failures already documented in `deferred-items.md` (full-suite intermittently shows 5).

## Decisions Made

- **Match existing moduledoc tone, no `(D-XX)` suffix on the new subheader.** The existing `(D-05)` on `## Crash recovery` is a real backreference to a CONTEXT decision, not a stylistic suffix. The new subheader uses plain `## Transaction strategy`, matching `## Message number allocation`'s naming style.
- **Inline comments are pointers, not duplicates.** Each comment is one line and references `@moduledoc`; the rationale lives only in the moduledoc (single-source-of-truth pattern from PATTERNS.md).
- **No spec narrowing.** The `:call_without_opaque` Dialyzer concern is plan 46-03 (QUAL-01) work, explicitly out of scope here.

## Deviations from Plan

None — plan executed exactly as written. The pre-existing credo warning and TUI test failures encountered during the cadence gate are pre-existing on baseline (commit `c672accb`), affect files unrelated to this plan's scope (`sessions/session.ex` and `tui/app_test.exs`), and were logged to `deferred-items.md` per the executor scope-boundary rule.

## Issues Encountered

- **`mix credo --strict` exits 16 due to pre-existing Logger metadata warning** in `lib/foglet_bbs/sessions/session.ex:196`. Verified pre-existing on base commit `c672accb` (unmodified by this plan). Logged to `deferred-items.md` for plan 46-04 (QUAL-03) triage. Per scope-boundary rule, do NOT fix in this plan.
- **`mix test` shows 5 pre-existing failures in `Foglet.TUI.AppTest`** caused by a missing test fixture function `Foglet.TUI.AppTest.FakePosts.list_reader_window/2`. These are a subset of the 13 failures previously logged in `deferred-items.md` from plan 46-01. Routed to plan 46-04.

## User Setup Required

None — no external service configuration required.

## Pointer Note

Closes CONCERNS.md Security Considerations heading at line 151 — disposition will be applied in plan 04 (QUAL-03).

## Next Phase Readiness

- DOM-02 acceptance criteria met: a top-to-bottom reader of `lib/foglet_bbs/boards/server.ex` now encounters the rationale (`## Transaction strategy` at line 28) before the first `|> Repo.transaction()` call at line 172.
- Multi step labels `:post` and `:thread_update` and the `handle_call` pattern matches are unchanged; module observable behavior is preserved.
- Plan 46-03 (QUAL-01 Dialyzer `:call_without_opaque` fix) can proceed against this stable, documented call structure.
- Plan 46-04 (QUAL-03 baseline cleanup) inherits the now-accumulated deferred-items log: 13 TUI test failures plus the credo Logger-metadata warning, all pre-existing relative to phase 46 base.

## Self-Check: PASSED

Verified:
- `lib/foglet_bbs/boards/server.ex` exists and contains `## Transaction strategy` (1 match), `locked deviation from` (1 match), `Repo.transact/1` reference, and 2 inline `Multi step labels :post / :thread_update are load-bearing` comments.
- Commits exist in `git log`: `e99e24da` (Task 1 moduledoc), `b54b14ad` (Task 2 inline comments), `049173ed` (Task 3 deferred-items log).
- `rtk mix compile --warnings-as-errors` exits 0.
- Multi step labels `:post` (line 145, 193) and `:thread_update` (line 201) preserved at original positions; handle_call pattern matches at lines 104 (`{:ok, %{post: post}}`) and 120 (`{:ok, %{thread_update: thread, post: post}}`) preserved.

---
*Phase: 46-domain-cleanup-and-final-quality-gate*
*Completed: 2026-04-29*
