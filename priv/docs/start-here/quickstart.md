%{
  title: "Quickstart",
  weight: 30
}
---

This is the shortest useful local path from a fresh clone to an SSH connection.
It is meant for development or local evaluation, not production deployment.

## 1. Clone the repository

```bash
git clone git@github.com:bmanturner/foglet-bbs.git
cd foglet-bbs
```

Install the Elixir and Erlang/OTP versions pinned in `.tool-versions` before you
run Mix commands.

## 2. Start Postgres

If you do not already have a compatible local Postgres running, use the Compose
service from the repo:

```bash
docker compose up -d postgres
```

If port `5432` is already in use, choose another host port and pass the matching
`DATABASE_URL` to Mix commands, for example:

```bash
POSTGRES_PORT=55432 docker compose up -d postgres
DATABASE_URL=ecto://postgres:postgres@localhost:55432/foglet_bbs_dev mix setup
```

If you used the default Compose port, continue with the next step.

## 3. Set up the app

```bash
mix setup
```

`mix setup` fetches dependencies, creates and migrates the database, runs
`priv/repo/seeds.exs`, and configures the repo's git hooks path.

The normal seed file is for local development. Production releases use the
release-safe seed path instead and should not rely on development sample users,
boards, or fixture content.

## 4. Start Foglet

```bash
mix phx.server
```

This starts the Phoenix endpoint and, unless the application config disables it,
the Erlang SSH daemon. Defaults are:

- HTTP: `http://localhost:4000`
- docs: `http://localhost:4000/docs`
- health check: `http://localhost:4000/up`
- SSH: `localhost:2222`

To use a different SSH port for this run:

```bash
FOGLET_SSH_PORT=2200 mix phx.server
```

## 5. Dial in over SSH

In another terminal, connect with a normal SSH client:

```bash
ssh localhost -p 2222
```

Use the handle you want to register or sign in with. Foglet's TUI owns the
registration, login, account, and board flows after the SSH connection opens.

After your account has an SSH public key on file, public-key login can identify
you directly. Password login remains available where the deployment allows it.

## Quick checks

Use these when the first run does not behave as expected:

| Symptom | Check |
| --- | --- |
| `mix setup` cannot connect to Postgres | Confirm Postgres is running and that `DATABASE_URL` matches the actual host, port, user, password, and database. |
| `docker compose up -d postgres` cannot bind port `5432` | Use another `POSTGRES_PORT` and pass a matching `DATABASE_URL` to Mix. |
| `ssh -p 2222 ...` is refused or hangs | Confirm `mix phx.server` is still running, `:start_ssh_daemon` has not been disabled, and nothing else is using the SSH port. |
| The SSH client warns about a changed host key | You may be pointing at a different Foglet instance or a regenerated host key. Verify before accepting the new key. |
| `/up` does not respond | Confirm the Phoenix endpoint is running and that `PORT` was not changed for this run. |

## Next

For production or longer-lived local operation, continue with:

- [Manual setup](/docs/installation/manual-setup)
- [Environment configuration](/docs/configuration/environment)
- [Production checklist](/docs/deployment/production-checklist)
- [Health and logs](/docs/operations/health-and-logs)
