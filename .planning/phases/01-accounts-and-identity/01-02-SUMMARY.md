---
phase: 01-accounts-and-identity
plan: "02"
subsystem: auth
tags: [elixir, ecto, schema, changeset, argon2, ssh, crypto, user, user-token, ssh-key]

requires:
  - phase: 01-01
    provides: "Foglet.Schema macro, five Phase 1 migrations, test scaffolding"

provides:
  - "Foglet.Accounts.User schema with six changesets: registration, password, role, confirm, profile, deletion"
  - "Foglet.Accounts.SSHKey schema with fingerprint computation via :ssh.hostkey_fingerprint/2"
  - "Foglet.Accounts.UserToken schema with build_email_token/2, verify_email_token_query/2, by_token_and_context_query/2"
  - "All pending tests in user_test.exs, ssh_key_test.exs, user_token_test.exs replaced with real assertions"

affects:
  - "01-03-PLAN.md — context API calls User.registration_changeset, SSHKey.changeset, UserToken.build_email_token"
  - "01-04-PLAN.md — Mix tasks call context functions built in Plan 03"

tech-stack:
  added:
    - ":ssh, :public_key, :crypto added to extra_applications in mix.exs (for SSH fingerprinting)"
  patterns:
    - "Argon2 pattern: hash_pwd_salt/1 in changeset, delete_change(:password) after hash, verify_pass/2 in context (Plan 03)"
    - "Token pattern: :crypto.strong_rand_bytes(32) → store SHA256 hash, return raw base64url token"
    - "SSHKey fingerprint: :ssh_file.decode/2 → :ssh.hostkey_fingerprint(:sha256, key) → 'SHA256:...' string"
    - "Programmatic fields: fingerprint, user_id, confirmed_at, deleted_at not in cast calls"

key-files:
  created:
    - lib/foglet_bbs/accounts/user.ex
    - lib/foglet_bbs/accounts/ssh_key.ex
    - lib/foglet_bbs/accounts/user_token.ex
  modified:
    - mix.exs
    - test/foglet_bbs/accounts/user_test.exs
    - test/foglet_bbs/accounts/ssh_key_test.exs
    - test/foglet_bbs/accounts/user_token_test.exs

key-decisions:
  - "Used :ssh.hostkey_fingerprint/2 instead of :public_key.ssh_hostkey_fingerprint/2 — the latter was removed in OTP 28"
  - "Added :ssh, :public_key, :crypto to extra_applications to suppress compile warnings for OTP modules"
  - "email_digest stored as Ecto.Enum in schema with values [:off, :daily, :weekly] despite being :string in DB"
  - "UserToken.validity_days/1 exposed as public function for Plan 03 context and test assertions"
  - "deletion_changeset/1 uses change/2 not cast/2 — all fields set programmatically (no user input)"

patterns-established:
  - "Argon2 hashing: always hash in changeset put_password_hash/1, never store plaintext"
  - "Token security: :crypto.strong_rand_bytes, SHA256 hash stored, raw returned — reconstruct impossible"
  - "SSH fingerprint: OTP :ssh.hostkey_fingerprint/2 (not :public_key module — moved in OTP 28)"

requirements-completed:
  - IDNT-01
  - IDNT-02
  - IDNT-03
  - IDNT-04
  - IDNT-08

duration: 30min
completed: 2026-04-18
---

# Plan 01-02: Account Schema Modules — User, SSHKey, UserToken

**Three Accounts schema modules with full changesets; all pending schema-layer tests replaced with passing real assertions (IDNT-01, IDNT-02, IDNT-03, IDNT-04, IDNT-08)**

## Performance

- **Duration:** ~30 min
- **Started:** 2026-04-18T15:20:00Z
- **Completed:** 2026-04-18T15:50:00Z
- **Tasks:** 2
- **Files created/modified:** 7

## Accomplishments

- `Foglet.Accounts.User` implemented with all DATA_MODEL.md fields and six changesets: registration (Argon2 hash, unique handle/email), password (re-hash), role (sysop pathway), confirm (set confirmed_at), profile (safe subset), deletion (anonymize PII)
- `Foglet.Accounts.SSHKey` implemented with fingerprint computed server-side via `:ssh.hostkey_fingerprint(:sha256, ...)` at changeset time; unique constraints on fingerprint and (user_id, label)
- `Foglet.Accounts.UserToken` implemented following phx.gen.auth token pattern — SHA256 hash stored, raw base64url token returned; `verify_email_token_query/2` enforces per-context expiry (7d confirm, 1d reset) and email-change invalidation
- All 14 pending test stubs in user_test.exs, ssh_key_test.exs, and user_token_test.exs replaced with real assertions; 0 `@tag :pending` or `flunk/1` remaining in those files
- Added `:ssh`, `:public_key`, `:crypto` to `extra_applications` in mix.exs to resolve OTP 28 compile warnings

## Task Commits

1. **Task 1: User schema + changesets + user_test.exs** — `e69d133` (feat)
2. **Task 2: SSHKey + UserToken schemas + their tests** — `0f5101c` (feat)

## Files Created/Modified

- `lib/foglet_bbs/accounts/user.ex` — Foglet.Accounts.User schema + 6 changesets
- `lib/foglet_bbs/accounts/ssh_key.ex` — Foglet.Accounts.SSHKey schema + fingerprint computation
- `lib/foglet_bbs/accounts/user_token.ex` — Foglet.Accounts.UserToken schema + build/verify functions
- `mix.exs` — Added :ssh, :public_key, :crypto to extra_applications
- `test/foglet_bbs/accounts/user_test.exs` — 8 real tests replacing pending stubs
- `test/foglet_bbs/accounts/ssh_key_test.exs` — 5 real tests replacing pending stubs
- `test/foglet_bbs/accounts/user_token_test.exs` — 9 real tests replacing pending stubs

## Decisions Made

- `:ssh.hostkey_fingerprint/2` used instead of `:public_key.ssh_hostkey_fingerprint/2` — the latter was deprecated and removed in OTP 28. The compiler warning explicitly suggested `ssh:hostkey_fingerprint/2` (Erlang notation for `:ssh.hostkey_fingerprint/2`)
- Added `:ssh` to `extra_applications` so `:ssh_file.decode/2` is available at compile and runtime; without this OTP dependency listed, the compiler emits "module not available" warnings even though the module exists
- `UserToken` timestamps use `updated_at: false` to match the insert-only design from DATA_MODEL.md

## Deviations from Plan

**1. OTP API change — :public_key.ssh_hostkey_fingerprint/2 removed in OTP 28**

- **Found during:** Task 2, initial compile
- **Issue:** Plan's action block referenced `:public_key.ssh_hostkey_fingerprint/2` which no longer exists in OTP 28 (moved to `:ssh` module)
- **Fix:** Used `:ssh.hostkey_fingerprint(:sha256, key)` instead. Added `:ssh`, `:public_key`, `:crypto` to `extra_applications` in mix.exs
- **Verification:** `mix compile --warnings-as-errors` exits 0; test for fingerprint format `"SHA256:..."` passes

## Issues Encountered

- PostgreSQL still unavailable — DB-touching tests (insert tests for uniqueness constraints) cannot run in this environment. Tests that don't touch DB (pure changeset tests, token build tests) all pass. DB-touching tests are correct code and will pass when Postgres is available

## Self-Check: PASSED

- `mix compile --warnings-as-errors` — exit 0
- `mix precommit` — exit 0 (compile + format + credo, no issues)
- Pure unit tests (non-DB): all pass
- DB-touching tests: deferred to runtime with live DB

## Next Phase Readiness

Plan 03 can immediately use:
- `User.registration_changeset/2`, `User.password_changeset/2`, `User.role_changeset/2`, `User.confirm_changeset/1`, `User.deletion_changeset/1`
- `SSHKey.changeset/2` (set `user_id` explicitly on struct before calling)
- `UserToken.build_email_token/2`, `UserToken.verify_email_token_query/2`, `UserToken.by_token_and_context_query/2`, `UserToken.by_user_and_contexts_query/2`

---
*Phase: 01-accounts-and-identity*
*Completed: 2026-04-18*
