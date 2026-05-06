%{
  title: "Manual setup",
  weight: 10
}
---

This page covers a source checkout setup: install the pinned toolchain, start
Postgres, prepare the database, run Foglet, and confirm that the SSH and HTTP
surfaces are alive. Use this when you are developing Foglet or running it by
hand instead of from the release Docker image.

## Install the pinned runtime

Foglet is an Elixir/Phoenix application with an Erlang `:ssh` daemon and a
Postgres database. The repository pins the working toolchain in
`.tool-versions`:

- Elixir `1.19.5-otp-28`
- Erlang/OTP `28.3.1`

Install those versions with your normal version manager, then verify them from
the repository root:

```bash
elixir --version
mix --version
```

The project declares `elixir: "~> 1.17"` in `mix.exs`, but the pinned versions
are the tested path. The SSH daemon also refuses to start on OTP runtimes older
than the patched baseline for CVE-2025-32433.

## Start Postgres

The local development config expects Postgres on `localhost:5432` with:

- username: `postgres`
- password: `postgres`
- database: `foglet_bbs_dev`

The repository includes a Postgres-only Compose file for that service:

```bash
docker compose -f docker-compose.yml up -d postgres
```

If port `5432` is already occupied, choose another host port and pass a matching
`DATABASE_URL` when you run Mix tasks:

```bash
POSTGRES_PORT=55432 docker compose -f docker-compose.yml up -d postgres
DATABASE_URL=ecto://postgres:postgres@localhost:55432/foglet_bbs_dev mix setup
```

## Prepare the app

From the repository root:

```bash
mix setup
```

`mix setup` is defined in `mix.exs`. It runs:

1. `mix deps.get`
2. `mix ecto.create`
3. `mix ecto.migrate`
4. `mix run priv/repo/seeds.exs`
5. `git config core.hooksPath .githooks`

The seed file is useful for local development, but it is not a production
bootstrap process. It creates development users and QA fixtures. Do not run it
against a production database.

If you need to rebuild local data from scratch, this command drops the dev
database before running the same setup chain:

```bash
mix ecto.reset
```

That wipes local development data.

## Check the environment

After dependencies are installed, run the doctor task:

```bash
mix foglet.doctor
```

The task checks the configured Elixir/Erlang runtime, database readiness, the
`citext` extension, SSH host-key readiness, and required local tools. Treat its
output as a local preflight, not as a substitute for production monitoring.

## Start Foglet

Start the Phoenix endpoint and supervised SSH daemon:

```bash
mix phx.server
```

By default:

- HTTP listens on `localhost:4000` in development.
- SSH listens on port `2222`.
- the public documentation surface is served under `/docs`.
- the health endpoint is `/up`.

Override the SSH port if another service is already using it:

```bash
FOGLET_SSH_PORT=2200 mix phx.server
```

Foglet loads `.env.local` in development before `runtime.exs` reads environment
variables. Real environment variables still win over file values.

## SSH host keys

The SSH daemon needs a host key before it can accept connections. In development
Foglet uses the application `priv/ssh` directory by default. On startup,
`Foglet.SSH.Supervisor` ensures the directory exists and calls
`Foglet.SSH.HostKey.ensure!/1`, which creates a host key when one is missing.

For long-running or shared instances, use a persistent host-key directory and
back it up. Losing the host key does not lose accounts or posts, but every SSH
client will warn that the server identity changed.

Production releases can set:

```bash
SSH_HOST_KEY_DIR=/data/ssh
```

## Connect locally

With the server running, connect with a normal SSH client:

```bash
ssh localhost -p 2222
```

Foglet's SSH daemon advertises public-key authentication only. It accepts the
client's offered key so the TUI can correlate the key with an existing account,
or start a guest/login flow when the key is unknown. Password login happens
inside the TUI, not through the SSH transport.

## Common setup failures

| Symptom | Check |
| --- | --- |
| `mix setup` cannot connect to Postgres | Confirm Postgres is running and that `DATABASE_URL` matches the port you exposed. |
| `mix phx.server` starts HTTP but SSH refuses connections | Check that the SSH daemon is enabled, the configured port is free, and the host-key directory is writable. |
| SSH warns that the host key changed | Confirm you are connecting to the intended instance. If this is your own deployment, restore the previous host key or accept that users must re-trust the server. |
| The terminal looks wrong after connecting | Use a modern terminal and OpenSSH client. The product surface is the SSH terminal UI, not a browser forum. |
