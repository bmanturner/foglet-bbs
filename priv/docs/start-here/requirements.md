%{
  title: "Requirements",
  weight: 20
}
---

Foglet needs an Elixir runtime, Postgres, an SSH port, an HTTP health/docs port,
and persistent storage for production secrets and host keys. This page lists the
practical requirements before you install it.

## Development toolchain

Use the repository's `.tool-versions` file as the source of truth for local
development. At the time this page was written it pins:

- Elixir `1.19.5-otp-28`
- Erlang/OTP `28.3.1`

The Mix project currently declares `elixir: "~> 1.17"`, but the repo toolchain is
what contributors and local operators should install. Use `mise`, `asdf`, or an
equivalent version manager that can read `.tool-versions`.

You also need:

- Git;
- a POSIX-like shell;
- OpenSSH client tools for connecting to the BBS;
- `ssh-keygen` if you need to create or rotate SSH host keys;
- Docker Compose if you want the repo's local Postgres path.

## Database

Foglet uses Postgres through Ecto. Postgres is the durable store for users,
boards, threads, posts, read pointers, runtime configuration rows, invites,
tokens, and other application data.

For local development, the repository provides a `postgres` service in
`docker-compose.yml`. The default development configuration expects Postgres on
`localhost` with the local credentials configured in `config/dev.exs`. If another
local database already owns port `5432`, run the Compose service on another host
port and set `DATABASE_URL` for the Mix command you are running.

Production requires `DATABASE_URL`. `config/runtime.exs` raises on boot in
`prod` when it is missing.

## Network ports

Foglet has two important listeners:

- SSH: the primary product surface. The default application port is `2222`, and
  `FOGLET_SSH_PORT` overrides it.
- HTTP: the Phoenix endpoint for the home page, `/docs`, and `/up`. The default
  port is `4000`, and `PORT` overrides it.

Expose the SSH port to callers. Expose HTTP only as your deployment requires for
health checks, docs, or a small public landing page. The web endpoint is not an
end-user forum UI.

## SSH host key persistence

The SSH daemon needs a host key. Development can use the repository's local
`priv/ssh` key material. Production should use its own host key, stored on
persistent storage and referenced with `SSH_HOST_KEY_DIR`.

Back up the host key directory. If you lose it, SSH clients will see the BBS as a
new host and users will have to re-trust it. That is not data loss, but it is a
trust event and looks like trouble to callers.

## Required production environment

At minimum, production needs:

- `DATABASE_URL`
- `SECRET_KEY_BASE`
- `PHX_HOST`

`PHX_HOST` defaults to `example.com` in runtime config if unset, but set it for a
real deployment. Generate `SECRET_KEY_BASE` with:

```bash
mix phx.gen.secret
```

Optional but common production variables include:

- `PORT` for the Phoenix HTTP port;
- `FOGLET_SSH_PORT` for the SSH daemon port;
- `SSH_HOST_KEY_DIR` for persistent SSH host keys;
- `FOGLET_DEFAULT_TIMEZONE` for new users and unauthenticated sessions;
- `FOGLET_GUEST_MODE_ENABLED` to enable or disable guest access;
- `FOGLET_MAIL_FROM` and `FOGLET_SMTP_*` variables for outbound mail;
- `FOGLET_DOOR_MANIFEST_DIR` if you operate door games from JSON manifests.

See [Environment configuration](/docs/configuration/environment) for the fuller
reference.

## Email

Foglet can run locally with the Swoosh local mail adapter. Production SMTP is
configured through environment variables such as `FOGLET_SMTP_RELAY` or
`FOGLET_SMTP_HOST`, port, username, password, TLS, SSL, and auth settings.

If SMTP is not configured, do not assume password reset or verification email can
reach users. Use operator tasks for break-glass token inspection only when that
is appropriate for your deployment.

## Terminal expectations

Callers need an SSH client and a real terminal. The TUI is designed for normal
terminal input, resize events, and full-screen rendering. Browser access to
`/docs` is useful for reading, but it does not replace SSH access to the BBS.
