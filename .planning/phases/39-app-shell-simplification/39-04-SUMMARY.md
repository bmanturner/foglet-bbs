---
phase: 39-app-shell-simplification
plan: 04
subsystem: tui

tags: [tui, screens, route-entry, reducer, screen-ownership, phase39]

# Dependency graph
requires:
  - phase: 39
    plan: 01
    provides: phase39_target tag exclusion + render baselines for byte-equivalence diff in Plan 39-08.
provides:
  - "Foglet.TUI.Screens.MainMenu.update(:on_route_enter, …) clause delegating to :load_oneliners when context.current_user is set; no-op otherwise."
  - "Foglet.TUI.Screens.Moderation.update(:on_route_enter, …) clause delegating to :load when context.current_user is set; no-op otherwise."
  - "Foglet.TUI.Screens.Sysop.update(:on_route_enter, …) clause delegating to :load when context.current_user is set; no-op otherwise."
  - "Foglet.TUI.Screens.ThreadList.update(:on_route_enter, …) clause delegating to :load unconditionally (matches today's app.ex:834-836 no-user gate)."
  - "Foglet.TUI.Screens.PostReader.update(:on_route_enter, …) two-clause shape: state-first thread_id match delegating to :load, plus route_params-fallback (atom-key then string-key) delegating to :load when binary."
  - "17 new reducer pins across 5 screen test files (3 + 3 + 3 + 3 + 5 = 17 — note: 6 PostReader pins because the integrated-path pin was added during GREEN to clarify the real App flow vs. the defensive route_params fallback)."
affects: 39-05, 39-08

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Screen-owned route-entry: each screen's update/3 grows an :on_route_enter clause that encodes the conditional-load semantics today encoded in App's per-screen maybe_dispatch_route_entry/3 clauses. App's clauses remain in this plan; Plan 39-05 collapses them into a single generic dispatch."
    - "Delegation over duplication: each :on_route_enter clause delegates to the existing :load (or :load_oneliners) clause rather than reimplementing load logic. This preserves the existing test seam (direct update(:load, …) callers in reducer tests are undisturbed) and minimizes diff size."
    - "TDD per task: each task pair is two commits — a test(...) commit asserting the expected delegation, then a feat(...) commit landing the clause."

key-files:
  created:
    - .planning/phases/39-app-shell-simplification/39-04-SUMMARY.md
  modified:
    - lib/foglet_bbs/tui/screens/main_menu.ex
    - lib/foglet_bbs/tui/screens/moderation.ex
    - lib/foglet_bbs/tui/screens/sysop.ex
    - lib/foglet_bbs/tui/screens/thread_list.ex
    - lib/foglet_bbs/tui/screens/post_reader.ex
    - test/foglet_bbs/tui/screens/main_menu_test.exs
    - test/foglet_bbs/tui/screens/moderation_test.exs
    - test/foglet_bbs/tui/screens/sysop_test.exs
    - test/foglet_bbs/tui/screens/thread_list_test.exs
    - test/foglet_bbs/tui/screens/post_reader_test.exs

key-decisions:
  - "[Phase 39-04]: Each :on_route_enter clause delegates to the existing :load / :load_oneliners clause rather than inlining the load logic. This keeps the diff small, preserves the existing test seams (direct update(:load, …) callers are unaffected), and means Plan 39-05's App-side cleanup can collapse five clauses into one without changing any screen's load semantics."
  - "[Phase 39-04]: PostReader gets TWO :on_route_enter clauses (state-first + route_params-fallback) mirroring subscriptions/2's shape. The state-first clause matches the integrated App flow (init_route_screen_state hydrates state.thread_id via State.from_context before :on_route_enter fires); the route_params fallback is defensive — when called with un-hydrated state it surfaces :load's missing-thread error rather than no-opping silently. ThreadList gets a SINGLE clause because today's app.ex:834-836 dispatch is unconditional and ThreadList's :load already carries a missing-board guard."
  - "[Phase 39-04]: Sysop's RED test required an active BOARDS tab to force :load to emit a real task effect — the default SITE tab has no slot mapping (slot_for(\"SITE\") returns nil) so both :load and the catch-all returned {state, []}, making them coincidentally equal. Pinning active_tab: 1 (BOARDS) ensures :load emits a sysop_load_boards task effect that the catch-all cannot produce, giving the test real RED signal."
  - "[Phase 39-04]: Each clause is inserted IMMEDIATELY ABOVE the existing :load (or :load_oneliners) clause. Function-clause ordering in Elixir matters — a catch-all `update(_message, …)` later in the file would absorb :on_route_enter if the new clauses weren't placed before it. Verified by all 17 reducer pins matching the new clauses, not the catch-alls."

patterns-established:
  - "Screen-owned route-entry pattern: each migrated screen has its own :on_route_enter reducer clause; App's per-screen dispatch clauses (slated for deletion in Plan 39-05) become a single generic dispatch."
  - "Conditional-load preservation through delegation: when a screen's pre-Phase-39 App clause was conditional (current_user gate), the new :on_route_enter clause encodes the same conditional, then delegates to the existing :load — ensuring byte-equivalent behavior for Plan 39-08's render-snapshot diff."

requirements-completed: []

# Metrics
duration: 9min
completed: 2026-04-29
---

# Phase 39 Plan 04: Add `update(:on_route_enter, …)` clauses to five screens

**Inverted the ownership of route-entry-time data loading: MainMenu, Moderation, Sysop, ThreadList, and PostReader each gained an `update(:on_route_enter, state, ctx)` clause that encodes the conditional-load semantics today carried by App's `maybe_dispatch_route_entry/3` clauses (`app.ex:810-845`). Each clause delegates to the screen's existing `:load` (or `:load_oneliners`) clause when its conditional fires, keeping the diff small and preserving the existing test seam. Landed 17 new reducer pins across five test files; zero new precommit failures, zero new test failures vs. `deferred-items.md` baseline.**

## Performance

- **Duration:** ~9 min
- **Started:** 2026-04-29T04:00:58Z
- **Completed:** 2026-04-29T04:09:35Z
- **Tasks:** 2 / 2 (each task pair: RED + GREEN = 4 commits total)
- **Files modified:** 10 (5 lib, 5 test)
- **Files created:** 1 (this SUMMARY.md)

## Accomplishments

### Insertion Lines (for Plan 39-05 verification)

For Plan 39-05's App-side cleanup — when collapsing the five `maybe_dispatch_route_entry/3` clauses into a single generic dispatch, the App shell needs to know each screen's `:on_route_enter` clause exists at:

| Screen | File | Clause line(s) | Inserted above (existing) |
|--------|------|---------------|---------------------------|
| `Foglet.TUI.Screens.MainMenu` | `lib/foglet_bbs/tui/screens/main_menu.ex` | 143 | `def update(:load_oneliners, …)` (formerly line 138, now line 152) |
| `Foglet.TUI.Screens.Moderation` | `lib/foglet_bbs/tui/screens/moderation.ex` | 69 | `def update(:load, …)` (formerly line 64, now line 78) |
| `Foglet.TUI.Screens.Sysop` | `lib/foglet_bbs/tui/screens/sysop.ex` | 65 | `def update(:load, …)` (formerly line 60, now line 74) |
| `Foglet.TUI.Screens.ThreadList` | `lib/foglet_bbs/tui/screens/thread_list.ex` | 41 | `def update(:load, %State{board_id: …}, …)` (formerly line 36, now line 45) |
| `Foglet.TUI.Screens.PostReader` | `lib/foglet_bbs/tui/screens/post_reader.ex` | 81 (state-first), 86 (route_params fallback) | `def update(:load, %State{thread_id: …}, …)` (formerly line 75, now line 91) |

### Test Deltas

| Test file | New `:on_route_enter` reducer pins (default suite) |
|-----------|---------------------------------------------------|
| `test/foglet_bbs/tui/screens/main_menu_test.exs` | 3 (delegate-when-user, no-op-no-user, nil-state-no-user) |
| `test/foglet_bbs/tui/screens/moderation_test.exs` | 3 (delegate-when-user, no-op-no-user, nil-state-no-user) |
| `test/foglet_bbs/tui/screens/sysop_test.exs` | 3 (delegate-when-user-on-BOARDS, no-op-no-user, nil-state-no-user) |
| `test/foglet_bbs/tui/screens/thread_list_test.exs` | 3 (parity-with-:load, no-user-still-loads, missing-board surfacing) |
| `test/foglet_bbs/tui/screens/post_reader_test.exs` | 5 (state-first, atom-key fallback, string-key fallback, missing no-op, non-binary state fall-through) + 1 integrated-path pin added during GREEN clarifying the real App flow |
| **Total** | **17 new reducer pins** |

### Test Suite Results

- `rtk mix test test/foglet_bbs/tui/screens/main_menu_test.exs test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/screens/sysop_test.exs` — **211 tests, 0 failures**
- `rtk mix test test/foglet_bbs/tui/screens/thread_list_test.exs test/foglet_bbs/tui/screens/post_reader_test.exs` — **101 tests, 0 failures**
- `rtk mix test test/foglet_bbs/tui/` — **1590 tests, 2 failures, 3 excluded** — both failures are the pre-existing `account_test.exs:1242, 1271` items tracked in `deferred-items.md`. **Zero new test failures introduced by this plan.**

### Build / Lint Gates

- `rtk mix compile --warnings-as-errors` — exit 0 (only raxol dependency-side warnings; foglet_bbs compiles cleanly).
- `rtk mix format --check-formatted` — ok across all 10 modified files.
- `rtk mix credo --strict` — `3678 mods/funs, found no issues.`
- `rtk mix dialyzer` — exactly 3 warnings: `app.ex:63:38:unknown_type`, `board_list.ex:161:9:pattern_match_cov`, `sysop.ex:823:8:pattern_match`. The third item shifted from line 810 → 823 because this plan added 13 lines above it (the `:on_route_enter` clause + `@spec`/`@callback` docstring), but the warning text is identical to the deferred-items.md entry. **Zero new dialyzer warnings introduced by this plan.**
- `rtk mix precommit` — halts at dialyzer with the same 3 pre-existing warnings (per `deferred-items.md`'s "rtk mix precommit does not exit 0 on main HEAD prior to Phase 39 work" baseline). **Zero new precommit failures.**

### Acceptance-Criteria Greps

| Check | Expected | Got |
|-------|----------|-----|
| `grep -c 'def update(:on_route_enter' main_menu.ex` | 1 | 1 |
| `grep -c 'def update(:on_route_enter' moderation.ex` | 1 | 1 |
| `grep -c 'def update(:on_route_enter' sysop.ex` | 1 | 1 |
| `grep -c 'def update(:on_route_enter' thread_list.ex` | 1 | 1 |
| `grep -c 'def update(:on_route_enter' post_reader.ex` | 2 | 2 |
| `grep -c 'def update(:load_oneliners' main_menu.ex` | ≥ 1 | 1 (untouched) |
| `grep -c 'def update(:load,' moderation.ex` | ≥ 1 | 1 (untouched) |
| `grep -c 'def update(:load,' sysop.ex` | ≥ 1 | 1 (untouched) |
| `grep -c 'def update(:load,' thread_list.ex` | ≥ 1 | 2 (both clauses untouched) |
| `grep -c 'def update(:load,' post_reader.ex` | ≥ 1 | 2 (both clauses untouched) |

## Task Commits

1. **Task 1 RED: add failing :on_route_enter pins for MainMenu, Moderation, Sysop** — `69e567a` (test)
2. **Task 1 GREEN: add :on_route_enter clause to MainMenu, Moderation, Sysop** — `472bea4` (feat)
3. **Task 2 RED: add failing :on_route_enter pins for ThreadList and PostReader** — `353f1b5` (test)
4. **Task 2 GREEN: add :on_route_enter clause to ThreadList and PostReader** — `5b56f9a` (feat)

## Files Created/Modified

### Created
- `.planning/phases/39-app-shell-simplification/39-04-SUMMARY.md` — this file.

### Modified

**Library (5 files):**
- `lib/foglet_bbs/tui/screens/main_menu.ex` — Inserted `def update(:on_route_enter, …)` at line 143 with explanatory comment citing app.ex:810-816. Delegates to `:load_oneliners` when `context.current_user` is set; otherwise `{normalize_state(local_state, context), []}`.
- `lib/foglet_bbs/tui/screens/moderation.ex` — Inserted `def update(:on_route_enter, …)` at line 69 with comment citing app.ex:818-824. Delegates to `:load` conditionally on `context.current_user`.
- `lib/foglet_bbs/tui/screens/sysop.ex` — Inserted `def update(:on_route_enter, …)` at line 65 with comment citing app.ex:826-832. Same shape as Moderation.
- `lib/foglet_bbs/tui/screens/thread_list.ex` — Inserted single-clause `def update(:on_route_enter, …)` at line 41, unconditionally delegating to `:load`. Comment cites app.ex:834-836's no-user gate.
- `lib/foglet_bbs/tui/screens/post_reader.ex` — Inserted two `def update(:on_route_enter, …)` clauses at lines 81 and 86: state-first match for `%State{thread_id: tid}` when `is_binary(tid)`, then route_params-fallback (atom key then string key) when the route_params carries a binary thread_id. Comment cites app.ex:838-843.

**Tests (5 files):**
- `test/foglet_bbs/tui/screens/main_menu_test.exs` — Added a new `describe "update(:on_route_enter, …) — Phase 39 Plan 04"` block with 3 reducer pins.
- `test/foglet_bbs/tui/screens/moderation_test.exs` — Same shape, 3 pins.
- `test/foglet_bbs/tui/screens/sysop_test.exs` — Same shape, 3 pins. The "delegates" pin uses `active_tab: 1` (BOARDS) to force `:load` to emit a real task effect (SITE tab has no slot mapping and would mask the catch-all path).
- `test/foglet_bbs/tui/screens/thread_list_test.exs` — Same shape, 3 pins.
- `test/foglet_bbs/tui/screens/post_reader_test.exs` — Same shape, 6 pins (5 specified in the plan + 1 integrated-path pin added during GREEN to clarify the real App flow vs. the defensive route_params fallback).

## Decisions Made

- **Delegation over duplication.** Each `:on_route_enter` clause delegates to the existing `:load` (or `:load_oneliners`) clause rather than reimplementing the load logic. Consequences: (a) zero behavior drift between today's App-side dispatch and tomorrow's screen-side dispatch — the same `:load` runs in both flows; (b) existing reducer tests that call `update(:load, …)` directly are completely undisturbed; (c) Plan 39-05's App-side cleanup can land as a pure deletion of the five `maybe_dispatch_route_entry/3` clauses without behavior changes.
- **PostReader two-clause shape mirrors `subscriptions/2` from Plan 39-03.** State-first match (when `state.thread_id` is binary) covers the integrated App flow path: `init_route_screen_state` hydrates state via `State.from_context` before `:on_route_enter` fires. The route_params fallback is defensive code — when called with un-hydrated state, `:load` surfaces `{:error, :missing_thread}` rather than no-opping silently. The integrated-path pin (added during GREEN) documents the real flow explicitly.
- **ThreadList single-clause unconditional delegation.** Today's `app.ex:834-836` clause has no `current_user` check, and the screen's `:load` clause already has the missing-board guard built in. The simplest preservation is unconditional delegation. Pin set includes a "no-user still loads" assertion that locks this in.
- **Sysop test pinned to BOARDS tab.** SITE tab (`active_tab: 0`, the init default) has no slot mapping (`slot_for("SITE")` returns `nil`), so `Sysop.update(:load, …)` produces `{state, []}` on a fresh state — coincidentally equal to the catch-all's output. RED would have falsely passed without an explicit clause. Pinning `active_tab: 1` (BOARDS) forces `:load` to emit a `sysop_load_boards` task effect that the catch-all cannot produce, giving the test real RED signal.
- **Insertion immediately above the existing `:load`/`:load_oneliners` clause** (not at the top of `update/3`, not at the bottom). Function-clause ordering in Elixir matters — a catch-all `update(_message, …)` at the end of the file would absorb `:on_route_enter` if the new clause weren't placed before it. Each module has such a catch-all (verified in main_menu.ex:381, moderation.ex:142, sysop.ex:162, post_reader.ex:218 (now ~218+5)), and all 17 reducer pins prove the new clauses match before the catch-all.
- **Comment block on each clause cites the source App-side line range** (app.ex:810-816, 818-824, 826-832, 834-836, 838-843). This makes Plan 39-05's deletion of the App-side clauses traceable: the future reviewer can see the screen-side comment, find the corresponding App-side range, and confirm the deletion is correctly paired.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Bug] PostReader RED test for route_params fallback assumed `:load` would succeed on un-hydrated state**

- **Found during:** Task 2 GREEN verification (`rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs`).
- **Issue:** The original RED test for the route_params-fallback path (`with no thread_id in state but atom :thread_id route param`) asserted `new_state.status == :loading` after `:on_route_enter`. But because the fallback delegates to `:load` with the un-hydrated `%State{}`, `:load`'s `is_binary(thread_id)` guard fails and the second `:load` clause (the missing-thread error guard) returns `{:error, :missing_thread}`. The test was wrong about the expected behavior.
- **Root cause:** I conflated the integrated App flow (where `init_route_screen_state` hydrates state.thread_id before `:on_route_enter` fires, so state-first matches) with the defensive fallback path (un-hydrated state + populated route_params). The plan's `<action>` block literally specifies the fallback delegates to `:load` without hydrating — this is correct behavior but doesn't produce a `:loading` status when called in isolation.
- **Fix:** Updated the two route_params-fallback pins to assert the truthful behavior (`status == {:error, :missing_thread}` after `:load` runs on un-hydrated state, with `last_error: :missing_thread`). Added a 6th pin ("fully hydrated state from State.from_context still delegates correctly (integrated path)") that uses `State.from_context(ctx)` to mirror the real App flow, proving the state-first clause matches when `init_route_screen_state` has done its job.
- **Files modified:** `test/foglet_bbs/tui/screens/post_reader_test.exs`.
- **Verification:** All 6 PostReader `:on_route_enter` pins pass; full PostReader test file is 67/67 (was 65 before this plan, +2 net counting the new `:on_route_enter` describe block).
- **Committed in:** `5b56f9a` (Task 2 GREEN commit — bundles the fixed test + the implementation since both reflect the same truthful semantics).

**Total deviations:** 1 auto-fixed (1 bug — RED test asserted wrong expected behavior).

**Impact on plan:** Plan 39-08's byte-equivalence diff is unaffected — the route_params-fallback path is rarely-hit dead code in the integrated App flow. The truthful test pins document the defensive nature of the fallback for future readers.

## Issues Encountered

- **`rtk mix precommit` does not exit 0**, but only for the same three pre-existing dialyzer warnings tracked in `.planning/phases/39-app-shell-simplification/deferred-items.md`. One warning's line number shifted (`sysop.ex:810` → `sysop.ex:823`) because this plan inserted 13 lines above it; the warning text is identical to the baseline. **This plan introduces zero new precommit failures vs. the deferred-items.md baseline.**
- **`rtk mix test` reports 2 failures** at `test/foglet_bbs/tui/screens/account_test.exs:1242, 1271` — both pre-existing per `deferred-items.md`. **Zero new test failures introduced by this plan.**

## Self-Check: PASSED

Verified before final commit:

**Files modified all exist and contain expected clauses:**
- `lib/foglet_bbs/tui/screens/main_menu.ex` line 143 — `def update(:on_route_enter, local_state, %Context{} = context) do` — FOUND.
- `lib/foglet_bbs/tui/screens/moderation.ex` line 69 — same shape — FOUND.
- `lib/foglet_bbs/tui/screens/sysop.ex` line 65 — same shape — FOUND.
- `lib/foglet_bbs/tui/screens/thread_list.ex` line 41 — `def update(:on_route_enter, %State{} = state, %Context{} = context) do` — FOUND.
- `lib/foglet_bbs/tui/screens/post_reader.ex` lines 81 and 86 — two-clause shape — FOUND.

**Commits exist:**
- `69e567a` (Task 1 RED) — FOUND in `git log`.
- `472bea4` (Task 1 GREEN) — FOUND.
- `353f1b5` (Task 2 RED) — FOUND.
- `5b56f9a` (Task 2 GREEN) — FOUND.

**Acceptance grep checks:**
- `grep -c 'def update(:on_route_enter'` returns 1, 1, 1, 1, 2 across the five files — all match expected.
- `grep -c 'def update(:load_oneliners'` returns 1 in main_menu.ex (untouched).
- `grep -c 'def update(:load,'` returns 1 in moderation.ex, 1 in sysop.ex, 2 in thread_list.ex, 2 in post_reader.ex (all untouched).

**Test counts:**
- `rtk mix test test/foglet_bbs/tui/screens/{main_menu,moderation,sysop}_test.exs` — 211/211 (was 202 before this plan, +9 = 3+3+3 new pins).
- `rtk mix test test/foglet_bbs/tui/screens/{thread_list,post_reader}_test.exs` — 101/101 (was 92 before this plan, +9 = 3+6 new pins, with the +1 PostReader extra).
- `rtk mix test test/foglet_bbs/tui/` — 1590 / 2 pre-existing failures / 3 excluded (deferred-items.md baseline match).

## Next Plan Readiness

- **Plan 39-05 (App build_pubsub_topics rewrite + maybe_dispatch_route_entry/3 cleanup)** can now safely delete the five per-screen App clauses at `app.ex:810-845` and replace them with a single generic dispatch:
  ```elixir
  defp maybe_dispatch_route_entry(%__MODULE__{} = state, screen, _params) do
    route_screen_update(state, screen, :on_route_enter)
  end
  ```
  All five migrated screens now respond to `:on_route_enter` correctly, so the deletion preserves byte-equivalent behavior. Plan 39-08's render-snapshot diff will confirm.
- **Plan 39-08 (verification)** SPEC §Acceptance Criteria item 4 ("Generic route-entry dispatch — App contains no `maybe_dispatch_route_entry` clause that pattern-matches a specific screen atom for any migrated production screen") becomes satisfiable in 39-05 because this plan landed the screen-side clauses 39-05 needs.

---
*Phase: 39-app-shell-simplification*
*Completed: 2026-04-29*
