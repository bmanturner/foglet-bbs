# Phase 42: App Runtime Helper Extraction - Context

**Gathered:** 2026-04-29 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 42 extracts `Foglet.TUI.App` runtime concerns into narrow helper modules while keeping `Foglet.TUI.App` as the Raxol application entry point and owner of the App struct. The phase is limited to routing/screen-state plumbing, modal runtime behavior, dynamic subscriptions, and generic effect interpretation. It must preserve current TUI behavior and screen reducer contracts, especially route-owned reinitialization and `{:modal_submit, kind, payload}` reducer messages.

Locked requirements come from `42-SPEC.md`: routing, modal, subscription, and effect behavior move behind helper APIs; durable domain mutations stay in `Foglet.*` contexts or screen-requested tasks; App keeps `init/1`, `update/2`, `view/1`, `subscribe/1`, message normalization, and high-level shell dispatch; helper-level behavioral tests make the new ownership falsifiable.
</domain>

<decisions>
## Implementation Decisions

### Helper Module Boundaries
- **D-01:** Put the extracted helpers under the App runtime namespace as `Foglet.TUI.App.Routing`, `Foglet.TUI.App.Modal`, `Foglet.TUI.App.Subscriptions`, and `Foglet.TUI.App.Effects`.
- **D-02:** Treat these helpers as App-shell runtime helpers, not general TUI/domain modules. They may operate on `%Foglet.TUI.App{}` state, but they must not own durable domain mutations or screen-specific business workflows.
- **D-03:** Keep `Foglet.TUI.App` as the integration point for Raxol callbacks and shell message normalization. The helpers own detailed behavior; App owns when to call them.

### Public API And Test Seams
- **D-04:** Do not preserve `Foglet.TUI.App` public helper functions only because old tests call them. If functions such as route/context/effect seams become obsolete after extraction, remove them and rewrite the tests around the new helper APIs.
- **D-05:** Preserve behavior coverage rather than compatibility surface. Existing App tests may be migrated to helper-level tests when the helper is the new owner, while App-level tests should cover callback integration and end-to-end shell wiring.
- **D-06:** Any thin App delegation function that remains must have a production reason or a clear public boundary reason, not merely a legacy-test reason.

### Extraction Order
- **D-07:** Extract routing first because modal submit, effect interpretation, rendering, and subscription topic derivation all depend on route encoding, screen keys, screen module resolution, context construction, and screen-state access.
- **D-08:** Extract modal runtime after routing so form submits can delegate target reducer delivery through the routing helper and visible failure handling remains App-shell-owned.
- **D-09:** Extract generic effects after routing and modal so navigation, modal open/dismiss, modal submit, session, terminal, publish, quit, and task effects can delegate to the proper runtime helpers without circular ownership.
- **D-10:** Extract subscriptions after routing is stable, because screen-declared topics depend on screen keys, screen modules, local screen state, and `Context` construction.

### Routing Helper
- **D-11:** The routing helper owns route encoding, screen-key derivation, current/local screen-state reads and writes, screen module resolution including `domain.screen_modules` override fallback, context construction, route-owned screen initialization, route-entry dispatch, and reducer routing.
- **D-12:** Preserve route-owned reinitialization for `:thread_list`, `:post_reader`, `:post_composer`, and `:new_thread` unless a later phase explicitly changes the route model.
- **D-13:** Preserve the loadable override fallback behavior for `domain.screen_modules`; invalid override atoms should remain visible to maintainers through logging and fall back to built-in resolution rather than silently no-oping.

### Modal Helper
- **D-14:** The modal helper owns modal overlay rendering, modal key precedence, confirm yes/no callbacks, info/error/warning dismissal keys, form event routing, and generic form-submit failure visibility.
- **D-15:** Modal helpers may call routing/effect callbacks supplied by App or the effect helper, but must not learn screen-specific business logic.
- **D-16:** Missing or invalid modal-submit targets must still produce a visible error modal, not a silent no-op.

### Effect Helper
- **D-17:** The effect helper owns interpretation of all current `%Foglet.TUI.Effect{}` types while delegating route mutation and modal-submit reducer delivery through routing/modal helpers.
- **D-18:** Task effects must preserve the current wrapper shape: command tasks return `{:screen_task_result, screen_key, op, {:ok | :error, result}}`, and App/shell routing delivers that back to the target screen as `{:task_result, op, result}`.
- **D-19:** Domain work remains inside context functions invoked by screen-requested tasks; the effect helper only schedules, dispatches, publishes, notifies sessions, resizes terminal state, or returns runtime commands.

### Subscription Helper
- **D-20:** The subscription helper owns heartbeat gating by `session_pid`, chrome clock intervals, `PubSubForwarder` wiring, `InitialRouteEnterForwarder` wiring, user topics, screen `subscriptions/2` delegation, and dynamic topic refresh.
- **D-21:** Preserve `PubSubForwarder.refresh/1` only-when-effective-topic-list-changes behavior.
- **D-22:** Preserve the initial route-enter subscription behavior so authenticated sessions mounted directly by `App.init/1` still receive exactly one `:on_route_enter` pass after the dispatcher starts.

### Coverage
- **D-23:** Move route/effect/subscription contract assertions from broad App tests into focused helper tests when ownership moves, but retain App-level integration tests for `init/1`, `update/2`, `view/1`, `subscribe/1`, modal/effect round trips, and dynamic refresh side effects.
- **D-24:** Tests must assert behavior and state/command/message outcomes, not the mere presence or absence of rendered text.

### the agent's Discretion
- Downstream agents may choose the exact public function names and arities for helper APIs, provided each helper has a narrow, discoverable API and tests name that ownership.
- Downstream agents may choose whether effects call routing/modal helpers directly or receive callback functions from App, as long as the dependency direction stays understandable and avoids circular module coupling.
- Downstream agents may split extraction into multiple plans by helper or by dependency order, as long as each step preserves passing runtime behavior.

### Folded Todos
No matching todos were folded into this phase.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

- `.planning/phases/42-app-runtime-helper-extraction/42-SPEC.md`
- `.planning/phases/41-tui-contract-and-modal-effects/41-CONTEXT.md`
- `.planning/ROADMAP.md`
- `.planning/REQUIREMENTS.md`
- `.planning/PROJECT.md`
- `.planning/codebase/CONCERNS.md`
- `.planning/codebase/CONVENTIONS.md`
- `.planning/codebase/STRUCTURE.md`
- `.planning/codebase/TESTING.md`
- `lib/foglet_bbs/tui/app.ex`
- `lib/foglet_bbs/tui/context.ex`
- `lib/foglet_bbs/tui/effect.ex`
- `lib/foglet_bbs/tui/pub_sub_forwarder.ex`
- `lib/foglet_bbs/tui/initial_route_enter_forwarder.ex`
- `lib/foglet_bbs/tui/widgets/modal.ex`
- `lib/foglet_bbs/tui/widgets/modal/form.ex`
- `test/foglet_bbs/tui/app_runtime_contract_test.exs`
- `test/foglet_bbs/tui/app_test.exs`
- `test/foglet_bbs/tui/effect_test.exs`
- `test/foglet_bbs/tui/screens/board_list_test.exs`
- `test/foglet_bbs/tui/screens/thread_list_test.exs`
- `test/foglet_bbs/tui/screens/post_reader_test.exs`
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Foglet.TUI.Context` is already the narrow screen-facing runtime context and should stay the value routing helpers build for screen reducers.
- `Foglet.TUI.Effect` already includes `:navigate`, `:modal`, `:modal_submit`, `:session`, `:terminal`, `:publish`, `:quit`, and `:task` effect constructors.
- `Foglet.TUI.PubSubForwarder` already normalizes topics, handles refresh messages, and bridges Phoenix PubSub into Raxol subscription messages.
- `Foglet.TUI.InitialRouteEnterForwarder` already supplies the one-shot first-load route-entry message that `App.init/1` cannot emit as a command.
- `Foglet.TUI.Widgets.Modal` and `Foglet.TUI.Widgets.Modal.Form` already separate modal body/form rendering and event handling from App overlay positioning.

### Established Patterns
- Screen-local state is stored under `App.screen_state` by screen key and reducers receive `{message, local_state, %Context{}}`.
- Route params are encoded as an atom for empty params or `{screen, params}` for non-empty params.
- Screen modules may be overridden through `session_context.domain.screen_modules` in tests and other injected contexts, with fallback to built-in screen resolution.
- Route entry dispatch uses `:on_route_enter`; screen reducers own first-load behavior.
- Screen `subscriptions/2` callbacks own screen-specific PubSub topics, while App owns user-level and stable runtime subscriptions.
- Task effects wrap success/error results and route them back through screen reducers rather than mutating screen state directly in App.

### Integration Points
- `Foglet.TUI.App.update/2` should delegate normalized key, subscription, route-enter, command-result, task-result, heartbeat, session replacement, and terminal messages to helper-owned behavior where appropriate.
- `Foglet.TUI.App.view/1` should keep the too-small gate and delegate screen/modal rendering through helper-owned paths.
- `Foglet.TUI.App.subscribe/1` should delegate stable subscription construction to the subscription helper.
- Existing tests in `app_runtime_contract_test.exs` and `app_test.exs` are the main migration source for helper-level coverage.
</code_context>

<specifics>
## Specific Ideas

- User correction: do not retain App public helper functions merely for old test compatibility. Rewrite obsolete tests so they cover the new helper APIs and preserved behavior.
- Prefer grep-friendly helper names matching the concern audit: `App.Routing`, `App.Modal`, `App.Subscriptions`, and `App.Effects`.
- Treat Phase 42 as maintainability extraction, not behavior expansion.
</specifics>

<deferred>
## Deferred Ideas

None - analysis stayed within phase scope.

### Reviewed Todos (not folded)
No matching todos were found for this phase.
</deferred>

---

*Phase: 42-app-runtime-helper-extraction*
*Context gathered: 2026-04-29*
