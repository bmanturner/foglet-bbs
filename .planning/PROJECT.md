# Foglet BBS

## What This Is

Foglet BBS is an SSH-first bulletin board system built as a Phoenix/Elixir application. Users connect through a terminal UI over SSH to create accounts, browse boards, read threads, write posts, and eventually use presence, chat, moderation, and sysop administration features. The Phoenix endpoint exists for operations and future structured clients, not as an end-user web UI.

## Core Value

A user can SSH into a living, reliable BBS and participate in conversations through a terminal-native experience that feels like arriving somewhere.

## Requirements

### Validated

- [x] Phoenix, Ecto, PostgreSQL, and OTP supervision are wired as the application foundation - existing code
- [x] Accounts support handles, emails, password authentication, roles, tokens, SSH keys, and sysop Mix tasks - existing code
- [x] Boards, categories, threads, posts, post edits, upvotes, subscriptions, and read pointers exist as persisted domain concepts - existing code
- [x] Per-board message numbers are allocated through supervised board server processes with transactional persistence - existing code
- [x] SSH daemon integration accepts terminal connections and routes them into session/TUI lifecycle code - existing code
- [x] Session processes track authenticated users, guest sessions, terminal size, TUI pid, and one-session-per-user replacement behavior - existing code
- [x] Raxol drives the TUI runtime with screens for login, registration, verification, main menu, board list, thread list, post reader, post composer, and new thread composition - existing code
- [x] Reusable themed TUI widgets cover chrome, lists, inputs, display elements, modals, post rendering, composition, and progress states - existing code
- [x] Runtime configuration is persisted in the database and cached through a typed ETS-backed config layer - existing code
- [x] Markdown rendering, user deletion anonymization, deleted-post preservation, SSH rate limiting, and broad SSH/TUI test coverage are in place - existing code

### Active

- [ ] Make the SSH/TUI BBS flow feel complete end to end: connect, authenticate, browse boards, read threads, compose posts, and return later with read state intact
- [ ] Preserve terminal-first ergonomics while continuing to improve screen state, widget consistency, and Raxol integration
- [ ] Build the community-presence layer: online users, last callers, login sequence, banners, news, preferences, and CP437-aware ANSI rendering
- [ ] Add real-time interaction through chat, DMs, mentions, notifications, and PubSub-backed live updates
- [ ] Add moderation and sysop operations inside the TUI so a BBS can be run day to day without leaving the terminal
- [ ] Add search, oneliners, profiles, upvotes, and polish that make the system feel complete for a solo user and small community
- [ ] Keep operational quality high through precommit checks, tests, security scanning, typed config, and deterministic process supervision

### Out of Scope

- General-purpose social network features - Foglet is intentionally a BBS with boards, threads, chat, and sysop-controlled community structure
- End-user web UI - the browser-facing Phoenix surface is for LiveDashboard and operations; the product experience is terminal-first
- Telnet as an initial interface - SSH is the primary supported transport; telnet is a possible future compatibility layer
- Client-side JavaScript app or asset pipeline - there is no current need for a SPA or web assets because the UI is rendered through Raxol
- Multi-node correctness as an early requirement - the architecture leaves room for clustering, but current correctness depends on local supervisors, registries, ETS, and Postgres
- Email-first engagement - email notifications and digests are later opt-in reach features, not the core BBS loop

## Context

Foglet is a brownfield Phoenix project that has already advanced beyond initial scaffolding. The codebase is a single OTP application on the BEAM, with Postgres as the authoritative data store and ETS/Phoenix PubSub used for ephemeral state, runtime config caching, and live event routing.

The primary interface is an SSH terminal UI. Erlang's built-in `:ssh` daemon accepts connections, `Foglet.SSH.CLIHandler` handles SSH channel lifecycle events, and Raxol owns the terminal rendering lifecycle. The TUI is intentionally screen-oriented: `Foglet.TUI.App` owns routing, modal handling, PubSub wiring, task command dispatch, and the active screen state; individual screen modules implement the `Foglet.TUI.Screen` behavior.

The domain core is organized as Phoenix-style context modules backed by Ecto schemas. Accounts, boards, threads, posts, configuration, markdown rendering, and sessions already have concrete modules and tests. Board servers are supervised per active board and serialize message-number allocation so the per-board numbering model stays deterministic under concurrency.

Project planning history lives in `.planning/`, including a codebase map, stack analysis, quick-task summaries, and current state. The current planning cycle has focused on tightening SSH handling, TUI domain injection, state structs, typed configuration, post deletion/anonymization semantics, and test coverage.

## Constraints

- **Tech stack**: Elixir 1.19.5, Erlang/OTP 28.3.1, Phoenix 1.8.5, Ecto, PostgreSQL, Bandit, and vendored Raxol - existing project choices and `.tool-versions` pin the runtime
- **Interface**: SSH terminal UI first - the product should optimize for terminal-native BBS workflows, not browser conventions
- **Web surface**: Phoenix endpoint is operational infrastructure - avoid adding end-user web routes unless a later decision explicitly changes product direction
- **Persistence**: Postgres is authoritative for domain state - ETS and process state must remain reconstructable after restart
- **Concurrency**: OTP processes own live coordination - use supervisors, registries, PubSub, and GenServers rather than ad hoc shared mutable state
- **Testing**: Process tests should use supervised processes and deterministic synchronization - avoid sleeps and fragile liveness checks
- **Security**: SSH auth, password hashing, account deletion, rate limiting, and runtime config changes need conservative handling - this is an internet-facing service
- **Dependencies**: Prefer project-standard libraries and Elixir/Phoenix/Raxol patterns - use `Req` for HTTP if needed and avoid adding date/time or HTTP client dependencies without a deliberate decision

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Build Foglet as an SSH-first BBS rather than a web forum | The desired experience is terminal-native and closer to classic BBS interaction than browser-first forum software | - Pending |
| Use Phoenix as the application foundation even without an end-user web UI | Phoenix supplies endpoint, PubSub, Ecto conventions, LiveDashboard, and operational structure while the primary UI remains SSH | - Pending |
| Use Raxol for TUI rendering and lifecycle | The project has an existing vendored TUI framework with screen, widget, runtime, and SSH integration patterns | - Pending |
| Keep SSH and Phoenix interfaces as peers over shared domain/session layers | This prevents the terminal experience from being a wrapper around a web UI and leaves room for future structured clients | - Pending |
| Store domain truth in Postgres and ephemeral truth in ETS/processes | Durable BBS data needs database consistency; presence, caches, and live UI state can be rebuilt | - Pending |
| Allocate per-board message numbers through board server processes | A single writer per board gives deterministic numbering without relying on per-board database sequence gymnastics | - Pending |
| Enforce one active session per user through the session supervisor and registry | BBS presence and terminal state are easier to reason about when a user has a single canonical session | - Pending |
| Keep sysop administration inside the TUI for day-to-day operations | A sysop should be able to operate the BBS from the same terminal experience users inhabit | - Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `$gsd-transition`):
1. Requirements invalidated? Move to Out of Scope with reason.
2. Requirements validated? Move to Validated with phase reference.
3. New requirements emerged? Add to Active.
4. Decisions to log? Add to Key Decisions.
5. "What This Is" still accurate? Update if drifted.

**After each milestone** (via `$gsd-complete-milestone`):
1. Full review of all sections.
2. Core Value check: still the right priority?
3. Audit Out of Scope: reasons still valid?
4. Update Context with current state.

---
*Last updated: 2026-04-22 after initialization*
