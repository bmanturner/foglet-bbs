---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: milestone
status: executing
last_updated: "2026-04-28T18:18:48.079Z"
last_activity: 2026-04-28
progress:
  total_phases: 7
  completed_phases: 0
  total_plans: 3
  completed_plans: 1
  percent: 33
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-28)

**Core value:** A user can SSH into a living, reliable BBS and participate in conversations through a terminal-native experience that feels like arriving somewhere.
**Current focus:** Phase 34 — runtime-contract-effects

## Current Position

Phase: 34 (runtime-contract-effects) — EXECUTING
Plan: 2 of 3
Status: Ready to execute
Last activity: 2026-04-28

## Accumulated Context

### Decisions

- v2.0 is an architecture milestone, not a product feature milestone.
- `Foglet.TUI.App` should become a small runtime shell that owns process/session/runtime concerns.
- Screens should own local state, key handling, async-result handling, and render input through `init/update/render`.
- Screens may request domain work through explicit effects; durable behavior and authorization remain in context modules.
- [Phase 34]: New screen callbacks are optional during phases 34-38 so existing production screens keep compiling until migration.
- [Phase 34]: Foglet.TUI.Effect constructors use precise variant return types for Dialyzer-friendly contracts.
- [Phase 34]: Foglet.TUI.Context rejects unknown fields to enforce the screen-facing boundary.

### Pending Todos

None yet.

### Blockers/Concerns

- Full migration touches every TUI screen and should be split into verifiable slices.
- Existing user-facing behavior must remain stable while the runtime boundary changes.
