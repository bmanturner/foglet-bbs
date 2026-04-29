# Phase 39: App Shell Simplification - Context

**Gathered:** 2026-04-29 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Delete the central screen-specific machinery still living in `Foglet.TUI.App`
after the Phase 34-38 migrations: seven legacy screen-owned struct fields,
per-screen route-entry dispatch clauses, the `:main_menu`-specific initial
screen-state seeding, hardcoded `:main_menu, :load_oneliners` calls in
`{:set_user, …}` / `{:promote_session, …}`, screen-state decoder helpers
(`post_reader_state_thread_id/1`, `post_composer_state_thread_id/1`,
`thread_list_state_board_id/1`), `current_screen`-pattern-matched PubSub topic
derivation, and screen-name-gated PubSub broadcast routing
(`{:board_activity, …}`, `{:thread_activity, …}`). Add one new optional
callback `Screen.subscriptions/2` so `PostReader` and `ThreadList` declare
their own PubSub topic interest. Modal/SizeGate ownership and Raxol-callback
plumbing stay App-resident. No product-feature changes, no domain context
edits, no new Effect variants beyond what these mechanisms strictly require,
no browser surfaces.
</domain>

<spec_lock>
## Specification Lock

`.planning/phases/39-app-shell-simplification/39-SPEC.md` locks 10 requirements
and 12 acceptance checks. Downstream agents MUST read it before planning. Do
not duplicate or reinterpret the requirements from memory; use the SPEC as the
source of truth for what must be delivered and what remains out of scope.
</spec_lock>

<decisions>
## Implementation Decisions

### Route-entry Mechanism (R4)
- **D-01:** Route entry is a generic `:on_route_enter` atom message dispatched
  to the active screen's `update/3` from a single screen-name-agnostic
  `maybe_dispatch_route_entry/3` clause that calls `route_screen_update(state,
  screen_key(screen), :on_route_enter)` unconditionally.
- **D-02:** Do not introduce a new `Effect.route_entry()` variant. Reuse the
  existing `route_screen_update/3` machinery and the existing `Effect.navigate`
  → `init_route_screen_state` → `maybe_dispatch_route_entry` order at
  `app.ex:152-160`.
- **D-03:** Screens that need to load on entry (`MainMenu`, `Moderation`,
  `Sysop`, `ThreadList`, `PostReader`) implement `update(:on_route_enter,
  state, ctx)`. Screens that do not become a no-op via their existing
  `update/3` catch-all clause; `Screen.update/3` keeps its current
  `term()`-message contract (no behaviour change).
- **D-04:** Per-screen entry dispatch clauses for `:main_menu`,
  `:moderation`, `:sysop`, `:thread_list`, `:post_reader` at
  `app.ex:810-845` are deleted, not relocated, and replaced by the single
  generic clause from D-01.

### Subscriptions Callback (R6, R7)
- **D-05:** Declare `@callback subscriptions(local_state, Foglet.TUI.Context.t())
  :: [String.t()]` on `Foglet.TUI.Screen` and list it under
  `@optional_callbacks`. The 2-arity / `local_state` first / `Context.t()`
  second order matches existing `update/3` and `render/2` conventions.
- **D-06:** App invokes `subscriptions/2` from inside the rebuilt
  `build_pubsub_topics/1` on every `subscribe/1` call. Steps: start with
  global topics (e.g. `PubSub.user_topic/1` if `current_user`), look up the
  active screen module via `screen_module_for/2`, and if
  `function_exported?(module, :subscriptions, 2)` is true, union
  `module.subscriptions(current_screen_state(state), build_context(state))`
  into the topic list.
- **D-07:** No App-side topic-diffing or "current topics" state. Raxol's
  existing `Subscription.custom(PubSubForwarder, …)` rebuild semantics handle
  adds/removes; the cost stays equivalent to today's path.
- **D-08:** Only `Foglet.TUI.Screens.PostReader` and
  `Foglet.TUI.Screens.ThreadList` implement `subscriptions/2` in this phase.
  Stateless screens (`Login`, `Register`, `Verify`, `MainMenu`, `Account`,
  `Moderation`, `Sysop`, `BoardList`, `NewThread`, `PostComposer`) do not.
- **D-09:** Each implementing screen sources its id (`thread_id`,
  `board_id`) from local state first and falls back to
  `Context.route_params` when local state has not been hydrated yet —
  matching today's precedence in `routed_thread_topic/1` /
  `thread_list_board_topic/1`. Empty-id cases return `[]`.

### Breadcrumb Input (R3)
- **D-10:** Affected screens (`ThreadList`, `PostReader`, `PostComposer`,
  `NewThread`) supply breadcrumb labels by setting `breadcrumb_parts:
  [String.t()]` on the chrome map they pass into `ScreenFrame`. The shape is
  the same parts-list `BreadcrumbBar.format/2` already consumes; no new
  struct.
- **D-11:** Delete `BreadcrumbBar.parts_for/1` and the per-screen pattern
  matches at `breadcrumb_bar.ex:62-92`, plus the `:current_board` /
  `:current_thread`-reading helpers (`board_name/1`, `thread_title/1`).
  Reusable formatting (`format/2`, truncation, render of the parts list)
  stays.
- **D-12:** Each affected screen derives breadcrumb labels from its own
  state struct (`ThreadList.State.board.name`, `PostReader.State.thread.title`,
  `NewThread.State.board`, `PostComposer.State.thread` / `.board`) inside its
  `render/2`.

### App PubSub Broadcast Routing (R8)
- **D-13:** `do_update({:board_activity, …}, state)` and
  `do_update({:thread_activity, …}, state)` lose their
  `current_screen ==` gates and forward through the same generic
  active-screen update mechanism used elsewhere. `BoardList` and
  `PostReader` handle them in their `update/3`; other screens are no-ops
  via their catch-all clauses.

### MainMenu First-load (R4 implication)
- **D-14:** MainMenu's first-load is owned by `MainMenu.update(:on_route_enter,
  state, ctx)`, which emits the existing `load_oneliners_task_effect/1`
  (`main_menu.ex:530`). The hardcoded `route_screen_update(state, :main_menu,
  :load_oneliners)` calls inside `do_update({:set_user, …})` and
  `do_update({:promote_session, …})` (`app.ex:552-563, 699-714`) are
  replaced by routing through `Effect.navigate(:main_menu, %{})` so
  first-entry uses the same generic path as any other navigation.
- **D-15:** Delete the `:main_menu`-specific clause in
  `maybe_init_initial_screen_state/1` (`app.ex:884-893`). The generic
  `init_route_screen_state/3` (`app.ex:777-794`) already handles MainMenu
  via `function_exported?/3` and does not need a special case.

### Test and Fixture Migration
- **D-16:** Existing PubSub regression tests at `app_test.exs:1483-1607`
  are kept verbatim for the cases that survive (authenticated MainMenu,
  BoardList route, ThreadList from route_params, ThreadList from local
  state, PostReader from route_params, PostReader from local state). The
  test-seam shape (`Enum.find(&match?(%Subscription{type: :custom}, &1))`
  → `:topics`) is unchanged.
- **D-17:** Delete (do not migrate) the two "ignores `current_board` /
  `current_thread`" pin-tests at `app_test.exs:1531-1551` and `:1587-1607`.
  They construct deleted struct fields directly and are pre-cleanup
  artifacts.
- **D-18:** Add one new pin-test: authenticated `:main_menu` produces only
  `["user:<id>"]`, proving stateless screens correctly omit the optional
  callback.
- **D-19:** Add an App struct-shape regression test (e.g. `Map.keys(%App{})`
  equals exactly `[:current_screen, :current_user, :session_context,
  :session_pid, :terminal_size, :route_params, :modal, :screen_state]`,
  order-independent) — satisfies the SPEC R1 acceptance check.
- **D-20:** `lib/foglet_bbs/tui/render_fixtures.ex` is migrated by deleting
  the legacy field assignments in `base_state/2` (`render_fixtures.ex:84-100`
  block setting `current_board: nil, current_thread: nil,
  current_thread_list: nil, posts: [], read_position: 0, composer_draft: nil,
  board_list: …`). Every `populate/3` clause already constructs
  `screen_state: %{...}` correctly (clauses at `render_fixtures.ex:156, 174,
  188-192, 203-211, 233-236, 257-260, 269-276`); none need rewriting.

### Claude's Discretion
- Exact atom name for the route-entry message (currently `:on_route_enter`)
  is flexible if all migrated screens use one consistent name and App's
  generic dispatcher does not pattern-match on a specific screen atom.
- Exact ordering of edits across requirements (delete struct fields first
  vs. add `subscriptions/2` first) is up to the planner; both must be
  green before a commit lands per `mix precommit`.
- Whether `MainMenu.update(:on_route_enter, …)` delegates to the existing
  `update(:load_oneliners, …)` clause, replaces it, or both — pick whichever
  produces the smaller diff while keeping the existing task contract.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Locked Phase Scope
- `.planning/phases/39-app-shell-simplification/39-SPEC.md` — Phase 39
  requirements, boundaries, constraints, and 12-check acceptance list.
- `.planning/ROADMAP.md` — v2.0 phase sequencing; Phase 39 goal and
  dependency notes.
- `.planning/REQUIREMENTS.md` — STATE-02..04 and APP-01..04 requirement IDs
  Phase 39 closes.
- `.planning/PROJECT.md` — SSH-first product boundary and v2.0 milestone
  intent.
- `.planning/phases/34-runtime-contract-effects/34-CONTEXT.md` — Phase 34
  decisions that constrain Phase 39 (no compatibility layer per D-04, task
  result tagging per D-13, screen-state struct conventions per D-17/D-18).

### TUI And Raxol Runtime
- `docs/ARCHITECTURE.md` — TUI/Raxol layer, SSH-first architecture, and
  session/domain ownership notes.
- `docs/raxol/getting-started/WIDGET_GALLERY.md` — Raxol layout, command,
  and component vocabulary.
- `lib/foglet_bbs/tui/widgets/README.md` — local widget conventions.

### Source Files Touched
- `lib/foglet_bbs/tui/app.ex` (struct 50-86; route-entry 810-845; PubSub
  417-526; main-menu special case 884-893; first-load hooks 552-563,
  699-714; PubSub broadcast clauses 648-661; modal/SizeGate 347-363,
  982-1046)
- `lib/foglet_bbs/tui/screen.ex` (behaviour declarations,
  `@optional_callbacks` list)
- `lib/foglet_bbs/tui/effect.ex` (no new variants — confirm)
- `lib/foglet_bbs/tui/context.ex` (consumed by `subscriptions/2`)
- `lib/foglet_bbs/tui/screens/main_menu.ex` (line 138 `:load_oneliners`,
  line 530 task effect)
- `lib/foglet_bbs/tui/screens/thread_list.ex` (line 28
  `State.from_context`, line 339 frame_state breadcrumb shim)
- `lib/foglet_bbs/tui/screens/post_reader.ex` (line 71, lines 890-903)
- `lib/foglet_bbs/tui/screens/post_composer.ex` (lines 400, 497)
- `lib/foglet_bbs/tui/screens/new_thread.ex` (line 705)
- `lib/foglet_bbs/tui/screens/board_list.ex` (consumes `:board_activity`)
- `lib/foglet_bbs/tui/screens/moderation.ex`,
  `lib/foglet_bbs/tui/screens/sysop.ex` (route-entry consumers)
- `lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex` (lines 50-51 parts
  seam, 62-92 per-screen branches to delete, 108-134 legacy field readers)
- `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex` (lines 185-196
  `normalize_chrome` already accepts `:breadcrumb_parts`)
- `lib/foglet_bbs/tui/render_fixtures.ex` (lines 84-100 legacy-field shim
  to delete)
- `lib/foglet_bbs/pub_sub.ex` (`user_topic/1`, `board_topic/1`,
  `thread_topic/1`)

### Tests Touched
- `test/foglet_bbs/tui/app_test.exs:1483-1607` — preserve subscription pin
  tests for surviving cases.
- `test/foglet_bbs/tui/app_test.exs:1531-1551, 1587-1607` — DELETE these
  pin tests (construct fields that will not exist).
- New tests: App struct-shape pin (D-19), MainMenu-only-user-topic pin
  (D-18), `Screen.behaviour_info(:optional_callbacks)` pin,
  `function_exported?/3` pins for PostReader/ThreadList `subscriptions/2`.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Foglet.TUI.Effect` and `apply_effect/2` already implement the eight
  generic mechanisms (navigate, task, modal, publish, session, terminal,
  quit, plus dispatch chains). No new variant required.
- `route_screen_update/3` (`app.ex:851-865`) already builds the
  `Context.t()` from `route_params` and routes a message into the active
  screen's `update/3`. Generic route-entry dispatch reuses it directly.
- `current_screen_state/1` (`app.ex:110-112`), `screen_module_for/2`, and
  `build_context/1` (`app.ex:128-144`) are already public — `subscriptions/2`
  plumbing needs no new App accessors.
- `BreadcrumbBar.format/2` and `BreadcrumbBar.render/3` (`breadcrumb_bar.ex:50-51`)
  already accept an explicit `[String.t()]` parts list;
  `ScreenFrame.normalize_chrome/2` (`screen_frame.ex:185-196`) already
  accepts `:breadcrumb_parts` on the chrome map and only falls back to
  `parts_for/1` if absent. Each affected screen already has the labels in
  its local state.
- Existing PubSub regression tests at `app_test.exs:1483-1607` use a
  durable subscription-shape seam (`Subscription{type: :custom}` →
  `:topics`) that survives the rewrite verbatim.
- `MainMenu.update(:load_oneliners, …)` (`main_menu.ex:138-141`) and
  `load_oneliners_task_effect/1` (`main_menu.ex:530-536`) already exist —
  `:on_route_enter` delegates rather than reimplements.

### Established Patterns
- `function_exported?/3`-gated optional callbacks are already the App
  idiom (`app.ex:854, 870, 964` for existing optional callbacks). Use the
  same gate for `subscriptions/2`.
- Phase 34 D-04 forbids any "old vs new screen" fallback / compatibility
  layer — a single generic call site is required, not a relocate-then-hide
  refactor.
- Phase 34 D-17/D-18 distinguishes stateful screens (first-class state
  struct) from stateless (`:stateless` / `%{}`); the `subscriptions/2`
  optional-callback split (PostReader/ThreadList vs the other ten)
  follows the same boundary.
- AGENTS.md prohibits text-presence/absence assertions. Subscription-shape
  pins, struct-shape pins, callback-export pins, and effect-emission pins
  are explicitly fine.
- Effect-task results are tagged with `screen_key` per Phase 34 D-13;
  no new tagging required for this phase.

### Integration Points
- `Foglet.TUI.App.subscribe/1` is called by Raxol on each model change;
  the new `build_pubsub_topics/1` runs there.
- `Effect.navigate/2` triggers `init_route_screen_state` then
  `maybe_dispatch_route_entry` in order (`app.ex:152-160`); the generic
  `:on_route_enter` dispatch piggybacks on this existing chain.
- `ScreenFrame.render/4` is the single entry point through which screens
  push breadcrumb parts into chrome; no Raxol-side change required.
- `mix foglet.tui.render` (the headless render harness) drives the same
  `Raxol.UI.Layout.Engine` as the live TUI; surviving render-fixture
  paths exercise the migrated chrome path automatically.
</code_context>

<specifics>
## Specific Ideas

- The route-entry message atom is `:on_route_enter` (D-01). Rename only if
  the planner identifies a clearer convention used elsewhere in the
  codebase; the SPEC does not constrain the literal name.
- Breadcrumb input is `breadcrumb_parts: [String.t()]` on the existing
  chrome map (D-10) — not a new struct, not a keyword arg pair.
- Stateless screens (10 of 12 production screens) MUST NOT implement
  `subscriptions/2` (D-08). This is a hard correctness signal: it proves
  the optional-callback contract works as designed.
</specifics>

<deferred>
## Deferred Ideas

- Removing the transitional `render/1`, `handle_key/2`,
  `init_screen_state/1` callbacks from `Foglet.TUI.Screen` — already
  optional, final cleanup is Phase 40.
- Verification, milestone-close, documentation refresh, and ROADMAP/
  REQUIREMENTS state moves — Phase 40.
- A typed `BreadcrumbModel` / `Breadcrumb.t()` struct shared across
  screens — out of scope for this phase, would be a separate refactor if
  ever needed.
- Per-screen processes / live screen sub-supervision — explicitly out of
  scope per Phase 34 D-08.
- App-side topic diffing or "subscription delta" optimization — only worth
  designing if profiling shows a problem; current path rebuilds every tick
  and there is no reported issue.

### Reviewed Todos (not folded)
None — no pending todos matched Phase 39 scope.
</deferred>
