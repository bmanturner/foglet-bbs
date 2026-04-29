<!-- refreshed: 2026-04-29 -->
# Architecture

**Analysis Date:** 2026-04-29

## System Overview

Foglet BBS is an SSH-first bulletin board system. The product surface is a
terminal UI delivered to clients over SSH; Phoenix runs in the same BEAM node
purely as infrastructure (endpoint for `/up`, LiveDashboard, PubSub bus,
telemetry). Authoritative state is Postgres; ephemeral state lives in
GenServers, ETS, and `Phoenix.PubSub` and must be reconstructable on restart.

```text
┌──────────────────────────────────────────────────────────────────────────┐
│                          External Clients                                 │
│   ssh user@host (TUI)                  HTTP /up, /dev/dashboard           │
└─────────────┬──────────────────────────────────────────┬─────────────────┘
              │                                           │
              ▼                                           ▼
┌─────────────────────────────────┐     ┌───────────────────────────────────┐
│   Foglet.SSH.Supervisor          │     │   FogletBbsWeb.Endpoint           │
│   `lib/foglet_bbs/ssh/`          │     │   `lib/foglet_bbs_web/endpoint.ex`│
│   ├─ DaemonOwner (:ssh.daemon)   │     │   ├─ Plug pipeline                │
│   ├─ KeyCB / PubkeyStash (ETS)   │     │   ├─ FogletBbsWeb.Router          │
│   ├─ RateLimiter (Hammer)        │     │   └─ LiveDashboard (dev)          │
│   └─ CLIHandler (per channel)    │     └───────────────┬───────────────────┘
└──────────────┬──────────────────┘                     │
               │ ssh_channel_up / pty / data            │
               ▼                                         │
┌──────────────────────────────────┐                    │
│   Raxol.Core.Runtime.Lifecycle    │                    │
│   (one per SSH channel)           │                    │
│   ├─ Foglet.TUI.App (reducer)     │                    │
│   ├─ Screens / Widgets             │                    │
│   └─ PubSubForwarder (subscription)│                    │
└──────────┬───────────────┬───────┘                    │
           │               │                             │
           ▼               ▼                             │
┌─────────────────┐  ┌────────────────────────┐          │
│ Domain Contexts │  │ Foglet.Sessions.Session │          │
│ Foglet.Accounts │  │ (per user, Registry)    │          │
│ Foglet.Boards   │  └────────────┬────────────┘          │
│ Foglet.Threads  │               │                       │
│ Foglet.Posts    │               │                       │
│ Foglet.Threads  │               │                       │
│ Foglet.Moderation│              │                       │
│ Foglet.Oneliners│               │                       │
│ Foglet.Config   │               │                       │
│ Foglet.Auth (Bodyguard)         │                       │
└────────┬─────┬──┘               │                       │
         │     │                  │                       │
         │     │  serialize msg # │                       │
         │     ▼                  │                       │
         │  ┌────────────────────┐│                       │
         │  │ Foglet.Boards.Server││ (one per active board, Registry)
         │  │ Single writer for  ││                       │
         │  │ message_number     ││                       │
         │  └─────────┬──────────┘│                       │
         │            │           │                       │
         ▼            ▼           ▼                       ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                       Phoenix.PubSub :: FogletBbs.PubSub                 │
│   user:<uid>   board:<bid>   thread:<tid>   boards   tui:pubsub_forwarder│
└──────────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌──────────────────────────────────────────────────────────────────────────┐
│   FogletBbs.Repo (Ecto + Postgrex)                                        │
│   `lib/foglet_bbs/repo.ex`     priv/repo/migrations/*.exs                  │
└──────────────────────────────────────────────────────────────────────────┘

   ETS caches (module-owned, named):
     :foglet_config            (Foglet.Config)
     Foglet.SSH.PubkeyStash    (pubkey ↔ peer correlation)
     Foglet.SSH.CLIHandler.Counter  (active SSH connection count)
     Foglet.BoardRegistry      (board_id → Boards.Server pid; Registry)
     Foglet.Sessions.Registry  (user_id → Sessions.Session pid; Registry)
```

## Component Responsibilities

| Component | Responsibility | File |
|-----------|----------------|------|
| `FogletBbs.Application` | OTP root supervisor; starts ETS caches, Repo, PubSub, Registries, Boards/Sessions DynamicSupervisors, Endpoint, SSH daemon | `lib/foglet_bbs/application.ex` |
| `FogletBbs.Repo` | Ecto repo over Postgres (postgrex) | `lib/foglet_bbs/repo.ex` |
| `Foglet.Schema` | Ecto schema defaults: UUID PK/FK, `utc_datetime_usec` timestamps | `lib/foglet_bbs/schema.ex` |
| `Foglet.SSH.Supervisor` | OTP supervisor for the SSH stack; asserts patched OTP; builds daemon opts | `lib/foglet_bbs/ssh/supervisor.ex` |
| `Foglet.SSH.DaemonOwner` | Owns `:ssh.daemon/2` ref; traps EXITs so supervisor restarts the daemon on failure | `lib/foglet_bbs/ssh/daemon_owner.ex` |
| `Foglet.SSH.KeyCB` | `:ssh_server_key_api` callback; loads host keys; stashes offered pubkeys | `lib/foglet_bbs/ssh/key_cb.ex` |
| `Foglet.SSH.PubkeyStash` | ETS table correlating `{peer_ip, peer_port}` → public_key for CLIHandler pickup | `lib/foglet_bbs/ssh/pubkey_stash.ex` |
| `Foglet.SSH.RateLimiter` | Hammer-backed per-IP connection rate limit | `lib/foglet_bbs/ssh/rate_limiter.ex` |
| `Foglet.SSH.HostKey` | Generates/persists Ed25519 host keys under `priv/ssh/` | `lib/foglet_bbs/ssh/host_key.ex` |
| `Foglet.SSH.CLIHandler` | `:ssh_server_channel` behaviour; owns channel lifecycle, alt-screen, Lifecycle start, event dispatch, connection-cap ETS counter | `lib/foglet_bbs/ssh/cli_handler.ex` |
| `Foglet.Sessions.Supervisor` | DynamicSupervisor for per-user sessions; one-session-per-user replacement protocol | `lib/foglet_bbs/sessions/supervisor.ex` |
| `Foglet.Sessions.Session` | Per-user GenServer; identity, terminal size, last-seen, theme/timezone snapshot; via `Foglet.Sessions.Registry` | `lib/foglet_bbs/sessions/session.ex` |
| `Foglet.Sessions.Preferences` | Snapshot of user preferences (timezone, time_format, theme_id, theme) | `lib/foglet_bbs/sessions/preferences.ex` |
| `Foglet.Boards.Supervisor` | DynamicSupervisor for per-board servers; boots all non-archived boards on app start | `lib/foglet_bbs/boards/supervisor.ex` |
| `Foglet.Boards.Server` | Per-board GenServer; **single writer** for `message_number`; runs `Ecto.Multi` for thread/post creation | `lib/foglet_bbs/boards/server.ex` |
| `Foglet.Boards` | Categories, boards, subscriptions, read pointers; `boot_board_servers/0` | `lib/foglet_bbs/boards.ex` |
| `Foglet.Threads` | Thread queries, lock/sticky/move, thread read pointers; thread creation delegates to `Boards.Server` | `lib/foglet_bbs/threads.ex` |
| `Foglet.Posts` | Post queries, edits, soft delete; reply creation delegates to `Boards.Server` | `lib/foglet_bbs/posts.ex` |
| `Foglet.Accounts` | Users, SSH keys, invites, tokens, email verification, account deletion | `lib/foglet_bbs/accounts.ex` |
| `Foglet.Authorization` | `Bodyguard.Policy` for operator actions; site/board scopes; sysop/mod role rules | `lib/foglet_bbs/authorization.ex` |
| `Foglet.Config` | Read-through ETS cache over `configuration` table; typed accessors; actor-aware `put/3` | `lib/foglet_bbs/config.ex` |
| `Foglet.Moderation` | Mod actions log + queries | `lib/foglet_bbs/moderation.ex` |
| `Foglet.Oneliners` | Ticker-style oneliners (post + hide) | `lib/foglet_bbs/oneliners.ex` |
| `Foglet.PostingPolicy` | Pure predicates (`can_post?/2`, `can_bypass_thread_lock?/2`) | `lib/foglet_bbs/posting_policy.ex` |
| `Foglet.PubSub` | Canonical topic constructors (`user_topic/1`, `board_topic/1`, `thread_topic/1`, `boards_aggregate/0`) | `lib/foglet_bbs/pub_sub.ex` |
| `Foglet.Markdown` | mdex-backed markdown rendering for post bodies | `lib/foglet_bbs/markdown.ex` |
| `Foglet.QueryHelpers` | Shared Ecto query helpers (e.g., `not_archived/1`) | `lib/foglet_bbs/query_helpers.ex` |
| `Foglet.TimeAgo` | Human-formatted relative timestamps | `lib/foglet_bbs/time_ago.ex` |
| `Foglet.TUI.App` | Raxol `Application`; UI shell struct; routes keys/messages to active screen; interprets `Foglet.TUI.Effect` values | `lib/foglet_bbs/tui/app.ex` |
| `Foglet.TUI.Screens.*` | Per-screen reducers + `state.ex` modules; render + `update/3` | `lib/foglet_bbs/tui/screens/<screen>.ex` and `screens/<screen>/state.ex` |
| `Foglet.TUI.Widgets.*` | Reusable display primitives (chrome, composer, list, modal, post, progress) | `lib/foglet_bbs/tui/widgets/*.ex` |
| `Foglet.TUI.PubSubForwarder` | Raxol `Subscription.custom/2` source; bridges `Phoenix.PubSub` topics → `{:subscription, msg}` to dispatcher | `lib/foglet_bbs/tui/pub_sub_forwarder.ex` |
| `Foglet.TUI.SizeGate` | Blocks rendering and key handling when terminal is too small | `lib/foglet_bbs/tui/size_gate.ex` |
| `Foglet.TUI.Theme` | Color palette + Raxol theme registry | `lib/foglet_bbs/tui/theme.ex` |
| `Foglet.TUI.Effect` | Pure data values returned by screen reducers (navigate, task, modal, publish, session, terminal, quit) | `lib/foglet_bbs/tui/effect.ex` |
| `Foglet.TUI.SessionContext` | Struct passed from CLIHandler into the TUI app (user, prefs, config snapshot) | `lib/foglet_bbs/tui/session_context.ex` |
| `Foglet.TUI.Modal` | Modal value + helpers consumed by `App.global_key_handler/2` | `lib/foglet_bbs/tui/modal.ex` |
| `Foglet.TUI.Command` | Wraps `Raxol.Core.Runtime.Command.task/1` for screen-bound async ops | `lib/foglet_bbs/tui/command.ex` |
| `Foglet.TUI.RenderFixtures` | Synthetic users/boards/threads for `mix foglet.tui.render` | `lib/foglet_bbs/tui/render_fixtures.ex` |
| `FogletBbsWeb.Endpoint` | Phoenix endpoint; static, plug session, router | `lib/foglet_bbs_web/endpoint.ex` |
| `FogletBbsWeb.Router` | Routes `/` (PageController), `/up` (HealthController), dev `/dev/dashboard` | `lib/foglet_bbs_web/router.ex` |
| `FogletBbsWeb.Telemetry` | telemetry_poller + metric definitions for `phoenix.*` and `foglet_bbs.repo.query.*` | `lib/foglet_bbs_web/telemetry.ex` |
| `FogletBbsWeb.PageController` / `HealthController` | Minimal HTTP surface (homepage, `/up`) | `lib/foglet_bbs_web/controllers/page_controller.ex`, `health_controller.ex` |

## Pattern Overview

**Overall:** Phoenix-style domain contexts ("Phoenix without LiveView") plus an
SSH/Raxol delivery layer. Per-aggregate GenServer for invariants
(`Foglet.Boards.Server`). Read-through ETS caches for config and per-connection
state. Phoenix.PubSub as the cross-process notification bus. Raxol-on-SSH as
the rendering runtime, with a custom `PubSubForwarder` subscription bridging
Phoenix.PubSub into Raxol's dispatcher loop.

**Key Characteristics:**
- Domain logic lives in `Foglet.*` contexts; Phoenix/HTTP code is `FogletBbs.*` / `FogletBbsWeb.*` and stays thin.
- Postgres is authoritative; every ETS table and GenServer must be reconstructable from the DB.
- Authorization is centralised in `Foglet.Authorization` (`Bodyguard.Policy`) with stable scopes `:site` and `{:board, board_id}`.
- TUI screens are reducers that return `Foglet.TUI.Effect` values; `Foglet.TUI.App` is the only effect interpreter.
- All inter-screen / inter-session notification flows over `Phoenix.PubSub` via topic constructors in `Foglet.PubSub`.

## Layers

**Delivery (SSH + Phoenix):**
- Purpose: Accept external connections, hand them off to runtime processes.
- Location: `lib/foglet_bbs/ssh/`, `lib/foglet_bbs_web/`
- Contains: `:ssh` daemon owner, channel handler, key callbacks, rate limiter, host-key generator; Phoenix endpoint, router, controllers, telemetry.
- Depends on: Sessions, TUI, domain contexts (read-only at delivery time).
- Used by: External SSH/HTTP clients.

**Runtime (Sessions + TUI + Boards.Server):**
- Purpose: Per-connection / per-user / per-board long-lived processes.
- Location: `lib/foglet_bbs/sessions/`, `lib/foglet_bbs/tui/`, `lib/foglet_bbs/boards/server.ex`
- Contains: `Sessions.Session` GenServer, Raxol `Lifecycle` (started by CLIHandler), `Foglet.TUI.App` reducer, per-board servers.
- Depends on: Domain contexts, `FogletBbs.PubSub`, Registries.
- Used by: Delivery layer.

**Domain Contexts (`Foglet.*`):**
- Purpose: Encapsulate business rules, transactions, authorization, preloads, PubSub broadcasts.
- Location: `lib/foglet_bbs/<context>.ex` plus `lib/foglet_bbs/<context>/` for schemas.
- Contains: Public API functions, Ecto schemas, changesets, scope helpers (`scope_for/1`).
- Depends on: `FogletBbs.Repo`, `Foglet.Authorization`, `Foglet.Config`, `Foglet.PubSub`.
- Used by: TUI screens, Mix tasks (`lib/mix/tasks/foglet.*.ex`), Boards.Server, tests.

**Persistence (Repo + Postgres):**
- Purpose: Durable state.
- Location: `lib/foglet_bbs/repo.ex`, `priv/repo/migrations/*.exs`, `priv/repo/seeds.exs`, `priv/repo/seeds/`.
- Contains: Single repo (`FogletBbs.Repo`) over Postgres via `postgrex`. Migrations are timestamped `YYYYMMDDHHMMSS_*.exs`.
- Depends on: Postgres.
- Used by: All contexts.

## Data Flow

### Primary Request Path — SSH login → main menu

1. Client TCP-connects on port 2222; OTP `:ssh` daemon (started by `Foglet.SSH.DaemonOwner.init/1` at `lib/foglet_bbs/ssh/daemon_owner.ex:45`) accepts the connection.
2. `Foglet.SSH.KeyCB.is_auth_key/3` (`lib/foglet_bbs/ssh/key_cb.ex`) validates the offered pubkey against the algorithm allowlist and stashes it in `Foglet.SSH.PubkeyStash` (ETS) keyed by peer.
3. Daemon is configured with `no_auth_needed: true` (`lib/foglet_bbs/ssh/supervisor.ex:77`), so authentication completes and `Foglet.SSH.CLIHandler` is invoked as `ssh_cli`.
4. `CLIHandler.handle_msg({:ssh_channel_up, ...})` (`lib/foglet_bbs/ssh/cli_handler.ex:80`) increments the ETS connection counter, applies `Foglet.SSH.RateLimiter`, pops the stashed pubkey, calls `Foglet.Accounts.Auth.authenticate_by_public_key/1` (`lib/foglet_bbs/accounts/auth.ex`), and starts a `Sessions.Session` via `Foglet.Sessions.Supervisor.start_session/1` or `start_guest_session/0`.
5. On `{:pty, ...}` (`cli_handler.ex:175`) the handler emits the alt-screen escape, builds a `Foglet.TUI.SessionContext`, and starts `Raxol.Core.Runtime.Lifecycle.start_link(Foglet.TUI.App, ...)` with `name: nil` (one Lifecycle per channel).
6. `Foglet.TUI.App.init/1` (`lib/foglet_bbs/tui/app.ex:259`) extracts the session context, registers `tui_pid` with the Session, and chooses an initial screen.
7. Subsequent `{:data, ...}` channel messages are parsed by `Raxol.SSH.IOAdapter.parse_input/1` and dispatched to the Raxol Dispatcher, which routes them through `Foglet.TUI.App.update/2`.

### Thread / post creation (per-board invariant path)

1. TUI screen reducer (e.g. `Foglet.TUI.Screens.NewThread.update/3` at `lib/foglet_bbs/tui/screens/new_thread.ex`) returns a `Foglet.TUI.Effect.task/3` calling `Foglet.Threads.create_thread/3`.
2. `Foglet.Threads.create_thread/3` (`lib/foglet_bbs/threads.ex:46`) checks `Foglet.PostingPolicy.can_post?/2`, then delegates to `Foglet.Boards.Server.create_thread/3`.
3. `Foglet.Boards.Server.handle_call({:create_thread, ...}, ...)` (`lib/foglet_bbs/boards/server.ex:97`) runs an `Ecto.Multi` that increments `boards.next_message_number`, inserts the `Thread` (with `first_post_id: nil`), inserts the root `Post` with the allocated `message_number`, updates `thread.first_post_id`, and bumps `users.post_count` — all in one DB transaction.
4. On success the in-memory counter advances; on failure the counter stays put so retries reuse the same number.
5. The owning context broadcasts to `Foglet.PubSub.thread_topic/1` / `board_topic/1`; subscribed TUI sessions receive the message via `Foglet.TUI.PubSubForwarder` (`lib/foglet_bbs/tui/pub_sub_forwarder.ex:103`) which wraps it as `{:subscription, msg}` for the Dispatcher.

### Configuration read

1. Caller invokes `Foglet.Config.get!/1` (`lib/foglet_bbs/config.ex:56`).
2. ETS table `:foglet_config` is consulted; on hit, value returned directly.
3. On miss, `Repo.get_by!(Foglet.Config.Entry, key: ...)` loads the row, the value is unwrapped (`%{"v" => v}`), inserted into ETS, and returned.
4. Writes via `put!/3` or `put/3` validate against `Foglet.Config.Schema` (`lib/foglet_bbs/config/schema.ex`), upsert the row, then `invalidate/1` drops the ETS key. Actor-aware `put/3` first calls `Bodyguard.permit(Foglet.Authorization, :edit_config, actor, :site)`.

**State Management:**
- Per-channel UI state is held inside the Raxol `Lifecycle` process (the `%Foglet.TUI.App{}` reducer state plus per-screen `%State{}` structs under `screen_state`).
- Per-user identity / preferences live in `Foglet.Sessions.Session` (one per `user_id`, registered via `Foglet.Sessions.Registry`).
- Per-board mutation invariants live in `Foglet.Boards.Server` (one per `board_id`, registered via `Foglet.BoardRegistry`).
- All durable state goes to Postgres through `FogletBbs.Repo`. ETS is cache-only (`:foglet_config`, pubkey stash, connection counter).

## Key Abstractions

**Domain Context (`Foglet.<Aggregate>`):**
- Purpose: Public boundary for an aggregate. Owns transactions, authorization checks, preload choices, PubSub side effects, cross-schema invariants.
- Examples: `lib/foglet_bbs/boards.ex`, `lib/foglet_bbs/threads.ex`, `lib/foglet_bbs/posts.ex`, `lib/foglet_bbs/accounts.ex`, `lib/foglet_bbs/moderation.ex`.
- Pattern: Function modules; sibling `lib/foglet_bbs/<context>/*.ex` directory holds `Ecto.Schema` modules and helpers.

**Authorization Scope:**
- Purpose: Stable shape passed to `Bodyguard.permit/4` so policy lookup is deterministic.
- Shapes: `:site` and `{:board, board_id}`.
- Examples: `Foglet.Boards.scope_for/1`, `Foglet.Threads.scope_for/1`, `Foglet.Posts.scope_for/1`.
- Rule: Scope derivation is centralised — never inline in screens or widgets.

**Per-Aggregate GenServer:**
- Purpose: Serialise mutations that need a single writer (message-number allocation).
- Examples: `Foglet.Boards.Server` (one per board, registered via `Foglet.BoardRegistry`).
- Pattern: `via_tuple(id) = {:via, Registry, {Foglet.BoardRegistry, id}}`. Self-heals on init by querying `MAX(message_number)`.

**Per-User GenServer:**
- Purpose: One-session-per-user enforcement, terminal-size tracking, theme snapshot.
- Examples: `Foglet.Sessions.Session` (registered via `Foglet.Sessions.Registry` only after promotion; guests are unregistered).
- Replacement protocol: `:replaced_by_new_session` message + monitor + 2 s timeout.

**Screen Reducer + Effect:**
- Purpose: Pure-ish UI updates. Screens take `(msg, ctx, state)` and return `{state, [Effect.t()]}`. `Foglet.TUI.App.apply_effect/2` interprets each effect as a `Raxol` runtime command or a domain action.
- Examples: `lib/foglet_bbs/tui/screens/post_reader.ex` + `screens/post_reader/state.ex`.
- Pattern: `Foglet.TUI.Effect.navigate/2`, `Effect.task/3`, `Effect.publish/2`, `Effect.open_modal/1`.

**Topic Constructor:**
- Purpose: Centralise PubSub topic strings so producers and consumers cannot drift.
- Examples: `Foglet.PubSub.user_topic/1`, `board_topic/1`, `thread_topic/1`, `boards_aggregate/0`.

**Read-through ETS Cache:**
- Purpose: Hot path reads without a Repo round-trip.
- Examples: `Foglet.Config` (`:foglet_config`), `Foglet.SSH.PubkeyStash` (peer→pubkey), `Foglet.SSH.CLIHandler.Counter` (active connection count).
- Rule: Idempotent `init_cache/0`; writes invalidate the key, never bypass the DB.

## Entry Points

**SSH daemon (port 2222 by default):**
- Location: `lib/foglet_bbs/ssh/supervisor.ex` → `lib/foglet_bbs/ssh/daemon_owner.ex` → `lib/foglet_bbs/ssh/cli_handler.ex`.
- Triggers: External SSH client connection.
- Responsibilities: Accept channel, identify user (pubkey or guest), start a `Sessions.Session` and a `Raxol.Core.Runtime.Lifecycle` running `Foglet.TUI.App`.

**Phoenix endpoint (port 4000 by default):**
- Location: `lib/foglet_bbs_web/endpoint.ex` → `lib/foglet_bbs_web/router.ex`.
- Triggers: HTTP request.
- Responsibilities: Serve `/` (placeholder homepage), `/up` health check (`FogletBbsWeb.HealthController`), `/dev/dashboard` LiveDashboard in dev. **No end-user browser workflows.**

**Application boot:**
- Location: `lib/foglet_bbs/application.ex`.
- Triggers: BEAM start (`mix phx.server`, release start, `iex -S mix`).
- Responsibilities: Initialize ETS caches (`Foglet.Config.init_cache/0`, `Foglet.SSH.PubkeyStash.init/0`), register themes, start the OTP supervision tree, then `Foglet.Boards.boot_board_servers/0` to start one server per non-archived board.

**Mix tasks (operator surface):**
- Location: `lib/mix/tasks/foglet.*.ex` (`foglet.user.create.ex`, `foglet.user.promote.ex`, `foglet.user.reset_password.ex`, `foglet.user.status.ex`, `foglet.user.verification_code.ex`, `foglet.board_subscriptions.ex`, `foglet.doctor.ex`, `foglet.tui.render.ex`).
- Triggers: `mix foglet.<task>` / `rtk mix foglet.<task>`.
- Responsibilities: Operator-only flows that go through the same domain contexts as the TUI.

**TUI render task (developer surface):**
- Location: `lib/mix/tasks/foglet.tui.render.ex`.
- Triggers: `rtk mix foglet.tui.render <screen>`.
- Responsibilities: Drive `Raxol.UI.Layout.Engine` over a `Foglet.TUI.RenderFixtures` user/board/thread set and print plain text — no Repo, no SSH.

## Architectural Constraints

- **Threading:** Single BEAM node, BEAM scheduler-managed. Each SSH channel owns its own Raxol `Lifecycle` process (`name: nil` registration in `cli_handler.ex:188-192` is required — naming would collapse all sessions onto one Lifecycle and reject concurrent connections).
- **Single-writer per board:** Message-number allocation is serialised by `Foglet.Boards.Server`. Direct insertion into `posts` outside the server breaks the invariant.
- **One session per user:** Enforced by `Foglet.Sessions.Registry` plus the `:replaced_by_new_session` protocol in `Foglet.Sessions.Supervisor.replace/2` and `replace_then_promote/3`. Guest sessions are NOT registered until promoted (`promote_guest_session/2` at `lib/foglet_bbs/sessions/supervisor.ex:86`).
- **Connection cap:** 500 concurrent SSH channels (module attr `@max_connections` in `cli_handler.ex:58`); enforced by an ETS counter in `Foglet.SSH.CLIHandler.Counter`.
- **OTP version floor:** SSH supervisor refuses to start on OTP older than 27.3.3 to mitigate CVE-2025-32433 (`lib/foglet_bbs/ssh/supervisor.ex:127`).
- **Global state (intentional):** `:foglet_config` ETS table, `Foglet.SSH.PubkeyStash` ETS table, `Foglet.SSH.CLIHandler.Counter` ETS table, `Foglet.BoardRegistry`, `Foglet.Sessions.Registry`. All are named, owned by a known module, and idempotent on init.
- **Trap-exits:** `Foglet.SSH.DaemonOwner` and `Foglet.SSH.CLIHandler` trap exits so daemon/lifecycle crashes propagate cleanly to supervisors and SSH clients.
- **Read pointers are monotonic:** `Foglet.Boards.ReadPointer` and `Foglet.Threads.ReadPointer` are persisted user state and only ever advance; UI-local scroll/read state is kept separate in screen `%State{}`.
- **Soft deletes preserve message numbers:** Deleted posts keep their `message_number`; gaps are intentional and authoritative.
- **No browser workflows:** `FogletBbsWeb.Router` exposes only `/`, `/up`, and dev `/dev/dashboard`. Adding a user-facing browser surface requires architecture-doc updates first.

## Anti-Patterns

### Bypassing `Foglet.Boards.Server` for post insertion

**What happens:** A caller `Repo.insert/1`s a `%Foglet.Posts.Post{}` directly to "skip the GenServer hop".
**Why it's wrong:** `message_number` is allocated by the per-board server in lockstep with `boards.next_message_number`. A direct insert either leaves the counter stale (collision on the next normal write) or duplicates an allocated number.
**Do this instead:** Always go through `Foglet.Threads.create_thread/3` or `Foglet.Posts.create_reply/4`, which delegate to `Foglet.Boards.Server.create_thread/3` / `create_post/4`.

### Inline scope derivation

**What happens:** A screen builds `{:board, board.id}` itself before calling `Bodyguard.permit/4`.
**Why it's wrong:** Scope shape is part of the policy contract; if the shape changes (e.g., `{:board, id, parent_id}`) every inline call site silently breaks the policy match.
**Do this instead:** Use `Foglet.Boards.scope_for/1`, `Foglet.Threads.scope_for/1`, `Foglet.Posts.scope_for/1` (`lib/foglet_bbs/boards.ex:30`, `lib/foglet_bbs/threads.ex:35`, `lib/foglet_bbs/posts.ex:32`).

### Putting `user_id` in changeset `cast/3`

**What happens:** A schema's changeset adds `:user_id` to the cast list so a controller / screen can pass it as an attribute.
**Why it's wrong:** Foreign keys are not user-settable; allowing them in `cast/3` opens an authorization-bypass surface and forces every call site to know the FK shape.
**Do this instead:** Set FKs programmatically on the struct (`%Post{user_id: user.id, board_id: board.id}`) before piping into `creation_changeset/2`. See `Foglet.Boards.Server.run_post_insert_multi/5` (`lib/foglet_bbs/boards/server.ex:128`).

### Hidden / disabled UI as authorization

**What happens:** A screen hides a "Lock thread" key binding for non-mods and treats that as the only check.
**Why it's wrong:** UI is a hint; nothing prevents the underlying domain function from being invoked through a different code path (Mix task, future API client, test fixture). Per `Foglet.Authorization` docs (D-17/D-18), the context function is the trust boundary.
**Do this instead:** Use `Bodyguard.permit?/4` for advisory rendering (grey out, hide), but ALWAYS call `Bodyguard.permit/4` inside the context function before side effects. See `Foglet.Config.put/3` (`lib/foglet_bbs/config.ex:146`) for the canonical pattern.

### Putting domain workflows in `FogletBbs.*` / `FogletBbsWeb.*`

**What happens:** A new feature lives inside a Phoenix controller, an SSH callback, or a TUI render function.
**Why it's wrong:** `Foglet.*` is the domain namespace; `FogletBbs.*` and `FogletBbsWeb.*` are infrastructure. Mixing layers makes contexts impossible to test in isolation and bleeds Phoenix concerns into SSH/TUI.
**Do this instead:** Add the workflow to (or create) a `Foglet.<Aggregate>` context module. Controllers/handlers/screens call the context.

### Phoenix.PubSub topic strings inline

**What happens:** A broadcaster writes `Phoenix.PubSub.broadcast(FogletBbs.PubSub, "board:" <> id, msg)`.
**Why it's wrong:** The TUI consumer subscribes via `Foglet.PubSub.board_topic/1`. A typo or schema change drifts producer and consumer silently.
**Do this instead:** Always construct topics through `Foglet.PubSub` (`lib/foglet_bbs/pub_sub.ex`).

### Returning bare `:error` from `Bodyguard` `authorize/3`

**What happens:** Policy clause returns `:error` instead of `{:error, :forbidden}`.
**Why it's wrong:** `Bodyguard.permit/4` coerces bare `:error` and the reason atom is lost downstream.
**Do this instead:** Always return `:ok` or `{:error, :forbidden}` (D-14). See `Foglet.Authorization.authorize/3` (`lib/foglet_bbs/authorization.ex:88-126`).

## Error Handling

**Strategy:** Tagged tuples at context boundaries; raise only for programmer errors; let-it-crash for supervised processes.

**Patterns:**
- Domain functions return `{:ok, result}` / `{:error, reason}`. Authorization failures specifically return `{:error, :forbidden}`.
- Bang variants (`get!/1`, `put!/3`) are for trusted internal callers (seeds, Mix tasks, tests). Non-bang variants exist for actor-driven paths.
- `Ecto.Multi` is the unit of multi-row consistency (see `Foglet.Boards.Server.run_post_insert_multi/5` / `run_thread_create_multi/4`).
- `Foglet.SSH.DaemonOwner` traps exits and stops itself on unexpected daemon death; `Foglet.SSH.Supervisor` (`:one_for_one`) restarts it.
- `Foglet.SSH.CLIHandler` traps exits; if the Raxol `Lifecycle` crashes, the channel is closed cleanly and the connection counter decremented.
- `Foglet.Config.put/3` catches `Ecto.InvalidChangesetError`, `Postgrex.Error`, `DBConnection.ConnectionError` and returns `{:error, :db_error}` so callers never see a raw raise.

## Cross-Cutting Concerns

**Logging:** Standard `Logger`. SSH channel lifecycle events log at `info`; supervisor restarts and protocol violations at `warning` / `error`.

**Validation:** Ecto changesets at the schema layer. `Foglet.Config.Schema` validates runtime config keys before they touch the DB. `Foglet.PostingPolicy` is the predicate layer for "may this user post here".

**Authentication:**
- SSH pubkey: `Foglet.SSH.KeyCB` stashes offered pubkeys; `Foglet.SSH.CLIHandler` authenticates on `ssh_channel_up` via `Foglet.Accounts.Auth.authenticate_by_public_key/1`.
- Password: TUI login screen calls `Foglet.Accounts.Auth.authenticate_by_password/2`; on success it triggers `Foglet.Sessions.Supervisor.promote_guest_session/2`.
- Email verification: `Foglet.Accounts.Verification` (token-hash storage in `user_tokens`).

**Authorization:** `Foglet.Authorization` (`Bodyguard.Policy`). Always called inside the domain function before side effects; TUI may use `Bodyguard.permit?/4` for advisory rendering only.

**Telemetry / Observability:** `FogletBbsWeb.Telemetry` defines metrics for `phoenix.*`, `foglet_bbs.repo.query.*`, and VM stats. LiveDashboard consumes them in dev. No external APM is wired.

**Rate limiting:** `Foglet.SSH.RateLimiter` (Hammer) on inbound SSH connections by peer IP.

---

*Architecture analysis: 2026-04-29*
