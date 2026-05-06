%{
  title: "Upgrades",
  weight: 40
}
---

This page covers safe upgrade practice for a running Foglet instance. It assumes
you already have a working deploy target and a database backup path.

Foglet upgrades are release upgrades plus database migrations. Treat the
database as the hard part.

## Before upgrading

1. Read the release notes or diff for migrations and runtime configuration
   changes.
2. Back up Postgres.
3. Back up the persistent SSH host key directory named by `SSH_HOST_KEY_DIR`.
4. Confirm required env vars still exist: `DATABASE_URL`, `SECRET_KEY_BASE`,
   `PHX_HOST`, `PORT`, `FOGLET_SSH_PORT`, and SMTP vars if email is enabled.
5. Confirm your deploy target will keep `/data` or equivalent persistent storage
   mounted across releases.

Do not upgrade if you cannot answer how to restore the database and host keys.

## Migrations and release-safe seeds

The release module exposes two operations:

```sh
bin/foglet_bbs eval "FogletBbs.Release.migrate()"
bin/foglet_bbs eval "FogletBbs.Release.seed()"
```

`migrate()` runs all pending Ecto migrations. `seed()` runs migrations and then
runs the production-safe seed allowlist from `lib/foglet_bbs/release.ex`:

- `priv/repo/seeds/config.exs`
- `priv/repo/seeds/fixtures.exs`

Those seed files are meant for defaults the running application assumes exist.
They are not the full local development seed set and do not include QA-only SSH
harness accounts.

On the committed Fly profile, deploy uses the release command configured in
`fly.toml`, so migrations/seeds run as part of deployment.

## Upgrade checks

After deploy, check:

```sh
curl -fsS https://your-host/up
ssh your-handle@your-host
```

Then inspect logs for:

- failed migrations
- Repo connection errors
- missing `SECRET_KEY_BASE` or `DATABASE_URL`
- SSH host key directory errors
- SMTP configuration errors if email is enabled
- repeated application restarts

A passing HTTP health check is necessary but not sufficient. The SSH login path
is the product; verify it.

## Rollback expectations

There are two rollback shapes:

- Code rollback: deploy the previous release/image while keeping the current
  database.
- Data rollback: restore Postgres from backup or run a schema rollback.

Code rollback is only safe if the previous release can read the migrated schema.
When a migration is not backward-compatible, rolling the image back may make the
old app fail harder.

Schema rollback is available through `FogletBbs.Release.rollback/2`, but it
requires choosing a migration version and understanding the migration's down
path. Do not use it casually on production data.

## Safer default during incidents

When an upgrade fails after migrations have run, prefer this order:

1. Stop the broken release or keep traffic off it.
2. Preserve logs and the current database state.
3. Decide whether the quickest safe fix is roll-forward code, code rollback, or
   database restore.
4. Restore only after you have a known-good backup and approval for destructive
   production data changes.

The board can tolerate a pause. It cannot tolerate a rushed restore that erases
the wrong day.
