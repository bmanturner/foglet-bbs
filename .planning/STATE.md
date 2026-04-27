---
gsd_state_version: 1.0
milestone: v1.4
milestone_name: milestone
status: executing
stopped_at: Phase 29 context gathered (assumptions mode)
last_updated: "2026-04-27T20:31:53.684Z"
last_activity: 2026-04-27 -- Phase 29 planning complete
progress:
  total_phases: 8
  completed_phases: 3
  total_plans: 21
  completed_plans: 17
  percent: 81
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-26)

**Core value:** A user can SSH into a living, reliable BBS and participate in conversations through a terminal-native experience that feels like arriving somewhere.
**Current focus:** Phase 28 — modal-form-substrate

## Current Position

Phase: 28 (modal-form-substrate) — IMPLEMENTATION COMPLETE, UAT PENDING
Plan: 7 of 7 (all plans done; 5 review fixes applied)
Status: Ready to execute
Last activity: 2026-04-27 -- Phase 29 planning complete

## Performance Metrics

**Velocity:**

- Total plans completed: 84 from shipped v1.1; 26 in v1.2; 48 in v1.3
- Average duration: Not measured for v1.4 yet
- Total execution time: Not measured for v1.4 yet

**By Phase (v1.4):**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 26. Layout & Width Foundations | TBD | - | - |
| 27. Cursor & Breadcrumb Polish | TBD | - | - |
| 28. Modal.Form Substrate | TBD | - | - |
| 29. Sysop Tab Lifecycle & Bodies | TBD | - | - |
| 30. Account Workflow | TBD | - | - |
| 31. Auth Flow | TBD | - | - |
| 32. Main Menu Chrome Polish | TBD | - | - |
| 33. Composer Wrap & Boards Interaction | TBD | - | - |

**Recent Trend:**

- Last 5 plans: Not measured for v1.4 yet
- Trend: Not established

| Phase 15 P02 | 5min | 3 tasks | 5 files |
| Phase 26 P01 | 9min | 2 tasks | 6 files |
| Phase 26 P02 | 6min | 3 tasks | 10 files |
| Phase 26 P03 | 6min | 2 tasks | 5 files |
| Phase 26 P04 | 6min | 3 tasks | 7 files |

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
- [v1.4]: `ISSUES.md` is the milestone PRD — surfaced bugs from human SSH/TUI verification of v1.3.
- [v1.4]: Stabilization milestone, not feature expansion. SEED-001 and SEED-002 remain dormant.
- [v1.4]: Two ISSUES.md items resolved before milestone start and struck from scope: Boards-screen freeze on board select, and Main Menu Up/Down keys being inert.
- [Phase 26 Plan 01]: Table width budgets are drawable content widths; callers subtract screen frame borders before passing `:width`.
- [Phase 26 Plan 01]: Foglet resolves table column widths before Raxol rendering because Raxol adds separator padding per cell.
- [Phase 26 Plan 01]: No-space wrapping and table elision use `TextWidth` grapheme-aware helpers rather than byte or character slicing.
- [Phase ?]: [Phase 26 Plan 02]: Tabbed operator screens pass drawable content width, not raw terminal columns, into Tabs.render/2.
- [Phase ?]: [Phase 26 Plan 02]: Moderation compact height prioritizes ConsoleTable content over KvGrid summaries.
- [Phase ?]: [Phase 26 Plan 02]: Shared invite tables use ratio columns resolved against a conservative drawable width when callers omit :width.
- [Phase 26]: BoardTree windowing derives the focused row from Raxol tree cursor and visible nodes without mutating tree state.
- [Phase 26]: Boards screen passes drawable content width and a compact logical tree-row budget into BoardTree.
- [Phase 26]: Compact Boards rendering reserves detail, feedback, and inspector rows only when they fit, with the tree winning at small heights.
- [Phase 26]: Preserve consecutive newline tuples in Foglet.Markdown.render/1; MarkdownBody owns clamping paragraph separators to one blank visible row. — Required so shared post rendering can distinguish soft line breaks from paragraph separators.
- [Phase 26]: Keep list-item rendering to one logical line per item by stripping MDEx list container structural newlines. — Preserving paragraph newline tuples exposed MDEx list tag whitespace that would otherwise create blank rows between bullets.
- [Phase 26]: Leave Phase 26 human SSH verification pending when real fixed-size terminal checks are not run in the execution session. — Human terminal-fit acceptance requires real SSH visual verification at exact terminal dimensions.

### Pending Todos

None yet.

### Blockers/Concerns

No active blockers. Phase planning should preserve delivery honesty, context-level enforcement, and break-glass operator paths where the roadmap calls for them.

- Phase 26 manual SSH UAT remains pending at fixed terminal sizes; rtk mix precommit is blocked by pre-existing out-of-scope Dialyzer warnings documented in 26-04-SUMMARY.md.

### Quick Tasks Completed

| # | Description | Date | Commit | Status | Directory |
|---|-------------|------|--------|--------|-----------|
| 260426-g0k | There is an issue with text input. If I type five characters and backspace to erase the whole string, the first character is always present and impossible to replace, and if I begin typing more characters, that first character gets pushed to the right by the inserted characters | 2026-04-26 | 8b9c3f3 | Verified | [260426-g0k-there-is-an-issue-with-text-input-if-i-t](./quick/260426-g0k-there-is-an-issue-with-text-input-if-i-t/) |
| 260426-gnq | Put Chrome V2 breadcrumb/status and command hints on the screen border rows | 2026-04-26 | ae623da | Verified | [260426-gnq-the-recent-milestone-was-supposed-to-cha](./quick/260426-gnq-the-recent-milestone-was-supposed-to-cha/) |
| 260426-hbu | Add a cursor icon to active text inputs | 2026-04-26 | 9a9fedc | Verified | [260426-hbu-we-need-a-cursor-icon-to-appear-on-the-t](./quick/260426-hbu-we-need-a-cursor-icon-to-appear-on-the-t/) |
| 260426-jdz | Fix board breadcrumb struct access view error | 2026-04-26 | c357fc6 | Verified | [260426-jdz-gsd-quick-full-id-56e39788-5cba-41d3-abb](./quick/260426-jdz-gsd-quick-full-id-56e39788-5cba-41d3-abb/) |
| 260426-jbn | Fix one-connection-at-a-time bottleneck in SSH/Raxol stack (filed raxol#228, #229) | 2026-04-26 | ccbeef4 | Verified | [260426-jbn-the-application-only-allows-one-active-c](./quick/260426-jbn-the-application-only-allows-one-active-c/) |

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

Last session: 2026-04-27T17:42:24.987Z
Stopped at: Phase 29 context gathered (assumptions mode)
Resume file: .planning/phases/29-sysop-tab-lifecycle-bodies/29-CONTEXT.md
