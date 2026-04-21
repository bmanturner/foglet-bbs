---
phase: 06-email-verification-toggle-resend
fixed_at: 2026-04-20T20:15:00Z
review_path: .planning/workstreams/phase-03-polish/phases/06-email-verification-toggle-resend/06-REVIEW.md
iteration: 1
findings_in_scope: 7
fixed: 7
skipped: 0
status: all_fixed
---

# Phase 06: Code Review Fix Report

**Fixed at:** 2026-04-20T20:15:00Z
**Source review:** .planning/workstreams/phase-03-polish/phases/06-email-verification-toggle-resend/06-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 7
- Fixed: 7
- Skipped: 0

## Fixed Issues

### WR-01: `expired_exists?/2` never returns `true` — `:expired` branch is unreachable

**Files modified:** `lib/foglet_bbs/accounts.ex`
**Commit:** d5e4ee2
**Applied fix:** Added a time-filter condition (`t.inserted_at <= ago(^validity, "minute")`) to `expired_exists?/2` so it only returns `true` when the specific submitted code exists in the DB AND is outside the validity window. This prevents a wrong code from matching an old expired row and incorrectly surfacing as `:expired` after a resend. Uses `UserToken.email_verify_validity_minutes/0` for the validity constant.

---

### WR-02: `resend_code_raw/1` resets `cooldown_until` and `attempts` unconditionally

**Files modified:** `lib/foglet_bbs/tui/screens/verify.ex`
**Commit:** 6b9470a
**Applied fix:** Added documentation to `@moduledoc` explicitly stating that the reset of `attempts` and `cooldown_until` on a successful resend is intentional (D-09): a fresh code makes any previous attempt count meaningless. Clarifies this is a deliberate UX design decision and does not bypass security since the old code is invalidated when a new one is issued.

---

### WR-03: `safe_config_get/2` ignores the passed `default` parameter (catch-all rescue)

**Files modified:** `lib/foglet_bbs/tui/screens/login.ex`, `lib/foglet_bbs/tui/screens/register.ex`
**Commit:** eef6f40
**Applied fix:** Replaced the `safe_config_get/2` private helper (which used a catch-all `rescue _`) with a direct call to `Config.get/2` in both modules. `Config.get/2` already handles missing keys with a default via its own narrowly-scoped rescue, eliminating the catch-all pattern. Also resolves IN-01 (duplicate function) as a side effect — see below.

---

### WR-04: Bare `{:ok, code} = Accounts.build_verify_code(user)` crashes on DB failure

**Files modified:** `lib/foglet_bbs/tui/screens/login.ex`, `lib/foglet_bbs/tui/screens/register.ex`, `config/dev.exs`
**Commit:** c7ea1a3
**Applied fix:** Replaced the bare match with a `case` expression in both modules. The `{:error, _cs}` branch shows a user-friendly error modal instead of crashing the SSH session. In `login.ex`, the verify branch was extracted into a private `start_verify_flow/2` helper to keep `submit_login/1` within the cyclomatic complexity threshold. Also resolves IN-02 (Mix.env runtime check) as part of the same commit — see below.

---

### IN-01: Duplicate `safe_config_get/2` between Login and Register

**Files modified:** `lib/foglet_bbs/tui/screens/login.ex`, `lib/foglet_bbs/tui/screens/register.ex`
**Commit:** eef6f40
**Applied fix:** Resolved as part of WR-03 fix. Both copies of `safe_config_get/2` were removed and replaced with direct `Config.get/2` calls, eliminating the duplication entirely without needing a shared module.

---

### IN-02: `Mix.env()` used at runtime in production code paths

**Files modified:** `lib/foglet_bbs/tui/screens/login.ex`, `lib/foglet_bbs/tui/screens/register.ex`, `config/dev.exs`
**Commit:** c7ea1a3
**Applied fix:** Replaced the `if Mix.env() != :prod` runtime check with a `@log_verify_codes Application.compile_env(:foglet_bbs, :log_verify_codes, false)` module attribute in both `login.ex` and `register.ex`. Added `config :foglet_bbs, :log_verify_codes, true` to `config/dev.exs` to preserve dev-time code logging. The flag is now resolved at compile time, which is the correct Elixir pattern.

---

### IN-03: Seeds use a hardcoded dev password; no comment noting dev-only intent

**Files modified:** `priv/repo/seeds.exs`
**Commit:** 23204d9
**Applied fix:** Added a three-line comment above the seed user creation block noting that seeds are dev-only fixtures, the password is a well-known dev value, and `mix run priv/repo/seeds.exs` must never be run against a production database.

---

_Fixed: 2026-04-20T20:15:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
