# Foglet BBS

## What This Is

Foglet BBS is an SSH-first bulletin board system built as a Phoenix/Elixir application. Users connect through a terminal UI over SSH to create accounts, browse boards, read threads, write posts, manage account preferences, participate through lightweight oneliners, and use role-appropriate moderation/sysop workflows without leaving the terminal. The Phoenix endpoint exists for operations and future structured clients, not as an end-user web UI.

## Core Value

A user can SSH into a living, reliable BBS and participate in conversations through a terminal-native experience that feels like arriving somewhere.

## Current State

**Shipped version:** v1.1 Operations Surfaces & Invites on 2026-04-24.

Foglet now has terminal-native Account, Moderation, and Sysop surfaces; actor-aware authorization; persisted single-use invites; invite-only registration redemption; shared INVITES tabs; account profile/preferences with live session refresh; sysop config and board/category operations; preference-aware chrome time rendering; persistent oneliners; and moderation hide/audit workflows.

The chrome clock intentionally displays time only. It honors the user's timezone and 12h/24h preference; date display is not part of the accepted v1.1 behavior.

## Next Milestone Goals

No next milestone is defined yet. Use `$gsd-new-milestone` to gather fresh requirements and build the next roadmap.

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
- [x] Read-only Account, Moderation, and Sysop shell screens exist with role-gated main-menu entries, milestone tab sets, placeholder/loading/error states, and a shared `InvitesSurface` primitive - v1.1 Phase 0
- [x] Operator actions are actor-aware and scope-aware, with `:site` and `{:board, board_id}` scope shapes preserved for future board-scoped moderation - v1.1 Phase 1
- [x] Shared modal form infrastructure supports typed terminal forms used by sysop/account workflows - v1.1 Phase 1.1
- [x] Sysops can manage typed site policy, invite controls, board/category lifecycle, and system details from the TUI - v1.1 Phase 2
- [x] Persisted single-use invite codes support authorized generation, status review, unused revocation, and transactional `invite_only` registration redemption - v1.1 Phase 3
- [x] Invite workflows are surfaced through a shared INVITES tab according to runtime generation policy - v1.1 Phase 4
- [x] Users can manage private profile and presentation settings from Account and see saved changes reflected without reconnecting - v1.1 Phase 5
- [x] Main-menu chrome renders preference-aware time and refreshes without reconnecting - v1.1 Phase 6
- [x] Main menu includes persistent bounded oneliners with quick posting - v1.1 Phase 7
- [x] Moderation workspace uses real scope-aware data and can hide oneliners through audited moderation tooling - v1.1 Phase 8

### Active

- [ ] Define the next milestone requirements.

### Out of Scope

- General-purpose social network features - Foglet is intentionally a BBS with boards, threads, chat, and sysop-controlled community structure
- End-user web UI - the browser-facing Phoenix surface is for LiveDashboard and operations; the product experience is terminal-first
- Telnet as an initial interface - SSH is the primary supported transport; telnet is a possible future compatibility layer
- Client-side JavaScript app or asset pipeline - there is no current need for a SPA or web assets because the UI is rendered through Raxol
- Multi-node correctness as an early requirement - the architecture leaves room for clustering, but current correctness depends on local supervisors, registries, ETS, and Postgres
- Email-first engagement - email notifications and digests are later opt-in reach features, not the core BBS loop

## Context

Foglet is a brownfield Phoenix project that has advanced beyond initial scaffolding. The codebase is a single OTP application on the BEAM, with Postgres as the authoritative data store and ETS/Phoenix PubSub used for ephemeral state, runtime config caching, and live event routing.

The primary interface is an SSH terminal UI. Erlang's built-in `:ssh` daemon accepts connections, `Foglet.SSH.CLIHandler` handles SSH channel lifecycle events, and Raxol owns the terminal rendering lifecycle. The TUI is screen-oriented: `Foglet.TUI.App` owns routing, modal handling, PubSub wiring, task command dispatch, and active screen state; individual screen modules implement the `Foglet.TUI.Screen` behavior.

The domain core is organized as Phoenix-style context modules backed by Ecto schemas. Accounts, boards, threads, posts, configuration, oneliners, moderation, markdown rendering, and sessions have concrete modules and tests. Board servers are supervised per active board and serialize message-number allocation so the per-board numbering model stays deterministic under concurrency.

## Constraints

- **Tech stack**: Elixir 1.19.5, Erlang/OTP 28.3.1, Phoenix 1.8.5, Ecto, PostgreSQL, Bandit, and vendored Raxol - existing project choices and `.tool-versions` pin the runtime
- **Interface**: SSH terminal UI first - the product should optimize for terminal-native BBS workflows, not browser conventions
- **Web surface**: Phoenix endpoint is operational infrastructure - avoid adding end-user web routes unless a later decision explicitly changes product direction
- **Persistence**: Postgres is authoritative for domain state - ETS and process state must remain reconstructable after restart
- **Concurrency**: OTP processes own live coordination - use supervisors, registries, PubSub, and GenServers rather than ad hoc shared mutable state
- **Testing**: Process tests should use supervised processes and deterministic synchronization - avoid sleeps and fragile liveness checks
- **Security**: SSH auth, password hashing, account deletion, rate limiting, invite workflows, moderation actions, and runtime config changes need conservative handling
- **Surface reuse**: Account, moderation, and sysop screens should share invite-tab primitives rather than forking near-identical implementations
- **Authorization**: Moderator and sysop UI must align with role checks and future board-scoped moderation instead of assuming every moderator is global forever

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Build Foglet as an SSH-first BBS rather than a web forum | The desired experience is terminal-native and closer to classic BBS interaction than browser-first forum software | Good |
| Use Phoenix as the application foundation even without an end-user web UI | Phoenix supplies endpoint, PubSub, Ecto conventions, LiveDashboard, and operational structure while the primary UI remains SSH | Good |
| Use Raxol for TUI rendering and lifecycle | The project has an existing vendored TUI framework with screen, widget, runtime, and SSH integration patterns | Good |
| Keep SSH and Phoenix interfaces as peers over shared domain/session layers | This prevents the terminal experience from being a wrapper around a web UI and leaves room for future structured clients | Good |
| Store domain truth in Postgres and ephemeral truth in ETS/processes | Durable BBS data needs database consistency; presence, caches, and live UI state can be rebuilt | Good |
| Allocate per-board message numbers through board server processes | A single writer per board gives deterministic numbering without relying on per-board database sequence gymnastics | Good |
| Enforce one active session per user through the session supervisor and registry | BBS presence and terminal state are easier to reason about when a user has a single canonical session | Good |
| Keep sysop administration inside the TUI for day-to-day operations | A sysop should be able to operate the BBS from the same terminal experience users inhabit | Good |
| Build a reusable invite-management surface embedded in account, moderation, and sysop screens | Invite generation rules vary by runtime config, but workflows and data model should stay consistent across roles | Good |
| Store per-user time rendering preferences alongside other presentation preferences | Timezone and 12h/24h display are user-specific UI concerns that drive chrome and future timestamp rendering | Good |
| Render chrome time without date | The user prefers time-only chrome; date was intentionally removed from the accepted v1.1 behavior | Good |

## Evolution

This document evolves at phase transitions and milestone boundaries.

---
*Last updated: 2026-04-24 after v1.1 milestone completion*
