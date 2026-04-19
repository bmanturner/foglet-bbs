---
id: SEED-002
status: dormant
planted: 2026-04-19
planted_during: v1.0 / Phase 03 UAT
trigger_when: Phase 10 (Email Notifications) planning, or any milestone touching email delivery, account verification, or sysop configuration
scope: Medium
---

# SEED-002: Resend verification email from Verify screen + configurable email verification requirement

## Why This Matters

Two related gaps discovered during Phase 03 UAT:

1. **Resend**: When an unverified user exits the Verify screen and logs in again, they're redirected back to Verify (now fixed) but have no way to request a new code if the original expired. The `{:resend}` event is already stubbed in `verify.ex` but not wired to a visible UI affordance.

2. **Configurable requirement**: Some sysops run private/trusted BBSs and don't want to require email verification. A `require_email_verification` config key (defaulting to `true`) would let them skip the whole flow, treating all newly registered users as immediately confirmed.

## When to Surface

**Trigger:** Phase 10 (Email Notifications) — when Swoosh SMTP delivery is being wired up, this seed should be presented because the resend flow requires actual email delivery to be meaningful. Also relevant to any milestone adding sysop config options.

This seed should be presented during `/gsd-new-milestone` when the milestone scope matches any of these conditions:
- Mentions email delivery, Swoosh, SMTP, or transactional email
- Adds or extends sysop-facing configuration options
- Touches account registration or onboarding flow

## Scope Estimate

**Medium** — two related but independently shippable pieces:
- Resend UI: wire existing `{:resend}` event stub in `verify.ex` to a visible key hint + cooldown display. Small on its own.
- Configurable verification: add `require_email_verification` to `Foglet.Config`, check it in `login.ex` `confirmed_at: nil` clause and `register.ex` submit. Medium — needs config, accounts, and TUI changes.

## Breadcrumbs

- `lib/foglet_bbs/tui/screens/verify.ex:101,109` — `{:resend}` event already stubbed in `handle_verify_event/2` via `resend_code_raw/1`
- `lib/foglet_bbs/tui/screens/login.ex:273` — `confirmed_at: nil` guard redirects unverified users to Verify screen
- `lib/foglet_bbs/tui/screens/register.ex:245` — `build_verify_code` called on registration
- `lib/foglet_bbs/accounts.ex:156` — `build_verify_code/1` spec and implementation
- `lib/foglet_bbs/accounts/user.ex:29` — `confirmed_at` field on User schema
- `.planning/ROADMAP.md` Phase 10 — Email Notifications milestone where SMTP delivery lands

## Notes

Discovered during Phase 03 UAT when testing the unverified re-login bypass. The bypass was fixed inline (redirect to Verify), but the full UX (resend + optional enforcement) is Phase 10 work.
