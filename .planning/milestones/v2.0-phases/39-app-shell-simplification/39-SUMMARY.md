# Phase 39 — App Shell Simplification — Summary

**Completed:** 2026-04-29
**Wave 0 baselines:** `test/foglet_bbs/tui/render_snapshots/{main_menu,board_list,thread_list,post_reader,account}.txt`
**Plans executed:** 39-01 through 39-08 (8 plans, 5 waves).

`Foglet.TUI.App` is now a runtime shell. Every function in the module maps to one of: Raxol callback, message normalization, route storage, screen-state storage, context construction, effect interpretation, modal/SizeGate precedence, session runtime hook, PubSub plumbing, or rendering dispatch. The seven legacy screen-specific struct fields (`current_board`, `current_thread`, `current_thread_list`, `posts`, `read_position`, `composer_draft`, `board_list`) are gone; PubSub topic interest is sourced via the new `Screen.subscriptions/2` optional callback; route-entry dispatch is one screen-agnostic clause; broadcast routing (`{:board_activity, …}`, `{:thread_activity, …}`) reaches the active screen via the generic update path. App.ex shrank from 1102 lines to 957 (-145 lines, ~13.2% reduction), purely as the consequence of deletions called out in Requirements 1, 4, 5, 7, and 8.

---

## SPEC §Acceptance Criteria — Evidence

| # | Check | Command | Result |
|---|-------|---------|--------|
| 1 | Struct keys exact | `rtk mix run -e 'IO.inspect(Map.keys(%Foglet.TUI.App{}) \|> Enum.sort())'` | ✅ `[:__struct__, :current_screen, :current_user, :modal, :route_params, :screen_state, :session_context, :session_pid, :terminal_size]` (8 user-visible fields + `:__struct__`) |
| 2 | No production reader of deleted fields | `rtk grep -rnE 'state\.(current_board\|current_thread\|current_thread_list\|posts\|read_position\|composer_draft\|board_list)\b' lib/` | ✅ 2 matches, both in comments (`new_thread.ex:624`, `post_reader.ex:494`) referring to deleted writes — no executable readers |
| 3 | BreadcrumbBar reads no legacy field | `rtk grep -nE 'Map\.get\(.*:current_board\|Map\.get\(.*:current_thread' lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex` | ✅ exit 1 (empty) |
| 4 | App has no production-screen atom dispatch pattern | `rtk grep -nE 'defp? [a-z_]+\(.*:(login\|register\|verify\|main_menu\|board_list\|thread_list\|post_reader\|post_composer\|new_thread\|account\|moderation\|sysop),' lib/foglet_bbs/tui/app.ex \| grep -v 'Effect\.navigate'` AND `rtk grep -nE 'current_screen ==\|current_screen in \[' lib/foglet_bbs/tui/app.ex` | ✅ both empty (exit 1). The `screen_module_for/1` table (12 single-arg clauses, no trailing comma) is the static route→module dispatch table — explicitly permitted, not a behavior dispatch. |
| 5 | Decoder helpers gone | `rtk grep -rn 'post_reader_state_thread_id\|post_composer_state_thread_id\|thread_list_state_board_id' lib/` | ✅ exit 1 (empty) |
| 6 | `behaviour_info` includes `subscriptions/2` | `rtk mix run -e 'IO.inspect({:subscriptions, 2} in Foglet.TUI.Screen.behaviour_info(:optional_callbacks))'` | ✅ `true` |
| 7 | `function_exported?` for PostReader / ThreadList / BoardList | `rtk mix run -e 'Code.ensure_loaded?(Foglet.TUI.Screens.PostReader); Code.ensure_loaded?(Foglet.TUI.Screens.ThreadList); Code.ensure_loaded?(Foglet.TUI.Screens.BoardList); IO.inspect({:post_reader, function_exported?(...)}); ...'` | ✅ all three `true` |
| 8 | Topic regression for four cases | `rtk mix test test/foglet_bbs/tui/app_test.exs --only describe:"subscribe/1"` | ✅ 12 tests, 0 failures |
| 9 | Modal precedence tests pass without modification | `rtk mix test test/foglet_bbs/tui/app_test.exs --only describe:"modal key dismissal (task #6)"` | ✅ 10 tests, 0 failures |
| 10 | Functional attribution (qualitative) | human review | ✅ Recorded under "## Qualitative App-Shell Review (SPEC R10 attestation)" below — PASS pending human approval |
| 11 | `mix precommit` exits 0 | `rtk mix precommit` | ⚠ exits 2 — but on the **two pre-existing dialyzer warnings tracked in `deferred-items.md`** (`board_list.ex:161` pattern_match_cov, `sysop.ex:823` pattern_match). Phase 39 introduced ZERO new precommit failures and resolved the third pre-existing warning (`app.ex:63 ThreadEntry.t/0`, eliminated by Plan 39-07's struct-field deletion). |
| 12 | Render byte-equivalence (5 screens) | `for s in main_menu board_list thread_list post_reader account; do diff -u "test/foglet_bbs/tui/render_snapshots/$s.txt" <(rtk mix foglet.tui.render "$s" \| sed 's/\x1b\[[0-9;]*m//g'); done` | ✅ All deltas are either (a) wall-clock time stamps in the chrome's right-edge `HH:MM` slot or (b) the expected breadcrumb migration deltas explicitly documented in Plan 39-06's SUMMARY (see "Render Byte-Equivalence Diff Results" below). No semantic regression. |

---

## Line-Count Delta (non-gating per SPEC R10)

| File | Pre-phase | Post-phase | Delta |
|------|-----------|------------|-------|
| `lib/foglet_bbs/tui/app.ex` | 1102 | 957 | **-145 lines (-13.2%)** |
| `lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex` | 151 | 62 | **-89 lines (-58.9%)** |
| `lib/foglet_bbs/tui/render_fixtures.ex` | 426 | 420 | **-6 lines (-1.4%)** |

**Total deletion across the three files: -240 lines.** The reduction in `app.ex` is the consequence of deleting six topic-decoder helpers, five per-screen route-entry clauses, the `:main_menu` initial-state shim, the `maybe_seed_legacy_route_context/3` no-op, the `route_param/2` helper, three unused aliases, and the seven legacy struct fields (with the type entries that referenced them). The reduction in `breadcrumb_bar.ex` is the consequence of deleting `parts_for/1` and seven private helpers (`board_name/1`, `thread_title/1`, `screen_state_for/2`, `login_parts/1`, `screen/1`, `map_or_empty/1`); the widget is now a pure list-only formatter.

---

## Render Byte-Equivalence Diff Results

For each tracked screen, `diff -u test/foglet_bbs/tui/render_snapshots/<screen>.txt <(rtk mix foglet.tui.render <screen> | sed 's/\x1b\[[0-9;]*m//g')`:

| Screen | Diff verdict | Explanation |
|--------|--------------|-------------|
| `main_menu` | breadcrumb-only delta + wall-clock time | Top-border breadcrumb changed from `Foglet ▸ Home` to `Foglet`. MainMenu is NOT one of the four screens migrated to explicit `breadcrumb_parts` in Plan 39-06; it now uses the default `["Foglet"]` from `ScreenFrame.normalize_chrome/2`. **Expected and explicitly captured in 39-06 SUMMARY (Decisions Made #3).** Time stamp `22:36 → 00:16` is wall-clock advance. |
| `board_list` | breadcrumb-only delta + wall-clock time | Same migration consequence: `Foglet ▸ Boards` → `Foglet`. BoardList is NOT in 39-06 scope. Expected. |
| `thread_list` | wall-clock time only | Breadcrumb `Foglet ▸ general` is **identical** to the baseline — ThreadList IS in Plan 39-06's scope, so its `breadcrumb_parts: ["Foglet", board_label(state)]` reproduces the original segment exactly via screen-local state. Only the time stamp differs. ✅ |
| `post_reader` | wall-clock time only (and the cache-warning timestamp) | Breadcrumb `Foglet ▸ general ▸ Welcome — read me first` is **identical** — PostReader IS in 39-06's scope. The `[PostReader] render cache miss for post=p-1 width=80` warning's timestamp differs, which is wall-clock noise. ✅ |
| `account` | breadcrumb-only delta + wall-clock time | `Foglet ▸ Account` → `Foglet`. Account is NOT in 39-06 scope. Expected. |

**Summary:** Three of five screens show the explicitly-permitted breadcrumb-only delta from the SPEC's exception clause ("…except for any breadcrumb input change explicitly visible in screen render output"). Two of five screens (`thread_list`, `post_reader`) reproduce their breadcrumbs exactly via the new screen-owned contract — proof that the Plan 39-06 migration is byte-for-byte equivalent for the screens it covers. **No screen exhibits a non-breadcrumb non-timestamp change.** No regression.

If Login / MainMenu / BoardList / Account / Moderation / Sysop breadcrumbs need to be restored, that is Phase 40 scope (each remaining screen migrating to explicit `breadcrumb_parts` with its own per-screen `board_label` / `thread_title_label` helpers, mirroring Plan 39-06's pattern). Plan 39-06's SUMMARY explicitly defers Login (`@tag :phase39_login_breadcrumb_pending`) for that follow-up.

---

## Test Migrations / Deletions (D-17, D-23)

Recorded in detail in `39-07-SUMMARY.md` (Tests Deleted and Tests Migrated tables). Headline counts:

- **Deleted from `app_test.exs` (4):** Two D-17 pin tests for the legacy `current_board`/`current_thread` fields; two `{:boards_loaded}`/`{:threads_loaded}` "leaves X untouched" no-op pins.
- **Migrated in `app_test.exs` (~17):** Setup-block migrations from `current_board:`/`current_thread:`/`board_list:`/etc. to `screen_state.<screen>` reads.
- **Migrated in `post_reader_test.exs` (~30):** `setup` and `p2_state/1` rewritten with backward-compatible legacy override-key translation; ~10 test bodies migrated from `s.posts` / `s.read_position[...]` to `s.screen_state.post_reader.posts` / `s.screen_state.post_reader.pending_read_positions[...]`.
- **Migrated in `post_composer_test.exs` (3 sites):** Two App-struct constructors and the `with_reply/2` helper.
- **Migrated in `new_thread_test.exs` (3):** Submit-success assertions rewritten to assert on `cmds` instead of `final.current_board.id`.
- **Migrated in `app_runtime_contract_test.exs` (2):** `state/1` helper trimmed; two assertion blocks updated.
- **Migrated in `layout_smoke_test.exs` (1):** PostComposer App-struct constructor.

---

## Closed Requirements

- [x] **STATE-02** — App struct narrowed to 8 runtime-shell fields. (Closed by 39-07, verified by `app_struct_test.exs` running un-tagged in the default suite.)
- [x] **STATE-03** — BreadcrumbBar reads explicit `breadcrumb_parts` input. No `Map.get(state, :current_board)` / `Map.get(state, :current_thread)` calls in the chrome widget. (Closed by 39-06.)
- [x] **STATE-04** — Decoder helpers (`post_reader_state_thread_id/1`, `post_composer_state_thread_id/1`, `thread_list_state_board_id/1`) gone. (Closed by 39-05.)
- [x] **APP-01** — App reads end-to-end as a runtime shell. Every function attributable to a runtime-shell category (see "## Qualitative App-Shell Review (SPEC R10 attestation)" below). Line-count delta -145.
- [x] **APP-02** — No screen-specific result-handler gates on `current_screen`. `{:board_activity, …}` and `{:thread_activity, …}` route generically through `route_screen_update/3`. (Closed by 39-05.)
- [x] **APP-03** — PubSub topic interest sourced from `Screen.subscriptions/2` optional callback. App owns user-level (`user:<id>`) topics only; `screen_declared_topics/1` defers to the active screen. (Closed by 39-02 declaring the callback, 39-03 implementing on three stateful screens, 39-05 wiring App's subscribe path.)
- [x] **APP-04** — Modal precedence and SizeGate remain App-owned. The 10 modal-key-dismissal tests in `app_test.exs` pass without modification (Check 9 above).

---

## Outstanding (Phase 40 scope)

- **VERIFY-01..05** — Phase 40 verification work (consume this SUMMARY, run /gsd-verify-work).
- **Removal of transitional callbacks** (`render/1`, `handle_key/2`, `init_screen_state/1`) from `Foglet.TUI.Screen`. These remain `@optional_callbacks` for now; 39-07 removed all production reads of the legacy App fields they were designed to bridge, but the callback declarations themselves stay until Phase 40 confirms no fixture / test path still uses them.
- **Login / MainMenu / BoardList / Account / Moderation / Sysop breadcrumb migration** — those six screens still use the `["Foglet"]` default breadcrumb. Plan 39-06 covered ThreadList / PostReader / PostComposer / NewThread; Phase 40 (or a dedicated chrome-finishing plan) extends the same `breadcrumb_parts` contract to the rest. Plan 39-06's `@tag :phase39_login_breadcrumb_pending` already pins three Login-breadcrumb regression tests for that follow-up.
- **Pre-existing dialyzer warnings**: `lib/foglet_bbs/tui/screens/board_list.ex:161:9 pattern_match_cov` and `lib/foglet_bbs/tui/screens/sysop.ex:823:8 pattern_match`. Both predate Phase 39 and are tracked in `deferred-items.md`.
- **Pre-existing test failures**: `test/foglet_bbs/tui/screens/account_test.exs:1242, 1271` — BL-01 form-modal lock release tests on doomed-submit error routing. Both predate Phase 39, unchanged by all eight plans.

---

## Qualitative App-Shell Review (SPEC R10 attestation)

> **VERDICT (executor):** PASS — every function in `lib/foglet_bbs/tui/app.ex` (957 lines, post-Phase-39) maps to exactly one of the runtime-shell categories defined in SPEC R10. Pending human verification.

### Function-by-function classification

The table below classifies every `def`/`defp` in `app.ex` (post-Phase-39) into one of the runtime-shell categories. Source line numbers are at HEAD `c9c14f7`.

| # | Function | Lines | Category | Notes |
|---|----------|-------|----------|-------|
| 1 | `current_route/1` (2 clauses) | 75-80 | Route storage | Returns atom or `{atom, params}` from the App struct |
| 2 | `screen_key/1` (2 clauses) | 84-85 | Route storage | Collapses `current_route` shape to atom |
| 3 | `current_screen_state/1` | 89-91 | Screen-state storage | |
| 4 | `screen_state_for/2` | 95-97 | Screen-state storage | |
| 5 | `put_screen_state/3` | 101-103 | Screen-state storage | |
| 6 | `build_context/1` | 107-109 | Context construction | |
| 7 | `build_context/2` | 113-123 | Context construction | |
| 8 | `apply_effect/2` (12 clauses, `:navigate`/`:modal`/`:session(set_user/set_current_user/update_preferences/dispatch/default)`/`:terminal`/`:publish`/`:quit`/`:task`) | 127-228 | Effect interpretation | Each clause interprets one Effect type → `{state, [Command.t()]}` |
| 9 | `apply_effects/2` | 232-237 | Effect interpretation | Reduce over a list |
| 10 | `init/1` (`@impl true`) | 242-271 | Raxol callback | Lifecycle entry; unpacks context, derives initial screen, registers TUI pid with Session |
| 11 | `initial_screen/1` (2 clauses) | 273-274 | Session runtime hook | Bridges `Foglet.Accounts.post_login_screen/1` to runtime entry — picks `:login` or post-login screen based on user |
| 12 | `extract_context/1` | 284-300 | Raxol callback support | Unpacks Lifecycle-shape vs test-shape input — runtime-only adapter |
| 13 | `update/2` (`@impl true`) | 303-305 | Raxol callback | Delegates via `normalize_message → do_update` |
| 14 | `normalize_message/1` (4 clauses) | 311-323 | Message normalization | Raxol `%Event{}` → `{:key, data}` / `{:window_change, w, h}` |
| 15 | `view/1` (`@impl true`) | 326-341 | Raxol callback | SizeGate / modal / render_screen branch |
| 16 | `render_modal_overlay/2` | 352-362 | Modal/SizeGate | Centered modal overlay render |
| 17 | `subscribe/1` (`@impl true`) | 365-405 | Raxol callback | Heartbeat + clock + PubSub topics |
| 18 | `build_pubsub_topics/1` | 416-425 | PubSub plumbing | User-level topics + screen-declared topics |
| 19 | `screen_declared_topics/1` | 431-440 | PubSub plumbing | Defers to active screen via `subscriptions/2` callback |
| 20 | `do_update/2` (~20 clauses: `:window_change`, `:navigate`, `:set_user`, `:show_modal`, `:dismiss_modal`, `:confirm_modal`, `:key`, `:board_activity`, `:thread_activity`, `:notification`, `:heartbeat_tick`, `:main_menu_clock_tick`, `:session_replaced`, `:promote_session`, `:command_result`, `:screen_task_result`, `:terminate_after_modal`, `:task_error`, catch-all) | 444-658 | Effect interpretation | Each clause interprets one runtime message; the `:board_activity` and `:thread_activity` clauses are screen-agnostic (route via `route_screen_update`); the `:set_user` / `:promote_session` clauses use `Effect.navigate` (no hardcoded screen-specific dispatch) |
| 21 | `domain_from_session_context/1` (2 clauses) | 660-667 | Context construction | Helper for `build_context/2` |
| 22 | `init_route_screen_state/3` | 669-686 | Screen-state storage | Initializes screen-local state via `module.init/1` |
| 23 | `route_owned_screen?/1` (2 clauses) | 688-692 | Screen-state storage | Predicate — keys whose state is route-owned (re-init on every navigate) |
| 24 | `reinitialize_route_state?/3` | 694-698 | Screen-state storage | Predicate — combine route-owned + new-params signals |
| 25 | `maybe_dispatch_route_entry/3` | 707-709 | Effect interpretation | One clause: always dispatches `:on_route_enter` to active screen |
| 26 | `route_screen_update/3` | 711-725 | Effect interpretation / PubSub plumbing | Generic active-screen update routing — applies effects after the call |
| 27 | `new_contract_screen?/2` | 727-731 | Effect interpretation support | Probe for `update/3` exported on a screen module |
| 28 | `context_for_screen_key/2` | 733-742 | Context construction | Per-screen context with route_params filtering |
| 29 | `maybe_init_initial_screen_state/1` | 750-752 | Screen-state storage | One clause: defers to `init_route_screen_state/3` |
| 30 | `take_screen_modal_submit/0` | 754-758 | Modal/SizeGate | Form-modal submit handoff via process dictionary |
| 31 | `humanize_op/1` | 760-762 | Effect interpretation support | Op-name humanization for task error messages |
| 32 | `merge_session_preferences/2` | 764-773 | Session runtime hook | Updates session_context with user preferences |
| 33 | `refresh_session_preferences/2` (2 clauses) | 775-781 | Session runtime hook | Notifies Session GenServer of preference change |
| 34 | `format_notification/3` (3 clauses) | 783-785 | Effect interpretation support | Format helper for the `:notification` modal message |
| 35 | `process_screen_commands/2` | 794-813 | Effect interpretation | Routes legacy I/O tuples returned by screens through `do_update/2` |
| 36 | `render_screen/1` | 815-825 | Rendering dispatch | Active-screen render entry |
| 37 | `render_local_state/4` | 827-835 | Rendering dispatch | Renders screen-local state, lazy-init via `module.init/1` if absent |
| 38 | `global_key_handler/2` (2 clauses) | 840-845 | Modal/SizeGate | Routes keys through `handle_modal_key` when a modal is active |
| 39 | `handle_modal_key/3` (~10 clauses: `:confirm` y/n/escape, `:form` submit/cancel/other, `:info`/`:error`/`:warning` enter/escape/space, catch-all) | 848-901 | Modal/SizeGate | Modal-key precedence handlers |
| 40 | `wrap_commands/1` | 908 | Effect interpretation support | Adapter for modal callback returns |
| 41 | `wrap_command/1` (3 clauses) | 910-912 | Effect interpretation support | `{:terminate, _}` → `Command.quit()`, `%Command{}` passthrough |
| 42 | `screen_module_for/2` | 914-926 | Screen-state storage | Domain-override-aware route→module lookup |
| 43 | `known_screens/0` | 928-943 | Screen-state storage | List of route atoms known to the runtime |
| 44 | `screen_module_for/1` (12 clauses, one per route atom) | 945-956 | Screen-state storage | Static route→module dispatch table — NOT a behavior dispatch (no runtime branching on screen identity beyond returning the module). Permitted per SPEC Check 4 ("function-clause head pattern matches like `defp foo(state, :main_menu, ...)`" — the prohibition is on multi-arg clauses keyed off a screen atom for behavior; the single-arg lookup table has no trailing comma in the regex and is the canonical Elixir idiom for an atom→module map). |

### Category counts

| Category | Function count |
|----------|---------------:|
| Raxol callback | 4 (`init`, `update`, `view`, `subscribe`) |
| Raxol callback support (init helper) | 1 (`extract_context`) |
| Message normalization | 1 (`normalize_message` w/ 4 clauses) |
| Route storage | 2 (`current_route`, `screen_key`) |
| Screen-state storage | 8 (`current_screen_state`, `screen_state_for`, `put_screen_state`, `init_route_screen_state`, `route_owned_screen?`, `reinitialize_route_state?`, `maybe_init_initial_screen_state`, `screen_module_for/1+2` + `known_screens`) |
| Context construction | 4 (`build_context/1`, `build_context/2`, `domain_from_session_context`, `context_for_screen_key`) |
| Effect interpretation | ~10 (`apply_effect`, `apply_effects`, `do_update` w/ ~20 clauses, `maybe_dispatch_route_entry`, `route_screen_update`, `new_contract_screen?`, `process_screen_commands`, `humanize_op`, `format_notification`, `wrap_commands`, `wrap_command`) |
| Modal / SizeGate | 4 (`render_modal_overlay`, `take_screen_modal_submit`, `global_key_handler`, `handle_modal_key`) |
| Session runtime hook | 3 (`initial_screen`, `merge_session_preferences`, `refresh_session_preferences`) |
| PubSub plumbing | 2 (`build_pubsub_topics`, `screen_declared_topics`) |
| Rendering dispatch | 2 (`render_screen`, `render_local_state`) |

### Findings

- **No function exists solely to handle one specific production screen.** The `do_update` clauses for `:board_activity` and `:thread_activity` are screen-agnostic (they route via `route_screen_update` to the active screen). The `:set_user` and `:promote_session` clauses use `Effect.navigate(:main_menu, %{})` — the `:main_menu` here is a literal data argument to `Effect.navigate`, not a pattern match for behavior selection. The `screen_module_for/1` table is a static route→module map; no clause encodes screen-specific behavior beyond returning the module name.
- **No clause pattern-matches `current_screen` against a screen atom for behavior gating.** Verified by `grep` (Check 4b above). The legacy `state.current_screen ==` and `current_screen in [...]` patterns are gone.
- **PubSub topic derivation never names a screen.** `build_pubsub_topics/1` produces `user:<id>` topics directly and delegates everything else to `screen_declared_topics/1`, which calls `module.subscriptions(state, ctx)`. App.ex contains no string literal of the form `"thread:#{id}"` or `"board:#{id}"` (those live in the screen modules' subscriptions implementations).
- **Route-entry dispatch is one screen-agnostic clause.** `maybe_dispatch_route_entry/3` always dispatches `:on_route_enter`. Each screen owns its first-load semantics in its own `:on_route_enter` reducer clause.

### Reviewer verdict (executor self-attestation)

PASS. Every function in `lib/foglet_bbs/tui/app.ex` is attributable to a runtime-shell responsibility. There are zero functions whose purpose is to handle one specific migrated production screen.

---

## Phase 39 Plan-by-Plan Recap

| Plan | Wave | Title | Key contribution |
|------|-----:|-------|------------------|
| 39-01 | 0 | Wave 0 baseline + pin tests | 5 ANSI-stripped render snapshots + 7 fail-loud pin tests behind `:phase39_target` exclude |
| 39-02 | 1 | `Screen.subscriptions/2` optional-callback declaration | `@optional_callbacks` extended; behaviour pin from 39-01 turns green |
| 39-03 | 1 | `subscriptions/2` implementation on 3 stateful screens | PostReader / ThreadList / BoardList implement the callback |
| 39-04 | 2 | `:on_route_enter` reducer clauses on 5 screens | MainMenu / Moderation / Sysop / ThreadList / PostReader own first-load |
| 39-05 | 2 | App-side cleanup (build_pubsub_topics, route-entry dispatch, broadcast routing) | App.ex shrinks 1102 → 975 (-127); 6 topic decoders + 5 per-screen route-entry clauses gone |
| 39-06 | 3 | Breadcrumb chrome migration to explicit `breadcrumb_parts` | BreadcrumbBar 151 → 62 lines; 4 screens emit `:breadcrumb_parts` |
| 39-07 | 4 | Legacy struct-field deletion + test fixture migration | App struct 15 → 8 fields; ~50 test fixture sites migrated |
| 39-08 | 4 | Phase verification + summary | This document |

---

## Self-Check

- All 12 SPEC §Acceptance Criteria checks have evidence captured above (Check 11 noted as baseline-relative; Check 12 noted as expected breadcrumb-migration delta + wall-clock noise).
- Line-count delta recorded (-145 in app.ex, -89 in breadcrumb_bar.ex, -6 in render_fixtures.ex).
- All 7 Phase 39 requirement IDs (STATE-02, STATE-03, STATE-04, APP-01, APP-02, APP-03, APP-04) listed under "Closed Requirements".
- Qualitative App-Shell Review (SPEC R10 attestation) section present with verdict PASS pending human approval.
- Render byte-equivalence diff results captured for all 5 tracked screens.

**Status:** PASS pending the SPEC R10 human-verify checkpoint approval.

---
*Phase: 39-app-shell-simplification*
*Completed: 2026-04-29*
