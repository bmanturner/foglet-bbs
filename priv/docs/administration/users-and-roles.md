%{
  title: "Users and roles",
  weight: 10
}
---

This page explains Foglet account roles, account status, and the sysop user-management flow. Use it when you need to approve new callers, suspend an account, or understand why an account cannot act.

## Roles

Foglet stores one role on each user account.

| Role | What it means |
| --- | --- |
| `user` | A normal member. Users can read member-visible boards, post where board policy allows members, manage their profile and SSH keys, and generate invites only when site settings allow it. |
| `mod` | A moderator. Mods can use site-wide moderator actions and board-scoped moderator actions, but cannot edit site configuration. |
| `sysop` | The operator account. Sysops can perform all guarded actions at site scope, including user status changes, board/category administration, site settings, and test email delivery. |

The authorization layer rejects deleted, pending, rejected, and suspended accounts before role checks. A suspended sysop is still suspended. The role does not bypass account lifecycle state.

## Account statuses

Foglet keeps lifecycle state in `status`.

| Status | Meaning | Allowed sysop transition |
| --- | --- | --- |
| `pending` | Registration awaits sysop approval. The account cannot act yet. | approve to `active` or reject to `rejected` |
| `active` | The account can sign in and act according to its role and board policy. | suspend to `suspended` |
| `suspended` | The account exists but cannot act. | reactivate to `active` |
| `rejected` | A registration was rejected. The row remains and continues to reserve its handle and email. | none |

Deleted users are separate from status. A deleted account is soft-deleted and cannot be changed through the status screen.

## Managing users in the TUI

Sysops manage accounts from the sysop area, `USERS` tab.

The tab groups accounts by status and shows handle, role, status, and email. Move through the list, then press:

| Key | Action |
| --- | --- |
| `v` | Open the selected user's public profile. |
| `a` | Approve a pending account. |
| `r` | Reject a pending account. |
| `s` | Suspend an active account. |
| `u` | Reactivate a suspended account. |

Foglet only offers transitions that the selected account can take. If another sysop changes or deletes the account while you are looking at it, the action may fail with a short message and the list will reload.

## Role changes

Role changes exist in the domain layer, but the public sysop TUI described here is primarily a status-management screen. Treat role promotion/demotion as an operator action outside this page's normal account-approval flow unless your installation documents a specific task or console procedure for it.

## Email verification and operator accounts

If email verification is enabled, ordinary active users may be held at the verification screen until confirmed. Mods and sysops can pass the current verification boundary so an operator is not locked out by a newly enabled verification requirement.

## Deleting accounts

Account deletion is a soft-delete/anonymization path. Foglet rewrites authored posts to the tombstone user, removes private/account-local rows such as SSH keys and read pointers, clears profile fields, and keeps the user row so existing foreign keys remain valid.

Do not describe deletion as a purge. The message body remains unless a separate post/thread moderation action removed it.
