# Project Research Summary

**Project:** Foglet BBS v1.2 Pre-Alpha Gap Closure
**Domain:** SSH-first BBS pre-alpha readiness, onboarding honesty, sysop administration, posting policy enforcement, SSH keys, and board subscriptions
**Researched:** 2026-04-24
**Confidence:** HIGH

## Executive Summary

This milestone uses `GAP_MILESTONE.md`, not external ecosystem research, as the source of truth. The audit is codebase-first and identifies incomplete functionality already exposed by Foglet's current terminal product surface. The milestone should therefore close visible gaps before adding new reach features.

The decisive theme is honesty plus enforcement. If Foglet says a code was emailed, delivery must be attempted or the copy must say how the operator will deliver it. If sysops can select `sysop_approved`, pending users must have an approval path. If a board exposes `postable_by`, thread and reply creation must enforce it inside contexts before board-server writes. If SSH keys and board subscriptions exist as domain concepts, users need terminal workflows to manage them.

## Key Findings

### Recommended Stack

Use the existing Phoenix/Ecto/Postgres/Raxol/OTP stack. Add an email delivery dependency only if implementation planning confirms the project does not already have an appropriate mailer. Keep delivery-mode configuration in `Foglet.Config.Schema`, runtime behavior in `Foglet.Config`, domain side effects in `Foglet.Accounts`, and user-facing behavior in SSH/TUI screens.

### Expected Features

**Must have:**
- Operational or explicitly disabled email/no-email mode for verification, reset, and pending approval.
- Sysop user-status queue and actor-aware Accounts APIs for approve, reject, suspend, and reactivate.
- Mix task coverage for break-glass user status administration and code/reset delivery.
- Context-level board posting policy and locked-thread enforcement.
- Account `SSH KEYS` management tab.
- Board subscription directory or management flow.
- Copy and tests proving visible sysop configuration options have real effect or honest disabled behavior.

**Defer:**
- Webhook notifications.
- Email digests.
- Rich moderation case management.
- End-user browser administration.

### Critical Pitfalls

1. **Screen-only enforcement** - posting policy and user-status changes must be enforced in contexts, not only hidden TUI controls.
2. **False delivery claims** - verification, reset, and pending-approval screens must not say "emailed" unless delivery is real.
3. **Dead-end registration modes** - `sysop_approved` and no-email verification must have operator-completable workflows.
4. **Board server bypass** - policy checks must happen before `Foglet.Boards.Server` allocates message numbers or persists posts.
5. **Subscription confusion** - empty states must point to real self-service or sysop-service actions.

## Seed Selection

- Included `SEED-002: Resend verification email from Verify screen + configurable email verification requirement` because it directly matches email delivery, verification, and onboarding gaps.
- Excluded `SEED-001: User notifications over webhook` because webhook delivery is a future notification channel and not required for pre-alpha gap closure.

## Sources

### Primary
- `GAP_MILESTONE.md`
- `.planning/PROJECT.md`
- `.planning/MILESTONES.md`
- `.planning/STATE.md`
- `docs/DATA_MODEL.md`
- Current code references found for email verification, user status, posting policy, SSH keys, and subscriptions

---
*Research synthesis updated: 2026-04-24*
*Ready for roadmap: yes*
