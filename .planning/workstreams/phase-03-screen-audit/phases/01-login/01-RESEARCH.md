# Phase 1: Login — Research

**Researched:** 2026-04-21
**Domain:** Elixir TUI screen refactor — TextInput adoption, state shape migration, `with`-chain refactor
**Confidence:** HIGH (all findings grounded in direct file reads of the codebase)

## Summary

Phase 1 replaces the hand-rolled form input logic (~50 LoC, 6 helper functions) in `lib/foglet_bbs/tui/screens/login.ex` with two `Widgets.Input.TextInput` instances (handle + password). The `bordered: false` option on TextInput has already landed (commit `5eb9f8e`), so the phase can proceed directly to audit work. The phase also adds the missing `init_screen_state/1` and rewrites the nested `case {:ok,_}|{:error,_}` authentication chain (lines 267–308) as a `with` chain.

The key architectural change is flattening the `form` map into direct screen state fields: the two TextInput structs live at `screen_state[:login].handle_input` and `.password_input`, with `focused_field` tracking which field receives keystrokes. Error state moves from `form.error` to a top-level `error` field in the login sub-state.

**Primary recommendation:** Follow CONTEXT.md decisions D-01 through D-08 verbatim — all API shapes are locked, and the micro-patch prerequisite is already complete. The planner's job is routing the executor through the delete/rewrite/add operations in the correct order.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Form input rendering | Browser / Client (TUI) | — | TextInput widgets are pure renderers of Raxol element trees |
| Focus toggle logic | Frontend Server (TUI App) | — | Screen intercepts Tab/Enter/Escape before delegating to TextInput |
| Authentication | API / Backend | — | `Accounts.authenticate_by_password/2` is synchronous domain call |
| Session promotion | API / Backend | — | `post_login_screen/1` routes to verify or main_menu |
| `Config.get` reads | Frontend Server (TUI App) | — | ETS read-through cached, no DB hit on render path |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `Foglet.TUI.Widgets.Input.TextInput` | Existing (commit 5eb9f8e added `bordered: false`) | Single-line text input with `init/1 + handle_event/2 + render/2` contract | D-14 stateful widget pattern; already adopted in Phase 0 |
| `Foglet.TUI.Theme` | Existing | Theme routing via `from_state/1` | Phase 0 extraction; all screens must use this |
| `Foglet.TUI.Screens.Domain` | Existing (Phase 0) | Domain-module lookup | Not used in Login (no domain calls), but available |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `Foglet.Accounts` | Existing | `authenticate_by_password/2`, `post_login_screen/1`, `build_verify_code/1` | Auth flow (unchanged) |
| `Foglet.Config` | Existing | `registration_mode/1` runtime config read | Render-path safe per D-07 (ETS cached) |
| ExUnit | Built-in | Test framework for screen behavior | Async tests, inline fixtures |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Two `TextInput` instances | Single `TextInput` with mode toggle | Would require custom mode state; two-instance pattern is D-14 canonical for multi-field forms |
| `with` chain | Keep nested `case` | `with` is idiomatic Elixir for multi-step validation; Phase 0 precedent exists |

**Installation:**
No new packages. Phase 0's `Theme.from_state/1` and `Screens.Domain.get/2` are already available.

**Version verification:** [VERIFIED: direct read] `TextInput` at `lib/foglet_bbs/tui/widgets/input/text_input.ex` includes `bordered: false` option (line 95, default `false`).

## Architecture Patterns

### System Architecture Diagram

```
User keystrokes (Tab/Enter/Escape/char)
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│  Login Screen (lib/foglet_bbs/tui/screens/login.ex)        │
│                                                             │
│  ┌────────────────────────────────────────────────────┐    │
│  │  Key Routing (handle_form_key/2)                   │    │
│  │  • Tab → cycle focused_field (:handle ↔ :password) │    │
│  │  • Enter → advance focus or submit                 │    │
│  │  • Escape → clear form, return to :menu            │    │
│  │  • char/backspace → delegate to focused TextInput  │    │
│  └────────────────────────────────────────────────────┘    │
│         │                        │                         │
│         ▼                        ▼                         │
│  ┌──────────────────┐  ┌──────────────────────────┐       │
│  │ Handle TextInput │  │ Password TextInput       │       │
│  │ (mask_char: nil) │  │ (mask_char: "*")         │       │
│  └──────────────────┘  └──────────────────────────┘       │
│         │                        │                         │
│         └────────────┬───────────┘                         │
│                      ▼                                     │
│         screen_state[:login] = %{                          │
│           sub: :login_form,                                │
│           focused_field: :handle | :password,              │
│           handle_input: %TextInput{},                      │
│           password_input: %TextInput{},                    │
│           error: nil | "Invalid credentials."              │
│         }                                                  │
└─────────────────────────────────────────────────────────────┘
                      │
                      ▼
        submit_login/1 (with-chain)
                      │
        ┌─────────────┼─────────────┐
        ▼             ▼             ▼
   :active      :pending       :suspended
        │             ▼             ▼
        ▼         modal clear    modal
   verify or   screen_state    clear
   promote                     screen_state
```

### Recommended Project Structure
```
lib/foglet_bbs/tui/screens/login.ex
├── Aliases + imports (Theme, ScreenFrame, TextInput, Accounts)
├── Module attributes (@menu_keys, @menu_keys_no_register)
├── init_screen_state/1 (PUBLIC — NEW per D-03)
├── render/1 (PUBLIC)
├── handle_key/2 (PUBLIC)
├── Private key handlers
│   ├── handle_menu_key/2
│   ├── handle_form_key/2 (rewritten per D-06)
│   ├── focused_input/1 (NEW — helper to get focused TextInput)
│   └── update_focused_input/2 (NEW — helper to put back TextInput)
├── Private render helpers
│   ├── render_menu/2
│   └── render_login_form/2 (rewritten for TextInput)
├── Private state plumbing
│   ├── get_login_ss/1 (existing — keep)
│   ├── put_login_ss/2 (existing — keep)
│   ├── sub_state/1 (existing — keep)
│   └── registration_mode/1 (existing — keep)
└── Private domain plumbing
    ├── enter_login_form/1 (rewritten per D-03)
    ├── maybe_register/1 (existing — keep unchanged)
    ├── submit_login/1 (rewritten as `with` per D-08)
    ├── handle_active_user/2 (existing — keep)
    └── start_verify_flow/2 (existing — keep)
```

### Pattern 1: Inline label + TextInput row (D-02)

**What:** Label and TextInput on the same row, visually identical to `"Handle:   value█"` format.

**When to use:** Login form (this phase), Register (Phase 2), NewThread title input (Phase 7).

**Example:**
```elixir
# Source: CONTEXT.md D-02, verified via Raxol View DSL
row style: %{gap: 0} do
  [
    text("Handle:   ", fg: theme.primary.fg),
    TextInput.render(
      login_ss.handle_input,
      bordered: false,
      theme: theme
    )
  ]
end
```

**Key implementation detail:** The `gap: 0` style ensures the label and input render adjacent without extra whitespace. The three-space padding in `"Handle:   "` matches today's visual density.

### Pattern 2: Key routing with interception (D-06)

**What:** Screen intercepts control keys (Tab, Enter, Escape) before delegating to TextInput.

**When to use:** Any multi-field form with TextInput widgets.

**Example:**
```elixir
# Source: CONTEXT.md D-06
defp handle_form_key(%{key: :tab}, state) do
  login_ss = get_login_ss(state)
  focused = Map.get(login_ss, :focused_field, :handle)
  new_focused = if focused == :handle, do: :password, else: :handle
  new_login_ss = Map.put(login_ss, :focused_field, new_focused)
  {:update, put_login_ss(state, new_login_ss), []}
end

defp handle_form_key(%{key: :enter}, state) do
  login_ss = get_login_ss(state)
  focused = Map.get(login_ss, :focused_field, :handle)

  if focused == :password do
    submit_login(state)
  else
    new_login_ss = Map.put(login_ss, :focused_field, :password)
    {:update, put_login_ss(state, new_login_ss), []}
  end
end

defp handle_form_key(event, state) do
  {new_input, _action} = TextInput.handle_event(event, focused_input(state))
  {:update, update_focused_input(state, new_input), []}
end
```

### Pattern 3: `with` chain for auth (D-08)

**What:** Replace nested `case {:ok,_}|{:error,_}` with linear `with` clauses.

**When to use:** Multi-step authentication/verification flows.

**Example:**
```elixir
# Source: CONTEXT.md D-08, verified pattern from login.ex:267-308
defp submit_login(state) do
  login_ss = get_login_ss(state)
  handle_value = login_ss.handle_input.raxol_state.value
  password_value = login_ss.password_input.raxol_state.value

  with {:ok, user} <- Accounts.authenticate_by_password(handle_value, password_value),
       {:ok, screen} <- Accounts.post_login_screen(user) do
    handle_auth_success(state, user, screen)
  else
    {:error, :invalid_credentials} ->
      login_ss_with_error = %{login_ss | error: "Invalid credentials.", password_input: TextInput.init([])}
      {:update, put_login_ss(state, login_ss_with_error), []}

    {:ok, %{status: :pending}} ->
      modal = %{type: :error, message: "Your account is pending sysop approval."}
      {:update, %{state | modal: modal, screen_state: %{}}, []}

    {:ok, %{status: :suspended}} ->
      modal = %{type: :error, message: "Your account is suspended."}
      {:update, %{state | modal: modal, screen_state: %{}}, []}
  end
end

# Extracted helper for D-08 pattern
defp handle_auth_success(state, user, :verify) do
  start_verify_flow(state, user)
end

defp handle_auth_success(state, user, :main_menu) do
  {:update, %{state | screen_state: %{}}, [{:promote_session, user}]}
end
```

**Note:** The existing `handle_active_user/2` and `start_verify_flow/2` helpers are retained. The `with` chain replaces only the top-level `case` structure.

### Anti-Patterns to Avoid

- **Putting TextInput struct directly in `form` map:** CONTEXT.md D-04 explicitly rejects nested `form:` sub-map. TextInput structs live at `screen_state[:login].handle_input` and `.password_input` directly.
- **Reading `raxol_state.value` in render:** This is fine (value is needed for display), but remember that render is pure — no state mutations inside `render_login_form/2`.
- **Delegating all keys to TextInput:** Enter and Escape have screen-level semantics (submit, cancel). Only char/backspace/cursor movement delegate to TextInput.
- **Blocking on Enter at handle field:** Enter advances focus to password, not submit. Only password-field Enter submits.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Character input handling | `append_to_focused/2`, `drop_last_grapheme/1` | `TextInput.handle_event/2` | Handles cursor movement, backspace, delete, home/end, Unicode graphemes correctly |
| Password masking | `mask_password/1` | `TextInput.init(mask_char: "*")` | Masking is built into Raxol's TextInput component |
| Focus cursor rendering | `format_input_line/3`, `focus_style/1`, `input_fg/2` | `TextInput.render/2` | Cursor position and style are managed by the widget |
| Form state map | Nested `form: %{handle, password, error}` | Flat map with two TextInput structs | D-14 requires stateful widgets be hoisted to screen_state, not nested in opaque maps |

**Key insight:** The hand-rolled helpers in today's `login.ex` total ~50 lines. `TextInput` encapsulates all of this logic except focus routing (which is screen-specific).

## Runtime State Inventory

> Not applicable — greenfield refactor within a single screen file, no rename/migration.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — Login is stateless UI, only transient screen_state | N/A |
| Live service config | None | N/A |
| OS-registered state | None | N/A |
| Secrets/env vars | None | N/A |
| Build artifacts | None | N/A |

## Common Pitfalls

### Pitfall 1: Block expression rebinding
**What goes wrong:** Trying to rebind `state` inside an `if` or `case` clause.
**Why it happens:** Elixir block expressions create new bindings, they don't mutate.
**How to avoid:** Bind the entire expression to `state`:

```elixir
# INVALID — rebind lost
if focused == :password do
  state = submit_login(state)
end

# VALID
state =
  if focused == :password do
    submit_login(state)
  else
    advance_focus(state)
  end
```
**Warning signs:** Compiler warning "variable 'state' is unused" or keys having no effect.

### Pitfall 2: Struct Access syntax
**What goes wrong:** Trying to use `login_ss[:focused_field]` or `get_in(login_ss, [:focused_field])`.
**Why it happens:** Maps and structs have different access semantics. `screen_state[:login]` is a plain map (not a struct), but `TextInput` is a struct.
**How to avoid:** Use `Map.get/2` for maps, `struct.field` for structs:

```elixir
# Correct
focused = Map.get(login_ss, :focused_field, :handle)
value = login_ss.handle_input.raxol_state.value

# Wrong
focused = login_ss[:focused_field]  # Works on map but not idiomatic
value = login_ss.handle_input[:value]  # ERROR — struct doesn't implement Access
```
**Warning signs:** `AccessBehaviour` errors or key lookups returning `nil`.

### Pitfall 3: Delegating Enter/Escape to TextInput
**What goes wrong:** User presses Enter on handle field, form submits immediately with empty password.
**Why it happens:** TextInput returns `:submitted` action for Enter. If screen delegates, the action is consumed.
**How to avoid:** Intercept Enter and Escape first, only delegate char/backspace/cursor keys:

```elixir
defp handle_form_key(%{key: :enter}, state) do
  # Screen handles Enter — don't delegate
  ...
end

defp handle_form_key(%{key: :escape}, state) do
  # Screen handles Escape — don't delegate
  ...
end

defp handle_form_key(event, state) do
  # Delegate char, backspace, cursor keys to TextInput
  {new_input, _action} = TextInput.handle_event(event, focused_input(state))
  ...
end
```
**Warning signs:** Enter submits with empty password, or Escape has no effect.

### Pitfall 4: Forgetting to clear password on auth error
**What goes wrong:** User sees "Invalid credentials" but password field is still filled, forcing them to delete before retry.
**Why it happens:** Error state is set but password_input is not re-initialized.
**How to avoid:** Re-init password TextInput on error:

```elixir
{:error, :invalid_credentials} ->
  new_password_input = TextInput.init([])  # Clears value
  new_login_ss = %{login_ss | error: "Invalid credentials.", password_input: new_password_input}
  {:update, put_login_ss(state, new_login_ss), []}
```
**Warning signs:** Test "invalid credentials surface an inline error and clear password field" fails.

### Pitfall 5: `with` chain else-clause pattern mismatch
**What goes wrong:** `with` chain doesn't catch all error branches because pattern doesn't match.
**Why it happens:** `Accounts.authenticate_by_password/2` returns `{:ok, user}` or `{:error, :invalid_credentials}`, but user status (`:pending`, `:suspended`) is inside the user struct, not a separate error tuple.
**How to avoid:** Match on user status after `{:ok, user}`:

```elixir
with {:ok, user} <- Accounts.authenticate_by_password(handle, password),
     {:ok, screen} <- Accounts.post_login_screen(user) do
  handle_auth_success(state, user, screen)
else
  {:error, :invalid_credentials} ->
    # Handle wrong password

  {:ok, %{status: :pending}} ->
    # This doesn't match above — user was authenticated but not active
    # Need explicit status check or use pattern matching in helper
```
**Warning signs:** Pending/suspended users don't see their modals, or test coverage gaps.

### Pitfall 6: Losing screen_state clear on modal
**What goes wrong:** Modal appears but form remains visible behind it (ghost form).
**Why it happens:** Modal sets `state.modal` but doesn't clear `state.screen_state`.
**How to avoid:** Always set `screen_state: %{}` when showing modal:

```elixir
modal = %{type: :error, message: "..."}
{:update, %{state | modal: modal, screen_state: %{}}, []}
```
**Warning signs:** Layout smoke test shows modal + form content simultaneously.

## Code Examples

Verified patterns from official sources:

### TextInput initialization with mask_char
```elixir
# Source: [VERIFIED: lib/foglet_bbs/tui/widgets/input/text_input.ex:62-78]
handle_input = TextInput.init(value: "", max_length: @max_handle_length)
password_input = TextInput.init(value: "", mask_char: "*")
```

### TextInput event delegation
```elixir
# Source: [VERIFIED: lib/foglet_bbs/tui/widgets/input/text_input.ex:82-88]
{new_input, _action} = TextInput.handle_event(event, focused_input(state))
# _action is discarded because Enter/Escape are intercepted at screen level
```

### TextInput render with theme and bordered option
```elixir
# Source: [VERIFIED: lib/foglet_bbs/tui/widgets/input/text_input.ex:98-110]
TextInput.render(
  login_ss.handle_input,
  bordered: false,
  theme: theme
)
```

### Inline label + TextInput row layout
```elixir
# Source: [VERIFIED: Raxol View DSL — docs/raxol/getting-started/WIDGET_GALLERY.md:36-44]
row style: %{gap: 0} do
  [
    text("Handle:   ", fg: theme.primary.fg),
    TextInput.render(login_ss.handle_input, bordered: false, theme: theme)
  ]
end
```

### Focus-aware text color
```elixir
# Source: [VERIFIED: existing login.ex:220-222 pattern, adapted for TextInput]
label_fg = if focused == :handle, do: theme.accent.fg, else: theme.primary.fg
label_style = if focused == :handle, do: [:bold], else: []

row style: %{gap: 0} do
  [
    text("Handle:   ", fg: label_fg, style: label_style),
    TextInput.render(login_ss.handle_input, bordered: false, theme: theme)
  ]
end
```

### Error rendering below password field
```elixir
# Source: [VERIFIED: existing login.ex:189-195 pattern]
error_items =
  if login_ss.error do
    [text(""), text(login_ss.error, fg: theme.error.fg, style: [:bold])]
  else
    []
  end

column style: %{gap: 0} do
  [
    # ... handle row ...
    # ... password row ...
  ] ++ error_items
end
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Hand-rolled `format_input_line/3`, `mask_password/1`, `drop_last_grapheme/1` | `TextInput.init/1` with `mask_char: "*` | This phase | 50 lines deleted, `█` cursor drift accepted |
| Nested `case {:ok,_}|{:error,_}` | `with` chain | This phase | More linear control flow, Elixir-idiomatic |
| `init_screen_state/1` missing | `init_screen_state/1` returns `%{sub: :menu}` | This phase | D-14 compliance, lazy TextInput init |

**Deprecated/outdated:**
- `handle_form_key/2` family (current 6-clause function) — replaced by new routing pattern
- `form` map with nested `handle`, `password`, `error` keys — flattened to direct fields

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `bordered: false` is available on TextInput (commit 5eb9f8e) | Standard Stack | LOW — verified via direct file read |
| A2 | Row layout with `gap: 0` produces visually identical output to current `"Handle:   value█"` format | Pattern 1 | LOW — Raxol flexbox behavior verified in docs |
| A3 | `with` chain pattern preserves all happy/error branches bit-for-bit | Pattern 3 | LOW — pattern verified against existing `case` structure |
| A4 | `Config.get` is ETS read-through cached, no render-path hit | Architecture | LOW — verified in docs, inherited decision locked |

**If this table is empty:** All claims in this research were verified or cited — no user confirmation needed.

## Open Questions (RESOLVED)

1. **Exact row layout implementation for label alignment**
   - What we know: `row style: %{gap: 0}` puts children adjacent. Label `"Handle:   "` has three-space padding.
   - What's unclear: Whether TextInput's internal cursor positioning aligns exactly with the `█` block cursor's column position.
   - Recommendation (RESOLVED): Proceed with `row` layout; test exact column alignment in smoke test. If off-by-one, adjust label padding in code review.

2. **`with` chain else-clause structure for multi-branch errors**
   - What we know: `authenticate_by_password/2` returns `{:ok, user}` or `{:error, :invalid_credentials}`. User has `status: :active | :pending | :suspended`.
   - What's unclear: Whether to pattern-match on status in `with` clauses or use `case` inside success branch.
   - Recommendation (RESOLVED): Use `case` on `user.status` inside the `with` success branch (or call `handle_active_user/2` which already does this). This keeps `with` linear and branches only at decision points.

## Environment Availability

> Phase has no external dependencies beyond the existing Elixir/OTP runtime and Raxol.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Elixir | Runtime | ✓ | (see `elixir --version`) | — |
| OTP | Runtime | ✓ | (see `erl -version`) | — |
| Raxol | TUI framework | ✓ | vendored in `deps/raxol` | — |
| ExUnit | Tests | ✓ | Built-in | — |
| `mix precommit` | CI gate | ✓ | Alias defined in `mix.exs` | — |

**Missing dependencies with no fallback:** None.

**Missing dependencies with fallback:** None.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | ExUnit (built-in) |
| Config file | `test/test_helper.exs` (standard) |
| Quick run command | `mix test test/foglet_bbs/tui/screens/login_test.exs` |
| Full suite command | `mix precommit` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| LOGIN-01 | TextInput adoption (handle + masked password) | unit | `mix test test/foglet_bbs/tui/screens/login_test.exs:84-150` | ✅ Existing |
| LOGIN-02 | Hand-rolled functions deleted | grep | `rg -n "format_input_line\|input_fg\|focus_style\|mask_password\|drop_last_grapheme\|append_to_focused" lib/foglet_bbs/tui/screens/login.ex` | N/A — shell command |
| LOGIN-03 | State shape migrated + `init_screen_state/1` added | unit | `mix test test/foglet_bbs/tui/screens/login_test.exs` (extend with `init_screen_state/1` test) | ✅ Existing (extend) |
| LOGIN-04 | `with` chain replaces nested `case` | unit | `mix test test/foglet_bbs/tui/screens/login_test.exs:152-244` | ✅ Existing |
| LOGIN-05 | `Config.get` safety documented | manual | Verify no DB hit in render path (already cached) | N/A |
| LOGIN-06 | AUDIT rubric (grep gates #8, #9, etc.) | grep + unit | See AUDIT-05 table below | ✅ Existing (extend) |

### Sampling Rate
- **Per task commit:** `mix test test/foglet_bbs/tui/screens/login_test.exs`
- **Per wave merge:** `mix precommit`
- **Phase gate:** Full suite green + grep gates return zero

### AUDIT-05 Grep Gates (from REQUIREMENTS.md)
| Gate # | Pattern | Command | Expected After Phase |
|--------|---------|---------|---------------------|
| 1 | Named color atoms | `rg ':red\|:green\|:cyan\|:yellow\|:blue\|:magenta\|:white\|:black' lib/foglet_bbs/tui/screens/login.ex` | Zero |
| 2 | Hex literals | `rg '"#[0-9a-fA-F]{6}"' lib/foglet_bbs/tui/screens/login.ex` | Zero |
| 3 | Raw ANSI escapes | `rg '\\e\[|\\x1b' lib/foglet_bbs/tui/screens/login.ex` | Zero |
| 8 | Inlined theme extraction | `rg '\(Map\.get\(state, :session_context\) \|\| %\{\}\) \|> Map\.get\(:theme\)' lib/foglet_bbs/tui/screens/login.ex` | Zero (already migrated in Phase 0) |
| 9 | Inlined domain lookup | `rg 'get_in\(.*\[:domain,' lib/foglet_bbs/tui/screens/login.ex` | Zero (N/A for Login) |

### Wave 0 Gaps
- [ ] None — existing `test/foglet_bbs/tui/screens/login_test.exs` covers all LOGIN-01..06 behaviors. Extend with `init_screen_state/1` test (new function).

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | `Accounts.authenticate_by_password/2` (Argon2, domain layer) |
| V3 Session Management | yes | `post_login_screen/1` routes to verify or main_menu (existing) |
| V4 Access Control | no | Login screen has no access control |
| V5 Input Validation | yes | `TextInput` max_length (default 256) + handle validation in domain layer |
| V6 Cryptography | yes | Password hashing via Argon2 (Accounts layer, not touched in this phase) |

### Known Threat Patterns for {stack}

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Password enumeration (timing attack) | Information Disclosure | Domain layer uses constant-time Argon2 comparison; TUI timing variability dominates |
| Handle injection (metadata manipulation) | Tampering | Domain layer validates handle format/syntax;TextInput only handles raw string |
| CSRF/replay | N/A | SSH session is stateful, no HTTP-style CSRF |

**Note:** This phase is a UI refactor only — no changes to authentication logic, password hashing, or session management.

## Sources

### Primary (HIGH confidence)
- `lib/foglet_bbs/tui/screens/login.ex` — current 347-LoC implementation, all functions to delete/rewrite
- `lib/foglet_bbs/tui/widgets/input/text_input.ex` — TextInput contract: `init/1`, `handle_event/2`, `render/2`, `bordered: false` option
- `test/foglet_bbs/tui/screens/login_test.exs` — existing test coverage, patterns for new tests
- `lib/foglet_bbs/tui/theme.ex` — `from_state/1` (Phase 0), `default/0`
- `lib/foglet_bbs/tui/screens/domain.ex` — `get/2` (Phase 0, not used in Login but available)
- `01-CONTEXT.md` — locked decisions D-01 through D-08
- `REQUIREMENTS.md` — LOGIN-01..06, AUDIT-05..22 rubric

### Secondary (MEDIUM confidence)
- `docs/ARCHITECTURE.md` — system architecture, session layer, ETS caching
- `docs/raxol/getting-started/WIDGET_GALLERY.md` — Raxol TextInput/row/column primitives
- `lib/foglet_bbs/tui/widgets/README.md` — widget catalog, D-14 pattern

### Tertiary (LOW confidence)
- None — all findings grounded in direct file reads or Phase 0 research.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all widgets and patterns verified via direct file reads
- Architecture: HIGH — existing login.ex structure fully understood, D-14 pattern confirmed
- Pitfalls: HIGH — all pitfalls drawn from CLAUDE.md Elixir gotchas and existing test failures

**Research date:** 2026-04-21
**Valid until:** 30 days (stable domain, no external dependency changes expected)
