---
phase: 47-bound-unbounded-list-queries-drop-chrome-v1-shims-and-reduce
plan: 02
subsystem: database
tags: [ecto, threads, pagination, query-bounds, tdd]

requires:
  - phase: 44-domain-bounded-windows
    provides: trailing-keyword-opts pattern with normalize_*_limit/1 defaulting helper (Foglet.Posts.list_reader_window/2)
provides:
  - Foglet.Threads.list_threads/3 with bounded :limit defaulting to @page_size
  - Foglet.Threads.default_page_size/0 returning 50
  - Foglet.Threads.list_threads_query/3 — public query-builder for SQL inspection
  - SQL-layer LIMIT enforcement on both nil-user and binary-user branches
affects: [47-03, 47-04, 47-05]

tech-stack:
  added: []
  patterns:
    - "Trailing keyword opts on context list functions, mirroring Phase 44 list_reader_window/2"
    - "Public query-builder helper alongside execute helper, so tests (and future composition callers) can inspect generated SQL via Ecto.Adapters.SQL.to_sql/3"
    - "Centralised page size as a module attribute referenced by both the SQL LIMIT and a public default_page_size/0 accessor — single literal location"

key-files:
  created: []
  modified:
    - lib/foglet_bbs/threads.ex
    - test/foglet_bbs/threads/threads_test.exs

key-decisions:
  - "[Phase 47] Page size centralised as @page_size 50 module attribute on Foglet.Threads — not Foglet.Config (D-08). The SQL LIMIT and default_page_size/0 both reference @page_size; the literal 50 appears only on the declaration line."
  - "[Phase 47] :after / :before opts are documented in @doc but NOT validated, parsed, or rejected (D-06). Adding stub validators would introduce untested code paths."
  - "[Phase 47] list_threads_query/3 is a public @doc-ed helper rather than a private function. This gives tests a clean SQL-inspection surface without :private function reflection, and leaves room for future composition callers."
  - "[Phase 47] No @spec on default_page_size/0 — Dialyzer's success typing is the literal 50, and any pos_integer() spec triggers :contract_supertype. The codebase's .dialyzer_ignore.exs convention is to avoid broad supertype suppressions."

patterns-established:
  - "Bounded list functions in Foglet contexts: arity-1 and arity-2 are delegators, arity-N+ carries the keyword opts and the normalize_limit/1 defaulting helper"

requirements-completed: [R3, R4]

duration: 9min
completed: 2026-04-30
---

# Phase 47 Plan 02: Bound Foglet.Threads.list_threads Summary

**Bounded `Foglet.Threads.list_threads/{1,2,3}` to a centralised `@page_size 50` with SQL-layer `LIMIT`, exposed `default_page_size/0` and `list_threads_query/3` for SQL inspection, with zero call-site changes (R3 + R4).**

## Performance

- **Duration:** 9 min
- **Started:** 2026-04-30T12:39:03Z
- **Completed:** 2026-04-30T12:48:29Z
- **Tasks:** 1 (TDD: RED + GREEN, no REFACTOR needed)
- **Files modified:** 2

## Accomplishments

- `@page_size 50` module attribute centralises the bound; the literal `50` appears exactly once in `lib/foglet_bbs/threads.ex` (R4 acceptance grep verified)
- `default_page_size/0` returns `50` (R4)
- `list_threads/3 (board_id, user_id_or_nil, opts)` applies `LIMIT $` at the SQL layer; arity-1 and arity-2 forms delegate with `opts: []` so existing call sites (`ThreadList` screen, `app_test` fixtures) are untouched (R3 / D-05)
- `list_threads_query/3` exposes the bounded Ecto query without executing it, so tests assert `LIMIT` via `Ecto.Adapters.SQL.to_sql/3` for both branches (nil user and binary user)
- 8 new tests cover: `default_page_size/0`, 75-thread → 50-result bound (arity-1, arity-2 with reader, nil user), `[desc: sticky, desc: last_post_at]` ordering preserved within tiers, generated SQL contains `LIMIT` plus `50` in the parameter list, explicit `:limit` opt overrides default, and non-positive / non-integer `:limit` falls back defensively
- All 42 `Foglet.ThreadsTest` tests green; `mix precommit` clean (compile w/ warnings-as-errors, formatter, Credo, Sobelow, Dialyzer)
- `:after` / `:before` documented in `@doc` only; not parsed or validated (D-06)
- No `Foglet.Config` key added (D-08); no SQL `OFFSET` introduced

## Task Commits

TDD cycle for Task 1 produced two commits:

1. **Task 1 RED: failing tests for bounded list_threads/3** — `f5d0abe2` (test)
2. **Task 1 GREEN: bound list_threads to @page_size 50** — `c5e4e98f` (feat)

REFACTOR was skipped: the GREEN implementation followed the established Phase 44 trailing-opts pattern from the start, with no duplication or smell to address.

## Files Created/Modified

- `lib/foglet_bbs/threads.ex` — Added `@page_size 50`, `default_page_size/0`, two `list_threads/3` clauses (nil-user and binary-user branches with `limit: ^limit`), two `list_threads_query/3` clauses, `normalize_limit/1` defensive helper. Existing `list_threads/1` and `list_threads/2` converted to single-line delegators.
- `test/foglet_bbs/threads/threads_test.exs` — Added two `describe` blocks (`default_page_size/0`, `list_threads/{1,2,3} bounded`) with 8 new tests and a `seed_75_threads/2` fixture helper that varies `last_post_at` and `sticky` to make ordering observable.

## Decisions Made

- **Public `list_threads_query/3` rather than a private helper accessed via `@moduletag :internal`.** The plan's `<action>` step for Test 4 explicitly allowed picking whichever pattern is consistent with the repo. There is no existing precedent in this repo for `Ecto.Adapters.SQL.to_sql/3` inspection (`grep` returned no hits), so the cleanest option is a documented public helper. This leaves the door open for future composition callers and avoids private-function reflection in tests.
- **No `@spec` on `default_page_size/0`.** Dialyzer's success typing is the literal `50`; any `pos_integer()` spec triggers `:contract_supertype`. Because `.dialyzer_ignore.exs` deliberately avoids broad supertype suppressions (Phase 46 quality baseline), the spec was omitted with a comment explaining why.
- **Defensive `normalize_limit/1` falls back to `@page_size` for non-positive or non-integer overrides.** Mirrors the Phase 44 `normalize_reader_limit/1` precedent and is verified by the "non-positive or invalid :limit" test. This is consistent with D-06's spirit of accepting `opts` without strict validation while keeping behaviour deterministic.

## Deviations from Plan

None - plan executed exactly as written. The only structural choice not fully prescribed by the plan was the `list_threads_query/3` exposure (public vs private), which the plan's `<action>` step explicitly delegated to the executor.

## Issues Encountered

- **Dialyzer `:contract_supertype` warning on initial `default_page_size/0` `@spec`.** Resolved by removing the spec (see Decisions Made). Caught by `mix precommit` before the GREEN commit; not a runtime issue.
- **Worktree had no `_build` / deps installed.** Ran `rtk mix deps.get` once at the start of the GREEN phase. Not a deviation — expected setup for a fresh worktree.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 47-03 (next in wave 2) can rely on `Foglet.Threads.list_threads/3` and `default_page_size/0` as a stable pattern for bounding other list queries (e.g., `Foglet.Boards.list_boards`, directory queries) using the same trailing-opts + module-attribute idiom.
- The `list_threads_query/3` helper is available for any future plan that needs to compose or inspect the threads query (e.g., adding cursor pagination via the reserved `:after` / `:before` keys in a later milestone).
- Zero TUI-screen code changes required — `Foglet.TUI.Screens.ThreadList` continues to call `list_threads/2` and now transparently receives a bounded list.

## Self-Check: PASSED

- `lib/foglet_bbs/threads.ex` exists and contains `@page_size 50`, `def default_page_size`, two `def list_threads(..., opts)` arity-3 clauses with `limit: ^limit`, two `def list_threads_query` clauses — verified
- `test/foglet_bbs/threads/threads_test.exs` exists and contains the two new describe blocks plus `seed_75_threads/2` helper — verified
- Commits `f5d0abe2` and `c5e4e98f` exist in `git log --all` — verified
- All 42 tests in `test/foglet_bbs/threads/threads_test.exs` pass — verified
- `mix precommit` is green (compile, formatter, Credo, Sobelow, Dialyzer) — verified
- `grep -n "50" lib/foglet_bbs/threads.ex` returns exactly 1 hit on the `@page_size 50` line — verified

---
*Phase: 47-bound-unbounded-list-queries-drop-chrome-v1-shims-and-reduce*
*Completed: 2026-04-30*
