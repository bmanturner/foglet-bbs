---
phase: 39-app-shell-simplification
plan: 01
subsystem: testing

tags: [tui, raxol, exunit, golden-snapshot, pin-tests, phase39_target]

# Dependency graph
requires:
  - phase: 38-account-operator-workbenches
    provides: Final pre-Phase-39 production-screen reducer contracts (Account, Moderation, Sysop migrated). Five tracked screens render cleanly via mix foglet.tui.render so baseline capture is meaningful.
provides:
  - Pre-phase render baselines (ANSI-stripped, 80x24) for main_menu, board_list, thread_list, post_reader, account at test/foglet_bbs/tui/render_snapshots/
  - phase39_target ExUnit tag wired into test_helper.exs so tagged tests are excluded from default mix test
  - Wave 0 fail-loud pin tests on App struct shape (D-19 / R1)
  - Wave 0 fail-loud pin tests on Screen.subscriptions/2 optional-callback contract (R6, D-05)
  - Wave 0 fail-loud pin tests on PostReader / ThreadList / BoardList subscriptions/2 exports (D-08, D-22 / R6, R7)
  - Wave 0 fail-loud pin test on MainMenu subscribe/1 producing only ['user:<id>'] (D-18)
affects: 39-02, 39-03, 39-04, 39-05, 39-06, 39-07, 39-08

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Pin-test gating: tag tests with @tag :phase39_target and exclude in test_helper.exs so default suite stays green; later waves drop tags as work lands."
    - "Golden render snapshots under test/foglet_bbs/tui/render_snapshots/ consumed by Plan 39-08 byte-equivalence diff."

key-files:
  created:
    - test/foglet_bbs/tui/app_struct_test.exs
    - test/foglet_bbs/tui/render_snapshots/main_menu.txt
    - test/foglet_bbs/tui/render_snapshots/board_list.txt
    - test/foglet_bbs/tui/render_snapshots/thread_list.txt
    - test/foglet_bbs/tui/render_snapshots/post_reader.txt
    - test/foglet_bbs/tui/render_snapshots/account.txt
    - .planning/phases/39-app-shell-simplification/deferred-items.md
  modified:
    - test/test_helper.exs
    - test/foglet_bbs/tui/screen_test.exs
    - test/foglet_bbs/tui/screens/post_reader_test.exs
    - test/foglet_bbs/tui/screens/thread_list_test.exs
    - test/foglet_bbs/tui/screens/board_list_test.exs
    - test/foglet_bbs/tui/app_test.exs
    - test/foglet_bbs/tui/screens/post_composer_test.exs
    - lib/foglet_bbs/tui/screens/new_thread/state.ex

key-decisions:
  - "[Phase 39-01]: Wave 0 pin tests use the :phase39_target ExUnit tag and live behind a default-suite exclusion (test_helper.exs); later waves and Plan 39-08 drop the tag as the matching work lands. This preserves green default mix test while giving Wave 0 a fail-loud target the included-tag run will catch."
  - "[Phase 39-01]: Render baselines were captured at default 80x24 with the same ANSI-strip pipeline Plan 39-08 will use, so byte-equivalence diff in 39-08 compares apples-to-apples."

patterns-established:
  - "phase39_target tag pattern: Wave 0 ships tagged tests that are excluded by default; subsequent waves remove tags as their work lands."
  - "Render snapshot pattern: ANSI-stripped text fixtures under test/foglet_bbs/tui/render_snapshots/ as golden references for byte-equivalence diff."

requirements-completed: [STATE-02, STATE-04, APP-01, APP-03]

# Metrics
duration: 22min
completed: 2026-04-29
---

# Phase 39 Plan 01: Wave-0 baseline capture and fail-loud pin tests

**Captured five ANSI-stripped pre-phase render snapshots and added six tagged Wave-0 pin tests (struct shape, optional-callback, three subscriptions/2 exports, MainMenu user-only topic) gated behind a phase39_target exclusion in test_helper.exs so the default suite stays green.**

## Performance

- **Duration:** ~22 min
- **Started:** 2026-04-29T03:21:46Z
- **Completed:** 2026-04-29T03:43:59Z
- **Tasks:** 2 / 2
- **Files modified:** 9 (incl. 1 new test file)
- **Files created:** 7 (5 baselines, 1 test file, 1 deferred-items.md)

## Accomplishments

- Five render baseline `.txt` files captured at 80x24, ANSI-stripped, ready as golden references for Plan 39-08 byte-equivalence diff. Sizes range 2.6K–3.0K; `! grep -P '\x1b\[' test/foglet_bbs/tui/render_snapshots/*.txt` exits 0.
- New `test/foglet_bbs/tui/app_struct_test.exs` pins the post-Phase-39 eight-field App struct shape and refutes the seven legacy fields. Today, both tests fail under `--include phase39_target` because the struct still carries the legacy fields — that is the intended fail-loud signal that proves the pin will catch the deletion in Plan 39-07.
- Five existing test files gained one new tagged describe each:
  - `screen_test.exs` — `{:subscriptions, 2}` in `Foglet.TUI.Screen.behaviour_info(:optional_callbacks)`
  - `post_reader_test.exs` — `function_exported?(Foglet.TUI.Screens.PostReader, :subscriptions, 2)`
  - `thread_list_test.exs` — `function_exported?(Foglet.TUI.Screens.ThreadList, :subscriptions, 2)`
  - `board_list_test.exs` — `function_exported?(Foglet.TUI.Screens.BoardList, :subscriptions, 2)`
  - `app_test.exs` — `App.subscribe/1` for authenticated `:main_menu` returns `pubsub_sub.data.args.topics == ["user:u1"]`
- `test/test_helper.exs` adds `:phase39_target` to the default ExUnit exclude list. Default `rtk mix test` runs `2112 tests, 7 excluded` (the seven new pins).

## Task Commits

1. **Task 1: capture pre-phase render baselines** — `b9da35e` (test)
2. **Task 2: add Wave 0 phase39_target pin tests** — `197b94c` (test)

## Files Created/Modified

### Created
- `test/foglet_bbs/tui/app_struct_test.exs` — Two tagged tests pinning post-Phase-39 App struct shape (D-19) and refuting seven legacy fields.
- `test/foglet_bbs/tui/render_snapshots/main_menu.txt` — 80x24 ANSI-stripped baseline.
- `test/foglet_bbs/tui/render_snapshots/board_list.txt` — 80x24 ANSI-stripped baseline.
- `test/foglet_bbs/tui/render_snapshots/thread_list.txt` — 80x24 ANSI-stripped baseline.
- `test/foglet_bbs/tui/render_snapshots/post_reader.txt` — 80x24 ANSI-stripped baseline.
- `test/foglet_bbs/tui/render_snapshots/account.txt` — 80x24 ANSI-stripped baseline.
- `.planning/phases/39-app-shell-simplification/deferred-items.md` — Tracks pre-existing dialyzer warnings, account_test.exs failures, and the inline Credo Rule-3 fixes.

### Modified
- `test/test_helper.exs` — Added `:phase39_target` to ExUnit `exclude:` list.
- `test/foglet_bbs/tui/screen_test.exs` — New `describe "Screen behaviour (Phase 39 R6, D-05)"` with optional-callback pin.
- `test/foglet_bbs/tui/screens/post_reader_test.exs` — New `describe "subscriptions/2 export (Phase 39 R6, D-08)"`; alias-ordering fix (Rule 3).
- `test/foglet_bbs/tui/screens/thread_list_test.exs` — New `describe "subscriptions/2 export (Phase 39 R6, D-08)"`.
- `test/foglet_bbs/tui/screens/board_list_test.exs` — New `describe "subscriptions/2 export (Phase 39 R7, D-22)"`.
- `test/foglet_bbs/tui/app_test.exs` — New tagged test in subscribe/1 describe block pinning MainMenu-only-`["user:u1"]` (D-18).
- `test/foglet_bbs/tui/screens/post_composer_test.exs` — Alias-ordering fix only (Rule 3, Credo).
- `lib/foglet_bbs/tui/screens/new_thread/state.ex` — Alias-ordering fix only (Rule 3, Credo).

## Decisions Made

- **`@tag :phase39_target` exclusion via `test_helper.exs`** rather than `mix.exs` test config — keeps the tag opt-in and removes a single-line at end of phase (Plan 39-08), matching VALIDATION.md's expectation. Confirmed by re-running `rtk mix test` against the included tag — pin tests fail loud as expected.
- **Render baseline captured with the same `sed 's/\x1b\[[0-9;]*m//g'` pipeline Plan 39-08 will use**, so byte-equivalence diff is a like-for-like comparison even though `mix foglet.tui.render` already ANSI-strips. The double-strip is cheap insurance.
- The `==> raxol` mix dep-compile prefix is consistently emitted on stdout by `mix foglet.tui.render`. It's deterministic across runs and identical between the baseline and 39-08's diff command, so it does not invalidate byte-equivalence.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking] Pre-existing Credo readability issues blocked precommit Credo step**

- **Found during:** Task 2 verify (`rtk mix precommit`)
- **Issue:** `mix credo --strict` reported 3 alphabetical-alias-ordering issues on `main` HEAD — confirmed pre-existing via `git stash` of 39-01 changes:
  - `test/foglet_bbs/tui/screens/post_reader_test.exs:4` — `Screens.PostReader` ordered before `{Context, Effect}` group.
  - `test/foglet_bbs/tui/screens/post_composer_test.exs:4` — `Screens.PostComposer` ordered before `Context`.
  - `lib/foglet_bbs/tui/screens/new_thread/state.ex:12` — `Widgets.Input.TextInput` ordered before `Context`.
- **Fix:** Reordered aliases to alphabetical group order in each file. Behavior-preserving; no semantic change.
- **Files modified:** the three files above.
- **Verification:** `rtk mix credo --strict` returns "found no issues"; `rtk mix format --check-formatted` exits 0.
- **Committed in:** `197b94c` (Task 2 commit).

---

**Total deviations:** 1 auto-fixed (1 blocking).
**Impact on plan:** Trivial alphabetical fixes confined to alias blocks; unrelated to Phase 39 design but required for the precommit Credo step to exit 0.

## Issues Encountered

- **`rtk mix precommit` does not exit 0 even after the Credo Rule-3 fix**, due to three pre-existing Dialyzer warnings on `main` HEAD (`app.ex:63 unknown_type ThreadEntry.t/0`, `board_list.ex:161 pattern_match_cov`, `sysop.ex:810 pattern_match`). Verified pre-existing via `git stash` + `rtk mix dialyzer`. These predate Phase 39; the `app.ex` one will be eliminated naturally by Plan 39-07's struct-field deletion. Tracked in `deferred-items.md`. **Plan 39-01 introduces zero new dialyzer warnings.**

  This makes the literal phrasing of the plan's success criterion "rtk mix precommit exits 0" unmeetable on top of `main` without absorbing unrelated cleanup. Flagged here transparently rather than silently choosing to fix unrelated files.

- **Two pre-existing `account_test.exs` failures** (lines 1242, 1271 — doomed-submit error-routing) appear in `rtk mix test`. Verified pre-existing on stashed `main` HEAD. Tracked in `deferred-items.md`; out of scope for 39-01.

## Self-Check: PASSED

Verified before commit:
- `test/foglet_bbs/tui/render_snapshots/main_menu.txt` — FOUND
- `test/foglet_bbs/tui/render_snapshots/board_list.txt` — FOUND
- `test/foglet_bbs/tui/render_snapshots/thread_list.txt` — FOUND
- `test/foglet_bbs/tui/render_snapshots/post_reader.txt` — FOUND
- `test/foglet_bbs/tui/render_snapshots/account.txt` — FOUND
- `test/foglet_bbs/tui/app_struct_test.exs` — FOUND
- Commit `b9da35e` — FOUND in git log
- Commit `197b94c` — FOUND in git log
- `grep -c '@tag :phase39_target'` returns 2 in app_struct_test.exs and ≥1 in screen_test.exs, post_reader_test.exs, thread_list_test.exs, board_list_test.exs, app_test.exs.
- `grep -c 'phase39_target' test/test_helper.exs` returns 1.
- Default `rtk mix test test/foglet_bbs/tui/...` runs the 6 affected test files: 241 tests, 0 failures, 7 excluded.

## Next Phase Readiness

- Pin tests for the post-Phase-39 target shape are live on disk and skipped from the default suite. As Wave 1 lands the matching work, each plan removes the `@tag :phase39_target` from the corresponding test (e.g., 39-02 unblocks the BoardList subscriptions pin, 39-03 the ThreadList pin, etc.). Plan 39-08 removes the global exclusion line from `test_helper.exs`.
- Render baselines exist and are ready for Plan 39-08's byte-equivalence diff. The diff command in 39-08 must be: `rtk mix foglet.tui.render <screen> | sed 's/\x1b\[[0-9;]*m//g' | diff test/foglet_bbs/tui/render_snapshots/<screen>.txt -` (identical pipeline to capture).
- `deferred-items.md` enumerates pre-existing failures Wave 1+ should NOT block on but should fix incidentally if their files come into scope (especially `app.ex:63 ThreadEntry.t/0` which Plan 39-07 deletes).

---
*Phase: 39-app-shell-simplification*
*Completed: 2026-04-29*
