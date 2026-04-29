# Phase 39: App Shell Simplification — Specification

**Created:** 2026-04-28
**Ambiguity score:** 0.15 (gate: ≤ 0.20)
**Requirements:** 10 locked

## Goal

`Foglet.TUI.App` becomes a runtime shell: it owns Raxol callbacks, message normalization, route storage, generic screen-state storage, context construction, effect interpretation, modal/SizeGate precedence, session runtime hooks, and rendering dispatch — and nothing else. All seven legacy screen-specific App struct fields and every screen-name pattern match for migrated screens are removed. PubSub topic interest is declared by screens via a new optional callback rather than derived by App pattern-matching on screen state.

## Background

Phases 34–38 migrated every production screen (`Login`, `Register`, `Verify`, `MainMenu`, `BoardList`, `ThreadList`, `PostReader`, `PostComposer`, `NewThread`, `Account`, `Moderation`, `Sysop`) to the `Foglet.TUI.Screen` reducer contract (`init/1`, `update/3`, `render/2`) over `Foglet.TUI.Context`. App is currently 1,102 lines and still carries:

- Seven legacy struct fields kept "for unmigrated flows/tests": `current_board`, `current_thread`, `current_thread_list`, `posts`, `read_position`, `composer_draft`, `board_list` (`lib/foglet_bbs/tui/app.ex:62-86`).
- Screen-specific route-entry dispatch clauses for `:main_menu`, `:moderation`, `:sysop`, `:thread_list`, and `:post_reader` (`maybe_dispatch_route_entry/3`, `app.ex:810-845`).
- A `:main_menu`-specific clause in `maybe_init_initial_screen_state/1` (`app.ex:884-893`).
- Hardcoded `:main_menu, :load_oneliners` dispatch in `do_update({:set_user, …}, …)` and `do_update({:promote_session, …}, …)` (`app.ex:552-563, 699-714`).
- PubSub topic derivation that pattern-matches `current_screen` and reaches into `screen_state[:thread_list]` / `[:post_reader]` to extract IDs (`build_pubsub_topics/1`, `routed_thread_topic/1`, `thread_list_board_topic/1`, `app.ex:417-526`).
- Helper functions that decode screen-local state structs from inside App: `post_reader_state_thread_id/1`, `post_composer_state_thread_id/1`, `thread_list_state_board_id/1` (`app.ex:483-525`).
- Screen-specific PubSub message dispatch: `{:board_activity, …}` only acts when `current_screen == :board_list`, and `{:thread_activity, …}` only acts when `current_screen == :post_reader` (`app.ex:648-661`).
- Two non-test production readers of the legacy fields: `lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex:111` (`Map.get(:current_board)`) and `:131` (`Map.get(:current_thread)`).
- Test/fixture readers in `lib/foglet_bbs/tui/render_fixtures.ex:94-98`.

This phase deletes all of that and makes the App-screen boundary unambiguous: App owns runtime, screens own their own data and interests.

## Requirements

1. **Legacy App struct fields deleted**: The seven legacy screen-specific fields are removed from `%Foglet.TUI.App{}` entirely — not retained as `nil`-valued shims.
   - Current: `defstruct` and `@type t` in `app.ex:50-86` define `current_board`, `current_thread`, `current_thread_list`, `posts`, `read_position`, `composer_draft`, `board_list`.
   - Target: `%Foglet.TUI.App{}` defines only `current_screen`, `current_user`, `session_context`, `session_pid`, `terminal_size`, `route_params`, `modal`, and `screen_state`. The seven legacy fields and their type entries are gone.
   - Acceptance: `Foglet.TUI.App.__struct__() |> Map.keys()` contains none of `:current_board`, `:current_thread`, `:current_thread_list`, `:posts`, `:read_position`, `:composer_draft`, `:board_list`. A compile-time check (e.g., a unit test using `Map.has_key?/2`) proves absence.

2. **No production reader of deleted fields remains**: All non-test code that reads the seven deleted fields is migrated to read screen-local state, route_params, or context instead.
   - Current: `breadcrumb_bar.ex:111,131` reads `state.current_board` / `state.current_thread`. Production screens (`new_thread.ex`, `post_composer.ex`, `post_reader.ex`, `thread_list.ex`) reference these names in transitional code paths.
   - Target: No file under `lib/` reads any of the seven field names from an `App` struct; readers either source from `Foglet.TUI.Context`, screen-local state, or the active screen's render input.
   - Acceptance: `grep -E "(current_board|current_thread|current_thread_list|state\.posts|composer_draft|read_position|state\.board_list)" lib/` returns no matches outside trivial documentation comments.

3. **Breadcrumb chrome reads explicit input, not App state**: The chrome breadcrumb is a stateless component that receives the labels it must display.
   - Current: `breadcrumb_bar.ex` reads `Map.get(state, :current_board)` and `Map.get(state, :current_thread)` and crafts breadcrumb segments from App fields.
   - Target: `breadcrumb_bar.ex` accepts an explicit input (e.g., `%{board_label: …, thread_label: …}` or equivalent) supplied by the active screen's `render/2`. Screens that need a breadcrumb (`ThreadList`, `PostReader`, `PostComposer`, `NewThread`) derive it from their own local state and pass it through the chrome wrapper.
   - Acceptance: `lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex` contains no call to `Map.get/2` (or any other accessor) reading `:current_board` or `:current_thread`. Render-smoke tests for affected screens still produce a non-empty breadcrumb in their expected positions.

4. **Generic route-entry dispatch**: App contains no `maybe_dispatch_route_entry` clause that pattern-matches a specific screen atom for any migrated production screen.
   - Current: `app.ex:810-845` has explicit clauses for `:main_menu`, `:moderation`, `:sysop`, `:thread_list`, and `:post_reader`, each calling `route_screen_update(state, screen_key, screen_specific_message)`.
   - Target: A single generic mechanism delivers a route-entry signal to the active screen's `update/3` (or equivalent), and the screen decides what to load. App contains no per-screen dispatch clauses for production screens.
   - Acceptance: `lib/foglet_bbs/tui/app.ex` does not contain a function clause that matches `screen` against any of the production atoms (`:login`, `:register`, `:verify`, `:main_menu`, `:board_list`, `:thread_list`, `:post_reader`, `:post_composer`, `:new_thread`, `:account`, `:moderation`, `:sysop`) for the purpose of dispatching screen-specific entry messages. MainMenu, Moderation, Sysop, ThreadList, and PostReader continue to load their data on first entry, verified by their existing reducer tests.

5. **No App-side helper functions decode screen-local state**: App does not unpack screen-local state structs to extract IDs or other fields.
   - Current: `post_reader_state_thread_id/1` (`app.ex:483-488`), `post_composer_state_thread_id/1` (`app.ex:490-501`), and `thread_list_state_board_id/1` (`app.ex:521-526`) reach into screen-local state from App.
   - Target: These three helper functions are removed. Any replacement consumer (e.g., the new subscriptions callback) lives inside the owning screen module.
   - Acceptance: `grep -n "post_reader_state_thread_id\|post_composer_state_thread_id\|thread_list_state_board_id" lib/` returns no matches.

6. **`Screen.subscriptions/2` optional callback added**: The Screen behaviour declares an optional callback for screen-declared PubSub topic interest.
   - Current: `Foglet.TUI.Screen` defines `init/1`, `update/3`, `render/2`, and transitional `render/1`/`handle_key/2`/`init_screen_state/1`. No subscription callback exists. App alone derives topics by inspecting screen state.
   - Target: `Foglet.TUI.Screen` declares `@callback subscriptions(local_state, Foglet.TUI.Context.t()) :: [String.t()]` and lists it under `@optional_callbacks`. Screens that need extra PubSub topics (`PostReader`, `ThreadList`) implement the callback; stateless screens (`Login`, `MainMenu`, etc.) do not.
   - Acceptance: `Foglet.TUI.Screen.behaviour_info(:optional_callbacks)` includes `{:subscriptions, 2}`. `function_exported?(Foglet.TUI.Screens.PostReader, :subscriptions, 2)` and `function_exported?(Foglet.TUI.Screens.ThreadList, :subscriptions, 2)` both return `true`.

7. **App PubSub derivation uses screen-declared interests**: `Foglet.TUI.App.subscribe/1` derives screen-specific topics by calling `subscriptions/2` on the active screen, not by pattern-matching `current_screen` or peeking into `screen_state`.
   - Current: `build_pubsub_topics/1` (`app.ex:433-461`), `routed_thread_topic/2`, `thread_list_board_topic/1`, and friends pattern-match `current_screen` and read `screen_state[:thread_list]` / `[:post_reader]` directly.
   - Target: App's subscribe path produces user-level and global topics generically, then unions them with `screen_module.subscriptions(local_state, context)` for the active route when the callback is exported. App contains no `current_screen` pattern matches for topic derivation and no reads of specific screen-state keys.
   - Acceptance: For an equivalent App state, the topic set produced by the new path matches the topic set produced by the old path (verified by a regression test that pins the topic list for `:thread_list` with a known `board_id`, `:post_reader` with a known `thread_id`, `:board_list`, and an authenticated screen with neither). `lib/foglet_bbs/tui/app.ex` contains no function clause that pattern-matches `current_screen` against a production-screen atom for the purpose of building a PubSub topic.

8. **PubSub broadcast messages route generically**: `{:board_activity, …}` and `{:thread_activity, …}` are forwarded to the active screen via the generic update path; App does not gate them on `current_screen`.
   - Current: `do_update({:board_activity, _, _}, state)` only fires `route_screen_update(:board_list, :load)` when `current_screen == :board_list`; `{:thread_activity, _, _}` only fires when `current_screen == :post_reader` (`app.ex:648-661`).
   - Target: Both messages route through the generic active-screen update mechanism. Screens that care (`BoardList`, `PostReader`) handle them in their `update/3`; screens that do not are no-ops.
   - Acceptance: App contains no clause that gates a PubSub broadcast on a specific `current_screen` atom. `BoardList` and `PostReader` reducer tests prove the messages reach `update/3` and produce the expected reload effects.

9. **Modal precedence and SizeGate remain App-owned**: Modal opening, dismissal, confirm-yes/no, form submit/cancel routing, and SizeGate render-time short-circuit stay in App as runtime concerns.
   - Current: `render_modal_overlay/2`, `global_key_handler/2`, `handle_modal_key/3` clauses, and the SizeGate branch in `view/1` are all App-resident (`app.ex:347-363, 982-1046`).
   - Target: Same — modal precedence and SizeGate are intentionally App-level. Screen-issued modal requests continue to flow through `Effect.modal(:open|:dismiss)` and are interpreted by `apply_effect/2`.
   - Acceptance: `app_test.exs` modal-precedence and SizeGate tests pass without modification. No screen module routes a modal key event without going through `apply_effect/2` for `Effect.modal`.

10. **App module materially smaller**: `lib/foglet_bbs/tui/app.ex` shrinks by ≥30% in line count from its current 1,102-line baseline.
    - Current: `wc -l lib/foglet_bbs/tui/app.ex` → 1,102.
    - Target: `wc -l lib/foglet_bbs/tui/app.ex` ≤ 750 lines, achieved by deleting (not relocating-via-comment) screen-specific clauses, helpers, and legacy fields. The remaining App reads as a runtime shell — Raxol callbacks, normalization, route storage, screen-state storage, generic update routing, effect interpretation, modal/SizeGate, session/PubSub plumbing, and rendering dispatch.
    - Acceptance: `wc -l lib/foglet_bbs/tui/app.ex` returns ≤ 750. Public `app.ex` exports continue to satisfy every existing screen and test caller without compatibility shims.

## Boundaries

**In scope:**
- Delete `current_board`, `current_thread`, `current_thread_list`, `posts`, `read_position`, `composer_draft`, `board_list` from the App struct, type, and every reader.
- Migrate `breadcrumb_bar.ex` and any screen render path that supplied breadcrumb data via App fields to the explicit-input shape.
- Add `Screen.subscriptions/2` as an `@optional_callbacks` member of `Foglet.TUI.Screen`; implement it in `PostReader` and `ThreadList`.
- Replace App's screen-name pattern matches (route-entry dispatch, PubSub topic derivation, PubSub broadcast routing, initial-screen-state) with a generic mechanism that defers to the active screen.
- Remove `post_reader_state_thread_id/1`, `post_composer_state_thread_id/1`, `thread_list_state_board_id/1`, and any other App-side accessor that decodes a specific screen's local state.
- Update `lib/foglet_bbs/tui/render_fixtures.ex`, `test/foglet_bbs/tui/...` fixtures, and any other test helpers that construct App states using the deleted fields.
- Adjust the small handful of `do_update` clauses that hardcode `:main_menu, :load_oneliners` so MainMenu owns its own first-load via the generic route-entry mechanism.

**Out of scope:**
- New product features or screen behavior changes — this phase is a pure ownership refactor.
- Changes to `Foglet.Boards`, `Foglet.Threads`, `Foglet.Posts`, `Foglet.Accounts`, `Foglet.Sessions.*`, or `Foglet.SSH.*` — domain authority is unchanged.
- Removing the transitional `render/1`, `handle_key/2`, `init_screen_state/1` callbacks from `Foglet.TUI.Screen` — these are already optional; final cleanup is Phase 40 territory.
- Adding new `Effect` types beyond what the generic route-entry / subscriptions mechanisms strictly require.
- Verification, milestone-close, or documentation work — those are Phase 40.
- Any change to Raxol upstream, the heartbeat/clock subscription cadence, or the SSH channel lifecycle.
- Browser/Phoenix endpoints — Foglet BBS is SSH-first; Phoenix infrastructure is untouched here.

## Constraints

- No screen-specific pattern match may be introduced into `Foglet.TUI.App` to satisfy any of these requirements; the cleanup must remove them, not relocate them.
- `Screen.subscriptions/2` MUST remain optional — stateless screens (Login, Register, Verify, MainMenu, Account, Moderation, Sysop, BoardList, NewThread, PostComposer) must compile and run without implementing it. Today, only `PostReader` and `ThreadList` have a non-empty topic set.
- All existing `mix precommit` checks (compile with warnings as errors, formatter, Credo, Sobelow, Dialyzer) must pass.
- No new tests may merely assert presence/absence of literal text strings — per `AGENTS.md`, those tests are explicitly disallowed. Coverage must assert behavior (state transitions, effects, struct shape, callback exports, topic equivalence).
- Per-board message-number invariants and `Foglet.Boards.Server` write-path are unaffected; this phase touches only the TUI runtime boundary.

## Acceptance Criteria

- [ ] `Map.keys(%Foglet.TUI.App{})` returns exactly `[:current_screen, :current_user, :session_context, :session_pid, :terminal_size, :route_params, :modal, :screen_state]` (order-independent).
- [ ] `grep -nE "current_board|current_thread|current_thread_list|state\.posts|composer_draft|read_position|state\.board_list" lib/` returns no production code matches outside docstrings.
- [ ] `lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex` contains no `Map.get(_, :current_board)` or `Map.get(_, :current_thread)` call.
- [ ] `lib/foglet_bbs/tui/app.ex` contains no function clause that pattern-matches a production-screen atom (`:login`, `:register`, `:verify`, `:main_menu`, `:board_list`, `:thread_list`, `:post_reader`, `:post_composer`, `:new_thread`, `:account`, `:moderation`, `:sysop`) for the purpose of dispatching screen-specific entry messages, broadcast handling, initial-state seeding, or PubSub topic derivation.
- [ ] `grep -n "post_reader_state_thread_id\|post_composer_state_thread_id\|thread_list_state_board_id" lib/` returns no matches.
- [ ] `Foglet.TUI.Screen.behaviour_info(:optional_callbacks)` includes `{:subscriptions, 2}`.
- [ ] `function_exported?(Foglet.TUI.Screens.PostReader, :subscriptions, 2)` and `function_exported?(Foglet.TUI.Screens.ThreadList, :subscriptions, 2)` are both `true`.
- [ ] A regression test pins the topic list produced by `Foglet.TUI.App.subscribe/1` for: (a) authenticated MainMenu (no extra topics), (b) BoardList route (boards aggregate topic present), (c) ThreadList with a known `board_id` (board topic present), and (d) PostReader with a known `thread_id` (thread topic present). The test passes both before any rewrite and after.
- [ ] Existing modal precedence tests in `test/foglet_bbs/tui/app_test.exs` (info/error/warning dismiss, confirm yes/no, form submit/cancel) pass without modification.
- [ ] `wc -l lib/foglet_bbs/tui/app.ex` returns a value ≤ 750.
- [ ] `mix precommit` exits 0.
- [ ] `mix foglet.tui.render main_menu`, `…board_list`, `…thread_list`, `…post_reader`, and `…account` produce output that is byte-for-byte unchanged (after ANSI-strip) versus the pre-phase baseline, except for any breadcrumb input change explicitly visible in screen render output.

## Ambiguity Report

| Dimension          | Score | Min  | Status | Notes                                                              |
|--------------------|-------|------|--------|--------------------------------------------------------------------|
| Goal Clarity       | 0.92  | 0.75 | ✓      | Legacy fields deleted; App becomes runtime shell                   |
| Boundary Clarity   | 0.85  | 0.70 | ✓      | Field set, breadcrumb path, PubSub model all locked                |
| Constraint Clarity | 0.78  | 0.65 | ✓      | `subscriptions/2` optional; `mix precommit` gate; no new pattern matches |
| Acceptance Criteria| 0.78  | 0.70 | ✓      | 12 falsifiable checks (struct shape, grep absence, exports, line count) |
| **Ambiguity**      | 0.15  | ≤0.20| ✓      |                                                                    |

## Interview Log

| Round | Perspective | Question summary                                          | Decision locked                                                                                                  |
|-------|-------------|----------------------------------------------------------|------------------------------------------------------------------------------------------------------------------|
| 1     | Researcher  | Legacy App struct fields — delete or keep?              | (a) Delete all seven fields entirely (`current_board`, `current_thread`, `current_thread_list`, `posts`, `read_position`, `composer_draft`, `board_list`) |
| 1     | Researcher  | Breadcrumb chrome reader — how does it source labels?   | (c) Each screen's `render/2` passes explicit breadcrumb input into a stateless chrome wrapper                    |
| 1     | Researcher  | PubSub topic interest — screen callback or App-side route derivation? | (a) Add `Screen.subscriptions(local_state, Context.t()) :: [topic]` as `@optional_callbacks`; App unions screen-declared topics with global/user topics |

---

*Phase: 39-app-shell-simplification*
*Spec created: 2026-04-28*
*Next step: /gsd-discuss-phase 39 — implementation decisions (route-entry mechanism shape, breadcrumb input contract, subscription regression test fixtures, etc.)*
