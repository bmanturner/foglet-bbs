---
phase: 39-app-shell-simplification
plan: 03
subsystem: tui

tags: [tui, screens, subscriptions, pubsub, optional-callback, phase39]

# Dependency graph
requires:
  - phase: 39
    plan: 02
    provides: "Foglet.TUI.Screen.subscriptions/2 declared as @optional_callbacks; @impl Foglet.TUI.Screen on a subscriptions/2 implementation no longer warns."
provides:
  - "Foglet.TUI.Screens.PostReader.subscriptions/2 returning [\"thread:<id>\"] from local State.thread_id (or atom/string route_params fallback)."
  - "Foglet.TUI.Screens.ThreadList.subscriptions/2 returning [\"board:<id>\"] from local State.board_id (or atom/string route_params fallback)."
  - "Foglet.TUI.Screens.BoardList.subscriptions/2 returning [\"boards\"] unconditionally (Foglet.PubSub.boards_aggregate())."
  - "post_reader_test.exs / thread_list_test.exs / board_list_test.exs subscriptions/2 reducer pins (4 + 4 + 1, plus 1 + 1 + 1 export pins) running in the default suite — :phase39_target tags removed."
affects: 39-05, 39-07, 39-08

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Screen-declared PubSub topic interest: each stateful screen owns the binary topic strings it cares about, sourced from its local state struct first and route_params (atom-key, then string-key) second; empty fallback returns [] so the App union path stays well-typed."
    - "Test-driven RED → GREEN per task: each screen implementation is preceded by a test commit asserting the expected behaviour (with corresponding describe-block tag removal), then a feat commit lands the implementation."
    - "Stateless screen non-implementation as positive contract evidence: the optional-callback design is proven by Login/Register/Verify/MainMenu/Account/Moderation/Sysop/NewThread/PostComposer continuing to compile and run without subscriptions/2 — verified by an explicit grep gate."

key-files:
  created:
    - .planning/phases/39-app-shell-simplification/39-03-SUMMARY.md
  modified:
    - lib/foglet_bbs/tui/screens/post_reader.ex
    - lib/foglet_bbs/tui/screens/thread_list.ex
    - lib/foglet_bbs/tui/screens/board_list.ex
    - test/foglet_bbs/tui/screens/post_reader_test.exs
    - test/foglet_bbs/tui/screens/thread_list_test.exs
    - test/foglet_bbs/tui/screens/board_list_test.exs

key-decisions:
  - "[Phase 39-03]: PostReader.subscriptions/2 placed between the new render/2 and the legacy render/1 in post_reader.ex — keeps all `@impl Foglet.TUI.Screen` callbacks for the new contract grouped before the transitional region, mirroring the screen.ex callback ordering chosen in 39-02."
  - "[Phase 39-03]: ThreadList.subscriptions/2 placed immediately after the single render/2 clause; no transitional render/1 exists in thread_list.ex so subscriptions/2 sits adjacent to the other new-contract impls."
  - "[Phase 39-03]: BoardList.subscriptions/2 placed AFTER the legacy render/2 fallback (`def render(local_state, %Context{} = context), do: render(normalize_state(local_state), context)`) rather than before it. The fallback is part of the render/2 callback group (it's the same arity); putting subscriptions/2 between the two render/2 clauses would have split a single behaviour callback. After the fallback keeps subscriptions/2 adjacent to the other new-contract impls without splitting render/2."
  - "[Phase 39-03]: BoardList ignores both arguments (D-22) — the boards aggregate topic is unconditional whenever BoardList is the active screen, matching today's App-side semantics at app.ex:442 (`if state.current_screen in [:board_list], do: [PubSub.boards_aggregate() | topics]`). Spec accepts `State.t() | map() | nil` since BoardList's update/3 normalises map-shaped legacy state inputs and we want callers to pass through whatever shape they have without coercion."
  - "[Phase 39-03]: PostReader and ThreadList use the local-state-first / route_params-fallback shape literally specified in the plan's <action> block (atom key first via `Map.get(params, :thread_id) || Map.get(params, \"thread_id\")`, then `is_binary/1` guard returning `[]` for non-binary IDs). This mirrors the deleted `routed_thread_id/1` precedence in app.ex:475-481 and the matching `routed_board_id/1` shape, so SPEC R7 acceptance (topic-set parity for ThreadList/PostReader after the App-side rewrite in 39-05) holds."
  - "[Phase 39-03]: All three implementations use `@impl true` (matching the existing convention in each file: post_reader.ex line 69, thread_list.ex line 26, board_list.ex line 26) rather than the more verbose `@impl Foglet.TUI.Screen` — this keeps each module visually consistent with its existing callbacks."

patterns-established:
  - "Screen subscriptions/2 contract honored by stateful screens, omitted by stateless screens — the @optional_callbacks design from 39-02 now has three concrete implementers and nine concrete non-implementers, proving the optional dispatch is well-typed in both directions."

requirements-completed: []

# Metrics
duration: 4min
completed: 2026-04-29
---

# Phase 39 Plan 03: Implement subscriptions/2 on PostReader, ThreadList, BoardList Summary

**Implemented `subscriptions/2` on the three stateful Screen modules with PubSub topic interest — PostReader returns `["thread:<id>"]` from local State first then route_params (atom/string), ThreadList returns `["board:<id>"]` with the same precedence, BoardList returns `["boards"]` unconditionally — and unblocked the Plan 39-01 `function_exported?/3` pins by removing `@tag :phase39_target` from all three screen test files; landed 9 new reducer pins (4 + 4 + 1) passing in the default suite.**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-04-29T03:52:56Z
- **Completed:** 2026-04-29T03:56:55Z
- **Tasks:** 3 / 3
- **Files modified:** 6 (3 lib, 3 test)
- **Files created:** 1 (this SUMMARY.md)

## Accomplishments

### Implementation Lines (for Plan 39-05 verification)

For Plan 39-05's `function_exported?(module, :subscriptions, 2)` rewrite — the App shell needs to know exactly where each screen's callback lives:

| Screen | File | `@impl true` line | `@spec` line | Function clause(s) |
|--------|------|-------------------|--------------|--------------------|
| `Foglet.TUI.Screens.PostReader` | `lib/foglet_bbs/tui/screens/post_reader.ex` | 225 | 226 | 227–229 (state-first), 231–236 (route_params fallback) |
| `Foglet.TUI.Screens.ThreadList` | `lib/foglet_bbs/tui/screens/thread_list.ex` | 134 | 135 | 136–138 (state-first), 140–145 (route_params fallback) |
| `Foglet.TUI.Screens.BoardList`  | `lib/foglet_bbs/tui/screens/board_list.ex`  | 244 | 245 | 246–248 (unconditional) |

### Test Deltas

| Test file | `@tag :phase39_target` removal | New tests (default suite) |
|-----------|-------------------------------|--------------------------|
| `test/foglet_bbs/tui/screens/post_reader_test.exs` | line 1112 (originally) — removed | 4 new: state, atom-key, string-key, empty |
| `test/foglet_bbs/tui/screens/thread_list_test.exs` | line 434 (originally) — removed | 4 new: state, atom-key, string-key, empty |
| `test/foglet_bbs/tui/screens/board_list_test.exs`  | line 409 (originally) — removed | 1 new: unconditional `["boards"]` |

All previously-tagged `function_exported?/3` pins now run in the default suite; together with the 9 new reducer pins they total **12 new green tests** added by this plan (3 export + 9 reducer).

### Test Suite Results

- `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs` — **65 tests, 0 failures**
- `rtk mix test test/foglet_bbs/tui/screens/thread_list_test.exs` — **27 tests, 0 failures**
- `rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs` — **23 tests, 0 failures**
- Full `rtk mix test` — **2125 tests, 2 failures, 1 property** — both failures are the pre-existing `account_test.exs:1242, 1271` items tracked in `deferred-items.md`. **Zero new test failures introduced by this plan.**

### Build / Lint Gates

- `rtk mix compile --warnings-as-errors` — exit 0 (only raxol dependency-side warnings; foglet_bbs compiles cleanly).
- `rtk mix format` — ok across all 6 modified files.
- `rtk mix dialyzer` — exactly 3 pre-existing warnings (`app.ex:63`, `board_list.ex:161`, `sysop.ex:810`), all tracked in `deferred-items.md`. **Zero new dialyzer warnings introduced by this plan.**
- `rtk mix precommit` — halts at dialyzer with the same 3 pre-existing warnings (per `deferred-items.md`'s "rtk mix precommit does not exit 0 on main HEAD prior to Phase 39 work" baseline). **Zero new precommit failures.**

### Stateless-Screen Non-Implementation Evidence

Per SPEC R6 / D-08, only stateful screens with PubSub interest implement `subscriptions/2`. Verified by the plan's <success_criteria> grep gate:

```
$ for s in login register verify main_menu account moderation sysop new_thread post_composer; do
    rtk grep -q 'def subscriptions' lib/foglet_bbs/tui/screens/$s.ex && echo FAIL: $s || echo OK: $s
  done
OK: login
OK: register
OK: verify
OK: main_menu
OK: account
OK: moderation
OK: sysop
OK: new_thread
OK: post_composer
```

All nine stateless screens compile and run without `subscriptions/2` — the optional-callback contract from Plan 39-02 is now empirically grounded.

### Acceptance-Criteria Greps

| Check | Expected | Got |
|-------|----------|-----|
| `grep -c 'def subscriptions' post_reader.ex` | ≥ 2 | 2 |
| `grep -c 'thread_topic' post_reader.ex` | ≥ 2 | 2 |
| `grep -c 'def subscriptions' thread_list.ex` | ≥ 2 | 2 |
| `grep -c 'board_topic' thread_list.ex` | ≥ 2 | 2 |
| `grep -c 'def subscriptions' board_list.ex` | ≥ 1 | 1 |
| `grep -c 'boards_aggregate' board_list.ex` | ≥ 1 | 1 |

## Task Commits

1. **Task 1 RED: add failing PostReader.subscriptions/2 reducer pins** — `c517f72` (test)
2. **Task 1 GREEN: implement PostReader.subscriptions/2** — `27da7e3` (feat)
3. **Task 2 RED: add failing ThreadList.subscriptions/2 reducer pins** — `1419e6f` (test)
4. **Task 2 GREEN: implement ThreadList.subscriptions/2** — `5d5489e` (feat)
5. **Task 3 RED: add failing BoardList.subscriptions/2 reducer pin** — `6c5bbaf` (test)
6. **Task 3 GREEN: implement BoardList.subscriptions/2** — `b91789e` (feat)

## Files Created/Modified

### Created
- `.planning/phases/39-app-shell-simplification/39-03-SUMMARY.md` — this file.

### Modified
- `lib/foglet_bbs/tui/screens/post_reader.ex` — added `@impl true def subscriptions/2` with two clauses (lines 225–236) between the new-contract `render/2` (lines 207–223) and the legacy `render/1` (line 238 onward).
- `lib/foglet_bbs/tui/screens/thread_list.ex` — added `@impl true def subscriptions/2` with two clauses (lines 134–145) immediately after `render/2` (lines 119–132).
- `lib/foglet_bbs/tui/screens/board_list.ex` — added `@impl true def subscriptions/2` (lines 244–248) after the `render/2` legacy fallback at line 242, ignoring both arguments and returning `[Foglet.PubSub.boards_aggregate()]` unconditionally.
- `test/foglet_bbs/tui/screens/post_reader_test.exs` — removed `@tag :phase39_target` from the export pin; added 4 new reducer pins inside the same describe block.
- `test/foglet_bbs/tui/screens/thread_list_test.exs` — removed `@tag :phase39_target` from the export pin; added 4 new reducer pins inside the same describe block.
- `test/foglet_bbs/tui/screens/board_list_test.exs` — removed `@tag :phase39_target` from the export pin; added 1 new reducer pin (unconditional `["boards"]`).

## Decisions Made

- **`@impl true` over `@impl Foglet.TUI.Screen`** in all three implementations — the file-local convention in each module (verified by `grep '^  @impl' lib/foglet_bbs/tui/screens/{post_reader,thread_list,board_list}.ex`) is `@impl true`, so matching it preserves visual consistency. Either form satisfies the behaviour-binding contract.
- **PostReader: insert between new render/2 and legacy render/1.** The file has a documented "transitional" boundary in its module-doc; subscriptions/2 is a new-contract addition, so it sits with `init/1`, `update/3`, `render/2` rather than next to `render/1`/`handle_key/2`.
- **BoardList: insert after the render/2 legacy fallback.** BoardList has two render/2 clauses (struct-typed and map-typed); subscriptions/2 sits after the second one to avoid splitting the render/2 group. The two arguments are ignored on purpose — the boards aggregate topic is unconditional per D-22, mirroring the deleted `app.ex:442` behaviour.
- **Spec annotations:** PostReader and ThreadList both use `@spec subscriptions(State.t() | nil, Context.t()) :: [String.t()]` (Dialyzer-friendly, captures the local-state-or-nil precedence); BoardList uses `State.t() | map() | nil` because its `update/3` accepts map-shaped legacy state via `normalize_state/1` and we don't want subscriptions/2 to coerce.
- **Tests follow the plan's RED → GREEN per task literally.** Each task pair is two commits: a `test(...)` commit untagging the existing pin and adding the failing reducer assertions, then a `feat(...)` commit landing the implementation. Six commits total, mirroring the `tdd="true"` flag on each task.

## Deviations from Plan

**1. [Rule 3 - Blocking] Mid-edit recovery in `lib/foglet_bbs/tui/screens/thread_list.ex`** — During Task 2 GREEN, my Edit call's `new_string` accidentally appended a stray `defp _placeholder_to_close_render do …` placeholder block immediately after the new `subscriptions/2` clauses. The post-tool formatter hook ran and reformatted the file, leaving the unwanted `defp` in place. Re-read the file, confirmed the placeholder was real (lines 147–149), removed it via a follow-up Edit, ran `rtk mix format` and `rtk mix compile --warnings-as-errors` (both clean), then re-ran the file's tests (27/0). No commit included the placeholder — it was caught and removed before staging. Tracked as Rule 3 because the placeholder was a self-inflicted blocker on Task 2 verification, fixed inline before the GREEN commit landed.

No other deviations.

## Issues Encountered

- **`rtk mix precommit` does not exit 0**, but only for the three pre-existing dialyzer warnings tracked in `.planning/phases/39-app-shell-simplification/deferred-items.md`. Verified the count is exactly 3 by running `rtk mix dialyzer` and listing the warnings. **This plan introduces zero new precommit failures vs. the deferred-items.md baseline.** Per the orchestrator's note in 39-01's deferred-items.md ("These are NOT introduced by Phase 39 work. Do NOT attempt to fix them"), no remediation attempted.
- **`rtk mix test` reports 2 failures** at `test/foglet_bbs/tui/screens/account_test.exs:1242, 1271` — both pre-existing per `deferred-items.md`. **Zero new test failures introduced by this plan.**

## Self-Check: PASSED

Verified before commit:

**Files created/modified all exist:**
- `lib/foglet_bbs/tui/screens/post_reader.ex` — FOUND, contains `@impl true def subscriptions(%State{thread_id: thread_id}, _context) when is_binary(thread_id)` at line 227 and `def subscriptions(_local_state, %Context{route_params: params})` at line 231.
- `lib/foglet_bbs/tui/screens/thread_list.ex` — FOUND, contains the corresponding board_id clauses at lines 136 and 140.
- `lib/foglet_bbs/tui/screens/board_list.ex` — FOUND, contains the unconditional `def subscriptions(_local_state, _context)` at line 246.
- All three test files — FOUND, each with `@tag :phase39_target` removed from the export pin and 4 + 4 + 1 reducer pins added (verified by `rtk grep 'phase39_target' test/foglet_bbs/tui/screens/{post_reader,thread_list,board_list}_test.exs` returning 0 matches inside the subscriptions describe blocks).

**Commits exist:**
- `c517f72`, `27da7e3`, `1419e6f`, `5d5489e`, `6c5bbaf`, `b91789e` all present in `rtk git log --oneline -10`.

**Acceptance grep checks:**
- All 6 grep counts match expectations (see "Acceptance-Criteria Greps" table above).

**Stateless-screen non-implementation:**
- All 9 stateless screens (login, register, verify, main_menu, account, moderation, sysop, new_thread, post_composer) confirmed by the success_criteria for-loop to NOT contain `def subscriptions` (verified above).

**Test counts:**
- post_reader_test.exs: 65/65, thread_list_test.exs: 27/27, board_list_test.exs: 23/23.
- Full suite: 2125 tests, 2 pre-existing failures (deferred-items.md baseline match).

## Next Plan Readiness

- **Plan 39-04 (route-entry update clauses)** is the immediate next plan in Wave 1 — independent of subscriptions/2, but ThreadList and PostReader will pick up `update(:on_route_enter, …)` clauses there and may want to know that their state structs already carry `board_id` / `thread_id` populated by `from_context/1` at init.
- **Plan 39-05 (App build_pubsub_topics rewrite)** can now confidently rely on `function_exported?(Foglet.TUI.Screens.PostReader, :subscriptions, 2)`, `…ThreadList…`, and `…BoardList…` all returning `true`, and the topic-equivalence regression test pinned by SPEC R7 will pass for the three migrated screens. App's deletion of `routed_thread_topic/2`, `thread_list_board_topic/1`, and the boards-aggregate gate at `app.ex:442` is now safe — the screen-side replacements are in place.
- **Plan 39-08 (verification/milestone close)** SPEC §Acceptance Criteria items 6 and 7 (`function_exported?` and topic-set parity) are partially satisfied by this plan; the union path inside App still needs to be wired in 39-05 before they pass end-to-end.

---
*Phase: 39-app-shell-simplification*
*Completed: 2026-04-29*
