# Phase 47: Bound unbounded list queries, drop Chrome V1 shims, and reduce App + large screen modules — Specification

**Created:** 2026-04-30
**Ambiguity score:** 0.15 (gate: ≤ 0.20)
**Requirements:** 7 locked

## Goal

Eliminate the three residual debt items called out in `.planning/codebase/CONCERNS.md` after Phase 46: (1) the unbounded list queries `Foglet.Posts.list_posts/1` and `Foglet.Threads.list_threads/2`, (2) the Chrome V1 compatibility shims in the chrome widget set, and (3) the mixed-mode `Foglet.TUI.Screens.Login` reducer plus continued reduction of `Foglet.TUI.App`.

## Background

Phase 46 closed the v2.1 traceability table for everything except **TUI-05** (separated reducer/state/render for screens with mixed responsibilities) and refreshed `CONCERNS.md` with the residual items still in the tree:

- **Unbounded queries.** `Foglet.Posts.list_posts/1` (`lib/foglet_bbs/posts.ex:84-92`) returns every non-deleted post in a thread. Despite Phase 44 routing the windowed reading path through `list_reader_window/2`, the initial bulk load in `Foglet.TUI.Screens.PostReader.load_posts/2` (`post_reader.ex:309`) still calls `list_posts/1` — a Phase 44 residual that was never migrated. `Foglet.Threads.list_threads/2` (`threads.ex:106-152`) joins thread read-pointer rows with no `LIMIT` and is the sole data source for the active board view through `Foglet.TUI.Screens.ThreadList` (`thread_list.ex:269`).
- **Chrome V1 shims.** Four widget modules carry parallel V1 / V2 code paths: `Foglet.TUI.Widgets.Chrome.KeyBar` (26 lines), `ScreenFrame` (212), `StatusBar` (150), and `Normalizer` (141). The legacy shapes are flat `{key, description}` tuple lists for keybars and "legacy screen title string or Chrome V2 model" handling in chrome wrappers. Both shapes are tested and exercised; bug-fixes have to be repeated against both branches.
- **App.ex residual size.** After Phase 42 extractions (`App.Routing`, `App.Modal`, `App.Effects`, `App.Subscriptions`), `lib/foglet_bbs/tui/app.ex` is 483 lines — the largest non-screen module in `lib/`. Two responsibilities still concentrate there: per-screen `screen_states` map plumbing, and the `set_user` / `promote_session` aliasing helpers.
- **Large screen modules.** Of the screens flagged by CONCERNS, **only `login.ex` (606 lines)** has the multi-mode tagged-union problem that TUI-05 targets — its reducer multiplexes `menu / login_form / reset_request / reset_consume` mode handlers and is also the source of the `:contract_supertype` dialyzer ignore entry. PostReader is at its natural size after Phase 43; main_menu, boards_view, modal/form, and cli_handler are intentionally out of scope for this phase.

### A note on the Posts API shape

PostReader is a *positioned reader*, not a paginated list — when a user enters a thread, they need to land at their read pointer (or jump to a specific post number), not at "page 1 of 50." Phase 44 already built `Foglet.Posts.list_reader_window/2` precisely for this: it returns posts windowed *around a position*, which supports both first-time entry (window around post #1) and jump-to-post (window around the target). `list_posts/1` is the legacy unbounded reader that survived Phase 44 only because `load_posts/2` was never migrated. The right replacement for `load_posts/2` is therefore `list_reader_window/2`, not a new "first page" function — pages would force consumers into offset-style thinking and break jump-to-post semantics. `Threads.list_threads/2` is different: thread lists are top-down scrolled, not jumped into, so a `LIMIT`-bounded list (with a future cursor option) is the correct shape there.

## Requirements

1. **Posts.list_posts/1 deleted**: The unbounded function is removed, not deprecated.
   - Current: `Foglet.Posts.list_posts/1` exists as public API; `PostReader.load_posts/2` and several test fixtures call it.
   - Target: `Foglet.Posts.list_posts/1` is removed from `lib/foglet_bbs/posts.ex`. No call sites remain in `lib/` or `test/`.
   - Acceptance: `grep -rn "\.list_posts\b" lib/ test/` returns zero hits. `mix compile --warnings-as-errors` succeeds.

2. **PostReader.load_posts/2 routed through `list_reader_window/2`**: The eager full-thread load is replaced with windowed loading anchored at the user's intended landing position.
   - Current: `Foglet.TUI.Screens.PostReader.load_posts/2` calls `posts_mod.list_posts/1` to load the entire thread, then seeds read positions and warms the render cache from that full list.
   - Target: `load_posts/2` calls `posts_mod.list_reader_window/2` anchored at the user's read pointer (or post position 1 when no pointer exists, or the requested target when a jump is in progress). The seed-read-position, render-cache warmup, and viewport warmup paths consume the windowed result. Jump-to-post entry paths continue to function correctly because the window primitive supports anchoring at any position.
   - Acceptance: A unit test seeds a thread with 200 posts and a read pointer at post 150, then asserts `PostReader.load_posts/2` causes `list_reader_window/2` to be called (verified via the existing fixture-mod indirection in `post_reader_test.exs`) and that the resulting screen state lands at the read pointer rather than at post 1. A second test seeds a thread with 5 posts and asserts entry still works correctly when the thread is smaller than the window. The render-purity guard test from Phase 44 continues to pass.

3. **Threads.list_threads/{1,2} bounded by default**: The unread-aware listing has an enforced page ceiling.
   - Current: `Foglet.Threads.list_threads/2` returns every thread in a board with no `LIMIT` clause; `ThreadList` consumes the full result.
   - Target: `Foglet.Threads.list_threads/2` accepts a `limit:` option, defaults to the module-level page-size constant (50), and applies `LIMIT` in the SQL. The arity-1 form `list_threads/1` is also bounded by the same default. Result ordering is preserved (most recent activity first). The option keyword list is reserved for future cursor work (`after:` / `before:` keys) but Phase 47 only uses default options at call sites.
   - Acceptance: A unit test seeds a board with 75 threads (mixed read/unread) and asserts `list_threads(board_id, user_id)` returns exactly 50 entries, ordered most-recent-activity-first. Inspecting the generated query via `Ecto.Adapters.SQL.to_sql/3` shows a `LIMIT 50` clause. `ThreadList` continues to render correctly without code changes beyond accepting the bounded result.

4. **Threads page-size constant centralised**: A named constant defines the threads page bound.
   - Current: No page-size constant exists in `Foglet.Threads`.
   - Target: A `@page_size 50` module attribute and a public `default_page_size/0` function live in `Foglet.Threads`. The bounded query references the constant rather than a hard-coded literal.
   - Acceptance: A test asserts `Foglet.Threads.default_page_size() == 50`. `grep -n "50" lib/foglet_bbs/threads.ex` shows the literal only in the constant declaration, not inside query bodies.

5. **Chrome V1 paths removed**: All four chrome widgets are V2-only.
   - Current: `KeyBar`, `ScreenFrame`, `StatusBar`, and `Normalizer` carry explicit V1 branches (flat `{key, description}` tuples, "legacy screen title string" handling).
   - Target: V1 branches are deleted from `KeyBar`, `ScreenFrame`, and `StatusBar`. `Foglet.TUI.Widgets.Chrome.Normalizer` is deleted entirely (its only purpose was the V1→V2 bridge). All screen call sites emit V2 grouped command bars.
   - Acceptance: `grep -rn "{[^,]\\+, *\"[^\"]\\+\"}" lib/foglet_bbs/tui/screens/` returns zero hits matching the legacy keybar tuple shape. `lib/foglet_bbs/tui/widgets/chrome/normalizer.ex` no longer exists. `mix test` passes with the V1 fixture tests deleted (not skipped).

6. **App.ScreenStates and App.SessionAlias extracted**: Two responsibilities leave `Foglet.TUI.App`.
   - Current: `Foglet.TUI.App` directly manipulates the `screen_states` map through inline `Map.get` / `Map.put` / `Map.update` helpers, and carries `set_user`, `promote_session`, and related aliasing helpers next to its Raxol runtime callbacks.
   - Target: A new `Foglet.TUI.App.ScreenStates` module (under 100 lines) owns get/put/update for `state.screen_states`. A new `Foglet.TUI.App.SessionAlias` module (under 80 lines) owns the user/session aliasing helpers. `Foglet.TUI.App` delegates to both. `Foglet.TUI.App` itself drops below 400 lines.
   - Acceptance: `lib/foglet_bbs/tui/app/screen_states.ex` and `lib/foglet_bbs/tui/app/session_alias.ex` both exist and each has its own focused unit test. `wc -l lib/foglet_bbs/tui/app.ex` reports under 400. `grep -n "screen_states" lib/foglet_bbs/tui/app.ex` shows only field references and delegating calls — no inline map manipulation.

7. **Login mode-machine refactor**: `Foglet.TUI.Screens.Login` is decomposed into per-mode reducer modules with a tagged-union state.
   - Current: `lib/foglet_bbs/tui/screens/login.ex` is 606 lines and multiplexes four modes (`menu / login_form / reset_request / reset_consume`) inside a single reducer. The screen is the source of the `:contract_supertype` `.dialyzer_ignore.exs` entry.
   - Target: Login is restructured along the Phase 43 PostReader pattern: a per-mode reducer module (e.g., `lib/foglet_bbs/tui/screens/login/menu.ex`, `login/login_form.ex`, `login/reset_request.ex`, `login/reset_consume.ex`), a sibling `login/state.ex` carrying the tagged-union state, and the top-level `login.ex` reduced to dispatch + render glue. `login.ex` itself drops below 300 lines. The `:contract_supertype` ignore entry for `login.ex` is removed if the refactor eliminates the underlying warning; otherwise it is documented in `.dialyzer_ignore.exs` with a refreshed inline rationale citing Phase 47.
   - Acceptance: The four per-mode reducer modules and `login/state.ex` exist. `wc -l lib/foglet_bbs/tui/screens/login.ex` reports under 300. Existing login screen tests pass without modification beyond import-path adjustments. `mix dialyzer` is green; if the `:contract_supertype` ignore entry remains, its rationale comment cites Phase 47.

## Boundaries

**In scope:**

- Deletion of `Foglet.Posts.list_posts/1`.
- Migration of `Foglet.TUI.Screens.PostReader.load_posts/2` to `Foglet.Posts.list_reader_window/2`, anchored at the read pointer or jump target.
- Bounded `Foglet.Threads.list_threads/{1,2}` with a default page size of 50.
- A centralised `default_page_size/0` constant in `Foglet.Threads`.
- Removal of all Chrome V1 code paths in `KeyBar`, `ScreenFrame`, `StatusBar`, and full deletion of `Normalizer`.
- Migration of any remaining V1 screen call sites to V2 grouped command bars.
- Extraction of `App.ScreenStates` and `App.SessionAlias` from `Foglet.TUI.App`, dropping App below 400 lines.
- Login mode-machine refactor (tagged-union state + per-mode reducer modules), dropping `login.ex` below 300 lines.

**Out of scope:**

- A new `Foglet.Posts.list_posts_page/2` (or any "first page" function) — `list_reader_window/2` is the correct primitive for PostReader, and adding a paginated variant would force offset-style thinking and break jump-to-post semantics.
- Cursor-based scrolling pagination in the `ThreadList` TUI — domain layer reserves the option shape but the TUI only renders the first page in this phase.
- Decomposition of `post_reader.ex`, `main_menu.ex`, `boards_view.ex`, `modal/form.ex`, or `cli_handler.ex` — CONCERNS documents these as either at natural size or addressed by previous phases.
- Removal of the two `.dialyzer_ignore.exs` "unnecessary skip" entries on the Account form modules — kept by Phase 46 D-06; revisit only when those forms are themselves refactored.
- New API surfaces beyond the bounded reader (e.g., admin-facing unbounded export) — if such a need emerges, it lands in a later phase with explicit scope.
- Changes to the Phoenix `FogletBbsWeb.*` layer — Phase 47 stays inside `Foglet.TUI.*`, `Foglet.Posts`, and `Foglet.Threads`.
- Cross-context refactors (e.g., touching `Foglet.Boards.Server` ordering or read-pointer schemas) — explicitly preserved.

## Constraints

- **No behavior change for end users.** PostReader entry must still land at the read pointer; jump-to-post must still work; boards and threads with ≤ 50 entries must render identically to the current implementation, including unread state.
- **Compatibility with existing tests.** Existing TUI screen tests, fixture-mod tests (`FakePosts`, `FakeThreads`), and posts/threads context tests must continue to pass after migration. Tests asserting V1 chrome shapes are deleted, not skipped. Test fixtures that implement `list_posts/1` are migrated to implement `list_reader_window/2` instead.
- **`mix precommit` must remain green.** All gates — compile-with-warnings-as-errors, formatter, Credo, Sobelow, Dialyzer — must pass at the end of the phase.
- **Page size is a constant, not configuration.** No `Foglet.Config` key is added for page size in this phase; the value is module-level and hard-coded at 50.
- **No SQL `OFFSET`-based pagination.** When the option shape is introduced for future cursor work, it must be cursor-shaped (e.g., `after:` / `before:` keys), not numeric offset, consistent with the Phase 44 `list_reader_window/2` shape.

## Acceptance Criteria

- [ ] `Foglet.Posts.list_posts/1` no longer exists; `grep -rn "\.list_posts\b" lib/ test/` returns zero hits
- [ ] `Foglet.TUI.Screens.PostReader.load_posts/2` calls `Foglet.Posts.list_reader_window/2` anchored at the read pointer or jump target (verified via fixture-mod indirection in `post_reader_test.exs`)
- [ ] PostReader entry on a 200-post thread with read pointer at post 150 lands at the read pointer (verified by unit test)
- [ ] PostReader entry on a 5-post thread (smaller than the window) still works correctly (verified by unit test)
- [ ] Phase 44 render-purity guard test for PostReader continues to pass
- [ ] `Foglet.Threads.list_threads/{1,2}` enforce `LIMIT 50` by default (verified by `Ecto.Adapters.SQL.to_sql/3` inspection)
- [ ] `Foglet.Threads.default_page_size/0` returns `50` (verified by unit test)
- [ ] `lib/foglet_bbs/tui/widgets/chrome/normalizer.ex` does not exist
- [ ] `KeyBar`, `ScreenFrame`, and `StatusBar` contain no V1 code paths (verified by code review against the legacy shapes documented in CONCERNS)
- [ ] All screen call sites under `lib/foglet_bbs/tui/screens/` emit V2 grouped command bars (verified by grep for the legacy tuple shape returning zero hits)
- [ ] `lib/foglet_bbs/tui/app/screen_states.ex` exists, is under 100 lines, and has a dedicated unit test
- [ ] `lib/foglet_bbs/tui/app/session_alias.ex` exists, is under 80 lines, and has a dedicated unit test
- [ ] `lib/foglet_bbs/tui/app.ex` is under 400 lines
- [ ] `lib/foglet_bbs/tui/screens/login.ex` is under 300 lines, with per-mode reducer modules under `lib/foglet_bbs/tui/screens/login/` and a `login/state.ex` carrying the tagged-union state
- [ ] All existing TUI screen tests pass; tests asserting V1 chrome shapes are deleted (not skipped); the full suite (currently 2,224 tests, 1 property) remains green
- [ ] `mix precommit` is clean: compile-with-warnings-as-errors, formatter, Credo, Sobelow, Dialyzer all pass
- [ ] `.planning/codebase/CONCERNS.md` is updated to reflect the resolved tech-debt entries

## Ambiguity Report

| Dimension          | Score | Min  | Status | Notes                                                                |
|--------------------|-------|------|--------|----------------------------------------------------------------------|
| Goal Clarity       | 0.92  | 0.75 | ✓      | Three workstreams precisely scoped against CONCERNS line numbers     |
| Boundary Clarity   | 0.88  | 0.70 | ✓      | New `list_posts_page` explicitly out; cursor scrolling explicitly out|
| Constraint Clarity | 0.78  | 0.65 | ✓      | Page size = 50 locked; cursor-not-offset locked; `mix precommit` bar |
| Acceptance Criteria| 0.82  | 0.70 | ✓      | 16 pass/fail checkboxes, all grep / size / test based                |
| **Ambiguity**      | 0.15  | ≤0.20| ✓      | Gate passed                                                          |

## Interview Log

| Round | Perspective    | Question summary                                              | Decision locked                                                                       |
|-------|----------------|---------------------------------------------------------------|---------------------------------------------------------------------------------------|
| 1     | Researcher     | What's the end-state for `Posts.list_posts/1`?                | Delete entirely; migrate `load_posts/2` to a bounded variant                          |
| 1     | Researcher     | Domain pagination shape for `Threads.list_threads/2`?         | Cursor-shaped option API in domain; first-page-only in TUI for now                    |
| 1     | Researcher     | Which large screen modules are in scope for TUI-05?           | Login only (CONCERNS-flagged), plus continued App.ex reduction                        |
| 2     | Simplifier     | Login refactor depth?                                         | Tagged-union state + per-mode reducer modules (Phase 43 PostReader pattern)           |
| 2     | Boundary Keeper| App.ex line target vs. responsibility extraction?             | Responsibility extraction (no line target gaming); pick concerns to move              |
| 2     | Boundary Keeper| Confirm out-of-scope screens, dialyzer ignores, scrolling?    | Confirmed; cursor scrolling deferred, other large screens deferred                    |
| 3     | Seed Closer    | Which App.ex concerns extract?                                | (i) `App.ScreenStates`, (ii) `App.SessionAlias`; skip initial-route hook              |
| 3     | Seed Closer    | Chrome V1 pass/fail bar; keep or drop `Normalizer`?           | Delete `Normalizer` entirely (V1→V2 bridge has no V2-only purpose)                    |
| 3     | Seed Closer    | Page size and Posts API shape?                                | Page size 50 (Threads only); Posts uses `list_reader_window/2` — no `list_posts_page` |
| 3     | Failure Analyst| Does paginated Posts API break jump-to-post / read-pointer?   | Yes — windowed (`list_reader_window/2`) is the correct primitive; pagination dropped  |

---

*Phase: 47-bound-unbounded-list-queries-drop-chrome-v1-shims-and-reduce*
*Spec created: 2026-04-30*
*Next step: /gsd-discuss-phase 47 — implementation decisions (window anchor selection, login state record, extraction order, etc.)*
