# Roadmap: Foglet BBS v1.1 Operations Surfaces & Invites

## Overview

This milestone turns Foglet's SSH client into a fuller operations surface in smaller, safer slices. The work starts with screen shells and shared UI primitives, then adds actor-aware policy, typed sysop controls, real invite persistence, reusable invite activation, account preferences with live session refresh, chrome clock wiring, persistent oneliners, and finally the populated moderation workspace.

## Phases

**Phase Numbering:**
- Integer phases (`0`, `1`, `2`...): planned milestone work
- Decimal phases (`2.1`, `2.2`): urgent insertions if needed later

- [ ] **Phase 0: Screen Shells and Shared Surface Primitives** - Scaffold Account, Moderation, Sysop, and shared tab/screen state without shipping fake business behavior.
- [ ] **Phase 1: Authorization and Scope Backbone** - Add actor-aware policy and future-safe moderation scope rules before operator actions ship.
- [ ] **Phase 2: Sysop Config and Board Management** - Expose typed site policy, invite controls, board/category lifecycle, and system details from the TUI.
- [ ] **Phase 3: Invite Persistence and Registration Enforcement** - Make invite-only onboarding real through persisted single-use invites and transactional redemption.
- [ ] **Phase 4: Shared Invite Surface Activation** - Turn on the reusable `INVITES` tab across allowed surfaces according to config and role.
- [ ] **Phase 5: Account Preferences and Live Session Refresh** - Let users manage private profile and display defaults with immediate session updates.
- [ ] **Phase 6: Chrome Clock and Main Menu Wiring** - Wire the top-right chrome clock and main-menu navigation to the new preference and role model.
- [ ] **Phase 7: Oneliners and Main Menu Social Strip** - Add persistent oneliners and quick posting while keeping the menu lightweight.
- [ ] **Phase 8: Moderation Workspace Population and Scope-Aware Operations** - Populate the moderation workspace with real, actor-aware data and actions.

## Phase Details

### Phase 0: Screen Shells and Shared Surface Primitives
**Goal**: Foglet has navigable Account, Moderation, and Sysop shells plus reusable tab and state primitives, but no fake persistence or placeholder business actions that later phases must undo.
**Depends on**: Nothing (first phase)
**Requirements**: ACCT-01, MODR-01, SYSO-01
**Success Criteria** (what must be TRUE):
  1. User can navigate from the main menu into read-only shell versions of Account, Moderation, and Sysop according to current role visibility.
  2. Account, Moderation, and Sysop render their milestone tab sets with stable focus, tab switching, placeholder, loading, and error states.
  3. A shared surface primitive exists for the reusable `INVITES` tab so later phases do not duplicate invite-tab UI/state across screens.
  4. Screen shell work does not introduce fake save actions or fake moderation/invite behavior that bypasses real domain logic.
**Plans**: 7 plans
  - [x] 00-01-PLAN.md — Wave 0: write failing tests for Account, Moderation, Sysop shells and shared InvitesSurface (plus main_menu/app/layout_smoke extensions)
  - [x] 00-02-PLAN.md — Wave 1: shared INVITES surface primitive (InvitesSurface + InvitesState)
  - [x] 00-03-PLAN.md — Wave 1: App routing seams for :account/:moderation/:sysop + ShellVisibility helper
  - [ ] 00-04-PLAN.md — Wave 2: Account shell (PROFILE/PREFS + conditional INVITES via shared surface) [ACCT-01]
  - [ ] 00-05-PLAN.md — Wave 2: Moderation shell (QUEUE/LOG/USERS/SANCTIONS/BOARDS, role-gated) [MODR-01]
  - [ ] 00-06-PLAN.md — Wave 2: Sysop shell (SITE/BOARDS/LIMITS/SYSTEM/USERS, role-gated) [SYSO-01]
  - [ ] 00-07-PLAN.md — Wave 3: MainMenu role-gated entries + `mix precommit` gate
**UI hint**: yes

### Phase 1: Authorization and Scope Backbone
**Goal**: Operator actions are gated by actor-aware, scope-aware policy before sysop and moderation surfaces gain real behavior.
**Depends on**: Phase 0
**Requirements**: MODR-02, MODR-03
**Success Criteria** (what must be TRUE):
  1. Moderation and operator actions are enforced through actor-aware authorization rather than screen-only visibility checks.
  2. The authorization seam supports at least `:site` and `{:board, board_id}` scopes so future board-scoped moderation does not require API rewrites.
  3. Unauthorized operator actions return explicit forbidden results instead of silently succeeding or relying on hidden UI controls.
**Plans**: TBD
**UI hint**: no

### Phase 2: Sysop Config and Board Management
**Goal**: Sysops can manage typed site policy, invite controls, board/category lifecycle, and system details from the TUI on top of the new authz backbone.
**Depends on**: Phase 1
**Requirements**: INVT-06, INVT-07, SYSO-02, SYSO-03, SYSO-04
**Success Criteria** (what must be TRUE):
  1. Sysop can change seeded runtime config values for registration, invite policy, and operational limits from the TUI, and unschematized config keys are not exposed there.
  2. Invite generation policy can be set to `sysop_only`, `mods`, or `any_user`, and `any_user` mode can use either unlimited or numeric per-user invite caps.
  3. Sysop can create, update, list, and archive categories and boards from the `BOARDS` tab without direct database edits.
  4. Sysop can inspect current system details from the `SYSTEM` tab.
**Plans**: TBD
**UI hint**: yes

### Phase 3: Invite Persistence and Registration Enforcement
**Goal**: Invite-only onboarding is real, transactional, and single-use before the shared invite UI becomes operational.
**Depends on**: Phase 2
**Requirements**: INVT-02, INVT-03, INVT-04, INVT-05
**Success Criteria** (what must be TRUE):
  1. Authorized actor can generate a single-use invite code and the system persists issuer, created time, consumed state, and revocation state.
  2. Authorized actor can review invite status and revoke an unused invite code through real domain behavior.
  3. Registration in `invite_only` mode accepts only persisted, unrevoked, unconsumed invite codes.
  4. Successful registration consumes an invite exactly once, and failed registration attempts do not burn invite codes.
**Plans**: TBD
**UI hint**: no

### Phase 4: Shared Invite Surface Activation
**Goal**: The reusable `INVITES` tab becomes a live feature in each allowed surface according to invite policy and role.
**Depends on**: Phase 3
**Requirements**: INVT-01, MODR-04, SYSO-05
**Success Criteria** (what must be TRUE):
  1. Authorized actor can open the shared `INVITES` tab from Account, Moderation, or Sysop according to `invite_code_generators`.
  2. When invite generation is restricted to sysops or moderators, the allowed operator invite surfaces provide unlimited invite generation for the permitted role.
  3. Invite-tab behavior is shared across surfaces rather than implemented in separate duplicated flows.
**Plans**: TBD
**UI hint**: yes

### Phase 5: Account Preferences and Live Session Refresh
**Goal**: Users can manage private profile and presentation settings from Account and see those changes reflected in the active session immediately.
**Depends on**: Phase 4
**Requirements**: ACCT-02, ACCT-03, ACCT-04, ACCT-05, ACCT-06
**Success Criteria** (what must be TRUE):
  1. User can edit private profile details from Account, including `location`, `tagline`, and `real_name`.
  2. User can choose a valid IANA timezone used for Foglet's user-facing timestamp rendering, and new accounts default to the system timezone until changed.
  3. User can choose 12-hour or 24-hour time display plus a registered Foglet theme from Account, and new accounts default to 12-hour time until changed.
  4. User sees saved Account preference changes reflected in the active session without reconnecting.
**Plans**: TBD
**UI hint**: yes

### Phase 6: Chrome Clock and Main Menu Wiring
**Goal**: The main menu and screen chrome reflect the new preference model and expose the new operational surfaces cleanly.
**Depends on**: Phase 5
**Requirements**: MENU-01, MENU-02
**Success Criteria** (what must be TRUE):
  1. User sees current date and time in the top-right screen chrome rendered in their saved timezone and 12h/24h preference, defaulting to system timezone and 12-hour time when no user preference has been saved yet.
  2. Main-menu time display refreshes at least once per minute without requiring reconnect.
  3. Main-menu navigation cleanly exposes Account, Moderation, and Sysop entry points according to current role and policy state.
**Plans**: TBD
**UI hint**: yes

### Phase 7: Oneliners and Main Menu Social Strip
**Goal**: The main menu gains a persistent, bounded social strip that feels alive without becoming chat-like noise.
**Depends on**: Phase 6
**Requirements**: ONEL-01, ONEL-02, ONEL-03
**Success Criteria** (what must be TRUE):
  1. User can view recent oneliners on the main menu.
  2. User can post a short oneliner from the main menu.
  3. Oneliner posts persist across restart and respect a bounded maximum length.
**Plans**: TBD
**UI hint**: yes

### Phase 8: Moderation Workspace Population and Scope-Aware Operations
**Goal**: Moderators can work from a populated workspace whose visible data and available actions stay inside authorized scope and include oneliner moderation.
**Depends on**: Phases 1 and 7
**Requirements**: MODR-05
**Success Criteria** (what must be TRUE):
  1. The moderation workspace shows real queue, log, user, sanction, and board data within the current operator's authorized scope.
  2. Moderator can hide an oneliner through moderation tooling so abusive shoutbox content can be removed without direct database edits.
  3. Populated moderation behavior preserves room for future board-scoped moderation instead of assuming every moderator is global.
**Plans**: TBD
**UI hint**: yes

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 0. Screen Shells and Shared Surface Primitives | 0/TBD | Not started | - |
| 1. Authorization and Scope Backbone | 0/TBD | Not started | - |
| 2. Sysop Config and Board Management | 0/TBD | Not started | - |
| 3. Invite Persistence and Registration Enforcement | 0/TBD | Not started | - |
| 4. Shared Invite Surface Activation | 0/TBD | Not started | - |
| 5. Account Preferences and Live Session Refresh | 0/TBD | Not started | - |
| 6. Chrome Clock and Main Menu Wiring | 0/TBD | Not started | - |
| 7. Oneliners and Main Menu Social Strip | 0/TBD | Not started | - |
| 8. Moderation Workspace Population and Scope-Aware Operations | 0/TBD | Not started | - |
