# Phase 47: Bound Unbounded List Queries, Drop Chrome V1 Shims, Reduce App + Login - Pattern Map

**Mapped:** 2026-04-30
**Files analyzed:** 22 (8 new, 14 modified/deleted)
**Analogs found:** 22 / 22

This phase has unusually strong analog coverage because every workstream cites
an explicit Phase precedent in CONTEXT (Phase 42 App.* extractions, Phase 43
PostReader decomposition, Phase 44 list_reader_window/2 trailing-keyword
shape). Pattern assignments below cite concrete file paths with line numbers
the planner can hand straight to plan actions.

## File Classification

| New / Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---------------------|------|-----------|----------------|---------------|
| `lib/foglet_bbs/tui/app/screen_states.ex` (new) | App helper | request-response | `lib/foglet_bbs/tui/app/routing.ex` (esp. lines 38-54) | exact |
| `lib/foglet_bbs/tui/app/session_alias.ex` (new) | App helper | event-driven | `lib/foglet_bbs/tui/app/modal.ex` (clause-table style) | exact |
| `test/foglet_bbs/tui/app/screen_states_test.exs` (new) | test | request-response | `test/foglet_bbs/tui/app/routing_test.exs` | exact |
| `test/foglet_bbs/tui/app/session_alias_test.exs` (new) | test | event-driven | `test/foglet_bbs/tui/app/modal_test.exs` | exact |
| `lib/foglet_bbs/tui/screens/login/menu.ex` (new) | per-mode reducer | event-driven | `lib/foglet_bbs/tui/screens/login.ex:166-181` (handle_menu_key) | role+flow exact |
| `lib/foglet_bbs/tui/screens/login/login_form.ex` (new) | per-mode reducer | request-response | `lib/foglet_bbs/tui/screens/login.ex:247-285` (handle_form_key) | role+flow exact |
| `lib/foglet_bbs/tui/screens/login/reset_request.ex` (new) | per-mode reducer | request-response | `lib/foglet_bbs/tui/screens/login.ex:287-305, 398-442` | role+flow exact |
| `lib/foglet_bbs/tui/screens/login/reset_consume.ex` (new) | per-mode reducer | request-response | `lib/foglet_bbs/tui/screens/login.ex:313-340, 466-489` | role+flow exact |
| `lib/foglet_bbs/posts.ex` (modify, delete) | context | CRUD | n/a — pure deletion (R1) | n/a |
| `lib/foglet_bbs/threads.ex` (modify, add arity-3) | context | CRUD | `lib/foglet_bbs/posts.ex:99-153` (`list_reader_window/2`) | exact |
| `lib/foglet_bbs/tui/screens/post_reader.ex` (modify) | screen reducer | CRUD | `Foglet.Posts.list_reader_window/2` consumers already in `post_reader.ex` (window-anchor helpers at `:567-609`) | exact |
| `lib/foglet_bbs/tui/app.ex` (modify, drop <400) | conductor | event-driven | already self-shaped (Phase 42 precedent); pattern is delegate-out | exact |
| `lib/foglet_bbs/tui/app/routing.ex` (modify) | App helper | request-response | self (move screen_state inline manipulation to ScreenStates) | exact |
| `lib/foglet_bbs/tui/screens/login.ex` (modify, drop <300) | screen reducer | event-driven | `lib/foglet_bbs/tui/screens/post_reader.ex` + `post_reader/render.ex` (Phase 43 layout) | exact |
| `lib/foglet_bbs/tui/screens/login/state.ex` (modify) | screen state | n/a | self (preserve map shape per D-13); add no constructors | self |
| `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex` (modify) | widget | request-response | self (delete V1 branches at 191-196, 198-204) | n/a |
| `lib/foglet_bbs/tui/widgets/chrome/status_bar.ex` (modify) | widget | request-response | self (delete arity at :37) | n/a |
| `lib/foglet_bbs/tui/widgets/chrome/key_bar.ex` (DELETE) | widget | n/a | n/a | n/a |
| `lib/foglet_bbs/tui/widgets/chrome/normalizer.ex` (DELETE) | widget | n/a | n/a | n/a |
| Five screen call sites (V1→V2) | screen render | request-response | `lib/foglet_bbs/tui/screens/sysop/render.ex:52-54, 61-79` (V2 grouped emission) | exact |
| Test fixtures (post_reader_test.exs, app_test.exs) | test | CRUD | `Posts.list_reader_window/2` consumers in `post_reader.ex` | exact |
| `.dialyzer_ignore.exs` (conditional remove) | config | n/a | n/a (D-17: only if naturally resolved) | n/a |

## Pattern Assignments

### `lib/foglet_bbs/tui/app/screen_states.ex` (new — App helper, request-response)

**Analog:** `lib/foglet_bbs/tui/app/routing.ex` lines 38-54 (the existing
`screen_state_for/2` and `put_screen_state/3` already live here; the
extraction is a *move* out of `Routing` into a focused module).

**Module layout pattern** (from `routing.ex:1-16`):

```elixir
defmodule Foglet.TUI.App.ScreenStates do
  @moduledoc """
  App-shell screen-state map helper.

  Owns get/put/update/delete for `state.screen_state` (note: the field is
  singular per `app.ex:58, 68`; D-18 explicitly does not rename it).
  """

  alias Foglet.TUI.App
  # ...
end
```

**Core CRUD pattern** to copy (from `routing.ex:44-54`):

```elixir
@spec screen_state_for(App.t(), term()) :: term()
def screen_state_for(%App{screen_state: screen_state}, key) do
  Map.get(screen_state || %{}, key)
end

@spec put_screen_state(App.t(), term(), term()) :: App.t()
def put_screen_state(%App{} = state, key, local_state) do
  %{state | screen_state: Map.put(state.screen_state, key, local_state)}
end
```

**Adapt to D-19** — expose `get/2`, `put/3`, `update/4`, `delete/2` (use
`App.Routing` / `App.Modal` API style). Keep delegators on `App` (`app.ex:103-114`)
as thin one-line passthroughs.

**Size budget (D-21):** < 100 lines.

---

### `lib/foglet_bbs/tui/app/session_alias.ex` (new — App helper, event-driven)

**Analog:** `lib/foglet_bbs/tui/app/modal.ex` (clause-table style; small focused
module taking `%App{}` and returning `{App.t(), [Command.t()]}`).

**Imports/aliases pattern** (from `modal.ex:1-18`):

```elixir
defmodule Foglet.TUI.App.SessionAlias do
  alias Foglet.TUI.App
  alias Foglet.TUI.App.Effects
  alias Raxol.Core.Runtime.Command
  # ...
end
```

**Clauses to move from `app.ex`:**

1. `:set_user` clause — `app.ex:270-272` (3 lines):

```elixir
defp do_update({:set_user, user}, state) do
  do_update({:promote_session, user}, state)
end
```

2. `:promote_session` clause — `app.ex:384-412` (~29 lines, includes the
   `session_context |> Map.put(:user, user) |> Map.put(:user_id, user.id)`
   aliasing helper and the `Effects.apply_effect(...)` navigate-to-main-menu
   tail).

3. `:session_replaced` clause — `app.ex:369-378` (10 lines, the warning modal
   with `on_confirm/on_cancel: Command.quit()`).

**Delegation shape** (D-20): `App` retains thin one-line `do_update`
clauses dispatching to `SessionAlias.set_user/2`,
`SessionAlias.promote_session/2`, `SessionAlias.session_replaced/2`. The
public callback boundary is unchanged.

**Size budget (D-21):** < 80 lines.

---

### `test/foglet_bbs/tui/app/screen_states_test.exs` (new)

**Analog:** `test/foglet_bbs/tui/app/routing_test.exs`

**Imports/setup pattern** (from `routing_test.exs:1-9, 51-75`):

```elixir
defmodule Foglet.TUI.App.ScreenStatesTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.App
  alias Foglet.TUI.App.ScreenStates

  defp state(attrs \\ %{}) do
    attrs = Map.new(attrs)

    struct!(
      App,
      Map.merge(
        %{
          current_screen: :main_menu,
          screen_state: %{main_menu: %{seeded: true}}
        },
        attrs
      )
    )
  end
  # ...
end
```

**Test shape** — focus on get/put/update/delete and nil-safety on `screen_state`
field (cf. `routing.ex:46-48` — `screen_state || %{}` must be preserved).

---

### `test/foglet_bbs/tui/app/session_alias_test.exs` (new)

**Analog:** `test/foglet_bbs/tui/app/modal_test.exs:1-55`

**Helper pattern (`modal_test.exs:35-55`):**

```elixir
defp state(attrs) do
  attrs = Map.new(attrs)

  session_context = Map.get(attrs, :session_context, %{...})

  struct!(App, Map.merge(%{
    current_screen: :source,
    session_context: session_context,
    screen_state: %{...},
    terminal_size: {100, 30}
  }, attrs))
end
```

**Test the three behaviors:**
1. `set_user/2` (currently `app.ex:270-272`) delegates to `promote_session/2`.
2. `promote_session/2` writes `current_user`, calls
   `Sessions.Supervisor.promote_guest_session/3` when `session_pid` is a pid,
   updates `session_context.user` and `session_context.user_id`, navigates
   to `:main_menu`.
3. `session_replaced/2` opens an `Foglet.TUI.Modal` warning with
   `on_confirm/on_cancel` callbacks that emit `Command.quit()`.

---

### `lib/foglet_bbs/tui/screens/login/menu.ex` (new — per-mode reducer, event-driven)

**Analog:** existing `handle_menu_key/2` clauses in `login.ex:166-181`.

**Module shape** (D-14):

```elixir
defmodule Foglet.TUI.Screens.Login.Menu do
  alias Foglet.TUI.{Context, Effect}
  alias Foglet.TUI.Screens.Login.State, as: LoginState

  @spec handle_key(map(), map()) :: term()
  def handle_key(%{key: :char, char: c}, state) when c in ["l", "L"], do: ...
  def handle_key(%{key: :char, char: c}, state) when c in ["r", "R"], do: ...
  def handle_key(%{key: :char, char: c}, state) when c in ["f", "F"], do: ...
  def handle_key(%{key: :char, char: c}, state) when c in ["t", "T"], do: ...
  def handle_key(_key, _state), do: :no_match
end
```

**Move verbatim from `login.ex:166-181` plus** the helpers
`enter_login_form/1` (`:372-374`), `maybe_register/1` (`:376-384`),
`maybe_enter_reset_request/1` (`:388-390`), `enter_reset_consume/1`
(`:394-396`), and `registration_mode/1` (`:363-368`).

`Menu` exports **`handle_key/2`** only (no `handle_task_result/3` — there are
no `:menu`-targeted task results per D-16).

---

### `lib/foglet_bbs/tui/screens/login/login_form.ex` (new — per-mode reducer, request-response)

**Analog:** `login.ex:247-285` (`handle_form_key`, `handle_unlocked_form_key`)
plus the `submit_login/1` flow at `:491-513` and the `:login` task-result
handlers at `:83-95, 192-242`.

**Per-mode module exports both callbacks (D-14, D-16):**

```elixir
defmodule Foglet.TUI.Screens.Login.LoginForm do
  @spec handle_key(map(), map()) :: term()
  def handle_key(...), do: ...

  @spec handle_task_result(term(), map(), Foglet.TUI.Context.t()) ::
          {map(), [Foglet.TUI.Effect.t()]}
  def handle_task_result(...), do: ...
end
```

**`handle_key/2`** absorbs the existing key dispatch:

```elixir
# from login.ex:247-285
defp handle_form_key(key, state) do
  login_ss = LoginState.get(state)

  if Map.get(login_ss, :submitting?, false) do
    {:update, state, []}
  else
    handle_unlocked_form_key(key, state)
  end
end
```

Plus tab/enter/escape/text-forwarding clauses; no behavior change per D-13.

**`handle_task_result/3`** absorbs all three current `:login` task-result
clauses (`login.ex:83-95`) and the cascading `handle_login_result/2` machine
(`:192-242`) including `login_error_modal/3` and `unlock_login_form/1`.

---

### `lib/foglet_bbs/tui/screens/login/reset_request.ex` (new)

**Analog:** `login.ex:287-305` (`handle_reset_key`), `submit_reset_request/1`
(`:398-416`), `dispatch_reset_request/3` (`:424-442`), and the three
`:reset_request` task-result clauses (`:97-128`).

**Same `handle_key/2` + `handle_task_result/3` shape as LoginForm.**

---

### `lib/foglet_bbs/tui/screens/login/reset_consume.ex` (new)

**Analog:** `login.ex:313-340` (`handle_reset_consume_key`),
`submit_reset_consume/1` (`:466-489`), and the four `:reset_token` task-result
clauses (`:130-152`).

---

### `lib/foglet_bbs/posts.ex` (modify — delete `list_posts/1`)

**Pattern:** pure deletion of lines 83-97. No analog needed; the call sites
that consume `list_posts/1` are migrated separately (PostReader →
`list_reader_window/2`; tests deleted per D-23).

**SPEC R1 grep gate:** after deletion,
`grep -rn "\.list_posts\b" lib/ test/` must return zero hits.

---

### `lib/foglet_bbs/threads.ex` (modify — add arity-3 with `@page_size 50`)

**Analog:** `lib/foglet_bbs/posts.ex:99-153` — the `list_reader_window/2`
trailing-keyword shape (D-05).

**Trailing-opts pattern to copy** (from `posts.ex:106-110`):

```elixir
@spec list_reader_window(String.t(), keyword()) :: ReaderWindow.t()
def list_reader_window(thread_id, opts \\ []) do
  limit = normalize_reader_limit(Keyword.get(opts, :limit, 50))
  direction = normalize_reader_direction(Keyword.get(opts, :direction, :initial))
  # ...
end
```

**Defaulting helper pattern** (from `posts.ex:155-156`):

```elixir
defp normalize_reader_limit(limit) when is_integer(limit) and limit > 0, do: limit
defp normalize_reader_limit(_limit), do: 50
```

**Adapt for `Threads.list_threads/3`** (D-05, D-06, D-07):

```elixir
@page_size 50

@doc "Default page size for `list_threads/{1,2,3}`."
@spec default_page_size() :: pos_integer()
def default_page_size, do: @page_size

@doc """
List threads in a board, annotated with `:has_unread` for `user_id`.

Bounded by `@page_size` (#{@page_size}). Reserved keys (not yet implemented):

  * `:after`  — cursor for next-page (future cursor work)
  * `:before` — cursor for prev-page (future cursor work)

Phase 47 only consumes `:limit`.
"""
@spec list_threads(String.t(), String.t() | nil, keyword()) :: [ThreadEntry.t()]
def list_threads(board_id, user_id_or_nil, opts \\ [])

def list_threads(board_id, nil, opts) do
  # arity-1 path with limit
  limit = normalize_limit(Keyword.get(opts, :limit, @page_size))
  ...
end

def list_threads(board_id, user_id, opts) when is_binary(user_id) do
  limit = normalize_limit(Keyword.get(opts, :limit, @page_size))

  query =
    from t in Thread,
      left_join: trp in ReadPointer,
      on: trp.thread_id == t.id and trp.user_id == ^user_id,
      where: t.board_id == ^board_id,
      order_by: [desc: t.sticky, desc: t.last_post_at],
      limit: ^limit,        # NEW — enforce page bound at SQL layer
      select: %{...has_unread: ...}
  ...
end
```

**Existing arity-1 (`threads.ex:75-85`) and arity-2 (`:106-142`) delegate** to
arity-3 with `opts: []` (D-05). All current tests pass through unchanged.

**SPEC R3 acceptance:** `Ecto.Adapters.SQL.to_sql/3` shows `LIMIT 50`.
**SPEC R4 acceptance:** `grep -n "50" lib/foglet_bbs/threads.ex` returns only
the `@page_size 50` declaration line.

---

### `lib/foglet_bbs/tui/screens/post_reader.ex` (modify — `load_posts/2` → `list_reader_window/2`)

**Analog:** existing in-file consumers of `Posts.list_reader_window/2` already
present in `post_reader.ex` (the `load_direction/1` and
`selected_index_after_window_load/3` helpers at `:567-609` — Phase 44 D-13/D-14).

**Anchor mapping (D-02):**

```elixir
# from CONTEXT D-02
opts =
  cond do
    read_pointer_message_number ->
      [direction: :around, around_message_number: read_pointer_message_number]

    state.load_intent == :jump_last ->
      [direction: :last]

    true ->
      [direction: :initial]
  end

window = posts_mod.list_reader_window(load_thread_id, opts)
posts = window.posts  # or whatever ReaderWindow shape exposes
```

**Reuse without modification (D-04):** `selected_index_after_window_load/3` at
`:585-609` lands the selected index back on the read-pointer's
`message_number` after the windowed load. This is what makes SPEC R2's
"200 posts + pointer at 150" acceptance test pass.

**Do NOT (D-03):**
- Add a new `:read_pointer` direction keyword to `list_reader_window/2`.
- Have the screen call `Foglet.Threads.get_thread_read_pointer/2`. Read-pointer
  lookup remains in the load path where it already lives.

---

### `lib/foglet_bbs/tui/app.ex` (modify — drop below 400 lines)

**Strategy:** delegate-out (no behavior change). Replace the `:set_user`,
`:promote_session`, and `:session_replaced` clauses (60+ lines) with one-line
delegators to `App.SessionAlias`. Replace any inline `screen_state` map
manipulation (mostly already in `Routing` per D-19; check `app.ex` for any
remaining residual) with delegators to `App.ScreenStates`.

**Existing delegator pattern** (from `app.ex:76-114`) — one-line passthroughs:

```elixir
@spec current_route(t()) :: atom() | {atom(), map()}
def current_route(%__MODULE__{} = state), do: Routing.current_route(state)
```

Apply the same shape to the new modules.

**Size gate (R6, D-21):** `wc -l lib/foglet_bbs/tui/app.ex` must report < 400
(currently 483; need to remove ~84 net lines via the two extractions).

---

### `lib/foglet_bbs/tui/app/routing.ex` (modify)

**Pattern:** Per D-19, the inline manipulation at `routing.ex:53` (the body of
`put_screen_state/3`, etc.) moves to `App.ScreenStates`. `Routing` either:
- Calls `ScreenStates.put/3` from `Routing.put_screen_state/3` (preserving
  Routing's own delegator), or
- Re-aliases / removes its `screen_state_for/2` and `put_screen_state/3` if
  callers can be updated to call `ScreenStates` directly.

**Recommendation (D-19 hint):** Routing keeps its delegators (call sites at
`:84, 90, 116` etc.) but they now call into `ScreenStates`. This minimizes
diff churn outside the new module.

---

### `lib/foglet_bbs/tui/screens/login.ex` (modify — drop below 300 lines)

**Analog:** `lib/foglet_bbs/tui/screens/post_reader.ex` + `post_reader/render.ex`
+ `post_reader/state.ex` (Phase 43 PostReader pattern).

**Top-level `update/3` `:key` dispatch (D-15):** keep the four-way
`case LoginState.sub(state)` at `login.ex:157-164`; each branch becomes a
one-line delegate:

```elixir
defp reduce_key(state, key) do
  case LoginState.sub(state) do
    :login_form -> LoginForm.handle_key(key, state)
    :reset_request -> ResetRequest.handle_key(key, state)
    :reset_consume -> ResetConsume.handle_key(key, state)
    _ -> Menu.handle_key(key, state)
  end
end
```

**Top-level task-result dispatch (D-16):** route by **task atom**, not by
`:sub`:

```elixir
def update({:task_result, :login, result}, ls, ctx),
  do: LoginForm.handle_task_result(result, ls, ctx)

def update({:task_result, :reset_request, result}, ls, ctx),
  do: ResetRequest.handle_task_result(result, ls, ctx)

def update({:task_result, :reset_token, result}, ls, ctx),
  do: ResetConsume.handle_task_result(result, ls, ctx)
```

**Catch-all** at `login.ex:154` (`def update(_message, local_state, %Context{}), do: {local_state, []}`)
stays at the top level.

**Do NOT (D-13):** convert `LoginState` to a tagged-union struct. Keep the map
shape; existing `Map.merge` writes at `:101, 116, 127, 139, 147` survive
unchanged.

**`.dialyzer_ignore.exs` (D-17):** if the `:contract_supertype` entry for
`login.ex` is naturally resolved by the refactor, remove it; otherwise refresh
its inline rationale citing Phase 47. Do not chase by adding speculative
`@spec`s.

**Size gate (R7):** `wc -l lib/foglet_bbs/tui/screens/login.ex` must report
< 300 (currently 606; ~310 lines move out into the four mode modules).

---

### `lib/foglet_bbs/tui/screens/login/state.ex` (modify — keep map shape, add nothing)

**Analog:** self. Per D-13/D-14, the existing constructors (`default/0`,
`login_form/0`, `reset_request/0`, `reset_consume/0` at `:38-83`) already
serve the per-mode reducer modules. **No new constructors are added.**

**Do NOT** rewrite to a tagged-union struct — locked by D-13.

---

### `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex` (modify — drop V1)

**Pattern:** pure deletion (D-10 step 2 + step 5).

**Delete:**
- The `Normalizer` alias at `:27` (the explicit alias).
- `defp normalize_chrome(_legacy_title, state)` at `:191-196` (the legacy
  title-string clause).
- The `Normalizer.commands/1` fallback branch at `:198-204` (the
  `command_groups/1` else-arm). After deletion, `command_groups/1` reduces
  to `if grouped_commands?(commands), do: CommandBar.normalize_groups(commands), else: []`
  or simply asserts the new contract.

**Preserve:**
- The `defp normalize_chrome(%{} = chrome, state)` map clause at `:185-189`
  (the V2 path).
- All border-segment / chrome-model rendering at `:42-178` — unchanged.

---

### `lib/foglet_bbs/tui/widgets/chrome/status_bar.ex` (modify — drop legacy-title arity)

**Pattern:** delete the `legacy_title/1` clause at `:101` and the `legacy_title`
fallthroughs at `:91-99`. Also remove the dispatch line `def render(state, title), do: render(state, title, [])`
at `:37` if call sites all migrate to the V2 `render/3` form (verify via
`grep -rn "StatusBar.render" lib/ test/`).

**Preserve:** `status_atoms/1` (`:71-79`) — used by `ScreenFrame` and unrelated
to V1.

---

### `lib/foglet_bbs/tui/widgets/chrome/key_bar.ex` (DELETE)

**Pattern:** file deletion (D-10 step 3). After step 2 removes the
`Normalizer.commands/1` fallback in `screen_frame.ex`, `KeyBar` is unreferenced
(its body at `:23-25` is just a `Normalizer → CommandBar` shim).

---

### `lib/foglet_bbs/tui/widgets/chrome/normalizer.ex` (DELETE)

**Pattern:** file deletion (D-10 step 4). After `KeyBar` is deleted and
`screen_frame.ex` no longer aliases `Normalizer`, no consumers remain.

**SPEC R5 acceptance:** `lib/foglet_bbs/tui/widgets/chrome/normalizer.ex`
no longer exists.

---

### Five screen call sites — V1 → V2 grouped command bars

**Analog (concrete V2 emission):** `lib/foglet_bbs/tui/screens/sysop/render.ex:52-79`.

**Pattern to copy** (from `sysop/render.ex:61-79`):

```elixir
defp sysop_commands(ss, jump_hint) do
  base = [
    %{
      label: "System",
      commands: [%{key: "Q", label: "Back", priority: 0}]
    },
    %{
      label: "Tabs",
      commands: [
        %{key: "←/→", label: "Tab", priority: 10},
        %{key: jump_hint, label: "Jump", priority: 10}
      ]
    }
  ]
  # ...
end
```

**Migration table:**

| Call site | Current V1 emission | Suggested V2 grouping |
|-----------|---------------------|------------------------|
| `board_list.ex:226-231` | `[{"j/k", "Select"}, {"←/→", "Collapse/Expand"}, {"Enter", "Open"}, {"s/u", "Subscribe/Unsubscribe"}, {"Q", "Back"}]` | `[%{label: "Navigate", commands: [...j/k, ←/→, Enter...]}, %{label: "Actions", commands: [...s/u...]}, %{label: "System", commands: [%{key: "Q", label: "Back", priority: 0}]}]` |
| `thread_list.ex:132-137` | `[{"j/k", "Select"}, {"Enter", "Open"}, {"C", "Compose"}, {"Q", "Back"}]` | Navigate / Actions / System |
| `moderation.ex:175` | `[{"Q", "Back"}]` | `[%{label: "System", commands: [%{key: "Q", label: "Back", priority: 0}]}]` |
| `moderation.ex:201-207` (`key_list/1`) | `[{"←/→", "Tab"}, {jump_hint, "Jump"}, {"Q", "Back"}]` | Tabs + System (mirror sysop's pattern at sysop/render.ex:67-73 exactly) |
| `account/render.ex:43-52` (`key_bar/1`) | `[{"←/→", "Tab"}, {jump_hint, "Jump"}, {"Tab", "Field"}, {"Enter", "Save"}, {"Esc", "Cancel"}, {"Ctrl+Q", "Back"}]` | Tabs + Field + Save + System |
| `post_reader/render.ex:31-38` | `[{"N", "Next"}, {"P", "Prev"}, {"J", "Scroll ↓"}, {"K", "Scroll ↑"}, {"R", "Reply"}, {"Q", "Back"}]` | Navigate (N, P, J, K) / Actions (R) / System (Q) |

**Group/priority hints** — copy the priority-tier conventions used by
`sysop/render.ex`:
- System group: `priority: 0`
- Tabs / Navigate: `priority: 10`
- Actions: `priority: 30` or `5` (sysop uses `5` for the Revoke/Retry
  conditional commands at lines 99, 116)

**SPEC R5 acceptance grep:** after each call-site migration,
`grep -rn "{[^,]\\+, *\"[^\"]\\+\"}" lib/foglet_bbs/tui/screens/`
must return zero hits matching the legacy keybar tuple shape (D-12).

---

### Test fixture migrations

**`test/foglet_bbs/tui/screens/post_reader_test.exs` (modify — D-22)**

Delete the `list_posts/1` implementations at lines 11, 62, 78, 114
(including `BoundedFakePosts.list_posts/1` regression-guard at :114 which
itself contains `.list_posts` and would fail SPEC R1's grep). Migrate fixture
mods to implement only `list_reader_window/2`.

**Pattern for the fixture replacement** — fixture mods already implement the
windowed contract; this is a deletion-only migration. Cross-reference the
fixture mod patterns at `routing_test.exs:10-44` (the `SampleScreen` /
`SampleScreen.State` shape) for fixture-mod style.

**`test/foglet_bbs/tui/app_test.exs` (modify — D-22)**

Delete the `list_posts/1` impls at `:55-89`.

**`test/foglet_bbs/posts_test.exs:410-450` (DELETE — D-23)**

Delete the `list_posts/1` tombstone-semantics tests entirely. Phase 44
D-13/D-14 already covers tombstone behavior through `list_reader_window/2`.

**Note:** `test/foglet_bbs/posts_test.exs` does not currently exist at the
working tree root path — verify against the actual test path before deleting
(`grep -rn "list_posts" test/` to find).

---

## Shared Patterns

### Trailing-keyword opts on context functions

**Source:** `lib/foglet_bbs/posts.ex:106-110, 155-162` (Phase 44 precedent).
**Apply to:** `Foglet.Threads.list_threads/3`.

```elixir
@spec list_threads(String.t(), String.t() | nil, keyword()) :: [ThreadEntry.t()]
def list_threads(board_id, user_id, opts \\ []) do
  limit = normalize_limit(Keyword.get(opts, :limit, @page_size))
  # ...
end

defp normalize_limit(limit) when is_integer(limit) and limit > 0, do: limit
defp normalize_limit(_limit), do: @page_size
```

Document `:after` and `:before` in `@doc` as reserved-for-future-use; do NOT
validate or reject (D-06).

### Public delegators on parent + concrete logic in child

**Source:** `lib/foglet_bbs/tui/app.ex:76-114` (Phase 42 `App.Routing`
delegator boundary).
**Apply to:** all new `App.ScreenStates` and `App.SessionAlias` delegators
on `App`.

```elixir
@spec current_route(t()) :: atom() | {atom(), map()}
def current_route(%__MODULE__{} = state), do: Routing.current_route(state)
```

### Per-mode reducer module shape (Phase 43 sibling-module pattern)

**Source:** `lib/foglet_bbs/tui/screens/post_reader/{state.ex, render.ex}`
(Phase 43); also exemplified by the existing private mode helpers in
`login.ex:166-340`.
**Apply to:** all four `Login.{Menu, LoginForm, ResetRequest, ResetConsume}`
modules.

Each per-mode module exports:

- `handle_key/2` — keyboard event reducer (all four modules).
- `handle_task_result/3` — task-result reducer (LoginForm, ResetRequest,
  ResetConsume only — D-16).

Sub-state constructors stay in `Login.State` (D-14).

### V2 grouped command emission

**Source:** `lib/foglet_bbs/tui/screens/sysop/render.ex:52-79` (canonical V2
example).
**Apply to:** all five V1→V2 screen migrations.

Group label conventions and priority tiers are documented inline in
`sysop/render.ex`; copy that vocabulary verbatim to keep the codebase's
chrome-vocabulary consistent.

### App helper test scaffolding

**Source:** `test/foglet_bbs/tui/app/{routing,modal}_test.exs`
**Apply to:** `screen_states_test.exs`, `session_alias_test.exs`.

The `defp state(attrs \\ %{}), do: struct!(App, Map.merge(%{...defaults...}, attrs))`
pattern at `routing_test.exs:51-75` and `modal_test.exs:35-55` is the
established scaffolding shape.

## No Analog Found

None — every Phase 47 file has an explicit Phase-precedent analog (Phase 42
for App.* extractions, Phase 43 for PostReader-pattern decomposition, Phase 44
for `list_reader_window/2` trailing-keyword shape, plus in-file V2 grouped
emission examples in `sysop/render.ex`).

## Metadata

**Analog search scope:**
- `lib/foglet_bbs/tui/app/`
- `lib/foglet_bbs/tui/screens/`
- `lib/foglet_bbs/tui/widgets/chrome/`
- `lib/foglet_bbs/posts.ex`, `lib/foglet_bbs/threads.ex`
- `test/foglet_bbs/tui/app/`

**Files scanned:** 17 (read with targeted offsets where files exceeded
2,000 lines is N/A — all read files were under that bound).

**Pattern extraction date:** 2026-04-30
