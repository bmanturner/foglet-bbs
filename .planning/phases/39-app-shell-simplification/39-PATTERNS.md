# Phase 39: App Shell Simplification — Pattern Map

**Mapped:** 2026-04-29
**Files analyzed:** 17 (12 production, 5 test/fixture)
**Analogs found:** 17 / 17 (every file has an in-repo precedent)
**Match quality:** all matches are in-tree; the phase is a pure refactor with
no greenfield surfaces.

This document is the source of truth for the planner. Every file scheduled to
change in Phase 39 is paired with the closest existing analog in the codebase,
the concrete excerpt to mirror, and the anti-patterns that must not be
re-introduced. Anti-patterns are repeated per-file because the SPEC R7 acceptance
check forbids them globally.

---

## File Classification

| File (created or modified) | Role | Data Flow | Closest Analog | Match Quality |
|----------------------------|------|-----------|----------------|---------------|
| `lib/foglet_bbs/tui/app.ex` | Raxol runtime / TUI shell | event-driven (subscribe + update + render) | self (in-place delete) | exact (refactor) |
| `lib/foglet_bbs/tui/screen.ex` | behaviour declaration | n/a (contract module) | self lines 37–62 (`@callback` + `@optional_callbacks`) | exact |
| `lib/foglet_bbs/tui/screens/main_menu.ex` | Raxol screen reducer (stateless w/ State) | request-response (key + load) | self lines 138–141 (existing `update(:load_oneliners, …)`) | exact |
| `lib/foglet_bbs/tui/screens/moderation.ex` | Raxol screen reducer | request-response | self lines 64–71 (existing `update(:load, …)`) | exact |
| `lib/foglet_bbs/tui/screens/sysop.ex` | Raxol screen reducer | request-response | `screens/moderation.ex` lines 64–71 | role+flow match |
| `lib/foglet_bbs/tui/screens/thread_list.ex` | Raxol screen reducer (stateful) | request-response + pub-sub | self lines 36–49 (existing `update(:load, …)`) and `routed_thread_topic/1` in `app.ex:463-481` (subscriptions analog) | exact |
| `lib/foglet_bbs/tui/screens/post_reader.ex` | Raxol screen reducer (stateful) | request-response + pub-sub + transform | self lines 75–83 (existing `update(:load, …)`) and self lines 106–116 (existing `:thread_activity` reducer) | exact |
| `lib/foglet_bbs/tui/screens/board_list.ex` | Raxol screen reducer (stateful) | request-response + pub-sub | self lines 26–43 (existing `update(:load, …)`) | exact |
| `lib/foglet_bbs/tui/screens/post_composer.ex` | Raxol screen reducer (stateful) | request-response + form | self `frame_state/2` at lines 497–506 (legacy field cleanup analog) | role+flow match |
| `lib/foglet_bbs/tui/screens/new_thread.ex` | Raxol screen reducer (stateful) | request-response + form | self `frame_state/2` at lines 705–715 | role+flow match |
| `lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex` | stateless widget (formatter) | transform | self lines 36–60 (`format/2` + `render/3` already accept explicit parts) | exact |
| `lib/foglet_bbs/tui/render_fixtures.ex` | test fixture builder | batch | self lines 84–100 (`base_state/2` block to delete) | exact |
| `test/foglet_bbs/tui/app_struct_test.exs` (NEW) | unit test (struct-shape pin) | n/a | `test/foglet_bbs/tui/screen_test.exs` lines 1–135 (callback-export pin shape) | role+flow match |
| `test/foglet_bbs/tui/app_test.exs` | unit test (subscribe seam) | n/a | self lines 1483–1530 (surviving subscription pins) | exact |
| `test/foglet_bbs/tui/screen_test.exs` | unit test (behaviour pins) | n/a | self lines 89–134 (existing reducer-contract describe block) | exact |
| `test/foglet_bbs/tui/screens/post_reader_test.exs` | unit test (screen reducer) | n/a | `test/foglet_bbs/tui/screen_test.exs` (target shape post-migration) | role match |
| `test/foglet_bbs/tui/screens/thread_list_test.exs` | unit test (screen reducer) | n/a | self existing reducer describe blocks | exact |
| `test/foglet_bbs/tui/screens/board_list_test.exs` | unit test (screen reducer) | n/a | self existing reducer describe blocks | exact |

---

## Pattern Assignments

### `lib/foglet_bbs/tui/screen.ex` (behaviour, n/a)

**Analog:** self — extend the existing block at lines 37–62.

**Imports / aliases:** none change. `Foglet.TUI.Context.t()` is already
referenced by lines 37–39.

**Existing pattern to extend** (`screen.ex:37-62`):

```elixir
@callback init(Foglet.TUI.Context.t()) :: local_state()
@callback update(message(), local_state(), Foglet.TUI.Context.t()) :: update_result()
@callback render(local_state(), Foglet.TUI.Context.t()) :: any()

# transitional callbacks ...

@optional_callbacks init: 1,
                    update: 3,
                    render: 2,
                    render: 1,
                    handle_key: 2,
                    init_screen_state: 1
```

**Phase 39 addition (D-05, R6):** add a `subscriptions/2` callback declaration
plus an entry in the `@optional_callbacks` list. Per D-05 the arity ordering
mirrors `update/3` and `render/2` — `local_state` first, `Context.t()` second.

```elixir
@callback subscriptions(local_state(), Foglet.TUI.Context.t()) :: [String.t()]

@optional_callbacks init: 1,
                    update: 3,
                    render: 2,
                    render: 1,
                    handle_key: 2,
                    init_screen_state: 1,
                    subscriptions: 2
```

**Anti-patterns:**
- Do not declare `subscriptions/2` as a non-optional callback. Per D-08 only
  PostReader / ThreadList / BoardList implement it; stateless screens must
  compile without an implementation.
- Do not also remove the transitional `render/1`, `handle_key/2`,
  `init_screen_state/1` declarations — Phase 40 owns that cleanup.

---

### `lib/foglet_bbs/tui/app.ex` — struct (controller / runtime, event-driven)

**Analog:** self lines 50–86 (the field set is shrinking; the surviving fields
already define the target shape).

**Existing pattern** (`app.ex:50-86`):

```elixir
@type t :: %__MODULE__{
        current_screen: screen(),
        current_user: Foglet.Accounts.User.t() | nil,
        session_context: Foglet.TUI.SessionContext.t() | map(),
        session_pid: pid() | nil,
        terminal_size: {pos_integer(), pos_integer()},
        route_params: map(),
        modal: Foglet.TUI.Modal.t() | nil,
        screen_state: map(),
        board_list: list() | nil,
        # Phase 39 cleanup: legacy fields ...
        current_board: map() | nil,
        current_thread: ThreadEntry.t() | nil,
        current_thread_list: list() | nil,
        posts: list() | nil,
        read_position: map(),
        composer_draft: String.t() | nil
      }

defstruct current_screen: :login,
          current_user: nil,
          session_context: %Foglet.TUI.SessionContext{},
          session_pid: nil,
          terminal_size: {80, 24},
          route_params: %{},
          modal: nil,
          screen_state: %{},
          board_list: nil,
          current_board: nil,
          current_thread: nil,
          current_thread_list: nil,
          posts: nil,
          read_position: %{},
          composer_draft: nil
```

**Phase 39 target (R1, D-19):** delete the seven legacy fields from both `@type`
and `defstruct`. Final shape (order-independent):

```elixir
@type t :: %__MODULE__{
        current_screen: screen(),
        current_user: Foglet.Accounts.User.t() | nil,
        session_context: Foglet.TUI.SessionContext.t() | map(),
        session_pid: pid() | nil,
        terminal_size: {pos_integer(), pos_integer()},
        route_params: map(),
        modal: Foglet.TUI.Modal.t() | nil,
        screen_state: map()
      }

defstruct current_screen: :login,
          current_user: nil,
          session_context: %Foglet.TUI.SessionContext{},
          session_pid: nil,
          terminal_size: {80, 24},
          route_params: %{},
          modal: nil,
          screen_state: %{}
```

The `alias Foglet.TUI.Screens.PostComposer`, `PostReader`, `ThreadList` aliases
at lines 26–28 become unused once the decoder helpers below are deleted; remove
them too to keep `mix precommit` clean (Credo `:UnusedAliasWarning`).

**Anti-patterns:**
- Do not retain any of the seven fields as `nil`-valued shims. SPEC R1 acceptance
  check explicitly excludes that ("removed entirely — not retained as
  `nil`-valued shims").
- Do not introduce new fields to compensate (e.g., `legacy_screen_data: %{}`).

---

### `lib/foglet_bbs/tui/app.ex` — generic route-entry (controller, request-response)

**Analog:** self — `route_screen_update/3` at lines 851–865 already implements
the screen-name-agnostic dispatch.

**Existing pattern** (`app.ex:851-865`):

```elixir
defp route_screen_update(%__MODULE__{} = state, key, message) do
  module = screen_module_for(state, key)

  if Code.ensure_loaded?(module) and function_exported?(module, :update, 3) do
    local_state = screen_state_for(state, key)
    context = context_for_screen_key(state, key)
    {new_local_state, effects} = module.update(message, local_state, context)

    state
    |> put_screen_state(key, new_local_state)
    |> apply_effects(List.wrap(effects))
  else
    {state, []}
  end
end
```

**Existing pattern to delete** (`app.ex:810-845`) — five per-screen clauses:

```elixir
defp maybe_dispatch_route_entry(%__MODULE__{} = state, :main_menu, _params) do
  if state.current_user do
    route_screen_update(state, :main_menu, :load_oneliners)
  else
    {state, []}
  end
end

defp maybe_dispatch_route_entry(%__MODULE__{} = state, :moderation, _params) do
  ...
end

defp maybe_dispatch_route_entry(%__MODULE__{} = state, :sysop, _params) do
  ...
end

defp maybe_dispatch_route_entry(%__MODULE__{} = state, :thread_list, _params) do
  route_screen_update(state, :thread_list, :load)
end

defp maybe_dispatch_route_entry(%__MODULE__{} = state, :post_reader, params) do
  case route_param(params, :thread_id) do
    thread_id when is_binary(thread_id) -> route_screen_update(state, :post_reader, :load)
    _other -> {state, []}
  end
end

defp maybe_dispatch_route_entry(%__MODULE__{} = state, _screen, _params), do: {state, []}
```

**Phase 39 replacement (D-01, D-04, R4):** collapse to a single screen-agnostic
clause that always routes `:on_route_enter`:

```elixir
defp maybe_dispatch_route_entry(%__MODULE__{} = state, screen, _params) do
  route_screen_update(state, screen_key(screen), :on_route_enter)
end
```

`route_screen_update/3` at lines 851–865 already does the
`function_exported?(module, :update, 3)` guard, so screens that never receive
`:on_route_enter` simply hit their `update(_message, state, _ctx)` catch-all
and become no-ops.

**Anti-patterns:**
- Do not pattern-match `screen` against any of `:login | :register | :verify |
  :main_menu | :board_list | :thread_list | :post_reader | :post_composer |
  :new_thread | :account | :moderation | :sysop` here. SPEC R4 acceptance check
  explicitly forbids this.
- Do not introduce a `Effect.route_entry()` variant (D-02 forbids).
- Do not gate dispatch on `state.current_user`; let each screen decide
  (e.g., MainMenu's `:on_route_enter` checks the user — see analog below).
- Do not relocate the per-screen dispatch into a private dispatch table; SPEC
  Constraint #1 says "the cleanup must remove them, not relocate them."

---

### `lib/foglet_bbs/tui/app.ex` — `build_pubsub_topics/1` (controller, pub-sub)

**Analog:** self lines 433–461 (current implementation), self lines 853–854
(`function_exported?/3`-gated optional callback dispatch — the canonical
codebase idiom).

**Existing pattern to delete** (`app.ex:433-526`):

```elixir
defp build_pubsub_topics(state) do
  topics =
    if state.current_user do
      [PubSub.user_topic(state.current_user.id)]
    else
      []
    end

  topics =
    if state.current_screen in [:board_list] do          # screen-name pattern match — DELETE
      [PubSub.boards_aggregate() | topics]
    else
      topics
    end

  topics =
    case thread_list_board_topic(state) do                # decoder call — DELETE
      nil -> topics
      topic -> [topic | topics]
    end

  topics =
    case routed_thread_topic(state) do                    # decoder call — DELETE
      nil -> topics
      topic -> [topic | topics]
    end

  topics
end
```

The five helper functions `routed_thread_topic/1` (463–473), `routed_thread_id/1`
(475–481), `post_reader_state_thread_id/1` (483–488),
`post_composer_state_thread_id/1` (490–501), `thread_list_board_topic/1`
(503–512), and `thread_list_state_board_id/1` (521–526) all delete with this
block.

**Phase 39 replacement (D-06, D-22, R7):** mirror the
`Code.ensure_loaded?/1` + `function_exported?/3` paired guard pattern already
used for `update/3` (line 854), `update/3` again (line 870), and `render/2`
(line 964):

```elixir
defp build_pubsub_topics(%__MODULE__{} = state) do
  user_topics =
    if state.current_user do
      [PubSub.user_topic(state.current_user.id)]
    else
      []
    end

  user_topics ++ screen_declared_topics(state)
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

The `:board_list`-aggregate special case at line 442 moves into
`BoardList.subscriptions/2` (D-22). After the move, `app.ex` contains zero
`current_screen ==` / `current_screen in [:foo]` clauses for topic derivation.

**Anti-patterns:**
- Do not pattern-match `current_screen` against any production-screen atom
  inside `build_pubsub_topics/1` or any helper it calls (R7 acceptance check).
- Do not reach into `state.screen_state[:thread_list]`, `[:post_reader]`,
  `[:post_composer]`, etc. from inside App. The whole point is that App
  delegates state-decoding to the screen.
- Do not implement App-side topic diffing (D-07 forbids; Pitfall 2 documents
  that Raxol calls `subscribe/1` once at startup, but Phase 39's correctness
  target is functional equivalence at the `subscribe/1` boundary, not
  resubscribe semantics).
- Do not use `Code.ensure_loaded?/1` alone — pair with `function_exported?/3`
  exactly like the existing dispatch sites at lines 854, 870, 964.

---

### `lib/foglet_bbs/tui/app.ex` — broadcast routing (controller, pub-sub)

**Analog:** self — the existing screen-agnostic broadcast handlers at lines
716–722 and 724–726 already show the target shape.

**Existing pattern to follow** (`app.ex:716-726`):

```elixir
defp do_update({:command_result, inner}, state) do
  do_update(inner, state)
end

defp do_update({:screen_task_result, key, op, result}, state) do
  route_screen_update(state, key, {:task_result, op, result})
end
```

**Existing pattern to delete** (`app.ex:648-661`):

```elixir
defp do_update({:board_activity, _board_id, _event}, state)
     when state.current_screen == :board_list do                 # gate — DELETE
  route_screen_update(state, :board_list, :load)
end

defp do_update({:board_activity, _board_id, _event}, state), do: {state, []}

defp do_update({:thread_activity, thread_id, event}, state)
     when state.current_screen == :post_reader do                # gate — DELETE
  route_screen_update(state, :post_reader, {:thread_activity, thread_id, event})
end

defp do_update({:thread_activity, _thread_id, _event}, state), do: {state, []}
```

**Phase 39 replacement (D-13, R8):** route generically via
`route_screen_update/3` to the active screen. The active screen's `update/3`
catch-all clause makes screens that don't care into no-ops.

```elixir
defp do_update({:board_activity, _board_id, _event} = msg, state) do
  route_screen_update(state, screen_key(current_route(state)), msg)
end

defp do_update({:thread_activity, _thread_id, _event} = msg, state) do
  route_screen_update(state, screen_key(current_route(state)), msg)
end
```

`PostReader` already handles `{:thread_activity, thread_id, event}` in its
`update/3` (`post_reader.ex:106-120`); `BoardList` must add a clause for
`{:board_activity, _, _}` to call the existing `:load` path. Other screens
fall through their `update(_message, state, _ctx)` catch-all and no-op.

**Anti-patterns:**
- Do not preserve the `current_screen ==` guards on the new clauses (R8
  acceptance check).
- Do not delete the broadcast handlers entirely; the messages must still
  reach the active screen via `route_screen_update/3`.

---

### `lib/foglet_bbs/tui/app.ex` — set_user / promote_session (controller, navigate)

**Analog:** self — `apply_effect(state, Effect.navigate(...))` flow at lines
148–161 already runs `init_route_screen_state` then `maybe_dispatch_route_entry`.

**Existing pattern to delete** (`app.ex:552-563, 699-714`):

```elixir
defp do_update({:set_user, user}, state) do
  route_screen_update(
    %{state | current_user: user, current_screen: :main_menu, route_params: %{}},
    :main_menu,
    :load_oneliners                                       # hardcoded screen-specific message — DELETE
  )
end

defp do_update({:promote_session, user}, state) do
  if is_pid(state.session_pid) do
    Foglet.Sessions.Supervisor.promote_guest_session(state.session_pid, user)
  end

  route_screen_update(
    %{state | current_user: user, current_screen: :main_menu, route_params: %{}},
    :main_menu,
    :load_oneliners                                       # hardcoded screen-specific message — DELETE
  )
end
```

**Phase 39 replacement (D-14):** route through `Effect.navigate(:main_menu, %{})`
so first-entry uses the same generic path as any other navigation. The new
generic `maybe_dispatch_route_entry` (above) will deliver `:on_route_enter` to
MainMenu, which delegates to its existing `:load_oneliners` reducer.

```elixir
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

**Anti-patterns:**
- Do not name `:main_menu` as a target message argument anywhere besides the
  `Effect.navigate/2` literal (which is data, not a pattern match — the SPEC
  R4 acceptance check explicitly carves out navigate-target literals; the
  forbidden pattern is dispatching screen-specific *entry messages*).
- Do not retain the hardcoded `:load_oneliners` call. MainMenu's
  `:on_route_enter` clause must be the only entry point for first-load.

---

### `lib/foglet_bbs/tui/app.ex` — `maybe_init_initial_screen_state/1` (controller)

**Analog:** self — `init_route_screen_state/3` at lines 777–794 already handles
MainMenu generically via `function_exported?/3` (line 788).

**Existing pattern to delete** (`app.ex:884-893`):

```elixir
defp maybe_init_initial_screen_state(%{current_screen: :main_menu, current_user: user} = state)
     when not is_nil(user) do
  main_menu_state =
    state
    |> build_context()
    |> Screens.MainMenu.init()
    |> Map.put(:oneliner_status, :idle)

  put_screen_state(state, :main_menu, main_menu_state)
end

defp maybe_init_initial_screen_state(%__MODULE__{} = state) do
  init_route_screen_state(state, state.current_screen, state.route_params)
end
```

**Phase 39 replacement (D-15):** keep only the generic clause:

```elixir
defp maybe_init_initial_screen_state(%__MODULE__{} = state) do
  init_route_screen_state(state, state.current_screen, state.route_params)
end
```

The `init_route_screen_state/3` body at lines 777–794 already covers MainMenu
via the `function_exported?(module, :init, 1)` branch. The
`oneliner_status: :idle` shim is unnecessary: MainMenu's `:on_route_enter`
sets `oneliner_status: :loading` before the task fires.

**Anti-patterns:**
- Do not pattern-match `current_screen: :main_menu` here (R4 acceptance check).
- Do not duplicate MainMenu's `init/1` post-processing in App.

---

### `lib/foglet_bbs/tui/app.ex` — `maybe_seed_legacy_route_context/3` (controller)

**Analog:** self lines 808 — already a no-op `(state, _screen, _params), do: state`.

**Phase 39 disposition:** delete the function and its call site at line 157.
With the seven legacy struct fields gone there is nothing for it to seed; the
Phase 34 D-04 "no compatibility layer" rule disallows leaving dead shims.

**Anti-patterns:**
- Do not rename or repurpose this function for the chrome migration. Chrome
  state flows through screen-emitted `breadcrumb_parts` (see BreadcrumbBar
  pattern below), not through App-side seeding.

---

### `lib/foglet_bbs/tui/screens/main_menu.ex` (Raxol screen reducer, request-response)

**Analog:** self — existing `update(:load_oneliners, …)` clause at lines 138–141.

**Existing pattern** (`main_menu.ex:138-141, 530-536`):

```elixir
def update(:load_oneliners, local_state, %Context{} = context) do
  local_state = normalize_state(local_state, context)
  {%{local_state | oneliner_status: :loading}, [load_oneliners_task_effect(context)]}
end

defp load_oneliners_task_effect(%Context{} = context) do
  oneliners_mod = domain_module(context, :oneliners)

  Effect.task(:load_oneliners, :main_menu, fn ->
    oneliners_mod.list_recent_visible(@oneliner_display_limit)
  end)
end
```

**Phase 39 addition (D-14):** add an `:on_route_enter` clause that delegates to
`:load_oneliners` when a user is present, and falls through to a normalized
no-op otherwise. The smallest possible diff per CONTEXT.md "Claude's Discretion":

```elixir
def update(:on_route_enter, local_state, %Context{} = context) do
  if context.current_user do
    update(:load_oneliners, local_state, context)
  else
    {normalize_state(local_state, context), []}
  end
end
```

Insert above the existing `:load_oneliners` clause so the dispatch falls
through to it cleanly.

**Anti-patterns:**
- Do not rename `:load_oneliners` to `:on_route_enter`. The existing message
  is a stable test seam and direct `update(:load_oneliners, …)` callers in
  reducer tests must keep working.
- Do not inline the task-effect builder; reuse `load_oneliners_task_effect/1`.

---

### `lib/foglet_bbs/tui/screens/moderation.ex` (Raxol screen reducer)

**Analog:** self — existing `update(:load, …)` clause at lines 64–71.

**Existing pattern** (`moderation.ex:64-71`):

```elixir
def update(:load, local_state, %Context{} = context) do
  ss =
    local_state
    |> normalize_state(context)
    |> Map.merge(%{loading?: true, error: nil})

  {ss, [load_workspace_effect(context)]}
end
```

**Phase 39 addition (D-03):** add an `:on_route_enter` delegation. App's
existing per-screen clause (lines 818–824) loaded conditionally on
`state.current_user`; preserve that semantics inside the screen.

```elixir
def update(:on_route_enter, local_state, %Context{} = context) do
  if context.current_user do
    update(:load, local_state, context)
  else
    {normalize_state(local_state, context), []}
  end
end
```

**Anti-patterns:**
- Do not eagerly load when `context.current_user` is nil. The original App
  guard (`app.ex:818-824`) was conditional; preserve that.

---

### `lib/foglet_bbs/tui/screens/sysop.ex` (Raxol screen reducer)

**Analog:** `screens/moderation.ex` lines 64–71 — same role and data flow.

**Phase 39 addition (D-03):** mirror the Moderation pattern exactly:

```elixir
def update(:on_route_enter, local_state, %Context{} = context) do
  if context.current_user do
    update(:load, local_state, context)
  else
    {normalize_state(local_state, context), []}
  end
end
```

(Read the actual sysop.ex `update(:load, …)` clause to confirm its arity and
state-normalization helper name; structurally identical to Moderation.)

**Anti-patterns:** same as Moderation.

---

### `lib/foglet_bbs/tui/screens/thread_list.ex` (Raxol screen reducer, stateful)

**Analog (route entry):** self lines 36–49 (existing `update(:load, …)` clause).

**Analog (subscriptions/2):** App lines 463–481 (current `routed_thread_topic` /
`routed_thread_id` pattern — the local-state-first / route-params-fallback
precedence to mirror inside the screen).

**Existing pattern — `:load` clause** (`thread_list.ex:36-49`):

```elixir
def update(:load, %State{board_id: board_id} = state, %Context{} = context)
    when is_binary(board_id) do
  threads_mod = resolve_threads_module(context)
  user_id = context.current_user && context.current_user.id

  new_state = %{state | status: :loading, last_op: :load_threads, last_error: nil}

  effect =
    Effect.task(:load_threads, :thread_list, fn ->
      dispatch_thread_load(threads_mod, board_id, user_id)
    end)

  {new_state, [effect]}
end

def update(:load, %State{} = state, %Context{}) do
  {%{state | status: {:error, :missing_board}, last_op: nil, last_error: :missing_board}, []}
end
```

**Phase 39 addition — `:on_route_enter`:**

```elixir
def update(:on_route_enter, local_state, %Context{} = context) do
  update(:load, local_state, context)
end
```

(ThreadList loads unconditionally today — `app.ex:834-836` doesn't check
`current_user`. Preserve.)

**Phase 39 addition — `subscriptions/2` (D-08, D-09):**

Mirror the existing `routed_thread_id/1` precedence:

```elixir
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

The two-clause shape — local-state branch then context-fallback — mirrors the
App-side `thread_list_board_id/1` at `app.ex:514-519`.

**Phase 39 modification — `frame_state/2`** (`thread_list.ex:339-349`):

The current `frame_state/2` builds a plain map (not an `%App{}`) with
`current_board: state.board` for the BreadcrumbBar legacy reader. Per D-12,
the screen now emits `breadcrumb_parts` directly. Update the chrome map at
line 126 (currently `%{}`) and trim `current_board` from `frame_state/2`:

```elixir
# was: ScreenFrame.render(frame_state, %{}, thread_content, [...])
chrome = %{breadcrumb_parts: ["Foglet", board_label(state)]}
ScreenFrame.render(frame_state, chrome, thread_content, [...])

defp board_label(%State{board: %{name: name}}) when is_binary(name), do: name
defp board_label(%State{}), do: "Boards"
```

After this change, `frame_state/2` no longer needs `current_board: state.board`
(BreadcrumbBar's `parts_for/1` is gone). Other consumers (Theme, etc.) read
`frame_state.session_context` and `terminal_size` only.

**Anti-patterns:**
- Do not reach into App state from `subscriptions/2` — the local_state arg is
  the only screen state available, and `Context.route_params` is the fallback.
- Do not conditionally subscribe based on `Code.ensure_loaded?(Foglet.PubSub)`;
  this is a runtime module, always loaded.
- Do not retain `current_board:` in the chrome map. The chrome map carries
  `:breadcrumb_parts` and `:status_atoms` only (per
  `screen_frame.ex:185-189`).

---

### `lib/foglet_bbs/tui/screens/post_reader.ex` (Raxol screen reducer, stateful)

**Analog (route entry):** self lines 75–87 (existing `update(:load, …)` clause).

**Analog (subscriptions/2):** App lines 475–481 (`routed_thread_id/1`
local-state-first / route-params-fallback precedence).

**Analog (legacy body cleanup, D-21):** PostReader's own new-contract `update/3`
clauses at lines 75–204, which read from `%State{}` not `state.posts` /
`state.read_position` / `state.current_thread`.

**Existing pattern — `:load` clause** (`post_reader.ex:75-87`):

```elixir
def update(:load, %State{thread_id: thread_id} = state, %Context{} = context)
    when is_binary(thread_id) do
  posts_mod = resolve_domain_module(context, :posts, Foglet.Posts)
  new_state = %{state | status: :loading, last_op: :load_posts, last_error: nil}
  effect = Effect.task(:load_posts, :post_reader, fn -> posts_mod.list_posts(thread_id) end)
  {new_state, [effect]}
end

def update(:load, %State{} = state, %Context{}) do
  {%{state | status: {:error, :missing_thread}, last_op: nil, last_error: :missing_thread}, []}
end
```

**Phase 39 addition — `:on_route_enter`:**

App's existing per-screen clause (`app.ex:838-843`) gated on `route_param(params,
:thread_id)`. Preserve that gate inside the screen — but use the canonical
local-state-first fallback so a re-entry without route_params still loads:

```elixir
def update(:on_route_enter, %State{thread_id: thread_id} = state, %Context{} = context)
    when is_binary(thread_id) do
  update(:load, state, context)
end

def update(:on_route_enter, local_state, %Context{route_params: params} = context) do
  case Map.get(params, :thread_id) || Map.get(params, "thread_id") do
    thread_id when is_binary(thread_id) -> update(:load, local_state, context)
    _other -> {local_state, []}
  end
end
```

**Phase 39 addition — `subscriptions/2` (D-08, D-09):**

```elixir
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

**Phase 39 modification — chrome map:**

```elixir
# was: ScreenFrame.render(frame_state, %{}, post_content, [...])
chrome = %{breadcrumb_parts: ["Foglet", board_label(state), thread_title(state)]}
ScreenFrame.render(frame_state, chrome, post_content, [...])

defp board_label(%State{board: %{name: name}}) when is_binary(name), do: name
defp board_label(%State{}), do: "Boards"

defp thread_title(%State{thread: %{title: title}}) when is_binary(title), do: title
defp thread_title(%State{}), do: "Thread"
```

**Phase 39 modification — legacy callback bodies (D-21, Pitfall 1):**

The legacy `render/1` (lines 225–243), `handle_key/2` (328–380), `load_posts/2`
(400–428), `flush_read_pointers/2` (455–476), `advance_post/2` (650–686),
`scroll_post/2` (688–720), `build_flush_context/1` (722–741), and
`frame_state/2` (890–903) all read from `state.posts`, `state.read_position`,
`state.current_thread`, `state.current_board`, and `state.composer_draft` on
the App struct. Per D-21 these bodies must be **rewritten**, not deleted, to
read from `state.screen_state[:post_reader]` (a `%PostReader.State{}`) so that:

1. `mix compile --warnings-as-errors` stays green after the App struct fields
   are removed.
2. The transitional callback **declarations** in `screen.ex` survive (Phase 40
   removes them).

**Concrete rewrites** (all on the legacy paths):

- `state.posts` → `(state.screen_state[:post_reader] || %State{}).posts`
- `state.read_position` → `(state.screen_state[:post_reader] || %State{}).pending_read_positions`
- `state.current_thread` → `(state.screen_state[:post_reader] || %State{}).thread`
- `state.current_board` → `(state.screen_state[:post_reader] || %State{}).board`
- `state.composer_draft` → `(state.screen_state[:post_composer] || %PostComposer.State{}).input_state.value`

Add a small private helper for safety:

```elixir
defp legacy_state(state) do
  Map.get(state.screen_state || %{}, :post_reader) || %State{}
end
```

The legacy `frame_state/2` at lines 890–903 is a **plain map** (not `%App{}`)
so its `current_board:`, `current_thread:`, `posts:`, `read_position:` keys
are NOT blocked by the App struct cleanup (Pitfall 5 / Assumption A3 in
RESEARCH). They can stay as plain-map keys; the BreadcrumbBar reader is what
goes away. Confirm by reading the current line range and verifying it uses
`%{ ... }` syntax, not `%App{ ... }`.

**Anti-patterns:**
- Do not delete the transitional `render/1` / `handle_key/2` / `load_posts/2` /
  `flush_read_pointers/2` declarations — Phase 40 owns that. The bodies must
  remain callable.
- Do not assert presence of any text in the new `subscriptions/2` test
  (Pitfall 6). Pin behavior: `subscriptions(%State{thread_id: "t-99"}, ctx)
  == ["thread:t-99"]`.
- Do not introduce `Code.ensure_loaded?(__MODULE__)` checks — the screen
  always loads.

---

### `lib/foglet_bbs/tui/screens/board_list.ex` (Raxol screen reducer, stateful)

**Analog:** self lines 36–43 (existing `update(:load, …)` clause).

**Phase 39 addition — `subscriptions/2` (D-22, R7):**

Per CONTEXT D-22, BoardList implements `subscriptions/2` returning the boards
aggregate topic, eliminating App's `:board_list`-special-case at line 442.
This is the cleanest application of D-06 ("App invokes `subscriptions/2` …
union into the topic list") and removes the last `current_screen ==`-style
gate from App's PubSub path.

```elixir
@impl true
@spec subscriptions(State.t() | nil, Context.t()) :: [String.t()]
def subscriptions(_local_state, _context) do
  [Foglet.PubSub.boards_aggregate()]
end
```

**Phase 39 addition — `update/3` for `:board_activity`:**

App now generic-dispatches `{:board_activity, _, _}` to whatever screen is
active (D-13). BoardList's existing screen-side reload runs through `:load`.
Add a clause that triggers reload:

```elixir
def update({:board_activity, _board_id, _event}, local_state, %Context{} = context) do
  update(:load, local_state, context)
end
```

`update(:load, …)` at lines 36–43 already does the right thing
(`load_boards_effect`).

**Anti-patterns:**
- Do not return `[]` from `subscriptions/2` based on user state. The boards
  aggregate is a global topic; it should be present whenever BoardList is
  the active screen, matching the current `if state.current_screen in
  [:board_list]` semantics at `app.ex:442`.
- Do not gate `subscriptions/2` on `context.current_user` — the existing
  topic was unconditional.

---

### `lib/foglet_bbs/tui/screens/post_composer.ex` (Raxol screen reducer, stateful)

**Analog (legacy body cleanup):** self existing new-contract clauses for
`submit_local/2` (lines 456–484) — read from `%State{}`, not from
`state.composer_draft` / `state.current_thread`.

**Existing pattern — new-contract `frame_state/2`** (`post_composer.ex:497-506`):

```elixir
defp frame_state(%State{} = state, %Context{} = context) do
  %{
    current_screen: :post_composer,
    current_user: context.current_user,
    session_context: context.session_context,
    terminal_size: context.terminal_size || @default_terminal_size,
    route_params: context.route_params || %{},
    screen_state: %{post_composer: state}
  }
end
```

Note this is a plain map (`%{ ... }`), not `%App{ ... }`, so `current_screen:`
and `screen_state:` here are plain-map keys, not the deleted struct fields.
Pitfall 4 / Assumption A3.

**Phase 39 modification — chrome map (D-10, D-12, R3):**

```elixir
# was: ScreenFrame.render(frame_state, %{}, content, [...])
chrome = %{breadcrumb_parts: ["Foglet", board_label(state), thread_title(state), "Reply"]}
ScreenFrame.render(frame_state, chrome, content, [...])
```

**Phase 39 modification — legacy bodies (D-21, Pitfall 1):**

Lines 400, 420, and 544 reference `state.composer_draft` and
`Map.get(state, :current_thread)` directly. Rewrite to read from
`state.screen_state[:post_composer]` (a `%PostComposer.State{}`) for the
draft and `state.screen_state[:post_reader]` (or `route_params`) for the
thread/board.

Concretely, line 400's `Map.get(state, :current_thread)` → look up the
PostReader state struct's `.thread` field, or pull from `route_params[:thread]`
if PostReader has not been hydrated.

**Anti-patterns:**
- Do not retain the legacy `composer_draft:` field-update on App in cancel/
  submit-success paths; rewrite to delete the `:post_composer` screen-state
  entry (which is what Phase 37 already does in the new-contract path —
  `submit_success/2` at lines 442–454 doesn't touch `composer_draft`).

---

### `lib/foglet_bbs/tui/screens/new_thread.ex` (Raxol screen reducer, stateful)

**Analog (chrome migration):** `lib/foglet_bbs/tui/screens/thread_list.ex:126`
(target shape) and self `frame_state/2` at lines 705–715 (current legacy-key
shape).

**Existing pattern — current frame_state** (`new_thread.ex:705-715`):

```elixir
defp frame_state(%State{} = state, %Context{} = context) do
  %{
    current_screen: :new_thread,
    current_user: context.current_user,
    current_board: state.board,
    session_context: context.session_context,
    terminal_size: context.terminal_size,
    route: context.route,
    route_params: context.route_params
  }
end
```

(Plain map; the `current_board:` here is the BreadcrumbBar legacy reader's
input. After D-11 deletes the reader, `current_board:` here is dead and can
be trimmed.)

**Phase 39 modification — chrome map (D-10, D-12):**

The render function is at `new_thread.ex:172, 203`. Mirror ThreadList:

```elixir
# was: ScreenFrame.render(state, %{}, board_content, [...])
chrome = %{breadcrumb_parts: ["Foglet", board_label(state), "New Thread"]}
ScreenFrame.render(state, chrome, board_content, [...])

defp board_label(%State{board: %{name: name}}) when is_binary(name), do: name
defp board_label(%State{}), do: "Boards"
```

**Anti-patterns:**
- Do not pass `current_board:` through `frame_state/2` solely for BreadcrumbBar.
  After D-11, the legacy reader is gone.

---

### `lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex` (stateless widget, transform)

**Analog:** self lines 36–60 — `format/2` and `render/3` already accept an
explicit parts list. The cleanup deletes the state-decode path; the formatter
stays.

**Existing pattern to keep** (`breadcrumb_bar.ex:36-60`):

```elixir
@spec format([term()], keyword()) :: String.t()
def format(parts, opts \\ []) when is_list(parts) do
  separator = if Keyword.get(opts, :ascii?, false), do: @ascii_separator, else: @separator
  formatted = parts |> normalize_parts() |> Enum.join(separator)

  case Keyword.get(opts, :width) do
    width when is_integer(width) -> TextWidth.truncate(formatted, width)
    _ -> formatted
  end
end

@spec render(Theme.t(), [term()] | map(), keyword()) :: any()
def render(%Theme{} = theme, parts_or_state, opts \\ []) do
  parts = if is_list(parts_or_state), do: parts_or_state, else: parts_for(parts_or_state)
  content = format(parts, opts)
  slot = breadcrumb_slot(theme)

  text(content,
    fg: Map.get(slot, :fg),
    bg: Map.get(slot, :bg),
    style: Map.get(slot, :style, [])
  )
end
```

**Existing pattern to delete** (`breadcrumb_bar.ex:23-30, 62-92, 106-143`):

```elixir
@spec parts_for(map()) :: [String.t()]
def parts_for(state) when is_map(state) do
  state |> parts_for_screen(screen(state)) |> normalize_parts()
end
def parts_for(_state), do: [@root]

defp parts_for_screen(state, :login), do: login_parts(state)
defp parts_for_screen(_state, :register), do: [@root, "Register"]
defp parts_for_screen(_state, :verify), do: [@root, "Verify"]
defp parts_for_screen(_state, :main_menu), do: [@root, "Home"]
defp parts_for_screen(_state, :board_list), do: [@root, "Boards"]
defp parts_for_screen(state, :thread_list), do: [@root, board_name(state)]
defp parts_for_screen(state, :post_reader), do: [@root, board_name(state), thread_title(state)]
defp parts_for_screen(state, :new_thread), do: [@root, board_name(state), "New Thread"]
defp parts_for_screen(state, :post_composer), do: [@root, board_name(state), thread_title(state), "Reply"]
defp parts_for_screen(_state, :account), do: [@root, "Account"]
defp parts_for_screen(_state, :moderation), do: [@root, "Moderation"]
defp parts_for_screen(_state, :sysop), do: [@root, "Sysop"]
defp parts_for_screen(_state, _screen), do: [@root]

defp screen(state), do: Map.get(state, :current_screen)

defp board_name(state) do
  state_board = state |> Map.get(:current_board) |> map_or_empty()      # legacy reader — DELETE
  ...
end

defp thread_title(state) do
  state |> Map.get(:current_thread) |> map_or_empty() |> Map.get(:title, "Thread")  # legacy reader — DELETE
end
```

The `screen_state_for/2` private helper at lines 139–143 also goes away (it
exists only to serve `board_name/1`).

`@root`, `@separator`, `@ascii_separator`, `normalize_parts/1`, and
`breadcrumb_slot/1` all remain.

**ScreenFrame downstream change** (`screen_frame.ex:185-196`):

```elixir
defp normalize_chrome(%{} = chrome, state) do
  chrome
  |> Map.put_new(:breadcrumb_parts, BreadcrumbBar.parts_for(state))     # parts_for/1 deleted — UPDATE
  |> Map.put_new(:status_atoms, StatusBar.status_atoms(state))
end

defp normalize_chrome(_legacy_title, state) do
  %{
    breadcrumb_parts: BreadcrumbBar.parts_for(state),                   # parts_for/1 deleted — UPDATE
    status_atoms: StatusBar.status_atoms(state)
  }
end
```

After `BreadcrumbBar.parts_for/1` is deleted (Pitfall 3), update the
fallbacks. Recommend `Map.put_new(:breadcrumb_parts, ["Foglet"])` so a screen
that fails to supply parts gets a single-segment root crumb instead of a
crash. The legacy-title clause becomes unreachable in practice (every screen
now passes a chrome map) — leave it returning `%{breadcrumb_parts: ["Foglet"],
status_atoms: ...}` as a defensive default.

**Anti-patterns:**
- Do not hide the deletion behind a `parts_for/1` shim that returns
  `["Foglet"]` — the call site in `normalize_chrome/2` must also change so
  every chrome map carries an explicit parts list.
- Do not introduce a Foglet-wide `Breadcrumb.t()` struct (Deferred Ideas).

---

### `lib/foglet_bbs/tui/render_fixtures.ex` (test fixture builder, batch)

**Analog:** self lines 84–100 — the `base_state/2` block to delete; per-screen
`populate/3` clauses at lines 156, 174, 188–192, 203–211, 233–236, 257–260,
269–276 are the **target** shape (plain `screen_state: %{...}` maps).

**Existing pattern to delete** (`render_fixtures.ex:84-100`):

```elixir
defp base_state(screen, terminal_size) do
  user = if screen in [:login, :register, :verify], do: nil, else: synthetic_user()

  %App{
    current_screen: screen,
    current_user: user,
    session_context: synthetic_session_context(user),
    terminal_size: terminal_size,
    screen_state: %{},
    board_list: nil,                # DELETE
    current_board: nil,             # DELETE
    current_thread: nil,            # DELETE
    current_thread_list: nil,       # DELETE
    posts: nil,                     # DELETE
    read_position: %{}              # DELETE
  }
end
```

**Phase 39 target:**

```elixir
defp base_state(screen, terminal_size) do
  user = if screen in [:login, :register, :verify], do: nil, else: synthetic_user()

  %App{
    current_screen: screen,
    current_user: user,
    session_context: synthetic_session_context(user),
    terminal_size: terminal_size,
    screen_state: %{}
  }
end
```

**CRITICAL — Pitfall 4:** Do NOT touch line 184 (`board_list: BoardList.State.new(...)`
inside a `populate/3` clause). That `board_list:` is a screen-state map key
(an atom screen identifier), not the deleted App struct field. A naïve grep
will surface both lines.

**Anti-patterns:**
- Do not migrate any of the per-screen `populate/3` clauses. They already
  build `screen_state: %{...}` correctly (CONTEXT D-20).

---

## Test File Patterns

### `test/foglet_bbs/tui/app_struct_test.exs` (NEW, struct-shape pin)

**Analog:** `test/foglet_bbs/tui/screen_test.exs` (overall file shape — async
unit test, no setup, structural assertions only).

**Pattern to mirror (D-19, R1 acceptance):**

```elixir
defmodule Foglet.TUI.AppStructTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.App

  describe "struct shape (Phase 39 R1)" do
    test "%App{} contains exactly the eight runtime-shell fields" do
      keys = App.__struct__() |> Map.keys() |> Enum.sort()

      assert keys == [
               :__struct__,
               :current_screen,
               :current_user,
               :modal,
               :route_params,
               :screen_state,
               :session_context,
               :session_pid,
               :terminal_size
             ]
    end

    test "%App{} contains none of the seven legacy fields" do
      keys = App.__struct__() |> Map.keys() |> MapSet.new()

      legacy = [
        :current_board,
        :current_thread,
        :current_thread_list,
        :posts,
        :read_position,
        :composer_draft,
        :board_list
      ]

      Enum.each(legacy, fn field ->
        refute MapSet.member?(keys, field), "expected legacy field #{inspect(field)} to be deleted"
      end)
    end
  end
end
```

**Anti-patterns:**
- Do not `assert is_nil(state.current_board)` — the field is deleted, not
  nilled. The struct test must operate on `Map.keys/1`, not field reads
  (those would raise at struct-construction time, but the explicit absence
  pin is what SPEC R1 demands).
- Do not test serialization or migrations; this phase has none.

---

### `test/foglet_bbs/tui/app_test.exs` (modify subscribe describe block)

**Analog:** self lines 1483–1530 (surviving subscription pins to keep
verbatim per D-16).

**Pattern to keep** (`app_test.exs:1483-1530`):

```elixir
test "board_list screen adds 'boards' topic" do
  user = %Foglet.Accounts.User{id: "u1", handle: "alice"}

  {:ok, state} =
    App.init(%{session_context: fake_oneliners_context(%{user: user, user_id: "u1"})})

  state = %{state | current_screen: :board_list}
  subs = App.subscribe(state)

  pubsub_sub = Enum.find(subs, &match?(%Raxol.Core.Runtime.Subscription{type: :custom}, &1))
  assert pubsub_sub != nil
  assert "boards" in pubsub_sub.data.args.topics
end
```

The seam shape (`Enum.find(&match?(%Subscription{type: :custom}, &1))` →
`pubsub_sub.data.args.topics`) is durable; keep it.

**Phase 39 deletions (D-17):**

Delete the two pin tests at lines 1531–1551 (`current_board` ignored) and
1587–1607 (`current_thread` ignored). They construct deleted struct fields
directly and would fail to compile after R1.

**Phase 39 addition (D-18):**

Add a new pin proving stateless screens omit `subscriptions/2`:

```elixir
test "main_menu (stateless authenticated screen) produces only user topic" do
  user = %Foglet.Accounts.User{id: "u1", handle: "alice"}

  {:ok, state} =
    App.init(%{session_context: fake_oneliners_context(%{user: user, user_id: "u1"})})

  state = %{state | current_screen: :main_menu, current_user: user}
  subs = App.subscribe(state)

  pubsub_sub = Enum.find(subs, &match?(%Raxol.Core.Runtime.Subscription{type: :custom}, &1))
  assert pubsub_sub != nil
  assert pubsub_sub.data.args.topics == ["user:u1"]
end
```

**Phase 39 fixture migrations (Pitfall 5, D-23):**

The five sites in this file at lines 1666, 2011, 2092, 2099, 2110 use
`%{state | posts: legacy_posts}` or `%{state | read_position: %{...}}`. These
must be either deleted (if they exercise the legacy `handle_key/2` path that
Phase 37 made dead) or rewritten to use
`screen_state: %{post_reader: %PostReader.State{posts: ...}}`. The plan owns
the call: read each test's assertion to determine if it pins legacy or
new-contract behavior.

**Anti-patterns:**
- Do not migrate the deleted pin tests at 1531–1551 / 1587–1607 — D-17
  mandates deletion.
- Do not assert against rendered text in the new D-18 pin (Pitfall 6 /
  AGENTS.md).
- Do not add `Process.sleep/1` or `Process.alive?/1` (AGENTS.md Constraint 9).

---

### `test/foglet_bbs/tui/screen_test.exs` (extend with optional-callbacks pin)

**Analog:** self lines 89–134 (existing `describe "new screen contract"` block).

**Pattern to extend (R6 acceptance):**

```elixir
describe "Screen behaviour (Phase 39 R6)" do
  test "lists subscriptions/2 in @optional_callbacks" do
    optional = Foglet.TUI.Screen.behaviour_info(:optional_callbacks)

    assert {:subscriptions, 2} in optional
  end

  test "preserves the existing optional callback set" do
    optional = MapSet.new(Foglet.TUI.Screen.behaviour_info(:optional_callbacks))

    expected = [
      {:init, 1},
      {:update, 3},
      {:render, 2},
      {:render, 1},
      {:handle_key, 2},
      {:init_screen_state, 1},
      {:subscriptions, 2}
    ]

    Enum.each(expected, fn callback ->
      assert MapSet.member?(optional, callback),
             "expected #{inspect(callback)} in @optional_callbacks"
    end)
  end
end
```

**Anti-patterns:**
- Do not assert exact equality of the optional-callbacks list; behaviour_info
  ordering is not guaranteed. Use set membership.

---

### `test/foglet_bbs/tui/screens/post_reader_test.exs` (function_exported + 20 fixture migrations)

**Analog (function_exported pin):** the new screen_test.exs block above.

**Pattern to add (D-23, R6 acceptance):**

```elixir
describe "subscriptions/2 (Phase 39 R6)" do
  test "module exports subscriptions/2" do
    assert function_exported?(Foglet.TUI.Screens.PostReader, :subscriptions, 2)
  end

  test "returns thread topic from local state" do
    state = Foglet.TUI.Screens.PostReader.State.new(thread_id: "t-99")
    ctx = %Foglet.TUI.Context{route_params: %{}}

    assert Foglet.TUI.Screens.PostReader.subscriptions(state, ctx) == ["thread:t-99"]
  end

  test "returns thread topic from route params when local state is empty" do
    ctx = %Foglet.TUI.Context{route_params: %{thread_id: "t-route"}}

    assert Foglet.TUI.Screens.PostReader.subscriptions(nil, ctx) == ["thread:t-route"]
  end

  test "returns [] when no thread id is available" do
    ctx = %Foglet.TUI.Context{route_params: %{}}

    assert Foglet.TUI.Screens.PostReader.subscriptions(nil, ctx) == []
  end
end
```

**Pattern for fixture migration (D-23, Pitfall 5):**

The ~20 sites that name deleted fields (385, 403, 424, 430, 438, 447, 506,
539, 559, 753, 765, 778, 822, 829, 838, 851, 885, 894, 913, 924, 940, 996,
1016) divide into three categories:

1. **Tests that exercise the legacy `handle_key/2` path** — these tests pin
   the dead-at-runtime path and should be deleted outright if every assertion
   targets `state.posts ==` or similar legacy shape. Likely candidates: 506,
   539 (direct `state.posts ==` reads).
2. **Tests that exercise the new reducer path but happen to set legacy fields
   incidentally** — rewrite `p2_state(%{posts: ...})` to construct a
   `%PostReader.State{posts: ...}` inside `screen_state: %{post_reader: ...}`.
3. **Tests that pin behavior under `state.read_position[...]`** — these
   should be migrated to `state.pending_read_positions[...]` on the
   `%PostReader.State{}` struct, since that is the new field name.

The discriminator: read each failing test's assertions. If they assert on
`state.posts == ...` directly, that is testing the legacy struct shape and
is itself a pre-cleanup artifact (delete). If they call
`PostReader.handle_key/2` then assert on a state-shape change, the test is
exercising dead code (delete or rewrite to call `update/3` instead).

**Anti-patterns:**
- Do not migrate tests via `state.posts || (state.screen_state[:post_reader] && state.screen_state[:post_reader].posts)` 
  — that is a fall-back shim, exactly the kind D-04 / Phase 34 D-04 forbids.
- Do not assert visible rendered text presence. The existing
  `flat =~ "Loading…"` patterns at lines 380–388 are pre-existing and
  currently violate AGENTS.md; do not propagate them. Where Phase 39 adds
  new assertions, target structural shape only.

---

### `test/foglet_bbs/tui/screens/thread_list_test.exs` and `board_list_test.exs` (function_exported pins)

**Analog:** the post_reader_test.exs block above.

**Pattern (R6 / R7 acceptance):**

```elixir
describe "subscriptions/2 (Phase 39 R6/R7)" do
  test "ThreadList exports subscriptions/2" do
    assert function_exported?(Foglet.TUI.Screens.ThreadList, :subscriptions, 2)
  end

  test "returns board topic from local state" do
    state = Foglet.TUI.Screens.ThreadList.State.new(board_id: "b-77")
    ctx = %Foglet.TUI.Context{route_params: %{}}

    assert Foglet.TUI.Screens.ThreadList.subscriptions(state, ctx) == ["board:b-77"]
  end
end
```

For board_list_test.exs, the equivalent block pins
`BoardList.subscriptions(_, _) == ["boards"]` (the aggregate topic, per D-22).

**Anti-patterns:** same as post_reader_test.exs.

---

## Shared Patterns

### Optional callback dispatch via `function_exported?/3`

**Source:** `lib/foglet_bbs/tui/app.ex:854, 870, 964` (three existing call sites).

**Apply to:** the new `subscriptions/2` invocation inside
`build_pubsub_topics/1` / `screen_declared_topics/1`, plus any other Phase 39
introduction that needs to invoke an optional Screen callback.

```elixir
# Source: lib/foglet_bbs/tui/app.ex:854 (route_screen_update/3)
if Code.ensure_loaded?(module) and function_exported?(module, :update, 3) do
  local_state = screen_state_for(state, key)
  context = context_for_screen_key(state, key)
  {new_local_state, effects} = module.update(message, local_state, context)
  ...
end

# Source: lib/foglet_bbs/tui/app.ex:870 (new_contract_screen?/2)
defp new_contract_screen?(%__MODULE__{} = state, screen) do
  module = screen_module_for(state, screen_key(screen))
  Code.ensure_loaded?(module) and function_exported?(module, :update, 3)
end

# Source: lib/foglet_bbs/tui/app.ex:964 (render_screen/1)
if Code.ensure_loaded?(module) and function_exported?(module, :render, 2) do
  ...
end
```

Both `Code.ensure_loaded?/1` and `function_exported?/3` are required in pair —
in test/dev the module may not be loaded yet when `subscribe/1` runs.

**Anti-patterns:**
- Do not use `function_exported?/3` alone. `Code.ensure_loaded?/1` is the
  guard against unloaded modules.
- Do not catch `UndefinedFunctionError` and fall back. The export check is
  the contract.

---

### Stateful-screen state struct with `from_context/1` and local-state-first / route-params-fallback

**Source:** `lib/foglet_bbs/tui/screens/thread_list.ex:28` and
`lib/foglet_bbs/tui/screens/post_reader.ex:71`.

**Apply to:** ThreadList and PostReader's new `subscriptions/2`. The
precedence is:

1. Read id from `local_state.thread_id` / `.board_id` if it's a binary.
2. Fall back to `Context.route_params[:thread_id]` / `[:board_id]` (atom or
   string key).
3. Empty / missing → return `[]`.

```elixir
# Source: lib/foglet_bbs/tui/screens/thread_list.ex:28
def init(%Context{} = context), do: State.from_context(context)

# Mirrors today's app.ex:475-481 routed_thread_id/1 precedence (which gets deleted).
```

**Anti-patterns:**
- Do not read from App state inside `subscriptions/2` — only `local_state`
  and `Context.t()` are passed.

---

### Chrome map flowing into `ScreenFrame.render/4`

**Source:** `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex:185-189`.

**Apply to:** every affected screen's render function (ThreadList, PostReader,
PostComposer, NewThread).

```elixir
# Source: lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex:185-189
defp normalize_chrome(%{} = chrome, state) do
  chrome
  |> Map.put_new(:breadcrumb_parts, BreadcrumbBar.parts_for(state))
  |> Map.put_new(:status_atoms, StatusBar.status_atoms(state))
end
```

The chrome map is a plain `%{}` carrying `:breadcrumb_parts` (a `[String.t()]`)
and optionally `:status_atoms`. Use `Map.put_new` semantics: the screen's
explicit value wins over any default.

**Anti-patterns:**
- Do not introduce a `Chrome` struct (Deferred Ideas).
- Do not put `breadcrumb_parts` on the screen's State struct; build it inside
  `render/2` from existing State fields (D-12).
- Do not let `BreadcrumbBar.parts_for/1` survive the deletion — update
  `normalize_chrome/2` so the `Map.put_new` fallback uses `["Foglet"]` (or
  raises) instead.

---

### Test seam: subscription shape via `Subscription{type: :custom}`

**Source:** `test/foglet_bbs/tui/app_test.exs:1492` (durable through Phase 39
per D-16).

**Apply to:** any new `App.subscribe/1` regression test (D-18, BoardList
boards-aggregate equivalence).

```elixir
pubsub_sub = Enum.find(subs, &match?(%Raxol.Core.Runtime.Subscription{type: :custom}, &1))
assert pubsub_sub != nil
assert "<expected-topic>" in pubsub_sub.data.args.topics
```

**Anti-patterns:**
- Do not pattern-match on subscription order; use `Enum.find`.
- Do not assert `length(subs) == N` — heartbeat / clock subscriptions are
  separate and not under Phase 39 control.

---

### Test seam: structural pins, not text presence

**Source:** AGENTS.md ("DO NOT WRITE BULLSHIT TESTS THAT TEST FOR THE PRESENCE
OR ABSENCE OF TEXT") + `test/foglet_bbs/tui/screen_test.exs:89-134` (the
canonical structural-pin shape in this codebase).

**Apply to:** every new Phase 39 test.

Acceptable pin shapes:
- `Map.keys(%App{}) == [...]` (D-19)
- `Foglet.TUI.Screen.behaviour_info(:optional_callbacks)` membership
- `function_exported?(module, :subscriptions, 2)` (D-18)
- Topic-list equality (`pubsub_sub.data.args.topics == ["user:u1"]`)
- Effect-emission match: `match?(%Effect{type: :task, payload: %{op: :load_oneliners}}, ...)`
- Reducer state-transition assertions (`{%State{posts: [_, _]}, []} = update(...)`)

Forbidden:
- `assert html =~ "Loading..."` or any `=~` on rendered output
- `refute serialized =~ "**world**"`
- Sleep-and-poll timing assertions

---

## No Analog Found

None. Phase 39 is a pure refactor; every introduction (subscriptions/2,
on_route_enter, breadcrumb_parts chrome key, struct-shape pin) has a direct
in-tree analog. The closest "no exact analog" is the new
`test/foglet_bbs/tui/app_struct_test.exs`, but `screen_test.exs` is a strong
role-and-flow match for "async unit test that pins module-level structural
properties," which is the entire content of the new file.

---

## Metadata

**Analog search scope:**
- `lib/foglet_bbs/tui/app.ex` (full read in chunks; lines 1–906 inspected)
- `lib/foglet_bbs/tui/screen.ex` (full file)
- `lib/foglet_bbs/tui/screens/{main_menu,moderation,thread_list,post_reader,post_composer,new_thread,board_list}.ex` (relevant ranges)
- `lib/foglet_bbs/tui/widgets/chrome/{breadcrumb_bar,screen_frame}.ex` (full read of breadcrumb_bar; relevant range of screen_frame)
- `lib/foglet_bbs/tui/render_fixtures.ex` (lines 75–195)
- `lib/foglet_bbs/pub_sub.ex` (full file)
- `test/foglet_bbs/tui/app_test.exs` (lines 1480–1620)
- `test/foglet_bbs/tui/screen_test.exs` (full file)
- `test/foglet_bbs/tui/screens/post_reader_test.exs` (lines 380–460 plus grep summary)

**Files scanned:** 13 production, 4 test/fixture
**Pattern extraction date:** 2026-04-29
