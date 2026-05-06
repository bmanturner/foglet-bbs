%{
  title: "Registration and invites",
  weight: 20
}
---

This page explains how Foglet lets new callers in: open registration, invite-only registration, and sysop-approved registration.

## Registration modes

The `registration_mode` site setting controls new account flow.

| Mode | Behavior |
| --- | --- |
| `open` | A new registration creates an active account immediately. |
| `invite_only` | A new registration must include a valid invite code. The invite is consumed during account creation. |
| `sysop_approved` | A new registration creates a pending account. A sysop must approve or reject it from the sysop user screen. |

The setting is DB-backed runtime configuration. Use the sysop settings flow when available for your build; otherwise set it through the operator tooling documented for your deployment.

## Invite generation policy

The `invite_code_generators` site setting controls who may generate invite codes.

| Value | Who can generate invites |
| --- | --- |
| `sysop_only` | Sysops only. |
| `mods` | Sysops and mods. |
| `any_user` | Any active member. |

Authorization still rejects pending, rejected, suspended, and deleted users before invite permissions are checked.

## Invite registration

In invite-only mode, the invite code is required. Empty or missing codes are rejected before the account is created. When a valid code is accepted, Foglet creates the user and marks the invite as consumed in the same registration flow.

If the caller offered an SSH public key during registration, Foglet attempts to attach it after user creation. A duplicate or invalid key can still fail the registration path, so advise callers to retry with a known-good OpenSSH public key or add the key after signing in.

## Sysop-approved registration

In sysop-approved mode, new accounts start as `pending`. They cannot use normal member capabilities until approved.

Sysops manage pending accounts in the sysop area, `USERS` tab:

| Key | Action |
| --- | --- |
| `a` | Approve the selected pending user. |
| `r` | Reject the selected pending user. |

Approval changes the account from `pending` to `active`. Rejection changes it to `rejected`; the handle and email remain reserved.

Foglet sends status-transition email when mail delivery is configured. If delivery fails, the account transition can still complete; the sysop screen reports the delivery failure separately.

## What is not here yet

Public docs should not promise a full invite-admin catalog unless your build exposes one. Foglet has invite creation, consumption, and revocation paths in the application, but the exact operator surface depends on the current release. Keep deployment-specific invite commands in operations docs, not in this administration overview.
