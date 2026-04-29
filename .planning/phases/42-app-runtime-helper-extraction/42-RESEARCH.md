# Phase 42: App Runtime Helper Extraction - Research

## RESEARCH COMPLETE

## Executive Summary

Phase 42 is a maintainability extraction, not a behavior expansion. The current `Foglet.TUI.App` concentrates four runtime concern clusters:

- Routing/screen state/context helpers: `current_route/1`, `screen_key/1`, `build_context/1`, `screen_state_for/2`, `put_screen_state/3`, `init_route_screen_state/3`, `route_screen_update/3`, `context_for_screen_key/2`, `screen_module_for/2`.
- Modal runtime: modal overlay rendering, modal key precedence, confirm callbacks, form submission routing, and generic form-submit failure.
- Subscription runtime: heartbeat and clock subscriptions, `PubSubForwarder` custom subscription setup, `InitialRouteEnterForwarder`, user topics, screen-declared topics, and refresh-on-topic-change.
- Effect runtime: interpretation of `%Foglet.TUI.Effect{}` values for navigation, modal open/dismiss/submit, session messages, terminal resize, PubSub publish, quit, and task wrapping.

The best implementation plan is dependency ordered: routing first, modal second, effects third, subscriptions last. Routing is the lowest-level dependency for screen keys, context construction, target reducer delivery, rendering, and screen subscription delegation. Modal and effects then call into routing instead of duplicating screen dispatch. Subscriptions can move after routing because it depends on screen module resolution and context construction.

## Source Inventory

### Primary Implementation Files

- `lib/foglet_bbs/tui/app.ex` - extraction source; remains Raxol application module and owns `%Foglet.TUI.App{}`.
- `lib/foglet_bbs/tui/context.ex` - screen reducer context value; routing helper should build it.
- `lib/foglet_bbs/tui/effect.ex` - current effect value constructors; effect helper interprets these values but does not change the data shape.
- `lib/foglet_bbs/tui/pub_sub_forwarder.ex` - existing dynamic PubSub bridge; subscription helper should call `refresh/1` only when effective topics differ.
- `lib/foglet_bbs/tui/initial_route_enter_forwarder.ex` - existing one-shot first-route-enter subscription; subscription helper should keep wiring it.
- `lib/foglet_bbs/tui/widgets/modal.ex` and `lib/foglet_bbs/tui/widgets/modal/form.ex` - modal rendering/form event primitives; modal helper should reuse these.

### Primary Test Files

- `test/foglet_bbs/tui/app_runtime_contract_test.exs` - concentrated runtime contract tests; migrate many assertions into helper-specific test files.
- `test/foglet_bbs/tui/app_test.exs` - App callback and broader runtime integration tests; keep high-level App shell coverage here.
- `test/foglet_bbs/tui/effect_test.exs` - effect constructor tests; add helper interpreter tests separately rather than bloating constructor coverage.

## Existing Runtime Behavior To Preserve

### Routing

- Empty route params are encoded as the screen atom; non-empty params become `{screen, params}`.
- Screen-local state lives under `state.screen_state` by screen key.
- `%Foglet.TUI.Context{}` carries `current_user`, `session_context`, `session_pid`, `terminal_size`, `route`, `route_params`, and `domain`.
- `domain.screen_modules` overrides should win when the override atom is loadable.
- Invalid override atoms must log and fall back to the built-in resolver, not silently no-op.
- Route-owned screens `:thread_list`, `:post_reader`, `:post_composer`, and `:new_thread` must reinitialize when entered so route params drive data loading.
- Route entry dispatch sends `:on_route_enter` through the active screen reducer.
- Screen reducers receive `{message, local_state, context}` and return `{local_state, effects}`.

### Modal

- Modal keys take precedence over screen reducers.
- Confirm modal keys: `Y/y` confirms; `N/n` or Escape cancels.
- Info/error/warning modal keys: Enter, Escape, and Space dismiss.
- Form modal events go through `Foglet.TUI.Widgets.Modal.Form.handle_event/2`.
- Form submit must route a first-class `%Foglet.TUI.Effect{type: :modal_submit}` to the target reducer as `{:modal_submit, kind, payload}`.
- Missing or invalid modal-submit targets must produce `%Foglet.TUI.Modal{type: :error, title: "Form Error", message: "Unable to submit form."}`.

### Effects

- `:navigate` updates `current_screen`, resets `route_params`, clears `modal`, initializes route state, then dispatches `:on_route_enter`.
- `:modal` opens or dismisses `state.modal`.
- `:modal_submit` routes through screen reducer delivery or shows the generic modal-submit error.
- `{:session, {:set_user, user}}` delegates to existing promotion behavior.
- `{:session, {:set_current_user, user}}` only updates `current_user`.
- `{:session, {:update_preferences, snapshot}}` merges preferences into `session_context` and informs `Foglet.Sessions.Session` when `session_pid` is present.
- `{:session, {:dispatch, message}}` re-enters App dispatch.
- Other session payloads are sent to `session_pid` when present.
- `{:terminal, {:size, {cols, rows}}}` reuses window-change behavior.
- `:publish` broadcasts with `Phoenix.PubSub.broadcast(FogletBbs.PubSub, topic, message)`.
- `:quit` returns `[Command.quit()]`.
- `:task` wraps success/error into `{:screen_task_result, screen_key, op, {:ok | :error, result}}`.

### Subscriptions

- Heartbeat interval subscribes only when `session_pid` is a pid.
- Main-menu clock interval always subscribes.
- PubSub custom subscription uses `Foglet.TUI.PubSubForwarder` with computed topics.
- Initial route-enter custom subscription uses `Foglet.TUI.InitialRouteEnterForwarder`.
- User topic is `Foglet.PubSub.user_topic(state.current_user.id)` when authenticated.
- Active screen `subscriptions/2` contributes screen-specific topics when exported.
- Dynamic refresh calls `PubSubForwarder.refresh(new_topics)` only when old and new topic lists differ.

## Recommended Helper APIs

Exact names and arities can shift during implementation, but plans should preserve this shape:

### `Foglet.TUI.App.Routing`

- `current_route(app) :: atom() | {atom(), map()}`
- `screen_key(route_or_screen) :: atom()`
- `current_screen_state(app) :: term()`
- `screen_state_for(app, key) :: term()`
- `put_screen_state(app, key, local_state) :: app`
- `build_context(app) :: Foglet.TUI.Context.t()`
- `build_context(app, route_params) :: Foglet.TUI.Context.t()`
- `init_route_screen_state(app, screen, params) :: app`
- `dispatch_route_entry(app, screen, params) :: {app, [Command.t()]}`
- `route_screen_update(app, key, message) :: {app, [Command.t()]}`
- `context_for_screen_key(app, key) :: Foglet.TUI.Context.t()`
- `screen_module_for(app, key) :: module() | nil`
- `render_screen(app) :: Raxol UI tree`

### `Foglet.TUI.App.Modal`

- `render_overlay(modal, app) :: Raxol UI tree`
- `handle_key(key_event, app) :: {app, [Command.t()]}`
- `dismiss(app) :: {app, []}`
- `confirm(app, :yes | :no) :: {app, [Command.t()]}`
- `submit_error(app) :: {app, []}`

Modal helper should depend on routing/effect callbacks or direct helper calls, but must not know screen-specific business modules.

### `Foglet.TUI.App.Effects`

- `apply_effect(app, Effect.t()) :: {app, [Command.t()]}`
- `apply_effects(app, [Effect.t()]) :: {app, [Command.t()]}`

Effects should call `Routing` for navigation and reducer delivery and `Modal` for modal-submit failures or dismissal. Domain mutations remain in screen-requested tasks and contexts.

### `Foglet.TUI.App.Subscriptions`

- `subscribe(app) :: [Subscription.t()]`
- `topics(app) :: [String.t()]`
- `screen_declared_topics(app) :: [String.t()]`
- `refresh_dynamic(old_app, new_app) :: :ok`

The helper should reuse `Foglet.PubSub`, `Foglet.TUI.PubSubForwarder`, and `Foglet.TUI.InitialRouteEnterForwarder`.

## Planning Recommendations

1. Start by extracting routing and migrating route/helper tests. Keep App public delegators only if they are production-useful; otherwise rewrite tests to call `App.Routing`.
2. Extract modal behavior next, because modal form submit needs reducer routing and visible failure behavior.
3. Extract effect interpretation after routing/modal exist so effect tests can prove delegation instead of duplicating old App internals.
4. Extract subscriptions last so it can use routing-owned screen module/context helpers for `subscriptions/2`.
5. Keep App-level tests focused on `init/1`, `update/2`, `view/1`, `subscribe/1`, message normalization, and cross-helper integration.
6. Avoid text-presence tests. Assert state changes, command structs, reducer messages, PubSub messages, modal struct fields, and subscription structs.

## Pitfalls

- Do not create circular dependencies where `Routing` calls `Effects` and `Effects` calls `Routing` in a way that obscures ownership. A practical shape is: routing can call `Effects.apply_effects/2` after reducer returns effects, while effects calls routing for navigation and target reducer delivery. If this becomes circular at compile time, pass an effect interpreter callback into routing reducer delivery.
- Do not let modal helper call screen modules directly with copied logic. Use routing-owned reducer delivery.
- Do not drop the invalid override warning fallback; silent no-ops would regress maintainability.
- Do not refresh PubSub subscriptions after every update. Preserve the old/new effective topic comparison.
- Do not move session promotion or durable domain calls into helpers beyond existing App shell dispatch paths. Screen tasks and domain contexts own those mutations.
- Do not keep obsolete App helper functions only because old tests call them. The context explicitly allows migrating tests to helper APIs.

## Validation Architecture

### Automated Test Strategy

- Add focused helper tests:
  - `test/foglet_bbs/tui/app/routing_test.exs`
  - `test/foglet_bbs/tui/app/modal_test.exs`
  - `test/foglet_bbs/tui/app/effects_test.exs`
  - `test/foglet_bbs/tui/app/subscriptions_test.exs`
- Preserve or slim existing integration coverage:
  - `test/foglet_bbs/tui/app_runtime_contract_test.exs`
  - `test/foglet_bbs/tui/app_test.exs`
- Quick feedback command for this phase:
  - `rtk mix test test/foglet_bbs/tui/app_runtime_contract_test.exs test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/app`
- Full verification:
  - `rtk mix precommit`

### Coverage Map

- Routing tests cover D-01, D-02, D-03, D-04, D-05, D-06, D-07, D-11, D-12, D-13, D-23, D-24, and TUI-04.
- Modal tests cover D-01, D-02, D-03, D-08, D-14, D-15, D-16, D-23, D-24, and TUI-04.
- Effect tests cover D-01, D-02, D-03, D-09, D-17, D-18, D-19, D-23, D-24, and TUI-04.
- Subscription tests cover D-01, D-02, D-03, D-10, D-20, D-21, D-22, D-23, D-24, and TUI-04.
- App integration tests cover the shell boundary: Raxol callbacks, message normalization, SizeGate path, modal/effect/subscription delegation, and initial route entry.

### Verification Commands

- During extraction: run focused helper tests after each helper lands.
- Before completing each plan: run `rtk mix test test/foglet_bbs/tui/app_runtime_contract_test.exs test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/app`.
- Before phase completion: run `rtk mix precommit`.

## Open Questions

None blocking. The main implementation choice is whether routing reducer delivery accepts an effect interpreter callback to avoid compile-time cycles. Both callback and direct-helper approaches are acceptable if tests make dependency direction understandable.
