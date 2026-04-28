---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: milestone
status: executing
last_updated: "2026-04-28T21:22:44.555Z"
last_activity: 2026-04-28
progress:
  total_phases: 7
  completed_phases: 3
  total_plans: 10
  completed_plans: 10
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-28)

**Core value:** A user can SSH into a living, reliable BBS and participate in conversations through a terminal-native experience that feels like arriving somewhere.
**Current focus:** Phase 37 — post-composer-flow

## Current Position

Phase: 37
Plan: Not started
Status: Ready to plan Phase 37
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
- [Phase 35-auth-home-screens]: MainMenu now uses a first-class State struct for recent oneliners, selection, pending hide target, status, and form errors.
- [Phase 35-auth-home-screens]: MainMenu reducer tests assert local state and Effect values instead of legacy handle_key/2 or App top-level oneliner fields.
- [Phase 35-auth-home-screens]: App still carries transitional oneliner compatibility clauses for Plan 35-04 cleanup, but load results now feed MainMenu screen_state.
- [Phase 35-auth-home-screens]: App no longer carries Phase 35 production local-flow do_update clauses for Login, Register, Verify, or MainMenu/oneliners. — Plan 35-04 cleanup completed auth/home screen-owned update loop migration.
- [Phase 35-auth-home-screens]: MainMenu initial and navigation loads enter through MainMenu.update/3 using the generic screen reducer/effect path. — Keeps App as runtime interpreter while MainMenu owns oneliner loading.
- [Phase 35-auth-home-screens]: Modal form submit routing remains App runtime plumbing but carries only a generic screen key, submit kind, and payload. — Preserves modal precedence without App owning target screen business state.

### Pending Todos

None yet.

### Blockers/Concerns

- Full migration touches every TUI screen and should be split into verifiable slices.
- Existing user-facing behavior must remain stable while the runtime boundary changes.
