# Project Research Summary

**Project:** Foglet BBS v1.1 Operations Surfaces & Invites
**Domain:** SSH-first BBS operations surfaces, invite enforcement, account preferences, and main-menu social polish
**Researched:** 2026-04-23
**Confidence:** HIGH

## Executive Summary

Foglet v1.1 is not a new product category. It is an SSH-first BBS adding the operational surfaces mature BBSes are expected to have: compact account defaults, real invite-only onboarding, moderator and sysop workspaces, and a lightweight social strip on the main menu. The research is consistent that Foglet should keep this terminal-native, role-gated, and explicit. The right implementation is a Phoenix monolith with thin TUI screens, domain logic in contexts, Postgres as the source of truth, and small OTP helpers only where live caching or timed refreshes are actually needed.

For this codebase, the decisive recommendation is to add one new stack dependency, `Timex ~> 3.7`, then build the milestone around four new seams: `Foglet.Authz`, `Foglet.Invites`, `Foglet.Moderation`, and `Foglet.Oneliners`. Preferences should stay in `users.preferences`; invite codes and oneliners should be persisted in Postgres; the recent-oneliners view should be served from a supervised in-memory buffer backed by the database; and the reusable `INVITES` UI should live in shared TUI code, not in three copied surfaces. `Foglet.TUI.App` should remain a dispatcher, not become a business-logic sink.

The biggest risks are already visible in the current codebase. `register.ex` still treats invite validation as a stub path, and `ssh/cli_handler.ex` snapshots session context at connect time. If v1.1 ships on top of those seams unchanged, invite-only mode will remain fake and preference/config changes will drift from the active SSH session. The roadmap should therefore front-load actor-aware authorization, transactional invite consumption, typed preference validation, and live session refresh before building out the full moderation and sysop shells.

## Key Findings

### Recommended Stack

This milestone does not need a technology reset. The existing Phoenix/Ecto/Postgres/Raxol/OTP stack is the correct substrate for v1.1. The only required addition is `Timex ~> 3.7` so stored IANA timezone preferences and user-facing clock rendering have an approved milestone-level implementation path. Everything else should reuse what Foglet already has: Postgres for durable state, Phoenix PubSub plus OTP timers for refreshes, existing typed runtime config, and existing Raxol screens/widgets for the UI layer.

**Core technologies:**
- `Timex ~> 3.7`, Elixir stdlib `DateTime`, `Calendar`, `Base`, and `:crypto`: timezone rendering, clock formatting, and secure invite-code generation within the approved v1.1 stack.
- Ecto + PostgreSQL: authoritative storage for invite lifecycle, moderation data, oneliners, and user display preferences.
- Phoenix PubSub + OTP timers: minute-clock refresh and oneliner fanout without adding schedulers or another event bus.
- Raxol + existing Foglet TUI widgets: account, moderation, sysop, and shared invite surfaces inside the existing SSH UI model.

### Expected Features

The milestone table stakes are clear and specific to Foglet's stated v1.1 goal: operational depth inside the TUI. The must-have line is not "more screens"; it is real workflows behind those screens.

**Must have (table stakes):**
- Account screen for private profile basics plus presentation defaults: timezone, `12h/24h`, theme, and small visibility-style preferences.
- Shared `INVITES` tab with generate, list, revoke, audit, and real registration redemption.
- Functional moderation workspace with queue, log, users, sanctions, and board-aware context.
- Sysop workspace for runtime config, board/category lifecycle, user role/status management, and operational limits.
- Main-menu localized clock plus bounded recent oneliners with quick posting.

**Should have (good v1.x follow-ons, not blockers):**
- Theme/timestamp previews and "where this setting appears" hints.
- Multi-use invites, optional notes, and moderator invite delegation when config enables it.
- Richer operator detail panes combining account, invite, sanction, and activity context.
- Presence-adjacent menu polish such as online counts or recent caller hints.

**Defer (v2+ or later milestone):**
- SSH-key, password, or broader credential self-service in Account.
- Referral trees, outbound invite campaigns, or hidden auto-approval mechanics.
- Appeals, case management, saved moderator views, or automation-assisted moderation.
- Advanced sysop observability dashboards and chat-like real-time shoutbox behavior.

### Architecture Approach

The recommended architecture is to keep screens thin and contexts thick. `Foglet.TUI.Screens.Account`, `Moderation`, and `Sysop` should own view state only. Shared invite rendering should live in `Foglet.TUI.Screens.Operations.InvitesTab`. Business rules belong in new or expanded contexts, with one centralized authorization seam that is called from the domain layer as well as the TUI. Postgres remains authoritative; ETS/process state remains reconstructable.

**Major components:**
1. `Foglet.Authz` — central actor-plus-scope policy for account, moderation, invite, and sysop actions.
2. `Foglet.Invites` + `Foglet.Invites.InviteCode` — issue, preview, redeem, revoke, and audit invite codes transactionally.
3. `Foglet.Oneliners` + `Foglet.Oneliners.Entry` — persist oneliners, maintain a bounded recent-entry buffer, and broadcast refreshes.
4. `Foglet.Moderation` — reports, sanctions, action log, board-aware moderation queries, and moderation wrappers around thread/post/oneliner actions.
5. `Foglet.TUI.App` plus new Account/Moderation/Sysop screens — command dispatch, routing, and state updates only.

### Critical Pitfalls

1. **Invite consumption outside user creation** — preview invite codes in the wizard, but consume them only inside the same transaction that inserts the user.
2. **Authorization enforced only in screens** — require actor-aware domain APIs and return `{:error, :forbidden}` from contexts, not just hidden tabs in the TUI.
3. **Global-only moderator assumptions** — carry explicit scope through moderation queries and actions so v1.1 does not block board-scoped moderators later.
4. **Session-context drift after preference or config changes** — refresh `current_user` and derived session context after Account or Sysop saves so theme, clock, and invite/config visibility update without reconnect.
5. **Timezone preferences without a real contract** — validate IANA zone names, add `Timex ~> 3.7`, and route all user-facing timestamp rendering through one formatter.

## Implications for Roadmap

Based on the research, suggested phase structure:

### Phase 1: Policy and Persistence Backbone
**Rationale:** Every later screen depends on safe domain APIs, real persistence, and a defined time-formatting contract.
**Delivers:** `Foglet.Authz`; invite/oneliner/moderation schemas and contexts; `Timex ~> 3.7` wiring; a shared timestamp formatter; typed config additions such as oneliner policy where needed; supervised `Foglet.Oneliners` buffer.
**Addresses:** Real invite model, moderation audit/logging foundation, oneliner persistence, future board-scoped moderation.
**Avoids:** Screen-only auth, fake timezone support, cache-as-truth oneliners.

### Phase 2: Invite Enforcement and Shared Invite Workflow
**Rationale:** Invite surfaces are only credible once `invite_only` registration is real end to end.
**Delivers:** Transactional invite issue/redeem/revoke flow, row locking or equivalent concurrency control, registration integration in `Accounts`, replacement of the current register-screen stub, and one reusable `InvitesTab`.
**Uses:** `:crypto`, `Base`, Ecto/Postgres, existing runtime config accessors.
**Implements:** `Foglet.Invites`, shared TUI invite surface, actor-aware authorization.
**Avoids:** Burning invites on failed registration, arbitrary strings passing as invites, duplicated invite UIs.

### Phase 3: Account Preferences and Live Session Refresh
**Rationale:** The milestone's personalization goals depend on a trustworthy preferences pipeline before the main menu or operator surfaces can feel correct.
**Delivers:** Account screen, typed preference validation in `Accounts` and `Accounts.User`, immediate save feedback, active-session refresh for theme/time/config-derived state, and localized clock rendering from user preferences.
**Addresses:** Account table stakes, main-menu timestamp requirement, preference-driven theming.
**Avoids:** Reconnect-required changes, free-form timezone garbage, inconsistent timestamp rendering.

### Phase 4: Main Menu Oneliners and Social Polish
**Rationale:** Once preferences and the oneliner domain exist, the main menu can be upgraded without inventing new infrastructure.
**Delivers:** Minute tick integration, bounded recent-oneliners display, quick-post flow, moderation hide/delete hooks, and navigation affordances into Account/Moderation/Sysop based on role.
**Uses:** `Foglet.Oneliners`, PubSub, OTP timers, shared timestamp formatter.
**Implements:** DB-first oneliner writes plus in-memory recent buffer refresh.
**Avoids:** Chat-like noise, DB query on every repaint, unmoderated shoutbox state.

### Phase 5: Moderation and Sysop Workspaces
**Rationale:** These surfaces should be built last because they sit on top of auth, persistence, config, invite, and oneliner seams introduced earlier.
**Delivers:** Moderation tabs for queue/log/users/sanctions/boards, Sysop tabs for site/boards/limits/system/users, board-aware moderation queries, user administration, and conditional reuse of the shared `InvitesTab`.
**Addresses:** The remaining P1 features for moderator and sysop operations.
**Avoids:** Placeholder-heavy tabs, direct calls into ungated thread/post APIs, config controls the runtime cannot actually honor.

### Phase Ordering Rationale

- Phase 1 comes first because v1.1 currently lacks the safe domain seams the new surfaces would rely on.
- Phase 2 comes before the big UI shells because invite enforcement is a milestone-defining workflow with a known broken seam in the current register path.
- Phase 3 comes before Phase 4 so account saves immediately affect the active session and main-menu rendering.
- Phase 4 comes before full operator shells because oneliners and menu polish are low-cost once the underlying contracts exist.
- Phase 5 comes last because it should compose stable contexts rather than force business rules into `Foglet.TUI.App` or duplicated screen modules.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 5:** Exact sysop control set and moderator tab depth should be scoped carefully against existing typed config and board-management APIs.
- **Phase 5:** Board-scoped moderation UX needs explicit planning so the first screen does not accidentally encode global-only assumptions.

Phases with standard patterns (skip research-phase):
- **Phase 1:** `Timex ~> 3.7` wiring, typed preference validation, and context/schema additions are well understood.
- **Phase 2:** Transactional invite redemption and shared invite-tab reuse have clear patterns from both the codebase research and external references.
- **Phase 3:** Account preferences plus live session refresh are mostly local integration work, not a research problem.
- **Phase 4:** Bounded oneliners with DB authority and a small process cache fit established OTP/PubSub patterns.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | The recommended stack is mostly existing Foglet infrastructure plus one approved dependency addition, `Timex ~> 3.7`. |
| Features | MEDIUM | The milestone shape is clear, but exact moderation/sysop depth still requires product scoping discipline. |
| Architecture | HIGH | The proposed boundaries map directly onto current seams in `TUI.App`, registration, config, and domain contexts. |
| Pitfalls | HIGH | The major failure modes are already observable in the current codebase and have direct prevention strategies. |

**Overall confidence:** HIGH

### Gaps to Address

- Exact v1.1 definition of "functional moderation workspace": decide whether queue/log/users/sanctions/boards means scaffold-plus-basic actions or full operator workflows in this milestone.
- Exact first-pass sysop controls: only expose settings that already map cleanly to `Foglet.Config.Schema`, typed accessors, and live runtime consumers.
- Invite code visibility rules: confirm whether v1.1 ships with single-use only or includes multi-use plus notes/expiry in the first pass.
- Board-scoped moderation rollout: preserve scope-aware design now even if initial data and UI mostly exercise site-wide moderation.

## Sources

### Primary (HIGH confidence)
- `.planning/PROJECT.md` — milestone scope and current-codebase constraints
- `docs/ARCHITECTURE.md` — existing application boundaries and system model
- `docs/DATA_MODEL.md` — persisted concepts and future moderation/oneliner/invite fit
- `.planning/codebase/CONCERNS.md` — known codebase risks around auth and TUI boundaries
- `.planning/research/STACK.md` — stack recommendation synthesis
- `.planning/research/FEATURES.md` — milestone feature expectations and deferrals
- `.planning/research/ARCHITECTURE.md` — proposed module and screen boundaries
- `.planning/research/PITFALLS.md` — concrete failure modes and phase warnings
- Elixir `Calendar` docs — timezone and formatting contract
- Elixir `DateTime` docs — timezone conversion and UTC handling
- Timex docs — timezone handling and formatting support for Elixir

### Secondary (MEDIUM confidence)
- Synchronet documentation — compact defaults, user editing, moderation, and sysop patterns in terminal-native BBS software
- Citadel administration manual — invite/new-user and room/admin operating patterns
- Mystic BBS docs and feature references — moderator and new-user control patterns
- ENiGMA½ feature references — theme customization and oneliner/front-door affordances

### Tertiary (LOW confidence)
- None

---
*Research completed: 2026-04-23*
*Ready for roadmap: yes*
