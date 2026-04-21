---
gsd_state_version: 1.0
workstream: phase-03-screen-audit
milestone: v1.0.2
milestone_name: screen-audit
status: ready_to_plan
last_updated: "2026-04-21T00:00:00.000Z"
last_activity: 2026-04-21
progress:
  total_phases: 10
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
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

**Phase:** Phase 0 of 10 (Cross-cutting extractions — prelude)
**Plan:** —
**Status:** Ready to plan
**Last activity:** 2026-04-21 — ROADMAP.md created; 10 phases locked; 100% requirement coverage.

Progress: [░░░░░░░░░░] 0%

## Roadmap Summary

10 phases. Critical path under parallelism: `0 → 1 → (2+3) → (4+5+6) → (7+8) → 9` (6 serial blocks).

- **Phase 0** — Cross-cutting extractions: `Theme.from_state/1` + `Screens.Domain.get/2`; touches all 9 screens + chrome + size_gate + app modal (prelude exception to `AUDIT-13` scope fence).
- **Phases 1–9** — One-per-screen audits (Login → Register → Verify → MainMenu → BoardList → ThreadList → NewThread → PostComposer → PostReader). Scope fence `AUDIT-13` strictly enforced: each phase diff touches exactly ONE screen file + its test.

## Accumulated Context

### Inherited decisions locked at workstream creation

- `Foglet.Config` render-path reads are safe (ETS read-through cached) — no pre-audit gap closure; document in each phase CONTEXT.
- `Input.TextInput` adoption in Login (and inherited by Phases 2 Register + 7 NewThread) locked by user with accepted `█`-cursor visual drift.
- Verify 6-char `[ABC___]` buffer stays hand-rolled (07 D-02 inheritance).
- Spinner adoption evaluated per screen against anti-affordance rule (no spinner on instant ops).
- Phrasing normalization is scoped to each audited screen's own file — no cross-screen sweep commit.

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

Last session: 2026-04-21 — ROADMAP.md created; requirements traceability complete.
Stopped at: Roadmap approved; Phase 0 ready to plan.
Resume file: None.
