# Phase 2: Register — Research

**Researched:** 2026-04-21
**Domain:** Elixir TUI screen refactor — wizard two-step collapse, TextInput adoption, `with`-chain, top-level state migration
**Confidence:** HIGH (all findings from direct file reads of codebase; no external sources needed)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Two-step wizard: `:invite_code` step (invite_only mode) + `:combined` step (all modes) with four TextInput instances.
- **D-02:** Key routing on `:combined` step follows Phase 1 D-06 precedent: Tab cycles focused_field; Escape returns to :login; Enter advances or submits; all others delegated to focused TextInput.
- **D-03:** Confirm-password validation is screen-side on Enter from `:confirm_password`; mismatch sets `error:` without calling `submit/2`.
- **D-04:** `screen_state[:register]` is a flat map (see state shape in CONTEXT.md). No nested `data:` sub-map; `collected:` accumulates validated step outputs. TextInput structs created eagerly in `init_screen_state/1`.
- **D-05 (AUDIT-19):** `init_screen_state/1` is public with `@spec init_screen_state(keyword()) :: map()`.
- **D-06:** `register.ex` self-initializes `screen_state[:register]` lazily via `get_register_ss/1`. `login.ex:maybe_register/1` becomes `%{state | current_screen: :register}` only — one-line deletion.
- **D-07 (AUDIT-13(b) expansion):** Three-touch scope: `login.ex:maybe_register/1` (one-line deletion), `app.ex:53-56` (remove field declaration), `app.ex:354-361` (migrate dispatch).
- **D-08:** `app.ex:354-361` dispatch rewritten; `:submit_step` self-dispatch round-trip preserved; modal-close `screen_state: %{}` reset preserved.
- **D-09:** `with` chain targets the nested `case` chains inside `submit/2` (REGISTER-03/AUDIT-09). All existing branches preserved.
- **D-10:** `Config.get("registration_mode")` in `registration_mode/1` is safe (ETS read-through). No change required.

### Claude's Discretion

- Exact naming of state helpers (`get_register_ss/1`, `put_register_ss/2`, `clear_register_ss/1`, etc.) — follow Phase 1 `get_login_ss`/`put_login_ss` naming style.
- Whether `handle_wizard_event/2` is kept as public (§6 domain hooks per AUDIT-18) or collapsed into `do_update` dispatch directly.
- AUDIT-18 canonical section ordering — planner handles the reorder.
- Line count target: current 294 LoC, must land strictly lower.

### Deferred Ideas (OUT OF SCOPE)

None declared.

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| REGISTER-01 | Single-line wizard input replaced with `Widgets.Input.TextInput` (mask_char `*` for password + confirm) | TextInput contract fully read; same init/handle_event/render pattern as Phase 1 |
| REGISTER-02 | Wizard step dispatcher audited — prefer multi-clause `render_step/2` + pattern-matched step atoms | Current `render/1` is a flat sequential display; new structure maps cleanly to multi-clause render |
| REGISTER-03 | `submit/2` nested `case` chain rewritten as `with` chain | Exact chain structure at lines 232–280 catalogued below; all branches identified |
| REGISTER-04 | `apply/3` + `function_exported?/3` + `credo:disable` in `valid_invite_code?/1` preserved verbatim | Block identified at lines 195–211; must not be touched |
| REGISTER-05 | AUDIT rubric items 05–22 pass; `mix precommit` green; line count decreases | All rubric items assessed below |
| REGISTER-06 | `state.register_wizard` → `state.screen_state[:register]` migration; dispatch at `app.ex:354-361` rewritten; Watch List items honored | Exact code at each touch point documented below |

</phase_requirements>

---

## Summary

Phase 2 is a structural refactor of `lib/foglet_bbs/tui/screens/register.ex` (294 LoC). The current implementation is a sequential one-field-per-step wizard where each step shows one hand-rolled text input (`"> value█"` format). The refactor collapses this into a two-step structure — `:invite_code` (invite_only mode only) and `:combined` (four TextInput instances: handle, email, password, confirm_password) — inheriting the Phase 1 login pattern verbatim.

The top-level `state.register_wizard` field is removed from the App struct and all wizard state moves into `state.screen_state[:register]` (a flat map). Three touch points outside `register.ex` are permitted under AUDIT-13(b): `app.ex:53-56` (field declaration), `app.ex:354-361` (wizard dispatch), and `login.ex:maybe_register/1` (one-line deletion). The `submit/2` nested `case` chain (lines 232–280) becomes a `with` chain. The `valid_invite_code?/1` block (lines 195–211) is preserved verbatim.

The Phase 1 `login.ex` post-refactor is the direct template: `get_login_ss/1`, `put_login_ss/2`, `handle_form_key/2` routing, inline label + TextInput row layout, and `sub_state/1` toggling are all directly analogous. Register extends this pattern to 4 fields and 2 wizard steps.

**Primary recommendation:** Treat Phase 1's completed `login.ex` as the implementation template. Map each Phase 1 pattern to its Register equivalent, then add the two-step wizard layer (`:invite_code` → `:combined`) on top.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Form input rendering (4-field combined step) | TUI Screen (`register.ex`) | TextInput widget | Screen owns layout; TextInput owns character rendering |
| Focus cycling (Tab) | TUI Screen | — | Screen intercepts Tab before TextInput sees it (Phase 1 D-06) |
| Invite-code validation | TUI Screen | `Accounts.consume_invite_code/1` (optional) | Screen calls `valid_invite_code?/1` which wraps apply/3 |
| Confirm-password comparison | TUI Screen | — | D-03: screen-side comparison, not an Accounts call |
| Registration pipeline | API / Backend | — | `Accounts.register_user/1`, `register_pending_user/1` — synchronous |
| Post-login routing | API / Backend | — | `Accounts.post_login_screen/1` returns `:verify | :main_menu` |
| Wizard state storage | `state.screen_state[:register]` | — | Post-Phase-2 canonical store; no top-level field |
| App dispatch routing | `app.ex:do_update/2` | — | Routes `{:register_wizard, event}` to `Screens.Register.handle_wizard_event/2` |
| Mode config read | `registration_mode/1` in `register.ex` | `Foglet.Config` (ETS cached) | Safe on render path (D-10) |

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `Foglet.TUI.Widgets.Input.TextInput` | Existing (bordered: false shipped in micro-patch) | Single-line input with init/handle_event/render | D-14 stateful widget; Phase 1 set the precedent |
| `Foglet.TUI.Theme` | Existing | `from_state/1` for theme lookup | Phase 0 extraction; all screens must use |
| `Foglet.TUI.Widgets.Chrome.ScreenFrame` | Existing | Chrome wrapper with KeyBar | Unchanged call |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `Foglet.Accounts` | Existing | `register_user/1`, `register_pending_user/1`, `post_login_screen/1`, `build_verify_code/1` | Submit pipeline (unchanged semantics) |
| `Foglet.Config` | Existing | `registration_mode/1` render-path config | ETS cached; safe (D-10) |
| ExUnit | Built-in | Test framework | New wizard flow + cancel flow tests |

**No new packages required.**

---

## Architecture Patterns

### System Architecture Diagram

```
User keystrokes
       │
       ▼
┌──────────────────────────────────────────────────────────────┐
│  Register Screen (register.ex)                              │
│                                                              │
│  handle_key/2                                                │
│  ├── :escape  → clear_register_ss + goto :login             │
│  └── all else → route by step                               │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Step :invite_code (invite_only mode only)          │    │
│  │  • Enter → emit {:register_wizard, {:submit_step,   │    │
│  │              :invite_code, value}} command           │    │
│  │  • char/backspace → delegate to invite_code_input   │    │
│  └─────────────────────────────────────────────────────┘    │
│                           ↓ (advance on valid code)          │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Step :combined                                     │    │
│  │  focused_field: :handle | :email | :password        │    │
│  │               | :confirm_password                   │    │
│  │  • Tab → cycle focused_field                        │    │
│  │  • Enter on handle/email/password → advance focus   │    │
│  │  • Enter on confirm_password → validate + submit    │    │
│  │  • char/backspace → delegate to focused TextInput   │    │
│  └─────────────────────────────────────────────────────┘    │
│                           │                                  │
│            screen_state[:register] = %{                     │
│              mode:               "open" | ...,              │
│              step:               :invite_code | :combined,  │
│              focused_field:      :handle | ...,             │
│              invite_code_input:  %TextInput{} | nil,        │
│              handle_input:       %TextInput{},              │
│              email_input:        %TextInput{},              │
│              password_input:     %TextInput{},              │
│              confirm_input:      %TextInput{},              │
│              collected:          %{},                        │
│              error:              nil | String.t()           │
│            }                                                 │
└──────────────────────────────────────────────────────────────┘
                           │
          {:register_wizard, {:submit_step, step, value}}
                           │
                           ▼
         app.ex do_update({:register_wizard, event}, state)
                           │
                           ▼
         Screens.Register.handle_wizard_event/2
                           │
         ┌─────────────────┼──────────────────┐
         ▼                 ▼                  ▼
   invite_code       combined step         {:cancel}
   validation         submit/2             goto :login
```

### Recommended Project Structure (AUDIT-18 canonical order)

```
lib/foglet_bbs/tui/screens/register.ex
├── §1  Aliases + imports  (Theme, ScreenFrame, TextInput, Accounts, Config)
├── §2  Module attributes  (@modes, @log_verify_codes)
├── §3  init_screen_state/1  (PUBLIC — AUDIT-19)
├── §4  render/1  (PUBLIC)
├── §5  handle_key/2  (PUBLIC)
├── §6  handle_wizard_event/2  (PUBLIC — domain-hook callback from app.ex)
├── §7  Private key handlers
│       handle_invite_key/2 | handle_combined_key/2
│       advance_focus/1 | focused_input/1 | update_focused_input/3
├── §8  Private render helpers
│       render_invite_step/2 | render_combined_step/2
├── §9  Private state plumbing
│       get_register_ss/1 | put_register_ss/2 | clear_register_ss/1
│       advance_to_combined/2
├── §10 Private domain plumbing
│       submit/2 (with-chain) | valid_invite_code?/1 (PRESERVED VERBATIM)
│       registration_mode/1 | session_ctx/1 | changeset_error_text/1
│       maybe_log_verify_code/2
```

### Pattern 1: State shape (D-04)

**What:** `screen_state[:register]` is a flat map with all four TextInput structs allocated eagerly.

**When to use:** Created by `init_screen_state/1`; read via `get_register_ss/1`.

```elixir
# Source: [VERIFIED: CONTEXT.md D-04]
def init_screen_state(opts \\ []) do
  _ = opts
  mode = # read registration_mode from ... needs state context, see D-05 note below
  step = if mode == "invite_only", do: :invite_code, else: :combined
  %{
    mode:               mode,
    step:               step,
    focused_field:      :invite_code_or_handle_depending_on_step,
    invite_code_input:  TextInput.init([]),
    handle_input:       TextInput.init([]),
    email_input:        TextInput.init([]),
    password_input:     TextInput.init(mask_char: "*"),
    confirm_input:      TextInput.init(mask_char: "*"),
    collected:          %{},
    error:              nil
  }
end
```

**Important note on `init_screen_state/1` and mode:** `registration_mode/1` requires state (reads `session_context`). `init_screen_state/1` takes no state by D-05 spec. Resolution: `init_screen_state/1` defaults mode to `"open"` (step `:combined`); `get_register_ss/1` re-initializes with the correct mode on first access using the live state. This is the same pattern as Phase 1's lazy init — `init_screen_state/1` returns the AUDIT-19-compliant stub, while `get_register_ss/1` handles mode-aware bootstrap. [VERIFIED: CONTEXT.md D-05 and D-06 cross-referenced]

**Preferred `get_register_ss/1` pattern (D-06):**
```elixir
defp get_register_ss(state) do
  get_in(state, [:screen_state, :register]) || init_screen_state_for(state)
end

defp init_screen_state_for(state) do
  mode = registration_mode(state)
  step = if mode == "invite_only", do: :invite_code, else: :combined
  focused = if step == :invite_code, do: :invite_code, else: :handle
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

### Pattern 2: Focus cycling for 4-field combined step (D-02)

**What:** Tab cycles through handle → email → password → confirm_password → (wrap to handle). Enter on non-final fields advances; Enter on confirm_password triggers validation + submit.

```elixir
# Source: [VERIFIED: CONTEXT.md D-02, modeled on login.ex Phase 1 pattern]
@focus_cycle [:handle, :email, :password, :confirm_password]

defp next_field(current) do
  idx = Enum.find_index(@focus_cycle, &(&1 == current)) || 0
  Enum.at(@focus_cycle, rem(idx + 1, length(@focus_cycle)))
end

defp handle_combined_key(%{key: :tab}, state) do
  reg = get_register_ss(state)
  new_reg = %{reg | focused_field: next_field(reg.focused_field), error: nil}
  {:update, put_register_ss(state, new_reg), []}
end

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
```

### Pattern 3: `with` chain for `submit/2` (D-09 / REGISTER-03)

**What:** Replace the current nested `case {:ok,_}|{:error,_}` chains in `submit/2` (lines 232–280) with a `with` chain.

**Current structure (lines 232–280):**
```elixir
# open / invite_only head:
case Accounts.register_user(data) do
  {:ok, user} ->
    case Accounts.post_login_screen(user) do
      :verify ->
        case Accounts.build_verify_code(user) do
          {:ok, code}   -> # happy path: goto :verify
          {:error, _cs} -> # modal: "Could not generate verification code"
        end
      :main_menu ->
        # {:promote_session, user}
    end
  {:error, changeset} ->
    # inline error: changeset_error_text, step back to :handle
end
```

**Target `with` chain:**
```elixir
# Source: [VERIFIED: CONTEXT.md D-09 + direct read of register.ex:232-280]
defp submit(%{mode: mode, collected: collected} = _reg, state)
    when mode in ["open", "invite_only"] do
  data = %{
    handle:   state_value(state, :handle_input),
    email:    state_value(state, :email_input),
    password: state_value(state, :password_input),
    invite_code: Map.get(collected, :invite_code)
  }

  with {:ok, user}  <- Accounts.register_user(data),
       screen       <- Accounts.post_login_screen(user),
       {:ok, code}  <- maybe_build_verify_code(screen, user) do
    handle_register_success(state, user, screen, code)
  else
    {:error, changeset} when is_struct(changeset, Ecto.Changeset) ->
      reg = get_register_ss(state)
      new_reg = %{reg | error: changeset_error_text(changeset), focused_field: :handle}
      {:update, put_register_ss(state, new_reg), []}

    {:error, _build_code_error} ->
      modal = %{type: :error, message: "Could not generate a verification code. Please try again."}
      {:update, %{state | modal: modal}, []}
  end
end
```

**Note:** The planner decides the exact clause structure (D-09 discretion). All four existing branches must be preserved: verify path, main_menu path, changeset error, build_verify_code error.

### Pattern 4: `handle_wizard_event/2` migration (D-08 / REGISTER-06)

**Current `app.ex:354-361`:**
```elixir
defp do_update({:register_wizard, event}, state) do
  # Delegated from register screen during wizard transitions.
  Screens.Register.handle_wizard_event(event, state)
end
```

**After Phase 2 — semantics preserved, state reads/writes through `screen_state[:register]`:**
```elixir
# Source: [VERIFIED: app.ex:354-357, CONTEXT.md D-08]
# The clause itself does NOT change — handle_wizard_event/2 in register.ex
# is rewritten to read/write screen_state[:register] instead of state.register_wizard.
# The app.ex dispatch clause is preserved as-is OR the planner chooses to
# inline the dispatch — either is valid per Claude's Discretion.
defp do_update({:register_wizard, event}, state) do
  Screens.Register.handle_wizard_event(event, state)
end
```

### Anti-Patterns to Avoid

- **Nested `data:` sub-map in screen state:** D-04 explicitly rejects nested sub-maps. `collected:` accumulates validated step outputs (invite code only); handle/email/password are read directly from TextInput structs at submit time.
- **Delegating Enter/Escape to TextInput:** D-02 requires screen interception. TextInput returns `:submitted` for Enter and `:cancelled` for Escape — if delegated, these fire silently.
- **Block expression rebinding (CLAUDE.md gotcha):** `if focused_field == :confirm_password do state = ... end` — rebind is lost. Always bind the entire expression.
- **Struct Access syntax on TextInput:** `reg[:handle_input]` does not work on plain maps; use `Map.get(reg, :handle_input)` or `reg.handle_input`.
- **Touching app.ex beyond lines 53-56 and 354-361:** AUDIT-13(b) scope fence is strict. Only those two blocks may change.
- **Writing `register_wizard:` in login.ex beyond `maybe_register/1`:** D-07 specifies exactly one line deletion in `login.ex` and nothing else.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Character input + backspace | Manual string slice/append | `TextInput.handle_event/2` | Current register.ex does this (lines 68-82); TextInput handles Unicode, cursor, home/end |
| Password masking display | `display_value(:password, _)` (lines 133-136) | `TextInput.init(mask_char: "*")` | Masking built into Raxol TextInput |
| Focus cursor rendering | `"> #{display_value(...)}█"` (lines 44-48) | `TextInput.render/2` with `bordered: false` | Widget manages cursor position and style |
| Confirm-password match | Accounts call | Direct comparison: `pw_input.raxol_state.value == confirm_input.raxol_state.value` | This is screen-side validation per D-03 |

**Key insight:** The current register.ex hand-rolls ~30 LoC of character input handling (`handle_key` clauses for `:backspace`, `:char`, and the `display_value` + `current_input` pattern). All of this collapses into TextInput delegation.

---

## Current Code Inventory (Phase 2 replaces/migrates)

### Functions to DELETE (no analog in new design)

| Function | Lines | Reason |
|----------|-------|--------|
| `default_wizard/1` | 108–111 | Replaced by `init_screen_state/1` + `get_register_ss/1` |
| `first_step_for/1` | 122–124 | Logic moves into `init_screen_state_for/1` |
| `advance/4` (all 5 clauses) | 138–193 | Replaced by two-step routing in `handle_wizard_event/2` and `handle_combined_key/2` |
| `prompt_for_step/1` | 126–131 | Replaced by multi-clause `render_step/2` labels |
| `display_value/2` | 133–136 | Replaced by TextInput masking |
| `handle_key` for `:backspace` | 68–73 | Delegated to TextInput |
| `handle_key` for `:char` | 78–82 | Delegated to TextInput |
| `handle_key` for `:enter` (raw) | 60–66 | Replaced by per-step key handlers |
| `handle_key` for `:escape` (raw) | 56–58 | Replaced — Escape now calls `clear_register_ss` |

### Functions to PRESERVE VERBATIM

| Function | Lines | Why |
|----------|-------|-----|
| `valid_invite_code?/1` | 195–211 | REGISTER-04 + AUDIT-15: `apply/3` + `credo:disable` is the documented exception |
| `maybe_log_verify_code/2` | 286–293 | Conditional compilation via `@log_verify_codes`; leave as-is |
| `changeset_error_text/1` | 282–284 | No change needed |
| `registration_mode/1` | 113–118 | No change needed |
| `session_ctx/1` | 120 | No change needed |

### Functions to REWRITE

| Function | Lines | Change |
|----------|-------|--------|
| `render/1` | 28–53 | Switch to `get_register_ss`, dispatch `render_step/2` by `reg.step` |
| `handle_wizard_event/2` | 95–104 | Read/write through `screen_state[:register]` instead of `state.register_wizard` |
| `submit/2` (open/invite_only head) | 232–280 | Rewrite as `with` chain (D-09) |
| `submit/2` (sysop_approved head) | 213–230 | Migrate `state.register_wizard` refs to `screen_state[:register]`; keep case structure |

### app.ex changes (AUDIT-13(b) exception)

**Lines 53-56 — remove from `@type t` and `defstruct`:**
```elixir
# REMOVE:
register_wizard: map() | nil,   # from @type t (line 54)
register_wizard: nil,            # from defstruct (line 73)
```

**Lines 354-357 — `do_update({:register_wizard, event}, state)`:**
The dispatch clause itself is unchanged. The behavior changes because `handle_wizard_event/2` in `register.ex` is rewritten to use `screen_state[:register]`.

### login.ex change (D-07)

**`maybe_register/1` (lines 230-249 in the current post-Phase-1 login.ex):**
```elixir
# BEFORE (current login.ex after Phase 1):
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

# AFTER (one-line deletion):
new_state = %{state | current_screen: :register}
```

Also delete `first_step_for_mode/1` from `login.ex` (it becomes dead code after the `register_wizard` write is removed).

---

## AUDIT Rubric Assessment (AUDIT-05 through AUDIT-22)

### Grep Gates (AUDIT-05)

| Gate | Pattern | register.ex Status | Action |
|------|---------|-------------------|--------|
| 1 | Named color atoms `:red\|:green\|...` | NOT PRESENT today | Maintain zero |
| 2 | Hex literals `"#[0-9a-fA-F]{6}"` | NOT PRESENT | Maintain zero |
| 3 | Raw ANSI `\e[\|\\x1b` | NOT PRESENT | Maintain zero |
| 4 | Theme struct mutation `%{.*theme.*\|` | NOT PRESENT | Maintain zero |
| 5 | `box style.*border` | NOT PRESENT | Maintain zero |
| 6 | `IO.(write\|puts\|inspect)` | NOT PRESENT | Maintain zero |
| 7 | `{80, 24}` inline | NOT PRESENT (no terminal size check in register.ex) | N/A |
| 8 | Inlined theme extraction | NOT PRESENT (already uses `Theme.from_state/1`) | Maintain zero |
| 9 | Inlined domain lookup | NOT PRESENT (no domain calls in register.ex) | N/A |

All 9 grep gates trivially pass for register.ex — the screen has no raw color, ANSI, or domain-lookup anti-patterns. The only work is ensuring the rewritten file does not introduce them.

### Behavioral Invariants (AUDIT-06)

- `handle_key/2` source-order: new two-clause structure (`:escape` first, then catch-all routing) — preserve this ordering. The Watch List item (iii) from REGISTER-06 calls this out explicitly.
- `render/*` functions must be pure reads — the new `render_step/2` helpers must not mutate state.
- `handle_key/2` must never inspect `state.modal` — confirmed: modal dispatch lives in `app.ex:329-334`.
- `%{state | modal: modal, screen_state: %{}}` — modal-close reset (Watch List (ii)): `submit/2`'s `{:error, _cs}` path for `build_verify_code` shows `{%{state | modal: modal}, []}` without `screen_state: %{}` (intentional — error does not terminate the wizard). The sysop_approved success modal path pairs `modal: modal` with wizard clear; this behavior must be preserved.

### Widget Contract (AUDIT-07)

- Four TextInput instances need `theme: theme` passed to `TextInput.render/2`. [VERIFIED: text_input.ex:99 — `Keyword.fetch!(opts, :theme)` — this is required, not optional]
- All four TextInput structs live in `screen_state[:register]` (D-04, D-14 hoisting).
- No stateless widgets need `screen_state` entries (AUDIT-16 note about D-16).

### Chrome Contract (AUDIT-08)

- `ScreenFrame.render/4` already used (line 52). The new KeyBar hints for `:combined` step need to include `{"Tab", "Switch field"}, {"Enter", "Next/Submit"}, {"Esc", "Cancel"}`.

### `with` chain (AUDIT-09)

- Applies to register.ex — `submit/2` open/invite_only head (lines 232–280). Non-trivial; see Pattern 3 above.

### Loading-state widget (AUDIT-10)

- `register_user/1` and `register_pending_user/1` are synchronous; `build_verify_code/1` is synchronous. No spinner needed. AUDIT-10 passes trivially.

### Loading/empty-state phrasing (AUDIT-11)

- Register has no loading or empty-state text. N/A.

### Dead-code audit (AUDIT-12)

- `handle_wizard_event/2` is public and called from `app.ex:354`. Not dead — keep.
- No `load_*` or `flush_*` public functions. AUDIT-12 passes trivially.

### Scope fence (AUDIT-13)

- Phase 2 carries the documented exception (b): `app.ex:53-56` and `app.ex:354-361` + `login.ex:maybe_register/1`.
- No other `app.ex` or `login.ex` lines may be touched.

### No new shared modules (AUDIT-14)

- All new helpers (`get_register_ss`, `put_register_ss`, `clear_register_ss`, `init_screen_state_for`) are file-scoped private functions or public spec-compliant functions within `register.ex`. No new module.

### CI gate (AUDIT-15)

- `mix precommit` green. No new `@dialyzer` / `credo:disable` / `sobelow_skip` suppressions.
- **Exception preserved verbatim:** `valid_invite_code?/1` — `# credo:disable-for-next-line Credo.Check.Refactor.Apply` at line 199.

### Size delta (AUDIT-16)

**Current:** 294 LoC.
**Estimated deletions:**
- `advance/4` five clauses: ~55 LoC
- `default_wizard/1`, `first_step_for/1`: ~7 LoC
- `prompt_for_step/1`, `display_value/2`: ~9 LoC
- Raw `handle_key` clauses for `:backspace`, `:char` (replaced by delegation): ~12 LoC
- Current `submit/2` nested case rewritten as shorter `with` chain: ~15 LoC net savings

**Estimated additions:**
- `init_screen_state/1` spec + body: ~15 LoC
- `get_register_ss/1` + `put_register_ss/2` + `clear_register_ss/1`: ~10 LoC
- `handle_invite_key/2` + `handle_combined_key/2`: ~25 LoC
- `render_invite_step/2` + `render_combined_step/2`: ~30 LoC
- `advance_focus/1`, `next_field/1`, `focused_input/1`, `update_focused_input/3`: ~15 LoC
- `input_key/1` helper (maps focused_field atom to map key): ~6 LoC

**Net estimate:** 294 - 98 + 101 ≈ **~297 LoC before optimization**. This is tight — the planner must be disciplined about brevity in render helpers and may need to compress the combined-step render (all four fields share the same focus-color pattern; extract a helper). Target: stay under 294. A realistic target is 240-270 LoC if render helpers are compact.

**AUDIT-16 risk is MEDIUM.** The planner should include a final LoC check and compress aggressively.

### Protected layout regions (AUDIT-17)

- `login / register / verify` screens: below the error line is reserved. The new two-step structure has:
  - `:invite_code` step: one input row + optional error row
  - `:combined` step: four input rows + optional error row
- No additional rows may be added below the error row. The `Mode: #{w.mode}` debug line at current line 42 should be removed in the refactor (it's a dev artifact and consumes a row).

### Canonical section order (AUDIT-18)

The new `register.ex` must follow the 10-section canonical order (see §7 Project Structure above). Key note: `handle_wizard_event/2` is public and dispatched from `app.ex` — it belongs in §6 (public domain-hook callbacks). No deviation required; document in `@moduledoc` that `handle_wizard_event/2` is the §6 domain hook.

### `init_screen_state/1` (AUDIT-19)

- Must be present and public: `@spec init_screen_state(keyword()) :: map()`.
- Opts currently unused but present for signature conformance.
- The stub returned can be mode-agnostic (`"open"` default, step `:combined`) since `get_register_ss/1` provides the mode-aware version on first real access.

---

## Common Pitfalls

### Pitfall 1: Value extraction from TextInput struct at submit time

**What goes wrong:** `submit/2` tries to read handle/email/password from `collected:` map or from a now-migrated `data:` map — but D-04 says values are read directly from TextInput structs.

**Why it happens:** The old wizard stores collected values in `data: %{handle: ..., email: ...}` and passes them as `data` to `register_user/1`. The new design reads them directly from `handle_input.raxol_state.value` etc.

**How to avoid:** At submit time:
```elixir
handle   = reg.handle_input.raxol_state.value
email    = reg.email_input.raxol_state.value
password = reg.password_input.raxol_state.value
# invite_code comes from reg.collected[:invite_code] (accumulated at step advance)
```

**Warning signs:** `register_user/1` receives empty strings for handle/email/password.

### Pitfall 2: `state.register_wizard` nil-check pattern carried forward

**What goes wrong:** `get_register_ss/1` is written as `state.register_wizard || default_wizard(state)` — this references the removed field and crashes.

**Why it happens:** The old pattern (lines 29, 61, 69, 79, 100) uses `|| default_wizard(state)` everywhere. All of these become `get_register_ss(state)` calls.

**How to avoid:** Replace every `state.register_wizard || default_wizard(state)` with `get_register_ss(state)`. Grep before finalizing: `rg "register_wizard" lib/foglet_bbs/tui/screens/register.ex` must return zero after the refactor.

**Warning signs:** `UndefinedFunctionError` or KeyError on `register_wizard` key.

### Pitfall 3: Confirm-password validation skipping submit/2

**What goes wrong:** Enter on `:confirm_password` calls `submit/2` directly without first comparing `password_input.raxol_state.value == confirm_input.raxol_state.value`.

**Why it happens:** The old wizard has no confirm step; it's easy to copy-paste the password submission path and forget the pre-check.

**How to avoid:** `validate_and_submit/2` (or inline guard) must run the comparison first:
```elixir
defp validate_and_submit(reg, state) do
  pw = reg.password_input.raxol_state.value
  cpw = reg.confirm_input.raxol_state.value
  if pw == cpw do
    submit(reg, state)
  else
    new_reg = %{reg | error: "Passwords do not match."}
    {:update, put_register_ss(state, new_reg), []}
  end
end
```

**Warning signs:** Registration succeeds with mismatched passwords, or `submit/2` is called before confirm step.

### Pitfall 4: `:submit_step` self-dispatch round-trip for invite_code step

**What goes wrong:** On the `:invite_code` step, Enter is handled entirely within `handle_key/2` inline (no `{:register_wizard, {:submit_step, ...}}` command emitted), breaking the round-trip through `App.update/2`.

**Why it happens:** The current code's Enter handler emits the command; it's tempting to short-circuit and call `handle_wizard_event/2` directly.

**How to avoid:** Per D-08 Watch List (i): `:submit_step` self-dispatch must still round-trip through `App.update/2`. Enter on `:invite_code` step emits `{:register_wizard, {:submit_step, :invite_code, value}}` as a command; `handle_wizard_event/2` processes it. This is the existing pattern — preserve it.

**Warning signs:** `handle_wizard_event/2` never called for the invite_code step; state advances without going through `App.update/2`.

### Pitfall 5: Block expression rebinding (from CLAUDE.md)

**What goes wrong:** Pattern like:
```elixir
if reg.step == :invite_code do
  state = advance_invite_code(state)
end
```
The rebind inside `if` is lost.

**How to avoid:** Always bind the whole `if`/`case` expression:
```elixir
state =
  if reg.step == :invite_code do
    advance_invite_code(state)
  else
    state
  end
```

### Pitfall 6: Losing `screen_state: %{}` reset on wizard cancel/modal

**What goes wrong:** Escape or modal-close leaves `screen_state[:register]` intact, so next time the user navigates to register they see stale state.

**Why it happens:** Forgetting to pair the `current_screen: :login` transition with clearing the register screen state.

**How to avoid:**
```elixir
defp handle_key(%{key: :escape}, state) do
  {:update, clear_register_ss(%{state | current_screen: :login}), []}
end

defp clear_register_ss(state) do
  new_ss = Map.delete(state.screen_state || %{}, :register)
  %{state | screen_state: new_ss}
end
```

**Warning signs:** Test "escape returns to :login and clears register state" fails.

### Pitfall 7: `login.ex:first_step_for_mode/1` left as dead code

**What goes wrong:** After removing `register_wizard:` initialization from `maybe_register/1`, `first_step_for_mode/1` is unused in `login.ex` but not deleted. Dialyzer or Credo may warn.

**How to avoid:** Delete `first_step_for_mode/1` from `login.ex` along with the `register_wizard:` write. Check: `rg "first_step_for_mode" lib/foglet_bbs/tui/screens/login.ex` should return zero.

---

## Code Examples

### `init_screen_state/1` (AUDIT-19 compliant)

```elixir
# Source: [VERIFIED: CONTEXT.md D-05, TextInput contract verified via text_input.ex:62-78]
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

### TextInput value access

```elixir
# Source: [VERIFIED: text_input.ex:42, login.ex:257-258 (post-Phase-1)]
handle_value = reg.handle_input.raxol_state.value
password_value = reg.password_input.raxol_state.value
```

### Render combined step — inline label + TextInput row

```elixir
# Source: [VERIFIED: login.ex:202-215 post-Phase-1 pattern, extended to 4 fields]
defp render_combined_step(state, theme) do
  reg = get_register_ss(state)
  focused = reg.focused_field

  column style: %{gap: 0} do
    fields = [
      {:handle,           "Handle:          ", reg.handle_input},
      {:email,            "Email:           ", reg.email_input},
      {:password,         "Password:        ", reg.password_input},
      {:confirm_password, "Confirm password:", reg.confirm_input}
    ]

    rows = Enum.map(fields, fn {field, label, input} ->
      fg = if focused == field, do: theme.accent.fg, else: theme.primary.fg
      st = if focused == field, do: [:bold], else: []
      row style: %{gap: 0} do
        [
          text(label, fg: fg, style: st),
          TextInput.render(input, bordered: false, theme: theme)
        ]
      end
    end)

    error_items =
      if reg.error do
        [text(""), text(reg.error, fg: theme.error.fg, style: [:bold])]
      else
        []
      end

    rows ++ error_items
  end
end
```

### `input_key/1` helper (maps `focused_field` to map key)

```elixir
# Source: [VERIFIED: login.ex:139-140 post-Phase-1 pattern, extended]
defp input_key(:invite_code),      do: :invite_code_input
defp input_key(:handle),           do: :handle_input
defp input_key(:email),            do: :email_input
defp input_key(:password),         do: :password_input
defp input_key(:confirm_password), do: :confirm_input
```

---

## Runtime State Inventory

> Phase 2 is a rename/migration phase for `state.register_wizard`.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — `register_wizard` is transient in-memory session state only, never persisted to DB | N/A |
| Live service config | None — `registration_mode` is read from `Foglet.Config` (ETS) at render time; no persistent wizard state | N/A |
| OS-registered state | None | N/A |
| Secrets/env vars | None — `@log_verify_codes` is compile-env; no runtime secret | N/A |
| Build artifacts | None — no egg-info, no compiled artifact embeds `register_wizard` | N/A |

**All categories:** None — verified by direct read of register.ex, app.ex, and login.ex. `state.register_wizard` is an in-memory session map field; no persistence layer stores it. Migration is purely a code change (remove field from struct + rewrite accessors).

---

## Environment Availability

> Phase has no external dependencies beyond the existing Elixir/OTP runtime and Raxol.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Elixir/OTP | Runtime | Yes | (project mix.exs) | — |
| Raxol | TUI framework | Yes | vendored in deps/ | — |
| ExUnit | Tests | Yes | built-in | — |
| `mix precommit` | CI gate | Yes | defined in mix.exs | — |
| `TextInput.init(mask_char: "*")` | Password + confirm fields | Yes | verified in text_input.ex:65 | — |
| `TextInput` `bordered: false` option | All fields | Yes | verified in text_input.ex:103 | — |

**Missing dependencies with no fallback:** None.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | ExUnit (built-in) |
| Config file | `test/test_helper.exs` |
| Quick run command | `mix test test/foglet_bbs/tui/screens/register_test.exs` |
| Full suite command | `mix precommit` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| REGISTER-01 | TextInput adopted; password + confirm fields use mask | unit | `mix test test/foglet_bbs/tui/screens/register_test.exs` (extend) | Yes — extend |
| REGISTER-02 | Wizard step dispatcher uses pattern-matched `render_step/2` | grep | `rg "render_step\|render_invite\|render_combined" lib/foglet_bbs/tui/screens/register.ex` | N/A — shell |
| REGISTER-03 | `with` chain in `submit/2` | unit | `mix test test/foglet_bbs/tui/screens/register_test.exs` (submit describe block) | Yes — extend |
| REGISTER-04 | `apply/3` + `credo:disable` preserved verbatim | grep | `rg "credo:disable-for-next-line" lib/foglet_bbs/tui/screens/register.ex` returns exactly one match | N/A — shell |
| REGISTER-05 | AUDIT rubric passes | grep + unit | See AUDIT-05 gates below | Yes — extend |
| REGISTER-06 | `state.register_wizard` → `state.screen_state[:register]`; round-trip tests | unit | `mix test test/foglet_bbs/tui/screens/register_test.exs` (new wizard round-trip + cancel describe blocks) | Wave 0 gap |

### Existing Test Coverage (register_test.exs — 293 lines)

Current tests cover the OLD API (`state.register_wizard`, `{:submit_step, step, value}` dispatch). All existing tests break after Phase 2 and must be rewritten to use the new state shape.

**Tests that need rewriting (all of them):**

| Describe block | Test count | Migration note |
|----------------|------------|----------------|
| `render/1` | 1 | Update `base_state` to use `screen_state[:register]` instead of `register_wizard:` |
| `wizard sequence (D-23)` | 4 | Rewrite: step advance now moves `focused_field` within `:combined` step; cancel returns to `:login` |
| `submit/2 — VERIFY-01 routing` | 2 | Update state assertions: `state.register_wizard == nil` → `get_in(state, [:screen_state, :register]) == nil` or cleared |
| `cancel` | 1 | `state.register_wizard == nil` → `Map.get(state.screen_state, :register) == nil` |
| `handle_key/2 — character input` | 8 | Old tests check `state.register_wizard.current_input`; new tests check `reg.handle_input.raxol_state.value` |
| `handle_wizard_event/2 — step reset` | 2 | Old tests check `state.register_wizard.step`; new tests check focused_field + `screen_state[:register].step` |

### New Tests Required (REGISTER-06 Watch List (iv))

```
describe "wizard round-trip (Phase 2 two-step)" do
  test "open mode: combined step — focus advances handle → email → password → confirm"
  test "open mode: Enter on confirm_password with matching passwords → submit"
  test "open mode: Enter on confirm_password with mismatching passwords → error, no submit"
  test "invite_only mode: invite_code step → combined step on valid code"
  test "invite_only mode: invalid invite_code stays on invite_code step with error"
  test "sysop_approved mode: starts directly on combined step (no invite_code step)"
  test "Tab cycles all four fields in combined step"
  test "cancel flow: Escape returns to :login and clears screen_state[:register]"
  test "init_screen_state/1 returns a map with correct keys and TextInput structs"
end
```

### AUDIT-05 Grep Gates

| Gate # | Pattern | Command | Expected |
|--------|---------|---------|---------|
| 1 | Named color atoms | `rg ':red\|:green\|:cyan\|:yellow\|:blue\|:magenta\|:white\|:black' lib/foglet_bbs/tui/screens/register.ex` | Zero |
| 2 | Hex literals | `rg '"#[0-9a-fA-F]{6}"' lib/foglet_bbs/tui/screens/register.ex` | Zero |
| 3 | Raw ANSI | `rg '\\\\e\\\[' lib/foglet_bbs/tui/screens/register.ex` | Zero |
| 8 | Inlined theme | `rg 'Map\.get.*session_context.*Map\.get.*:theme' lib/foglet_bbs/tui/screens/register.ex` | Zero |
| 9 | Inlined domain | `rg 'get_in.*\[:domain' lib/foglet_bbs/tui/screens/register.ex` | Zero |

### Additional grep verification commands

```bash
# REGISTER-06: No remaining register_wizard references in register.ex
rg "register_wizard" lib/foglet_bbs/tui/screens/register.ex
# Expected: zero

# REGISTER-06: No remaining register_wizard in login.ex
rg "register_wizard" lib/foglet_bbs/tui/screens/login.ex
# Expected: zero

# REGISTER-06: No remaining register_wizard in app.ex beyond the dispatch clause
rg "register_wizard" lib/foglet_bbs/tui/app.ex
# Expected: exactly the one do_update dispatch clause at ~line 354

# REGISTER-04: credo:disable preserved
rg "credo:disable-for-next-line" lib/foglet_bbs/tui/screens/register.ex
# Expected: exactly one match

# AUDIT-16: Line count
wc -l lib/foglet_bbs/tui/screens/register.ex
# Expected: strictly less than 294

# AUDIT-19: init_screen_state/1 present
rg "def init_screen_state" lib/foglet_bbs/tui/screens/register.ex
# Expected: exactly one match

# AUDIT-18: canonical section order smoke check
rg "def init_screen_state|def render|def handle_key|def handle_wizard_event|defp handle_|defp render_|defp get_register_ss|defp put_register_ss|defp submit|defp valid_invite" lib/foglet_bbs/tui/screens/register.ex
# Expected: functions appear in canonical section order (3 → 4 → 5 → 6 → 7 → 8 → 9 → 10)
```

### Sampling Rate

- **Per task commit:** `mix test test/foglet_bbs/tui/screens/register_test.exs`
- **Per wave merge:** `mix precommit`
- **Phase gate:** Full suite green + all grep gates return expected values

### Wave 0 Gaps

- [ ] `test/foglet_bbs/tui/screens/register_test.exs` — ALL existing tests must be rewritten (new state shape); new wizard round-trip + cancel describe blocks must be added. The existing 293-line file tests the old API verbatim.
- [ ] `base_state/1` fixture in register_test.exs must be updated to populate `screen_state: %{register: init_screen_state_for(state)}` instead of `register_wizard:`.

---

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | Register creates accounts; auth is login screen |
| V3 Session Management | Yes | Session promoted or verify screen entered after registration |
| V4 Access Control | No | N/A for registration flow |
| V5 Input Validation | Yes | TextInput max_length (default 256); handle/email/password validated by domain layer |
| V6 Cryptography | Yes | Password hashing via Argon2 in `Accounts.register_user/1` (domain layer, not touched) |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Account enumeration via handle | Information Disclosure | Domain layer returns generic changeset errors; TUI displays `changeset_error_text/1` without leaking timing |
| Confirm-password bypass | Tampering | Screen-side validation (D-03) before calling `submit/2`; no API endpoint accepts unconfirmed passwords |
| Invite code brute-force | Elevation of Privilege | `valid_invite_code?/1` calls `Accounts.consume_invite_code/1` which is destructive on success — codes are single-use |

**This phase is a UI refactor only** — no changes to account creation, password hashing, or session management logic.

---

## Open Questions

1. **`init_screen_state/1` mode defaulting**
   - What we know: D-05 requires no-arg (or opts-only) signature. Mode requires `state`. `get_register_ss/1` has access to state.
   - What's unclear: Whether `init_screen_state/1` should default to `"open"` (mode-unaware) and rely on `get_register_ss/1` for mode-aware bootstrap, or whether the planner should thread `state` through a different way.
   - Recommendation: `init_screen_state/1` returns mode `"open"` default (AUDIT-19 compliant stub). `get_register_ss/1` calls a private `init_screen_state_for(state)` on cache miss, which reads the live mode. This matches Phase 1's `enter_login_form/1` pattern for fresh init.

2. **`handle_wizard_event/2` inlining vs. keeping public**
   - What we know: AUDIT-18 §6 is for public domain-hook callbacks called from `app.ex`. The dispatch clause at `app.ex:354` calls `Screens.Register.handle_wizard_event/2`.
   - What's unclear: Whether to keep it public (easiest — no app.ex changes beyond the field removal) or inline into `do_update`.
   - Recommendation (Claude's Discretion): Keep `handle_wizard_event/2` public. Changing `app.ex:354` to inline would require a larger edit and risk the scope fence. Public function in §6 is idiomatic per AUDIT-18.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `login.ex:maybe_register/1` in the post-Phase-1 file (lines 230-249) still writes `register_wizard:` | login.ex change inventory | LOW — verified by direct read of current login.ex (line 238-246) |
| A2 | `first_step_for_mode/1` in login.ex (line 252-253) becomes dead code after the `register_wizard:` write is removed | login.ex change | LOW — verified: only caller is `maybe_register/1` |
| A3 | The `submit/2` `with` chain can preserve all four branches (verify, main_menu, changeset error, build_verify_code error) | Pattern 3 | LOW — all branches identified; `with` + `else` covers them |
| A4 | Line count will land below 294 with the identified deletions and additions | AUDIT-16 | MEDIUM — net delta is close; planner must be disciplined with render helper brevity |

---

## Sources

### Primary (HIGH confidence)

- `lib/foglet_bbs/tui/screens/register.ex` — current 294-LoC implementation, all functions inventoried
- `lib/foglet_bbs/tui/screens/login.ex` — post-Phase-1 reference implementation (entire file read)
- `lib/foglet_bbs/tui/widgets/input/text_input.ex` — TextInput contract: `init/1`, `handle_event/2`, `render/2`, struct shape
- `lib/foglet_bbs/tui/app.ex:1-76, 290-380` — `@type t`, `defstruct`, `do_update` dispatch
- `test/foglet_bbs/tui/screens/register_test.exs` — 293-line existing test file; all tests reference old API
- `.planning/workstreams/phase-03-screen-audit/phases/02-register/02-CONTEXT.md` — locked decisions D-01..D-10
- `.planning/workstreams/phase-03-screen-audit/phases/01-login/01-CONTEXT.md` — Phase 1 patterns D-01..D-08
- `.planning/workstreams/phase-03-screen-audit/phases/01-login/01-RESEARCH.md` — Phase 1 research (patterns, pitfalls)
- `.planning/workstreams/phase-03-screen-audit/REQUIREMENTS.md` — REGISTER-01..06, AUDIT-05..22

### Secondary (MEDIUM confidence)

- `.planning/workstreams/phase-03-screen-audit/phases/01-login/01-01-PLAN.md` — Phase 1 plan structure as analog for plan shape

### Tertiary (LOW confidence)

- None — all findings grounded in direct file reads.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — TextInput contract fully read; Phase 1 pattern verified in completed login.ex
- Architecture: HIGH — all touch points identified via direct file reads; exact line numbers verified
- Pitfalls: HIGH — drawn from Phase 1 research, CLAUDE.md gotchas, and direct analysis of the old vs. new state shapes
- Line count estimate: MEDIUM — approximate; planner must verify at end of plan

**Research date:** 2026-04-21
**Valid until:** 30 days (stable internal domain; no external dependency changes possible)
