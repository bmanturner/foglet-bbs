---
workstream: phase-03-polish
milestone: v1.0.1
milestone_name: Phase 03 Polish
created: 2026-04-19
status: defining_requirements
last_updated: 2026-04-19
last_activity: 2026-04-19
progress:
  total_phases: 0
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Workstream State — phase-03-polish

## Project Reference

See: .planning/PROJECT.md (shared across workstreams)

**Core value:** Two users SSHing into the same BBS and feeling like they're actually present together.
**Workstream focus:** Harden the SSH + TUI experience shipped in Phase 03 — consistency, readability, and functional completeness — before the main workstream moves on to Presence (Phase 04).

## Relationship to Main Workstream

- Main workstream (`.planning/STATE.md`) is at v1.0, Phase 04 context gathered, ready to plan Presence & Login Sequence.
- Phase 03 (SSH + TUI) is marked complete on the main roadmap with 6/6 plans shipped — functional but rough.
- This workstream addresses polish/correctness gaps surfaced in hands-on use that don't belong in Phase 04.

## Current Position

**Phase:** Not started (defining requirements)
**Plan:** —
**Status:** Defining requirements for v1.0.1 polish milestone
**Last activity:** 2026-04-19 — Workstream created; milestone scope confirmed with user

## Milestone Scope (from user)

Ten items to be shaped into requirements:

1. Markdown → ANSI rendering is broken (posts show raw markdown)
2. Layout is inconsistent across screens (header/divider/statusbar vary) — StatusBar should be a reusable widget at the top with a divider beneath, showing page context and user handle
3. Seeded threads in General don't render properly (wrapping / other rendering issues)
4. Boards list shows stuck unread count (`(6 unread)` next to General) that never clears
5. Thread list rows need more info — creator handle, last-activity "time ago" (30s, 5m, 2w)
6. Theme application is inconsistent — border box and some text don't pick up theme
7. Composer has no title field, so starting a new thread from the board page is impossible
8. Build a thin reusable-widget layer on top of Raxol — **without reinventing widgets Raxol already provides** (docs at `docs/raxol/`)
9. Minimum terminal dimensions — show "terminal too small" message below threshold
10. Audit email verification — toggleable skip per registration mode via sysop config; wire stubbed resend affordance (picks up SEED-002)
11. Wire thread creation + post reply end-to-end

## Accumulated Context

### Decisions
Inherited from main workstream (see `.planning/PROJECT.md` Key Decisions).

### Blockers/Concerns
- Research pending (Raxol widget inventory) before requirement refinement to ensure reuse over reinvention.

### Reference Seeds
- SEED-002 (email-verification-ux) — folded into scope item #10 above.

## Session Continuity

Last session: 2026-04-19 workstream created
Stopped at: Milestone scope confirmed; about to run research + draft REQUIREMENTS.md
