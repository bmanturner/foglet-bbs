%{
  title: "First sysop",
  weight: 30
}
---

This page shows the supported break-glass path for creating the first operator
account. A sysop is the site operator role: use it to administer users, boards,
configuration, invites, and other operator workflows.

## Create the account

Run the Mix task from a source checkout after the database exists and migrations
have run:

```bash
mix foglet.user.create --handle HANDLE --email EMAIL --password PASSWORD
```

Example:

```bash
mix foglet.user.create --handle ada --email ada@example.net --password 'use-a-real-password-here'
```

All three flags are required. Unknown or missing flags exit non-zero with a
usage message.

Sysop-created accounts are confirmed immediately. Foglet does not generate an
email verification token for accounts created through this task.

Use a password long enough for real use. Do not paste a production password into
shared logs, issue trackers, shell history you do not control, or support
comments.

## Promote the account

New accounts start as normal users. Promote the handle to `sysop`:

```bash
mix foglet.user.promote HANDLE --role sysop
```

Example:

```bash
mix foglet.user.promote ada --role sysop
```

Valid roles are:

- `user`
- `mod`
- `sysop`

The task exits non-zero if the handle does not exist, the role is missing, or
the role is not one of those values.

## Release/container form

In an OTP release, run the same task code through the release binary with the
same environment the app uses:

```bash
/app/bin/foglet_bbs eval 'Mix.Tasks.Foglet.User.Create.run(["--handle", "ada", "--email", "ada@example.net", "--password", "use-a-real-password-here"])'
/app/bin/foglet_bbs eval 'Mix.Tasks.Foglet.User.Promote.run(["ada", "--role", "sysop"])'
```

For Docker, include the production environment and persistent `/data` mount you
use for the running server. The task needs database access; it does not need the
SSH port to be exposed.

## Sign in over SSH

Start Foglet, then connect:

```bash
ssh HOST -p PORT
```

For local development the default is:

```bash
ssh localhost -p 2222
```

Foglet's SSH transport uses public-key authentication so the client must be able
to offer a key. If the key is already attached to the account, Foglet can start
the session as that user. If the key is unknown, the TUI starts in the guest or
login flow and you can sign in with the handle/password you created.

After signing in, add your normal SSH public key through the account settings
flow so future connections can be correlated automatically.

## If you created the wrong role

Run the promote task again with the intended role:

```bash
mix foglet.user.promote HANDLE --role user
```

Do this carefully on a shared instance. Removing the last sysop can leave the
BBS without an operator account unless you still have database or release-shell
access.

## What this does not do

Creating the first sysop does not:

- create categories, boards, or production content beyond whatever seeds or
  migrations already installed.
- configure email delivery.
- open registration.
- change SSH host keys.
- grant operating-system access to the server.

Those are separate operator tasks.
