# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-23)

**Core value:** A user can SSH into a living, reliable BBS and participate in conversations through a terminal-native experience that feels like arriving somewhere.
**Current focus:** Phase 0 - Screen Shells and Shared Surface Primitives

## Current Position

Phase: 0 of 9 (Screen Shells and Shared Surface Primitives)
Plan: 0 of TBD in current phase
Status: Ready to plan
Last activity: 2026-04-23 - Roadmap revised to 9 phases for milestone v1.1 Operations Surfaces & Invites

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**
- Total plans completed: 0
- Average duration: -
- Total execution time: 0.0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 0. Screen Shells and Shared Surface Primitives | 0 | - | - |
| 1. Authorization and Scope Backbone | 0 | - | - |
| 2. Sysop Config and Board Management | 0 | - | - |
| 3. Invite Persistence and Registration Enforcement | 0 | - | - |
| 4. Shared Invite Surface Activation | 0 | - | - |
| 5. Account Preferences and Live Session Refresh | 0 | - | - |
| 6. Chrome Clock and Main Menu Wiring | 0 | - | - |
| 7. Oneliners and Main Menu Social Strip | 0 | - | - |
| 8. Moderation Workspace Population and Scope-Aware Operations | 0 | - | - |

**Recent Trend:**
- Last 5 plans: -
- Trend: -

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Phase 0 is shell-only work: route, tab, and state scaffolding without fake persistence or fake operator behavior.
- Shared invite flows stay single-use in v1.1 and reuse one `INVITES` surface across allowed screens.
- Moderation remains scope-aware so future board-scoped moderators fit without reworking authorization later.
- Main-menu clock placement is in the top-right chrome, with new-user defaults of system timezone and 12-hour time.

### Pending Todos

None yet.

### Blockers/Concerns

- Phase 2 depends on Phase 1 exposing actor-aware policy first, so sysop and moderation surfaces do not rely on screen-only auth.
- Phase 4 depends on Phase 3 finishing real invite persistence and redemption before the reusable `INVITES` UI becomes operational.
- Chrome time rendering must honor system timezone and 12-hour defaults for new accounts before user preferences are saved.

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| *(none)* | | | |

## Session Continuity

Last session: 2026-04-23 11:17 CDT
Stopped at: Roadmap revised to 9 phases; Phase 0 is ready for planning
Resume file: None
