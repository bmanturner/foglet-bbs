# Phase 9: Delivery Modes and Onboarding Honesty - Specification

**Created:** 2026-04-24
**Ambiguity score:** 0.08 (gate: <= 0.20)
**Requirements:** 6 locked

## Goal

Verification and password-reset flows only operate when email delivery is configured through Swoosh, and no-email operation prevents verification and password reset from being offered as valid user workflows.

## Background

Foglet already has account registration, pending-user creation, email-verification tokens, reset-password tokens, and a Verify screen. `Foglet.Config.Schema` currently exposes `require_email_verification` and `email_verify_resend_cooldown_seconds`, but it has no delivery-mode setting. `Foglet.Accounts.build_verify_code/1` persists a short-lived verification code, and `Foglet.TUI.Screens.Verify` lets users submit or resend that code with cooldown state. Login and registration build verification codes and, in dev only, may log them. They do not send email. The Verify screen currently says the code was emailed, and resend success says a new code was sent even though no delivery is attempted.

Password-reset token creation also exists through `Accounts.deliver_user_reset_password_instructions/2` and the break-glass `mix foglet.user.reset_password` task, but that path only persists a token and prints a URL. There is no Swoosh mailer in the repo today, and no end-user browser reset route is registered. Phase 9 closes the delivery-honesty gap without changing Foglet's SSH-first product boundary.

## Requirements

1. **Swoosh delivery mode contract**: Foglet exposes an operator-configurable delivery mode with exactly two user-visible states: Swoosh email delivery enabled and explicit no-email mode.
   - Current: Runtime config has verification toggles and cooldowns, but no canonical delivery-mode value; email delivery capability is not represented in `Foglet.Config`.
   - Target: Domain and TUI flows can ask a typed config/runtime API whether delivery mode is Swoosh email or no-email; Swoosh adapter settings and credentials remain in runtime/environment config, not DB-backed configuration.
   - Acceptance: Focused tests can set each delivery mode and verify that verification, reset, Sysop copy, and operator tooling branch from that mode instead of from ad hoc environment checks or hard-coded assumptions.

2. **Verification requires email capability**: Email verification is a valid configuration only when Swoosh email delivery mode is enabled.
   - Current: Registration, login, and resend call `Accounts.build_verify_code/1` directly; the Verify screen claims an email was sent even when no mailer exists.
   - Target: In Swoosh email mode, verification-code delivery attempts email and the TUI may say a code was emailed only after that attempt is made. In no-email mode, `require_email_verification` cannot be enabled through normal operator configuration, and users are not routed to Verify as a no-email relay workaround.
   - Acceptance: Tests cover initial registration verification, login verification, and resend in Swoosh email mode; no-email tests prove `require_email_verification=true` is rejected or rendered unavailable and no user sees Verify-screen email copy in no-email mode.

3. **Cooldown-aware Verify screen feedback**: The Verify screen keeps its existing code-entry and resend cooldown behavior while making resend results honest for Swoosh email delivery.
   - Current: Resend cooldown state exists, but success copy always says "A new code has been sent."
   - Target: Resend is still blocked by `email_verify_resend_cooldown_seconds`; successful resend uses generic delivery copy that does not expose provider success/failure details beyond saying instructions will be sent if delivery is possible.
   - Acceptance: Verify-screen tests prove resend cooldown still blocks repeated resend, invalid-code cooldown remains independent from resend cooldown, and success/failure messages do not claim delivery beyond what Swoosh attempted.

4. **Terminal-native password reset request**: A user can request password-reset delivery from the terminal login flow when Swoosh email mode is configured, without being sent to a non-existent or out-of-scope browser workflow.
   - Current: Users have no terminal password-reset request path; the existing break-glass Mix task prints a reset URL for operators, but no browser reset route exists.
   - Target: Login offers a reset request path only when Swoosh email mode is enabled. It accepts the minimum identity needed to target an account, creates reset delivery details for matching active users, attempts Swoosh delivery, and always uses generic enumeration-safe copy for matching and non-matching input.
   - Acceptance: Tests prove a valid active user request creates a reset token/detail and attempts Swoosh delivery, an unknown/deleted/inactive user receives the same outward terminal response without delivery, no reset option appears in no-email mode, and no user-facing copy points to an unimplemented browser reset page.

5. **Operator delivery administration**: Operators can inspect and manage delivery-mode implications from both the Sysop TUI and a break-glass Mix task.
   - Current: Sysop configuration surfaces expose `require_email_verification`, but they do not know whether email delivery is possible; the reset Mix task can generate raw reset URLs even though no configured user reset delivery exists.
   - Target: Sysop TUI and Mix tooling both make the active delivery mode visible, prevent or flag the invalid no-email-plus-verification configuration, and make password reset unavailable in no-email mode instead of generating operator-relay reset details.
   - Acceptance: Tests prove both operator paths expose delivery mode, reject or clearly block `no_email + require_email_verification=true`, hide or disable password reset in no-email mode, and preserve Swoosh reset behavior when email is enabled.

6. **Honest user and operator copy**: Every changed terminal and Mix-task message distinguishes "emailed", "available for operator relay", "pending sysop approval", and "break-glass generated" outcomes.
   - Current: Register, Login, Verify, and reset task copy can imply email or notification delivery even when delivery is not attempted.
   - Target: No user-facing or operator-facing copy claims email, notification, verification, or reset delivery unless the corresponding Swoosh delivery path is enabled and attempted; delivery failures use generic copy, and pending approval notification copy is left honest for Phase 10 rather than promising MAIL-07 early.
   - Acceptance: Focused TUI and Mix-task tests assert the visible strings for Swoosh email mode, no-email mode, pending approval, resend, reset request, and break-glass reset paths do not contain false delivery claims.

## Boundaries

**In scope:**
- A Swoosh-backed delivery-mode contract that downstream Accounts/TUI code can consume.
- Swoosh email-mode delivery attempts for verification and user-requested password reset.
- No-email-mode validation that prevents email verification and password reset from being offered.
- Operator visibility for delivery mode and invalid delivery-dependent configuration from both Sysop TUI and Mix tooling.
- Swoosh email-mode Verify-screen resend behavior and generic delivery copy.
- Terminal login/reset request flow in Swoosh email mode only.
- Focused domain, config, TUI, and Mix-task tests for MAIL-01 through MAIL-06.

**Out of scope:**
- MAIL-07 approval/rejection notification delivery - Phase 10 owns user status administration and approval outcomes.
- Browser password-reset pages or other end-user browser workflows - Foglet remains SSH-first/TUI-first for this milestone.
- No-email verification relay or no-email password-reset relay - those workflows are invalid when email is disabled.
- Webhook notifications, email digests, delivery retry queues, and outbound delivery logs - these are v2 notification features.
- Full user administration in the Sysop USERS tab - Phase 10 owns pending, rejected, suspended, and reactivated user state operations.
- Storing Swoosh adapter credentials, API keys, or other secrets in the `configuration` table - secrets belong in runtime/environment config.
- Multi-node delivery guarantees or durable background job processing - v1.2 targets the current single-node Phoenix/OTP/Postgres deployment model.

## Constraints

- Domain mutations and delivery decisions must live in `Foglet.Accounts`, `Foglet.Config`, or another `Foglet.*` context boundary, not directly in TUI render functions.
- Runtime-editable non-secret delivery settings must be schematized in `Foglet.Config.Schema`, seeded, cached, and exposed through typed accessors.
- Email sending must use Swoosh.
- Swoosh adapter credentials must stay in runtime/environment config and must not be persisted in DB-backed config.
- TUI screens render already-loaded state and route work through commands or context calls; they must not perform direct Repo queries for delivery retrieval.
- Password-reset request copy must avoid user enumeration and must stay generic on delivery failure.
- Tests must preserve the existing verification-code expiry and resend/invalid-attempt cooldown semantics.

## Acceptance Criteria

- [ ] `Foglet.Config` or an equivalent context exposes a typed delivery-mode read path with Swoosh email and explicit no-email states.
- [ ] Swoosh email mode verification registration, login, and resend attempts delivery before copy says instructions were emailed.
- [ ] No-email mode prevents `require_email_verification=true` through normal operator configuration.
- [ ] No-email registration and login never route users to Verify as an operator-relay workaround.
- [ ] Verify-screen resend cooldown and invalid-attempt cooldown remain independent.
- [ ] Login exposes a terminal password-reset request path only in Swoosh email mode.
- [ ] Password-reset request responses are enumeration-safe and generic for unknown, deleted, inactive, or delivery-failure cases.
- [ ] No-email mode does not expose password reset to users or operators.
- [ ] No user-facing reset delivery points to an unimplemented browser reset page.
- [ ] Sysop TUI and Mix tooling both surface delivery mode and block or flag invalid delivery-dependent settings.
- [ ] Pending-approval copy does not promise email notification delivery before Phase 10 implements MAIL-07.
- [ ] Focused tests cover MAIL-01, MAIL-02, MAIL-03, MAIL-04, MAIL-05, and MAIL-06.

## Ambiguity Report

| Dimension           | Score | Min   | Status | Notes |
|---------------------|-------|-------|--------|-------|
| Goal Clarity        | 0.94  | 0.75  | met    | Swoosh email delivery, email-only verification/reset, and no-email invalid flows are locked. |
| Boundary Clarity    | 0.92  | 0.70  | met    | Browser reset, no-email relay, MAIL-07, user status admin, webhooks, digests, and delivery logs are excluded. |
| Constraint Clarity  | 0.86  | 0.65  | met    | Swoosh, SSH-first boundary, config/secrets split, no enumeration, generic failure copy, and cooldown preservation are locked. |
| Acceptance Criteria | 0.88  | 0.70  | met    | Acceptance is expressed as pass/fail checks across config, domain, TUI, Swoosh, and Mix paths. |
| **Ambiguity**       | 0.08  | <=0.20| met    | Weighted clarity is 0.92. |

Status: met = dimension meets minimum, below = planner treats as assumption.

## Interview Log

The first draft was generated from roadmap, requirements, and codebase scouting. This revision incorporates the user's clarifications from 2026-04-24.

| Round | Perspective | Question summary | Decision locked |
|-------|-------------|------------------|-----------------|
| 1 | Researcher | What exists today related to verification and reset? | Verification-code generation, verify/resend TUI, reset-token generation, and break-glass reset task exist; Swoosh delivery does not. |
| 2 | Researcher + Simplifier | What email library should be used? | Use Swoosh for email delivery. |
| 3 | Boundary Keeper | Where should operator delivery administration live? | Both Sysop TUI and Mix tooling must expose delivery-mode implications. |
| 4 | Boundary Keeper | When should password reset be available? | Only when Swoosh email mode is enabled; no-email mode must not offer password reset. |
| 5 | Failure Analyst | What should delivery-failure copy say? | Use generic copy rather than disclosing delivery failure or account existence. |
| 6 | Seed Closer | How should no-email interact with verification? | In no-email mode, email verification is not a valid configuration option. |

---

*Phase: 09-delivery-modes-and-onboarding-honesty*
*Spec created: 2026-04-24*
*Next step: $gsd-discuss-phase 9 - implementation decisions (how to build what is specified above)*
