%{
  title: "Health and logs",
  weight: 10
}
---

This page covers the operational signals Foglet exposes today: the HTTP health
check, application logs, and the local doctor task. Use it when the board is
running badly or you need to prove a deploy is alive.

Foglet is SSH-first. The Phoenix HTTP endpoint exists for operations and docs;
it is not the caller-facing product surface.

## Health check

```sh
curl -fsS http://127.0.0.1:4000/up
```

`/up` is routed outside the browser pipeline and returns a simple health result
from `FogletBbsWeb.HealthController`. In production the HTTP listener defaults
to `PORT=4000`; Fly.io maps that internal port through its HTTP service and uses
`/up` as the committed health check.

A passing `/up` check means the Phoenix endpoint is answering. It does not prove
that callers can sign in over SSH, that Postgres migrations are current, or that
SMTP is configured.

## SSH listener check

```sh
ssh -p 2222 your-handle@your-host
```

The SSH daemon defaults to port `2222` unless `FOGLET_SSH_PORT` is set. On Fly,
`fly.toml` exposes public TCP port `22` and maps it to the app's SSH port.

If SSH fails but `/up` passes, check:

- the configured `FOGLET_SSH_PORT` value
- firewall or platform TCP service rules
- whether the release logs show SSH startup errors
- whether `SSH_HOST_KEY_DIR` points at a readable persistent directory

## Logs

Use your process manager or platform log stream. For a local Phoenix server,
logs print to the terminal that started the app:

```sh
mix phx.server
```

For a release, use the release process logs from your host, container runtime,
or platform:

```sh
fly logs --app foglet-bbs
```

The application currently relies on standard Elixir/Phoenix logging and platform
log collection. No Prometheus, OTLP, Sentry, PagerDuty, or external telemetry
exporter is wired by the committed configuration.

## Local doctor task

```sh
mix foglet.doctor
```

`mix foglet.doctor` runs safe local checks only. It does not make network calls
outside the configured database and does not mutate the database. It verifies:

- the Elixir version in `.tool-versions`
- the Erlang/OTP major version in `.tool-versions`
- database reachability
- the `citext` extension created by the first migration
- SSH host key presence
- basic environment-variable shape

Doctor is most useful before starting a local instance or after changing local
toolchain/database settings. In production, prefer platform health checks and
release logs; Mix may not be present in a release image.

## What a healthy deploy proves

Before calling a deploy healthy, check both surfaces:

1. HTTP `/up` answers.
2. The SSH port accepts a connection and reaches the Foglet login flow.
3. Logs show no repeated Repo, SSH host key, migration, or SMTP startup errors.
4. Returning callers see the same SSH host key fingerprint as before the deploy.

That last point matters. The host key is the board's network identity. If it
changes unexpectedly, callers get trust warnings and the board feels replaced.
