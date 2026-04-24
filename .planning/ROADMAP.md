# Roadmap: Foglet BBS

## Milestones

- ✅ **v1.1 Operations Surfaces & Invites** - Phases 0-8, including inserted Phase 1.1 (shipped 2026-04-24). See [.planning/milestones/v1.1-ROADMAP.md](milestones/v1.1-ROADMAP.md).
- 🚧 **v1.2 Pre-Alpha Gap Closure** - Phases 9-14 (in progress).

## Overview

v1.2 closes the codebase-first gaps that would make currently visible Foglet flows misleading or unusable before pre-alpha. The milestone keeps Foglet SSH-first and TUI-first: day-to-day user and sysop workflows happen in the terminal, while domain rules, status changes, delivery decisions, and authorization remain in `Foglet.*` contexts. Webhook notifications, email digests, browser admin, and full moderation case management remain out of scope.

## Phases

**Phase Numbering:**
- Integer phases (9, 10, 11): Planned milestone work
- Decimal phases (10.1, 10.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

<details>
<summary>✅ v1.1 Operations Surfaces & Invites (Phases 0-8) - SHIPPED 2026-04-24</summary>

- [x] Phase 0: Screen Shells and Shared Surface Primitives (7/7 plans)
- [x] Phase 1: Authorization and Scope Backbone (4/4 plans)
- [x] Phase 1.1: Shared Modal Form Primitive (3/3 plans)
- [x] Phase 2: Sysop Config and Board Management (6/6 plans)
- [x] Phase 3: Invite Persistence and Registration Enforcement (3/3 plans)
- [x] Phase 4: Shared Invite Surface Activation (5/5 plans)
- [x] Phase 5: Account Preferences and Live Session Refresh (4/4 plans)
- [x] Phase 6: Chrome Clock and Main Menu Wiring (4/4 plans)
- [x] Phase 7: Oneliners and Main Menu Social Strip (3/3 plans)
- [x] Phase 8: Moderation Workspace Population and Scope-Aware Operations (4/4 plans)

</details>

### 🚧 v1.2 Pre-Alpha Gap Closure (In Progress)

**Milestone Goal:** Offered registration, account, posting, subscription, and sysop configuration flows are honest, operational, and enforce their rules before Foglet is presented as a credible pre-alpha.

- [ ] **Phase 9: Delivery Modes and Onboarding Honesty** - Verification, reset, and no-email onboarding paths match the configured delivery mode.
- [x] **Phase 10: User Status Administration** - Sysops can approve, reject, suspend, and reactivate users through actor-aware terminal and break-glass workflows. Sysop receive email upon new user awaiting approval when email is available. (completed 2026-04-24)
- [x] **Phase 11: Posting Policy Enforcement** - Board posting policy and locked-thread restrictions are enforced before board-server writes. (completed 2026-04-24)
- [ ] **Phase 12: Account SSH Key Management** - Users can manage SSH keys from Account and successful public-key auth records usage metadata (when last successful login with key was made).
- [x] **Phase 13: Board Subscription Management** - Users have real terminal paths to inspect and change board subscriptions. (completed 2026-04-24)
- [ ] **Phase 14: Launch Hygiene and Operator Notes** - Visible sysop settings, tests, copy, and operator docs are aligned for pre-alpha.

## Phase Details

### Phase 9: Delivery Modes and Onboarding Honesty
**Goal**: Users and operators experience verification, reset, and no-email onboarding flows that accurately reflect whether Foglet can send email.
**Depends on**: Phase 8
**Requirements**: MAIL-01, MAIL-02, MAIL-03, MAIL-04, MAIL-05, MAIL-06
**Success Criteria** (what must be TRUE):
  1. Operator can configure SMTP delivery mode or explicit no-email mode, and verification defaults behave accordingly.
  2. User receives or can request verification codes only through delivery paths Foglet actually attempts, with cooldown-aware feedback on the Verify screen.
  3. User can request password reset delivery when SMTP is configured, while operators retain the existing break-glass reset path.
  4. User-facing terminal copy never claims an email or notification was sent unless delivery was attempted.
  5. Operator can retrieve verification or reset delivery details through an explicit no-email workflow when SMTP is disabled.
**Plans**: 6 plans
Plans:
- [x] 09-01-PLAN.md — Delivery-mode config and Swoosh foundation
- [x] 09-02-PLAN.md — Verification delivery and Verify resend honesty
- [x] 09-03-PLAN.md — Terminal password-reset request flow
- [x] 09-04-PLAN.md — Sysop delivery-mode visibility and invalid-combo blocking
- [x] 09-05-PLAN.md — Break-glass reset task delivery-mode honesty
- [x] 09-06-PLAN.md — Cross-surface delivery-copy regression guard
**UI hint**: yes

### Phase 10: User Status Administration
**Goal**: Sysops can move users through pending, rejected, suspended, active, and reactivated states without dead-end registration modes.
**Depends on**: Phase 9
**Requirements**: MAIL-07, USER-01, USER-02, USER-03, USER-04, USER-05
**Success Criteria** (what must be TRUE):
  1. Sysop can list pending users from the Sysop `USERS` tab.
  2. Sysop can approve or reject pending users through actor-aware Accounts workflows.
  3. Sysop can suspend or reactivate existing users through actor-aware Accounts workflows.
  4. Operator can approve, reject, suspend, or reactivate users through a break-glass Mix task.
  5. Pending, rejected, suspended, and reactivated users see accurate login outcomes, TUI copy, and approval or rejection notification behavior when SMTP is configured.
**Plans**: 4 plans
Plans:
- [x] 10-01-PLAN.md — Rejected status persistence and Accounts transition boundary
- [x] 10-02-PLAN.md — Sysop USERS tab status administration
- [x] 10-03-PLAN.md — Break-glass user status Mix task
- [x] 10-04-PLAN.md — Approval/rejection delivery and status login copy
**UI hint**: yes

### Phase 11: Posting Policy Enforcement
**Goal**: Users can only create threads and replies when board policy and thread state permit the action.
**Depends on**: Phase 10
**Requirements**: POST-01, POST-02, POST-03, POST-04
**Success Criteria** (what must be TRUE):
  1. User can create a thread only when the board's `postable_by` policy permits their role.
  2. User can reply only when the board's `postable_by` policy permits their role and the thread is not locked.
  3. Rejected thread or reply attempts do not allocate board message numbers or persist posts.
  4. User sees a clear terminal error when submission is rejected by posting policy or locked-thread state.
**Plans**: 3 plans
Plans:
- [x] 11-01-PLAN.md — Thread posting-policy preflight and side-effect invariants
- [x] 11-02-PLAN.md — Reply posting-policy and locked-thread preflight
- [x] 11-03-PLAN.md — Terminal rejection copy for posting denials
**UI hint**: yes

### Phase 12: Account SSH Key Management
**Goal**: Users can manage their own SSH public keys from Account and use registered keys to authenticate.
**Depends on**: Phase 11
**Requirements**: KEYS-01, KEYS-02, KEYS-03, KEYS-04, KEYS-05
**Success Criteria** (what must be TRUE):
  1. User can open an Account `SSH KEYS` tab from the terminal UI.
  2. User can add a valid OpenSSH public key with a label and receive clear validation errors for invalid input.
  3. User can list their SSH keys with label, fingerprint, created time, and last-used time when available.
  4. User can revoke one of their own SSH keys from Account.
  5. User can authenticate with a registered SSH public key, and successful public-key authentication records last-used metadata.
**Plans**: 3 plans
Plans:
- [x] 12-01-PLAN.md — Accounts SSH key lifecycle and public-key auth metadata
- [ ] 12-02-PLAN.md — Account SSH KEYS terminal tab
- [ ] 12-03-PLAN.md — Phase 12 regression validation and precommit
**UI hint**: yes

### Phase 13: Board Subscription Management
**Goal**: Users and sysops can intentionally manage board subscriptions through real terminal workflows.
**Depends on**: Phase 12
**Requirements**: SUBS-01, SUBS-02, SUBS-03, SUBS-04, SUBS-05
**Success Criteria** (what must be TRUE):
  1. User can view subscribed and unsubscribed active boards in a board directory or equivalent board-management flow.
  2. User can subscribe to an active board from the terminal UI.
  3. User can unsubscribe from a board when doing so does not break required access assumptions.
  4. Sysop can inspect or adjust a user's board subscriptions from the Sysop surface or a break-glass Mix task.
  5. Empty board-list and new-thread states point to the real available subscription action instead of nonexistent sysop work.
**Plans**: 4 plans
Plans:
- [x] 13-01-PLAN.md — Board subscription policy and context boundary
- [x] 13-02-PLAN.md — Terminal board directory subscribe/unsubscribe workflow
- [x] 13-03-PLAN.md — Break-glass board subscription Mix task
- [x] 13-04-PLAN.md — Sysop board policy field and Phase 13 regression gate
**UI hint**: yes

### Phase 14: Launch Hygiene and Operator Notes
**Goal**: Pre-alpha-visible settings, tests, copy, and operator notes match the behavior Foglet actually supports.
**Depends on**: Phase 13
**Requirements**: HYGN-01, HYGN-02, HYGN-03
**Success Criteria** (what must be TRUE):
  1. Every visible Sysop configuration option changes real runtime behavior or renders as disabled or unavailable with honest copy.
  2. Pre-alpha blocker flows have focused tests for happy path, forbidden path, and user-facing error or copy behavior.
  3. Operator notes describe how to run Foglet in SMTP mode and no-email mode.
  4. A sysop reviewing the terminal surfaces sees no offered browser admin, webhook notification, email digest, or full case-management moderation workflow for this milestone.
**Plans**: 3 plans
Plans:
- [x] 14-01-PLAN.md — Sysop config accountability and blocker audit
- [x] 14-02-PLAN.md — Launch-copy and blocker-flow test audit
- [ ] 14-03-PLAN.md — Root README operator notes and hygiene gate
**UI hint**: yes

## Progress

**Execution Order:**
Phases execute in numeric order: 9 -> 10 -> 11 -> 12 -> 13 -> 14

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 0. Screen Shells and Shared Surface Primitives | v1.1 | 7/7 | Complete | 2026-04-24 |
| 1. Authorization and Scope Backbone | v1.1 | 4/4 | Complete | 2026-04-24 |
| 1.1 Shared Modal Form Primitive | v1.1 | 3/3 | Complete | 2026-04-24 |
| 2. Sysop Config and Board Management | v1.1 | 6/6 | Complete | 2026-04-24 |
| 3. Invite Persistence and Registration Enforcement | v1.1 | 3/3 | Complete | 2026-04-24 |
| 4. Shared Invite Surface Activation | v1.1 | 5/5 | Complete | 2026-04-24 |
| 5. Account Preferences and Live Session Refresh | v1.1 | 4/4 | Complete | 2026-04-24 |
| 6. Chrome Clock and Main Menu Wiring | v1.1 | 4/4 | Complete | 2026-04-24 |
| 7. Oneliners and Main Menu Social Strip | v1.1 | 3/3 | Complete | 2026-04-24 |
| 8. Moderation Workspace Population and Scope-Aware Operations | v1.1 | 4/4 | Complete | 2026-04-24 |
| 9. Delivery Modes and Onboarding Honesty | v1.2 | 0/TBD | Not started | - |
| 10. User Status Administration | v1.2 | 4/4 | Complete   | 2026-04-24 |
| 11. Posting Policy Enforcement | v1.2 | 3/3 | Complete   | 2026-04-24 |
| 12. Account SSH Key Management | v1.2 | 1/3 | In Progress|  |
| 13. Board Subscription Management | v1.2 | 4/4 | Complete    | 2026-04-24 |
| 14. Launch Hygiene and Operator Notes | v1.2 | 2/3 | In Progress|  |
