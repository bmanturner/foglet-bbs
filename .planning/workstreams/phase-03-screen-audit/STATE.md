---
gsd_state_version: 1.0
workstream: phase-03-screen-audit
milestone: v1.0.2
milestone_name: screen-audit
status: defining_requirements
last_updated: "2026-04-21T00:00:00.000Z"
last_activity: 2026-04-21
progress:
  total_phases: 0
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
---

# Workstream State — phase-03-screen-audit

## Project Reference

See: .planning/PROJECT.md (shared across workstreams — **not modified from inside a workstream**)

**Core value:** Two users SSHing into the same BBS and feeling like they're actually present together.
**Workstream focus:** Retrospective audit of the 9 TUI screens shipped through `phase-03-polish`. Two concerns per screen — (a) idiomatic Elixir correctness, (b) styling/primitive adoption — with a bias toward sparseness so later milestones (Presence, Chat, DMs, Search) have room to layer in functionality without a re-layout.

## Relationship to Other Workstreams

- Main workstream (`.planning/STATE.md`) — at v1.0, Phase 04 (Presence & Login Sequence) next up on the main roadmap.
- Sibling workstream `phase-03-polish` — complete (8 phases); delivered the widget foundation, theme, chrome, markdown rendering, composer end-to-end, terminal-size gate, Raxol migration, and the local widget library this workstream will audit against.
- This workstream makes no domain/functional changes — it pulls the Phase 03 screens up to the bar set by Phases 6-8 of `phase-03-polish` (theme hygiene, primitive adoption, D-07/D-09/D-13/D-14/D-16 conformance).

## Current Position

**Phase:** Not started (defining requirements)
**Plan:** —
**Status:** Defining requirements
**Last activity:** 2026-04-21 — Workstream created from `/gsd-new-milestone --ws phase-03-screen-audit`

## Milestone Scope (from user)

- Audit each of 9 TUI screens for idiomatic Elixir correctness
- Update styling on each screen to fully exploit the existing `Foglet.TUI.Widgets.*` primitives + `Foglet.TUI.Theme`
- **Err on the side of sparseness** — preserve vertical/horizontal real estate for upcoming milestones (Phase 4 Presence, Phase 5 Chat, Phase 6 DMs/Mentions, Phase 9 Search/Oneliners)
- One phase per screen; 9 phases total, restart numbering at 1
- Research first — spawn 4 parallel researchers before defining requirements

## Accumulated Context

Inherited from `phase-03-polish` (widget contracts, theme struct, D-07..D-20 decisions):

### Decisions locked (inherited, not re-decided)

- `Foglet.TUI.Theme` struct is the sole color routing path (D-07/D-09)
- All widgets accept `theme:` as explicit keyword arg (D-13)
- Stateful widgets expose `init/1 + handle_event/2 + render/2` (D-14); stateless widgets expose `render/*` only (D-16)
- Raxol `ThemeManager` is rejected
- Widget directory convention: `lib/foglet_bbs/tui/widgets/<bucket>/<name>.ex` (D-10)
- No hardcoded color atoms — every color via a Theme slot

### Reference seeds

None matched at workstream creation (seeds checked in step 2.5 of workflow).

## Session Continuity

Last session: 2026-04-21 — workstream created, research pending.
