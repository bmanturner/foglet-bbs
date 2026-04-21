# Phase 2: Register — Pattern Map

**Mapped:** 2026-04-21
**Files analyzed:** 5 (register.ex rewrite, app.ex two-block edit, login.ex one-line deletion, register_test.exs rewrite, TextInput read-only contract)
**Analogs found:** 5 / 5

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `lib/foglet_bbs/tui/screens/register.ex` | screen (controller) | request-response + event-driven wizard | `lib/foglet_bbs/tui/screens/login.ex` | exact (same architecture, same Phase-1 post-refactor patterns) |
| `lib/foglet_bbs/tui/app.ex` (lines 53-56, 354-361) | application shell | request-response dispatch | `lib/foglet_bbs/tui/app.ex` (existing, self-analog) | exact (minimal field removal + dispatch preservation) |
| `lib/foglet_bbs/tui/screens/login.ex` (`maybe_register/1`) | screen | request-response | `lib/foglet_bbs/tui/screens/login.ex` (other functions) | exact (one-line deletion, no new pattern needed) |
| `test/foglet_bbs/tui/screens/register_test.exs` | test | — | `test/foglet_bbs/tui/screens/login_test.exs` | exact (same fixture + assertion patterns) |
| `lib/foglet_bbs/tui/widgets/input/text_input.ex` | widget (read-only contract) | — | — | reference only, not modified |

---

## Pattern Assignments

### `lib/foglet_bbs/tui/screens/register.ex` (screen, request-response + wizard)

**Analog:** `lib/foglet_bbs/tui/screens/login.ex`

**Imports pattern** (login.ex lines 34-39):
```elixir
alias Foglet.{Accounts, Config}
alias Foglet.TUI.Theme
alias Foglet.TUI.Widgets.Chrome.ScreenFrame
alias Foglet.TUI.Widgets.Input.TextInput

import Raxol.Core.Renderer.View
```
Register adds `alias Foglet.Config` (already present) and keeps `@modes` and `@log_verify_codes` module attributes. The `alias Foglet.Accounts` is separate in the current register.ex — merge to `alias Foglet.{Accounts, Config}` to match login.

---

#### Pattern: `init_screen_state/1` (AUDIT-19) — no analog in login (login returns `%{sub: :menu}`)

Register's version is the richer case: eagerly allocates four TextInput structs, defaulting to mode `"open"` / step `:combined`. The public function satisfies AUDIT-19; the mode-aware private helper (`init_screen_state_for/1`) provides the real bootstrap on first `get_register_ss/1` call.

```elixir
# COPY THIS EXACTLY — login.ex lines 46-47 give the @spec signature shape
@spec init_screen_state(keyword()) :: map()
def init_screen_state(_opts \\ []) do
  %{
    mode:              "open",
    step:              :combined,
    focused_field:     :handle,
    invite_code_input: TextInput.init([]),
    handle_input:      TextInput.init([]),
    email_input:       TextInput.init([]),
    password_input:    TextInput.init(mask_char: "*"),
    confirm_input:     TextInput.init(mask_char: "*"),
    collected:         %{},
    error:             nil
  }
end
```

Private companion for mode-aware init (called from `get_register_ss/1` on cache miss):
```elixir
defp init_screen_state_for(state) do
  mode    = registration_mode(state)
  step    = if mode == "invite_only", do: :invite_code, else: :combined
  focused = if step == :invite_code,  do: :invite_code, else: :handle
  %{
    mode:              mode,
    step:              step,
    focused_field:     focused,
    invite_code_input: TextInput.init([]),
    handle_input:      TextInput.init([]),
    email_input:       TextInput.init([]),
    password_input:    TextInput.init(mask_char: "*"),
    confirm_input:     TextInput.init(mask_char: "*"),
    collected:         %{},
    error:             nil
  }
end
```

---

#### Pattern: `get_*/put_*/clear_*` state plumbing — copy from login.ex lines 156-164

```elixir
# login.ex lines 156-164 — exact template, rename :login → :register
defp get_login_ss(state) do
  Map.get(state.screen_state || %{}, :login) ||
    %{focused_field: nil, handle_input: nil, password_input: nil, error: nil}
end

defp put_login_ss(state, login_ss) do
  new_screen_state = Map.put(state.screen_state || %{}, :login, login_ss)
  %{state | screen_state: new_screen_state}
end
```

Register equivalents:
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

---

#### Pattern: `render/1` dispatch by sub-state — copy from login.ex lines 50-66

```elixir
# login.ex lines 50-66
def render(state) do
  mode = registration_mode(state)
  sub  = sub_state(state)
  theme = Theme.from_state(state)

  content =
    column style: %{gap: 0} do
      [
        case sub do
          :login_form -> render_login_form(state, theme)
          _           -> render_menu(mode, theme)
        end
      ]
    end

  ScreenFrame.render(state, "Login", content, keys_for(sub, mode))
end
```

Register's `render/1` dispatches by `reg.step` instead of `sub`:
```elixir
def render(state) do
  reg   = get_register_ss(state)
  theme = Theme.from_state(state)

  content =
    column style: %{gap: 0} do
      [
        case reg.step do
          :invite_code -> render_invite_step(state, theme)
          :combined    -> render_combined_step(state, theme)
        end
      ]
    end

  ScreenFrame.render(state, "Register", content, keys_for(reg.step))
end
```

---

#### Pattern: `handle_key/2` top-level routing — copy from login.ex lines 68-75

```elixir
# login.ex lines 68-75
@spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
def handle_key(key, state) do
  case sub_state(state) do
    :login_form -> handle_form_key(key, state)
    _           -> handle_menu_key(key, state)
  end
end
```

Register routes by step instead of sub:
```elixir
@spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
def handle_key(key, state) do
  reg = get_register_ss(state)
  case reg.step do
    :invite_code -> handle_invite_key(key, state)
    :combined    -> handle_combined_key(key, state)
  end
end
```

The Escape clause must be extracted BEFORE the step dispatch (matches both steps):
```elixir
def handle_key(%{key: :escape}, state) do
  {:update, clear_register_ss(%{state | current_screen: :login}), []}
end
```

---

#### Pattern: Tab cycling focus — extend login.ex lines 94-99

```elixir
# login.ex lines 94-99 (two-field version)
defp handle_form_key(%{key: :tab}, state) do
  login_ss = get_login_ss(state)
  new_focused = if login_ss.focused_field == :handle, do: :password, else: :handle
  new_login_ss = %{login_ss | focused_field: new_focused}
  {:update, put_login_ss(state, new_login_ss), []}
end
```

Register's four-field version uses a module attribute cycle list:
```elixir
@focus_cycle [:handle, :email, :password, :confirm_password]

defp next_field(current) do
  idx = Enum.find_index(@focus_cycle, &(&1 == current)) || 0
  Enum.at(@focus_cycle, rem(idx + 1, length(@focus_cycle)))
end

defp handle_combined_key(%{key: :tab}, state) do
  reg     = get_register_ss(state)
  new_reg = %{reg | focused_field: next_field(reg.focused_field), error: nil}
  {:update, put_register_ss(state, new_reg), []}
end
```

---

#### Pattern: Enter advances focus or submits — copy from login.ex lines 102-111

```elixir
# login.ex lines 102-111
defp handle_form_key(%{key: :enter}, state) do
  login_ss = get_login_ss(state)
  if login_ss.focused_field == :password do
    submit_login(state)
  else
    new_login_ss = %{login_ss | focused_field: :password}
    {:update, put_login_ss(state, new_login_ss), []}
  end
end
```

Register's combined-step Enter (last field is `:confirm_password`; passwords compared first):
```elixir
defp handle_combined_key(%{key: :enter}, state) do
  reg = get_register_ss(state)
  case reg.focused_field do
    :confirm_password ->
      validate_and_submit(reg, state)
    field ->
      new_reg = %{reg | focused_field: next_field(field), error: nil}
      {:update, put_register_ss(state, new_reg), []}
  end
end

defp validate_and_submit(reg, state) do
  pw  = reg.password_input.raxol_state.value
  cpw = reg.confirm_input.raxol_state.value
  if pw == cpw do
    submit(reg, state)
  else
    new_reg = %{reg | error: "Passwords do not match."}
    {:update, put_register_ss(state, new_reg), []}
  end
end
```

---

#### Pattern: Everything-else delegates to focused TextInput — copy from login.ex lines 120-136

```elixir
# login.ex lines 120-136
defp handle_form_key(event, state) do
  {new_input, _action} = TextInput.handle_event(event, focused_input(state))
  {:update, update_focused_input(state, new_input), []}
end

defp focused_input(state) do
  login_ss = get_login_ss(state)
  focused  = Map.get(login_ss, :focused_field, :handle)
  Map.get(login_ss, input_key(focused))
end

defp update_focused_input(state, new_input) do
  login_ss  = get_login_ss(state)
  focused   = Map.get(login_ss, :focused_field, :handle)
  new_login_ss = Map.put(login_ss, input_key(focused), new_input)
  put_login_ss(state, new_login_ss)
end

defp input_key(:handle),   do: :handle_input
defp input_key(:password), do: :password_input
```

Register catch-all (both steps share the same delegation shape):
```elixir
defp handle_combined_key(event, state) do
  {new_input, _action} = TextInput.handle_event(event, focused_input(state))
  {:update, update_focused_input(state, new_input), []}
end

defp focused_input(state) do
  reg     = get_register_ss(state)
  focused = Map.get(reg, :focused_field, :handle)
  Map.get(reg, input_key(focused))
end

defp update_focused_input(state, new_input) do
  reg     = get_register_ss(state)
  focused = Map.get(reg, :focused_field, :handle)
  new_reg = Map.put(reg, input_key(focused), new_input)
  put_register_ss(state, new_reg)
end

defp input_key(:invite_code),      do: :invite_code_input
defp input_key(:handle),           do: :handle_input
defp input_key(:email),            do: :email_input
defp input_key(:password),         do: :password_input
defp input_key(:confirm_password), do: :confirm_input
```

---

#### Pattern: Inline label + TextInput row render — copy from login.ex lines 183-216

```elixir
# login.ex lines 183-216 — the exact row/column DSL idiom
defp render_login_form(state, theme) do
  login_ss = get_login_ss(state)
  focused  = Map.get(login_ss, :focused_field, :handle)

  handle_label_fg    = if focused == :handle,   do: theme.accent.fg, else: theme.primary.fg
  handle_label_style = if focused == :handle,   do: [:bold],         else: []
  password_label_fg  = if focused == :password, do: theme.accent.fg, else: theme.primary.fg
  password_label_style = if focused == :password, do: [:bold], else: []

  error_items =
    if login_ss.error do
      [text(""), text(login_ss.error, fg: theme.error.fg, style: [:bold])]
    else
      []
    end

  column style: %{gap: 0} do
    [
      row style: %{gap: 0} do
        [
          text("Handle:   ", fg: handle_label_fg, style: handle_label_style),
          TextInput.render(login_ss.handle_input, bordered: false, theme: theme)
        ]
      end,
      row style: %{gap: 0} do
        [
          text("Password: ", fg: password_label_fg, style: password_label_style),
          TextInput.render(login_ss.password_input, bordered: false, theme: theme)
        ]
      end
    ] ++ error_items
  end
end
```

Register's combined step (4 fields) uses an `Enum.map` loop to keep LoC down:
```elixir
defp render_combined_step(state, theme) do
  reg     = get_register_ss(state)
  focused = reg.focused_field

  fields = [
    {:handle,           "Handle:           ", reg.handle_input},
    {:email,            "Email:            ", reg.email_input},
    {:password,         "Password:         ", reg.password_input},
    {:confirm_password, "Confirm password: ", reg.confirm_input}
  ]

  rows =
    Enum.map(fields, fn {field, label, input} ->
      fg = if focused == field, do: theme.accent.fg, else: theme.primary.fg
      st = if focused == field, do: [:bold],         else: []
      row style: %{gap: 0} do
        [text(label, fg: fg, style: st), TextInput.render(input, bordered: false, theme: theme)]
      end
    end)

  error_items =
    if reg.error do
      [text(""), text(reg.error, fg: theme.error.fg, style: [:bold])]
    else
      []
    end

  column style: %{gap: 0} do
    rows ++ error_items
  end
end
```

---

#### Pattern: `with` chain in submit — extend login.ex lines 264-329

```elixir
# login.ex lines 264-292 — the with + else pattern
with {:ok, user} <- Accounts.authenticate_by_password(handle_value, password_value),
     :active     <- user.status do
  screen = Accounts.post_login_screen(user)
  handle_auth_success(state, user, screen)
else
  {:error, :invalid_credentials} -> ...
  :pending  -> ...
  :suspended -> ...
end
```

Register's `submit/2` open/invite_only head replaces the current nested `case` chain (register.ex lines 232-280) with:
```elixir
defp submit(%{mode: mode, collected: collected} = reg, state)
    when mode in ["open", "invite_only"] do
  data = %{
    handle:      reg.handle_input.raxol_state.value,
    email:       reg.email_input.raxol_state.value,
    password:    reg.password_input.raxol_state.value,
    invite_code: Map.get(collected, :invite_code)
  }

  with {:ok, user} <- Accounts.register_user(data),
       screen      <- Accounts.post_login_screen(user),
       {:ok, code} <- maybe_build_verify_code(screen, user) do
    handle_register_success(state, user, screen, code)
  else
    {:error, changeset} when is_struct(changeset, Ecto.Changeset) ->
      new_reg = %{reg | error: changeset_error_text(changeset), focused_field: :handle}
      {:update, put_register_ss(state, new_reg), []}

    {:error, _build_code_error} ->
      modal = %{type: :error, message: "Could not generate a verification code. Please try again."}
      {:update, %{state | modal: modal}, []}
  end
end
```

The sysop_approved head (register.ex lines 213-230) migrates `state.register_wizard` refs to `screen_state[:register]` but keeps the `case` structure (planner's call per D-09).

---

#### Pattern: `handle_wizard_event/2` dispatch (§6 public domain hook) — preserve from register.ex lines 91-104

```elixir
# register.ex lines 91-104 — preserve @spec and public visibility
@doc "..."
@spec handle_wizard_event(
        {:submit_step, atom(), String.t()} | {:cancel},
        map()
      ) :: {map(), list()}
def handle_wizard_event({:cancel}, state) do
  {%{state | current_screen: :login, register_wizard: nil}, []}
end

def handle_wizard_event({:submit_step, step, value}, state) do
  w = state.register_wizard || default_wizard(state)
  w = Map.put_new(w, :current_input, "")
  advance(w, step, value, state)
end
```

After Phase 2 migration, the `{:cancel}` head clears via `clear_register_ss`:
```elixir
def handle_wizard_event({:cancel}, state) do
  {clear_register_ss(%{state | current_screen: :login}), []}
end

def handle_wizard_event({:submit_step, :invite_code, value}, state) do
  reg = get_register_ss(state)
  # validate code, advance to :combined or set error
  ...
end

def handle_wizard_event({:submit_step, :combined, _value}, state) do
  # combined step submit is handled directly in handle_combined_key/2 via validate_and_submit/2;
  # this clause exists to satisfy the round-trip contract if needed
  {state, []}
end
```

The spec return type changes from `{map(), list()}` to `{:update, map(), list()} | {:update, map(), list()}` — planner should reconcile with actual return shape used in `do_update` (current `app.ex:354-357` passes the return value directly).

---

#### Pattern: Preserved verbatim blocks

**`valid_invite_code?/1`** (register.ex lines 195-211) — copy without any change:
```elixir
defp valid_invite_code?(code) when is_binary(code) and byte_size(code) > 0 do
  if function_exported?(Foglet.Accounts, :consume_invite_code, 1) do
    # apply/3 is intentional here: Accounts.consume_invite_code/1 does not exist yet
    # (Phase 8). Using apply avoids a compile-time undefined-function warning.
    # credo:disable-for-next-line Credo.Check.Refactor.Apply
    case apply(Foglet.Accounts, :consume_invite_code, [code]) do
      :ok -> true
      _   -> false
    end
  else
    Regex.match?(~r/\A[A-Za-z0-9]{4,32}\z/, code)
  end
end

defp valid_invite_code?(_), do: false
```

**`maybe_log_verify_code/2`** (register.ex lines 286-293) — copy verbatim (compile-time conditional):
```elixir
if @log_verify_codes do
  defp maybe_log_verify_code(user, code) do
    require Logger
    Logger.info("[verify] code for @#{user.handle}: #{code}")
  end
else
  defp maybe_log_verify_code(_user, _code), do: :ok
end
```

**`changeset_error_text/1`** (register.ex line 282-284) — copy verbatim.

**`registration_mode/1` and `session_ctx/1`** (register.ex lines 113-120) — copy verbatim (also matches login.ex lines 142-149).

---

### `lib/foglet_bbs/tui/app.ex` — lines 53-56 and 354-361 (two isolated edits)

**Analog:** Self-analog; the surrounding code is the reference.

**Remove from `@type t`** (app.ex line 54):
```elixir
# REMOVE this line from @type t:
register_wizard: map() | nil,
```

**Remove from `defstruct`** (app.ex line 73):
```elixir
# REMOVE this line from defstruct:
register_wizard: nil,
```

**`do_update` dispatch clause** (app.ex lines 354-357) — no change to the clause itself:
```elixir
# PRESERVE AS-IS — behavior changes because handle_wizard_event/2 in register.ex
# is rewritten to use screen_state[:register]; app.ex dispatch is unchanged.
defp do_update({:register_wizard, event}, state) do
  # Delegated from register screen during wizard transitions.
  Screens.Register.handle_wizard_event(event, state)
end
```

---

### `lib/foglet_bbs/tui/screens/login.ex` — `maybe_register/1` (one-line deletion)

**Analog:** login.ex lines 230-253 (the full function before and after):

```elixir
# BEFORE (login.ex lines 230-253 — current state after Phase 1):
defp maybe_register(state) do
  case registration_mode(state) do
    "disabled" ->
      :no_match

    mode ->
      new_state = %{
        state
        | current_screen: :register,
          register_wizard: %{
            mode: mode,
            step: first_step_for_mode(mode),
            data: %{},
            error: nil,
            current_input: ""
          }
      }

      {:update, new_state, []}
  end
end

defp first_step_for_mode("invite_only"), do: :invite_code
defp first_step_for_mode(_mode),         do: :handle
```

```elixir
# AFTER (Phase 2):
defp maybe_register(state) do
  case registration_mode(state) do
    "disabled" ->
      :no_match

    _mode ->
      {:update, %{state | current_screen: :register}, []}
  end
end
# DELETE first_step_for_mode/1 entirely — it becomes dead code
```

---

### `test/foglet_bbs/tui/screens/register_test.exs` (full rewrite)

**Analog:** `test/foglet_bbs/tui/screens/login_test.exs`

**`base_state/1` fixture pattern** (login_test.exs lines 9-18):
```elixir
# login_test.exs lines 9-18 — template, adapt for register
defp base_state(mode \\ "open") do
  %Foglet.TUI.App{
    current_screen: :login,
    current_user: nil,
    session_context: %{registration_mode: mode},
    terminal_size: {80, 24},
    screen_state: %{}
  }
  |> Map.from_struct()
end
```

Register version — note no `register_wizard:` key; `screen_state` is empty (register.ex self-initializes):
```elixir
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

**`form_state/2` fixture pattern** (login_test.exs lines 30-54) — register equivalent is `combined_state/2`:
```elixir
# login_test.exs lines 30-54
defp form_state(fields, focused \\ :password) do
  handle_input   = TextInput.init(value: Keyword.get(fields, :handle, ""))   |> text_input_at_end()
  password_input = TextInput.init(value: Keyword.get(fields, :password, ""), mask_char: "*") |> text_input_at_end()
  error = Keyword.get(fields, :error, nil)

  %Foglet.TUI.App{
    current_screen: :login,
    session_context: %{registration_mode: "open"},
    terminal_size: {80, 24},
    screen_state: %{
      login: %{
        sub: :login_form,
        focused_field: focused,
        handle_input: handle_input,
        password_input: password_input,
        error: error
      }
    }
  }
  |> Map.from_struct()
end
```

Register equivalent:
```elixir
defp combined_state(fields, focused \\ :handle) do
  # Build pre-seeded TextInput structs for each field (with cursor at end)
  ...
  %Foglet.TUI.App{
    current_screen: :register,
    session_context: %{registration_mode: "open"},
    terminal_size: {80, 24},
    screen_state: %{
      register: %{
        mode:              "open",
        step:              :combined,
        focused_field:     focused,
        invite_code_input: TextInput.init([]),
        handle_input:      handle_input,
        email_input:       email_input,
        password_input:    password_input,
        confirm_input:     confirm_input,
        collected:         %{},
        error:             Keyword.get(fields, :error, nil)
      }
    }
  }
  |> Map.from_struct()
end
```

**`text_input_at_end/1` helper** (login_test.exs lines 23-26) — copy verbatim:
```elixir
defp text_input_at_end(ti) do
  {ti_end, _action} = TextInput.handle_event(%{key: :end}, ti)
  ti_end
end
```

**Assertion pattern for `screen_state[:register]` keys** (copy from login_test.exs lines 117-123):
```elixir
# login_test.exs lines 117-123 — use Access.key/1 to reach inside struct fields
assert get_in(new_state, [
  :screen_state,
  :register,
  :handle_input,
  Access.key(:raxol_state),
  :value
]) == "a"
```

**`init_screen_state/1` test block** (login_test.exs lines 56-64 — exact template):
```elixir
describe "init_screen_state/1 (AUDIT-19)" do
  test "returns minimal open-mode stub" do
    ss = Register.init_screen_state([])
    assert ss.mode == "open"
    assert ss.step == :combined
    assert ss.focused_field == :handle
    assert %TextInput{} = ss.handle_input
    assert %TextInput{} = ss.password_input
    assert %TextInput{} = ss.confirm_input
    assert ss.collected == %{}
    assert ss.error == nil
  end

  test "accepts opts but ignores them" do
    assert %{mode: "open"} = Register.init_screen_state(foo: :bar)
  end
end
```

**Cancel flow assertion** (login_test.exs lines 214-222):
```elixir
# login_test.exs lines 214-222 — escape clears sub-state
test "escape from login form returns to menu sub with cleared form" do
  state = form_state([handle: "alice", password: "secret"], :password)
  {:update, new_state, []} = Login.handle_key(%{key: :escape}, state)
  assert get_in(new_state, [:screen_state, :login, :sub]) == :menu
  assert get_in(new_state, [:screen_state, :login, :handle_input]) == nil
end
```

Register version:
```elixir
test "escape returns to :login and clears screen_state[:register]" do
  state = combined_state([], :handle)
  {:update, new_state, []} = Register.handle_key(%{key: :escape}, state)
  assert new_state.current_screen == :login
  assert Map.get(new_state.screen_state || %{}, :register) == nil
end
```

---

## Shared Patterns

### TextInput contract (all TextInput usages in register.ex)

**Source:** `lib/foglet_bbs/tui/widgets/input/text_input.ex`

**Init** (text_input.ex lines 62-79):
```elixir
TextInput.init([])                     # plain text field
TextInput.init(mask_char: "*")         # password / confirm_password
TextInput.init(value: "prefilled")     # test fixtures only
```

**Handle event** (text_input.ex line 83 — returns `{new_struct, action}`):
```elixir
{new_input, _action} = TextInput.handle_event(event, current_input_struct)
```
`action` is `:submitted | :cancelled | :changed | nil` — screens intercept Enter/Escape before delegating, so `action` is usually `nil` or `:changed` when delegation occurs.

**Render** (text_input.ex lines 97-110 — `theme:` is REQUIRED):
```elixir
TextInput.render(input_struct, bordered: false, theme: theme)
```
Passing `bordered: true` wraps in a box; Phase 2 uses `bordered: false` throughout (D-01 micro-patch inherited from Phase 1).

**Value access at submit time** (text_input.ex line 42, confirmed in login.ex lines 257-258):
```elixir
# Access via .raxol_state.value — NOT struct[:key] (struct Access not implemented)
handle_value   = reg.handle_input.raxol_state.value
password_value = reg.password_input.raxol_state.value
```

---

### Theme extraction (all render functions)

**Source:** `lib/foglet_bbs/tui/screens/login.ex` line 53; phase 0 canonical pattern

```elixir
theme = Theme.from_state(state)
```

Never inline `Map.get(state, :session_context)` + `Map.get(ctx, :theme)` — AUDIT-05 gate 8 fails.

---

### Error rendering pattern (below last field, no fill below)

**Source:** login.ex lines 193-198, repeated in register.ex lines 32-37

```elixir
error_items =
  if reg.error do
    [text(""), text(reg.error, fg: theme.error.fg, style: [:bold])]
  else
    []
  end
# Append to rows list: rows ++ error_items
```

AUDIT-17: no additional rows below the error row.

---

### `handle_wizard_event/2` return type alignment

**Source:** `lib/foglet_bbs/tui/app.ex` lines 354-357

```elixir
# app.ex passes handle_wizard_event/2 return directly to process_screen_commands/2
# (or similar). Current register.ex returns {state, commands} (bare tuple).
# Planner must verify the return shape matches what do_update passes back to
# Raxol's runtime — the current app.ex does NOT wrap in {:update, ...}.
defp do_update({:register_wizard, event}, state) do
  Screens.Register.handle_wizard_event(event, state)
end
```

This means `handle_wizard_event/2` must continue returning `{state, commands}` (bare 2-tuple), NOT `{:update, state, commands}`. The `submit/2` and `handle_wizard_event/2` functions use the bare-tuple convention; `handle_key/2` and `handle_*_key/2` helpers use `{:update, state, commands}`.

---

## No Analog Found

None — all files have close analogs.

---

## Metadata

**Analog search scope:** `lib/foglet_bbs/tui/screens/`, `lib/foglet_bbs/tui/app.ex`, `lib/foglet_bbs/tui/widgets/input/`, `test/foglet_bbs/tui/screens/`
**Files fully read:** login.ex (341 lines), register.ex (294 lines), text_input.ex (145 lines), app.ex lines 1-120 + 330-410, login_test.exs (437 lines), register_test.exs (293 lines)
**Pattern extraction date:** 2026-04-21
