---
phase: 02-register
reviewed: 2026-04-21T00:00:00Z
depth: standard
files_reviewed: 6
files_reviewed_list:
  - lib/foglet_bbs/tui/app.ex
  - lib/foglet_bbs/tui/screens/login.ex
  - lib/foglet_bbs/tui/screens/register.ex
  - test/foglet_bbs/tui/layout_smoke_test.exs
  - test/foglet_bbs/tui/screens/login_test.exs
  - test/foglet_bbs/tui/screens/register_test.exs
findings:
  critical: 0
  warning: 3
  info: 2
  total: 5
status: issues_found
---

# Phase 02: Code Review Report

**Reviewed:** 2026-04-21
**Depth:** standard
**Files Reviewed:** 6
**Status:** issues_found

## Summary

The phase-02 migration is structurally sound. The core deliverables — moving register state from
`state.register_wizard` to `screen_state[:register]`, adopting `Input.TextInput` for all four
fields, and the `with`-chain submission pipeline — are correctly implemented. The `handle_key/2`
clause ordering (escape before catch-all) is correct. No named colors, no raw ANSI, no
`IO.write/puts` appear in screen files.

Three issues require attention before this phase closes:

1. **Two smoke tests crash at runtime** — `layout_smoke_test.exs` has login-form state fixtures
   using the pre-TextInput shape (`form: %{handle: ..., password: ...}` nested inside) that no
   longer matches what `Login.render` expects. `Login.render` will raise `KeyError` on those tests.
2. **`register.ex` `@spec` omits `:no_match`** — the declared return type for `handle_key/2` is
   inconsistent with every other screen's spec and the contract `app.ex` pattern-matches against,
   which will produce a Dialyzer warning.
3. **`do_update({:register_wizard, event})` returns `handle_wizard_event`'s result unwrapped** —
   the call site in `app.ex:352-354` returns the bare result of `handle_wizard_event/2` directly,
   which works because `handle_wizard_event/2` returns `{state, commands}`. However, the `else`
   branches of `process_screen_commands` dispatch `{:register_wizard, ...}` tuples through
   `do_update/2`, which then calls `handle_wizard_event/2` and returns its `{state, commands}`.
   This chain is correct, but it means `handle_wizard_event/2` is both a `do_update` terminal AND
   called from `process_screen_commands`. The existing test at `register_test.exs:289-296` that
   asserts the command tuple `{:register_wizard, ...}` is emitted verifies this path, but there is
   no test that exercises the full round-trip through `app.ex` to confirm the result is not
   double-wrapped. Noted as a warning.

---

## Warnings

### WR-01: Stale login-form state fixture causes `KeyError` crash in smoke tests

**File:** `test/foglet_bbs/tui/layout_smoke_test.exs:79-107, 246-271, 468-479`

**Issue:** Three tests construct `screen_state[:login]` using the old pre-TextInput shape:

```elixir
login: %{
  sub: :login_form,
  form: %{handle: "alice", password: "secret", error: nil},  # stale — pre-TextInput
  focused_field: :handle
}
```

`Login.render` calls `get_login_ss/1`, which returns this map intact (it's truthy, so the
fallback default is not used). `render_login_form` then evaluates `login_ss.error` — but `:error`
is not a top-level key in this map (it's nested inside `:form`), so Elixir raises `KeyError`.
Even if that were fixed, `TextInput.render(login_ss.handle_input, ...)` would receive `nil`
because `:handle_input` is also absent.

The login screen was migrated to TextInput structs in a prior phase, but these three smoke-test
fixtures were not updated.

**Fix:** Replace the stale state fixture with the correct post-TextInput shape, mirroring the
pattern already used correctly in the same file at lines 278-307 and in `login_test.exs`:

```elixir
alias Foglet.TUI.Widgets.Input.TextInput

state = %App{
  screen_state: %{
    login: %{
      sub: :login_form,
      focused_field: :handle,
      handle_input: TextInput.init(value: "alice"),
      password_input: TextInput.init(value: "", mask_char: "*"),
      error: nil
    }
  },
  terminal_size: {80, 24}
}
```

Apply the same correction to the three affected test bodies (lines 80-89, 248-258, 470-479).
The `TI.init(value: "alice")` pattern is already established at line 289 of the same file.

---

### WR-02: `@spec handle_key/2` in `register.ex` is missing `| :no_match`

**File:** `lib/foglet_bbs/tui/screens/register.ex:76`

**Issue:** The spec reads:

```elixir
@spec handle_key(map(), map()) :: {:update, map(), list()}
```

Every other screen in the codebase declares:

```elixir
@spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
```

`app.ex:337-347` pattern-matches the return of `screen_module.handle_key/2` against both
`{:update, ...}` and `:no_match`. Dialyzer will warn that the `:no_match` branch is unreachable
for a value typed as `{:update, map(), list()}`. This is consistent with `mix precommit`
running Dialyzer.

Note: register's `handle_key/2` *does* correctly never return `:no_match` at runtime (all keys
are consumed), so the spec as written is accurate. The fix is still warranted for contract
uniformity and to eliminate the Dialyzer warning.

**Fix:**

```elixir
@spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
```

---

### WR-03: `do_update({:register_wizard, event})` round-trip has no app-level integration test

**File:** `lib/foglet_bbs/tui/app.ex:352-354`

**Issue:** `do_update({:register_wizard, event}, state)` calls `handle_wizard_event/2` and
returns its `{state, commands}` result directly. This is used by `process_screen_commands/2`
when `handle_invite_key` emits `{:register_wizard, {:submit_step, :invite_code, value}}` as a
command. The path is:

```
handle_key → {:update, state, [{:register_wizard, {:submit_step, :invite_code, value}}]}
  → process_screen_commands → do_update({:register_wizard, ...})
    → handle_wizard_event({:submit_step, :invite_code, value}, state)
      → {new_state, []}
```

The `register_test.exs:289-296` test asserts the command tuple is emitted, but stops short of
verifying that the tuple is correctly dispatched through `app.ex` and that the resulting state
transition (`:invite_code` step → `:combined` step, `collected` map updated) is applied. If
`do_update`'s return contract were to change (e.g., someone wraps it in `{:ok, ...}`), this path
would silently break — the state transition would be lost and the screen would stay on
`:invite_code` indefinitely.

**Fix:** Add one integration-level test in `register_test.exs` (or a dedicated `app_test.exs`)
that drives `App.update({:key, %{key: :enter}}, state_on_invite_step)` and asserts the resulting
state has `screen_state[:register].step == :combined`. This test would catch contract drift
between `handle_wizard_event`'s return shape and `do_update`'s expectations.

---

## Info

### IN-01: `init_screen_state/1` hardcodes `mode: "open"` — diverges from runtime behavior

**File:** `lib/foglet_bbs/tui/screens/register.ex:39-51`

**Issue:** The public `init_screen_state/1` always returns `mode: "open"` and `step: :combined`,
regardless of any opts passed. The private `init_screen_state_for/1` (line 296) reads the actual
registration mode from `state.session_context`. In production the lazy call in `get_register_ss/1`
ensures the correct mode is used. However, any future caller invoking the public `init_screen_state/1`
to bootstrap screen state (e.g., pre-populating `screen_state[:register]` during a screen
transition in `app.ex`) will get an "open" state that is wrong for `invite_only` or
`sysop_approved` sites. The existing test (line 114-116) explicitly documents this by asserting
`mode == "open"` with the comment "accepts opts but ignores them".

This is a design trade-off (documented in `02-DISCUSSION-LOG.md`), not a bug today. Flagged so
the divergence between the public stub and the runtime initializer is visible for Phase 8 when
invite code logic is wired.

**Fix (optional):** Add a `@doc false` or `@doc` note to `init_screen_state/1` explicitly
stating it returns an "open"-mode stub and that callers requiring mode-aware init should call
`get_register_ss/1` instead (which is private). Alternatively, accept a `mode:` opt and thread
it through, matching `init_screen_state_for`'s behavior.

---

### IN-02: Bare `rescue _ ->` in login test setup swallows all exception types

**File:** `test/foglet_bbs/tui/screens/login_test.exs:368-372`

**Issue:** The setup block uses:

```elixir
original =
  try do
    Foglet.Config.get!("require_email_verification")
  rescue
    _ -> :not_seeded
  end
```

A bare `rescue _ ->` catches all exceptions including `ArgumentError`, `RuntimeError`, and
`UndefinedFunctionError`. If `Foglet.Config.get!/1` fails for a reason other than a missing key
(e.g., ETS table not started), the failure will be silently swallowed and `:not_seeded` returned,
causing the test to run without its precondition being verified.

**Fix:** Narrow the rescue clause to the specific exception that signals a missing config key, or
use `Foglet.Config.get/2` with a sentinel default:

```elixir
original = Foglet.Config.get("require_email_verification", :not_seeded)
```

This eliminates the try/rescue entirely if `Config.get/2` supports a default.

---

_Reviewed: 2026-04-21_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
