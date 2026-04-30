---
gsd_state_version: 1.0
milestone: v2.1
milestone_name: milestone
status: executing
stopped_at: Phase 46 context gathered (assumptions mode)
last_updated: "2026-04-30T01:59:55.997Z"
last_activity: 2026-04-30 -- Phase 46 execution started
progress:
  total_phases: 6
  completed_phases: 5
  total_plans: 26
  completed_plans: 22
  percent: 85
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-29)

**Core value:** A user can SSH into a living, reliable BBS and participate in conversations through a terminal-native experience that feels like arriving somewhere.
**Current focus:** Phase 46 — Domain Cleanup and Final Quality Gate

## Current Position

Phase: 46 (Domain Cleanup and Final Quality Gate) — EXECUTING
Plan: 1 of 4
Status: Executing Phase 46
Last activity: 2026-04-30 -- Phase 46 execution started

Progress: [█████████░] 86%

## Performance Metrics

**Velocity:**

- Total plans completed: 13
- Average duration: N/A
- Total execution time: 0.0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 41-46 | TBD | TBD | N/A |
| 41 | 4 | - | - |
| 42 | 5 | - | - |

**Recent Trend:**

- Last 5 plans: none
- Trend: N/A

| Phase 42 P01 | 9min | 3 tasks | 4 files |
| Phase 42 P42-02 | 7min | 3 tasks | 4 files |
| Phase 42 P42-03 | 8min | 3 tasks | 5 files |
| Phase 42 P42-04 | 8min | 3 tasks | 4 files |
| Phase 42 P42-05 | 7min | 3 tasks | 5 files |
| Phase 44 P44-01 | 5min | 2 tasks | 4 files |
| Phase 44 P44-02 | 10min | 4 tasks | 4 files |
| Phase 44 P44-04 | 4min | 3 tasks | 3 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table. Recent decisions affecting current work:

- v2.1 addresses every item in `.planning/codebase/CONCERNS.md` through implementation, documentation, tests, or a final verification disposition.
- Phase numbering continues from v2.0, starting at Phase 41.
- Research is intentionally skipped for v2.1 because this is internal hardening and cleanup rather than new feature discovery.
- Roadmap phases are derived only from v2.1 requirements in `.planning/REQUIREMENTS.md`.
- [Phase 42]: Routing owns route encoding, screen-key derivation, context construction, screen module resolution, reducer dispatch, and render dispatch.
- [Phase 42]: Foglet.TUI.App keeps public route helper delegators only for render fixtures and screen-focused test boundaries; implementation lives in Routing.
- [Phase 42]: Modal owns overlay rendering, modal key precedence, confirm callbacks, dismissal, form event routing, and generic form-submit failure visibility.
- [Phase 42]: Foglet.TUI.App delegates modal-owned behavior while keeping high-level App update messages and Raxol callbacks.
- [Phase 42]: Routing interprets reducer-returned effects through App.Effects so App no longer exposes public effect helper functions.
- [Phase 42]: Effects owns interpretation of current Foglet.TUI.Effect values while App owns when shell messages enter effect interpretation.
- [Phase 42]: Subscriptions owns heartbeat gating, chrome clock interval wiring, PubSubForwarder wiring, InitialRouteEnterForwarder wiring, user topics, screen-declared topics, and dynamic refresh diffing.
- [Phase 42]: Foglet.TUI.App retains only the Raxol callback integration points for subscribe/1 and post-update refresh timing.
- [Phase 42]: Foglet.TUI.App remains a public fixture boundary for route state helpers, but effect interpretation tests now target Foglet.TUI.App.Effects directly. — Phase 42 finalization kept App as the Raxol shell while preserving helper-owned effect behavior coverage.
- [Phase 42]: App runtime tests use structural state, command, modal, and SizeGate element assertions instead of pure rendered-text presence checks. — This preserves behavior coverage while following AGENTS.md testing guidance.
- [Phase 44]: Plan 44-01 reader windows use message_number cursors scoped by thread_id rather than offsets or inserted timestamps. — message_number is the stable reader sequence and preserves continuity across tombstones.
- [Phase 44]: Plan 44-01 reader/history query paths remain tombstone-capable; no QueryHelpers.not_deleted/1 filtering was added. — Soft-deleted posts keep historical message numbers and must remain visible to reader/history consumers.
- [Phase 44]: PostReader keeps State.posts as the active bounded window while storing reader-window cursor metadata beside it. — Preserves existing render/read-pointer compatibility while satisfying bounded-state POST-01.
- [Phase 44]: Adjacent-window navigation uses pending_window_direction for boundary landing. — The reducer can deterministically select index 0 for next windows and the final post for previous windows after async task results.
- [Phase 44]: Thread activity reloads use reader windows anchored around the selected post message number. — This preserves the current reader position when the refreshed bounded window still contains the selected post.
- [Phase 44]: Reader/history tests assert soft-deleted post rows and original message numbers without checking rendered tombstone text.
- [Phase 44]: Thread list tests cover list_threads/1, list_threads/2, and nil-user delegation through the shared not-deleted filter.
- [Phase 44]: Board summary tests cover single and batch unread count APIs plus directory last-post summaries at the context boundary.

### Pending Todos

None yet.

### Blockers/Concerns

- Keep the milestone bounded to stability and maintenance hardening; do not add new end-user product surfaces.
- Preserve SSH-first TUI behavior while changing runtime, screen, and lifecycle internals.

## Deferred Items

Previous milestone carried forward 16 acknowledged debug/quick/seed items. They remain outside v2.1 unless represented by `.planning/codebase/CONCERNS.md`; see the previous STATE history and `.planning/MILESTONES.md` for the archive summary.

## Session Continuity

Last session: 2026-04-30T01:32:54.908Z
Stopped at: Phase 46 context gathered (assumptions mode)
Resume file: .planning/phases/46-domain-cleanup-and-final-quality-gate/46-CONTEXT.md
