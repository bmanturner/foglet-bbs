# Foglet BBS

## What This Is

Foglet BBS is an SSH-first bulletin board system built as a Phoenix/Elixir application. Users connect through a terminal UI over SSH to create accounts, browse boards, read threads, write posts, manage account preferences, participate through lightweight oneliners, and use role-appropriate moderation/sysop workflows without leaving the terminal. The Phoenix endpoint exists for operations and future structured clients, not as an end-user web UI.

## Core Value

A user can SSH into a living, reliable BBS and participate in conversations through a terminal-native experience that feels like arriving somewhere.

## Current State

**Previous shipped version:** v1.4 Post-Facelift Polish & Bug Fixes completed on 2026-04-28.
**Shipped version:** v2.0 TUI Runtime Shell & Screen Update Loops completed on 2026-04-29.
**Current milestone:** v2.1 Stability & Maintenance Hardening.

Foglet now has terminal-native Account, Moderation, and Sysop workbenches; actor-aware authorization; invite-only registration redemption; account profile/preferences; sysop config and board/category operations; preference-aware chrome time rendering; persistent oneliners; moderation hide/audit workflows; honest SMTP/no-email onboarding and reset behavior; sysop user-status administration; board posting and locked-thread restrictions; Account SSH key management; board subscription management; and a polished Unicode-capable SSH/TUI visual foundation.

The v2.0 architecture migration is complete, and Phase 42 of v2.1 has now removed the bounded legacy screen compatibility surface and extracted cohesive App runtime helpers. `Foglet.TUI.App` remains the Raxol callback shell while `Foglet.TUI.App.Routing`, `Modal`, `Effects`, and `Subscriptions` own route/session/modal coordination, generic effect interpretation, dynamic PubSub forwarding, task dispatch, and screen-local state plumbing. Production screens own their local state transitions through the canonical `init/1`, `update/3`, and `render/2` contract, and modal form submits now flow through explicit `Foglet.TUI.Effect.modal_submit/3` values instead of process-dictionary handoffs.

## Current Milestone: v2.1 Stability & Maintenance Hardening

**Goal:** Turn the post-v2.0 codebase concerns audit into complete, focused cleanup and hardening work without expanding the product surface.

**Target features:**
- Retire the bounded legacy TUI screen compatibility callback surface and migrate remaining helpers/tests to the v2.0 screen contract.
- Replace the process-dictionary modal submit handoff with a first-class effect path routed by the App shell.
- Reduce `Foglet.TUI.App` concentration by extracting narrow routing, modal, subscription, and effect helper modules where they lower maintenance risk.
- Split oversized screen modules along established state/render/reducer boundaries, prioritizing the modules named in the concerns audit.
- Resolve every smaller concern from `.planning/codebase/CONCERNS.md`, including board supervisor confusion, Dialyzer baseline debt, SSH/session fragility, PostReader cache/pagination/purity concerns, and targeted coverage gaps.

## Requirements

### Validated

- [x] Phoenix, Ecto, PostgreSQL, and OTP supervision are wired as the application foundation - existing code.
- [x] Accounts support handles, emails, password authentication, roles, tokens, SSH keys, and sysop Mix tasks - existing code.
- [x] Boards, categories, threads, posts, post edits, upvotes, subscriptions, and read pointers exist as persisted domain concepts - existing code.
- [x] Per-board message numbers are allocated through supervised board server processes with transactional persistence - existing code.
- [x] SSH daemon integration accepts terminal connections and routes them into session/TUI lifecycle code - existing code.
- [x] Session processes track authenticated users, guest sessions, terminal size, TUI pid, and one-session-per-user replacement behavior - existing code.
- [x] Raxol drives the TUI runtime with screens for login, registration, verification, main menu, board list, thread list, post reader, post composer, new thread composition, account, moderation, and sysop - existing code.
- [x] Reusable themed TUI widgets cover chrome, lists, inputs, display elements, modals, post rendering, composition, and progress states - existing code.
- [x] Runtime configuration is persisted in the database and cached through a typed ETS-backed config layer - existing code.
- [x] Main BBS, account, moderation, and sysop screens have local screen modules, many with state structs, but the runtime shell still centrally owns too many screen-specific update clauses - v2.0 input context.
- [x] v2.0 Phase 34 established `Foglet.TUI.Context`, `Foglet.TUI.Effect`, and the `init/1`, `update/3`, `render/2` screen contract with App runtime helpers and focused tests.
- [x] v2.0 Phase 34 proved generic navigation, task, modal, publish/session, terminal-size, and quit effects through App, including task result routing back into screen `update/3`.
- [x] v2.0 Phase 34 documented stateful/stateless screen conventions and preserved existing App/render smoke behavior while deferring full screen-family migration.
- [x] v2.0 Phase 36 migrated BoardList and ThreadList to screen-owned reducers for directory/thread loading, subscription feedback, route-param navigation, PubSub topic derivation, and render fixture ownership.
- [x] v2.0 Phase 40 completed the current screen migration to the mini update-loop model while preserving SSH/TUI behavior, render smoke coverage, breadcrumbs, auth session promotion, dynamic PubSub subscriptions, and precommit gates.
- [x] v2.0 Phase 40 removed production App fallback dispatch to legacy `handle_key/2` and `render/1`, bounded compatibility callbacks in `Foglet.TUI.Screen`, and documented the new screen contract in `lib/foglet_bbs/tui/SCREEN_CONTRACT.md`.
- [x] v2.1 Phase 41 removed the legacy screen compatibility callbacks, migrated tests/smoke helpers to canonical screen setup, introduced explicit modal-submit effects, deleted modal-submit process-dictionary handoffs, and verified direct App-shell modal-submit success/failure coverage.
- [x] v2.1 Phase 42 extracted cohesive App runtime helpers for routing, modal, effects, and subscriptions without moving domain behavior into the TUI shell.

### Active

- [ ] v2.1 decomposes the largest screen modules enough that reducer, state, and render responsibilities are easier to test and change.
- [ ] v2.1 addresses every item in `.planning/codebase/CONCERNS.md` through implementation, documentation, or an explicit verification artifact.

### Out of Scope

- New end-user browser workflows - Foglet remains SSH-first and terminal-native.
- New product features during the hardening milestone - this milestone changes reliability, maintainability, and architecture, not the BBS feature set.
- Replacing Raxol - the new screen contract adapts to the existing Raxol runtime rather than swapping the renderer.
- Rewriting domain contexts - domain mutations remain in `Foglet.*` contexts and are invoked through task effects.
- Email/webhook notification expansion - SEED-001 and SEED-002 remain dormant because this milestone does not add notification or email delivery channels.

## Context

Foglet is a brownfield Phoenix project with the primary product surface served over SSH. `Foglet.SSH.CLIHandler` owns SSH channel lifecycle and starts Raxol. `Foglet.TUI.App` is the Raxol application module that currently normalizes messages, routes keys to screens, interprets returned commands, performs task dispatch, handles task results, manages modals, maintains top-level screen data, subscribes to PubSub, and renders the active screen.

The existing screen modules already implement `Foglet.TUI.Screen` with `render/1`, `handle_key/2`, and optional `init_screen_state/1`. The current behavior still passes the whole App state to screens and often expects screens to mutate `state.screen_state` directly. App also owns clauses like `{:boards_loaded, boards}`, `{:posts_loaded, posts}`, and `{:sysop_users_loaded, result}`, which reach into screen-local state.

The desired v2.0 shape is a runtime shell:

```elixir
screen = current_screen_module(app)
screen_state = current_screen_state(app)
ctx = Foglet.TUI.Context.from_app(app)

{new_screen_state, effects} =
  screen.update(message, screen_state, ctx)

app
|> put_current_screen_state(new_screen_state)
|> run_effects(effects)
```

Widgets already model the smaller local reducer style through `init/1`, `handle_event/2`, and `render/2`. v2.0 lifts that proven pattern to screen modules while keeping process ownership, subscriptions, modal overlay behavior, and command execution in the App shell.

The v2.1 source of truth is `.planning/codebase/CONCERNS.md`, generated after Phase 40. The audit found no active failures after `rtk mix precommit`, but it did identify bounded tech debt, security/runtime hardening opportunities, performance risks, fragile lifecycle paths, and targeted test coverage gaps. This milestone should address all of them rather than selecting only the highest-priority items.

## Constraints

- **Interface**: SSH terminal UI first - do not add browser-facing product flows.
- **Runtime**: Raxol remains the TUI runtime - adapt the screen boundary to Raxol callbacks and command/task delivery.
- **Domain ownership**: Domain behavior stays in `Foglet.*` contexts - screens may request task effects but must not own persistence invariants.
- **Authorization**: Mutations still use context-level policy checks - hidden UI is not authorization.
- **State ownership**: Screen-local state belongs to screen modules - App owns process/session/runtime coordination only.
- **Migration safety**: Full migration should proceed through representative slices and focused verification, but no old-screen fallback path is required.
- **Testing**: Preserve existing render smoke and behavior tests while adding reducer/effect tests; avoid tests that only assert text exists.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Build Foglet as an SSH-first BBS rather than a web forum | The desired experience is terminal-native and closer to classic BBS interaction than browser-first forum software | Good |
| Use Phoenix as the application foundation even without an end-user web UI | Phoenix supplies endpoint, PubSub, Ecto conventions, LiveDashboard, and operational structure while the primary UI remains SSH | Good |
| Use Raxol for TUI rendering and lifecycle | The project has an existing vendored TUI framework with screen, widget, runtime, and SSH integration patterns | Good |
| Store domain truth in Postgres and ephemeral truth in ETS/processes | Durable BBS data needs database consistency; presence, caches, and live UI state can be rebuilt | Good |
| Keep sysop administration inside the TUI for day-to-day operations | A sysop should be able to operate the BBS from the same terminal experience users inhabit | Good |
| Split the TUI facelift into Classic Modern BBS and Operator Console modes | User-facing conversation screens should feel social and placeful, while account/operator work remains compact and administrative | Good |
| Make v2.0 an architecture milestone for screen ownership | `Foglet.TUI.App` had accumulated screen-specific routing, async-result handling, and state mutation; moving those decisions into screens makes future TUI work safer | Phase 40 validated |
| Treat BoardList and ThreadList as screen-owned directory reducers | Board/thread browsing state, async loads, feedback, and route params now flow through local state and screen-tagged effects | Phase 40 validated |
| Bound legacy screen callbacks instead of deleting every helper immediately | Some modules and tests still expose compatibility helpers, but production App dispatch no longer depends on broad App-state callbacks | Phase 40 validated |
| Make v2.1 a complete concerns-audit hardening milestone | The post-v2.0 audit is a finite inventory of maintainability and reliability risks, and the user explicitly wants every concern addressed before moving on | Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `$gsd-transition`):
1. Requirements invalidated? -> Move to Out of Scope with reason
2. Requirements validated? -> Move to Validated with phase reference
3. New requirements emerged? -> Add to Active
4. Decisions to log? -> Add to Key Decisions
5. "What This Is" still accurate? -> Update if drifted

**After each milestone** (via `$gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check - still the right priority?
3. Audit Out of Scope - reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-04-29 after Phase 42 verification*
