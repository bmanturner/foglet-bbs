---
phase: 06-email-verification-toggle-resend
reviewed: 2026-04-20T19:39:45Z
depth: standard
files_reviewed: 9
files_reviewed_list:
  - lib/foglet_bbs/accounts.ex
  - lib/foglet_bbs/tui/screens/login.ex
  - lib/foglet_bbs/tui/screens/register.ex
  - lib/foglet_bbs/tui/screens/verify.ex
  - priv/repo/seeds.exs
  - test/foglet_bbs/accounts/accounts_test.exs
  - test/foglet_bbs/tui/screens/login_test.exs
  - test/foglet_bbs/tui/screens/register_test.exs
  - test/foglet_bbs/tui/screens/verify_test.exs
findings:
  critical: 0
  warning: 4
  info: 3
  total: 7
status: issues_found
---

# Phase 06: Code Review Report

**Reviewed:** 2026-04-20T19:39:45Z
**Depth:** standard
**Files Reviewed:** 9
**Status:** issues_found

## Summary

This phase adds the email-verification toggle (`require_email_verification` config), a resend-cooldown timer (`email_verify_resend_cooldown_seconds`), and the two-timer model on the Verify screen. The implementation is generally solid — the config-driven routing through `post_login_screen/1`, the independent cooldown clocks, and the `expired_exists?` fallback for the `:expired` error path are all correct in intent.

Four warnings were found, none of which are crash-level bugs but all of which represent real edge-case risks or logic gaps that could surface in production. Three info-level items cover code quality and dead-code patterns.

---

## Warnings

### WR-01: `expired_exists?/2` never returns `true` — `:expired` branch is unreachable

**File:** `lib/foglet_bbs/accounts.ex:241-249`

**Issue:** `verify_email_code/2` calls `expired_exists?/2` to distinguish between a code that existed but expired versus one that never existed at all. However, `verify_code_query/2` in `UserToken` already filters rows to `inserted_at > ago(15, "minute")`, so a valid row is only returned when the code is both correct AND within the 15-minute window. When the code has expired, `Repo.one(verify_code_query(...))` returns `nil`, and the code falls through to `expired_exists?/2`. But `expired_exists?/2` queries `UserToken` with no time filter at all — meaning after the code expires it remains in the table and `expired_exists?` returns `true`, correctly giving `:expired`. So far, fine.

The actual bug: `verify_email_code/2` is also reachable when the code is simply *wrong* (never matched). In that case `expired_exists?` will also return `false` — which is correct. BUT consider the scenario where a user enters a wrong code after their real code has expired. The query in `expired_exists?` matches only on `token == ^code and context == "email_verify" and sent_to == ^email and user_id == ^user_id`. If the wrong code happens to match any other expired row in the table (e.g., from a previous resend), the user would see `:expired` instead of `:invalid_code` — a misleading error message.

More importantly, after a successful `resend_code_raw/1` call, `resend_code_raw/1` calls `build_verify_code/1` which inserts a new row but does NOT delete the old expired token (no cleanup on resend). So multiple `email_verify` rows accumulate for the same user. `expired_exists?` with no time filter will match any of them — including the old expired one — even if the user typed a completely wrong code. Result: a wrong code can surface as `:expired` after a resend.

**Fix:** Delete old `email_verify` tokens for the user before inserting a new one during resend, OR add the time-filter exclusion to `expired_exists?` so it only returns `true` when the *specific submitted code* is expired (i.e., the row exists but is outside the window):

```elixir
defp expired_exists?(%User{id: user_id, email: email}, code) do
  query =
    from t in UserToken,
      where:
        t.token == ^code and t.context == "email_verify" and
          t.sent_to == ^email and t.user_id == ^user_id and
          t.inserted_at <= ago(^UserToken.email_verify_validity_minutes(), "minute")

  Repo.exists?(query)
end
```

Alternatively, clean up old tokens in `resend_code_raw/1`:

```elixir
# In Accounts.build_verify_code/1 or resend_code_raw before inserting
Repo.delete_all(UserToken.by_user_and_contexts_query(user, ["email_verify"]))
```

---

### WR-02: `resend_code_raw/1` resets `cooldown_until` and `attempts` unconditionally — mismatches test expectation in verify_test.exs

**File:** `lib/foglet_bbs/tui/screens/verify.ex:233-258`

**Issue:** `resend_code_raw/1` always sets `cooldown_until: nil` and `attempts: 0` (line 248-249). The test at `verify_test.exs:302-327` ("invalid-attempts cooldown does NOT block resend") explicitly asserts that after a successful resend, `cooldown_until == nil` and `attempts == 0` — so the test was written expecting this reset behavior. However, the `@moduledoc` states the two cooldowns are independent: "hitting invalid 5x still allows a resend; hitting resend once still allows code entry." Silently resetting `cooldown_until` and `attempts` on a successful resend is a more generous behavior than the docs describe, but more importantly it means an attacker who has exhausted their 5 attempts can bypass the invalid-attempt lockout by pressing Resend, then immediately trying codes again with a fresh attempt counter.

**Fix:** Either remove the `cooldown_until: nil` and `attempts: 0` reset from `resend_code_raw/1` and update the test assertion, or document this intentional reset as a design decision. If the intent is that resend resets the attempt counter (fresh code = fresh chance), the test comment should explain why, and the `@moduledoc` should be updated to match:

```elixir
# If resend intentionally resets the attempt counter:
new_vs = %{
  vs
  | buffer: "",
    # A new code means old attempt count is meaningless — reset.
    attempts: 0,
    cooldown_until: nil,
    resend_cooldown_until: DateTime.add(now, cooldown_seconds, :second)
}
```

Or if the reset is unintentional:

```elixir
new_vs = %{
  vs
  | buffer: "",
    resend_cooldown_until: DateTime.add(now, cooldown_seconds, :second)
}
```

---

### WR-03: `safe_config_get/2` ignores the passed `default` parameter

**File:** `lib/foglet_bbs/tui/screens/login.ex:147-151`, `lib/foglet_bbs/tui/screens/register.ex:120-124`

**Issue:** Both `Login` and `Register` define an identical `safe_config_get/2` helper that accepts a `default` parameter but does not use it. `Config.get!/1` (one-arity) raises on a missing key; the `rescue` clause catches the exception and returns the hardcoded `default` argument — but the default is never actually used as a fallback. It *is* returned from the `rescue` clause correctly. Wait — re-reading: the `rescue _ -> default` does return the caller-provided `default` on exception, so the parameter IS used. However, the function ignores the `Config.get!(key)` arity-1 form and never calls `Config.get(key, default)` (two-arity), meaning the `rescue` path is the only fallback path and a missing key silently degrades rather than failing loudly. This is acceptable, but the bigger issue is that if `Config.get!/1` raises for ANY reason other than missing key (e.g., a DB connectivity error during startup), the error is swallowed and the default is used, potentially masking a real problem.

More concretely: the `_` catch-all in `rescue` suppresses every possible error from `Config.get!/1`. A targeted rescue is safer:

**Fix:**
```elixir
defp safe_config_get(key, default) do
  Foglet.Config.get(key, default)
rescue
  e in [Ecto.QueryError, DBConnection.ConnectionError] ->
    require Logger
    Logger.warning("Config.get failed for key #{key}: #{inspect(e)}")
    default
end
```

Or simply use `Config.get/2` if it supports a default directly, avoiding the exception path entirely.

---

### WR-04: `submit_login/1` calls `Accounts.build_verify_code/1` with a bare `{:ok, code} = ...` match — crashes on DB failure

**File:** `lib/foglet_bbs/tui/screens/login.ex:275`

**Issue:** When routing to the verify screen, `submit_login/1` does:

```elixir
{:ok, code} = Accounts.build_verify_code(user)
```

`build_verify_code/1` can return `{:error, changeset}` if the DB insert fails (e.g., constraint violation, connection issue). This bare match will raise `MatchError`, crashing the SSH session handler. The same pattern exists in `register.ex` at line 243.

**Fix:** Pattern-match both outcomes and handle the error gracefully:

```elixir
case Accounts.build_verify_code(user) do
  {:ok, code} ->
    if Mix.env() != :prod do
      require Logger
      Logger.info("[verify] code for @#{user.handle}: #{code}")
    end
    {:update, %{state | current_user: user, current_screen: :verify, ...}, []}

  {:error, _cs} ->
    modal = %{type: :error, message: "Could not generate a verification code. Try again."}
    {:update, %{state | modal: modal}, []}
end
```

Apply the same fix to `register.ex:243`.

---

## Info

### IN-01: Duplicate `safe_config_get/2` between Login and Register

**File:** `lib/foglet_bbs/tui/screens/login.ex:147-151`, `lib/foglet_bbs/tui/screens/register.ex:120-124`

**Issue:** The function is copy-pasted identically in both modules. Any future fix (e.g., for WR-03) must be applied in two places.

**Fix:** Extract to a shared module, e.g. `Foglet.TUI.ConfigHelpers`, or place it in a `Foglet.Config` function as a `get_with_default/2` convenience.

---

### IN-02: `mix_env != :prod` logging check in production code paths

**File:** `lib/foglet_bbs/tui/screens/login.ex:277-280`, `lib/foglet_bbs/tui/screens/register.ex:245-248`

**Issue:** `Mix.env()` is evaluated at runtime, but `Mix.env/0` is intended to be used at compile time only. In a production release (built with `mix release`), `Mix.env/0` will always return `:prod` correctly since the release strips Mix, but relying on it at runtime is a known Elixir anti-pattern. The `require Logger` inside a conditional branch also compiles the Logger metadata into each call site.

**Fix:** Use a module attribute or application config for the dev-mode logging flag:

```elixir
# In config/dev.exs
config :foglet_bbs, :log_verify_codes, true

# In module
@log_verify_codes Application.compile_env(:foglet_bbs, :log_verify_codes, false)

if @log_verify_codes do
  Logger.info("[verify] code for @#{user.handle}: #{code}")
end
```

---

### IN-03: Seeds use a hardcoded dev password; no uniqueness guard on board insert

**File:** `priv/repo/seeds.exs:134`, `priv/repo/seeds.exs:103`

**Issue:** The seed password `"seedpassword123!"` is hardcoded in plain text. This is acceptable for development seeds, but worth noting since the CLAUDE.md flags "don't use `String.to_atom/1` on user input" — seed files run in all environments when `mix run priv/repo/seeds.exs` is invoked directly.

The board insert at line 103 uses `unless Repo.get_by(Board, slug: "general")` — this is idempotent, consistent with the rest of the seeds.

**Fix:** No action required for the board guard. For the password, consider wrapping the seed user creation in an environment check if seeds are run in non-dev environments, or documenting that seeds are dev-only.

---

_Reviewed: 2026-04-20T19:39:45Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
