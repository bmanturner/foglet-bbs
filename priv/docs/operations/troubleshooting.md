%{
  title: "Troubleshooting",
  weight: 50
}
---

This page starts from symptoms. Use it when a Foglet instance will not start,
will not answer over SSH, or cannot send the expected account mail.

## `/up` does not answer

Check that the Phoenix endpoint is running and listening on the expected HTTP
port.

```sh
curl -v http://127.0.0.1:4000/up
```

Common causes:

- the app is not running
- `PORT` is different from the port you checked
- production startup failed because `DATABASE_URL` or `SECRET_KEY_BASE` is
  missing
- the deploy platform is routing to the wrong internal port
- the app is crash-looping after boot

Read the app logs first. If the release never starts, the logs are more useful
than repeated health checks.

## Database connection errors

Symptoms include Repo startup failures, failed migrations, or doctor reporting
that Postgres cannot be reached.

Check:

- `DATABASE_URL` points at the intended database
- database credentials are current
- the database host allows connections from the app
- `POOL_SIZE` is appropriate for the database plan
- `ECTO_IPV6=true` is set only when the network path requires IPv6
- provider-required TLS is configured; the committed runtime config leaves
  `ssl: true` commented out by default

For local development, start the committed Postgres service and rerun setup:

```sh
docker compose up -d postgres
mix ecto.create
mix ecto.migrate
```

## Missing `citext`

`mix foglet.doctor` checks for the Postgres `citext` extension. The first
migration creates it. If doctor reports it missing, run migrations against the
same database the app uses:

```sh
mix ecto.migrate
```

If migrations fail because the database user cannot create extensions, grant the
needed permission or create `citext` as a database administrator before rerunning
migrations.

## SSH will not connect

Check the SSH port separately from HTTP:

```sh
ssh -p 2222 your-handle@your-host
```

Common causes:

- `FOGLET_SSH_PORT` is not the port exposed by your firewall/platform
- Fly or container TCP service mapping is wrong
- the SSH daemon failed to start because host keys are missing or unreadable
- the process can bind HTTP but not the SSH port
- a local client is connecting to the wrong host or cached host-key entry

If the host key changed unexpectedly, do not tell users to delete their
`known_hosts` entry until you understand why. A changed host key can mean lost
persistent storage or a different machine answering for the board.

## SSH login fails

Check the account state with operator tasks:

```sh
mix foglet.user.status HANDLE --status active --actor SYSOP_HANDLE
```

If the user is pending, approve or reject the account intentionally. If email is
disabled or unavailable, use the no-email verification or reset-token tasks only
as break-glass tools, and keep printed codes out of shared logs.

## SMTP does not send

Foglet uses SMTP only when `FOGLET_SMTP_RELAY` or `FOGLET_SMTP_HOST` is set. The
runtime config also reads:

- `FOGLET_SMTP_PORT` (default `587`)
- `FOGLET_SMTP_USERNAME`
- `FOGLET_SMTP_PASSWORD`
- `FOGLET_SMTP_SSL`
- `FOGLET_SMTP_TLS`
- `FOGLET_SMTP_AUTH`
- `FOGLET_MAIL_FROM`

If no SMTP relay is configured, account flows that depend on email must use the
no-email/operator recovery tasks. If SMTP is configured but delivery fails,
inspect logs for relay, TLS, authentication, or sender-domain errors.

## Migrations fail during deploy

Do not keep retrying blindly. Capture the failing migration and error, then
decide whether the failed migration changed any data before stopping.

Check:

- the release has the same `DATABASE_URL` as the app
- the database user can create extensions and alter tables
- the migration was not already partially applied
- the current app version matches the schema state

If production data may have been partially changed, ask for approval before
rollback or restore.

## `mix foglet.doctor` gives command suggestions that mention local tooling

Doctor is a local-development convenience. Its messages may point at local repo
commands and local Postgres. In production, use release commands, platform logs,
and the deployment guide instead.

## When to stop and escalate

Escalate before changing production data when:

- host keys were lost or may be compromised
- a migration partially applied
- a restore would discard user posts or account changes
- database credentials or SMTP secrets may have leaked
- you cannot tell which database the running app is using

The safest next command is often no command at all until the shape of the damage
is known.
