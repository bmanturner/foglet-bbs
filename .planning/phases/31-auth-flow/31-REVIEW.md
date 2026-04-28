---
phase: 31-auth-flow
reviewed: 2026-04-27T00:00:00Z
depth: standard
files_reviewed: 7
files_reviewed_list:
  - lib/foglet_bbs/accounts/user_token.ex
  - lib/foglet_bbs/accounts/verification.ex
  - lib/foglet_bbs/tui/screens/login.ex
  - lib/foglet_bbs/tui/screens/login/state.ex
  - test/foglet_bbs/accounts/verification_test.exs
  - test/foglet_bbs/tui/layout_smoke_test.exs
  - test/foglet_bbs/tui/screens/login_test.exs
findings:
  critical: 1
  warning: 4
  info: 4
  total: 9
status: issues_found
---

# Phase 31: Code Review Report

**Reviewed:** 2026-04-27
**Depth:** standard
**Files Reviewed:** 7
**Status:** issues_found

## Summary

The auth-flow implementation is largely sound: the atomic single-use claim
in `consume_reset_token/2` correctly relies on PostgreSQL row locks via
`delete_all` inside `Repo.transact/1`, the verify-then-claim sequence
short-circuits cleanly when the row was already consumed, generic
`:invalid_or_expired` collapses every token-failure mode, and the screen
respects D-11 by keeping the raw token off chrome/breadcrumb/key-hint paths
(verified by sentinel tests). Test coverage on the critical paths
(concurrent consumption, expired token, malformed token, rolled-back password
validation) is strong.

The review found **one BLOCKER** in the reset-request key router: bare
`t`/`T` characters are intercepted as the "Enter reset token" shortcut even
while the identifier text input is focused, which makes it impossible for a
user to type any email address containing `t` or `T` into the Forgot
Password form. This regresses the most basic input contract of that screen.
Several smaller WARNING-level concerns and INFO-level cleanups follow.

## Critical Issues

### CR-001: `[T]` shortcut shadows character input on the reset_request form

**File:** `lib/foglet_bbs/tui/screens/login.ex:169-170`
**Severity:** BLOCKER
**Issue:**
Inside `handle_reset_key/2` (the key router for `sub: :reset_request`),
the `[T] Enter reset token` shortcut is matched before the catch-all that
forwards events to `identifier_input`:

```elixir
defp handle_reset_key(%{key: :char, char: c}, state) when c in ["t", "T"],
  do: enter_reset_consume(state)

defp handle_reset_key(event, state) do
  login_ss = LoginState.get(state)
  {new_input, _action} = TextInput.handle_event(event, login_ss.identifier_input)
  ...
end
```

The reset request flow's identifier field is a free-text email input. Any
user attempting to type an email that contains `t` or `T` — for example
`taylor@example.com`, `bot@bot.test`, `bfturner@foglet.io`, or any address
on a `.test` / `.toot` / `.tv` TLD — has those keystrokes silently
hijacked, jumping the screen into `:reset_consume` and discarding the
partially-typed identifier (because `enter_reset_consume/1` builds a fresh
form via `LoginState.reset_consume()`, line 73-81 of `state.ex`).

This is an unconditional regression on the email input contract. It is
also not required by D-15 (which only says token entry must be reachable
from both the menu and the Forgot Password flow — it does not specify a
bare-character shortcut). The same shortcut is correctly menu-only for
`:menu` (line 119-120) where the screen has no free-text input, and the
`:reset_consume` router (lines 184-211) does not steal `t`/`T`.

The existing test "[T] enters reset_consume sub-state from reset_request
(D-15)" (login_test.exs:556-564) seeds the identifier with
`"alice@example.test"` and presses `T`, verifying the shortcut works — but
no test asserts the inverse: that typing `t` or `T` into a partially-typed
identifier appends the character. So this regression is invisible to the
suite as written.

**Fix:**
Either make the shortcut a non-character key combination (e.g., `Ctrl+T`
or `F2`), or — preferable for keyboard-only TUIs — drop the bare-character
shortcut from the `:reset_request` router entirely. Token entry remains
reachable from the menu via `[T]`, satisfying D-15. Suggested patch:

```elixir
# DELETE these two lines (login.ex:169-170):
# defp handle_reset_key(%{key: :char, char: c}, state) when c in ["t", "T"],
#   do: enter_reset_consume(state)
```

If the affordance is judged worth keeping on this screen, route it through
a non-printable key (e.g., bind to `:f2` or require `Ctrl+T`), and
update `keys_for(:reset_request, _)` accordingly so the hint advertises
the actual keystroke.

Add a regression test:

```elixir
test "typing 't' or 'T' into the identifier field appends to the input, not the [T] shortcut" do
  state = reset_request_state("alice@example.")
  {:update, after_t, []} = Login.handle_key(%{key: :char, char: "t"}, state)
  assert get_in(after_t, [:screen_state, :login, :sub]) == :reset_request
  assert get_in(after_t, [:screen_state, :login, :identifier_input,
                          Access.key(:raxol_state), :value]) == "alice@example.t"
end
```

## Warnings

### WR-001: Email-shape regex duplicated across modules with no shared source

**File:** `lib/foglet_bbs/accounts/verification.ex:15`,
`lib/foglet_bbs/tui/screens/login.ex:49`
**Issue:**
Two copies of the same `~r/^[^@\s]+@[^@\s]+\.[^@\s]+$/` regex live in two
modules. The Login screen's comment explicitly notes it "mirrors"
`Verification`'s, but there is no compile-time link between them. If one
side is ever loosened (e.g., to permit `+` aliases or IDN domains) and
the other isn't, the screen and the boundary will silently disagree —
either letting input through that the boundary later rejects (UI lies) or
blocking input the boundary would accept (UX regression). D-02 makes this
shape an explicit invariant.

**Fix:**
Expose the regex (and a `email_shape?/1` predicate) from one module and
have the other call it:

```elixir
# In Foglet.Accounts.Verification
@email_shape_regex ~r/^[^@\s]+@[^@\s]+\.[^@\s]+$/
def email_shape?(value) when is_binary(value), do: Regex.match?(@email_shape_regex, value)

# In Foglet.TUI.Screens.Login — drop the local copy and call:
defp email_shape?(value), do: Verification.email_shape?(value)
```

### WR-002: `LoginState.toggle_focus/1` accepts and silently corrupts non-login-form sub-states

**File:** `lib/foglet_bbs/tui/screens/login/state.ex:110-111`
**Issue:**
`toggle_focus/2` matches `%{focused_field: _}` in its second clause, so
any caller passing a `:reset_consume` sub-state map (whose
`focused_field` is `:token`, `:password`, or `:password_confirmation`)
would silently get `focused_field: :handle` written back — an atom that
is invalid for the reset-consume cycle and would crash subsequent
`LoginState.input_key/1` lookups (no clause for `:handle` would match the
reset-consume input keys; actually `:handle` resolves to `:handle_input`,
which doesn't exist in a reset-consume sub-state, so the next render or
keystroke would dereference `nil`).

Today this is reachable only from `handle_form_key`, which is itself
gated by `sub: :login_form`, so the bug is latent. But the function is
not pattern-matched on `:sub`, so a future refactor that calls it from a
different sub-state would silently break the screen.

**Fix:**
Constrain pattern-matching so the function only mutates login-form
state, and make any other shape an explicit error:

```elixir
def toggle_focus(%{sub: :login_form, focused_field: :handle} = ss),
  do: %{ss | focused_field: :password}
def toggle_focus(%{sub: :login_form, focused_field: :password} = ss),
  do: %{ss | focused_field: :handle}
```

### WR-003: `verify_email_code/2` returns distinguishable error tags for missing vs expired codes

**File:** `lib/foglet_bbs/accounts/verification.ex:73-87`
**Issue:**
`verify_email_code/2` returns `{:error, :invalid_code}` for an unknown
code and `{:error, :expired}` for a code whose row exists but is past the
15-minute window. The phase context locks D-10/D-12 generic-copy
treatment for the *reset* path; D-08 ("short-lived codes don't need
hashing") suggests verify codes are intentionally less hardened. But the
two-tag return contract gives any TUI/API consumer the option to render
distinct copy, which would re-introduce the same enumeration leak D-12
forbids on the reset side, in a different surface.

The current TUI verify screen is out of this phase's scope, so this is
not a live leak — it is a footgun for the *next* surface that consumes
this function.

**Fix:**
Either collapse the two error tags at the boundary (preferred for
consistency with `consume_reset_token/2`), or document the distinction
with a `@doc` warning that callers MUST present identical user-facing
copy for the two cases. Suggested API change:

```elixir
@spec verify_email_code(User.t(), String.t()) ::
        {:ok, User.t()} | {:error, :invalid_or_expired}
```

If the phase-31 lock genuinely intends to keep the two tags, add a
sentence to the moduledoc that consumers must collapse them in user
copy.

### WR-004: `request_password_reset_delivery/1` discards `Repo.insert` failures silently

**File:** `lib/foglet_bbs/accounts/verification.ex:99-112`,
`lib/foglet_bbs/accounts/verification.ex:248-257`
**Issue:**
The pipeline

```elixir
identifier
|> String.trim()
|> find_reset_delivery_user()
|> maybe_deliver_password_reset()

{:ok, :generic_response}
```

discards the result of `maybe_deliver_password_reset/1`. That function's
inner `with` returns `{:error, %Ecto.Changeset{}}` if `Repo.insert`
fails (e.g., a constraint violation, DB transient error) but the caller
ignores it. For enumeration safety the *outward* response must remain
generic, but right now there is no telemetry / log emission either, so
a backend-induced failure to persist a reset token is invisible to
operators. A user reporting "I never got my reset email" cannot be
distinguished from a silent persistence failure.

**Fix:**
Preserve the generic outward response, but log the internal failure:

```elixir
defp maybe_deliver_password_reset(%User{} = user) do
  {raw_token, token_struct} = UserToken.build_email_token(user, "reset_password")

  case Repo.insert(token_struct) do
    {:ok, _token} ->
      _ = Foglet.Mailer.deliver(Email.password_reset(user, raw_token))
      :ok

    {:error, changeset} ->
      Logger.error("password_reset token insert failed",
        user_id: user.id, errors: inspect(changeset.errors))
      :ok
  end
end
```

This keeps the outward boundary generic while making backend failures
diagnosable.

## Info

### IN-001: `@verify_code_length` overloaded for both byte count and char count

**File:** `lib/foglet_bbs/accounts/user_token.ex:29, 187-192`
**Issue:**
`generate_verify_code/0` reuses the same constant `@verify_code_length =
6` for two semantically distinct quantities: (a) the number of random
bytes to generate (`:crypto.strong_rand_bytes(@verify_code_length)`),
and (b) the truncation length of the base32 encoding
(`binary_part(0, @verify_code_length)`). Six random bytes encode to
~10 base32 chars, of which only the first 6 are kept — so the actual
code entropy is 30 bits regardless of how many bytes are sampled. A
future contributor reading "generate verify code length 6" could
plausibly bump this to 8 thinking they get more entropy and inadvertently
break the verify-code byte-length contract.

**Fix:**
Split the constant:

```elixir
@verify_code_random_bytes 6
@verify_code_length 6

defp generate_verify_code do
  :crypto.strong_rand_bytes(@verify_code_random_bytes)
  |> Base.encode32(padding: false)
  |> binary_part(0, @verify_code_length)
  |> String.upcase()
end
```

### IN-002: `LoginState.input_key/1` raises on unknown atoms

**File:** `lib/foglet_bbs/tui/screens/login/state.ex:114-119`
**Issue:**
`input_key/1` has clauses only for the five known field atoms; any
other atom raises `FunctionClauseError`. This is fine when callers are
disciplined, but the function is consumed via
`FocusInput.get_focused/3` and `update_focused/4` with a fallback atom
of `:handle`, so a state whose `focused_field` is set to an unexpected
atom (e.g., from a future refactor) crashes the screen instead of
gracefully falling back.

**Fix:**
Add a fallthrough clause that returns a safe default, or document the
exhaustive contract explicitly with `@type focused_field :: :handle |
:password | :identifier | :token | :password_confirmation` and a
matching `@spec`.

### IN-003: `LoginState.get/1` fallback returns a login-form-shaped map

**File:** `lib/foglet_bbs/tui/screens/login/state.ex:92-95`
**Issue:**
When `state.screen_state[:login]` is missing, `get/1` returns
`%{focused_field: nil, handle_input: nil, password_input: nil, error:
nil}` — a login-form-flavored stub that silently masks the missing-state
condition. For reset-flow callers this stub will yield `nil` access
results that flow into TextInput rendering. The function is currently
called only after `LoginState.put/2` has populated state, so this is
latent, but the fallback shape is misleading.

**Fix:**
Return an empty map (`%{}`) and let the caller pattern-match for
required keys; or raise on missing state, since by the time `get/1` is
called the state should always be present.

### IN-004: Test "no_email mode falls back honestly when no sysops exist" does not assert the fallback message

**File:** `test/foglet_bbs/tui/screens/login_test.exs:511-525`
**Issue:**
The test name promises a fallback assertion, but the body only asserts
the rendered text matches `~r/sysop|operator/i` (which is satisfied by
the *intro* copy and would still pass even if
`@reset_no_email_no_sysops_fallback` were never inserted). The honest
no-sysops fallback message ("No sysop contact email is published on
this Foglet…") is never asserted.

**Fix:**
Add a positive assertion on the fallback string:

```elixir
assert rendered =~ "No sysop contact email is published"
```

This locks down the fallback behaviour the constant's existence
implies.

---

_Reviewed: 2026-04-27_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
