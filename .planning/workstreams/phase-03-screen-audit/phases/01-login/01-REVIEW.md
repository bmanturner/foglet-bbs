---
phase: 01-login
reviewed: 2026-04-21T00:00:00Z
depth: standard
files_reviewed: 2
files_reviewed_list:
  - lib/foglet_bbs/tui/screens/login.ex
  - test/foglet_bbs/tui/screens/login_test.exs
findings:
  critical: 0
  warning: 2
  info: 2
  total: 4
status: issues_found
---

# Phase 01: Code Review Report

**Reviewed:** 2026-04-21
**Depth:** standard
**Files Reviewed:** 2
**Status:** issues_found

## Summary

Reviewed the completed login screen refactor (`login.ex`) and its test suite. The implementation is structurally sound — the `with` chain, TextInput adoption, focus routing, `init_screen_state/1`, and modal clearing all look correct. Two warnings stand out: a missing `mask_char` on the error-branch password reset (which would expose the next password attempt in plaintext), and a non-deterministic test assertion that silently accepts two different outcomes. Two info-level items round out the report.

---

## Warnings

### WR-01: Password mask lost after failed login

**File:** `lib/foglet_bbs/tui/screens/login.ex:270`

**Issue:** On `{:error, :invalid_credentials}`, the password field is cleared by calling `TextInput.init([])` — without `mask_char: "*"`. The new TextInput has no mask, so the next password the user types will display in plaintext until they escape and re-enter the form (which calls `enter_login_form/1`, which correctly passes `mask_char: "*"`).

Compare line 270:
```elixir
new_password_input = TextInput.init([])
```

with line 223 in `enter_login_form/1`:
```elixir
password_input: TextInput.init(mask_char: "*"),
```

**Fix:** Pass `mask_char: "*"` consistently:
```elixir
new_password_input = TextInput.init(mask_char: "*")
```

---

### WR-02: Weakened assertion in pending-user modal test

**File:** `test/foglet_bbs/tui/screens/login_test.exs:320-328`

**Issue:** The test "pending user shows 'pending sysop approval' modal" uses a `case` to accept two different outcomes:

```elixir
case new_state.modal do
  %{type: :error, message: msg} ->
    assert msg =~ "pending"

  nil ->
    # Fallback: password mismatch shows inline error — acceptable but noted
    assert get_in(new_state, [:screen_state, :login, :error]) ==
             "Invalid credentials."
end
```

If `Accounts.authenticate_by_password/2` returns `{:error, :invalid_credentials}` (e.g., because `valid_user_attributes()` returns a map with atom-key `:password` which is retrieved correctly, but the fixture's default password `"correct horse battery"` doesn't match whatever was hashed), the test passes without ever exercising the pending-modal path. The intent of this test is specifically to verify the `:pending` status modal — that intent is obscured and the test can silently pass while verifying the wrong branch.

The immediately following test "Test D: pending user modal sets screen_state to %{}" (line 333) uses `valid_user_attributes(%{password: password})` with an explicit password, which eliminates the ambiguity. The earlier test should adopt the same pattern.

**Fix:** Eliminate the fallback branch by seeding an explicit password:
```elixir
test "pending user shows 'pending sysop approval' modal (D-05)" do
  password = "correct horse battery"
  attrs = valid_user_attributes(%{password: password})
  {:ok, user} = Foglet.Accounts.register_pending_user(attrs)
  assert user.status == :pending

  state = form_state([handle: user.handle, password: password], :password)

  {:update, new_state, _} = Login.handle_key(%{key: :enter}, state)

  assert %{type: :error, message: msg} = new_state.modal
  assert msg =~ "pending"
end
```

---

## Info

### IN-01: Dead branch in fixture attribute extraction

**File:** `test/foglet_bbs/tui/screens/login_test.exs:311-313`

**Issue:** The expression `attrs[:password] || attrs["password"]` attempts both atom-key and string-key access. `valid_user_attributes/0` always returns a map with atom keys (`%{handle: ..., email: ..., password: ...}`), so `attrs[:password]` never returns `nil` and the `attrs["password"]` branch is dead code. This is harmless but creates a false impression that the attributes might have string keys.

**Fix:** Use the atom key directly:
```elixir
password: attrs[:password]
```

---

### IN-02: `get_login_ss/1` fallback has over-specified nil defaults

**File:** `lib/foglet_bbs/tui/screens/login.ex:157-159`

**Issue:** The fallback map returned when no login sub-state exists:
```elixir
%{focused_field: nil, handle_input: nil, password_input: nil, error: nil}
```

This fallback is only ever reached in code paths outside the login form (e.g., during render when `sub == :menu`), where `handle_input` and `password_input` are never accessed. The fallback exists as defensive programming, but the explicit `nil` values create an implicit contract that callers will never dereference `handle_input` without checking. `submit_login/1` at lines 257-258 does dereference these fields directly:

```elixir
handle_value = login_ss.handle_input.raxol_state.value
password_value = login_ss.password_input.raxol_state.value
```

This is safe in practice because `submit_login/1` is only called when `focused_field == :password` (i.e., from the `handle_form_key/2` Enter handler), which is only reachable when `:login_form` is the active sub-state, which guarantees the real TextInput structs are present. But the fallback values would cause a `BadMapError` if the call chain ever violated that invariant.

**Fix:** If the fallback is kept, a pattern-matching guard in `submit_login/1` or a more minimal fallback (just `%{sub: :menu}`) would make the invariant explicit. Alternatively, document the assumption in a `@doc` comment on `submit_login/1`. No code change is required if the invariant is trusted; this is a clarity note.

---

_Reviewed: 2026-04-21_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
