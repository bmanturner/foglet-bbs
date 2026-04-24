---
phase: 03-invite-persistence-and-registration-enforcement
verified: 2026-04-24T00:50:01Z
status: passed
score: 13/13 must-haves verified
overrides_applied: 0
---

# Phase 3: Invite Persistence and Registration Enforcement Verification Report

**Phase Goal:** Invite-only onboarding is real, transactional, and single-use before the shared invite UI becomes operational.
**Verified:** 2026-04-24T00:50:01Z
**Status:** passed
**Re-verification:** No - initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Authorized actor can generate a single-use invite code and the system persists issuer, created time, consumed state, and revocation state. | VERIFIED | `Accounts.create_invite/1` authorizes with Bodyguard, enforces runtime policy/caps, generates secure codes, and inserts `%Invite{issuer_id: actor.id}`. Migration and schema persist `code`, `issuer_id`, `consumed_at`, `consumed_by_user_id`, `revoked_at`, and timestamps. |
| 2 | Authorized actor can review invite status and revoke an unused invite code through real domain behavior. | VERIFIED | `list_invites/1`, `get_invite_status/1`, and `revoke_invite/2` exist in `Foglet.Accounts`; status maps include lifecycle fields and revocation uses a conditional available-only DB update. |
| 3 | Registration in `invite_only` mode accepts only persisted, unrevoked, unconsumed invite codes. | VERIFIED | `register_user/1` dispatches `"invite_only"` to `register_invite_only_user/1`; missing/unavailable codes receive a generic `invite_code` changeset error, and redemption updates only rows where `consumed_at` and `revoked_at` are nil. |
| 4 | Successful registration consumes an invite exactly once, and failed registration attempts do not burn invite codes. | VERIFIED | User validation runs before invite mutation; user insert and invite consumption run inside `Repo.transact/1`; Ecto rolls back on `{:error, :invalid_invite_code}`. Tests cover success, invalid attrs, and second redemption. |
| 5 | Generated invite records can persist issuer, public code, timestamps, consumed state, and revocation state. | VERIFIED | `invite_codes` migration defines the required columns and indexes; `Invite` schema maps the fields and associations. |
| 6 | Invite status is derived as `:available`, `:consumed`, or `:revoked` from persisted timestamp fields. | VERIFIED | `Invite.status/1` returns revoked before consumed, consumed before available; tests assert all states. |
| 7 | Phase 2 invite_generation_per_user_limit/0 dependency exists before invite policy enforcement is implemented. | VERIFIED | `Foglet.Config.invite_generation_per_user_limit/0` is called in `Accounts.ensure_invite_generation_limit/1` and tested with `function_exported?/3`. |
| 8 | Registration enforcement tests exist so invite-only behavior cannot silently regress. | VERIFIED | `invite_registration_test.exs` covers missing, unknown, revoked, consumed, success, invalid attrs, and second redemption. |
| 9 | Authorized actors can generate persisted single-use invite codes according to runtime policy. | VERIFIED | `ensure_invite_generation_policy/1` handles `sysop_only`, `mods`, and `any_user`; tests exercise sysop/mod/user policy outcomes. |
| 10 | Invite code generation uses secure randomness and cannot be guessed from counters. | VERIFIED | `generate_invite_code/0` uses `:crypto.strong_rand_bytes(16)` and Base32 encoding, with unique-constraint retry. |
| 11 | Authorized callers can review persisted invite status without Phase 4 UI. | VERIFIED | Domain status/list APIs are implemented in `Foglet.Accounts`; no Phase 4 invite UI activation is required. |
| 12 | Authorized actors can revoke unused invites, and unauthorized actors cannot revoke invites. | VERIFIED | `revoke_invite/2` calls `Bodyguard.permit/4` before lookup and mutation; tests cover sysop success and user forbidden. |
| 13 | The existing register screen no longer consumes invite codes during the invite-code preflight step. | VERIFIED | `valid_invite_code?/1` is format-only; final submit passes `invite_code` to `Accounts.register_user/1`; no `consume_invite_code` references remain in `register.ex`. |

**Score:** 13/13 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/foglet_bbs/accounts/invite.ex` | Invite schema, changeset, and derived status helper | VERIFIED | Schema maps `invite_codes`; changeset validates generated code only; `status/1` derives lifecycle state. |
| `priv/repo/migrations/20260424001147_create_invite_codes.exs` | Invite table, FKs, unique code index, lifecycle indexes | VERIFIED | Migration creates UUID table, `code`, issuer/consumer FKs, lifecycle timestamps, unique code index, and indexes for issuer/consumed/revoked. |
| `lib/foglet_bbs/accounts.ex` | Invite generation/review/revoke and invite-only registration transaction | VERIFIED | Contains `create_invite/1`, `list_invites/1`, `get_invite_status/1`, `revoke_invite/2`, `register_invite_only_user/1`, and conditional invite consumption. |
| `lib/foglet_bbs/authorization.ex` | Domain authorization support for invite generation/revocation | VERIFIED | `:generate_invite` and `:revoke_invite` are valid actions; regular users only pass coarse generate gate, not revoke. |
| `lib/foglet_bbs/tui/screens/register.ex` | Non-consuming preflight and final submit forwarding | VERIFIED | Preflight regex checks format only; final submit calls `Accounts.register_user(data)`. |
| `test/foglet_bbs/accounts/invite_test.exs` | INVT-02, INVT-03, INVT-04 lifecycle coverage | VERIFIED | Covers persistence/status, create policy/cap, list/status, and revoke behavior. |
| `test/foglet_bbs/accounts/invite_registration_test.exs` | INVT-05 registration enforcement coverage | VERIFIED | Covers generic unavailable-code errors, transactional consumption, failed validation, and second redemption. |
| `test/foglet_bbs/tui/screens/register_test.exs` | Register-screen preflight regression coverage | VERIFIED | Covers valid preflight storing code and malformed/empty code rejection without consumption. |
| `test/support/accounts_fixtures.ex` | Invite fixture helper | VERIFIED | `invite_fixture/1` and `/2` insert persisted invites with programmatic issuer IDs. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `Invite` schema | `invite_codes` migration | Table and field names match | WIRED | Schema uses `schema "invite_codes"` with code/lifecycle fields matching migration. |
| `invite_test.exs` | `Foglet.Config.invite_generation_per_user_limit/0` | Dependency test | WIRED | Test asserts `function_exported?(Foglet.Config, :invite_generation_per_user_limit, 0)`. |
| `invite_registration_test.exs` | `Accounts.register_user/1` | Registration tests | WIRED | Tests call `Accounts.register_user/1` and assert invite-code errors/consumption behavior. |
| `accounts.ex` | `Foglet.Authorization` | Bodyguard checks | WIRED | `create_invite/1` and `revoke_invite/2` call `Bodyguard.permit/4`. |
| `accounts.ex` | `Foglet.Config` | Runtime policy/caps/mode | WIRED | Uses `registration_mode/0`, `invite_code_generators/0`, and `invite_generation_per_user_limit/0`. |
| `accounts.ex` | `Invite` schema | Insert/update/status projection | WIRED | Inserts via `Invite.changeset/2`, consumes/revokes with Ecto queries, projects status through `Invite.status/1`. |
| `register.ex` | `Accounts.register_user/1` | Final submit | WIRED | Final combined-step submit includes collected `invite_code` in `data`. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `lib/foglet_bbs/accounts.ex` | Invite status rows | `Repo.all(from(i in Invite...))` and `Repo.get_by(Invite, code: code)` | Yes - database rows projected into status maps | FLOWING |
| `lib/foglet_bbs/accounts.ex` | Invite consumption state | Conditional `repo.update_all` inside `Repo.transact/1` | Yes - updates persisted invite row only when available | FLOWING |
| `lib/foglet_bbs/tui/screens/register.ex` | Collected invite code | User-entered wizard state passed to `Accounts.register_user/1` | Yes - no hardcoded empty props or consuming preflight | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Invite-only registration enforcement tests pass | `mix test test/foglet_bbs/accounts/invite_registration_test.exs` | 5 tests, 0 failures | PASS |
| Orchestrator focused phase tests pass | Provided by orchestrator | 168 tests, 0 failures across Accounts/Auth/Config/Register coverage | PASS |
| Register UI/support tests pass | Provided by orchestrator | 45 tests, 0 failures across register-adjacent TUI/modal coverage | PASS |
| Schema drift check | Provided by orchestrator | `drift_detected false` | PASS |
| Code review | Provided by orchestrator | `status clean` | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| INVT-02 | 03-01, 03-02 | Authorized actor can generate a single-use invite code and view it once for sharing. | SATISFIED | `Accounts.create_invite/1` returns the persisted invite with public `code`; policy/cap tests cover authorized generation. |
| INVT-03 | 03-01, 03-02 | Authorized actor can review invite status including issuer, created time, consumed state, and revocation state. | SATISFIED | `list_invites/1` and `get_invite_status/1` return status maps with issuer, inserted time, consumed/revoked fields, and derived status. |
| INVT-04 | 03-01, 03-02 | Authorized actor can revoke an unused invite code. | SATISFIED | `revoke_invite/2` authorizes with `:revoke_invite`, rejects unknown/consumed/unavailable rows, and sets `revoked_at` for available invites. |
| INVT-05 | 03-01, 03-03 | Registration in `invite_only` mode accepts only persisted, unrevoked, unconsumed invite codes. | SATISFIED | `register_invite_only_user/1` validates invite presence, returns generic errors for unavailable codes, and consumes only available persisted rows transactionally. |

No additional Phase 3 requirement IDs were found in `.planning/REQUIREMENTS.md` beyond INVT-02, INVT-03, INVT-04, and INVT-05.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None | - | - | - | Anti-pattern scan found no TODO/FIXME/placeholders, empty implementations, hardcoded empty data flows, or `consume_invite_code` references in the owned files. |

### Human Verification Required

None. Phase 3 is domain/API behavior with automated coverage; no new user-facing invite UI was activated.

### Gaps Summary

No blocking gaps found. The phase goal is achieved: persisted invites exist, invite lifecycle APIs are real and authorization-backed, invite-only registration redeems available invite rows transactionally, failed attempts do not consume valid invites, and the register-screen preflight is non-consuming.

---

_Verified: 2026-04-24T00:50:01Z_
_Verifier: Claude (gsd-verifier)_
