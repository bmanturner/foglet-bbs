# Requirements: Foglet BBS v1.2 Pre-Alpha Gap Closure

**Defined:** 2026-04-24
**Core Value:** A user can SSH into a living, reliable BBS and participate in conversations through a terminal-native experience that feels like arriving somewhere.

## v1 Requirements

### Email & Onboarding

- [ ] **MAIL-01**: Operator can configure whether Foglet is in SMTP delivery mode or explicit no-email mode, and the verification/default behavior matches that mode.
- [ ] **MAIL-02**: User receives an email verification code after registration when SMTP delivery is configured and email verification is required.
- [ ] **MAIL-03**: User can request a fresh verification code from the Verify screen with cooldown-aware feedback.
- [ ] **MAIL-04**: User can receive a password reset email when SMTP delivery is configured, while the existing Mix task remains available as a break-glass path.
- [ ] **MAIL-05**: User-facing TUI copy never claims a code or notification was emailed unless Foglet actually attempted delivery.
- [ ] **MAIL-06**: Operator can retrieve verification, reset, or pending-approval delivery details through an explicit no-email/operator-visible workflow when SMTP delivery is disabled.
- [ ] **MAIL-07**: Pending user receives approval or rejection notification by email when SMTP delivery is configured.

### User Status Administration

- [ ] **USER-01**: Sysop can list pending users from the Sysop `USERS` tab.
- [ ] **USER-02**: Sysop can approve or reject a pending user through an actor-aware Accounts context API.
- [ ] **USER-03**: Sysop can suspend or reactivate an existing user through an actor-aware Accounts context API.
- [ ] **USER-04**: Sysop can approve, reject, suspend, or reactivate users through a break-glass Mix task.
- [ ] **USER-05**: Pending, rejected, suspended, and reactivated users see accurate login outcomes and TUI copy.

### Posting Policy Enforcement

- [ ] **POST-01**: User can create a thread only when the board's `postable_by` policy permits their role.
- [ ] **POST-02**: User can reply to a thread only when the board's `postable_by` policy permits their role.
- [ ] **POST-03**: User cannot reply to a locked thread through normal context or TUI posting paths.
- [ ] **POST-04**: User sees a clear terminal error when thread or reply submission is rejected by posting policy or thread lock state.

### SSH Key Management

- [ ] **KEYS-01**: User can open an Account `SSH KEYS` tab from the terminal UI.
- [ ] **KEYS-02**: User can add a valid OpenSSH public key with a label from Account.
- [ ] **KEYS-03**: User can list their SSH keys with label, fingerprint, created time, and last-used time when available.
- [ ] **KEYS-04**: User can revoke one of their SSH keys from Account.
- [ ] **KEYS-05**: User can authenticate with a registered SSH public key, and successful public-key authentication records last-used metadata.

### Board Subscriptions

- [ ] **SUBS-01**: User can view subscribed and unsubscribed active boards in a board directory or equivalent board-management flow.
- [ ] **SUBS-02**: User can subscribe to an active board from the terminal UI.
- [ ] **SUBS-03**: User can unsubscribe from a board when doing so will not break required access assumptions.
- [ ] **SUBS-04**: Sysop can inspect or adjust a user's board subscriptions from the Sysop surface or a break-glass Mix task.
- [ ] **SUBS-05**: Empty board-list and new-thread states tell the user what action is actually available, instead of pointing to nonexistent sysop work.

### Launch Hygiene

- [ ] **HYGN-01**: Every currently visible Sysop configuration option either changes real runtime behavior or renders as disabled/unavailable with honest copy.
- [ ] **HYGN-02**: Pre-alpha blocker flows have focused tests for happy path, forbidden path, and user-facing error/copy behavior.
- [ ] **HYGN-03**: Pre-alpha docs or operator notes describe how to run Foglet in SMTP mode and no-email mode.

## v2 Requirements

### Notifications & Delivery

- **NTFY-01**: User can configure webhook notification delivery for selected events.
- **NTFY-02**: User can opt into recurring email digests.
- **NTFY-03**: Operator can inspect outbound delivery logs and retry failed deliveries.

### Administration

- **ADMN-01**: Sysop can manage richer user histories, invite histories, and moderation histories from one user detail pane.
- **ADMN-02**: Sysop can bulk-assign board subscriptions by role or cohort.

## Out of Scope

| Feature | Reason |
|---------|--------|
| End-user browser workflows | Foglet remains SSH-first; Phoenix stays operational infrastructure for this milestone. |
| Webhook notifications | Relevant seed exists, but this milestone is about making existing email/onboarding claims operational before adding another delivery channel. |
| Email digests and marketing-style notification reach | Pre-alpha needs transactional delivery honesty, not engagement campaigns. |
| Full case-management moderation | The gap is posting-policy enforcement and user status administration, not a broader moderation product expansion. |
| Multi-node delivery guarantees | Current correctness target is the single-node Phoenix/OTP/Postgres deployment model already used by Foglet. |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| MAIL-01 | Phase 9 | Pending |
| MAIL-02 | Phase 9 | Pending |
| MAIL-03 | Phase 9 | Pending |
| MAIL-04 | Phase 9 | Pending |
| MAIL-05 | Phase 9 | Pending |
| MAIL-06 | Phase 9 | Pending |
| MAIL-07 | Phase 10 | Pending |
| USER-01 | Phase 10 | Pending |
| USER-02 | Phase 10 | Pending |
| USER-03 | Phase 10 | Pending |
| USER-04 | Phase 10 | Pending |
| USER-05 | Phase 10 | Pending |
| POST-01 | Phase 11 | Pending |
| POST-02 | Phase 11 | Pending |
| POST-03 | Phase 11 | Pending |
| POST-04 | Phase 11 | Pending |
| KEYS-01 | Phase 12 | Pending |
| KEYS-02 | Phase 12 | Pending |
| KEYS-03 | Phase 12 | Pending |
| KEYS-04 | Phase 12 | Pending |
| KEYS-05 | Phase 12 | Pending |
| SUBS-01 | Phase 13 | Pending |
| SUBS-02 | Phase 13 | Pending |
| SUBS-03 | Phase 13 | Pending |
| SUBS-04 | Phase 13 | Pending |
| SUBS-05 | Phase 13 | Pending |
| HYGN-01 | Phase 14 | Pending |
| HYGN-02 | Phase 14 | Pending |
| HYGN-03 | Phase 14 | Pending |

**Coverage:**
- v1 requirements: 29 total
- Mapped to phases: 29
- Unmapped: 0

---
*Requirements defined: 2026-04-24*
*Last updated: 2026-04-24 after milestone v1.2 initial definition*
