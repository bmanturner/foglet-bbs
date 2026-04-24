---
status: complete
phase: 12-account-ssh-key-management
source: [.planning/phases/12-account-ssh-key-management/12-01-SUMMARY.md, .planning/phases/12-account-ssh-key-management/12-02-SUMMARY.md, .planning/phases/12-account-ssh-key-management/12-03-SUMMARY.md]
started: 2026-04-24T20:25:11Z
updated: 2026-04-24T20:34:36Z
---

## Current Test

[testing complete]

## Tests

### 1. Account SSH KEYS Tab
expected: In the terminal Account screen for a normal authenticated user, an SSH KEYS tab appears alongside PROFILE and PREFS. Selecting it renders successfully and shows a clear empty state when the user has no registered keys.
result: pass

### 2. Add SSH Key With Validation Feedback
expected: From the SSH KEYS tab, the user can enter a label and valid OpenSSH public key, submit it, and see the key added. Blank fields, invalid key text, duplicate fingerprints, and duplicate labels produce visible terminal validation errors.
result: pass

### 3. Key List Metadata Without Raw Public Key Leakage
expected: The SSH KEYS tab lists only the current user's keys and shows each key's label, SHA256 fingerprint, created time, and last-used state. Stored key rows do not display the raw OpenSSH public key text.
result: pass

### 4. Refresh And Revoke Owned Key
expected: The user can refresh the SSH key list, select an owned key, revoke it from the Account screen, receive terminal feedback, and see the list update so the revoked key is gone.
result: pass

### 5. Revoked And Foreign Keys Cannot Authenticate Or Be Revoked
expected: Revoked keys no longer authenticate, unregistered or invalid keys fail closed, deleted-user keys fail closed, and attempts to revoke another user's key fail without changing that other user's key.
result: pass

### 6. Successful Public-Key Login Records Last Used
expected: A successful registered-key SSH login updates last-used metadata only for the key that authenticated. Failed key attempts, revoked/deleted-user keys, password login, and guest login do not update SSH key last-used metadata.
result: pass

## Summary

total: 6
passed: 6
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

[none yet]
