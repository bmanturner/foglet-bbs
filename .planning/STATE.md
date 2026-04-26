---
gsd_state_version: 1.0
milestone: v1.3
milestone_name: TUI Screen Facelift
status: planning_next_milestone
stopped_at: v1.3 milestone archived
last_updated: "2026-04-26T17:36:00.000Z"
last_activity: 2026-04-26
progress:
  total_phases: 10
  completed_phases: 10
  total_plans: 48
  completed_plans: 48
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-26)

**Core value:** A user can SSH into a living, reliable BBS and participate in conversations through a terminal-native experience that feels like arriving somewhere.
**Current focus:** Planning next milestone

## Current Position

Phase: -
Plan: -
Status: v1.3 shipped; ready to define next milestone
Last activity: 2026-04-26 - Completed quick task 260426-jbn: fix one-connection-at-a-time bottleneck in SSH/Raxol stack

Progress: [##########] 100% for v1.3

## Performance Metrics

**Velocity:**

- Total plans completed: 84 from shipped v1.1; 26 in v1.2
- Average duration: Not measured for v1.2 yet
- Total execution time: Not measured for v1.2 yet

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 9. Delivery Modes and Onboarding Honesty | TBD | - | - |
| 10. User Status Administration | TBD | - | - |
| 11. Posting Policy Enforcement | TBD | - | - |
| 12. Account SSH Key Management | TBD | - | - |
| 13. Board Subscription Management | TBD | - | - |
| 14. Launch Hygiene and Operator Notes | TBD | - | - |
| 15. Reset Path Gap Closure | 1/2 | 6min | 6min |
| 15 | 2 | - | - |
| 16 | 4 | - | - |
| 18 | 7 | - | - |
| 17 | 5 | - | - |
| 19 | 3 | - | - |
| 23 | 4 | - | - |
| 24 | 6 | - | - |
| 21 | 4 | - | - |
| 25 | 6 | - | - |

**Recent Trend:**

- Last 5 plans: Not measured for v1.2 yet
- Trend: Not established

| Phase 15 P02 | 5min | 3 tasks | 5 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.

Recent decisions affecting current work:

- v1.2 is pre-alpha gap closure, not a feature expansion milestone.
- Foglet remains SSH-first/TUI-first; no end-user browser workflows are planned.
- Domain behavior belongs in `Foglet.*` contexts; TUI screens consume and present context results.
- Webhook notifications, email digests, full moderation case management, and browser admin are out of scope.
- Phase 15 keeps reset recovery browser-free: the operator Mix task prints raw reset tokens, not HTTP URLs.
- Operator reset-token generation is centralized in `Foglet.Accounts` using the existing hashed `UserToken` primitive.
- [Phase 15]: Kept README reset verification manual-only; no README-specific ExUnit tests or automated README gates were added.
- [Phase 15]: Preserved Phase 14 historical failure language while adding Phase 15 closure evidence.
- [v1.3]: `SCREENS.md` is the milestone PRD and defines the Classic Modern BBS plus Operator Console visual split.
- [v1.3]: Width-aware text/layout helpers should land before Unicode-heavy aligned rows or editor cursor paths.
- [v1.3]: Active research uses `SCREENS.md` rather than stale v1.2 pre-alpha gap-closure research.
- [v1.3]: Login is chrome/mode scope only unless a later phase explicitly expands authentication screen layout work.
- [v1.3]: Operator Console primitives are split from Account/Moderation/Sysop conversion so shared widgets land before dense screen rewrites.
- [v1.3]: 64x22 is the hard minimum terminal size; 80x24 is a compact design target; larger terminals progressively gain panels, inspectors, details, and extra status.
- [v1.3]: Milestone archived with deferred human SSH/TUI checks tracked as non-blocking close debt.

### Pending Todos

None yet.

### Blockers/Concerns

No active blockers. Phase planning should preserve delivery honesty, context-level enforcement, and break-glass operator paths where the roadmap calls for them.

### Quick Tasks Completed

| # | Description | Date | Commit | Status | Directory |
|---|-------------|------|--------|--------|-----------|
| 260426-g0k | There is an issue with text input. If I type five characters and backspace to erase the whole string, the first character is always present and impossible to replace, and if I begin typing more characters, that first character gets pushed to the right by the inserted characters | 2026-04-26 | 8b9c3f3 | Verified | [260426-g0k-there-is-an-issue-with-text-input-if-i-t](./quick/260426-g0k-there-is-an-issue-with-text-input-if-i-t/) |
| 260426-gnq | Put Chrome V2 breadcrumb/status and command hints on the screen border rows | 2026-04-26 | ae623da | Verified | [260426-gnq-the-recent-milestone-was-supposed-to-cha](./quick/260426-gnq-the-recent-milestone-was-supposed-to-cha/) |
| 260426-hbu | Add a cursor icon to active text inputs | 2026-04-26 | 9a9fedc | Verified | [260426-hbu-we-need-a-cursor-icon-to-appear-on-the-t](./quick/260426-hbu-we-need-a-cursor-icon-to-appear-on-the-t/) |
| 260426-jdz | Fix board breadcrumb struct access view error | 2026-04-26 | c357fc6 | Verified | [260426-jdz-gsd-quick-full-id-56e39788-5cba-41d3-abb](./quick/260426-jdz-gsd-quick-full-id-56e39788-5cba-41d3-abb/) |
| 260426-jbn | Fix one-connection-at-a-time bottleneck in SSH/Raxol stack (filed raxol#228, #229) | 2026-04-26 | _pending_ | Verified | [260426-jbn-the-application-only-allows-one-active-c](./quick/260426-jbn-the-application-only-allows-one-active-c/) |

## Deferred Items

Items acknowledged and carried forward from v1.1 close:

| Category | Item | Status |
|----------|------|--------|
| uat_gap | v1.1 Phases 02, 04, 05, 07, and 08 have pending human UAT scenarios | carried forward |
| verification_gap | v1.1 Phases 02, 04, 05, 07, and 08 need human verification artifacts | carried forward |
| verification_gap | v1.1 Phase 06 time-only chrome was accepted as intentional | accepted |
| seed | SEED-001 user notifications over webhook | out of scope for v1.2 |
| seed | SEED-002 email verification UX | partially incorporated into Phase 9 |

Items acknowledged and deferred at v1.3 close on 2026-04-26:

| Category | Item | Status |
|----------|------|--------|
| uat_gap | Phase 18 Chrome V2 human terminal scenarios | deferred |
| uat_gap | Phase 19 Main Menu human terminal scenarios | deferred |
| verification_gap | Phase 18 Chrome V2 real terminal visual and keyboard-flow checks | human_needed |
| verification_gap | Phase 19 Main Menu real SSH rendering and live oneliner PubSub checks | human_needed |
| seed | SEED-001 user notifications over webhook | dormant |
| seed | SEED-002 email verification UX | dormant |

## Session Continuity

Last session: 2026-04-26
Stopped at: v1.3 milestone archived
Resume file: .planning/PROJECT.md
