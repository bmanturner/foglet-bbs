# Phase 42: App Runtime Helper Extraction - Patterns

## PATTERN MAPPING COMPLETE

## Files To Create

| File | Role | Closest Analog | Notes |
|------|------|----------------|-------|
| `lib/foglet_bbs/tui/app/routing.ex` | App-shell routing, context, screen-state, reducer dispatch, render dispatch | Existing private functions in `lib/foglet_bbs/tui/app.ex`; `Foglet.TUI.Context` | Move behavior, keep `%Foglet.TUI.App{}` as state shape. |
| `lib/foglet_bbs/tui/app/modal.ex` | App-shell modal overlay and modal key runtime | Existing private modal functions in `app.ex`; `Foglet.TUI.Widgets.Modal.Form` | Reuse widget APIs; keep screen-specific behavior out. |
| `lib/foglet_bbs/tui/app/effects.ex` | App-shell effect interpreter | Existing `App.apply_effect/2` and `apply_effects/2`; `Foglet.TUI.Effect` constructors | Interpret existing values, do not alter `%Effect{}` shape. |
| `lib/foglet_bbs/tui/app/subscriptions.ex` | App-shell subscription construction and dynamic topic refresh | Existing subscription private functions in `app.ex`; `PubSubForwarder`; `InitialRouteEnterForwarder` | Own topic list diffing and custom subscriptions. |
| `test/foglet_bbs/tui/app/routing_test.exs` | Focused routing helper contract | `test/foglet_bbs/tui/app_runtime_contract_test.exs` | Migrate route/state/context assertions here. |
| `test/foglet_bbs/tui/app/modal_test.exs` | Focused modal helper contract | `test/foglet_bbs/tui/app_test.exs` form modal tests | Assert state/commands/modal structs, not rendered text presence. |
| `test/foglet_bbs/tui/app/effects_test.exs` | Focused effect interpreter contract | `app_runtime_contract_test.exs`; `effect_test.exs` | Constructor tests stay in `effect_test.exs`; interpreter tests move here. |
| `test/foglet_bbs/tui/app/subscriptions_test.exs` | Focused subscription helper contract | App contract subscription tests | Assert subscription structs and `PubSubForwarder.refresh/1` behavior. |

## Files To Modify

| File | Role | Change |
|------|------|--------|
| `lib/foglet_bbs/tui/app.ex` | Raxol app shell | Delegate extracted behavior; keep struct, `init/1`, `update/2`, `view/1`, `subscribe/1`, normalization, high-level dispatch. |
| `test/foglet_bbs/tui/app_runtime_contract_test.exs` | Integration contract | Remove obsolete direct App helper assertions or redirect to helper modules; keep cross-helper behavior. |
| `test/foglet_bbs/tui/app_test.exs` | App callback integration | Keep App-level behavior around init/update/view/subscribe and screen round trips. |

## Concrete Existing Patterns

### Context Construction

`Foglet.TUI.Context.new/1` is the context builder's target API. It accepts only public screen-facing fields and derives `domain` from `session_context` when absent.

Planner and executor should preserve the current App behavior:

```elixir
Context.new(
  current_user: state.current_user,
  session_context: state.session_context,
  session_pid: state.session_pid,
  terminal_size: state.terminal_size,
  route: state.current_screen,
  route_params: route_params,
  domain: domain_from_session_context(state.session_context)
)
```

### Route State Storage

Screen-local state belongs in `state.screen_state`; writes should stay explicit and loud:

```elixir
%{state | screen_state: Map.put(state.screen_state, key, local_state)}
```

Do not reintroduce `state.screen_state || %{}` in write paths unless a new invariant justifies it.

### Route-Owned Reinitialization

Route-owned screens are locked by context and spec:

```elixir
key in [:thread_list, :post_reader, :post_composer, :new_thread]
```

These screens reinitialize on route entry, and routes with non-empty params plus `update/3` should also reinitialize.

### Override Fallback

Preserve the loadable override branch and warning fallback:

```elixir
override = get_in(domain_from_session_context(state.session_context), [:screen_modules, screen])

cond do
  is_atom(override) and not is_nil(override) and Code.ensure_loaded?(override) ->
    override

  is_atom(override) and not is_nil(override) ->
    Logger.warning("[TUI.App] domain.screen_modules[...] is not loadable; falling back...")
    maybe_known_screen_module(screen)

  true ->
    maybe_known_screen_module(screen)
end
```

The exact message can change, but the behavior must remain visible and fallback-based.

### Modal Form Runtime

`Foglet.TUI.Widgets.Modal.Form.handle_event/2` returns `{new_form, action}` where action can be:

- `{:submitted, %Foglet.TUI.Effect{type: :modal_submit}}`
- `:submitted`
- `{:submitted, other}`
- `:cancelled`
- `nil`

The modal helper should update the modal's form struct before interpreting action and should route invalid submit actions to the generic form error modal.

### Effect Task Runtime

The task wrapper shape is a cross-phase contract:

```elixir
Foglet.TUI.Command.task(op, fn ->
  try do
    {:screen_task_result, screen_key, op, {:ok, fun.()}}
  rescue
    e ->
      reason = Exception.format(:error, e, __STACKTRACE__)
      {:screen_task_result, screen_key, op, {:error, reason}}
  catch
    kind, value ->
      reason = Exception.format(kind, value, __STACKTRACE__)
      {:screen_task_result, screen_key, op, {:error, reason}}
  end
end)
```

Do not simplify this into unwrapped tasks; screen routing depends on the tuple shape.

### PubSub Forwarder Runtime

`Foglet.TUI.PubSubForwarder.refresh/1` broadcasts a control message to the dispatcher-owned forwarder. The subscription helper should call it only after comparing old and new topic lists:

```elixir
if old_topics != new_topics do
  _ = PubSubForwarder.refresh(new_topics)
end
```

## Test Patterns

### Good Assertion Shapes

- `assert %Context{route_params: %{thread_id: "t1"}} = Routing.build_context(state)`
- `assert %SampleScreen.State{messages: [{:on_route_enter, params}]} = Routing.screen_state_for(new_state, :sample_runtime)`
- `assert [%Raxol.Core.Runtime.Command{type: :task, data: task}] = cmds`
- `assert {:screen_task_result, :sample_runtime, :load, {:ok, value}} = task.()`
- `assert %Foglet.TUI.Modal{type: :error, message: "Unable to submit form."} = new_state.modal`
- `assert %Raxol.Core.Runtime.Subscription{type: :custom, data: %{module: Foglet.TUI.PubSubForwarder, args: %{topics: topics}}} = sub`

### Avoid

- Text-presence tests for modal or screen content.
- App public delegation functions kept only for legacy tests.
- Test-only process dictionary handoffs.
- Rebuilding large fixtures where a small override screen module proves the behavior.

## Dependency Notes

- `Routing` can depend on `%Foglet.TUI.App{}` structurally and on `Foglet.TUI.Context`.
- `Modal` can depend on `Routing`, `Foglet.TUI.Widgets.Modal`, `Foglet.TUI.Widgets.Modal.Form`, `Theme`, and `Command`.
- `Effects` can depend on `Routing`, `Modal`, `Foglet.TUI.Command`, `Effect`, `Phoenix.PubSub`, and session modules.
- `Subscriptions` can depend on `Routing`, `Foglet.PubSub`, `PubSubForwarder`, `InitialRouteEnterForwarder`, and `Raxol.Core.Runtime.Subscription`.
- If compile-time cycles appear between `Routing` and `Effects`, make route reducer dispatch accept an effect interpreter callback. This is the only expected cycle risk.
