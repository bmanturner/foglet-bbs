# Phase 9: Delivery Modes and Onboarding Honesty - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the analysis.

**Date:** 2026-04-24
**Phase:** 09-delivery-modes-and-onboarding-honesty
**Mode:** assumptions
**Areas analyzed:** Delivery Mode Configuration, Verification Delivery Boundary, Password Reset Flow, Operator Surfaces And Honest Copy

## Assumptions Presented

### Delivery Mode Configuration

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Delivery mode should be represented as one schematized, runtime-editable, non-secret config key with exactly two enum values, exposed through a typed `Foglet.Config` accessor; Swoosh adapter credentials stay in runtime/environment config. | Likely | `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-SPEC.md`, `lib/foglet_bbs/config/schema.ex`, `lib/foglet_bbs/config.ex`, `docs/DATA_MODEL.md` |

### Verification Delivery Boundary

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Registration, login re-entry, and Verify-screen resend should stop calling `Accounts.build_verify_code/1` as the delivery workflow and instead route through an Accounts-level delivery function that creates the code, attempts Swoosh delivery in email mode, and returns only generic success/failure information to TUI callers. | Confident | `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-SPEC.md`, `lib/foglet_bbs/tui/screens/register.ex`, `lib/foglet_bbs/tui/screens/login.ex`, `lib/foglet_bbs/tui/screens/verify.ex`, `lib/foglet_bbs/accounts.ex` |

### Password Reset Flow

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| User-requested password reset should be added as a terminal login subflow available only in Swoosh email mode, backed by an enumeration-safe Accounts function that targets active, non-deleted users and does not expose the existing browser-style reset URL to end users. | Likely | `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-SPEC.md`, `lib/foglet_bbs/tui/screens/login.ex`, `lib/foglet_bbs/accounts.ex`, `lib/foglet_bbs/accounts/user.ex`, `lib/mix/tasks/foglet.user.reset_password.ex` |

### Operator Surfaces And Honest Copy

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Operator-facing delivery-mode control and invalid-combination feedback should be integrated into existing Sysop config forms plus the break-glass reset Mix task, while visible copy in Register, Login, Verify, and reset tooling must be updated where it currently promises email/notifications without delivery. | Confident | `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-SPEC.md`, `.planning/milestones/v1.1-phases/02-sysop-config-and-board-management/02-CONTEXT.md`, `lib/foglet_bbs/tui/screens/sysop/site_form.ex`, `lib/foglet_bbs/tui/screens/sysop/limits_form.ex`, `lib/foglet_bbs/tui/screens/register.ex`, `lib/foglet_bbs/tui/screens/verify.ex`, `lib/mix/tasks/foglet.user.reset_password.ex` |

## Corrections Made

No corrections — all assumptions confirmed.

## External Research

- Swoosh dependency/version choice, mailer module configuration, adapter-specific runtime/env settings, and test delivery assertions need official Swoosh/Phoenix guidance during research. The repo currently has no Swoosh dependency or mailer module.
