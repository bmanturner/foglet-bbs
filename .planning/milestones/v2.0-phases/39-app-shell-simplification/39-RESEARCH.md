# Phase 39: App Shell Simplification - Research

**Researched:** 2026-04-28
**Domain:** Elixir / Raxol TUI runtime — central App-shell refactor
**Confidence:** HIGH (codebase-grounded; every claim verified by direct file read or grep)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Route-entry Mechanism (R4)**
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
- **D-04:** Per-screen entry dispatch clauses for `:main_menu`, `:moderation`,
  `:sysop`, `:thread_list`, `:post_reader` at `app.ex:810-845` are deleted, not
  relocated, and replaced by the single generic clause from D-01.

**Subscriptions Callback (R6, R7)**
- **D-05:** Declare `@callback subscriptions(local_state, Foglet.TUI.Context.t())
  :: [String.t()]` on `Foglet.TUI.Screen` and list it under
  `@optional_callbacks`. The 2-arity / `local_state` first / `Context.t()`
  second order matches existing `update/3` and `render/2` conventions.
- **D-06:** App invokes `subscriptions/2` from inside the rebuilt
  `build_pubsub_topics/1` on every `subscribe/1` call. Steps: start with global
  topics (e.g. `PubSub.user_topic/1` if `current_user`), look up the active
  screen module via `screen_module_for/2`, and if
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
- **D-09:** Each implementing screen sources its id (`thread_id`, `board_id`)
  from local state first and falls back to `Context.route_params` when local
  state has not been hydrated yet — matching today's precedence in
  `routed_thread_topic/1` / `thread_list_board_topic/1`. Empty-id cases return
  `[]`.

**Breadcrumb Input (R3)**
- **D-10:** Affected screens (`ThreadList`, `PostReader`, `PostComposer`,
  `NewThread`) supply breadcrumb labels by setting
  `breadcrumb_parts: [String.t()]` on the chrome map they pass into
  `ScreenFrame`. The shape is the same parts-list `BreadcrumbBar.format/2`
  already consumes; no new struct.
- **D-11:** Delete `BreadcrumbBar.parts_for/1` and the per-screen pattern
  matches at `breadcrumb_bar.ex:62-92`, plus the `:current_board` /
  `:current_thread`-reading helpers (`board_name/1`, `thread_title/1`).
  Reusable formatting (`format/2`, truncation, render of the parts list)
  stays.
- **D-12:** Each affected screen derives breadcrumb labels from its own state
  struct (`ThreadList.State.board.name`, `PostReader.State.thread.title`,
  `NewThread.State.board`, `PostComposer.State.thread` / `.board`) inside its
  `render/2`.

**App PubSub Broadcast Routing (R8)**
- **D-13:** `do_update({:board_activity, …}, state)` and
  `do_update({:thread_activity, …}, state)` lose their `current_screen ==`
  gates and forward through the same generic active-screen update mechanism
  used elsewhere. `BoardList` and `PostReader` handle them in their
  `update/3`; other screens are no-ops via their catch-all clauses.

**MainMenu First-load (R4 implication)**
- **D-14:** MainMenu's first-load is owned by
  `MainMenu.update(:on_route_enter, state, ctx)`, which emits the existing
  `load_oneliners_task_effect/1` (`main_menu.ex:530`). The hardcoded
  `route_screen_update(state, :main_menu, :load_oneliners)` calls inside
  `do_update({:set_user, …})` and `do_update({:promote_session, …})`
  (`app.ex:552-563, 699-714`) are replaced by routing through
  `Effect.navigate(:main_menu, %{})` so first-entry uses the same generic path
  as any other navigation.
- **D-15:** Delete the `:main_menu`-specific clause in
  `maybe_init_initial_screen_state/1` (`app.ex:884-893`). The generic
  `init_route_screen_state/3` (`app.ex:777-794`) already handles MainMenu via
  `function_exported?/3` and does not need a special case.

**Test and Fixture Migration**
- **D-16:** Existing PubSub regression tests at `app_test.exs:1483-1607` are
  kept verbatim for the cases that survive (authenticated MainMenu,
  BoardList route, ThreadList from route_params, ThreadList from local state,
  PostReader from route_params, PostReader from local state). The test-seam
  shape (`Enum.find(&match?(%Subscription{type: :custom}, &1))` → `:topics`)
  is unchanged.
- **D-17:** Delete (do not migrate) the two "ignores `current_board` /
  `current_thread`" pin-tests at `app_test.exs:1531-1551` and `:1587-1607`.
  They construct deleted struct fields directly and are pre-cleanup
  artifacts.
- **D-18:** Add one new pin-test: authenticated `:main_menu` produces only
  `["user:<id>"]`, proving stateless screens correctly omit the optional
  callback.
- **D-19:** Add an App struct-shape regression test
  (`Map.keys(%App{})` equals exactly `[:current_screen, :current_user,
  :session_context, :session_pid, :terminal_size, :route_params, :modal,
  :screen_state]`, order-independent) — satisfies the SPEC R1 acceptance check.
- **D-20:** `lib/foglet_bbs/tui/render_fixtures.ex` is migrated by deleting the
  legacy field assignments in `base_state/2` (`render_fixtures.ex:84-100`
  block setting `current_board: nil, current_thread: nil,
  current_thread_list: nil, posts: [], read_position: 0,
  composer_draft: nil, board_list: …`). Every `populate/3` clause already
  constructs `screen_state: %{...}` correctly (clauses at
  `render_fixtures.ex:156, 174, 188-192, 203-211, 233-236, 257-260, 269-276`);
  none need rewriting.

### Claude's Discretion

- Exact atom name for the route-entry message (currently `:on_route_enter`)
  is flexible if all migrated screens use one consistent name and App's
  generic dispatcher does not pattern-match on a specific screen atom.
- Exact ordering of edits across requirements (delete struct fields first
  vs. add `subscriptions/2` first) is up to the planner; both must be green
  before a commit lands per `mix precommit`.
- Whether `MainMenu.update(:on_route_enter, …)` delegates to the existing
  `update(:load_oneliners, …)` clause, replaces it, or both — pick whichever
  produces the smaller diff while keeping the existing task contract.

### Deferred Ideas (OUT OF SCOPE)

- Removing the transitional `render/1`, `handle_key/2`, `init_screen_state/1`
  callbacks from `Foglet.TUI.Screen` — already optional, final cleanup is
  Phase 40.
- Verification, milestone-close, documentation refresh, and ROADMAP /
  REQUIREMENTS state moves — Phase 40.
- A typed `BreadcrumbModel` / `Breadcrumb.t()` struct shared across screens —
  out of scope for this phase, would be a separate refactor if ever needed.
- Per-screen processes / live screen sub-supervision — explicitly out of
  scope per Phase 34 D-08.
- App-side topic diffing or "subscription delta" optimization — only worth
  designing if profiling shows a problem; current path rebuilds every tick
  and there is no reported issue.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| STATE-02 | Board lists, thread lists, posts, composer drafts, oneliner rows, tab lifecycle slots, and form feedback live in owning screen state, not screen-specific App fields. | Confirmed via grep: every screen except the legacy `handle_key/render` paths in PostReader/PostComposer (which are dead code per `new_contract_screen?` returning true for all 12 screens) already owns its data in `screen_state[:screen]`. Phase 39 deletes the now-redundant App fields. |
| STATE-03 | Screen-local helper modules no longer read or write `state.screen_state[:screen]` through the App struct after migration. | `BreadcrumbBar.board_name/1` and `thread_title/1` (lines 108–134) currently violate this. D-11/D-12 migrate them to explicit `:breadcrumb_parts` input from the screen. |
| STATE-04 | App stores screen states by route/screen key and does not manipulate individual screen struct fields after migration. | `post_reader_state_thread_id/1` (483–488), `post_composer_state_thread_id/1` (490–501), and `thread_list_state_board_id/1` (521–526) are App-side decoders. D-06/SPEC R5 deletes all three; the new `subscriptions/2` callback owns its own state decoding. |
| APP-01 | App owns only runtime shell responsibilities (Raxol callbacks, normalization, SizeGate/modal, route, screen state storage, context construction, effect interpretation, subscriptions, session hooks, rendering dispatch). | Removing the seven legacy fields, three decoder helpers, five route-entry clauses, two PubSub-broadcast `current_screen ==` gates, the `:main_menu`-special-case at 884–893, and the hardcoded `:main_menu, :load_oneliners` calls at 552–563 / 699–714 leaves precisely the shell responsibilities. |
| APP-02 | App no longer has screen-specific loaded-result clauses for migrated screens. | Already largely satisfied by Phases 35–38; remaining hold-outs are the broadcast gates (D-13) and the MainMenu first-load hardcoding (D-14). |
| APP-03 | PubSub subscriptions derive from route/context or screen-declared interests without screen-specific App state mutation. | New optional callback `Screen.subscriptions/2` (D-05) + App-side dispatch on `function_exported?/3` (D-06). PostReader and ThreadList implement it (D-08). |
| APP-04 | Modal handling remains App-level for overlay precedence; screen-owned modal requests flow through generic effects. | Already satisfied — modal/SizeGate plumbing (`render_modal_overlay/2`, `global_key_handler/2`, `handle_modal_key/3` at app.ex:347–363, 982–1046) is intentionally preserved per SPEC R9. No change required. |
</phase_requirements>

## Summary

Phase 39 is a pure refactor that completes the v2.0 milestone's App-screen
boundary cleanup. The work is bounded and well-understood: every screen has
already been migrated to the `init/1` + `update/3` + `render/2` reducer
contract in Phases 34–38, but `Foglet.TUI.App` still carries seven legacy
struct fields, three screen-state decoder helpers, five per-screen
route-entry dispatch clauses, two `current_screen ==` gates on PubSub
broadcasts, two hardcoded `:main_menu, :load_oneliners` first-load calls,
and a `:main_menu`-special-case in initial state seeding. All of those are
deleted (not relocated) in this phase. A new optional `Screen.subscriptions/2`
callback replaces App's screen-pattern-matched PubSub topic derivation;
only `PostReader` and `ThreadList` implement it.

**Primary recommendation:** Execute the cleanup in two waves. Wave 1 lands
the new mechanisms (Screen.subscriptions/2, generic route-entry, generic
broadcast routing, breadcrumb_parts seam) so the deletion in Wave 2 is a
straightforward removal. The single highest-risk landmine is **dead-but-
present legacy code in PostReader/PostComposer** that reads
`state.posts`/`state.read_position`/`state.current_thread` via `state.<field>`
on the App struct (post_reader.ex lines 251, 347, 359, 373, 410, 426, 504-513,
635, 651, 673-689, 723-724, 729; post_composer.ex lines 400, 420, 544);
deleting the App struct fields without first deleting these dead paths will
fail `compile --warnings-as-errors`.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Raxol app/init/update/view callbacks | App (`lib/foglet_bbs/tui/app.ex`) | — | App `use Raxol.Core.Runtime.Application` and is the sole `@impl`-bound module. |
| Message normalization (events → tuples) | App | — | `normalize_message/1` (app.ex:333–345) is runtime plumbing, not screen logic. |
| Route storage (current screen + params) | App | — | `current_screen` and `route_params` fields plus `current_route/1`/`screen_key/1` accessors. Screens read via `Context.route` / `Context.route_params`. |
| Screen-local state storage by key | App | Screen state struct | App stores `screen_state: map()` keyed by atom; screens own struct shape. |
| Context construction (`Foglet.TUI.Context`) | App | Domain modules | `build_context/1,2` (app.ex:127–144) reads App struct + session_context.domain. |
| Effect interpretation (`apply_effect/2`) | App | — | Single point of effect → Raxol command translation, including task → `Foglet.TUI.Command.task/2`. |
| Modal precedence + dismiss/confirm/form | App | Modal effects from screens | `render_modal_overlay`, `global_key_handler`, `handle_modal_key` (347–363, 982–1046). Screens emit `Effect.modal/Effect.open_modal/Effect.dismiss_modal`. |
| SizeGate render-time short-circuit | App | — | `view/1` cond at line 349. State preserved across resizes. |
| Session hooks (heartbeat, replace, promote) | App | `Foglet.Sessions.Session` | App handles `:heartbeat_tick`, `:session_replaced`, `:promote_session`. |
| PubSub plumbing (forwarder + topics) | App + `PubSubForwarder` | Screen `subscriptions/2` (NEW) | App owns user/global topics + dispatch to Raxol; screens declare per-screen topic interest via callback. |
| Rendering dispatch | App | Screen `render/2` | `render_screen/1` (app.ex:960–970) calls `module.render(local_state, context)`. |
| Per-screen first-load dispatch | App generic clause | Screen `update(:on_route_enter, …)` | Single screen-name-agnostic clause replaces 5 per-screen clauses. |
| Per-screen PubSub broadcast routing | App generic dispatch | Screen `update/3` | `{:board_activity,…}` and `{:thread_activity,…}` route through `route_screen_update/3` to active screen. |
| Breadcrumb labels | Screen `render/2` (via chrome map) | `BreadcrumbBar.format/2` (stateless) | Each screen builds `breadcrumb_parts: [...]` from its own state. BreadcrumbBar formats; no state-decode. |

## Standard Stack

This is an in-codebase refactor; no new external dependencies are introduced.
Existing libraries are already pinned:

### Core (already in use; no version changes required)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Raxol (vendored) | `vendor/raxol` (local) | TUI runtime, Subscription, Command, View | Foglet's chosen TUI framework; lifecycle and dispatcher contract documented locally. [VERIFIED: vendor/raxol/lib/raxol/core/runtime/events/dispatcher.ex] |
| Phoenix.PubSub | from Phoenix umbrella | Multi-process pub/sub | Foglet uses it for board/thread/user activity broadcast. [VERIFIED: lib/foglet_bbs/tui/pub_sub_forwarder.ex:55] |
| Bodyguard | (existing) | Authorization policies | Out of scope for Phase 39 — domain authorization unchanged. [CITED: AGENTS.md] |
| ExUnit | (stdlib) | Testing framework | All Foglet tests under `test/foglet_bbs/...` use it. |

### Tooling (`mix precommit` chain)
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Credo | (existing dev dep) | Style/linting | `mix credo --strict`. [VERIFIED: mix.exs:95] |
| Sobelow | (existing dev dep) | Security static analysis | `mix sobelow --exit Low`. [VERIFIED: mix.exs:96] |
| Dialyzer | (existing dev dep) | Type checking | `mix dialyzer`. [VERIFIED: mix.exs:97] |

**Installation:** None. `mix precommit` already aliased at `mix.exs:91-98`.

**Version verification:** Not applicable — Phase 39 introduces no new package
dependencies.

## Architecture Patterns

### System Architecture Diagram

```
                    ┌──────────────────────────────────┐
   SSH Channel ───▶ │  Foglet.SSH.CLIHandler           │
                    │  (peer/auth, lifecycle wrapper)  │
                    └────────────────┬─────────────────┘
                                     │ start_link
                                     ▼
                    ┌──────────────────────────────────┐
                    │  Raxol.Core.Runtime.Lifecycle    │
                    │  + Dispatcher                    │
                    │  • setup_subscriptions (1×)      │
                    │  • event loop                    │
                    └────────────────┬─────────────────┘
                                     │ init/1, update/2, view/1, subscribe/1
                                     ▼
                    ┌──────────────────────────────────┐
                    │  Foglet.TUI.App  (RUNTIME SHELL) │
                    │                                  │
                    │  ┌────────────────────────────┐  │
                    │  │ normalize_message/1        │  │  ← Raxol Event
                    │  └─────────────┬──────────────┘  │
                    │                ▼                 │
                    │  ┌────────────────────────────┐  │
                    │  │ do_update/2 (dispatch)     │  │
                    │  │  • effect interpreter      │  │
                    │  │  • modal handler           │  │
                    │  │  • SizeGate guard          │  │
                    │  └─────┬────────┬─────┬───────┘  │
                    │        │        │     │          │
                    │        │        │     ▼          │
                    │        │        │  ┌──────────┐  │
                    │        │        │  │ Effect   │  │
                    │        │        │  │ apply_*  │  │── task ──▶ Foglet.TUI.Command.task/2
                    │        │        │  └────┬─────┘  │── publish ▶ Phoenix.PubSub.broadcast
                    │        │        │       │        │── session ▶ Foglet.Sessions.Session
                    │        │        │       │        │── navigate ▶ init_route_screen_state
                    │        │        │       │        │             + maybe_dispatch_route_entry
                    │        │        ▼       ▼        │
                    │        │  ┌────────────────────┐ │
                    │        │  │ route_screen_update│ │── module.update(msg, local, ctx)
                    │        │  └────────────────────┘ │
                    │        ▼                         │
                    │  ┌────────────────────────────┐  │
                    │  │ render_screen/1            │  │── module.render(local_state, ctx)
                    │  └────────────────────────────┘  │
                    │                                  │
                    │  build_pubsub_topics/1 ─────────▶│── union user_topic, board/thread/boards
                    │  (called from subscribe/1)       │   topics from screen.subscriptions/2
                    └──────────────────────────────────┘
                                     │
              PubSubForwarder ◀──────┘ (Subscription.custom)
              ──── {:subscription, msg} ────▶ Dispatcher → update/2
```

**Key data-flow contracts (verified):**

1. **Init path:** `Lifecycle → Dispatcher.init → setup_subscriptions(state)` —
   called **once at startup**. (`vendor/raxol/.../events/dispatcher.ex:92`).
   `App.subscribe(model)` is invoked once per Dispatcher init; the returned
   list of subscriptions is started by `Subscription.start/2`.
2. **Update path:** Each runtime message lands in `App.update/2`, normalized
   into `do_update/2`, which dispatches by tuple shape.
3. **Effect path:** Screens return `[%Effect{}, ...]` from `update/3`. App's
   `apply_effects/2` folds them, producing `(state, [Command.t()])`.
4. **Navigate path:** `Effect.navigate(screen, params)` → `apply_effect/2` →
   `init_route_screen_state` → `maybe_dispatch_route_entry` (line 152–160).
   Phase 39 makes the second step generic (D-01).

### Recommended Project Structure (no change required)

```
lib/foglet_bbs/tui/
├── app.ex                      # ↓ shrinks (delete fields, decoders, dispatch clauses)
├── screen.ex                   # ↑ adds @callback subscriptions/2 + @optional_callbacks entry
├── effect.ex                   # unchanged (D-02)
├── context.ex                  # unchanged
├── render_fixtures.ex          # ↓ delete legacy-field shim at base_state/2
├── pub_sub_forwarder.ex        # unchanged
├── widgets/chrome/
│   ├── breadcrumb_bar.ex       # ↓ delete parts_for/1 + per-screen branches + state decoders
│   └── screen_frame.ex         # unchanged (already supports :breadcrumb_parts)
└── screens/
    ├── main_menu.ex            # +update(:on_route_enter, …)
    ├── moderation.ex           # +update(:on_route_enter, …)
    ├── sysop.ex                # +update(:on_route_enter, …)
    ├── thread_list.ex          # +update(:on_route_enter, …); +subscriptions/2; chrome map carries :breadcrumb_parts
    ├── post_reader.ex          # +update(:on_route_enter, …); +subscriptions/2; chrome map carries :breadcrumb_parts; legacy paths trimmed
    ├── post_composer.ex        # chrome map carries :breadcrumb_parts; legacy paths trimmed
    └── new_thread.ex           # chrome map carries :breadcrumb_parts
```

### Pattern 1: Optional callback gate via `function_exported?/3`

**What:** App invokes an optional Screen callback only when the module
exports it.

**When to use:** Adding a new optional Screen behaviour callback that not
every screen implements.

**Example (already established for `init/3`, `update/3`, `render/2`):**

```elixir
# Source: lib/foglet_bbs/tui/app.ex:854 (route_screen_update/3)
if Code.ensure_loaded?(module) and function_exported?(module, :update, 3) do
  local_state = screen_state_for(state, key)
  context = context_for_screen_key(state, key)
  {new_local_state, effects} = module.update(message, local_state, context)
  …
end

# Source: lib/foglet_bbs/tui/app.ex:870 (new_contract_screen?/2)
defp new_contract_screen?(%__MODULE__{} = state, screen) do
  module = screen_module_for(state, screen_key(screen))
  Code.ensure_loaded?(module) and function_exported?(module, :update, 3)
end

# Source: lib/foglet_bbs/tui/app.ex:964 (render_screen/1)
if Code.ensure_loaded?(module) and function_exported?(module, :render, 2) do
  context = context_for_screen_key(state, key)
  module.render(render_local_state(state, key, module, context), context)
…
```

Phase 39's `subscriptions/2` dispatch follows this exact pattern. Mirror the
`Code.ensure_loaded?/1 and function_exported?/3` paired guard — both are
required because in test/dev the module may not yet be loaded when subscribe
runs.

### Pattern 2: Stateful-screen state struct with `from_context/1`

**What:** Stateful screens own a `State` struct module with a constructor
that reads route_params from `Context`.

**Example:**

```elixir
# Source: lib/foglet_bbs/tui/screens/thread_list.ex:28
def init(%Context{} = context), do: State.from_context(context)

# Source: lib/foglet_bbs/tui/screens/post_reader.ex:71
def init(%Context{} = context), do: State.from_context(context)
```

`subscriptions/2` mirrors the same fall-back precedence: `local_state.thread_id
|| Context.route_params[:thread_id]`. Empty/missing → `[]`.

### Pattern 3: Chrome map flowing into ScreenFrame

**What:** Screens build a chrome map and pass it as the second arg to
`ScreenFrame.render/4`. `ScreenFrame.normalize_chrome/2` (185–196) reads
`:breadcrumb_parts` and `:status_atoms` from the chrome map; if absent it
falls back to legacy `BreadcrumbBar.parts_for/1` (which is what gets
deleted).

**Current call site (all four affected screens pass empty map `%{}` today):**

```elixir
# Source: lib/foglet_bbs/tui/screens/thread_list.ex:126
ScreenFrame.render(frame_state, %{}, thread_content, [...])

# Source: lib/foglet_bbs/tui/screens/post_reader.ex:215
ScreenFrame.render(frame_state, %{}, post_content, [...])

# Source: lib/foglet_bbs/tui/screens/post_composer.ex:132
ScreenFrame.render(frame_state, %{}, content, [...])

# Source: lib/foglet_bbs/tui/screens/new_thread.ex:172, :203
ScreenFrame.render(state, %{}, board_content, [...])
```

**After Phase 39 (each screen builds parts from its State):**

```elixir
# Example: thread_list.ex
chrome = %{breadcrumb_parts: ["Foglet", state.board.name]}
ScreenFrame.render(frame_state, chrome, thread_content, [...])

# Example: post_reader.ex
chrome = %{breadcrumb_parts: ["Foglet", state.board.name, state.thread.title]}
ScreenFrame.render(frame_state, chrome, post_content, [...])
```

`ScreenFrame.normalize_chrome/2` already does `Map.put_new(:breadcrumb_parts, ...)`,
so passing the key explicitly wins. Once `BreadcrumbBar.parts_for/1` is
deleted, `normalize_chrome` must be updated so the legacy fallback no longer
calls a deleted function.

### Anti-Patterns to Avoid

- **App pattern-matching on a production screen atom for any new responsibility.**
  SPEC Constraint #1 forbids this. Every new clause added during the cleanup
  must be screen-name-agnostic.
- **Adding a new Effect variant for route-entry.** D-02 explicitly forbids it.
  The existing chain (`Effect.navigate` → `init_route_screen_state` →
  `maybe_dispatch_route_entry`) is sufficient.
- **App-side topic diffing.** D-07 forbids it. `subscribe/1` is a pure
  function; whatever Raxol does with the returned subscription list is its
  contract, not App's responsibility.
- **Migrating the deleted PubSub regression tests instead of deleting them.**
  D-17 mandates deletion of the two `current_board`/`current_thread`-ignore
  pin-tests at `app_test.exs:1531-1551, 1587-1607`.
- **Hand-rolling a custom subscription manager** to mimic Raxol behavior.
  Raxol's `Subscription.custom/2` is the documented seam.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Optional behaviour callback dispatch | Custom protocol or pattern-match table | `Code.ensure_loaded?/1` + `function_exported?/3` | Already used 3× in this codebase for `init/1`, `update/3`, `render/2`. Mirror exactly. (app.ex:803–805, 854, 870, 964) |
| PubSub topic forwarding into Raxol | New GenServer or hand-rolled timer | `Foglet.TUI.PubSubForwarder` + `Subscription.custom/2` | Existing seam already used by `subscribe/1`. (pub_sub_forwarder.ex; vendor/raxol/.../subscription.ex:130) |
| Topic-list subscription deltas | App-side diff between old/new topic sets | Just return new list from `subscribe/1` each call | Raxol owns subscription lifecycle. D-07 forbids App-side diffing. Caveat: see Pitfall 2 below. |
| Breadcrumb formatting / display-width truncation | New formatter | `BreadcrumbBar.format/2` (stays after cleanup) | `breadcrumb_bar.ex:36–44` is reusable and unchanged by this phase. |
| Chrome map shape | New `Chrome` struct | Pass plain map with `:breadcrumb_parts` and `:status_atoms` | `ScreenFrame.normalize_chrome/2` (185–196) already accepts this shape; no struct needed. |
| Route-entry effect | New `Effect.route_entry/0` variant | Generic `:on_route_enter` atom message into `route_screen_update/3` | D-02 explicit. The existing message-dispatch path already covers this case. |
| App struct migration helper | A `migrate_legacy_state/1` function | Just delete the fields and any code that reads them | This is a clean delete, not a migration. The legacy fields have no downstream consumer that survives the phase. |

**Key insight:** Almost every mechanism this phase needs already exists. The
work is **deletion + thin shim** (one new optional callback, one generic
dispatch clause, one chrome-key adoption per affected screen).

## Runtime State Inventory

This is a **refactor phase**. Each category below is checked explicitly.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| **Stored data** | None — Phase 39 touches only TUI runtime code; no DB schema, table, ETS table, or Phoenix.PubSub topic name changes. | None. (verified by grep `defp.*topic\|board_topic\|thread_topic\|user_topic` in `lib/foglet_bbs/pub_sub.ex` is untouched.) |
| **Live service config** | None — no n8n / Datadog / external service. | None. |
| **OS-registered state** | None — no systemd unit, Task Scheduler, pm2 process, or launchd plist references TUI screen names or App struct keys. | None. |
| **Secrets/env vars** | None — no env var or SOPS key references the deleted struct fields. | None. |
| **Build artifacts / installed packages** | Compiled `.beam` files for `Foglet.TUI.App`, `Foglet.TUI.Screen`, the four affected screens, `BreadcrumbBar`, and `RenderFixtures`. | `mix compile` after the changes; standard build artifact regeneration. |
| **Test-side fixtures (Foglet-specific)** | Existing app_test.exs and post_reader_test.exs construct `%App{}` literals and use `%{state \| posts: legacy_posts}` updates that name deleted fields. | All test sites that name `:current_board`, `:current_thread`, `:current_thread_list`, `:posts`, `:read_position`, `:composer_draft`, or `:board_list` (as a struct field, not a screen_state map key) must be migrated or deleted. See Common Pitfall 1 below. |

**Nothing found in the first five categories** beyond the standard build
recompile. The last row is the real work — it's why this phase has so many
test-side touchpoints despite being a "pure" code refactor.

## Common Pitfalls

### Pitfall 1: Compile-warnings-as-errors break from dead legacy code in PostReader/PostComposer

**What goes wrong:** Deleting the seven App struct fields fails
`mix compile --warnings-as-errors` because PostReader and PostComposer's
**transitional** `handle_key/2` and `render/1` paths (preserved as legacy
test seams) still reference `state.posts`, `state.read_position`,
`state.current_thread`, `state.current_board`, and `state.composer_draft` on
the App struct.

**Verified call sites that will break:**

| File | Lines | Field accessed |
|------|-------|---------------|
| `screens/post_reader.ex` | 251, 347, 635, 651, 689 | `state.posts` |
| `screens/post_reader.ex` | 410, 426, 504–505, 510–513, 674, 679–680, 684, 729 | `state.read_position` |
| `screens/post_reader.ex` | 359, 373 | `posts:` / `composer_draft:` field-update on `%{state \|...}` |
| `screens/post_reader.ex` | 673–674, 723 | `state.current_thread` |
| `screens/post_reader.ex` | 724 | `state.current_board` |
| `screens/post_composer.ex` | 400 | `Map.get(state, :current_thread)` |
| `screens/post_composer.ex` | 420, 544 | `composer_draft:` field-update |

**Why it happens:** Phase 37 left the legacy `handle_key/render` paths in
place because they served as test seams (verified by the comments at
post_reader.ex:227 and 330). The current production runtime never reaches
them — `new_contract_screen?/2` returns `true` for every screen with
`update/3` exported, which routes `{:key, …}` through `route_screen_update/3`
to the new reducer. But the dead code still compiles, and Elixir's
`warnings-as-errors` will reject struct-field references after the fields
are deleted.

**How to avoid:** Plan the deletion order explicitly. Two valid orderings:

1. **Delete legacy callbacks first, struct fields second** (recommended):
   - Wave A: Delete legacy `handle_key/2` (post_reader.ex:328–380),
     legacy `render/1` (post_reader.ex:225–243), the legacy `load_posts/2`
     and `flush_*` paths if dead, and the legacy code blocks in
     post_composer.ex that reference deleted fields. Confirm via grep that
     no caller invokes them. (NB: SPEC §Out of Scope says removing the
     transitional callbacks is Phase 40 territory — verify with the planner
     whether deleting *just the bodies that reference deleted fields* is
     in-scope for Phase 39 or whether the legacy bodies must be rewritten.)
   - Wave B: Delete the App struct fields.
2. **Remove field references first** (alternative): rewrite the legacy
   bodies to read from `state.screen_state[:post_reader]` instead of
   App struct fields, then delete the App struct fields. This keeps the
   transitional API alive for Phase 40 to remove.

**Warning signs:** `mix compile` errors of the form
`undefined struct field :posts for Foglet.TUI.App` or
`unknown key :current_thread in struct ...`.

### Pitfall 2: Raxol calls `subscribe/1` only once at Dispatcher init

**What goes wrong:** D-07 says "Raxol's existing rebuild semantics handle
adds/removes." That is **not literally true** in the vendored Raxol —
`setup_subscriptions/1` is invoked once at Dispatcher startup
(vendor/raxol/.../events/dispatcher.ex:92), and there is no
resubscribe-on-model-change loop in the Dispatcher.

**Verified:** `grep -n "setup_subscriptions" vendor/raxol/.../events/dispatcher.ex`
yields exactly two matches: the call at line 92 and the definition at line 661.
No other call site. (`Raxol.Core.Runtime.Subscription.start/2` is called per
subscription; `stop_subscription/1` exists but is not invoked from
`setup_subscriptions`.)

**Why it happens:** The current Foglet implementation pattern-matches
`current_screen` inside `build_pubsub_topics/1`, but the function only runs
once at startup. The PubSub regression tests at app_test.exs:1483–1607 pass
because they call `App.subscribe(state)` directly with synthetic state — they
exercise `subscribe/1` as a pure function, not as a runtime path.

**How to avoid (relative to Phase 39 scope):**
- Phase 39's correctness target is **functional equivalence at the
  `subscribe/1` boundary**: same inputs → same topic list. The new code path
  must produce the same `topics` set the old code does for each test scenario
  pinned in app_test.exs:1483–1607 (after deleting the two cases listed in
  D-17). This is what the regression tests actually verify.
- Whether production runtime needs additional resubscribe-on-navigation
  triggers is a **separate concern** — and is explicitly listed in
  CONTEXT.md `## Deferred Ideas` ("App-side topic diffing or 'subscription
  delta' optimization — only worth designing if profiling shows a problem").
- Document this caveat in the verification artifact. Do not let Phase 39
  silently inherit a behavioral assumption that the existing code already
  doesn't satisfy.

**Warning signs:** None at the `mix precommit` level — this is a pure
behavioral observation about Raxol that does not affect compilation or the
pinned test outputs. Surfaces only if the user reports "topic broadcasts
don't reach me after I navigate."

### Pitfall 3: `BreadcrumbBar.normalize_chrome` falls back to a deleted function

**What goes wrong:** `screen_frame.ex:185-196` currently does
`Map.put_new(:breadcrumb_parts, BreadcrumbBar.parts_for(state))`. If
`BreadcrumbBar.parts_for/1` is deleted (per D-11) without updating
`normalize_chrome`, screens that fail to supply `:breadcrumb_parts`
explicitly will crash at render time with `UndefinedFunctionError`.

**Why it happens:** The legacy fallback was explicit (`Map.put_new`); deleting
the helper without removing the put_new leaves a dangling reference.

**How to avoid:**
- The chrome map **must** carry `:breadcrumb_parts` after this phase. Replace
  `Map.put_new(:breadcrumb_parts, BreadcrumbBar.parts_for(state))` with
  `Map.put_new(:breadcrumb_parts, [@root])` (the empty/root case) or have
  `normalize_chrome` raise if the key is missing.
- Verify by `mix foglet.tui.render` for every authenticated screen — if any
  produces a stack trace, the chrome map didn't carry `:breadcrumb_parts`.

**Warning signs:** `(UndefinedFunctionError) function
Foglet.TUI.Widgets.Chrome.BreadcrumbBar.parts_for/1 is undefined or private`.

### Pitfall 4: render_fixtures.ex line 184 is NOT a legacy field

**What goes wrong:** A naïve grep for `board_list:` in render_fixtures.ex
produces TWO matches (line 93 and line 184). They are NOT the same thing.

**Verified:** Line 93 is the legacy `board_list: nil` field on `%App{}`
(delete). Line 184 is `board_list: BoardList.State.new(...)` inside
`screen_state: %{board_list: ...}` (keep — it's the screen-state map key,
which is a screen identifier atom, not the App struct field).

**How to avoid:** When deleting the legacy `base_state/2` block (D-20),
delete only the lines that name the seven legacy keys at the top level of
`%App{}` (render_fixtures.ex:93–98). Do **not** touch the per-screen
`populate/3` clauses that build `screen_state: %{...}` maps — they're correct
as-is.

**Warning signs:** `RenderFixtures.populate(:board_list, ...)` returns a
state with `screen_state: %{}` instead of `%{board_list: ...}`, breaking
`mix foglet.tui.render board_list`.

### Pitfall 5: Test fixtures in `app_test.exs` and `post_reader_test.exs` reference deleted fields

**What goes wrong:** Several existing tests construct or update App state
using deleted field names:

**Verified sites in test/:**

| File | Lines | Construct |
|------|-------|-----------|
| `app_test.exs` | 1531–1551 | `current_board: board` (delete per D-17) |
| `app_test.exs` | 1587–1607 | `current_thread: thread` (delete per D-17) |
| `app_test.exs` | 1666 | `%{state \| posts: legacy_posts}` |
| `app_test.exs` | 2011 | `%{state \| posts: legacy_posts}` |
| `app_test.exs` | 2092, 2099, 2110 | `%{state \| current_screen: ..., read_position: %{"t1" => %{}}}` |
| `post_reader_test.exs` | 385, 403, 424, 430, 438, 447, 559, 753, 765, 778, 822, 829, 838, 851, 885, 894, 913, 924, 940, 996, 1016 | `%{state \| posts: ...}` or `p2_state(%{posts: ...})` |
| `post_reader_test.exs` | 506, 539 | `assert state.posts == ...` |

**Why it happens:** PostReader's legacy `handle_key/2` paths still drive
older tests; those tests construct App states via `p2_state/1` which spreads
`posts:` onto the App struct.

**How to avoid:** Three valid resolutions, ordered by preference:
1. If the test exercises the legacy code path (which becomes dead in Phase 39),
   delete the test. Likely candidates: `post_reader_test.exs:385–447, 506,
   539, 559, 753–1016` if they test the legacy `handle_key/2` paths
   exclusively.
2. If the test exercises the new reducer path but happens to set legacy
   fields incidentally, rewrite it to use `screen_state: %{post_reader: …}`.
3. If the test exercises a code path that genuinely needs the legacy field,
   the field is not actually unused and Phase 39's deletion is incomplete —
   investigate.

The discriminator: read each failing test's assertions. If they pin
behavior under `state.posts == ...` directly (post_reader_test.exs:506, 539),
that is testing the legacy struct shape and is itself a pre-cleanup artifact.

**Warning signs:** `(KeyError) key :posts not found in struct
Foglet.TUI.App` during `mix test`.

### Pitfall 6: AGENTS.md test-style enforcement

**What goes wrong:** Adding a test like
`assert html =~ "Loading..."` would violate the AGENTS.md rule:
"DO NOT WRITE BULLSHIT TESTS THAT TEST FOR THE PRESENCE OR ABSENCE OF TEXT."

**How to avoid:** Phase 39's new tests must assert structural shapes:
- `Map.keys(%App{}) == [...]` (D-19)
- `Foglet.TUI.Screen.behaviour_info(:optional_callbacks) |> Enum.member?({:subscriptions, 2})`
- `function_exported?(Foglet.TUI.Screens.PostReader, :subscriptions, 2)`
- `topic_list_for(state) == [...]` (subscription pin)
- `match?(%Effect{type: :task, payload: %{op: :load_oneliners}}, ...)` (effect-emission pin)

**Warning signs:** Any `assert ... =~` or `refute ... =~` in a Phase 39 test
that targets visible UI text rather than internal structure.

## Code Examples

### Example 1: Adding the optional `subscriptions/2` callback

```elixir
# Source: lib/foglet_bbs/tui/screen.ex (Phase 39 modification)
defmodule Foglet.TUI.Screen do
  # ... existing types ...

  @callback subscriptions(local_state(), Foglet.TUI.Context.t()) :: [String.t()]

  @optional_callbacks init: 1,
                      update: 3,
                      render: 2,
                      render: 1,
                      handle_key: 2,
                      init_screen_state: 1,
                      subscriptions: 2     # NEW
end
```

### Example 2: ThreadList implementing `subscriptions/2`

```elixir
# Source: lib/foglet_bbs/tui/screens/thread_list.ex (Phase 39 addition)
@impl true
@spec subscriptions(State.t() | nil, Context.t()) :: [String.t()]
def subscriptions(%State{board_id: board_id}, _context) when is_binary(board_id) do
  [Foglet.PubSub.board_topic(board_id)]
end

def subscriptions(_local_state, %Context{route_params: params}) do
  case Map.get(params, :board_id) || Map.get(params, "board_id") do
    board_id when is_binary(board_id) -> [Foglet.PubSub.board_topic(board_id)]
    _other -> []
  end
end
```

### Example 3: PostReader implementing `subscriptions/2`

```elixir
# Source: lib/foglet_bbs/tui/screens/post_reader.ex (Phase 39 addition)
@impl true
@spec subscriptions(State.t() | nil, Context.t()) :: [String.t()]
def subscriptions(%State{thread_id: thread_id}, _context) when is_binary(thread_id) do
  [Foglet.PubSub.thread_topic(thread_id)]
end

def subscriptions(_local_state, %Context{route_params: params}) do
  case Map.get(params, :thread_id) || Map.get(params, "thread_id") do
    thread_id when is_binary(thread_id) -> [Foglet.PubSub.thread_topic(thread_id)]
    _other -> []
  end
end
```

### Example 4: Rebuilt `build_pubsub_topics/1` in App

```elixir
# Source: lib/foglet_bbs/tui/app.ex (Phase 39 replacement of lines 433-526)
defp build_pubsub_topics(%__MODULE__{} = state) do
  topics =
    if state.current_user do
      [PubSub.user_topic(state.current_user.id)]
    else
      []
    end

  topics =
    if state.current_screen == :board_list do
      [PubSub.boards_aggregate() | topics]
    else
      topics
    end

  topics ++ screen_declared_topics(state)
end

defp screen_declared_topics(%__MODULE__{} = state) do
  key = screen_key(current_route(state))
  module = screen_module_for(state, key)

  if Code.ensure_loaded?(module) and function_exported?(module, :subscriptions, 2) do
    module.subscriptions(screen_state_for(state, key), build_context(state))
  else
    []
  end
end
```

NB: the `:board_list` aggregate-topic special case is still a screen-name
pattern match, but `:board_list` is **not** a "production-screen atom for the
purpose of dispatching screen-specific entry messages, broadcast handling,
initial-state seeding, or PubSub topic derivation" — it's a global aggregate
topic the App owns, not a screen-declared interest. The planner may choose
to push this into `BoardList.subscriptions/2` instead (cleaner) or keep it in
App as a global topic (matches D-06's "start with global topics" wording).
Recommend pushing it into `BoardList.subscriptions/2` for full uniformity.
This expands D-08's implementer list from {PostReader, ThreadList} to
{PostReader, ThreadList, BoardList} and should be confirmed with the planner.

### Example 5: Generic `:on_route_enter` dispatch

```elixir
# Source: lib/foglet_bbs/tui/app.ex (Phase 39 replacement of lines 810-845)
defp maybe_dispatch_route_entry(%__MODULE__{} = state, screen, _params) do
  route_screen_update(state, screen_key(screen), :on_route_enter)
end
```

The 5 per-screen clauses (lines 810–845) collapse to this single clause.
Screens that don't implement `update(:on_route_enter, …)` hit their existing
catch-all `def update(_message, state, _ctx), do: {state, []}` (verified
present at post_reader.ex:205, post_composer.ex:107, etc.) and become a
no-op.

### Example 6: MainMenu's `:on_route_enter` clause

```elixir
# Source: lib/foglet_bbs/tui/screens/main_menu.ex (Phase 39 addition near line 138)
def update(:on_route_enter, local_state, %Context{} = context) do
  if context.current_user do
    update(:load_oneliners, local_state, context)
  else
    {normalize_state(local_state, context), []}
  end
end
```

This delegates to the existing `update(:load_oneliners, …)` at main_menu.ex:138
— the smallest possible diff per CONTEXT.md "Claude's Discretion" point.

### Example 7: `do_update({:set_user, …})` and `({:promote_session, …})` simplification

```elixir
# Source: lib/foglet_bbs/tui/app.ex (Phase 39 replacement of lines 552-563, 699-714)
defp do_update({:set_user, user}, state) do
  apply_effect(%{state | current_user: user}, Effect.navigate(:main_menu, %{}))
end

defp do_update({:promote_session, user}, state) do
  if is_pid(state.session_pid) do
    Foglet.Sessions.Supervisor.promote_guest_session(state.session_pid, user)
  end

  apply_effect(%{state | current_user: user}, Effect.navigate(:main_menu, %{}))
end
```

`apply_effect(%Effect{type: :navigate, ...})` flow at app.ex:148–161 already
runs `init_route_screen_state` then `maybe_dispatch_route_entry` — which
under the new generic clause from Example 5 will dispatch `:on_route_enter`
to MainMenu, which delegates to `:load_oneliners` per Example 6. Identical
behavior, no hardcoded screen name in App.

### Example 8: Affected-screen chrome map adoption

```elixir
# Source: lib/foglet_bbs/tui/screens/thread_list.ex (Phase 39 modification near :126)
def render(%State{} = state, %Context{} = context) do
  frame_state = frame_state(state, context)
  theme = Theme.from_state(frame_state)
  thread_content = ...

  chrome = %{
    breadcrumb_parts: ["Foglet", board_label(state)]
  }

  ScreenFrame.render(frame_state, chrome, thread_content, [...])
end

defp board_label(%State{board: %{name: name}}) when is_binary(name), do: name
defp board_label(%State{}), do: "Boards"
```

Per D-12, each affected screen builds parts from its **own** state struct
(`ThreadList.State.board.name`, `PostReader.State.thread.title`,
`NewThread.State.board`, `PostComposer.State.thread / .board`). The
`@root = "Foglet"` literal is a Foglet-wide convention; the planner may choose
to extract it as a module attribute on each screen or leave it inline.

## State of the Art

This is a Foglet-internal architectural cleanup, not a domain where external
"state of the art" applies. The relevant ecosystem patterns:

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| App struct holds screen-specific data fields | Screen-local State structs stored in `screen_state` map by atom key | Phase 34 (RUNTIME-01) | Already in use everywhere; Phase 39 deletes the obsolete fields. |
| App pattern-matches `current_screen` for PubSub topic derivation | Optional `Screen.subscriptions/2` callback dispatched from App via `function_exported?/3` | Phase 39 (this phase) | Adds one optional callback; deletes ~95 lines of App-side topic-derivation code. |
| Per-screen route-entry clauses in App | Single generic `:on_route_enter` dispatch clause | Phase 39 (this phase) | Deletes 5 clauses; adds 1. |
| Per-screen breadcrumb assembly in `BreadcrumbBar.parts_for/1` | Each screen supplies `breadcrumb_parts: [...]` in chrome map | Phase 39 (this phase) | Deletes ~40 lines of chrome-side state-decode; pushes 4 lines of label-building into each affected screen. |

**Deprecated/outdated:**
- Legacy `Foglet.TUI.Screen.render/1`, `handle_key/2`, `init_screen_state/1`
  callbacks: still optional, scheduled for Phase 40 deletion (per SPEC §Out
  of scope and ROADMAP Phase 40). Phase 39 does not touch the callback
  declarations, but may need to delete callback **bodies** in PostReader and
  PostComposer if those bodies reference deleted struct fields.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The legacy `handle_key/2` and `render/1` paths in PostReader/PostComposer are dead at runtime because `new_contract_screen?(state, screen)` returns true for every screen. | Pitfall 1 | If a test or non-mainline runtime path still drives the legacy paths, deleting them breaks that path. **Verification:** grep all callers of `Foglet.TUI.Screens.PostReader.handle_key/2` and `.render/1` directly (not via App's auto-dispatch). If only test files reference them, A1 holds. |
| A2 | Pushing the `:board_list` aggregate-topic special case from App into `BoardList.subscriptions/2` is a cleaner application of D-06 than keeping it in App. | Code Example 4 | If the planner prefers to keep aggregate topics App-resident (matching CONTEXT.md D-06's "start with global topics e.g. user_topic"), then BoardList does not need `subscriptions/2` and D-08's implementer list stays at {PostReader, ThreadList}. **Verification:** ask in plan-check or accept either approach as functionally equivalent. |
| A3 | The legacy `frame_state/2` shims in PostReader (lines 890–903), PostComposer (497–506), ThreadList (339–349), and NewThread (705–715) construct **plain maps** that are NOT `%App{}` structs, so their `current_board:`, `current_thread:`, etc. keys are not blocked by the App struct cleanup. | Pitfall 1 + Standard Stack | If any of these shims were actually `%App{...}` literals (not plain maps), deleting App fields would break them. **Verified:** all four use bare `%{...}` map syntax. A3 confirmed. |

**Note:** The Assumptions Log is intentionally short. CONTEXT.md was gathered
in assumptions mode at 2026-04-29 and has 20 locked decisions; this research
verified each one against the live codebase, so most claims are
`[VERIFIED:...]` not `[ASSUMED]`.

## Open Questions

1. **Legacy callback body cleanup vs. Phase 40 deferral.**
   - What we know: SPEC §Out of scope says the transitional `render/1`,
     `handle_key/2`, `init_screen_state/1` callback **declarations** are
     deferred to Phase 40. But Pitfall 1 establishes that the **bodies** of
     those callbacks in PostReader and PostComposer reference deleted struct
     fields and will break compile-warnings-as-errors.
   - What's unclear: Is rewriting (or deleting) those bodies in Phase 39
     in-scope, or does the phase require a different approach (e.g.,
     inline-rewrite the bodies to read from `state.screen_state[:post_reader]`
     instead of `state.posts`)?
   - Recommendation: The planner should split the difference — delete only
     the bodies that reference deleted fields (since the callback is dead at
     runtime), or rewrite them to be field-free shims. Confirm with the user
     during plan-check if uncertain. The cleanest interpretation of D-04
     ("delete, not relocate") and the SPEC §Out of scope ("removing the
     transitional callbacks is Phase 40") is: rewrite the bodies to be
     `state.screen_state[:post_reader] || …`-based stubs in Phase 39, and
     delete the callback declarations entirely in Phase 40.

2. **Whether `BoardList` should implement `subscriptions/2` for the
   `boards` aggregate topic.**
   - What we know: D-06 says "start with global topics (e.g.
     `PubSub.user_topic/1` if `current_user`)" and D-08 lists only
     PostReader/ThreadList as implementers. The current code's
     `if state.current_screen in [:board_list]` (app.ex:442) is a
     screen-name pattern match — exactly the kind R7's acceptance check
     forbids.
   - What's unclear: Does keeping the `:board_list`-aggregate special case
     in App count as a violation of R7's acceptance check ("`lib/foglet_bbs/
     tui/app.ex` contains no function clause that pattern-matches
     `current_screen` against a production-screen atom **for the purpose of
     building a PubSub topic**")?
   - Recommendation: It does count. Push the aggregate topic into
     `BoardList.subscriptions/2`. Add `BoardList` to D-08's implementer list
     (planner can flag this for user confirmation if they want to stay
     strictly within the discussed scope).

3. **The two existing legacy-field "ignores" pin-tests at app_test.exs:1531–1551
   and 1587–1607 may not be the only test sites that name deleted fields.**
   - What we know: Pitfall 5 enumerates ~20+ additional sites in
     post_reader_test.exs and several in app_test.exs (lines 1666, 2011,
     2092, 2099, 2110) that reference deleted fields.
   - What's unclear: Are all of these caught by `mix test` (will the test
     suite fail loudly if a deleted-field reference is missed)? Yes, almost
     certainly — Elixir raises `KeyError` on unknown struct fields at
     runtime. So `mix test` (which precommit does NOT run — see Validation
     Architecture below) will surface them.
   - Recommendation: The planner must include `mix test` in the verification
     gate, not just `mix precommit`. AND the planner should account for
     Pitfall 5's full test-side migration in scope. This is non-trivial and
     should be a distinct task or wave in the plan.

## Environment Availability

Phase 39 is a code-only refactor with no new external dependencies.
**Step 2.6: SKIPPED (no external dependencies identified)** beyond what
Foglet's existing `mix.exs` already requires.

The pre-existing dependencies for `mix precommit` and `mix test` are assumed
present (Elixir, Erlang/OTP, Postgres for `ecto.migrate --quiet` in the test
alias, the vendored Raxol). If any are missing, the project doesn't compile
today, regardless of Phase 39.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | ExUnit (Elixir stdlib) |
| Config file | `test/test_helper.exs`, `mix.exs` `:test_paths` (default `["test"]`) |
| Quick run command | `mix test test/foglet_bbs/tui/app_test.exs:1410` (the `subscribe/1` describe block) |
| Targeted screen test | `mix test test/foglet_bbs/tui/screens/<screen>_test.exs` |
| Full suite command | `mix test` |
| Pre-commit chain | `mix precommit` (compile-warnings-as-errors, deps.unlock, format, credo --strict, sobelow, dialyzer) |
| Headless render | `mix foglet.tui.render <screen>` (ANSI-stripped output for byte-equivalence checks) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| STATE-02 | Seven legacy struct fields removed | unit (struct shape pin) | `mix test test/foglet_bbs/tui/app_struct_test.exs` (NEW) | ❌ Wave 0 |
| STATE-03 | BreadcrumbBar reads explicit input only | unit + render smoke | `mix test test/foglet_bbs/tui/widgets/chrome/breadcrumb_bar_test.exs` (existing — verify) + `mix foglet.tui.render thread_list,post_reader,post_composer,new_thread` | ⚠ verify existing |
| STATE-04 | App-side decoder helpers gone | grep absence | `! grep -q 'post_reader_state_thread_id\|post_composer_state_thread_id\|thread_list_state_board_id' lib/foglet_bbs/tui/app.ex` | n/a (CI grep) |
| APP-01 | App reads as runtime shell | code review (qualitative) + unit (struct shape) | covered by STATE-02 + R10 line-count delta in artifact | n/a |
| APP-02 | No screen-specific result handlers | grep absence + integration | `! grep -E "current_screen ==|current_screen in \[" lib/foglet_bbs/tui/app.ex \| grep -i broadcast`; existing reducer tests for BoardList/PostReader prove broadcasts reach `update/3` | ⚠ verify integration |
| APP-03 | PubSub from screen-declared interests | unit (subscription pin) | `mix test test/foglet_bbs/tui/app_test.exs:1410` + new MainMenu-only-user-topic pin | ⚠ existing block survives + 1 new test |
| APP-04 | Modal handling unchanged | unit (existing modal precedence tests) | `mix test test/foglet_bbs/tui/app_test.exs --only describe:"modal key dismissal"` | ✅ existing |

**Additional pins required by SPEC R6, R7:**

| Pin | Test Type | Command | File Exists? |
|-----|-----------|---------|-------------|
| `Screen.behaviour_info(:optional_callbacks)` includes `{:subscriptions, 2}` | unit | new `screen_test.exs` block | ❌ Wave 0 |
| `function_exported?(PostReader, :subscriptions, 2) == true` | unit | post_reader_test.exs new block | ❌ Wave 0 |
| `function_exported?(ThreadList, :subscriptions, 2) == true` | unit | thread_list_test.exs new block | ❌ Wave 0 |
| Topic-list equivalence for 4 cases (authenticated MainMenu, BoardList, ThreadList with board_id, PostReader with thread_id) | unit | app_test.exs:1410 block (D-16) + new MainMenu pin (D-18) | ⚠ existing + 1 new |
| `mix foglet.tui.render <each-of-five-screens>` byte-equivalence after ANSI-strip | golden-snapshot | `mix foglet.tui.render main_menu \| sed 's/\x1b\[[0-9;]*m//g' \| diff baseline.txt -` | ❌ Wave 0 baseline capture |

### Sampling Rate

- **Per task commit:** `mix compile --warnings-as-errors && mix test
  test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/screens/<edited>_test.exs`
- **Per wave merge:** `mix test` (full suite) + `mix foglet.tui.render` for
  the five tracked screens (`main_menu, board_list, thread_list, post_reader,
  account`).
- **Phase gate:** `mix precommit` exits 0 + full `mix test` green + render
  byte-equivalence diff is empty (after ANSI strip).

### Wave 0 Gaps

- [ ] `test/foglet_bbs/tui/app_struct_test.exs` — covers SPEC R1 (D-19) struct-shape pin
- [ ] New unit test in `test/foglet_bbs/tui/screen_test.exs` (or app_test.exs) — covers SPEC R6 (`@optional_callbacks` includes `{:subscriptions, 2}`)
- [ ] New unit blocks in `post_reader_test.exs` and `thread_list_test.exs` — `function_exported?/3` pins for `subscriptions/2`
- [ ] New pin-test in `app_test.exs` describe "subscribe/1" — authenticated MainMenu produces only `["user:<id>"]` (D-18)
- [ ] **Baseline capture** for `mix foglet.tui.render` golden snapshots — must run BEFORE any Phase 39 source change to capture the pre-phase reference output (per SPEC §Acceptance "byte-for-byte unchanged versus the pre-phase baseline")
- [ ] Test-fixture migration plan for `post_reader_test.exs` (Pitfall 5) — list of ~20 sites that name deleted fields

**Existing test infrastructure that survives:**
- `test/foglet_bbs/tui/app_test.exs:1410-1530` — `subscribe/1` describe block, 6 of 8 cases preserved per D-16
- `test/foglet_bbs/tui/app_test.exs` modal precedence + SizeGate blocks — preserved per SPEC R9
- All existing screen reducer tests — `update/3` contract unchanged

## Project Constraints (from CLAUDE.md / AGENTS.md)

These are non-negotiable directives extracted from the project root
`AGENTS.md` (CLAUDE.md `@AGENTS.md` redirect).

| # | Directive | Phase 39 Implication |
|---|-----------|----------------------|
| 1 | "DO NOT WRITE BULLSHIT TESTS THAT TEST FOR THE PRESENCE OR ABSENCE OF TEXT." | All Phase 39 tests must assert structure: struct keys, callback exports, topic-list equality, effect emission. NO `assert ... =~` against rendered output. (See Pitfall 6.) |
| 2 | "Run `mix precommit` when code changes are complete and fix any issues." | Phase gate. `mix precommit` is the canonical pre-commit chain. Note: it does NOT run `mix test` — that's separate. |
| 3 | "Use `rtk` as the shell command prefix in this repo, for example `rtk mix test` or `rtk git status`." | Plans should specify `rtk mix test` / `rtk mix precommit` etc. |
| 4 | "`Foglet.*` is the application/domain namespace; `FogletBbs.*` and `FogletBbsWeb.*` are Phoenix infrastructure." | Phase 39 touches `Foglet.TUI.*` only. Confirm. |
| 5 | "Keep domain workflows in contexts, not controllers, SSH callbacks, or TUI render functions." | Phase 39 doesn't add any domain workflow — pure runtime refactor. |
| 6 | "Per-board message numbers are stable" / "use `Foglet.Boards.scope_for/1`, `Foglet.Threads.scope_for/1`, and `Foglet.Posts.scope_for/1`" | Phase 39 doesn't touch domain authority or message-number invariants. Confirm by SPEC §Out of scope ("Per-board message-number invariants and `Foglet.Boards.Server` write-path are unaffected"). |
| 7 | Inspecting the TUI: `mix foglet.tui.render <screen>` | This is the verification harness for the byte-equivalence check (SPEC R10 / Acceptance). |
| 8 | Phoenix is "infrastructure for endpoint, PubSub, telemetry, LiveDashboard, and future structured clients; do not add end-user browser workflows" | Phase 39 doesn't touch FogletBbsWeb. Confirm by SPEC §Out of scope. |
| 9 | "Avoid `Process.sleep/1` and `Process.alive?/1`; synchronize with monitors, explicit messages, or `:sys.get_state/1`." | New Phase 39 tests should not use these patterns. |
| 10 | "Use `start_supervised!/1` for processes in tests." | If Phase 39 tests start any process (unlikely — most are pure-function pins), use `start_supervised!/1`. |

## Sources

### Primary (HIGH confidence — codebase verification)
- `lib/foglet_bbs/tui/app.ex` (1,102 lines, full read; lines 1–1102 inspected)
- `lib/foglet_bbs/tui/screen.ex` (full file)
- `lib/foglet_bbs/tui/effect.ex` (full file)
- `lib/foglet_bbs/tui/context.ex` (full file)
- `lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex` (full file)
- `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex` (full file)
- `lib/foglet_bbs/tui/render_fixtures.ex` (full file)
- `lib/foglet_bbs/tui/pub_sub_forwarder.ex` (full file)
- `lib/foglet_bbs/tui/screens/main_menu.ex` (lines 80–180, 510–560)
- `lib/foglet_bbs/tui/screens/post_reader.ex` (lines 1–550, 630–905, full file scanned)
- `lib/foglet_bbs/tui/screens/post_composer.ex` (lines 390–520)
- `lib/foglet_bbs/tui/screens/thread_list.ex` (lines 1–55, 320–350)
- `lib/foglet_bbs/tui/screens/new_thread.ex` (lines 690–720)
- `vendor/raxol/lib/raxol/core/runtime/events/dispatcher.ex` (lines 85–95, 660–700, plus full file grep)
- `vendor/raxol/lib/raxol/core/runtime/subscription.ex` (lines 120–200)
- `test/foglet_bbs/tui/app_test.exs` (lines 1410–1610, plus describe block grep)
- `mix.exs` (lines 78–101 — aliases including precommit)
- `.planning/phases/39-app-shell-simplification/39-CONTEXT.md` (full file)
- `.planning/phases/39-app-shell-simplification/39-SPEC.md` (full file)
- `.planning/REQUIREMENTS.md` (full file)
- `.planning/STATE.md` (full file)
- `.planning/ROADMAP.md` (full file)
- `.planning/phases/34-runtime-contract-effects/34-CONTEXT.md` (full file)
- `AGENTS.md` (full file via /Users/brendan.turner/.claude/CLAUDE.md → ./CLAUDE.md → AGENTS.md chain)

### Secondary (MEDIUM confidence — grep-derived inventories)
- Site enumeration of legacy-field readers via:
  - `grep -rn "current_board\|current_thread\|state.posts\|composer_draft\|read_position\|state.board_list" lib/`
  - `grep -rn "post_reader_state_thread_id\|post_composer_state_thread_id\|thread_list_state_board_id" lib/ test/`
  - `grep -rn "%App{" lib/ test/` (cross-checked against struct construction sites)
  - Per-screen exports survey via `grep -n "@impl\|^  def init\|^  def update\|^  def render\|^  def handle_key"` for all 12 screens

### Tertiary (LOW confidence)
None. All claims in this document are codebase-verified or directly cited from
the locked CONTEXT.md / SPEC.md.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no external dependencies; all libraries verified in `mix.exs` and vendored sources.
- Architecture: HIGH — every claim about `app.ex` line numbers, struct shapes, and dispatch paths verified by direct read.
- Pitfalls: HIGH for Pitfalls 1, 3, 4, 5 (all directly verified against current source); MEDIUM-HIGH for Pitfall 2 (Raxol once-only `setup_subscriptions` verified, but the *implication* for D-07 is interpretive); HIGH for Pitfall 6 (AGENTS.md citation).

**Research date:** 2026-04-28
**Valid until:** 2026-05-28 (30 days; this is a stable internal-refactor scope and the codebase shape doesn't churn day-to-day)

**Confidence-assignment rationale:** Phase 39's primary unknowns are
behavioral (do tests still pass after deletion?), not architectural. The
research consisted of reading the actual source against the SPEC's lock
items. Every numbered claim in CONTEXT.md was cross-checked against the
file at the cited line. Three minor discrepancies surfaced (recorded in the
Assumptions Log and Open Questions): the Raxol `setup_subscriptions` once-
only behavior (Pitfall 2), the `:board_list` aggregate topic special case
(Open Question 2), and the legacy callback bodies in PostReader/PostComposer
that reference deleted fields (Open Question 1, Pitfall 1, Pitfall 5).
