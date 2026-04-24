# Project Milestones: Foglet BBS

## v1.1 Operations Surfaces & Invites (Shipped: 2026-04-24)

**Delivered:** A fuller SSH/TUI operations surface with account preferences, shared invite workflows, sysop controls, persistent oneliners, and populated moderation tooling.

**Phases completed:** 0-8, including inserted Phase 1.1 (10 phases, 43 plans, 64 tasks)

**Key accomplishments:**

- Added Account, Moderation, and Sysop TUI surfaces with shared shell/state primitives and role-aware navigation.
- Introduced actor-aware authorization and reusable modal form infrastructure for operator workflows.
- Shipped persisted single-use invites, invite-only registration redemption, and shared live INVITES tabs across allowed surfaces.
- Added sysop runtime config, board/category management, and system snapshot screens.
- Added account profile/preferences with live session refresh and user-format-aware chrome time display.
- Added persistent oneliners plus moderation hide/audit workflows inside the terminal UI.

**Known deferred items at close:** 19 open planning artifacts acknowledged and deferred (see `.planning/STATE.md` Deferred Items).

**Audit note:** Phase 6's date-rendering audit concern was accepted as intentional. The chrome clock is time-only by product decision and still honors user timezone and 12h/24h preferences.

**What's next:** Start a fresh milestone with `$gsd-new-milestone`.

---
