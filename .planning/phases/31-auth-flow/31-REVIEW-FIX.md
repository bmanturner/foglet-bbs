---
phase: 31-auth-flow
fix_scope: all
findings_in_scope: 9
fixed: 8
skipped: 1
iteration: 1
status: partial
---

# Phase 31: Code Review Fix Report

**Fixed at:** 2026-04-27
**Source review:** `.planning/phases/31-auth-flow/31-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 9 (1 Critical, 4 Warning, 4 Info — `--all`)
- Fixed: 8
- Skipped: 1 (WR-003: distinction is load-bearing for non-reset flow)

All targeted test suites green after every fix:

- `test/foglet_bbs/accounts/verification_test.exs` (17 tests)
- `test/foglet_bbs/accounts_verify_code_test.exs` (11 tests)
- `test/foglet_bbs/tui/screens/login_test.exs` (73 tests)
- `test/foglet_bbs/tui/layout_smoke_test.exs` (87 tests)

`rtk mix precommit` is fully green (compile w/ warnings-as-errors,
format, credo --strict, sobelow, dialyzer).

## Fixed Issues

### CR-001: `[T]` shortcut shadows character input on the reset_request form

**Files modified:** `lib/foglet_bbs/tui/screens/login.ex`,
`test/foglet_bbs/tui/screens/login_test.exs`
**Commit:** `780ebd8`
**Applied fix:** Dropped the bare `t`/`T` character interceptor from
`handle_reset_key/2` so all characters reach `identifier_input`.
Updated the dispatched/no-email user-facing copy to instruct the user
on the Esc → menu → [T] route. Removed `[T]` from the
`:reset_request` keys footer hint. Replaced the two existing tests
that asserted the buggy behaviour with new contracts: typing `t` or
`T` appends to `identifier_input` and keeps `:sub == :reset_request`.
Added a positive D-15 regression test that asserts `[T]` from the
Login menu (`base_state()`) still enters `:reset_consume`.

### WR-001: Email-shape regex duplicated across modules

**Files modified:** `lib/foglet_bbs/accounts/verification.ex`,
`lib/foglet_bbs/tui/screens/login.ex`
**Commit:** `92d25e9`
**Applied fix:** Exposed `Foglet.Accounts.Verification.email_shape?/1`
as the single source of truth for the local D-02 email-shape gate.
`Foglet.TUI.Screens.Login` now delegates its private
`email_shape?/1` to the boundary helper instead of holding its own
copy of the regex. Refactored the boundary's private
`find_reset_delivery_user/1` to use the same predicate (DRY) instead
of `Regex.match?(@email_shape_regex, _)` directly.

### WR-002: `LoginState.toggle_focus/1` accepts non-login-form sub-states

**Files modified:** `lib/foglet_bbs/tui/screens/login/state.ex`
**Commit:** `724b2ec`
**Applied fix:** Constrained pattern matching on `sub: :login_form`
in both `toggle_focus/1` clauses, removing the permissive
`%{focused_field: _}` catch-all. Any future caller that invokes
`toggle_focus/1` from a non-login-form sub-state will now raise
`FunctionClauseError` immediately rather than silently writing
`focused_field: :handle` into a state that does not own that atom.
Live behaviour unchanged (the only caller is `handle_form_key`, which
is gated by `sub: :login_form`).

### WR-004: `request_password_reset_delivery/1` discards `Repo.insert` failures

**Files modified:** `lib/foglet_bbs/accounts/verification.ex`
**Commits:** `1d9a79e` (primary fix), `02d60dd` (Credo follow-up)
**Applied fix:** Replaced the silent `with`-discarded `Repo.insert`
result in `maybe_deliver_password_reset/1` with an explicit `case`.
On `{:ok, _token}` the mailer is invoked as before; on `{:error,
%Ecto.Changeset{}}` the changeset errors are now logged at error
level so backend persistence failures become diagnosable. The outward
boundary remains generic (`{:ok, :generic_response}` always returned)
so enumeration safety is preserved. Added `require Logger`. The
follow-up commit `02d60dd` inlines the diagnostic detail
(`user_id=… errors=…`) into the message string rather than passing
them as Logger metadata, because credo-strict flagged those metadata
keys as not being registered in the project's Logger metadata
config — same forensic value, no global config dependency. The raw
token is never logged (D-11).

### IN-001: `@verify_code_length` overloaded for byte count and char count

**Files modified:** `lib/foglet_bbs/accounts/user_token.ex`
**Commit:** `8ad0e51`
**Applied fix:** Introduced `@verify_code_random_bytes` (entropy
source byte count) alongside `@verify_code_length` (base32
truncation length). Both are 6 today so behaviour is unchanged, but
a future contributor bumping either constant for entropy reasons
will no longer accidentally break the 6-character user-facing
contract. Added an explanatory comment block documenting that base32
of 6 random bytes is already ~10 chars and only the first 6 are
kept.

### IN-002: `LoginState.input_key/1` raises on unknown atoms

**Files modified:** `lib/foglet_bbs/tui/screens/login/state.ex`
**Commit:** `375303b`
**Applied fix:** Added an explicit `t:focused_field/0` typedoc that
enumerates the contract (`:handle | :password | :identifier |
:token | :password_confirmation`) and refined the `@spec` of
`input_key/1` to use it. Kept the exhaustive (no-fallthrough)
behaviour because adding a permissive default would *mask*
state-corruption bugs by silently routing unknown atoms to
`:handle`. The exhaustiveness is now load-bearing documentation,
not an oversight.

### IN-003: `LoginState.get/1` fallback returns a login-form-shaped map

**Files modified:** `lib/foglet_bbs/tui/screens/login/state.ex`
**Commit:** `fefe67a`
**Applied fix:** Replaced the misleading login-form-flavored stub
(`%{focused_field: nil, handle_input: nil, password_input: nil,
error: nil}`) with `%{}`. In practice `handle_key/2` routes through
`LoginState.sub(state)` before any consumer calls `get/1`, so the
fallback is unreachable on the live path; with `%{}` an unexpected
fall-through fails fast at the consumer's first `Map.fetch!/2`
instead of producing visually-corrupt render output. Updated the
moduledoc to explain the rationale.

### IN-004: Test "no_email mode falls back honestly" lacks fallback assertion

**Files modified:** `test/foglet_bbs/tui/screens/login_test.exs`
**Commit:** `46a8d59`
**Applied fix:** Added a positive
`assert rendered =~ "No sysop contact email is published"` to the
no-sysops fallback test. The previous body matched only
`~r/sysop|operator/i`, which is satisfied by the intro copy alone —
the test would have passed even if
`@reset_no_email_no_sysops_fallback` had never been inserted into
the rendered output. The literal string is now a regression sentinel
for the fallback's existence and rendering.

## Skipped Issues

### WR-003: `verify_email_code/2` returns distinguishable error tags

**File:** `lib/foglet_bbs/accounts/verification.ex:73-87`
**Reason:** Skipped — distinction is load-bearing for the
non-reset email-verification flow, NOT just a copy-only consideration.

`grep -rn verify_email_code lib/ test/` shows the live caller is
`lib/foglet_bbs/tui/screens/verify.ex:202`
(`Foglet.TUI.Screens.Verify.verify_code/2`). That caller branches
on the two error tags differently:

```elixir
{:error, :expired} ->
  modal = %Foglet.TUI.Modal{
    type: :error,
    message: "Code expired. Press [R] to request a new one."
  }
  # Buffer is cleared but no attempt counter increment.

{:error, :invalid_code} ->
  handle_invalid_code(state, vs)
  # Increments attempt counter and triggers lockout / cooldown after
  # `@max_attempts`.
```

Collapsing the two tags to `:invalid_or_expired` would:
1. Cause expired-code attempts to count toward the lockout — a
   genuine UX regression for users whose code expired through no
   fault of their own.
2. Lose the helpful "Press [R] to request a new one" copy that is
   only triggered on `:expired`.

The `verify_email_code/2` function is shared with the
email-verification flow at signup, which is **out of scope for
Phase 31** (reset only). The reviewer's own note acknowledges
this is "a footgun for the *next* surface" rather than a live
leak. Per the project_specifics directive in the fix prompt:

> If callers rely on distinguishing those tags for flow routing
> (not just user-facing copy), collapsing them could break unrelated
> flows. … document the deviation in REVIEW-FIX.md as "skipped —
> distinction is load-bearing for non-reset flows" rather than
> blindly collapsing.

The reviewer's secondary suggestion ("add a sentence to the
moduledoc that consumers must collapse them in user copy") is also
declined for this iteration: the verify-screen copy genuinely
*does* differentiate (rate-limit vs expiry), which is correct
behaviour for that surface, and a moduledoc warning that consumers
"MUST collapse" would be misleading. A future phase that
introduces a new surface (e.g., an HTTP API) consuming this
function should re-evaluate whether to collapse at the API
boundary rather than at the function boundary.

**Original issue:** "`verify_email_code/2` returns
`{:error, :invalid_code}` for an unknown code and
`{:error, :expired}` for a code whose row exists but is past the
15-minute window. … the two-tag return contract gives any TUI/API
consumer the option to render distinct copy, which would
re-introduce the same enumeration leak D-12 forbids on the reset
side, in a different surface."

---

_Fixed: 2026-04-27_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
