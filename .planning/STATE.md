---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: TUI Runtime Shell & Screen Update Loops
status: planning
last_updated: "2026-04-28T17:00:56.871Z"
last_activity: 2026-04-28
progress:
  total_phases: 7
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-28)

**Core value:** A user can SSH into a living, reliable BBS and participate in conversations through a terminal-native experience that feels like arriving somewhere.
**Current focus:** v2.0 TUI Runtime Shell & Screen Update Loops

## Current Position

Phase: 34 (next up)
Plan: —
Status: Roadmap approved; ready to discuss or plan Phase 34
Last activity: 2026-04-28 — v2.0 roadmap approved; next phase is Phase 34

## Accumulated Context

### Decisions

- v2.0 is an architecture milestone, not a product feature milestone.
- `Foglet.TUI.App` should become a small runtime shell that owns process/session/runtime concerns.
- Screens should own local state, key handling, async-result handling, and render input through `init/update/render`.
- Screens may request domain work through explicit effects; durable behavior and authorization remain in context modules.

### Pending Todos

None yet.

### Blockers/Concerns

- Full migration touches every TUI screen and should be split into verifiable slices.
- Existing user-facing behavior must remain stable while the runtime boundary changes.
