# Project Retrospective

## Milestone: v1.1 — Operations Surfaces & Invites

**Shipped:** 2026-04-24  
**Phases:** 10 | **Plans:** 43

### What Was Built

- Account, Moderation, and Sysop terminal surfaces with shared shell and state primitives.
- Actor-aware authorization, stable scope shapes, and shared modal-form infrastructure.
- Persisted single-use invites, invite-only registration redemption, and shared live INVITES tabs.
- Account profile/preferences with live session refresh and preference-aware chrome time display.
- Persistent main-menu oneliners with composer flow.
- Moderation workspace population plus audited oneliner hide behavior.

### What Worked

- Small phase slices kept the SSH/TUI surface changes reviewable.
- Shared primitives prevented invite and form logic from forking across Account, Moderation, and Sysop.
- Phase verification caught a requirement wording mismatch before archive, and the product decision was recorded explicitly.

### What Was Inefficient

- Some planning metadata drifted from phase verification state, especially roadmap and requirements checkboxes.
- Several human UAT artifacts remained partial at close and had to be acknowledged as deferred.
- Summary extraction produced noisy milestone accomplishments, so the shipped entry needed manual cleanup.

### Patterns Established

- Domain mutations stay in contexts with actor-aware authorization.
- TUI screens delegate reusable behavior to shared widgets/actions and keep rendering pure over loaded state.
- Runtime configuration exposed in the TUI must be schematized and written through `Foglet.Config.put/3`.

### Key Lessons

- Requirement wording should be adjusted promptly when product intent changes, especially for UI display details.
- Milestone close should reconcile tracking metadata before archival to avoid stale pending states.
- Human terminal checks need an explicit owner or they accumulate as close-time debt.

## Cross-Milestone Trends

| Trend | Observation |
|-------|-------------|
| Planning metadata drift | Requirements and roadmap status can lag behind verified implementation. |
| Reusable TUI primitives | Shared widgets/actions reduce duplicated screen behavior. |
| Human UAT | Terminal visual and keyboard-flow checks remain hard to replace with automated tests. |
