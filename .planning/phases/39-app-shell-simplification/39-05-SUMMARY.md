---
phase: 39-app-shell-simplification
plan: 05
subsystem: tui

tags: [tui, app, runtime-shell, pubsub, route-entry, broadcast, phase39]

# Dependency graph
requires:
  - phase: 39
    plan: 03
    provides: "subscriptions/2 implementations on PostReader, ThreadList, BoardList — App can now defer screen-specific topic interest to module.subscriptions(state, ctx)."
  - phase: 39
    plan: 04
    provides: ":on_route_enter clauses on MainMenu, Moderation, Sysop, ThreadList, PostReader — App can now collapse maybe_dispatch_route_entry/3 to a single generic dispatch."
provides:
  - "App.build_pubsub_topics/1 derives screen-specific topics generically via screen_declared_topics/1, which calls module.subscriptions(state, ctx) under a Code.ensure_loaded?/1 + function_exported?(module, :subscriptions, 2) paired guard."
  - "App.maybe_dispatch_route_entry/3 collapsed to one screen-agnostic clause that always dispatches :on_route_enter to the active screen via route_screen_update/3."
  - "App.maybe_init_initial_screen_state/1 collapsed to one generic clause; the :main_menu special case is gone."
  - "do_update({:set_user, user}, state) and do_update({:promote_session, user}, state) use apply_effect(state, Effect.navigate(:main_menu, %{})) instead of hardcoded route_screen_update(state, :main_menu, :load_oneliners)."
  - "do_update({:board_activity, …}, state) and do_update({:thread_activity, …}, state) route generically via route_screen_update(state, screen_key(current_route(state)), msg) — no current_screen == gates remain."
  - "Six App-side topic-decoder helpers deleted (routed_thread_topic/1, routed_thread_id/1, post_reader_state_thread_id/1, post_composer_state_thread_id/1, thread_list_board_topic/1, thread_list_state_board_id/1)."
  - "maybe_seed_legacy_route_context/3 (a no-op since Phase 38) and route_param/2 (only used by the old :post_reader entry-dispatch clause) deleted."
  - "Three unused aliases removed (Foglet.TUI.Screens.PostComposer, .PostReader, .ThreadList)."
affects: 39-06, 39-07, 39-08

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Optional-callback paired guard: Code.ensure_loaded?(module) and function_exported?(module, :subscriptions, 2) — the same idiom App already uses for :update/3 (route_screen_update/3) and :render/2 (render_screen/1). subscriptions/2 joins the family."
    - "Screen-agnostic broadcast routing: PubSub messages reach the active screen via route_screen_update/3; screens that care handle them in update/3, screens that don't hit their update(_message, …) catch-all and no-op. The active screen is determined by screen_key(current_route(state)) — the same lookup used by all other screen dispatch sites."
    - "Effect.navigate as the single first-load entry point: set_user / promote_session no longer hardcode :load_oneliners; the navigate effect's existing interpretation chain (init_route_screen_state → maybe_dispatch_route_entry → :on_route_enter) reaches MainMenu, which delegates to its existing :load_oneliners clause (Plan 39-04 contract)."

key-files:
  created:
    - .planning/phases/39-app-shell-simplification/39-05-SUMMARY.md
  modified:
    - lib/foglet_bbs/tui/app.ex
    - test/foglet_bbs/tui/app_runtime_contract_test.exs

key-decisions:
  - "[Phase 39-05]: BoardList already had a {:board_activity, …} update/3 clause at board_list.ex:210 (added in Phase 38, before Phase 39 began). The plan's Task 3 Step 4 (`Add BoardList.update({:board_activity, …}, …) clause`) was therefore a no-op; verified by grep before the App-side change. PostReader already handles {:thread_activity, …} at post_reader.ex:124-138. No screen-side changes were needed in this plan."
  - "[Phase 39-05]: Skipped TDD RED commits per task. The plan's <behavior> blocks for all three tasks are already covered by existing tests in test/foglet_bbs/tui/app_test.exs (subscribe/1 describe-block at lines 1483-1622, set_user/promote_session tests at lines 241-258 and 746-763, board_activity/thread_activity tests at lines 1753-1807). These existing tests serve as the regression contract — they already RED-cover the intended behaviour. Each task is GREEN-only (one commit per task) and verified by the existing tests staying green. This matches the pragmatic interpretation 39-04 used (TDD-as-pin-tests) and avoids fabricating duplicate test cases solely to satisfy the tdd flag."
  - "[Phase 39-05]: SampleScreen test fixture in app_runtime_contract_test.exs was missing a catch-all update/3 clause. The new generic :on_route_enter dispatch (Task 2) routes to every active screen, including this test fixture. Added a `def update(_message, %State{} = state, %Context{}), do: {state, []}` clause to align the fixture with the Foglet.TUI.Screen contract (where catch-all is the documented mechanism for ignoring unknown messages). Tracked as Rule 3 deviation."
  - "[Phase 39-05]: Did NOT delete the seven legacy struct fields (current_board, current_thread, current_thread_list, posts, read_position, composer_draft, board_list) — that's Plan 39-07's job per the SPEC. The two D-19 pin tests in app_struct_test.exs (tagged :phase39_target) remain RED at this commit; they pass when 39-07 lands. Confirmed by running `mix test test/foglet_bbs/tui/app_struct_test.exs --include phase39_target` — the failures are exactly the two D-19 pins."
  - "[Phase 39-05]: Did NOT remove the @tag :phase39_target from the D-18 pin (app_test.exs:1609-1622) — the SPEC says wave 0 cleanup is Plan 39-07's responsibility. The pin test passes today (verified by --include phase39_target run = 136/136), so the tag is now truthful but kept for orchestration consistency."

patterns-established:
  - "App is now a runtime shell w.r.t. PubSub: every screen-specific topic comes from a screen module's subscriptions/2 callback. App owns user-level (user:<id>) topics only. The optional-callback contract is now wired end-to-end: 39-02 declared it, 39-03 implemented it on three stateful screens, 39-05 wired App's subscribe path to it."
  - "App is now a runtime shell w.r.t. route-entry: maybe_dispatch_route_entry/3 has one clause that always dispatches :on_route_enter — first-load semantics live in each screen's update(:on_route_enter, …) clause. The optional-callback discovery pattern is the same one App already uses for update/3 (function_exported?(module, :update, 3) at route_screen_update/3) — no new mechanism."
  - "App is now a runtime shell w.r.t. broadcast routing: {:board_activity, …} and {:thread_activity, …} reach the active screen via route_screen_update/3. The screens that care (BoardList, PostReader) handle them in update/3; others hit their catch-all and no-op."

requirements-completed: [APP-01, APP-02, APP-03, STATE-04]

# Metrics
duration: 12min
completed: 2026-04-29
---

# Phase 39 Plan 05: App-side cleanup (build_pubsub_topics, maybe_dispatch_route_entry, set_user/promote_session) Summary

**Replaced App's screen-specific machinery with the generic mechanisms the screen-side groundwork (Plans 39-03 subscriptions/2 and 39-04 :on_route_enter) made possible. App's PubSub topic derivation now defers entirely to module.subscriptions(state, ctx) via the `Code.ensure_loaded?/1 + function_exported?(:subscriptions, 2)` paired guard. App's route-entry dispatch is now one screen-agnostic clause that always sends :on_route_enter to the active screen. App's broadcast handlers (:board_activity, :thread_activity) route generically through route_screen_update/3 — no current_screen == gates remain. set_user/promote_session use Effect.navigate(:main_menu, %{}) instead of hardcoded :load_oneliners. Six topic-decoder helpers, the no-op maybe_seed_legacy_route_context/3, the route_param/2 helper, and three unused aliases (PostComposer, PostReader, ThreadList) deleted. App.ex shrank from 1102 lines to 975 (delta: -127, ~11.5% reduction). Behaviour parity verified: full TUI test suite passes with zero new failures; the two pre-existing account_test.exs failures and three pre-existing dialyzer warnings (per deferred-items.md) remain unchanged.**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-04-29T04:15:09Z
- **Completed:** 2026-04-29T04:27:30Z
- **Tasks:** 3 / 3 (GREEN-only per plan rationale below)
- **Files modified:** 2 (1 lib, 1 test)
- **Files created:** 1 (this SUMMARY.md)

## Accomplishments

### `lib/foglet_bbs/tui/app.ex` — Line-Count Delta

| Phase | Lines | Notes |
|-------|-------|-------|
| Pre-39-05 (HEAD@199aca7) | 1102 | Per SPEC R10 baseline |
| Post-39-05 (HEAD@7b612e8) | **975** | -127 lines (~11.5% reduction) |

This is the deletion-driven shrinkage SPEC R10 calls for; SPEC explicitly says
the line-count delta is reported for context and not gating. The bigger
qualitative win is the disappearance of seven distinct screen-specific
constructs (six topic decoders + one no-op + the `:main_menu` init shim + the
five per-screen route-entry clauses + the four-clause broadcast block).

### Helpers Deleted

Six topic-decoder helpers (per SPEC R5, R7):

| Helper | Pre-existing site | Now sourced from |
|--------|-------------------|------------------|
| `routed_thread_topic/1` | `app.ex:463-473` | (covered by `PostReader.subscriptions/2`) |
| `routed_thread_id/1` | `app.ex:475-481` | (covered by `PostReader.subscriptions/2`) |
| `post_reader_state_thread_id/1` | `app.ex:483-488` | (covered by `PostReader.subscriptions/2`) |
| `post_composer_state_thread_id/1` | `app.ex:490-501` | (no live consumer — the only PubSub interest at PostComposer was thread:<id>, now redundant with PostReader's subscription) |
| `thread_list_board_topic/1` | `app.ex:503-512` | (covered by `ThreadList.subscriptions/2`) |
| `thread_list_state_board_id/1` | `app.ex:521-526` | (covered by `ThreadList.subscriptions/2`) |

Other deletions:

| Helper | Pre-existing site | Reason |
|--------|-------------------|--------|
| `maybe_seed_legacy_route_context/3` | `app.ex:808` | No-op since Phase 38; sole call site at `app.ex:157` (apply_effect/:navigate) removed in tandem |
| `route_param/2` | `app.ex:847-849` | Only consumer was the deleted `:post_reader` entry-dispatch clause |
| Five `maybe_dispatch_route_entry/3` clauses | `app.ex:810-845` | Replaced by one generic clause |
| `:main_menu` clause of `maybe_init_initial_screen_state/1` | `app.ex:884-893` | Generic clause covers it via `init_route_screen_state/3`'s `function_exported?(module, :init, 1)` branch |
| `Foglet.TUI.Screens.PostComposer` alias | `app.ex:26` | No longer referenced |
| `Foglet.TUI.Screens.PostReader` alias | `app.ex:27` | No longer referenced |
| `Foglet.TUI.Screens.ThreadList` alias | `app.ex:28` | No longer referenced |

### New / Rewritten Functions

| Function | New shape | Reason |
|----------|-----------|--------|
| `build_pubsub_topics/1` | `user_topics ++ screen_declared_topics(state)` | Was 30+ lines of screen-specific pattern matches; now delegates to the screen via subscriptions/2 |
| `screen_declared_topics/1` (NEW, app.ex:449-457) | `function_exported?(module, :subscriptions, 2)` paired guard → `module.subscriptions(state, ctx)` or `[]` | Mirrors the optional-callback dispatch idiom App already uses for `:update/3` and `:render/2` |
| `maybe_dispatch_route_entry/3` | one screen-agnostic clause: `route_screen_update(state, screen_key(screen), :on_route_enter)` | Was five per-screen clauses; first-load semantics now live in each screen's `:on_route_enter` clause (Plan 39-04) |
| `maybe_init_initial_screen_state/1` | one generic clause | `init_route_screen_state/3` already covers MainMenu via `function_exported?(module, :init, 1)`; the `oneliner_status: :idle` shim is unnecessary because MainMenu's `:on_route_enter` sets `:loading` before the load task fires |
| `do_update({:set_user, user}, state)` | `apply_effect(%{state \| current_user: user}, Effect.navigate(:main_menu, %{}))` | Effect.navigate's interpretation chain reaches MainMenu's `:on_route_enter`, which delegates to `:load_oneliners` |
| `do_update({:promote_session, user}, state)` | same as set_user, plus the preserved `Foglet.Sessions.Supervisor.promote_guest_session/2` side effect | One-session-per-user (SSH-05 / D-25) is unchanged |
| `do_update({:board_activity, _, _} = msg, state)` | `route_screen_update(state, screen_key(current_route(state)), msg)` | BoardList's existing `update({:board_activity, …}, …)` clause at board_list.ex:210 handles it; other screens hit catch-all |
| `do_update({:thread_activity, _, _} = msg, state)` | same generic shape | PostReader's existing `update({:thread_activity, …}, …)` clauses at post_reader.ex:124-138 handle it |

### Test Suite Results

- `rtk mix test test/foglet_bbs/tui/app_test.exs` — **135/135 (1 excluded — the D-18 pin)**
- `rtk mix test test/foglet_bbs/tui/app_test.exs --include phase39_target` — **136/136** (D-18 pin passes, confirming `App.subscribe/1` for an authenticated MainMenu state produces topics `["user:u1"]` exactly per the SPEC R7 acceptance contract)
- `rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs test/foglet_bbs/tui/screens/post_reader_test.exs` — **94/94**
- `rtk mix test test/foglet_bbs/tui/screens/` — **734 tests, 2 failures** (account_test.exs:1242, 1271 — pre-existing per deferred-items.md)
- `rtk mix test test/foglet_bbs/tui/app_runtime_contract_test.exs` — **8/8** (after the SampleScreen test-fixture catch-all addition)
- `rtk mix test test/foglet_bbs/tui/` — **1590 tests, 2 failures, 3 excluded** — both failures match the deferred-items.md baseline. **Zero new test failures.**
- `rtk mix test test/foglet_bbs/tui/ --include phase39_target` — **1593 tests, 4 failures** = 2 pre-existing + 2 D-19 pins in app_struct_test.exs (struct shape — RED until Plan 39-07 lands the legacy field deletion).

### Build / Lint Gates

- `rtk mix compile --warnings-as-errors` — **exit 0** (only raxol dependency-side warnings; foglet_bbs compiles cleanly).
- `rtk mix format --check-formatted` — ok across all modified files.
- `rtk mix credo --strict` — `3661 mods/funs, found no issues.`
- `rtk mix dialyzer` — exactly 3 warnings, all pre-existing per deferred-items.md:
  - `lib/foglet_bbs/tui/app.ex:60:38:unknown_type` (formerly `:63:38` — line shifted by 3 because the alias deletes happened above this line; the `ThreadEntry.t/0` reference is in the `current_thread:` field of `@type t`, which Plan 39-07 will delete entirely)
  - `lib/foglet_bbs/tui/screens/board_list.ex:161:9:pattern_match_cov`
  - `lib/foglet_bbs/tui/screens/sysop.ex:823:8:pattern_match`
- `rtk mix precommit` — halts at dialyzer with the same 3 pre-existing warnings (per `deferred-items.md`'s "rtk mix precommit does not exit 0 on main HEAD prior to Phase 39 work" baseline). **Zero new precommit failures.**

### Acceptance-Criteria Greps

| Plan-level success criterion | Check | Result |
|------------------------------|-------|--------|
| App contains no `current_screen` pattern match against any production atom for entry-dispatch, broadcast, initial-state, or topic derivation | `! rtk grep -nE 'current_screen ==\|current_screen in \[' lib/foglet_bbs/tui/app.ex` | PASS (zero matches) |
| Six topic-decoder helpers gone | `! rtk grep -nE 'routed_thread_topic\|routed_thread_id\|post_reader_state_thread_id\|post_composer_state_thread_id\|thread_list_board_topic\|thread_list_state_board_id' lib/foglet_bbs/tui/app.ex` | PASS (zero matches) |
| `maybe_seed_legacy_route_context/3` deleted | `! rtk grep -n 'maybe_seed_legacy_route_context' lib/foglet_bbs/tui/app.ex` | PASS (zero matches) |
| `screen_declared_topics/1` is the only screen-specific topic source | `rtk grep -c 'screen_declared_topics' lib/foglet_bbs/tui/app.ex` | PASS (2 matches: 1 def + 1 call) |
| `function_exported?(:subscriptions, 2)` guard exists | `rtk grep -c 'function_exported?(.*:subscriptions, 2)' lib/foglet_bbs/tui/app.ex` | PASS (1 match in `screen_declared_topics/1`) |
| One `maybe_dispatch_route_entry/3` clause | `rtk grep -c 'defp maybe_dispatch_route_entry' lib/foglet_bbs/tui/app.ex` | PASS (1) |
| The single clause uses a variable for screen, not an atom | `! rtk grep -E 'defp maybe_dispatch_route_entry\(.*, :(login\|register\|verify\|main_menu\|board_list\|thread_list\|post_reader\|post_composer\|new_thread\|account\|moderation\|sysop)' lib/foglet_bbs/tui/app.ex` | PASS |
| One `maybe_init_initial_screen_state/1` clause | `rtk grep -c 'defp maybe_init_initial_screen_state' lib/foglet_bbs/tui/app.ex` | PASS (1) |
| `current_screen: :main_menu` Map updates gone (set_user/promote_session use Effect.navigate) | `rtk grep -c 'current_screen: :main_menu' lib/foglet_bbs/tui/app.ex` | PASS (0) |
| `Effect.navigate(:main_menu, …)` count >= 2 | `rtk grep -cE 'Effect\.navigate\(:main_menu' lib/foglet_bbs/tui/app.ex` | PASS (2: set_user + promote_session) |
| `route_screen_update(state, :main_menu, :load_oneliners)` removed | `rtk grep -c 'route_screen_update(state, :main_menu, :load_oneliners)' lib/foglet_bbs/tui/app.ex` | PASS (0) |
| BoardList handles `:board_activity` | `rtk grep -c ':board_activity' lib/foglet_bbs/tui/screens/board_list.ex` | PASS (1 — pre-existing clause at line 210) |
| PostReader handles `:thread_activity` | `rtk grep -c ':thread_activity' lib/foglet_bbs/tui/screens/post_reader.ex` | PASS (2 — both pre-existing clauses) |
| `Foglet.Sessions.Supervisor.promote_guest_session/2` side effect preserved | `rtk grep -c 'Foglet.Sessions.Supervisor.promote_guest_session' lib/foglet_bbs/tui/app.ex` | PASS (1) |

### Two D-17 Pin Tests (`test/foglet_bbs/tui/app_test.exs:1531-1551, 1587-1607`)

Per the plan's <output> directive, confirming these still compile and pass at this commit:

- `app_test.exs:1531`: "thread_list screen ignores current_board when route and local state omit board_id" — references `state.current_board` field — **PASSES** (the field still exists; Plan 39-07 will delete both the field and this test).
- `app_test.exs:1587`: "post_reader screen ignores current_thread without route or local thread id" — references `state.current_thread` field — **PASSES** (same disposition).

Verified by inclusion in the 135/135 default-suite run (subscribe describe-block at lines 1483-1622).

## Task Commits

1. **Task 1: rewrite build_pubsub_topics/1 via Screen.subscriptions/2** — `310865e` (refactor)
2. **Task 2: collapse maybe_dispatch_route_entry/3 to one generic clause** — `287e2d6` (refactor)
3. **Task 3: use Effect.navigate; route :board_activity/:thread_activity generically** — `7b612e8` (refactor)

## Files Created/Modified

### Created
- `.planning/phases/39-app-shell-simplification/39-05-SUMMARY.md` — this file.

### Modified
- `lib/foglet_bbs/tui/app.ex` — major cleanup as detailed above. Removed 127 lines net. Three commits.
- `test/foglet_bbs/tui/app_runtime_contract_test.exs` — added a catch-all `update(_message, …)` clause to the SampleScreen test fixture so the new generic `:on_route_enter` dispatch (Task 2) doesn't crash with `FunctionClauseError`. The catch-all aligns the fixture with the documented Foglet.TUI.Screen contract (catch-all is how screens ignore unknown messages).

## Decisions Made

- **GREEN-only TDD per task** (no separate RED commits). The plan's `<behavior>` blocks for all three tasks describe the CURRENT contract that existing tests in `test/foglet_bbs/tui/app_test.exs` already lock in (subscribe/1 describe-block at lines 1483-1622, set_user/promote_session tests at 241-258 and 746-763, board_activity/thread_activity tests at 1753-1807). These existing tests are the regression contract; adding a separate RED commit per task would have produced fabricated duplicate test cases solely to satisfy `tdd="true"`. Each Task is a single GREEN commit; verification is "existing tests stay green." This is the same pragmatic interpretation 39-04 used for the `:on_route_enter` plan (TDD-as-pin-tests, with the existing test suite as the contract).
- **No screen-side changes in this plan.** Task 3 Step 4 instructed adding a `BoardList.update({:board_activity, …}, …)` clause, but inspection showed BoardList already had one at `board_list.ex:210` (added in Phase 38, before Phase 39 began). PostReader's `:thread_activity` clauses at `post_reader.ex:124-138` were also pre-existing. The plan's prerequisites were already satisfied by Plans 39-03 and 39-04; this plan is App-side only.
- **Did not delete the seven legacy struct fields** (`current_board`, `current_thread`, `current_thread_list`, `posts`, `read_position`, `composer_draft`, `board_list`). Per SPEC R1 / D-19 and the plan's explicit note ("This plan does NOT delete the seven legacy struct fields — Plan 39-07 owns that"), these stay. The two D-19 pin tests in `app_struct_test.exs` (tagged `:phase39_target`) remain RED at this commit and will pass when 39-07 lands.
- **Did not modify `breadcrumb_bar.ex`.** Per SPEC R3 / the plan's explicit note ("This plan does NOT modify breadcrumb_bar.ex — Plan 39-06 owns that"). The breadcrumb chrome reader migration is Plan 39-06's scope.
- **Did not remove the `@tag :phase39_target` from the D-18 pin** (`app_test.exs:1609-1622`). The plan explicitly says "this plan does NOT remove that tag (Plan 39-07 owns the wave 0 cleanup)." The pin test passes today (verified by `--include phase39_target` runs producing 136/136 in `app_test.exs`), so the tag is now truthful but kept for orchestration consistency.
- **Used `Code.ensure_loaded?/1` AND `function_exported?/3` paired in `screen_declared_topics/1`**, matching the existing idiom used at `route_screen_update/3` and `render_screen/1`. Per PATTERNS.md "Anti-patterns" — using `Code.ensure_loaded?/1` alone is forbidden (the existing dispatch sites pair both). This consistency choice means a future grep `Code.ensure_loaded?\(.*\) and function_exported?` returns three callsites, which is a clean code-quality signal.
- **Used `screen_key(current_route(state))` for active-screen lookups in the rewritten broadcast clauses** (rather than raw `state.current_screen`). `current_route/1` returns either an atom or `{atom, params}` tuple depending on whether route_params is non-empty; `screen_key/1` collapses both into the atom needed for `route_screen_update/3`. Same lookup pattern is used at the existing `{:key, …}` and `:render` dispatch sites in App, so the broadcast clauses now match the canonical form.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking] SampleScreen test fixture in `app_runtime_contract_test.exs` lacked a catch-all `update/3` clause**

- **Found during:** Task 3 verification (`rtk mix test test/foglet_bbs/tui/`).
- **Issue:** After Task 2 collapsed `maybe_dispatch_route_entry/3` to one generic clause that always sends `:on_route_enter`, every active screen (including the test-fixture `SampleScreen` in `app_runtime_contract_test.exs`) receives `:on_route_enter` on entry. SampleScreen had only three explicit clauses (`:task_result`, `:key`, no catch-all), so `:on_route_enter` triggered `FunctionClauseError` and crashed five tests:
  - `task effect routing task failure wrapper routes an error through SampleScreen.update/3`
  - `task effect routing task success routes through SampleScreen.update/3`
  - `generic non-task effect interpretation navigate initializes only the target state and carries route params`
  - `generic non-task effect interpretation legacy navigation clears route params from effect navigation`
  - `generic non-task effect interpretation new-contract screens handle keys and render without legacy callbacks`
- **Root cause:** Test-fixture screen module didn't follow the documented Foglet.TUI.Screen contract pattern (catch-all `update(_message, state, _ctx)` for unknown messages). The plan's PATTERNS.md "Generic route-entry" anti-patterns section explicitly says "Screens that don't implement `:on_route_enter` hit their `update(_message, state, _ctx)` catch-all and become no-ops" — SampleScreen wasn't following that rule.
- **Fix:** Added a `def update(_message, %State{} = state, %Context{}), do: {state, []}` clause to SampleScreen, with a comment citing Phase 39 D-04. The catch-all aligns the fixture with the contract that production screens already follow (verified at `lib/foglet_bbs/tui/screens/board_list.ex:220`, `main_menu.ex:394`, `moderation.ex:142`, `sysop.ex:162`, `post_reader.ex` final clause, etc.).
- **Files modified:** `test/foglet_bbs/tui/app_runtime_contract_test.exs` (one Edit, +5 lines including comment).
- **Verification:** All 8 `app_runtime_contract_test.exs` tests pass; full TUI suite returns to baseline (1590 tests, 2 pre-existing failures, zero new failures).
- **Committed in:** `7b612e8` (Task 3 commit — bundled with the App-side change because it's the same logical unit: making the broadcast/route-entry generic.)
- **Tracked as Rule 3** because the missing catch-all blocked verification of Task 3's correctness; the fix is mechanical (one clause), confined to the test fixture, and doesn't change any production behaviour.

**Total deviations:** 1 auto-fixed (1 Rule 3 — blocking test infrastructure).

**Impact on plan:** Plan 39-08's byte-equivalence diff is unaffected — SampleScreen is test-only and its rendering is a `{:sample_render, ...}` tuple, not a user-visible screen. The fixture fix documents an implicit contract that future test screens should also follow.

## Issues Encountered

- **`rtk mix precommit` does not exit 0**, but only for the same three pre-existing dialyzer warnings tracked in `.planning/phases/39-app-shell-simplification/deferred-items.md`. One warning's line number shifted (`app.ex:63` → `app.ex:60`) because this plan deleted three alias lines above it; the warning text (`unknown_type: ThreadEntry.t/0`) is identical to the baseline, and Plan 39-07 will eliminate this warning entirely by deleting the `current_thread:` field that references `ThreadEntry.t/0`. **This plan introduces zero new precommit failures vs. the deferred-items.md baseline.**
- **`rtk mix test test/foglet_bbs/tui/` reports 2 failures** at `test/foglet_bbs/tui/screens/account_test.exs:1242, 1271` — both pre-existing per `deferred-items.md`. **Zero new test failures introduced by this plan.**

## Self-Check: PASSED

Verified before final commit:

**Files modified all exist:**
- `lib/foglet_bbs/tui/app.ex` — FOUND. Line count 975 (was 1102 pre-39-05).
- `test/foglet_bbs/tui/app_runtime_contract_test.exs` — FOUND. Catch-all clause at the SampleScreen module.

**Commits exist:**
- `310865e` (Task 1) — FOUND in `git log --oneline -5`.
- `287e2d6` (Task 2) — FOUND.
- `7b612e8` (Task 3) — FOUND.

**Acceptance grep checks:**
- All 14 plan-level acceptance grep checks pass (see "Acceptance-Criteria Greps" table above).

**Test counts:**
- `rtk mix test test/foglet_bbs/tui/app_test.exs` — 135/135 (default), 136/136 (with phase39_target).
- `rtk mix test test/foglet_bbs/tui/screens/` — 734 / 2 pre-existing failures.
- `rtk mix test test/foglet_bbs/tui/` — 1590 / 2 pre-existing failures, 3 excluded.

**Pre-existing baseline match:**
- 3 dialyzer warnings (matches deferred-items.md exactly).
- 2 test failures (matches deferred-items.md exactly).
- 0 new credo issues.

## Next Plan Readiness

- **Plan 39-06 (breadcrumb chrome migration)** — Independent of this plan; can land in any order with 39-05 once the wave 1 → wave 2 dependency (39-03, 39-04) was satisfied. App.ex changes here do NOT touch `lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex` per scope.
- **Plan 39-07 (legacy struct field deletion)** — All groundwork is in place:
  - The seven legacy struct fields are no longer read or written by any screen-specific App machinery (this plan removed all of it).
  - The two D-17 pin tests at `app_test.exs:1531-1551, 1587-1607` still compile and pass at this commit (they reference `state.current_board` / `state.current_thread`); 39-07 will delete those tests in tandem with the fields.
  - The two D-19 pin tests in `app_struct_test.exs` (tagged `:phase39_target`) currently fail with `--include phase39_target`; they will pass when 39-07 lands the field deletion.
  - The dialyzer `unknown_type: ThreadEntry.t/0` warning at `app.ex:60` will be eliminated when 39-07 deletes the `current_thread:` field that references it.
- **Plan 39-08 (verification)** — SPEC §Acceptance Criteria items 4 (R4 generic route-entry), 7 (R7 PubSub topic equivalence), and 8 (R8 generic broadcast routing) all become verifiable after this plan's three commits land:
  - R4: `! grep -nE 'defp maybe_dispatch_route_entry\(.*, :(login\|register\|…\|sysop)'` exits 0 (verified above).
  - R7: D-18 pin (MainMenu produces only `["user:u1"]`) passes today; the four parametrized topic-equivalence pins at app_test.exs:1483-1530 all pass.
  - R8: `! grep -E 'when state\.current_screen ==' lib/foglet_bbs/tui/app.ex` exits 0; broadcast-routing tests at lines 1753-1807 all pass.

---
*Phase: 39-app-shell-simplification*
*Completed: 2026-04-29*
