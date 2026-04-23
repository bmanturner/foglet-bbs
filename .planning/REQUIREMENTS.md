# Requirements: Foglet BBS

**Defined:** 2026-04-23
**Core Value:** A user can SSH into a living, reliable BBS and participate in conversations through a terminal-native experience that feels like arriving somewhere.

## v1 Requirements

### Account & Preferences

- [ ] **ACCT-01**: User can open a private Account screen from the TUI main menu.
- [ ] **ACCT-02**: User can edit private profile details from Account, including `location`, `tagline`, and `real_name`.
- [ ] **ACCT-03**: User can choose a valid IANA timezone used for Foglet's user-facing timestamp rendering, and new accounts default to the system timezone until changed.
- [ ] **ACCT-04**: User can choose 12-hour or 24-hour time display from Account, and new accounts default to 12-hour time until changed.
- [ ] **ACCT-05**: User can choose a registered Foglet TUI theme from Account.
- [ ] **ACCT-06**: User sees saved Account preference changes reflected in the active session without reconnecting.

### Invite Workflows

- [ ] **INVT-01**: Authorized actor can open a shared `INVITES` tab from Account, Moderation, or Sysop according to `invite_code_generators`.
- [ ] **INVT-02**: Authorized actor can generate a single-use invite code and view it once for sharing.
- [ ] **INVT-03**: Authorized actor can review invite status including issuer, created time, consumed state, and revocation state.
- [ ] **INVT-04**: Authorized actor can revoke an unused invite code.
- [ ] **INVT-05**: Registration in `invite_only` mode accepts only persisted, unrevoked, unconsumed invite codes.
- [ ] **INVT-06**: Sysop can set invite generation policy to `sysop_only`, `mods`, or `any_user`.
- [ ] **INVT-07**: Sysop can set a per-user invite generation limit to unlimited or a numeric cap when `any_user` invites are enabled.

### Moderation

- [ ] **MODR-01**: Moderator can open a Moderation workspace with `QUEUE`, `LOG`, `USERS`, `SANCTIONS`, and `BOARDS` tabs.
- [ ] **MODR-02**: Moderation workspace only shows actions and data for scopes the current operator is authorized to manage.
- [ ] **MODR-03**: Moderation actions exposed in v1.1 are enforced through actor-aware authorization rather than screen-only visibility checks.
- [ ] **MODR-04**: If `invite_code_generators` is `mods`, moderator workspace includes the shared `INVITES` tab with unlimited invite generation.
- [ ] **MODR-05**: Moderator can hide an oneliner through moderation tooling so abusive shoutbox content can be removed without direct database edits.

### Sysop Operations

- [ ] **SYSO-01**: Sysop can open a Sysop workspace with `SITE`, `BOARDS`, `LIMITS`, `SYSTEM`, and `USERS` tabs.
- [ ] **SYSO-02**: Sysop can edit seeded runtime config values for registration, invite policy, and limits from the Sysop workspace.
- [ ] **SYSO-03**: Sysop can create, update, list, and archive categories and boards from the `BOARDS` tab.
- [ ] **SYSO-04**: Sysop can inspect system details from the `SYSTEM` tab.
- [ ] **SYSO-05**: If `invite_code_generators` is `sysop_only`, Sysop workspace includes the shared `INVITES` tab with unlimited invite generation.

### Main Menu & Oneliners

- [ ] **MENU-01**: User sees current date and time in the top-right screen chrome rendered in their saved timezone and 12h/24h preference, defaulting to system timezone and 12-hour time when no user preference has been saved yet.
- [ ] **MENU-02**: Main menu time display refreshes at least once per minute without requiring reconnect.
- [ ] **ONEL-01**: User can view recent oneliners on the main menu.
- [ ] **ONEL-02**: User can post a short oneliner from the main menu.
- [ ] **ONEL-03**: Oneliner posts persist across restart and respect a bounded maximum length.

## v2 Requirements

### Account & Preferences

- **ACCT-07**: User can manage password, email, and SSH keys from Account.
- **ACCT-08**: User sees live previews and inheritance hints for theme and time-display settings.

### Invite Workflows

- **INVT-08**: Authorized actor can issue invite codes with expiry, notes, and configurable multi-use limits.
- **INVT-09**: Sysop can inspect invite history across all issuers with richer filtering and search.

### Moderation & Sysop

- **MODR-06**: Sysop can assign and revoke board-scoped moderator access from the TUI.
- **MODR-07**: Moderator can work a fuller report queue with richer target detail and sanction flows.
- **SYSO-06**: Sysop can edit additional runtime settings such as oneliner policy, theme allowlist, and retention windows once they have typed runtime consumers.

### Main Menu & Presence

- **MENU-03**: Main menu shows additional community-presence signals such as online counts, recent callers, or rotating status text.
- **ONEL-04**: Main menu oneliners support richer moderation, browsing, and retention controls.

## Out of Scope

| Feature | Reason |
|---------|--------|
| End-user web administration UI | Foglet remains terminal-first; this milestone deepens the SSH/TUI surface instead of adding a browser-facing admin product |
| Referral trees, campaign invites, or auto-approval onboarding | Invite workflows in v1.1 are explicit operator-created access control, not growth mechanics |
| Full chat-like shoutbox behavior | The main-menu oneliner strip is meant to add atmosphere, not become a second real-time chat system |
| Broad sysop controls for unschematized config keys | v1.1 should expose only settings with typed config accessors and live runtime effect |
| Rewriting moderation around global-only moderators | v1.1 must preserve room for board-scoped moderation instead of locking in global assumptions |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| ACCT-01 | Phase 0 | Pending |
| ACCT-02 | Phase 5 | Pending |
| ACCT-03 | Phase 5 | Pending |
| ACCT-04 | Phase 5 | Pending |
| ACCT-05 | Phase 5 | Pending |
| ACCT-06 | Phase 5 | Pending |
| INVT-01 | Phase 4 | Pending |
| INVT-02 | Phase 3 | Pending |
| INVT-03 | Phase 3 | Pending |
| INVT-04 | Phase 3 | Pending |
| INVT-05 | Phase 3 | Pending |
| INVT-06 | Phase 2 | Pending |
| INVT-07 | Phase 2 | Pending |
| MODR-01 | Phase 0 | Pending |
| MODR-02 | Phase 1 | Pending |
| MODR-03 | Phase 1 | Pending |
| MODR-04 | Phase 4 | Pending |
| MODR-05 | Phase 8 | Pending |
| SYSO-01 | Phase 0 | Pending |
| SYSO-02 | Phase 2 | Pending |
| SYSO-03 | Phase 2 | Pending |
| SYSO-04 | Phase 2 | Pending |
| SYSO-05 | Phase 4 | Pending |
| MENU-01 | Phase 6 | Pending |
| MENU-02 | Phase 6 | Pending |
| ONEL-01 | Phase 7 | Pending |
| ONEL-02 | Phase 7 | Pending |
| ONEL-03 | Phase 7 | Pending |

**Coverage:**
- v1 requirements: 28 total
- Mapped to phases: 28
- Unmapped: 0

---
*Requirements defined: 2026-04-23*
*Last updated: 2026-04-23 after milestone v1.1 initial definition*
