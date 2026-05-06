%{
  title: "Backups and restore",
  weight: 30
}
---

This page describes what must be backed up for a Foglet instance and how to
think about restore. Backups are not optional decoration; they are how the board
remembers its body after a bad deploy, a bad disk, or a bad command.

Foglet's durable state is split across Postgres, deploy-time secrets, and
persistent files. Back up all three.

## What to back up

### Postgres

Postgres is authoritative for users, roles, registration state, configuration
rows, categories, boards, threads, posts, read pointers, moderation state,
invites, verification records, and password-reset records.

Use your provider's managed backup feature or `pg_dump`:

```sh
pg_dump "$DATABASE_URL" > foglet-$(date +%Y%m%d).sql
```

If you use a managed database, confirm the retention window and test how to
restore into a new database. A backup you have never restored is a rumor.

### SSH host keys

Back up the directory named by `SSH_HOST_KEY_DIR`. On the committed Fly profile,
that is `/data/ssh`.

These keys define the SSH server identity. If they are lost or regenerated,
returning callers will see host-key warnings. That may be the correct recovery
choice after a compromise, but it should never happen by accident.

### Environment secrets

Back up the values or secret-store records for:

- `DATABASE_URL`
- `SECRET_KEY_BASE`
- SMTP credentials (`FOGLET_SMTP_*`) if configured
- platform tokens used to deploy or operate the instance

Do not put secret values in the repository, public docs, issue comments, or
support transcripts.

### Persistent data directory

Back up the persistent data volume used by your deployment. The committed
Docker/Fly baseline uses `/data`, including `/data/ssh`. Door-game data may also
live under persistent paths depending on your deployment profile.

## Before restoring

1. Stop the running app or put it behind maintenance controls so no new writes
   arrive during restore.
2. Record the current app version and migration state if possible.
3. Decide whether this is a full restore, a point-in-time database restore, or a
   host-key/secrets repair.
4. Get explicit approval before destructive production database changes.

## Restore outline

For a simple self-managed Postgres dump restore:

```sh
createdb foglet_bbs_restore
psql foglet_bbs_restore < foglet-YYYYMMDD.sql
```

Then point `DATABASE_URL` at the restored database, keep `SECRET_KEY_BASE` and
`SSH_HOST_KEY_DIR` consistent, and start the app. Run migrations only after you
know which application version will own the restored database.

For a managed provider, prefer its documented point-in-time restore flow. Restore
into a new database first when possible; switch the app over after inspection.

## After restoring

Check both surfaces:

```sh
curl -fsS http://your-host/up
ssh -p 2222 your-handle@your-host
```

Then verify:

- the expected sysop account can sign in
- categories and boards are present
- recent threads/posts match the restore point
- DB-backed site settings match the intended environment
- SSH clients do not report an unexpected host-key change
- logs are free of migration, Repo, and SSH host-key errors

## Rollback and irreversible changes

Application rollback is easier than data rollback. Schema rollback can lose data
if a migration dropped columns, rewrote values, or changed invariants. Treat
schema rollback as a production incident, not a routine deploy step.

If the safer path is to roll forward with a fix, do that. If the safer path is
to restore from backup, preserve the failed database first so the failure can be
understood later.
