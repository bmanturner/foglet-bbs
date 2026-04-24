---
phase: 09-delivery-modes-and-onboarding-honesty
verified: 2026-04-24T17:33:58Z
status: gaps_found
score: 20/23 must-haves verified
overrides_applied: 0
gaps:
  - truth: "Operator can configure SMTP delivery mode or explicit no-email mode, and verification defaults behave accordingly."
    status: failed
    reason: "Seeded defaults are delivery_mode=no_email, require_email_verification=true, and registration_mode=open; the Sysop form rejects that pair but seeds still create it, so new open registrations can persist an unverified user and then fail delivery."
    artifacts:
      - path: "lib/foglet_bbs/config/schema.ex"
        issue: "delivery_mode defaults to no_email while require_email_verification defaults to true."
      - path: "priv/repo/seeds/config.exs"
        issue: "Seeds schema defaults directly without enforcing the delivery/verification pair."
      - path: "lib/foglet_bbs/tui/screens/register.ex"
        issue: "Registration persists the account before delivery fails in no-email mode."
    missing:
      - "Make seeded defaults a valid delivery/verification combination, or enforce the cross-field rule during seeding before users can register."
  - truth: "User receives or can request verification codes only through delivery paths Foglet actually attempts, with cooldown-aware feedback on the Verify screen."
    status: failed
    reason: "The returning-login verification path still calls Accounts.build_verify_code/1 directly, generating a raw code without Swoosh delivery before routing to Verify."
    artifacts:
      - path: "lib/foglet_bbs/tui/screens/login.ex"
        issue: "start_verify_flow/2 calls Accounts.build_verify_code/1 instead of Accounts.deliver_verification_code/1."
    missing:
      - "Route Login verification through Accounts.deliver_verification_code/1 and handle unavailable/delivery_failed like Register."
  - truth: "Operator can retrieve verification or reset delivery details through an explicit no-email workflow when SMTP is disabled."
    status: failed
    reason: "No no-email operator retrieval workflow exists for verification or reset details. The reset Mix task exits in no-email mode, and no verification-code retrieval surface or task was added."
    artifacts:
      - path: "lib/mix/tasks/foglet.user.reset_password.ex"
        issue: "In no-email mode, the task exits before generating reset details."
      - path: "lib/foglet_bbs/tui/screens/sysop/site_form.ex"
        issue: "Exposes delivery mode and blocks invalid config, but does not provide retrieval of verification/reset details."
    missing:
      - "Add or explicitly override the roadmap MAIL-06 no-email operator workflow for retrieving verification/reset delivery details."
---

# Phase 9: Delivery Modes and Onboarding Honesty Verification Report

**Phase Goal:** Users and operators experience verification, reset, and no-email onboarding flows that accurately reflect whether Foglet can send email.
**Verified:** 2026-04-24T17:33:58Z
**Status:** gaps_found
**Re-verification:** No - initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Operator can configure SMTP delivery mode or explicit no-email mode, and verification defaults behave accordingly. | FAILED | `delivery_mode` default is `"no_email"` while `require_email_verification` default is `true` in `lib/foglet_bbs/config/schema.ex:87-99`; `priv/repo/seeds/config.exs:21-24` seeds those defaults directly; `registration_mode` also defaults to `"open"` at `schema.ex:51-54`. WR-01 is phase-blocking for MAIL-01. |
| 2 | User receives or can request verification codes only through delivery paths Foglet actually attempts, with cooldown-aware feedback on the Verify screen. | FAILED | Register and Verify resend call `Accounts.deliver_verification_code/1`, but Login returning-user verification still calls `Accounts.build_verify_code/1` at `lib/foglet_bbs/tui/screens/login.ex:399-410`. WR-02 is phase-blocking for MAIL-02/MAIL-03. |
| 3 | User can request password reset delivery when SMTP is configured, while operators retain the existing break-glass reset path. | VERIFIED | `Accounts.request_password_reset_delivery/1` branches on `delivery_mode` and attempts Swoosh delivery for active matches; Login exposes `[F] Forgot password` only in email mode; Mix reset task preserves email-mode break-glass URL generation. |
| 4 | User-facing terminal copy never claims an email or notification was sent unless delivery was attempted. | VERIFIED | Cross-surface copy guard exists in `test/foglet_bbs/tui/screens/delivery_copy_test.exs`; focused grep found no false TUI delivery copy in changed surfaces. |
| 5 | Operator can retrieve verification or reset delivery details through an explicit no-email workflow when SMTP is disabled. | FAILED | No retrieval task/surface exists. `mix foglet.user.reset_password` exits in no-email mode at `lib/mix/tasks/foglet.user.reset_password.ex:74-83`; no verification-code retrieval workflow was found. |
| 6 | Operator-configured delivery mode has exactly two runtime states: email and no_email. | VERIFIED | `Config.Schema` defines `enum: ["email", "no_email"]` and tests reject `"smtp"`/`"mailgun"`. |
| 7 | Swoosh adapter settings are runtime OTP config, not DB-backed configuration rows. | VERIFIED | `runtime.exs` reads `FOGLET_SMTP_*`; `Config.Schema` only adds the non-secret `delivery_mode` key. |
| 8 | Accounts can build Swoosh email structs for verification and reset without exposing browser reset URLs to TUI callers. | VERIFIED | `Foglet.Accounts.Email.verification_code/2` and `password_reset/2` build text `Swoosh.Email` structs with terminal-native reset text. |
| 9 | Registration verification delivery attempts email only in email mode. | VERIFIED | `Register` calls `Accounts.deliver_verification_code/1`; Accounts returns `{:error, :unavailable}` in no-email mode before token creation. |
| 10 | Verify resend keeps cooldown behavior and uses honest attempted-delivery copy. | VERIFIED | `Verify.resend_code_raw/1` calls `Accounts.deliver_verification_code/1` and updates `resend_cooldown_until` only on `{:ok, :attempted}`. |
| 11 | No TUI module treats raw verification-code generation as delivery. | FAILED | `Login.start_verify_flow/2` still generates a raw verification code and routes to Verify without delivery. |
| 12 | Login offers terminal password-reset request only in email delivery mode. | VERIFIED | `Login.keys_for/2` includes Forgot password only when `Config.delivery_mode() == "email"`; tests cover email/no-email visibility. |
| 13 | Reset request responses are identical for known, unknown, deleted, inactive, delivery-failed, and inactive users. | VERIFIED | `Accounts.request_password_reset_delivery/1` always returns `{:ok, :generic_response}` in email mode after collapsing lookup and delivery outcomes. |
| 14 | User-facing reset copy never points to a browser reset URL. | VERIFIED | Login reset copy is generic and browser-free; browser reset URL only remains in operator-only Mix output. |
| 15 | Sysop Site config exposes delivery_mode in the existing config surface. | VERIFIED | `SiteForm.site_keys/0` includes `"delivery_mode"` before `"require_email_verification"`. |
| 16 | Sysop Site config blocks or clearly flags no_email plus require_email_verification=true. | VERIFIED | `SiteForm.validate_delivery_verification_pair/1` blocks submit and sets errors on both keys before `Config.put/3`. |
| 17 | No separate browser or relay admin surface is introduced. | VERIFIED | No new `FogletBbsWeb` reset/admin surface found; behavior remains in TUI, Accounts, and Mix tooling. |
| 18 | Operator break-glass reset task remains available. | VERIFIED | Email-mode `mix foglet.user.reset_password` still generates an operator break-glass URL. |
| 19 | No-email mode does not present normal user reset delivery as available. | VERIFIED | Login hides Forgot password in no-email mode; the Mix task exits with no-email unavailable copy. |
| 20 | Mix reset output is honest about break-glass generation and does not imply email delivery. | VERIFIED | Mix task prints "no email was sent by this task" after generating the operator URL. |
| 21 | All Phase 9 user-facing and operator-facing copy is honest about delivery attempts. | VERIFIED | Copy regression tests cover Login, Register, Verify, Sysop SiteForm, and reset Mix task output. |
| 22 | No terminal or Mix copy promises MAIL-07 approval/rejection notification early. | VERIFIED | Register/Login pending copy no longer promises email notification; copy tests forbid approval notification phrases. |
| 23 | No end-user browser reset workflow or browser reset URL is introduced. | VERIFIED | User-facing TUI reset copy has no browser URL; operator-only Mix task remains the only `/users/reset_password` URL generator. |

**Score:** 20/23 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/foglet_bbs/config/schema.ex` | delivery mode enum schema | PARTIAL | Exists/substantive; enum is correct, but defaults create invalid no-email verification state. |
| `lib/foglet_bbs/config.ex` | typed `delivery_mode/0` accessor | VERIFIED | `def delivery_mode, do: get!("delivery_mode")`. |
| `lib/foglet_bbs/mailer.ex` | Swoosh mailer boundary | VERIFIED | Uses `Swoosh.Mailer, otp_app: :foglet_bbs`. |
| `lib/foglet_bbs/accounts/email.ex` | transactional email builders | VERIFIED | Builds verification and password-reset text emails. |
| `lib/foglet_bbs/accounts.ex` | verification/reset delivery APIs | VERIFIED | APIs exist and are substantive; reset delivery uses Swoosh in email mode. |
| `lib/foglet_bbs/tui/screens/register.ex` | registration verification delivery consumer | VERIFIED | Calls `Accounts.deliver_verification_code/1`. |
| `lib/foglet_bbs/tui/screens/verify.ex` | resend delivery consumer and cooldown feedback | VERIFIED | Calls `Accounts.deliver_verification_code/1` and preserves resend cooldown. |
| `lib/foglet_bbs/tui/screens/login.ex` | terminal reset request subflow | PARTIAL | Reset subflow is wired, but verification login path still bypasses delivery. |
| `lib/foglet_bbs/tui/screens/sysop/site_form.ex` | delivery mode visibility/editability | VERIFIED | Exposes and edits delivery mode through existing Sysop Site form. |
| `lib/mix/tasks/foglet.user.reset_password.ex` | mode-aware operator reset task | PARTIAL | Mode-aware and honest, but no-email reset detail retrieval required by roadmap is absent. |
| `test/foglet_bbs/tui/screens/delivery_copy_test.exs` | cross-surface false-delivery copy guard | VERIFIED | Covers changed TUI copy surfaces with forbidden phrase assertions. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `Config.delivery_mode/0` | `Config.Schema` | schematized key read | VERIFIED | `delivery_mode/0` reads `get!("delivery_mode")`; schema defines the key. |
| `Foglet.Mailer` | runtime OTP config | Swoosh adapter config | VERIFIED | `Foglet.Mailer` uses `otp_app: :foglet_bbs`; config/runtime/test configure adapter. |
| `Register` | `Accounts.deliver_verification_code/1` | registration success delivery | VERIFIED | `register.ex:401-402`. |
| `Verify` | `Accounts.deliver_verification_code/1` | resend delivery | VERIFIED | `verify.ex:163-184`. |
| `Login` | `Accounts.request_password_reset_delivery/1` | reset request subflow | VERIFIED | `login.ex:335-345`. |
| `Login` | verification delivery API | returning-user verify flow | FAILED | Uses `Accounts.build_verify_code/1`, not delivery API. |
| `SiteForm` | `Foglet.Config.put/3` | actor-aware config writes | VERIFIED | Submit loop uses `Config.put(acc_state.current_user, key, value)`. |
| `foglet.user.reset_password` | `Config.delivery_mode/0` | mode-aware reset task | VERIFIED | `lib/mix/tasks/foglet.user.reset_password.ex:59-84`. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `Register` | delivery result | `Accounts.deliver_verification_code/1` -> `Foglet.Mailer.deliver/1` | Yes in email mode | VERIFIED |
| `Verify` | resend modal/cooldown | `Accounts.deliver_verification_code/1` result | Yes in email mode | VERIFIED |
| `Login` | reset request message | `Accounts.request_password_reset_delivery/1` result | Yes, enumeration-safe | VERIFIED |
| `Login` | verification code for returning unconfirmed user | `Accounts.build_verify_code/1` | Real token, but no delivery attempt | FAILED |
| `SiteForm` | config drafts | `Foglet.Config.get/2`, `Config.put/3` | Yes | VERIFIED |
| `Mix reset task` | reset URL | `Accounts.deliver_user_reset_password_instructions/2` | Yes in email mode; blocked in no-email mode | PARTIAL |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Focused Phase 9 TUI/accounts/mix behavior | `rtk mix test test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/tui/screens/register_test.exs test/foglet_bbs/tui/screens/verify_test.exs test/foglet_bbs/tui/screens/sysop/site_form_test.exs test/foglet_bbs/tui/screens/delivery_copy_test.exs test/mix/tasks/foglet_user_reset_password_test.exs` | 170 tests, 0 failures | PASS |
| Config schema/accessor behavior | `rtk mix test test/foglet_bbs/config/schema_test.exs test/foglet_bbs/config_test.exs` | 80 tests, 0 failures | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| MAIL-01 | 09-01, 09-04, 09-06 | Operator can configure SMTP/no-email mode and verification/default behavior matches. | PARTIAL | Delivery mode enum/accessor and Sysop form exist, but seeded defaults create `no_email + require_email_verification=true`, which the Sysop form itself rejects. |
| MAIL-02 | 09-01, 09-02, 09-06 | User receives email verification code after registration when SMTP delivery is configured and verification is required. | PARTIAL | Registration path attempts Swoosh delivery in email mode, but returning-login verification path still generates without delivery. |
| MAIL-03 | 09-02, 09-06 | User can request fresh verification code from Verify screen with cooldown-aware feedback. | VERIFIED | Verify resend calls delivery API and sets resend cooldown on attempted delivery. |
| MAIL-04 | 09-03, 09-05, 09-06 | User can receive password reset email in SMTP mode while Mix task remains break-glass. | VERIFIED | Login reset request and Accounts reset delivery are email-mode only; Mix break-glass remains. |
| MAIL-05 | 09-02, 09-03, 09-05, 09-06 | TUI copy never claims emailed delivery unless Foglet attempted delivery. | VERIFIED | Copy tests and greps cover changed TUI and Mix surfaces. |
| MAIL-06 | 09-04, 09-05, 09-06 | Operator can retrieve verification/reset/pending-approval delivery details through no-email workflow when SMTP disabled. | FAILED | No such retrieval workflow exists; reset task exits in no-email mode and no verification retrieval surface/task was added. Pending approval notification is Phase 10 per roadmap. |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `lib/foglet_bbs/config/schema.ex` | 87-99 | Invalid default pair | Blocker | Creates no-email installs that require email verification. |
| `lib/foglet_bbs/tui/screens/login.ex` | 399-410 | Raw verification-code generation in TUI flow | Blocker | Bypasses delivery-mode policy and Swoosh attempt. |
| `lib/mix/tasks/foglet.user.reset_password.ex` | 74-83 | No-email retrieval missing | Blocker | Does not satisfy roadmap MAIL-06 no-email operator retrieval. |

### Human Verification Required

After the gaps are fixed, run one manual SSH/TUI pass:

1. Start a local SSH session, register in email mode, and confirm Verify copy appears only after delivery is attempted.
2. Return as an unconfirmed active user and confirm Login routes to Verify only through the same delivery-aware API.
3. Switch to no-email mode and verify the operator-facing workflow for verification/reset details is explicit and understandable.

### Gaps Summary

The implementation is substantive and most artifacts are wired, but the phase goal is not achieved yet. WR-01 and WR-02 are phase-blocking because they create real onboarding paths where Foglet cannot honestly deliver verification. MAIL-06 also remains unimplemented relative to the roadmap contract: the plans intentionally made no-email reset delivery unavailable, but no accepted override exists for the roadmap requirement that operators can retrieve delivery details through an explicit no-email workflow.

---

_Verified: 2026-04-24T17:33:58Z_
_Verifier: Claude (gsd-verifier)_
