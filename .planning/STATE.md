---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: milestone
status: executing
last_updated: "2026-04-28T19:58:43.160Z"
last_activity: 2026-04-28
progress:
  total_phases: 7
  completed_phases: 1
  total_plans: 7
  completed_plans: 5
  percent: 71
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-28)

**Core value:** A user can SSH into a living, reliable BBS and participate in conversations through a terminal-native experience that feels like arriving somewhere.
**Current focus:** Phase 35 — auth-home-screens

## Current Position

Phase: 35 (auth-home-screens) — EXECUTING
Plan: 3 of 4
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
- [Phase 34]: App stores transition route params separately from current_screen so legacy atom routing remains compatible.
- [Phase 34]: App runtime effect tests register sample screens through session_context.domain.screen_modules rather than production-screen-specific clauses.
- [Phase 34]: Task effect success/failure routing uses {:screen_task_result, screen_key, op, result} through screen update/3.
- [Phase 34]: Stateful screens must own first-class state structs with new/1 or document a local state type.
- [Phase 34]: Stateless screens must explicitly return :stateless or %{} from init/1 and avoid App-owned local storage.
- [Phase 34]: Production screen migrations remain deferred to phases 35-38; Phase 39 removes central App screen-specific machinery.
- [Phase 35]: [Phase 35-02]: Register and Verify keep their map-shaped state modules while exposing the Phase 34 screen contract.
- [Phase 35]: [Phase 35-02]: App no longer owns Register or Verify-specific production delegation clauses; onboarding task results route through generic screen_task_result.
- [Phase 35]: [Phase 35-02]: Register uses session effects for Verify routing, main-menu promotion, and pending-approval termination while App remains the runtime interpreter.

### Pending Todos

None yet.

### Blockers/Concerns

- Full migration touches every TUI screen and should be split into verifiable slices.
- Existing user-facing behavior must remain stable while the runtime boundary changes.
