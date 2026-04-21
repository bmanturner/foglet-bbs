---
phase: 06-email-verification-toggle-resend
verified: 2026-04-20T20:00:00Z
status: passed
score: 10/10 must-haves verified
overrides_applied: 0
re_verification: false
---

# Phase 6: Email Verification Toggle + Resend Verification Report

**Phase Goal:** A sysop can flip email verification off site-wide via config; a user on the verify screen can resend their code with visible cooldown feedback.
**Verified:** 2026-04-20T20:00:00Z
**Status:** PASSED
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `require_email_verification` config key exists in seeds with boolean default `true` | VERIFIED | `priv/repo/seeds.exs` line 51: `{"require_email_verification", true, ...}` |
| 2 | `email_verify_resend_cooldown_seconds` config key exists in seeds with integer default `60` | VERIFIED | `priv/repo/seeds.exs` line 53: `{"email_verify_resend_cooldown_seconds", 60, ...}` |
| 3 | `Accounts.post_login_screen/1` exists, typed `(User.t()) :: :main_menu | :verify`, reads toggle with safe default | VERIFIED | `lib/foglet_bbs/accounts.ex` lines 172–184: spec, cond on `confirmed_at` then `Foglet.Config.get("require_email_verification", true)` |
| 4 | `login.ex` dispatches through `post_login_screen/1`; old inline `confirmed_at: nil` check removed | VERIFIED | Line 273: `case Accounts.post_login_screen(user)`. Grep for `confirmed_at: nil` returns 0 matches. |
| 5 | `register.ex` dispatches through `post_login_screen/1`; both branches wire correctly | VERIFIED | Line 241: `case Accounts.post_login_screen(user)`. `:main_menu` branch emits `{:promote_session, user}` at line 271. |
| 6 | Dev-only Logger guard wraps verify-code logging at both call sites | VERIFIED | `if Mix.env() != :prod do` at login.ex line 277 and register.ex line 245 |
| 7 | `verify_state` gains `resend_cooldown_until` field initialised at all sites in `verify.ex` | VERIFIED | 8 occurrences of `resend_cooldown_until: nil` in verify.ex; no old 3-key literal shape remains |
| 8 | `resend_cooldown?/1` predicate is independent of `cooldown?/1`; `resend_code/1` gates on the resend timer | VERIFIED | Lines 149–155: two clause heads for `resend_cooldown?`. Line 222: `if resend_cooldown?(vs)`. |
| 9 | `cooldown_modal/2` (2-arity) replaces old 1-arity; resend feedback shows "Please wait to resend. Wait Ns." | VERIFIED | Line 159: `defp cooldown_modal(%DateTime{} = until, prefix)`. Old 1-arity gone (grep returns 0). Line 224 uses resend-specific message. |
| 10 | `resend_code_raw/1` reads `email_verify_resend_cooldown_seconds` from config and sets `resend_cooldown_until` | VERIFIED | Lines 238–250: `Foglet.Config.get("email_verify_resend_cooldown_seconds", 60)` and `resend_cooldown_until: DateTime.add(now, cooldown_seconds, :second)` |

**Score:** 10/10 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `priv/repo/seeds.exs` | Two new config keys appended | VERIFIED | `require_email_verification` (bool true) and `email_verify_resend_cooldown_seconds` (int 60) present at lines 51–54 |
| `lib/foglet_bbs/accounts.ex` | `post_login_screen/1` function | VERIFIED | Exists at line 173 with correct spec, cond logic, and safe `get/2` default |
| `test/foglet_bbs/accounts/accounts_test.exs` | 4+ tests for `post_login_screen/1` | VERIFIED | `describe "post_login_screen/1 (VERIFY-01)"` at line 60; 28 total tests pass |
| `lib/foglet_bbs/tui/screens/login.ex` | Post-login routing via `post_login_screen/1` | VERIFIED | Line 273 dispatches; `resend_cooldown_until: nil` at line 292; `{:promote_session, user}` at line 301 |
| `lib/foglet_bbs/tui/screens/register.ex` | Post-register routing via `post_login_screen/1` | VERIFIED | Line 241 dispatches; `resend_cooldown_until: nil` at line 259; `{:promote_session, user}` at line 271 |
| `test/foglet_bbs/tui/screens/login_test.exs` | 3 new tests for VERIFY-01 toggle behavior | VERIFIED | `describe "submit_login/1 — VERIFY-01 retroactive bypass"` at line 291; 28 tests pass |
| `test/foglet_bbs/tui/screens/register_test.exs` | 2 new tests for VERIFY-01 toggle routing | VERIFIED | `describe "submit/2 — VERIFY-01 post-registration routing"` at line 105; 20 tests pass |
| `lib/foglet_bbs/tui/screens/verify.ex` | Two-timer cooldown, `resend_cooldown?/1`, `cooldown_modal/2`, config-driven duration | VERIFIED | All four plan tasks implemented; 8 `resend_cooldown_until: nil` inits, correct predicate and modal helper |
| `test/foglet_bbs/tui/screens/verify_test.exs` | 5 new VERIFY-02 tests; all verify_state literals updated | VERIFIED | `describe "resend cooldown — VERIFY-02 two-timer model"` at line 242; all `%{buffer:` literals include `resend_cooldown_until`; 21 tests pass |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `login.ex:submit_login/1` | `Accounts.post_login_screen/1` | inner case dispatch | WIRED | Line 273 calls function; branches to `:verify` (builds code) or `:main_menu` (emits `{:promote_session, user}`) |
| `register.ex:submit/2` | `Accounts.post_login_screen/1` | inner case dispatch | WIRED | Line 241 calls function; same branch structure as login |
| `Accounts.post_login_screen/1` | `Foglet.Config.get/2` | direct call | WIRED | Line 178: `Foglet.Config.get("require_email_verification", true)` with safe boolean default |
| `verify.ex:resend_code/1` | `resend_cooldown?/1` | direct call | WIRED | Line 222: gating on `resend_cooldown?` not `cooldown?` — the VERIFY-02 bug fix |
| `verify.ex:resend_code_raw/1` | `Foglet.Config.get/2` | direct call | WIRED | Line 238: reads `email_verify_resend_cooldown_seconds` with default 60 |
| `verify.ex:resend_code_raw/1` | `verify_state.resend_cooldown_until` | map update | WIRED | Line 250: `resend_cooldown_until: DateTime.add(now, cooldown_seconds, :second)` |
| `verify.ex:cooldown_modal/2` | `app.ex:render_modal_overlay` | `state.modal` field | WIRED | Modal set on `state.modal`; app.ex line 157–158 renders it as a visible overlay when non-nil |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `accounts.ex:post_login_screen/1` | `require_email_verification` | `Foglet.Config.get/2` → ETS/DB | Yes — boolean from seeded `Foglet.Config` row | FLOWING |
| `verify.ex:resend_code_raw/1` | `cooldown_seconds` | `Foglet.Config.get/2` → ETS/DB | Yes — integer from seeded `Foglet.Config` row | FLOWING |
| `verify.ex:render/1` | `vs.resend_cooldown_until` | set by `resend_code_raw/1` after successful resend | Yes — `DateTime.add` result | FLOWING |

### Behavioral Spot-Checks

Step 7b: SKIPPED for function-level checks — the test suite (97 tests, 0 failures) provides behavioral coverage. The TUI screens require a running SSH session to exercise interactively; no HTTP endpoints or CLI entry points are testable in isolation.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| VERIFY-01 | Plans 06-01, 06-02 | Sysop-settable `require_email_verification` key; when `false`, skip verify on registration and login | SATISFIED | `post_login_screen/1` in accounts.ex; both login.ex and register.ex dispatch through it; 7 new tests covering confirmed/unconfirmed + toggle combinations |
| VERIFY-02 | Plan 06-03 | Verify screen shows visible "Resend code" key hint wired to `{:resend}`, respecting cooldown with visible feedback | SATISFIED | Key hint `{"R", "Resend code"}` rendered at verify.ex line 58; `resend_code/1` gates on `resend_cooldown?/1`; blocked press shows "Please wait to resend. Wait Ns." modal overlay via `app.ex:render_modal_overlay`; 5 new tests cover two-timer independence and config-driven duration |

**Orphaned requirements check:** REQUIREMENTS.md maps VERIFY-01 and VERIFY-02 to Phase 6. Both are accounted for in the plans' `requirements:` frontmatter. No orphaned requirements.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (none) | — | — | — | — |

No TODO/FIXME/placeholder comments, no stub returns, no empty handlers found across the five modified production files. All `return null` equivalents are legitimate `nil` initial values that are populated by real data.

### Human Verification Required

(None — all must-haves are verifiable programmatically.)

### Gaps Summary

No gaps. All 10 observable truths verified, all artifacts substantive and wired, all key links confirmed, data flows through real config reads and DateTime computation. The test suite ran 97 tests with 0 failures.

**VERIFY-01 note:** The requirement checkbox in REQUIREMENTS.md remains unchecked (`[ ]`). This is a documentation state issue only — the implementation is complete and tested. The checkbox should be updated to `[x]` in a separate documentation pass. This does not affect goal achievement.

**VERIFY-02 note:** The "visible feedback" is delivered via the modal overlay system (`state.modal` → `app.ex:render_modal_overlay`) rather than an inline status line in the verify screen's render content area. The REQUIREMENTS.md text ("visible feedback to the user") is satisfied by the modal approach — when a user presses R during cooldown, they see a prominent centered overlay reading "Please wait to resend. Wait Ns." This is consistent with how the rest of the app surfaces temporary error/info feedback.

---

_Verified: 2026-04-20T20:00:00Z_
_Verifier: Claude (gsd-verifier)_
