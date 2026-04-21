# Phase 03: Verify - Pattern Map

**Mapped:** 2026-04-21
**Files analyzed:** 6
**Analogs found:** 6 / 6

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `lib/foglet_bbs/tui/screens/verify.ex` | component | event-driven | `lib/foglet_bbs/tui/screens/register.ex` | role-match |
| `lib/foglet_bbs/tui/app.ex` | controller | event-driven | `lib/foglet_bbs/tui/app.ex` | exact |
| `lib/foglet_bbs/tui/screens/login.ex` | component | request-response | `lib/foglet_bbs/tui/screens/login.ex` | exact |
| `lib/foglet_bbs/tui/screens/register.ex` | component | request-response | `lib/foglet_bbs/tui/screens/register.ex` | exact |
| `test/foglet_bbs/tui/screens/verify_test.exs` | test | event-driven | `test/foglet_bbs/tui/screens/register_test.exs` | role-match |
| `test/foglet_bbs/tui/layout_smoke_test.exs` | test | request-response | `test/foglet_bbs/tui/layout_smoke_test.exs` | exact |

## Pattern Assignments

### `lib/foglet_bbs/tui/screens/verify.ex` (component, event-driven)

**Primary analog:** `lib/foglet_bbs/tui/screens/register.ex`

**Imports + module layout pattern** (`register.ex` lines 23-36):
```elixir
alias Foglet.{Accounts, Config}
alias Foglet.TUI.Theme
alias Foglet.TUI.Widgets.Chrome.ScreenFrame
alias Foglet.TUI.Widgets.Input.TextInput

import Raxol.Core.Renderer.View

# §2 Module attributes

@log_verify_codes Application.compile_env(:foglet_bbs, :log_verify_codes, false)
```

**Public initializer pattern** (`register.ex` lines 36-64):
```elixir
# §3 init_screen_state/1 (PUBLIC — AUDIT-19, D-05)

@doc """
Returns a minimal "open"-mode stub suitable for pre-populating
`screen_state[:register]` (e.g. during screen-transition bootstrapping).
"""
@spec init_screen_state(keyword()) :: map()
def init_screen_state(_opts \\ []) do
  %{
    mode: "open",
    step: :combined,
    focused_field: :handle,
    invite_code_input: TextInput.init([]),
    handle_input: TextInput.init([]),
    email_input: TextInput.init([]),
    password_input: TextInput.init(mask_char: "*"),
    confirm_input: TextInput.init(mask_char: "*"),
    collected: %{},
    error: nil
  }
end
```

**Private screen-state plumbing pattern** (`register.ex` lines 294-305):
```elixir
defp get_register_ss(state) do
  Map.get(state.screen_state || %{}, :register) || init_screen_state_for(state)
end

defp put_register_ss(state, reg) do
  new_screen_state = Map.put(state.screen_state || %{}, :register, reg)
  %{state | screen_state: new_screen_state}
end

defp clear_register_ss(state) do
  new_screen_state = Map.delete(state.screen_state || %{}, :register)
  %{state | screen_state: new_screen_state}
end
```

**Preserve current Verify render + event behavior** (`verify.ex` lines 35-67, 175-219, 239-267):
```elixir
@spec render(map()) :: any()
def render(state) do
  vs =
    state.verify_state ||
      %{buffer: "", attempts: 0, cooldown_until: nil, resend_cooldown_until: nil}

  theme = Theme.from_state(state)
  ...
  ScreenFrame.render(state, "Verify Email", content, [
    {"Enter", "Submit"},
    {"Backspace", "Delete"},
    {"R", "Resend code"},
    {"Esc", "Cancel"}
  ])
end

case Accounts.verify_email_code(state.current_user, vs.buffer) do
  {:ok, confirmed} ->
    {%{state | current_user: confirmed, current_screen: :main_menu, verify_state: nil}, []}

  {:error, :invalid_code} ->
    new_attempts = vs.attempts + 1
    ...
    {%{state | modal: modal, verify_state: new_vs}, []}
end

new_vs = %{
  vs
  | buffer: "",
    attempts: 0,
    cooldown_until: nil,
    resend_cooldown_until: DateTime.add(now, cooldown_seconds, :second)
}
```

**Migration implication:** copy the `register.ex` initializer/helper structure, but keep Verify’s existing slot-rendering, cooldown, resend, and modal behavior unchanged while swapping `verify_state` reads/writes to `screen_state[:verify]`.

---

### `lib/foglet_bbs/tui/app.ex` (controller, event-driven)

**Primary analog:** `lib/foglet_bbs/tui/app.ex`

**Top-level state shape pattern** (`app.ex` lines 39-56, 58-73):
```elixir
@type t :: %__MODULE__{
        current_screen: screen(),
        current_user: Foglet.Accounts.User.t() | nil,
        ...
        modal: map() | nil,
        screen_state: map(),
        ...
        subscribed_topics: MapSet.t()
      }

defstruct current_screen: :login,
          current_user: nil,
          ...
          modal: nil,
          screen_state: %{},
          ...
          subscribed_topics: MapSet.new()
```

**Verify dispatch pattern** (`app.ex` lines 352-359):
```elixir
defp do_update({:register_wizard, event}, state) do
  Screens.Register.handle_wizard_event(event, state)
end

defp do_update({:verify_event, event}, state) do
  Screens.Verify.handle_verify_event(event, state)
end
```

**Key routing pattern** (`app.ex` lines 327-348):
```elixir
true ->
  screen_module = screen_module_for(state.current_screen)

  case screen_module.handle_key(key_event, state) do
    {:update, new_state, commands} ->
      process_screen_commands(new_state, commands)

    :no_match ->
      global_key_handler(key_event, state)
  end
```

**Planner guidance:** remove `verify_state` from the struct/type/defaults, but keep the dedicated `{:verify_event, event}` dispatch hook intact.

---

### `lib/foglet_bbs/tui/screens/login.ex` (component, request-response)

**Primary analog:** `lib/foglet_bbs/tui/screens/login.ex`

**Transition-without-seeding pattern** (`login.ex` lines 230-237):
```elixir
defp maybe_register(state) do
  case registration_mode(state) do
    "disabled" ->
      :no_match

    _mode ->
      {:update, %{state | current_screen: :register}, []}
  end
end
```

**Clear screen-owned state on terminal success** (`login.ex` lines 284-285):
```elixir
defp handle_auth_success(state, user, :main_menu) do
  {:update, %{state | screen_state: %{}}, [{:promote_session, user}]}
end
```

**Existing verify-entry code to replace** (`login.ex` lines 288-305):
```elixir
defp start_verify_flow(state, user) do
  case Accounts.build_verify_code(user) do
    {:ok, code} ->
      maybe_log_verify_code(user, code)

      {:update,
       %{
         state
         | current_user: user,
           current_screen: :verify,
           screen_state: %{},
           verify_state: %{
             buffer: "",
             attempts: 0,
             cooldown_until: nil,
             resend_cooldown_until: nil
           }
       }, []}
```

**Planner guidance:** keep the `Accounts.build_verify_code/1` and screen transition flow, but make it look like `maybe_register/1` or the `:main_menu` success branch by not pre-seeding a top-level verify map.

---

### `lib/foglet_bbs/tui/screens/register.ex` (component, request-response)

**Primary analog:** `lib/foglet_bbs/tui/screens/register.ex`

**Verify transition branch to simplify** (`register.ex` lines 396-412):
```elixir
defp handle_register_success(state, user, :verify, code) do
  maybe_log_verify_code(user, code)

  new_state = %{
    state
    | current_user: user,
      current_screen: :verify,
      verify_state: %{
        buffer: "",
        attempts: 0,
        cooldown_until: nil,
        resend_cooldown_until: nil
      }
  }

  {:update, clear_register_ss(new_state), []}
end
```

**Pattern to preserve from sibling branch** (`register.ex` lines 414-416):
```elixir
defp handle_register_success(state, user, :main_menu, _code) do
  new_state = %{state | current_user: user}
  {:update, clear_register_ss(new_state), [{:promote_session, user}]}
end
```

**Shared helper-clearing pattern** (`register.ex` lines 303-305):
```elixir
defp clear_register_ss(state) do
  new_screen_state = Map.delete(state.screen_state || %{}, :register)
  %{state | screen_state: new_screen_state}
end
```

**Planner guidance:** retain the register success branching and `maybe_log_verify_code/2`, but make the `:verify` branch stop constructing the old default verify map.

---

### `test/foglet_bbs/tui/screens/verify_test.exs` (test, event-driven)

**Primary analog:** `test/foglet_bbs/tui/screens/register_test.exs`

**Base-state fixture pattern** (`register_test.exs` lines 14-25):
```elixir
# Pre-init screen_state-free state — register.ex self-initializes on first
# get_register_ss/1 call (D-06). screen_state is an empty map.
defp base_state(mode \\ "open") do
  %Foglet.TUI.App{
    current_screen: :register,
    current_user: nil,
    session_context: %{registration_mode: mode},
    terminal_size: {80, 24},
    screen_state: %{}
  }
  |> Map.from_struct()
end
```

**Assert screen-state clearing through public behavior** (`register_test.exs` lines 299-305):
```elixir
describe "handle_wizard_event/2 — {:cancel}" do
  test "clears screen_state[:register] and transitions to :login" do
    state = combined_state(handle: "alice")
    {new_state, []} = Register.handle_wizard_event({:cancel}, state)
    assert new_state.current_screen == :login
    assert Map.get(new_state.screen_state || %{}, :register) == nil
  end
end
```

**Current verify fixture shape to migrate** (`verify_test.exs` lines 13-23, 71-87):
```elixir
state =
  %Foglet.TUI.App{
    current_screen: :verify,
    current_user: user,
    session_context: %{},
    terminal_size: {80, 24},
    verify_state: %{buffer: "", attempts: 0, cooldown_until: nil, resend_cooldown_until: nil}
  }
  |> Map.from_struct()

{new_state, _} = Verify.handle_verify_event({:submit}, s)
assert new_state.current_screen == :main_menu
assert new_state.current_user.confirmed_at != nil
assert new_state.verify_state == nil
```

**Planner guidance:** follow the `register_test.exs` style by putting Verify data under `screen_state: %{verify: ...}` and asserting `Map.get(new_state.screen_state || %{}, :verify) == nil` on cancel/success paths.

---

### `test/foglet_bbs/tui/layout_smoke_test.exs` (test, request-response)

**Primary analog:** `test/foglet_bbs/tui/layout_smoke_test.exs`

**Existing screen_state fixture pattern** (`layout_smoke_test.exs` lines 79-92):
```elixir
state = %App{
  screen_state: %{
    login: %{
      sub: :login_form,
      focused_field: :handle,
      handle_input: TI.init(value: "alice"),
      password_input: TI.init(value: "", mask_char: "*"),
      error: nil
    }
  },
  terminal_size: {80, 24}
}
```

**Current Verify smoke fixture to migrate** (`layout_smoke_test.exs` lines 321-328, 509-516):
```elixir
state = %App{
  current_screen: :verify,
  current_user: %{id: "u1", handle: "alice"},
  verify_state: %{buffer: "XK7", attempts: 0, cooldown_until: nil},
  terminal_size: {80, 24},
  screen_state: %{}
}

Verify.render(%App{
  current_screen: :verify,
  current_user: %{id: "u1", handle: "alice"},
  verify_state: %{buffer: "XK7", attempts: 0, cooldown_until: nil},
  terminal_size: {80, 24},
  screen_state: %{}
})
```

**Planner guidance:** rewrite the Verify fixtures to match the rest of this file’s `screen_state` convention, and include `resend_cooldown_until: nil` so the fixture matches the locked Verify state shape.

## Shared Patterns

### Screen-Owned State Helpers
**Source:** `lib/foglet_bbs/tui/screens/register.ex` lines 294-305
**Apply to:** `verify.ex`
```elixir
defp get_register_ss(state) do
  Map.get(state.screen_state || %{}, :register) || init_screen_state_for(state)
end

defp put_register_ss(state, reg) do
  new_screen_state = Map.put(state.screen_state || %{}, :register, reg)
  %{state | screen_state: new_screen_state}
end

defp clear_register_ss(state) do
  new_screen_state = Map.delete(state.screen_state || %{}, :register)
  %{state | screen_state: new_screen_state}
end
```

### Public Initializer Contract
**Source:** `lib/foglet_bbs/tui/screens/login.ex` lines 46-47 and `lib/foglet_bbs/tui/screens/register.ex` lines 50-64
**Apply to:** `verify.ex`
```elixir
@spec init_screen_state(keyword()) :: map()
def init_screen_state(_opts), do: %{sub: :menu}
```

```elixir
@spec init_screen_state(keyword()) :: map()
def init_screen_state(_opts \\ []) do
  %{...}
end
```

### App-Level Event Dispatch
**Source:** `lib/foglet_bbs/tui/app.ex` lines 352-359
**Apply to:** `app.ex`, `verify.ex`
```elixir
defp do_update({:register_wizard, event}, state) do
  Screens.Register.handle_wizard_event(event, state)
end

defp do_update({:verify_event, event}, state) do
  Screens.Verify.handle_verify_event(event, state)
end
```

### Modal-First Feedback
**Source:** `lib/foglet_bbs/tui/screens/verify.ex` lines 181-186, 217-218, 242-267
**Apply to:** `verify.ex`, `verify_test.exs`
```elixir
cooldown?(vs) ->
  {%{state | modal: cooldown_modal(vs.cooldown_until, "Too many attempts.")}, []}

modal = %{type: :error, message: "Invalid code (#{new_attempts}/#{@max_attempts})."}
{%{state | modal: modal, verify_state: new_vs}, []}

modal = %{type: :info, message: "A new code has been sent."}
```

## No Analog Found

None.

## Metadata

**Analog search scope:** `lib/foglet_bbs/tui/screens`, `lib/foglet_bbs/tui/app.ex`, `test/foglet_bbs/tui`
**Files scanned:** 9
**Pattern extraction date:** 2026-04-21
