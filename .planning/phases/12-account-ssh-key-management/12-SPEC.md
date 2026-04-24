# Phase 12: Account SSH Key Management - Specification

**Created:** 2026-04-24
**Ambiguity score:** 0.13 (gate: <= 0.20)
**Requirements:** 6 locked

## Goal

Users can add, inspect, revoke, and use their own registered SSH public keys from the terminal Account surface, and successful public-key authentication records last-used metadata.

## Background

Foglet already has durable `ssh_keys` storage, a `Foglet.Accounts.SSHKey` schema, key fingerprint computation from OpenSSH public-key text, and `Foglet.Accounts.register_ssh_key/2`, `list_ssh_keys/1`, and `get_user_by_public_key/1`. The database includes `ssh_keys.last_used_at`, but successful key authentication does not update it. The SSH daemon already stashes offered public keys through `Foglet.SSH.KeyCB` and `Foglet.SSH.PubkeyStash`; `Foglet.SSH.CLIHandler` resolves the stashed key through `Accounts.get_user_by_public_key/1` and starts the session for the matched user.

The Account TUI currently exposes `PROFILE`, `PREFS`, and conditionally `INVITES`; there is no `SSH KEYS` tab, no Account form for adding keys, no key list display, and no self-service revoke action. Existing key APIs are not yet actor-aware for self-service ownership checks, and there is no revoke API.

## Requirements

1. **Account SSH KEYS tab**: Authenticated users can open an Account `SSH KEYS` tab from the terminal UI.
   - Current: `Foglet.TUI.Screens.Account.State` builds `PROFILE` and `PREFS` tabs, with conditional `INVITES`; no SSH key tab exists.
   - Target: Every authenticated Account screen includes an `SSH KEYS` tab that renders without direct Repo access and fits the existing terminal tab/navigation pattern.
   - Acceptance: TUI tests prove the Account screen exposes `SSH KEYS` for a normal authenticated user, tab navigation can select it, and rendering works when the user has zero keys.

2. **Self-service key registration**: Users can add a valid OpenSSH public key with a label from Account.
   - Current: `Accounts.register_ssh_key/2` can insert a key for a user and computes the fingerprint, but there is no Account UI flow for users to submit a label and public key.
   - Target: The `SSH KEYS` tab provides a terminal-native add flow for label plus OpenSSH public-key text, routes persistence through `Foglet.Accounts`, and displays clear validation errors for invalid key text, missing fields, duplicate fingerprint, or duplicate label.
   - Acceptance: Domain and TUI tests prove a valid key is stored with computed fingerprint; invalid OpenSSH text, blank label/key, duplicate key fingerprint, and duplicate user label fail with user-visible terminal errors.

3. **Key listing details**: Users can list their own SSH keys with label, fingerprint, created time, and last-used time when available.
   - Current: `Accounts.list_ssh_keys/1` returns keys ordered by `inserted_at`; no Account renderer displays them.
   - Target: The `SSH KEYS` tab lists only the current user's keys and shows label, SHA256 fingerprint, created timestamp, and either last-used timestamp or an explicit never-used marker.
   - Acceptance: Tests prove the list excludes other users' keys, displays the required fields for multiple keys, and renders a clear empty state when no keys exist.

4. **Self-service key revocation**: Users can revoke one of their own SSH keys from Account.
   - Current: There is no public Accounts revoke API and no TUI revoke action; key rows are only removed during account deletion.
   - Target: `Foglet.Accounts` exposes an ownership-safe revoke operation for the current user, and the `SSH KEYS` tab lets the user select and revoke one of their own keys with terminal feedback.
   - Acceptance: Domain and TUI tests prove revoking an owned key removes or disables it so it can no longer authenticate; attempts to revoke another user's key fail without changing that key; the Account key list refreshes after a successful revoke.

5. **Public-key authentication remains registered-key only**: SSH public-key authentication succeeds only for registered keys owned by non-deleted users and fails closed for unregistered, invalid, revoked, or deleted-user keys.
   - Current: `Accounts.get_user_by_public_key/1` finds non-deleted users by fingerprint, and deleted-user tests exist; revoked-key behavior does not exist because revocation is not implemented.
   - Target: The authentication lookup continues to route through Accounts, recognizes only active registered key rows, and rejects revoked or deleted-user keys without starting an authenticated session.
   - Acceptance: Tests prove registered keys resolve to the owning user, unregistered and invalid keys return `{:error, :not_found}`, revoked keys no longer resolve, and keys belonging to deleted users remain rejected.

6. **Last-used metadata recording**: Successful public-key authentication records last-used metadata for the key that authenticated the session.
   - Current: `ssh_keys.last_used_at` exists but is not updated by `CLIHandler.resolve_pubkey_user/1` or `Accounts.get_user_by_public_key/1`.
   - Target: Successful public-key authentication updates the matched key's `last_used_at` to the current UTC time without updating metadata for failed or password/guest login attempts.
   - Acceptance: Tests prove a successful registered-key login updates only that key's `last_used_at`; failed, invalid, unregistered, revoked, and deleted-user key attempts leave key metadata unchanged.

## Boundaries

**In scope:**
- Add an Account `SSH KEYS` tab for all authenticated users.
- Add terminal-native key add, list, and revoke behavior in the Account screen.
- Keep key persistence, ownership checks, revocation, lookup, and last-used updates inside `Foglet.Accounts` or another `Foglet.*` context boundary.
- Validate OpenSSH public-key text and compute SHA256 fingerprints server-side.
- Display label, fingerprint, created time, and last-used or never-used state.
- Ensure revoked keys cannot authenticate.
- Record `last_used_at` after successful public-key authentication.
- Focused domain, SSH-layer, and TUI tests for KEYS-01 through KEYS-05.

**Out of scope:**
- Browser-based account or SSH key management - Foglet remains SSH-first/TUI-first for this milestone.
- Operator or sysop management of another user's SSH keys - Phase 12 is self-service Account key management.
- SSH private-key generation, storage, import, or download - users manage private keys outside Foglet.
- Password changes, email changes, MFA, recovery codes, and credential history - adjacent account-security work is not required by KEYS-01 through KEYS-05.
- Key expiration policies, key comments editing, audit-log UI, bulk revocation, and notification on key use - useful hardening, but beyond pre-alpha gap closure.
- Changing host-key generation, daemon supervision, rate limiting, or connection-limit behavior - existing SSH infrastructure remains the integration point.

## Constraints

- Domain mutations must route through `Foglet.Accounts`; TUI screens must not call `Repo` directly.
- Actor/user-owned side effects must enforce ownership in the context API, not only by hiding UI actions.
- Programmatically set `user_id` on SSH key structs before changeset construction; do not make `user_id` caller-castable.
- Fingerprints must continue to be computed from OpenSSH public-key text server-side and stored as SHA256 strings.
- `last_used_at` must be UTC microsecond-compatible data matching existing schema timestamp conventions.
- Revocation must make the key unusable for future authentication; if implemented as soft revocation rather than deletion, the lookup path and schema tests must explicitly prove revoked keys are ignored.
- Account TUI rendering must stay terminal-native, use existing Account tab/widget patterns, and keep rendering pure over already-loaded state.
- Tests must avoid `Process.sleep/1`; synchronize through direct context calls, supervised processes, or deterministic assertions.

## Acceptance Criteria

- [ ] Account includes an `SSH KEYS` tab for normal authenticated users.
- [ ] The `SSH KEYS` tab renders an empty state when the user has no keys.
- [ ] User can add a valid OpenSSH public key with a label from Account.
- [ ] Added keys are stored with server-computed SHA256 fingerprints.
- [ ] Invalid OpenSSH key text, blank input, duplicate fingerprint, and duplicate label produce clear terminal errors.
- [ ] User can list only their own keys with label, fingerprint, created time, and last-used or never-used state.
- [ ] User can revoke an owned SSH key from Account.
- [ ] User cannot revoke another user's SSH key through the context API or TUI flow.
- [ ] Revoked keys no longer authenticate.
- [ ] Registered keys owned by non-deleted users still authenticate successfully.
- [ ] Unregistered, invalid, revoked, and deleted-user keys fail closed.
- [ ] Successful public-key authentication updates `last_used_at` for the matched key.
- [ ] Failed public-key attempts and password/guest flows do not update key last-used metadata.
- [ ] Focused tests cover KEYS-01, KEYS-02, KEYS-03, KEYS-04, and KEYS-05.

## Ambiguity Report

| Dimension           | Score | Min   | Status | Notes |
|---------------------|-------|-------|--------|-------|
| Goal Clarity        | 0.90  | 0.75  | met    | Add/list/revoke/use keys and last-used metadata are concrete outcomes. |
| Boundary Clarity    | 0.86  | 0.70  | met    | Self-service Account scope and excluded operator/browser/credential work are explicit. |
| Constraint Clarity  | 0.78  | 0.65  | met    | Context ownership, OpenSSH validation, UTC metadata, TUI purity, and auth failure behavior are locked. |
| Acceptance Criteria | 0.84  | 0.70  | met    | Criteria cover TUI, domain validation, ownership, authentication, revocation, and metadata updates. |
| **Ambiguity**       | 0.13  | <=0.20| met    | Weighted clarity is 0.87. |

Status: met = dimension meets minimum, below = planner treats as assumption.

## Interview Log

No structured question UI was available in this session, so decisions were derived from roadmap, requirements, and codebase scouting using the workflow's plain-text fallback.

| Round | Perspective | Question summary | Decision locked |
|-------|-------------|------------------|-----------------|
| 1 | Researcher | What exists today for SSH keys? | Schema, migration, fingerprint computation, register/list lookup APIs, pubkey stash, and CLIHandler lookup exist; Account TUI and revocation do not. |
| 1 | Researcher | What is the main gap between current state and Phase 12? | Build self-service Account UI plus ownership-safe revoke and last-used tracking. |
| 2 | Researcher + Simplifier | What is the minimum viable Account key surface? | One `SSH KEYS` tab with add, list, revoke, validation errors, and empty state. |
| 3 | Boundary Keeper | Who can manage keys in this phase? | Only the authenticated user can manage their own keys; sysop management is out of scope. |
| 4 | Failure Analyst | What would make the implementation unsafe? | UI-only ownership checks, revoked keys still authenticating, or failed auth attempts updating last-used metadata. |
| 5 | Seed Closer | How should last-used behavior be verified? | Successful registered-key auth updates only the matched key; failed, revoked, deleted-user, and non-key flows do not update metadata. |

---

*Phase: 12-account-ssh-key-management*
*Spec created: 2026-04-24*
*Next step: $gsd-discuss-phase 12 - implementation decisions (how to build what is specified above)*
