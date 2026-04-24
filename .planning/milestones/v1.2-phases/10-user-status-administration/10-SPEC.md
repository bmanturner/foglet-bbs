# Phase 10: User Status Administration - Specification

**Created:** 2026-04-24
**Ambiguity score:** 0.17 (gate: <= 0.20)
**Requirements:** 6 locked

## Goal

Sysops can approve, reject, suspend, and reactivate users through actor-aware terminal and break-glass workflows, with accurate login outcomes and SMTP-mode notifications for pending-user decisions.

## Background

Foglet already has `users.status` with `:active`, `:pending`, and `:suspended`. `Accounts.register_pending_user/1` creates pending users for sysop-approved registration mode, and login currently blocks pending and suspended users with terminal modals. There is no durable `:rejected` status, no actor-aware Accounts API for approving, rejecting, suspending, or reactivating users, and the Sysop `USERS` tab is still a placeholder. Existing break-glass Mix tasks cover user creation, role promotion, and password reset, but no status administration task exists.

Phase 9 owns the delivery-mode contract and Swoosh/no-email honesty. Phase 10 consumes that delivery-mode work to notify sysops when a user awaits approval and notify pending users when they are approved or rejected, without claiming email delivery when SMTP is unavailable.

## Requirements

1. **Durable rejected status**: Rejected registration requests are represented by a durable `:rejected` user status.
   - Current: `Foglet.Accounts.User` and the database status constraint allow only `:active`, `:pending`, and `:suspended`.
   - Target: `users.status` accepts `:rejected`; rejected users remain non-deleted rows so handles/emails stay reserved and login can report the correct outcome.
   - Acceptance: Schema, migration, and focused tests prove `:rejected` can be persisted, invalid statuses are rejected, and rejected users are not treated as deleted users.

2. **Actor-aware status transitions**: `Foglet.Accounts` exposes authorized status transition APIs for pending approval decisions and active account suspension management.
   - Current: Status can be changed only through direct changesets or ad hoc Repo updates in tests; no public actor-aware transition API exists.
   - Target: Sysop actors can perform exactly these transitions through Accounts: `pending -> active`, `pending -> rejected`, `active -> suspended`, and `suspended -> active`. Invalid transitions and deleted users are rejected without side effects.
   - Acceptance: Domain tests cover each valid transition, non-sysop forbidden attempts, invalid transition attempts, deleted-user rejection, and unchanged persisted state after rejected calls.

3. **Sysop USERS terminal administration**: The Sysop `USERS` tab lists and administers pending and existing non-deleted users enough to complete the locked status transitions.
   - Current: The Sysop screen renders `User administration will arrive in a later phase.` for `USERS`.
   - Target: Sysops can list pending users, approve or reject a pending user, list or select existing non-deleted users by status, suspend active users, and reactivate suspended users from the terminal UI.
   - Acceptance: TUI tests prove the `USERS` tab renders pending, active, suspended, and rejected users with accurate status labels; valid actions call the Accounts transition API; invalid or forbidden action results are shown as terminal copy instead of silently failing.

4. **Break-glass status task**: Operators can perform the same status transitions through a break-glass Mix task.
   - Current: Mix tasks exist for creating users, promoting roles, and resetting passwords, but not for approval, rejection, suspension, or reactivation.
   - Target: A status administration task accepts a user handle and target status `active`, `rejected`, or `suspended`; it applies the same valid transition rules as Accounts and prints pass/fail operator copy.
   - Acceptance: Mix-task tests prove pending users can be approved or rejected, active users can be suspended, suspended users can be reactivated, invalid transitions fail with a non-success result, and unknown/deleted users are not changed.

5. **SMTP-mode approval notifications**: SMTP-mode delivery sends the required user-status notifications without making false delivery claims in no-email mode.
   - Current: Pending registration copy can mention approval notification, but no approval/rejection notification path exists; sysop pending-user notification is also missing.
   - Target: When SMTP delivery is configured, sysops receive notification that a new user awaits approval, and pending users receive approval or rejection notification after the corresponding decision. When SMTP is unavailable, user-facing and operator-facing copy does not claim email was sent.
   - Acceptance: Tests prove SMTP mode attempts sysop pending-user notification and user approval/rejection notification; no-email mode performs the status transition without email claims; delivery failures do not roll back the status transition unless the implementation explicitly documents and tests a stricter failure policy.

6. **Accurate login outcomes and copy**: Pending, rejected, suspended, active, and reactivated users receive accurate terminal login outcomes.
   - Current: Pending and suspended users are blocked; rejected status does not exist; reactivation behavior is only implicit in a status change back to active.
   - Target: Active and reactivated users can proceed according to normal confirmation and verification rules; pending users see pending-approval copy; rejected users see rejection copy; suspended users see suspension copy.
   - Acceptance: Login-screen tests cover pending, rejected, suspended, active, and reactivated users, and assert that modal/copy text matches the persisted account state without promising unavailable notification delivery.

## Boundaries

**In scope:**
- Add durable `:rejected` status support to schema, migration, constraints, and tests.
- Actor-aware Accounts APIs for `pending -> active`, `pending -> rejected`, `active -> suspended`, and `suspended -> active`.
- Sysop `USERS` tab listing and actions needed for pending decisions and suspend/reactivate management.
- One break-glass status administration Mix task or equivalent operator command surface for the same transition set.
- SMTP-mode notification attempts for new pending users and approval/rejection decisions.
- Accurate TUI login outcomes and copy for pending, rejected, suspended, active, and reactivated users.
- Focused domain, TUI, Mix-task, delivery, and login tests for MAIL-07 and USER-01 through USER-05.

**Out of scope:**
- `rejected -> active` appeals or reopening rejected registrations - no appeal workflow is specified for pre-alpha.
- `suspended -> rejected` or arbitrary status editing - this phase locks a small transition graph to avoid case-management sprawl.
- Status changes for soft-deleted users - deleted users remain outside normal account administration.
- Rich user history, audit timeline, invite history, moderation history, or case-management views - these are v2 administration scope.
- Bulk actions, search/filter polish, pagination polish, profile editing, role changes, and board subscription controls - these are adjacent admin features, not required for status administration.
- End-user browser administration or approval workflows - Foglet remains SSH-first/TUI-first.
- Webhook notifications, email digests, delivery retry queues, and outbound delivery logs - these are v2 notification features.

## Constraints

- Status mutations must route through `Foglet.Accounts` or another `Foglet.*` context boundary, not direct Repo calls from TUI render or event code.
- Actor-triggered status mutations must use `Bodyguard.permit/4` before side effects.
- Programmatically set foreign keys or actor metadata before changeset construction where needed; do not make internal fields caller-castable for convenience.
- Login and TUI copy must not claim email notification unless the Swoosh delivery path is configured and attempted.
- Notification behavior must consume the delivery-mode contract from Phase 9; SMTP credentials or secrets must not be stored in DB-backed configuration.
- The Sysop `USERS` tab must stay terminal-native and must not introduce browser workflows.
- Tests must avoid `Process.sleep/1`; synchronize status or delivery behavior through explicit assertions, messages, or supervised processes.

## Acceptance Criteria

- [ ] `users.status` supports `active`, `pending`, `rejected`, and `suspended`, and rejects other values.
- [ ] `Foglet.Accounts` exposes actor-aware APIs for approve, reject, suspend, and reactivate operations.
- [ ] Only sysop actors can perform user status transitions through normal context APIs.
- [ ] `pending -> active`, `pending -> rejected`, `active -> suspended`, and `suspended -> active` succeed and persist the expected status.
- [ ] Invalid transitions, non-sysop actors, unknown users, and deleted users fail without changing persisted status.
- [ ] Sysop `USERS` tab lists pending users and allows approve/reject actions.
- [ ] Sysop `USERS` tab allows selecting non-deleted active or suspended users for suspend/reactivate actions.
- [ ] Break-glass Mix task can approve, reject, suspend, and reactivate users using the same transition rules.
- [ ] SMTP mode attempts notification to sysops when a user is awaiting approval.
- [ ] SMTP mode attempts notification to pending users when approved or rejected.
- [ ] No-email mode does not display or print copy claiming approval-related email was sent.
- [ ] Login outcomes and terminal copy are accurate for pending, rejected, suspended, active, and reactivated users.
- [ ] Focused tests cover MAIL-07 and USER-01 through USER-05.

## Ambiguity Report

| Dimension           | Score | Min   | Status | Notes |
|---------------------|-------|-------|--------|-------|
| Goal Clarity        | 0.90  | 0.75  | met    | Status administration, notification obligations, and login outcomes are specific. |
| Boundary Clarity    | 0.84  | 0.70  | met    | Transition graph, excluded admin polish, and v2 administration scope are explicit. |
| Constraint Clarity  | 0.75  | 0.65  | met    | Context boundary, authorization, SSH-first UI, delivery-mode honesty, and test constraints are locked. |
| Acceptance Criteria | 0.82  | 0.70  | met    | Criteria cover status persistence, actor rules, TUI, Mix task, notifications, and login copy. |
| **Ambiguity**       | 0.17  | <=0.20| met    | Weighted clarity is 0.83. |

Status: met = dimension meets minimum, below = planner treats as assumption.

## Interview Log

| Round | Perspective | Question summary | Decision locked |
|-------|-------------|------------------|-----------------|
| 1 | Researcher | Should rejected be durable status or represented another way? | Rejected is a durable `users.status` value, not soft deletion. |
| 1 | Researcher | Which approval notifications are in scope? | Both sysop pending-user notification and pending-user approval/rejection notification are in scope when SMTP is configured. |
| 1 | Researcher | What is the minimum Sysop USERS deliverable? | Pending queue plus active/suspended user management in the same terminal surface. |
| 2 | Researcher + Simplifier | Which status transitions are valid? | Lock only `pending -> active`, `pending -> rejected`, `active -> suspended`, and `suspended -> active`. |
| 2 | Researcher + Simplifier | What break-glass task shape should exist? | Use one status administration task or equivalent command surface with target status and shared transition validation. |
| 2 | Researcher + Simplifier | How broad should the user list be? | Enough list/select behavior to administer non-deleted users by status; exclude search, pagination polish, histories, role changes, and subscriptions. |

---

*Phase: 10-user-status-administration*
*Spec created: 2026-04-24*
*Next step: $gsd-discuss-phase 10 - implementation decisions (how to build what is specified above)*
