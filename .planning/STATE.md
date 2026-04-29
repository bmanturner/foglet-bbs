---
gsd_state_version: 1.0
milestone: v2.1
milestone_name: milestone
status: executing
stopped_at: Completed 42-04-PLAN.md
last_updated: "2026-04-29T22:18:04.466Z"
last_activity: 2026-04-29
progress:
  total_phases: 6
  completed_phases: 1
  total_plans: 9
  completed_plans: 8
  percent: 89
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-29)

**Core value:** A user can SSH into a living, reliable BBS and participate in conversations through a terminal-native experience that feels like arriving somewhere.
**Current focus:** Phase 42 — app-runtime-helper-extraction

## Current Position

Phase: 42 (app-runtime-helper-extraction) — EXECUTING
Plan: 5 of 5
Status: Ready to execute
Last activity: 2026-04-29

Progress: [█████████░] 89%

## Performance Metrics

**Velocity:**

- Total plans completed: 8
- Average duration: N/A
- Total execution time: 0.0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 41-46 | TBD | TBD | N/A |
| 41 | 4 | - | - |

**Recent Trend:**

- Last 5 plans: none
- Trend: N/A

| Phase 42 P01 | 9min | 3 tasks | 4 files |
| Phase 42 P42-02 | 7min | 3 tasks | 4 files |
| Phase 42 P42-03 | 8min | 3 tasks | 5 files |
| Phase 42 P42-04 | 8min | 3 tasks | 4 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table. Recent decisions affecting current work:

- v2.1 addresses every item in `.planning/codebase/CONCERNS.md` through implementation, documentation, tests, or a final verification disposition.
- Phase numbering continues from v2.0, starting at Phase 41.
- Research is intentionally skipped for v2.1 because this is internal hardening and cleanup rather than new feature discovery.
- Roadmap phases are derived only from v2.1 requirements in `.planning/REQUIREMENTS.md`.
- [Phase 42]: Routing owns route encoding, screen-key derivation, context construction, screen module resolution, reducer dispatch, and render dispatch.
- [Phase 42]: Foglet.TUI.App keeps public route helper delegators only for render fixtures and screen-focused test boundaries; implementation lives in Routing.
- [Phase 42]: Modal owns overlay rendering, modal key precedence, confirm callbacks, dismissal, form event routing, and generic form-submit failure visibility.
- [Phase 42]: Foglet.TUI.App delegates modal-owned behavior while keeping high-level App update messages and Raxol callbacks.
- [Phase 42]: Routing interprets reducer-returned effects through App.Effects so App no longer exposes public effect helper functions.
- [Phase 42]: Effects owns interpretation of current Foglet.TUI.Effect values while App owns when shell messages enter effect interpretation.
- [Phase 42]: Subscriptions owns heartbeat gating, chrome clock interval wiring, PubSubForwarder wiring, InitialRouteEnterForwarder wiring, user topics, screen-declared topics, and dynamic refresh diffing.
- [Phase 42]: Foglet.TUI.App retains only the Raxol callback integration points for subscribe/1 and post-update refresh timing.

### Pending Todos

None yet.

### Blockers/Concerns

- Keep the milestone bounded to stability and maintenance hardening; do not add new end-user product surfaces.
- Preserve SSH-first TUI behavior while changing runtime, screen, and lifecycle internals.

## Deferred Items

Previous milestone carried forward 16 acknowledged debug/quick/seed items. They remain outside v2.1 unless represented by `.planning/codebase/CONCERNS.md`; see the previous STATE history and `.planning/MILESTONES.md` for the archive summary.

## Session Continuity

Last session: 2026-04-29T22:18:04.462Z
Stopped at: Completed 42-04-PLAN.md
Resume file: None
