---
id: SEED-001
status: dormant
planted: 2026-04-18
planted_during: Phase 1 — Accounts & Identity (pre-planning)
trigger_when: When building Phase 10 (Email Notifications) or any milestone adding external notification delivery
scope: Small
---

# SEED-001: User notifications over webhook

## Why This Matters

Provides a delivery channel that works even when the user isn't logged in and doesn't
want email. The in-BBS notification system (Phase 6) only reaches users who are actively
connected via SSH. Email (Phase 10) covers offline users but requires an SMTP setup and
not everyone wants email. A per-user webhook URL fills the gap: users who want to pipe
BBS activity into Discord, a personal bot, a home automation system, or any HTTP endpoint
can do so without polling and without giving the BBS their email.

## When to Surface

**Trigger:** When building Phase 10 (Email Notifications) or any milestone that introduces
a new notification delivery channel.

This seed should be presented during `/gsd-new-milestone` when the milestone scope matches
any of these conditions:
- Email notifications are being added (Phase 10 — Swoosh + Oban scheduled jobs)
- A new notification delivery mechanism is being designed
- An "integrations" or "extensibility" milestone is being planned
- The notification dispatcher (built in Phase 6) is being extended with new delivery targets

## Scope Estimate

**Small** — A few hours. The notification event schema already normalizes activity into
structured `payload :map` objects (`docs/DATA_MODEL.md` §8). Webhook delivery is a new
dispatcher target alongside the existing PubSub (in-BBS) and future email dispatchers.
Core implementation:
- `webhook_subscriptions` table (user_id, url, events[], secret for HMAC signing)
- `Foglet.Notifications.WebhookDispatcher` — Oban job that POSTs the notification payload
- User preference UI to register/manage webhook URLs (TUI screen or Mix task)
- HMAC-SHA256 signing of payloads (security baseline)

## Breadcrumbs

Related code and decisions found in the current codebase:

- `docs/DATA_MODEL.md` §8 (Notifications) — `Foglet.Notifications.Notification` schema;
  `payload :map` (jsonb) already normalizes event data into a structured shape that's
  ready to POST to a webhook endpoint as-is
- `docs/DATA_MODEL.md` §Conventions — `payload :map` backed by jsonb; explicitly mentioned
  as the pattern for "notification payloads"
- `.planning/REQUIREMENTS.md` SOCL-04, SOCL-05 — in-BBS notification dispatcher (Phase 6)
  is the system webhooks would tap into
- `.planning/REQUIREMENTS.md` EMAIL-01 through EMAIL-05 — Phase 10 adds Swoosh + Oban
  for email delivery; webhook is a natural peer to wire in at the same time
- `.planning/ROADMAP.md` Phase 6 — builds `Foglet.Notifications` dispatcher + PubSub
  delivery; webhook dispatcher would be an additional output of this pipeline
- `.planning/ROADMAP.md` Phase 10 — Email Notifications via Oban scheduled jobs; Oban
  is already included in the scaffold and is the right primitive for async webhook delivery

## Notes

The architecture is already set up for this. The notification system (Phase 6) dispatches
events through a pipeline — adding a webhook target is additive, not structural. The
`payload :map` field on the `notifications` table is the JSON body; signing it with
HMAC-SHA256 using a per-subscription secret is the only additional complexity.

Consider surfacing this in the Phase 10 planning discussion: "while we're adding outbound
delivery channels (Swoosh), should webhooks land here too?"
