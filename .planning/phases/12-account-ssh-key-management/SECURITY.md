# Phase 12 Security Verification

**Phase:** 12 - account-ssh-key-management  
**ASVS Level:** 1  
**Config:** block_on=high, enforcement=true  
**Audited:** 2026-04-24

## Threat Summary

| Metric | Count |
|--------|-------|
| Threats registered | 15 |
| Threats closed | 15 |
| Threats open | 0 |
| Unregistered flags | 0 |

## Threat Verification

| Threat ID | Category | Disposition | Status | Evidence |
|-----------|----------|-------------|--------|----------|
| T-12-01 | Elevation of Privilege | mitigate | CLOSED | `Accounts.revoke_ssh_key/2` queries by `id` and `user_id`, then deletes only the matched row; missing/cross-user rows return `{:error, :not_found}`. Evidence: `lib/foglet_bbs/accounts.ex:760-766`. |
| T-12-02 | Tampering | mitigate | CLOSED | SSH key changeset casts only label/public_key, computes fingerprint, and keeps unique constraints for global fingerprint and per-user label. Evidence: `lib/foglet_bbs/accounts/ssh_key.ex:36-43`; duplicate tests at `test/foglet_bbs/accounts/ssh_key_test.exs:28-63`. |
| T-12-03 | Spoofing | mitigate | CLOSED | Public-key auth computes fingerprint and resolves only an existing key joined to a non-deleted active user. Evidence: `lib/foglet_bbs/accounts.ex:791-815`; review fix documents active-status gate at `12-REVIEW-FIX.md:24-29`. |
| T-12-04 | Repudiation | mitigate | CLOSED | `last_used_at` is written only after successful key/user match; invalid, unregistered, revoked, deleted-user, inactive, password, and guest paths are covered. Evidence: `lib/foglet_bbs/accounts.ex:791-805`; tests at `test/foglet_bbs/accounts/accounts_test.exs:659-726` and `test/foglet_bbs/ssh/cli_handler_test.exs:197-212`. |
| T-12-05 | Information Disclosure | mitigate | CLOSED | Invalid, unregistered, revoked, deleted-user, and inactive keys all return `{:error, :not_found}` through the same failure shape. Evidence: `lib/foglet_bbs/accounts.ex:803-805`; tests at `test/foglet_bbs/accounts/accounts_test.exs:678-714`. |
| T-12-06 | Elevation of Privilege | mitigate | CLOSED | TUI revoke delegates only to `Accounts.revoke_ssh_key(actor, id)`, relying on Accounts ownership enforcement. Evidence: `lib/foglet_bbs/tui/screens/account/ssh_keys_actions.ex:100-108`. |
| T-12-07 | Information Disclosure | mitigate | CLOSED | Key list renders label, fingerprint, created timestamp, and last-used state; row rendering does not include `public_key`. Evidence: `lib/foglet_bbs/tui/screens/account/ssh_keys_surface.ex:85-99`; raw-key non-display test at `test/foglet_bbs/tui/screens/account_test.exs:113-140`. |
| T-12-08 | Tampering | mitigate | CLOSED | Add flow normalizes attrs to only `label` and `public_key` before calling Accounts; user ownership remains context-set. Evidence: `lib/foglet_bbs/tui/screens/account/ssh_keys_actions.ex:24-32`; `Accounts.register_ssh_key/2` sets `user_id` on the struct at `lib/foglet_bbs/accounts.ex:747-752`. |
| T-12-09 | Denial of Service | mitigate | CLOSED | Invalid changesets are converted into state errors and rendered inline; add/revoke missing cases return state updates, not crashes. Evidence: `lib/foglet_bbs/tui/screens/account/ssh_keys_actions.ex:36-38` and `:111-115`; validation tests at `test/foglet_bbs/tui/screens/account_test.exs:614-620`. |
| T-12-10 | Spoofing | accept | CLOSED | Accepted risk: SSH KEYS tab visibility relies on Account screen authenticated-user routing; persistence authorization remains enforced in Accounts APIs. Evidence: Account loads actor from `current_user` and delegates active SSH KEYS events at `lib/foglet_bbs/tui/screens/account.ex:92-104`; accepted risk logged below. |
| T-12-11 | Tampering | mitigate | CLOSED | Requirement-tagged assertions cover add/list/revoke/auth metadata paths across Accounts, SSHKey, Account TUI, and CLIHandler tests. Evidence: Plan 12-03 summary files list KEYS-tagged test coverage at `12-03-SUMMARY.md:72-75`; focused suite passed at `12-03-SUMMARY.md:82-86`. |
| T-12-12 | Elevation of Privilege | mitigate | CLOSED | Production Account SSH key TUI files were checked for direct Repo usage with no matches, relying on Accounts ownership tests. Evidence: no-match grep recorded at `12-03-SUMMARY.md:84-85`. |
| T-12-13 | Spoofing | mitigate | CLOSED | Registered-key auth tests prove unregistered, deleted-user, and revoked keys fail; Accounts tests additionally cover invalid and inactive statuses. Evidence: `test/foglet_bbs/ssh/cli_handler_test.exs:160-194`; `test/foglet_bbs/accounts/accounts_test.exs:678-714`. |
| T-12-14 | Repudiation | mitigate | CLOSED | Tests prove successful auth updates only the matched key and failed/password/guest paths do not update metadata. Evidence: `test/foglet_bbs/accounts/accounts_test.exs:659-726`; `test/foglet_bbs/ssh/cli_handler_test.exs:197-212`. |
| T-12-15 | Denial of Service | mitigate | CLOSED | Final focused Phase 12 command and full `rtk mix precommit` passed before sign-off. Evidence: `12-03-SUMMARY.md:82-86`. |

## Accepted Risks Log

| Threat ID | Risk | Rationale | Compensating Control |
|-----------|------|-----------|----------------------|
| T-12-10 | SSH KEYS tab visibility is treated as presentation gating rather than an authorization boundary. | The Account screen is reached with `current_user`; hiding/showing the tab is not relied on for data protection. | All durable add/list/revoke operations route through `Foglet.Accounts`, where ownership and active-user checks are enforced. |

## Unregistered Flags

None. `12-02-SUMMARY.md` and `12-03-SUMMARY.md` both report no threat flags; `12-01-SUMMARY.md` has no `## Threat Flags` section.

## Review Carry-In

Code review found CR-01, a public-key auth status/verification gate bypass. The fix is documented as complete in `12-REVIEW-FIX.md:16-29`, and the audited implementation now gates public-key lookup to non-deleted active users in `lib/foglet_bbs/accounts.ex:808-815`.
