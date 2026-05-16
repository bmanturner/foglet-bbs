%{
  title: "Mix tasks",
  weight: 20
}
---

This page is the operator reference for Foglet-specific Mix tasks. These tasks
are useful for local operation, first-sysop setup, and break-glass account work.
In an OTP release, Mix may not be installed; use release commands or platform
operations instead.

Run tasks from the repository root with the application environment configured.
Most tasks start the app and talk to Postgres.

## Environment check

```sh
mix foglet.doctor
```

Runs safe local checks: pinned Elixir/Erlang versions, configured database
reachability, `citext`, SSH host key presence, and basic environment variables.
It does not make destructive database changes.

## Users and account status

```sh
mix foglet.user.create --handle HANDLE --email EMAIL --password PASSWORD
mix foglet.user.promote --handle HANDLE --role user|mod|sysop
mix foglet.user.status HANDLE --status active|rejected|suspended --actor SYSOP_HANDLE
```

`foglet.user.create` creates and confirms an account. Use it for first-sysop or
operator-created accounts, then promote the account if needed.

Status changes are operational tools. Prefer normal registration and approval
flows for routine users; use the CLI when the SSH flow is unavailable or an
operator needs to repair an account.

## Pending users

```sh
mix foglet.users.approve --handle HANDLE --actor SYSOP_HANDLE
mix foglet.users.reject --handle HANDLE --actor SYSOP_HANDLE --reason "reason"
```

Approval and rejection run through the account context and notification path.
The actor should be a sysop. If email delivery is not configured, the task still
updates the account state and reports the delivery result.

## Invites

```sh
mix foglet.invites.create --actor SYSOP_HANDLE
mix foglet.invites.list --actor SYSOP_HANDLE
mix foglet.invites.inspect INVITE_CODE --actor SYSOP_HANDLE
mix foglet.invites.revoke INVITE_CODE --actor SYSOP_HANDLE
```

Invite creation uses the configured invite policy. Codes are sensitive: they
permit registration. Treat printed invite codes like one-time secrets and do not
paste them into public logs or support threads.

## Verification and reset tokens

```sh
mix foglet.user.verification_code HANDLE
mix foglet.verification.inspect HANDLE
mix foglet.user.reset_password HANDLE
mix foglet.reset_token.inspect HANDLE
mix foglet.reset_token.expire HANDLE
```

These are break-glass tasks for no-email or account-recovery situations. They
print verification codes or reset tokens to the terminal. Do not capture this
output in shared logs. The reset-password task does not send email.

## Board subscriptions

```sh
mix foglet.board_subscriptions list --user HANDLE_OR_EMAIL
mix foglet.board_subscriptions subscribe --user HANDLE_OR_EMAIL --board BOARD_SLUG
mix foglet.board_subscriptions unsubscribe --user HANDLE_OR_EMAIL --board BOARD_SLUG
```

Subscription mutations route through `Foglet.Boards`, so archived-board and
required-subscription rules match the SSH terminal flow. The task refuses to
unsubscribe a user from a required subscription.

## Board chat

```sh
mix foglet.board_chat show --board BOARD_SLUG
mix foglet.board_chat enable --board BOARD_SLUG --actor SYSOP_HANDLE
mix foglet.board_chat disable --board BOARD_SLUG --actor SYSOP_HANDLE
mix foglet.board_chat set-mode --board BOARD_SLUG --mode ephemeral|permanent --actor SYSOP_HANDLE
mix foglet.board_chat set-ttl --board BOARD_SLUG --seconds 60..86400 --actor SYSOP_HANDLE
```

`show` is read-only. Mutations require an actor and route through board update
authorization. Archived boards can be inspected but not changed by this task.

## SSH IP access rules

```sh
mix foglet.ip_access.list
mix foglet.ip_access.create --mode allow|deny --address IP_OR_CIDR --reason TEXT
mix foglet.ip_access.disable ID
mix foglet.ip_access.enable ID
mix foglet.ip_access.remove ID
```

These tasks manage the SSH daemon's operator-defined IP allow/deny rules. Use
CIDR notation when you mean a network, not a single host. A bad deny rule can
lock callers out; keep a console or deploy shell open while changing access.

## Identity policy rules

```sh
mix foglet.identity_policy.list
mix foglet.identity_policy.create --kind reserved_handle|banned_handle|banned_email|banned_email_domain --value VALUE --reason TEXT
mix foglet.identity_policy.disable ID
mix foglet.identity_policy.enable ID
mix foglet.identity_policy.remove ID
```

Identity policy rules reserve handles and block handles, email addresses, or
email domains during registration/account checks. The create task reports
conflicts when a new rule overlaps existing accounts; read that output before
assuming the rule has solved an existing account problem.

## Contributor and QA-only tasks

```sh
mix foglet.tui.render SCREEN
mix foglet.qa.mode MODE
```

`foglet.tui.render` renders SSH/TUI screens as plain text for contributors. It
uses render fixtures and is not an operator health check.

`foglet.qa.mode` changes registration-related configuration for QA. Do not use
it as routine production administration unless you have inspected the exact
configuration keys it changes and intend that state.

## Production release commands

The release module provides migration and seed entry points for environments
where Mix is not present:

```sh
bin/foglet_bbs eval "FogletBbs.Release.migrate()"
bin/foglet_bbs eval "FogletBbs.Release.seed()"
```

The committed Fly deploy path uses a release command so migrations and
production-safe seeds run during deploy. Production-safe seeds are limited to
configuration defaults and fixtures the running application assumes exist; they
are not the local QA seed set.
