# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-18)

**Core value:** Two users SSHing into the same BBS and feeling like they're actually present together — boards, unread counts, who's online, real-time chat, and the sense of place that makes a BBS a BBS.
**Current focus:** Phase 1 — Accounts & Identity

## Current Position

Phase: 1 of 14 (Accounts & Identity)
Plan: 0 of TBD in current phase
Status: Ready to plan
Last activity: 2026-04-18 — Phase 1 context gathered; 4 decision areas discussed

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**
- Total plans completed: 0
- Average duration: —
- Total execution time: —

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**
- Last 5 plans: —
- Trend: —

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- M0: Stack locked — Elixir 1.19.5 / OTP 28.3.1 / Phoenix 1.8 / PostgreSQL; `:ssh` directly; Oban; Argon2
- M0: SSH-only user interface — no web UI for users; terminal-first is the product identity
- M0: Board server owns message-number sequence (GenServer per board, DynamicSupervisor)
- M0: One session per user with replace-old-session-with-notify semantics

### Pending Todos

None yet.

### Blockers/Concerns

- Registration mode (open / invite-only / sysop-approved) not yet decided — will need resolution before Phase 3 (SSH guest flow, SSH-04)
- License choice (MIT vs Apache 2.0) deferred to Phase 12

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| *(none)* | | | |

## Session Continuity

Last session: 2026-04-18
Stopped at: Phase 1 context gathered — ready to plan Phase 1
Resume file: .planning/phases/01-accounts-and-identity/01-CONTEXT.md
