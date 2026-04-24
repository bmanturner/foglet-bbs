---
phase: 09-delivery-modes-and-onboarding-honesty
verified: 2026-04-24T20:34:27Z
status: human_needed
score: 23/23 must-haves verified
overrides_applied: 0
re_verification:
  previous_status: gaps_found
  previous_score: 20/23
  gaps_closed:
    - "Seeded/default configuration no longer creates delivery_mode=no_email with require_email_verification=true and registration_mode=open."
    - "Returning-user Login verification routes through Accounts.deliver_verification_code/1 instead of raw Accounts.build_verify_code/1."
    - "Operator no-email retrieval workflows exist for verification codes and reset details through explicit Mix tasks."
  gaps_remaining: []
  regressions: []
human_verification:
  - test: "SSH/TUI onboarding pass in email mode"
    expected: "Register and returning unconfirmed Login users reach Verify only after Foglet attempts verification-code delivery; Verify resend keeps cooldown-aware feedback."
    why_human: "End-to-end terminal navigation, modal readability, and operator comprehension require interactive SSH/TUI validation."
  - test: "SSH/TUI and operator no-email pass"
    expected: "No-email mode does not offer normal user email reset delivery; operator Mix retrieval commands clearly print reset or verification details and say no email was sent."
    why_human: "The automated tests prove command behavior, but final operator workflow clarity is a human-facing copy and terminal-flow check."
---

# Phase 9: Delivery Modes and Onboarding Honesty Verification Report

**Phase Goal:** Users and operators experience verification, reset, and no-email onboarding flows that accurately reflect whether Foglet can send email.
**Verified:** 2026-04-24T20:34:27Z
**Status:** human_needed
**Re-verification:** Yes - after gap closure

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Operator can configure SMTP delivery mode or explicit no-email mode, and verification defaults behave accordingly. | VERIFIED | `delivery_mode` remains exactly `["email", "no_email"]`; `require_email_verification` now defaults to `false`, so the seeded default is valid with `delivery_mode=no_email` and `registration_mode=open`. |
| 2 | User receives or can request verification codes only through delivery paths Foglet actually attempts, with cooldown-aware feedback on the Verify screen. | VERIFIED | Register, Verify resend, and returning-user Login all call `Accounts.deliver_verification_code/1`; no TUI screen calls `Accounts.build_verify_code/1`. |
| 3 | User can request password reset delivery when SMTP is configured, while operators retain the existing break-glass reset path. | VERIFIED | `Accounts.request_password_reset_delivery/1` is email-mode only and enumeration-safe; Login exposes Forgot password only in email mode; reset Mix task still generates operator URLs. |
| 4 | User-facing terminal copy never claims an email or notification was sent unless delivery was attempted. | VERIFIED | Cross-surface copy tests pass; grep found false-delivery strings only in tests or explicit operator "no email was sent" copy. |
| 5 | Operator can retrieve verification or reset delivery details through an explicit no-email workflow when SMTP is disabled. | VERIFIED | `mix foglet.user.reset_password HANDLE` prints no-email reset details; `mix foglet.user.verification_code HANDLE` prints a no-email verification code; both label output as operator retrieval and state no email was sent. |
| 6 | Operator-configured delivery mode has exactly two runtime states: email and no_email. | VERIFIED | `Config.Schema` defines `enum: ["email", "no_email"]`; tests reject provider names such as `smtp` and `mailgun`. |
| 7 | Swoosh adapter settings are runtime OTP config, not DB-backed configuration rows. | VERIFIED | `Foglet.Mailer` uses `otp_app: :foglet_bbs`; runtime config reads SMTP environment variables; schema adds only non-secret `delivery_mode`. |
| 8 | Accounts can build Swoosh email structs for verification and reset without exposing browser reset URLs to TUI callers. | VERIFIED | `Foglet.Accounts.Email` builds verification/reset text emails; user-facing TUI copy contains no browser reset URL. |
| 9 | Registration verification delivery attempts email only in email mode. | VERIFIED | `Register` calls `Accounts.deliver_verification_code/1`; Accounts returns `{:error, :unavailable}` in no-email mode without token creation. |
| 10 | Verify resend keeps cooldown behavior and uses honest attempted-delivery copy. | VERIFIED | `Verify` uses delivery API and updates resend cooldown only after `{:ok, :attempted}`. |
| 11 | No TUI module treats raw verification-code generation as delivery. | VERIFIED | `rg` finds `Accounts.build_verify_code/1` only in the operator-only verification-code Mix task, not TUI screens. |
| 12 | Login offers terminal password-reset request only in email delivery mode. | VERIFIED | Login reset tests cover email/no-email menu behavior and reset request flow. |
| 13 | Reset request responses are identical for known, unknown, deleted, inactive, and delivery-failed users. | VERIFIED | Accounts tests cover `{:ok, :generic_response}` across known, unknown, deleted, pending, suspended, and delivery-failure cases. |
| 14 | User-facing reset copy never points to a browser reset URL. | VERIFIED | TUI grep finds no `/users/reset_password`, `http://`, or `https://` in Login/Register/Verify reset copy. |
| 15 | Sysop Site config exposes delivery_mode in the existing config surface. | VERIFIED | `SiteForm.site_keys/0` includes `"delivery_mode"` before `"require_email_verification"`. |
| 16 | Sysop Site config blocks or clearly flags no_email plus require_email_verification=true. | VERIFIED | `SiteForm.validate_delivery_verification_pair/1` blocks submit and sets errors on both keys before any `Config.put/3`. |
| 17 | No separate browser or relay admin surface is introduced. | VERIFIED | No new reset or verification-code module/route exists under `lib/foglet_bbs_web`; retrieval stays in explicit Mix tasks. |
| 18 | Operator break-glass reset task remains available. | VERIFIED | Email-mode reset Mix task still generates an operator break-glass URL. |
| 19 | No-email mode does not present normal user reset delivery as available. | VERIFIED | Login hides Forgot password in no-email mode; no-email reset task output is explicitly operator retrieval. |
| 20 | Mix reset output is honest about break-glass generation and does not imply email delivery. | VERIFIED | Reset task prints "no email was sent by this task" in both email and no-email operator paths. |
| 21 | All Phase 9 user-facing and operator-facing copy is honest about delivery attempts. | VERIFIED | Delivery-copy regression tests pass and grep shows no false user-facing delivery claims. |
| 22 | No terminal or Mix copy promises MAIL-07 approval/rejection notification early. | VERIFIED | Forbidden approval-notification copy is absent from TUI/Mix implementation. |
| 23 | No end-user browser reset workflow or browser reset URL is introduced. | VERIFIED | Browser reset URL generation remains operator-only in the existing Mix break-glass task; no end-user browser workflow was added. |

**Score:** 23/23 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/foglet_bbs/config/schema.ex` | delivery mode enum and valid default state | VERIFIED | `delivery_mode` default is `no_email`; `require_email_verification` default is `false`. |
| `lib/foglet_bbs/config.ex` | typed delivery-mode accessor | VERIFIED | `delivery_mode/0` reads the schematized key. |
| `lib/foglet_bbs/mailer.ex` | Swoosh mailer boundary | VERIFIED | Uses `Swoosh.Mailer, otp_app: :foglet_bbs`. |
| `lib/foglet_bbs/accounts/email.ex` | transactional email builders | VERIFIED | Builds verification, reset, and status notification email structs. |
| `lib/foglet_bbs/accounts.ex` | verification/reset delivery APIs | VERIFIED | Delivery-mode-aware verification and reset APIs are implemented and tested. |
| `lib/foglet_bbs/tui/screens/register.ex` | registration delivery consumer | VERIFIED | Calls `Accounts.deliver_verification_code/1`. |
| `lib/foglet_bbs/tui/screens/verify.ex` | resend delivery consumer | VERIFIED | Calls `Accounts.deliver_verification_code/1` and preserves cooldown behavior. |
| `lib/foglet_bbs/tui/screens/login.ex` | reset request and returning-user verification flow | VERIFIED | Reset request and unconfirmed-login verification route through Accounts APIs. |
| `lib/foglet_bbs/tui/screens/sysop/site_form.ex` | delivery-mode visibility/editability | VERIFIED | Exposes delivery mode and blocks invalid no-email verification pair. |
| `lib/mix/tasks/foglet.user.reset_password.ex` | operator reset retrieval | VERIFIED | Generates break-glass email-mode URL and no-email operator reset details. |
| `lib/mix/tasks/foglet.user.verification_code.ex` | operator no-email verification retrieval | VERIFIED | Generates a fresh code only in no-email mode for unconfirmed users. |
| `test/foglet_bbs/tui/screens/delivery_copy_test.exs` | false-delivery copy guard | VERIFIED | Guards changed terminal surfaces against false email/browser/reset claims. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `Config.delivery_mode/0` | `Config.Schema` | schematized key read | VERIFIED | Accessor reads `"delivery_mode"`; schema defines enum and default. |
| `Foglet.Mailer` | runtime OTP config | Swoosh adapter config | VERIFIED | Mailer uses `otp_app`; test/runtime config supplies adapter settings. |
| `Register` | `Accounts.deliver_verification_code/1` | registration success delivery | VERIFIED | Register uses the Accounts delivery boundary. |
| `Verify` | `Accounts.deliver_verification_code/1` | resend delivery | VERIFIED | Verify resend uses the Accounts delivery boundary. |
| `Login` | `Accounts.deliver_verification_code/1` | returning unconfirmed login | VERIFIED | Previous raw-code bypass is closed. |
| `Login` | `Accounts.request_password_reset_delivery/1` | reset request subflow | VERIFIED | Login reset flow calls the enumeration-safe Accounts API. |
| `SiteForm` | `Foglet.Config.put/3` | actor-aware config writes | VERIFIED | Sysop edits preserve actor-aware writes. |
| `foglet.user.reset_password` | `Accounts.deliver_user_reset_password_instructions/2` | operator reset detail generation | VERIFIED | Generates email-mode and no-email operator reset URLs. |
| `foglet.user.verification_code` | `Accounts.build_verify_code/1` | operator-only no-email verification retrieval | VERIFIED | Raw code generation is restricted to explicit operator Mix retrieval. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `Register` | verification delivery result | `Accounts.deliver_verification_code/1` -> `Foglet.Mailer.deliver/1` | Yes in email mode | VERIFIED |
| `Verify` | resend modal/cooldown | `Accounts.deliver_verification_code/1` result | Yes in email mode | VERIFIED |
| `Login` | returning-user verification route | `Accounts.deliver_verification_code/1` result | Yes in email mode; unavailable/failure handled | VERIFIED |
| `Login` | reset request message | `Accounts.request_password_reset_delivery/1` result | Yes, enumeration-safe | VERIFIED |
| `SiteForm` | config drafts | `Foglet.Config.get/2`, `Config.put/3` | Yes | VERIFIED |
| `Mix reset task` | reset URL | `Accounts.deliver_user_reset_password_instructions/2` | Yes in email and no-email operator modes | VERIFIED |
| `Mix verification-code task` | verification code | `Accounts.build_verify_code/1` | Yes in no-email operator mode | VERIFIED |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Focused Phase 9 gap closure and regression behavior | `rtk mix test test/foglet_bbs/config/schema_test.exs test/foglet_bbs/config_test.exs test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/accounts/accounts_test.exs test/mix/tasks/foglet_user_reset_password_test.exs test/mix/tasks/foglet_user_verification_code_test.exs test/foglet_bbs/tui/screens/delivery_copy_test.exs` | 206 tests, 0 failures | PASS |
| False-copy/browser-surface scan | `rg` over changed TUI and Mix surfaces | Only operator-only reset URL generation and explicit "no email was sent" copy matched | PASS |
| Raw verification-code bypass scan | `rg "Accounts.build_verify_code" lib/foglet_bbs/tui/screens lib/mix/tasks` | Only operator-only `foglet.user.verification_code` task matched | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| MAIL-01 | 09-01, 09-04, 09-06, 09-07 | Operator can configure SMTP/no-email mode and verification/default behavior matches. | SATISFIED | Config enum/accessor, Sysop form, invalid-pair guard, and valid seeded defaults are present. |
| MAIL-02 | 09-01, 09-02, 09-06, 09-07 | User receives verification code after registration when SMTP delivery is configured and verification is required. | SATISFIED | Registration and returning-login verification route through `Accounts.deliver_verification_code/1`. |
| MAIL-03 | 09-02, 09-06, 09-07 | User can request fresh verification code from Verify screen with cooldown-aware feedback. | SATISFIED | Verify resend uses delivery API and cooldown tests pass. |
| MAIL-04 | 09-03, 09-05, 09-06, 09-07 | User can receive password reset email in SMTP mode while Mix task remains break-glass. | SATISFIED | Login reset request, Accounts reset delivery, and operator reset Mix task are tested. |
| MAIL-05 | 09-02, 09-03, 09-05, 09-06, 09-07 | TUI copy never claims emailed delivery unless Foglet attempted delivery. | SATISFIED | Copy regression tests and grep checks pass. |
| MAIL-06 | 09-04, 09-05, 09-06, 09-07 | Operator can retrieve delivery details through no-email/operator-visible workflow when SMTP disabled. | SATISFIED | No-email reset and verification-code Mix retrieval workflows exist and are tested; pending approval delivery is Phase 10/MAIL-07 scope. |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None | - | - | - | No blocking stub, placeholder, raw TUI verification generation, or false user-facing delivery copy found. |

### Human Verification Required

### 1. SSH/TUI Onboarding Pass In Email Mode

**Test:** Start a local SSH session, configure email delivery mode with the test/dev adapter, register a user requiring verification, then sign in again as the unconfirmed user and use Verify resend.
**Expected:** The user reaches Verify only after delivery is attempted; resend feedback is cooldown-aware and does not expose provider details.
**Why human:** Terminal navigation, modal readability, and flow continuity are user-facing behavior.

### 2. No-Email Operator Retrieval Pass

**Test:** Configure no-email mode, run `mix foglet.user.reset_password HANDLE` and `mix foglet.user.verification_code HANDLE` for suitable users, and inspect the output.
**Expected:** Output clearly labels operator retrieval details and says no email was sent; normal user reset delivery remains unavailable.
**Why human:** The sensitive operator workflow is tested mechanically, but final clarity depends on reading the terminal output in context.

### Gaps Summary

No automated verification gaps remain. The three previous blockers are closed, all roadmap success criteria and MAIL-01 through MAIL-06 are accounted for, and focused tests pass. Final status is `human_needed` only because SSH/TUI flow and operator-output clarity require an interactive human pass under the verifier rules.

---

_Verified: 2026-04-24T20:34:27Z_
_Verifier: Claude (gsd-verifier)_
