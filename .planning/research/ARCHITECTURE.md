# Architecture Research

**Domain:** Operations surfaces and invite/oneliner integration for an SSH-first BBS
**Researched:** 2026-04-23
**Confidence:** HIGH

## Standard Architecture

### System Overview

```text
┌──────────────────────────────────────────────────────────────────────┐
│                         Existing Interface Layer                    │
│  SSH -> CLIHandler -> Session -> TUI.App -> Screen module          │
└───────────────────────────────┬──────────────────────────────────────┘
                                │
                                │ current_screen + screen_state + commands
                                ▼
┌──────────────────────────────────────────────────────────────────────┐
│                         New TUI Surface Layer                       │
│  Account screen     Moderation screen     Sysop screen              │
│         └────────────── shared Operations.InvitesTab ─────────────┘ │
│  Main menu gets: preferred clock + oneliners panel + new nav items  │
└───────────────┬──────────────────────┬──────────────────────┬───────┘
                │                      │                      │
                ▼                      ▼                      ▼
┌──────────────────────┐  ┌──────────────────────┐  ┌──────────────────────┐
│ Foglet.Accounts      │  │ Foglet.Moderation    │  │ Foglet.Config/Boards │
│ profile/preferences  │  │ reports/actions/...  │  │ sysop-owned writes   │
│ login/register glue  │  │ scope-aware authz    │  │ categories/boards    │
└──────────┬───────────┘  └──────────┬───────────┘  └──────────┬───────────┘
           │                         │                         │
           │                         │                         │
           ▼                         ▼                         ▼
┌──────────────────────┐  ┌──────────────────────┐  ┌──────────────────────┐
│ Foglet.Invites       │  │ Foglet.Oneliners     │  │ Foglet.Authz         │
│ invite codes         │  │ DB + ring buffer     │  │ actor/scope policy   │
│ generation/redemption│  │ main-menu cache      │  │ shared by all screens│
└──────────┬───────────┘  └──────────┬───────────┘  └──────────┬───────────┘
           │                         │                         │
           └──────────────┬──────────┴──────────────┬──────────┘
                          ▼                         ▼
                 PostgreSQL (authoritative)   ETS/process cache
                 invite codes, reports,       oneliners recent buffer,
                 sanctions, config, prefs     existing config/session caches
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| `Foglet.TUI.Screens.Account` | User-owned profile/preferences workspace | New screen with tabs/forms, no business logic beyond command dispatch |
| `Foglet.TUI.Screens.Moderation` | Mod workspace shell for queue/log/users/sanctions/boards | New screen using scope-aware loaders and authz-gated actions |
| `Foglet.TUI.Screens.Sysop` | Sysop workspace for config, board/category lifecycle, system limits | New screen; calls existing contexts through explicit commands |
| `Foglet.TUI.Screens.Operations.InvitesTab` | Reusable invite list/create/revoke UI embedded in multiple surfaces | New shared screen-helper/widget module, not a process |
| `Foglet.Invites` + `Foglet.Invites.InviteCode` | Invite issuance, lookup, redemption, reuse rules | New context + schema; DB-backed, no dedicated process |
| `Foglet.Moderation` | Reports, sanctions, audit log, board moderator assignments, moderation actions | New context + schemas; wraps thread/post/oneliner moderation writes |
| `Foglet.Oneliners` + `Foglet.Oneliners.Entry` | Persist and serve recent shoutbox entries; hide entries via mod actions | New context + schema + supervised GenServer ring buffer |
| `Foglet.Authz` | Central actor/scope authorization seam for account/mod/sysop operations | New pure module, called by contexts and TUI command handlers |
| `Foglet.Accounts` | Existing owner of users; gains typed preference validation and atomic invite-backed registration entrypoint | Modified context and user changesets |
| `Foglet.TUI.App` | Existing conductor; gains new screens, new tick/pubsub messages, no new domain logic | Modified app router only |

## Recommended Project Structure

```text
lib/foglet_bbs/
├── accounts.ex
├── authz.ex
├── invites.ex
├── invites/
│   └── invite_code.ex
├── moderation.ex
├── moderation/
│   ├── board_moderator.ex
│   ├── report.ex
│   ├── action.ex
│   └── sanction.ex
├── oneliners.ex
├── oneliners/
│   └── entry.ex
├── tui/
│   ├── screens/
│   │   ├── account.ex
│   │   ├── moderation.ex
│   │   ├── sysop.ex
│   │   └── operations/
│   │       ├── invites_tab.ex
│   │       ├── surface_state.ex
│   │       └── time_format.ex
│   └── widgets/
│       └── ... existing inputs/tabs/table widgets
└── application.ex
```

### Structure Rationale

- **New domain modules stay context-shaped:** invites, moderation, and oneliners are persistent business domains, so they should not be hidden inside TUI code.
- **Shared invite UI lives under `tui/screens/operations/`:** the reuse problem is presentational, not persistence-related. Keep one invite tab renderer/state helper and embed it into Account, Moderation, and Sysop shells.
- **Do not create an `Operations` mega-context:** config, boards, accounts, invites, moderation, and oneliners already have natural owners. A grab-bag admin context would blur boundaries fast.
- **Add one authz seam, not scattered role checks:** current thread/post APIs have no authorization barrier. That must be fixed before new operational surfaces ship.

## Architectural Patterns

### Pattern 1: Thin Screen, Thick Context

**What:** screens own focus, tab index, cursor position, and view composition; contexts own validation, transactions, auditing, and authorization.
**When to use:** every new account/mod/sysop action.
**Trade-offs:** slightly more command plumbing in `TUI.App`, but avoids turning screens into unsafe service layers.

**Example:**
```elixir
def submit_invite(actor, generators_policy, attrs) do
  with :ok <- Foglet.Authz.can_generate_invites?(actor, generators_policy),
       {:ok, invite} <- Foglet.Invites.issue_invite(actor, attrs) do
    {:ok, invite}
  end
end
```

### Pattern 2: Reusable Invite Tab as a Surface Primitive

**What:** one `InvitesTab` module renders the same list/create/revoke workflow in three parent screens.
**When to use:** any place the user may legitimately generate or inspect invites.
**Trade-offs:** parent screens must pass explicit capability flags and loaded data instead of letting the tab read global state.

**Use this contract:**
- input: `viewer`, `invite_policy`, `invites`, `selected_index`, `mode`
- output commands: `{:load_invites}`, `{:issue_invite, attrs}`, `{:revoke_invite, id}`
- visibility: parent screen decides whether the tab exists at all

This keeps the tab reusable across Account, Moderation, and Sysop without coupling it to moderation queues or config editors.

### Pattern 3: Scope-Aware Authorization

**What:** authz functions always receive both actor and scope, even when today's UI is mostly site-wide.
**When to use:** moderation actions, moderation screen access, board management, invite generation visibility.
**Trade-offs:** a little more ceremony now, but it prevents a rewrite when board-scoped moderators arrive.

**Example:**
```elixir
def can_moderate_board?(actor, :site), do: actor.role in [:mod, :sysop]
def can_moderate_board?(actor, {:board, board_id}),
  do: actor.role == :sysop or board_moderator?(actor.id, board_id)
```

Recommendation: model moderation loaders and actions around `scope = :site | {:board, board_id}` immediately. The first milestone can still default mods to `:site`, but the APIs should not assume that forever.

### Pattern 4: DB-First, Cache-After for Oneliners

**What:** persist the oneliner first, then refresh the in-memory recent buffer, then notify interested screens.
**When to use:** create/hide oneliner and main-menu refresh.
**Trade-offs:** one extra update step after the write, but no correctness risk if the GenServer dies.

The existing architecture already treats ETS/process state as disposable. Oneliners should follow that rule.

## Data Flow

### Invite Generation and Redemption

```text
[Account/Moderation/Sysop screen]
    ↓
[InvitesTab command]
    ↓
[Foglet.Authz.can_generate_invites?/2]
    ↓
[Foglet.Invites.issue_invite/2] -> [invite_codes table]

[Register screen invite step]
    ↓
[Foglet.Invites.preview_redeemable/1]   # validate, do not consume
    ↓
[final submit]
    ↓
[Foglet.Accounts.register_user_with_invite/2]
    ↓
[Repo transaction: insert user -> consume invite]
```

Critical boundary: do **not** consume the invite code when the wizard first accepts it. Only consume inside the final registration transaction, or users will burn codes by abandoning the form.

### Preferences and Main-Menu Clock

```text
[Account screen save]
    ↓
[Foglet.Accounts.update_profile/2]
    ↓
[users.theme + users.preferences]
    ↓
[TUI.App updates current_user/session snapshot]
    ↓
[MainMenu render helper formats DateTime for user prefs]
    ↑
[minute tick from TUI.App subscription]
```

This should remain a screen/view concern plus a pure formatter module. It does **not** need a process.

Important current seam: `CLIHandler.build_context/3` currently injects `Theme.default()` into `session_context`. That is fine for boot, but stale for user-chosen themes. The post-save path should refresh the in-memory user/session snapshot immediately instead of relying on reconnect.

### Oneliners / Shoutbox

```text
[MainMenu or dedicated shoutbox entry flow]
    ↓
[Foglet.Oneliners.create_entry(actor, body)]
    ↓
[oneliners table insert]
    ↓
[Foglet.Oneliners GenServer refreshes ring buffer]
    ↓
[PubSub or explicit reload command]
    ↓
[MainMenu render]
```

Moderation hide flow should go through `Foglet.Moderation.hide_oneliner/3`, which writes both the `oneliners.hidden` state and an append-only `mod_actions` row.

### Moderation and Sysop Surfaces

```text
[Screen tab switch]
    ↓
[TUI.App task command]
    ↓
[Foglet.Moderation / Foglet.Config / Foglet.Boards]
    ↓
[Repo query or write]
    ↓
[result message back to screen state]
```

`TUI.App` should stay a command dispatcher only. It should not become the place where role checks, invite policy, or moderation business rules live.

## Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| `TUI.Screen` -> `TUI.App` | commands/messages | Existing pattern; keep new surfaces on the same model |
| `TUI.App` -> `Accounts` | direct API/task | For profile save, registration, session user refresh |
| `TUI.App` -> `Invites` | direct API/task | Shared by Account, Moderation, Sysop, and Register |
| `TUI.App` -> `Moderation` | direct API/task | Reports, sanctions, board moderator assignments, oneliner hide |
| `Moderation` -> `Threads` / `Posts` / `Oneliners` | internal API | Wrap existing raw mutation functions so authz and audit live in one place |
| `Sysop screen` -> `Config` / `Boards` | direct API/task, guarded by `Authz` | No separate process needed; runtime config already has ETS caching |
| `Oneliners` context -> `Oneliners` GenServer | direct function call + PubSub | DB remains authority; process is only a fast recent-entry cache |

## Modified Components

| Component | Change Required | Why |
|-----------|-----------------|-----|
| `lib/foglet_bbs/tui/app.ex` | Add new screens, load/result messages, minute tick, oneliner refresh path | Existing conductor for all screen routing |
| `lib/foglet_bbs/tui/screens/main_menu.ex` | Add account/mod/sysop nav items, preferred clock, oneliners panel/entry point | Current main menu is intentionally sparse |
| `lib/foglet_bbs/tui/screens/register.ex` | Replace stubbed `function_exported?/2` invite validation with real invite preview/final consume flow | Current invite-only mode is not real |
| `lib/foglet_bbs/accounts.ex` | Add `register_user_with_invite/2`, preference validation/update helpers, current-user refresh contract | Accounts already owns registration and profile writes |
| `lib/foglet_bbs/accounts/user.ex` | Validate typed preference keys like timezone/clock mode inside `profile_changeset/2` | Keeps preference rules near user schema |
| `lib/foglet_bbs/ssh/cli_handler.ex` | Stop treating theme as a permanent boot-time default; refresh from user profile | Required for Account screen changes to feel immediate |
| `lib/foglet_bbs/application.ex` | Supervise `Foglet.Oneliners` | Docs already assume a recent-entry buffer process exists |
| `lib/foglet_bbs/threads.ex` and `lib/foglet_bbs/posts.ex` | Keep raw mutation helpers, but stop exposing them directly to new moderation UI | Authz and audit must sit above them |

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| Current single-node BBS | Monolith is correct; one `Oneliners` GenServer and plain context APIs are enough |
| Small community growth | Add PubSub refreshes for oneliner activity and config-sensitive UI; keep DB-first writes |
| Larger moderation load | Optimize moderation list queries and maybe add cached counts, but keep scopes and authz centralized |

### First Bottlenecks

1. **Authorization drift:** if screens call `Threads.lock_thread/1` or `Posts.delete_post/2` directly, the first new surface will ship unsafe behavior.
2. **`TUI.App` sprawl:** adding many operations directly into `do_update/2` is manageable only if the business logic stays in contexts and shared surface helpers.

## Anti-Patterns

### Anti-Pattern 1: One Invite Implementation Per Surface

**What people do:** copy the same invite list/create form into Account, Moderation, and Sysop.
**Why it's wrong:** policy divergence appears immediately, and fixing invite bugs requires three edits.
**Do this instead:** make one `InvitesTab` module and let each parent surface decide whether to include it.

### Anti-Pattern 2: Role Checks Only in the Screen

**What people do:** hide tabs for non-mods/non-sysops but call raw context writes underneath.
**Why it's wrong:** the next interface, task, or API path bypasses the check.
**Do this instead:** enforce `Foglet.Authz` inside the operational write path and keep the screen check as a UX convenience only.

### Anti-Pattern 3: Global-Only Moderation APIs

**What people do:** make every moderation query and action assume the actor is a site-wide moderator.
**Why it's wrong:** board-scoped moderation later forces a full rewrite of queries, screen state, and authz.
**Do this instead:** accept an explicit moderation scope now, even if the first release mostly passes `:site`.

### Anti-Pattern 4: Consuming Invites During the Wizard Step

**What people do:** mark the invite used as soon as the code passes validation.
**Why it's wrong:** abandoned or failed registrations waste codes and create support churn.
**Do this instead:** validate early, consume only in the final registration transaction.

## Build Order

1. **Authorization and persistence backbone**
   - Add `Foglet.Authz`
   - Add invite, moderation, and oneliner schemas/contexts
   - Supervise the `Foglet.Oneliners` buffer
   - Rationale: every later surface depends on stable write APIs and safe authz

2. **Invite flow end to end**
   - Implement `Foglet.Invites`
   - Replace register-screen invite stub with preview + final consume flow
   - Add shared `InvitesTab` helper
   - Rationale: Account/Moderation/Sysop invite tabs are only useful once invite-only registration is real

3. **Account surface and preference plumbing**
   - Add Account screen
   - Validate/save timezone and clock preferences in `Accounts`
   - Refresh `current_user`/theme snapshot after save
   - Rationale: main-menu clock and user-owned invite access both depend on account data plumbing

4. **Main-menu integration**
   - Add minute tick
   - Render preferred timestamp and recent oneliners
   - Add shoutbox entry flow and conditional nav to Account/Moderation/Sysop
   - Rationale: this uses the now-stable preference and oneliner layers

5. **Moderation surface scaffolding**
   - Add tabbed Moderation screen with scope-aware state
   - Wire queue/log/users/sanctions/boards loaders
   - Route oneliner hide and thread/post moderation through `Foglet.Moderation`
   - Rationale: safe moderation requires the authz seam and audit log already in place

6. **Sysop surface**
   - Add site/config/boards/system/users tabs
   - Reuse `InvitesTab` conditionally based on `invite_code_generators`
   - Let config writes flow through `Config.put!/3` and board/category writes through `Boards`
   - Rationale: sysop work sits on top of the same config, moderation, and invite foundations

## Sources

- `.planning/PROJECT.md`
- `docs/ARCHITECTURE.md`
- `docs/DATA_MODEL.md`
- `.planning/codebase/CONCERNS.md`
- `lib/foglet_bbs/tui/app.ex`
- `lib/foglet_bbs/tui/screens/main_menu.ex`
- `lib/foglet_bbs/tui/screens/register.ex`
- `lib/foglet_bbs/ssh/cli_handler.ex`
- `lib/foglet_bbs/accounts.ex`
- `lib/foglet_bbs/accounts/user.ex`
- `lib/foglet_bbs/config.ex`
- `lib/foglet_bbs/config/schema.ex`
- Repo search on 2026-04-23 found no configured `time_zone_database`; timezone formatting should therefore be implemented behind a small formatter with a UTC-safe fallback until that prerequisite is explicitly wired.

---
*Architecture research for: operations surfaces and invites milestone integration*
*Researched: 2026-04-23*
