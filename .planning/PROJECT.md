# Foglet BBS

## What This Is

Foglet BBS is an SSH-first bulletin board system built as a Phoenix/Elixir application. Users connect through a terminal UI over SSH to create accounts, browse boards, read threads, write posts, manage account preferences, participate through lightweight oneliners, and use role-appropriate moderation/sysop workflows without leaving the terminal. The Phoenix endpoint exists for operations and future structured clients, not as an end-user web UI.

## Core Value

A user can SSH into a living, reliable BBS and participate in conversations through a terminal-native experience that feels like arriving somewhere.

## Current State

**Shipped version:** v1.4 Post-Facelift Polish & Bug Fixes completed on 2026-04-28.
**Current milestone:** v2.0 TUI Runtime Shell & Screen Update Loops.

Foglet now has terminal-native Account, Moderation, and Sysop workbenches; actor-aware authorization; invite-only registration redemption; account profile/preferences; sysop config and board/category operations; preference-aware chrome time rendering; persistent oneliners; moderation hide/audit workflows; honest SMTP/no-email onboarding and reset behavior; sysop user-status administration; board posting and locked-thread restrictions; Account SSH key management; board subscription management; and a polished Unicode-capable SSH/TUI visual foundation.

The next architecture problem is ownership: `Foglet.TUI.App` currently owns route state, session state, modal state, task dispatch, task results, screen-specific async result handling, and screen-local state updates. Screens already own many render/key decisions, and widgets already follow a local `init/handle_event/render` pattern. v2.0 makes that ownership explicit at the screen boundary so `App` becomes a small runtime shell.

## Current Milestone: v2.0 TUI Runtime Shell & Screen Update Loops

**Goal:** Refactor the SSH/TUI runtime so `Foglet.TUI.App` becomes a small process shell, while each screen owns its local state, key handling, async-result handling, and render boundary through an explicit `init/update/render` interface.

**Target features:**
- Introduce first-class `Foglet.TUI.Context`, `Foglet.TUI.Effect`, and a screen behavior with `init/1`, `update/3`, and `render/2`.
- Make `App` route normalized messages to the active screen and interpret generic effects only: navigation, tasks, modals, PubSub/session operations, terminal resize, and termination.
- Replace anonymous `screen_state` bags and screen-owned top-level App fields with screen-local state structs.
- Fully migrate existing screens so `App` no longer reaches into BoardList, ThreadList, PostReader, Login, Account, Moderation, Sysop, or composer internals for async loads or key behavior.
- Preserve SSH-first behavior, domain-context boundaries, existing render contracts, and operator/account workflows while the architecture changes under them.
- Add regression coverage that proves screen reducers own local transitions and `App` remains a generic runtime shell.

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

### Active

- [ ] v2.0 - Define a screen runtime contract where screens expose `init/1`, `update/3`, and `render/2` over screen-local state and `Foglet.TUI.Context`.
- [ ] v2.0 - Add explicit effect values and a generic interpreter in `Foglet.TUI.App` for navigation, tasks, modal operations, PubSub/session operations, terminal resize, and quit.
- [ ] v2.0 - Move async-result handling out of `App` and into the screen that requested the work.
- [ ] v2.0 - Move stateful screens to first-class local state structs or explicit stateless modules.
- [ ] v2.0 - Fully migrate all current screens to the mini update-loop model while preserving SSH/TUI behavior and render contracts.
- [ ] v2.0 - Remove screen-specific domain/result clauses and generic `screen_state` manipulation from `App` after migration.

### Out of Scope

- New end-user browser workflows - Foglet remains SSH-first and terminal-native.
- New product features during the runtime refactor - this milestone changes ownership and architecture, not the BBS feature set.
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
| Make v2.0 an architecture milestone for screen ownership | `Foglet.TUI.App` has accumulated screen-specific routing, async-result handling, and state mutation; moving those decisions into screens makes future TUI work safer | Pending |

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
*Last updated: 2026-04-28 after starting v2.0 TUI Runtime Shell & Screen Update Loops*
