---
phase: 12
slug: account-ssh-key-management
status: verified
threats_open: 0
asvs_level: 1
created: 2026-04-24
---

# Phase 12 - Security

Per-phase security contract: threat register, accepted risks, and audit trail.

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| TUI/SSH -> Accounts | User-submitted labels, public keys, and offered SSH keys cross into persistence and authentication logic. | SSH public key material, labels, actor identity |
| Accounts -> Postgres | Durable key rows, uniqueness, ownership, deletion, and last-used metadata are written. | SSH key fingerprints, labels, timestamps, user ownership |
| SSH daemon -> CLIHandler | Offered key material from the SSH callback is encoded and passed to Accounts. | Public key auth callback data |
| Terminal input -> Account screen | Label, public-key text, and action key presses enter screen-local state. | User-controlled text and key events |
| Account screen -> Accounts | TUI delegates key list/add/revoke operations to context APIs. | Actor-scoped key lifecycle requests |
| Account state -> Renderer | Stored key metadata becomes terminal output. | Labels, fingerprints, timestamps |
| Tests -> public APIs | Regression tests exercise the same Accounts, SSH, and TUI boundaries users hit. | Public API inputs and assertions |
| Phase validation -> repository | Full precommit checks compile, formatting, static analysis, Sobelow, and Dialyzer. | Source and test verification results |

## Threat Register

| Threat ID | Category | Component | Disposition | Mitigation | Status |
|-----------|----------|-----------|-------------|------------|--------|
| T-12-01 | Elevation of Privilege | `Accounts.revoke_ssh_key/2` | mitigate | Query by both `id` and `user_id`; cross-user revoke returns `{:error, :not_found}` with no delete. | closed |
| T-12-02 | Tampering | duplicate key registration | mitigate | Keep DB unique indexes and `unique_constraint/3` for global fingerprint and per-user label uniqueness. | closed |
| T-12-03 | Spoofing | `Accounts.authenticate_by_public_key/1` | mitigate | Resolve only fingerprints backed by an existing key row joined to a non-deleted active user. | closed |
| T-12-04 | Repudiation | `ssh_keys.last_used_at` | mitigate | Update `last_used_at` only after successful registered-key match; failed/password/guest paths do not update metadata. | closed |
| T-12-05 | Information Disclosure | auth failure return shape | mitigate | Return `{:error, :not_found}` for invalid, unregistered, revoked, and deleted-user keys. | closed |
| T-12-06 | Elevation of Privilege | `SSHKeysActions.revoke_selected/2` | mitigate | Call only `Accounts.revoke_ssh_key(actor, key.id)`; ownership is enforced in Accounts. | closed |
| T-12-07 | Information Disclosure | `SSHKeysSurface.render/2` | mitigate | Render label, fingerprint, created time, and last-used state; do not render raw `public_key`. | closed |
| T-12-08 | Tampering | add flow attrs | mitigate | Send only `%{label: label, public_key: public_key}` to `Accounts.register_ssh_key/2`; `user_id` remains context-set. | closed |
| T-12-09 | Denial of Service | invalid form submissions | mitigate | Invalid changesets become inline error strings; screen remains usable and does not crash. | closed |
| T-12-10 | Spoofing | tab visibility | accept | SSH KEYS tab is visible to authenticated users only because Account requires `current_user`; persistence authorization remains in Accounts. | closed |
| T-12-11 | Tampering | regression coverage | mitigate | Requirement-tagged assertions cover add/list/revoke/auth metadata paths across all touched subsystems. | closed |
| T-12-12 | Elevation of Privilege | TUI key management | mitigate | Production TUI files contain no direct `Repo` usage and rely on Accounts ownership tests. | closed |
| T-12-13 | Spoofing | registered-key auth | mitigate | Tests prove unregistered, invalid, revoked, and deleted-user keys return failure. | closed |
| T-12-14 | Repudiation | `last_used_at` metadata | mitigate | Tests prove successful auth updates the matched key and failed/password/guest paths do not. | closed |
| T-12-15 | Denial of Service | validation feedback loop | mitigate | Focused command and full `rtk mix precommit` passed before phase sign-off. | closed |

*Status: open - closed*
*Disposition: mitigate (implementation required) - accept (documented risk) - transfer (third-party)*

## Threat Verification

| Threat ID | Category | Disposition | Evidence |
|-----------|----------|-------------|----------|
| T-12-01 | Elevation of Privilege | mitigate | `Accounts.revoke_ssh_key/2` queries by `id` and `user_id`, then deletes only the matched row; missing/cross-user rows return `{:error, :not_found}`. Evidence: `lib/foglet_bbs/accounts.ex:760-766`. |
| T-12-02 | Tampering | mitigate | SSH key changeset casts only label/public_key, computes fingerprint, and keeps unique constraints for global fingerprint and per-user label. Evidence: `lib/foglet_bbs/accounts/ssh_key.ex:36-43`; duplicate tests at `test/foglet_bbs/accounts/ssh_key_test.exs:28-63`. |
| T-12-03 | Spoofing | mitigate | Public-key auth computes fingerprint and resolves only an existing key joined to a non-deleted active user. Evidence: `lib/foglet_bbs/accounts.ex:791-815`; review fix documents active-status gate at `12-REVIEW-FIX.md:24-29`. |
| T-12-04 | Repudiation | mitigate | `last_used_at` is written only after successful key/user match; invalid, unregistered, revoked, deleted-user, inactive, password, and guest paths are covered. Evidence: `lib/foglet_bbs/accounts.ex:791-805`; tests at `test/foglet_bbs/accounts/accounts_test.exs:659-726` and `test/foglet_bbs/ssh/cli_handler_test.exs:197-212`. |
| T-12-05 | Information Disclosure | mitigate | Invalid, unregistered, revoked, deleted-user, and inactive keys all return `{:error, :not_found}` through the same failure shape. Evidence: `lib/foglet_bbs/accounts.ex:803-805`; tests at `test/foglet_bbs/accounts/accounts_test.exs:678-714`. |
| T-12-06 | Elevation of Privilege | mitigate | TUI revoke delegates only to `Accounts.revoke_ssh_key(actor, id)`, relying on Accounts ownership enforcement. Evidence: `lib/foglet_bbs/tui/screens/account/ssh_keys_actions.ex:100-108`. |
| T-12-07 | Information Disclosure | mitigate | Key list renders label, fingerprint, created timestamp, and last-used state; row rendering does not include `public_key`. Evidence: `lib/foglet_bbs/tui/screens/account/ssh_keys_surface.ex:85-99`; raw-key non-display test at `test/foglet_bbs/tui/screens/account_test.exs:113-140`. |
| T-12-08 | Tampering | mitigate | Add flow normalizes attrs to only `label` and `public_key` before calling Accounts; user ownership remains context-set. Evidence: `lib/foglet_bbs/tui/screens/account/ssh_keys_actions.ex:24-32`; `Accounts.register_ssh_key/2` sets `user_id` on the struct at `lib/foglet_bbs/accounts.ex:747-752`. |
| T-12-09 | Denial of Service | mitigate | Invalid changesets are converted into state errors and rendered inline; add/revoke missing cases return state updates, not crashes. Evidence: `lib/foglet_bbs/tui/screens/account/ssh_keys_actions.ex:36-38` and `:111-115`; validation tests at `test/foglet_bbs/tui/screens/account_test.exs:614-620`. |
| T-12-10 | Spoofing | accept | SSH KEYS tab visibility relies on Account screen authenticated-user routing; persistence authorization remains enforced in Accounts APIs. Evidence: Account loads actor from `current_user` and delegates active SSH KEYS events at `lib/foglet_bbs/tui/screens/account.ex:92-104`; accepted risk logged below. |
| T-12-11 | Tampering | mitigate | Requirement-tagged assertions cover add/list/revoke/auth metadata paths across Accounts, SSHKey, Account TUI, and CLIHandler tests. Evidence: `12-03-SUMMARY.md:72-75`; focused suite passed at `12-03-SUMMARY.md:82-86`. |
| T-12-12 | Elevation of Privilege | mitigate | Production Account SSH key TUI files were checked for direct Repo usage with no matches, relying on Accounts ownership tests. Evidence: no-match grep recorded at `12-03-SUMMARY.md:84-85`. |
| T-12-13 | Spoofing | mitigate | Registered-key auth tests prove unregistered, deleted-user, and revoked keys fail; Accounts tests additionally cover invalid and inactive statuses. Evidence: `test/foglet_bbs/ssh/cli_handler_test.exs:160-194`; `test/foglet_bbs/accounts/accounts_test.exs:678-714`. |
| T-12-14 | Repudiation | mitigate | Tests prove successful auth updates only the matched key and failed/password/guest paths do not update metadata. Evidence: `test/foglet_bbs/accounts/accounts_test.exs:659-726`; `test/foglet_bbs/ssh/cli_handler_test.exs:197-212`. |
| T-12-15 | Denial of Service | mitigate | Final focused Phase 12 command and full `rtk mix precommit` passed before sign-off. Evidence: `12-03-SUMMARY.md:82-86`. |

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-12-01 | T-12-10 | SSH KEYS tab visibility is presentation gating rather than an authorization boundary. The Account screen is reached with `current_user`, and all durable add/list/revoke operations route through `Foglet.Accounts`, where ownership and active-user checks are enforced. | GSD security audit | 2026-04-24 |

## Unregistered Flags

None. `12-02-SUMMARY.md` and `12-03-SUMMARY.md` both report no threat flags; `12-01-SUMMARY.md` has no `## Threat Flags` section.

## Review Carry-In

Code review found CR-01, a public-key auth status/verification gate bypass. The fix is documented as complete in `12-REVIEW-FIX.md:16-29`, and the audited implementation now gates public-key lookup to non-deleted active users in `lib/foglet_bbs/accounts.ex:808-815`.

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-04-24 | 15 | 15 | 0 | GSD security auditor |

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-04-24
