---
gsd_state_version: 1.0
milestone: v1.0.2
milestone_name: milestone
status: planning
stopped_at: Phase 5 context gathered
last_updated: "2026-04-22T01:52:51.594Z"
last_activity: 2026-04-21
progress:
  total_phases: 10
  completed_phases: 5
  total_plans: 11
  completed_plans: 11
  percent: 100
---

# Workstream State — phase-03-screen-audit

## Project Reference

See: .planning/PROJECT.md (shared across workstreams — **not modified from inside a workstream**)

**Core value:** Two users SSHing into the same BBS and feeling like they're actually present together.
**Workstream focus:** Retrospective audit of the 9 TUI screens shipped through `phase-03-polish`. Two concerns per screen — (a) idiomatic Elixir correctness, (b) styling/primitive adoption — with a **sparseness bias** so Milestones 4 (Presence), 5 (Chat), 6 (DMs/Notifications), and 9 (Search/Oneliners) have room to layer in functionality without a re-layout.

## Relationship to Other Workstreams

- Main workstream (`.planning/STATE.md`) — at v1.0, Phase 04 (Presence & Login Sequence) next up on the main roadmap.
- Sibling workstream `phase-03-polish` — complete (8 phases); delivered the widget foundation, theme, chrome, markdown rendering, composer end-to-end, terminal-size gate, Raxol migration, and the local widget library this workstream audits against.
- This workstream makes no domain/functional changes — it pulls the Phase 03 screens up to the bar set by Phases 6-8 of `phase-03-polish` (theme hygiene, primitive adoption, D-07/D-09/D-13/D-14/D-16 conformance).

## Current Position

Phase: 04 (mainmenu) — EXECUTING
Plan: Not started
**Phase:** 5 of 10 (boardlist)
**Next:** Phase 3 (Verify) — hand-rolled 6-char buffer preserved; consolidate 7 default-state literals; wizard-state migration to screen_state[:verify]
**Status:** Ready to plan
**Last activity:** 2026-04-21

Progress: [███░░░░░░░] 30%

## Roadmap Summary

10 phases. Critical path: `0 → 1 → 2 → 3 → (4+5+6) → (7+8) → 9` (7 serial blocks). **Phases 2 and 3 are serialized** (previously parallel) — both modify `app.ex` wizard-dispatch paths during the top-level wizard-state migration surfaced during Phase 0 discuss-phase.

- **Phase 0** — Cross-cutting extractions: `Theme.from_state/1` + `Screens.Domain.get/2`; touches all 9 screens + chrome + size_gate + app modal (AUDIT-13 exception (a)).
- **Phases 1–9** — One-per-screen audits (Login → Register → Verify → MainMenu → BoardList → ThreadList → NewThread → PostComposer → PostReader). Scope fence `AUDIT-13` enforced with documented exceptions: Phase 2 may touch `app.ex:53-56, 354-361` for Register wizard-state migration (exception (b)); Phase 3 may touch `app.ex:74-75` for Verify wizard-state migration (exception (c)).

## Accumulated Context

### Inherited decisions locked at workstream creation

- `Foglet.Config` render-path reads are safe (ETS read-through cached) — no pre-audit gap closure; document in each phase CONTEXT.
- `Input.TextInput` adoption in Login (and inherited by Phases 2 Register + 7 NewThread) locked by user with accepted `█`-cursor visual drift.
- Verify 6-char `[ABC___]` buffer stays hand-rolled (07 D-02 inheritance).
- Spinner adoption evaluated per screen against anti-affordance rule (no spinner on instant ops).
- Phrasing normalization is scoped to each audited screen's own file — no cross-screen sweep commit.

### Decisions locked during Phase 0 discuss-phase (amendment 2026-04-21)

- **Top-level wizard-state migration IN scope** — `state.register_wizard → state.screen_state[:register]` in Phase 2; `state.verify_state → state.screen_state[:verify]` in Phase 3. User chose consistency over restraint; overrides research recommendation to defer.
- **Canonical 10-section screen layout (AUDIT-18)** codified as an audit-wide rubric item; deviations require moduledoc note (MainMenu MENU-05 intentional-stateless; PostReader READER-07 load-absorb pattern + render_cache plumbing).
- **`init_screen_state/1` adoption (AUDIT-19)** codified — every screen exposes it or documents "intentionally stateless".
- **Phase 2 and Phase 3 serialized** (previously parallel) — both touch `app.ex` wizard-dispatch paths.
- **AUDIT-13 scope fence now has three documented exceptions** — Phase 0 (cross-cutting), Phase 2 (Register wizard-state), Phase 3 (Verify wizard-state).
- **Phase 0 plan structure: three plans** — 00-01 Theme helper + tests; 00-02 Domain module + tests; 00-03 Call-site migration (11 files). Standard authoring order (implementation, then tests).

### Decisions locked from `phase-03-polish` (inherited, not re-decided)

- `Foglet.TUI.Theme` struct is the sole color routing path (D-07/D-09).
- All widgets accept `theme:` as explicit keyword arg (D-13).
- Stateful widgets expose `init/1 + handle_event/2 + render/2` (D-14); stateless widgets expose `render/*` only (D-16).
- Widget directory convention: `lib/foglet_bbs/tui/widgets/<bucket>/<name>.ex` (D-10).
- No hardcoded color atoms — every color via a Theme slot.

### Pending Todos

None yet.

### Blockers/Concerns

None yet. Three correctness items are **scoped into phases** (not blockers):

- `thread_list.ex:136,140` `function_exported?/3` missing `Code.ensure_loaded/1` → Phase 6.
- Dead-code audit of public `load_*`/`flush_*` hooks → Phases 5, 6, 9.
- `with`-chain refactors for nested `case {:ok,_}|{:error,_}` → Phases 1 (Login), 2 (Register), 8 (PostComposer).

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| Constants | FUT-01: `Foglet.TUI.Constants` shared module for `{80, 24}` | Deferred | 2026-04-21 (workstream create) |
| Behaviour | FUT-02: `Foglet.TUI.Screens` behaviour with `init/render/handle_key` callbacks | Deferred | 2026-04-21 |
| Widget | FUT-03: Extend `Input.TextInput` with `█`-block cursor style | Deferred | 2026-04-21 |
| Pagination | FUT-04: PostReader pagination (currently loads all posts up-front) | Deferred | 2026-04-21 |
| Cosmetic | FUT-05: Normalize `{:terminate, :user_quit}` vs `{:terminate, :logout}` | Deferred | 2026-04-21 |

## Session Continuity

Last session: 2026-04-22T01:52:51.588Z
Stopped at: Phase 5 context gathered
Resume file: .planning/workstreams/phase-03-screen-audit/phases/05-boardlist/05-CONTEXT.md
