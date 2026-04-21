---
gsd_state_version: 1.0
milestone: v1.0.1
milestone_name: milestone
status: executing
stopped_at: Phase 8 context gathered
last_updated: "2026-04-21T01:23:23.904Z"
last_activity: 2026-04-20
progress:
  total_phases: 8
  completed_phases: 6
  total_plans: 23
  completed_plans: 22
  percent: 96
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

Phase: 07 (migrate-hand-rolled-ui-components-to-raxol-widgets) — EXECUTING
Plan: 1 of 3
**Phase:** 07 of 6 (migrate hand rolled ui components to raxol widgets)
**Plan:** Not started
**Status:** Executing Phase 07
**Last activity:** 2026-04-20

## Roadmap Summary

| Phase | Name | REQs | Depends on |
|-------|------|------|------------|
| 1 | Widget foundation + theme + screen chrome | WIDGET-01, WIDGET-02, THEME-01, FRAME-01, FRAME-02, LIST-04 | — |
| 2 | Markdown rendering correctness | RENDER-01, RENDER-02 | Phase 1 |
| 3 | Read-pointer correctness + thread-row enrichment | LIST-01, LIST-02, LIST-03 | Phase 1, Phase 2 |
| 4 | Composer & thread creation end-to-end | COMPOSE-01, COMPOSE-02, COMPOSE-03 | Phase 1 |
| 5 | Terminal size gate | FRAME-03 | Phase 1 |
| 6 | Email verification toggle + resend | VERIFY-01, VERIFY-02 | Phase 1 |
| 7 | Migrate hand-rolled UI components to Raxol widgets | D-01..D-17 (phase-level) | Phase 6 |
| 8 | Build local widget library from Raxol primitives | TBD | Phase 7 |

**Total plans:** TBD (filled in as each phase is planned)

## Milestone Scope (from user)

Ten items shaped into 17 requirements across 7 categories (see REQUIREMENTS.md):

1. Markdown → ANSI rendering is broken (posts show raw markdown) → RENDER-01, RENDER-02
2. Layout inconsistent across screens — StatusBar + chrome unified → FRAME-01, FRAME-02
3. Seeded threads in General don't render properly → covered by RENDER-01 acceptance against seeded data (seed fixtures themselves landed in commit `9578faf`)
4. Boards list stuck unread count → LIST-01, LIST-02
5. Thread list rows need creator + time-ago + post count → LIST-03
6. Theme application inconsistent → THEME-01
7. Composer has no title field → COMPOSE-01, COMPOSE-03
8. Thin reusable-widget layer on top of Raxol → WIDGET-01, WIDGET-02, LIST-04
9. Minimum terminal dimensions gate → FRAME-03
10. Email verification toggle + resend (SEED-002) → VERIFY-01, VERIFY-02
11. Wire thread creation + post reply end-to-end → COMPOSE-01, COMPOSE-02

## Accumulated Context

### Decisions

Inherited from main workstream (see `.planning/PROJECT.md` Key Decisions).

Locked for this milestone (see REQUIREMENTS.md "Locked Decisions"):

- Retroactive bypass on verification toggle-off: existing `confirmed_at: nil` users gain access on next login
- Widget style: function-form only (Raxol modern block-macro DSL)
- Markdown rendering: view-time with per-screen memoization (no pre-rendering to DB)
- Raxol `ThemeManager`: rejected; use `Foglet.TUI.Theme` struct

### Open Decisions (per-phase)

None. All open decisions resolved through Phase 5.

### Blockers/Concerns

None. Research is HIGH confidence; zero new dependencies required.

### Reference Seeds

- SEED-002 (email-verification-ux) — folded into VERIFY-01, VERIFY-02.

### Roadmap Evolution

- Phase 7 added: Migrate hand-rolled UI components to Raxol widgets
- Phase 8 added (2026-04-20): Build local widget library from Raxol primitives — proactively wrap the Raxol primitives we'll want for upcoming screens and explore underused idioms (e.g. `spacer()` vs `justify_*`). Source: `docs/raxol/getting-started/WIDGET_GALLERY.md`.

## Session Continuity

Last session: 2026-04-21T01:23:23.893Z

- Plan 02-01 (Wave 1): `Post.MarkdownBody` — newline-grouping via `Enum.chunk_by/2`, theme-driven style mapping (D-06), + tests
- Plan 02-02 (Wave 2): `Post.PostCard` — author header (`By @handle · 2h ago`) + themed divider + delegated `MarkdownBody` body, + tests
- Plan 02-03 (Wave 3): PostReader integration — `PostCard.render_from_tuples/5`, j/k within-post scroll (D-03, D-04, D-05), `render_cache` keyed on `{post.id, width}` in `screen_state[:post_reader]`, legacy `render_markdown_tuples/2` + `render_post_items/4` + `get_post_author/1` deleted, + tests including seeded-thread UAT smoke

Stopped at: Phase 8 context gathered
Resume file: .planning/workstreams/phase-03-polish/phases/08-build-local-widget-library-from-raxol-primitives/08-CONTEXT.md
