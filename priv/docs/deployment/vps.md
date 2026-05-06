%{
  title: "VPS",
  weight: 30
}
---

Foglet does not ship a complete VPS deployment bundle yet. There is no committed
`systemd` unit, reverse-proxy config, firewall script, or bare-metal install
script. This page describes the supported shape for operators who want to adapt
the OTP release to a single Linux host without pretending that a turnkey VPS
runbook exists.

If you need the lowest-friction path today, use the Docker image or the committed
Fly.io configuration. If you run a VPS, keep your local runbook with the host.
The repo is not the only source of truth for your firewall, TLS, backups, or OS
hardening.

## Supported shape

A VPS deployment should look like this:

- one Linux host
- Postgres reachable by `DATABASE_URL`
- one Foglet OTP release running as a non-root application user
- persistent storage for SSH host keys and any operator-managed door files
- SSH daemon bound to an internal or public port of your choice
- Phoenix endpoint bound to an HTTP port behind TLS termination or a reverse
  proxy
- a service manager such as `systemd` to restart the release after crashes or
  host reboot

Phoenix is supporting infrastructure. Do not frame the reverse proxy as the main
product surface; callers dial in over SSH.

## Build or obtain a release

The Dockerfile is the committed production image path. For a bare release, build
an OTP release with the repository's Elixir/Erlang versions and copy the
`_build/prod/rel/foglet_bbs` output to the host.

```sh
MIX_ENV=prod mix deps.get --only prod
MIX_ENV=prod mix compile
MIX_ENV=prod mix release
```

The release contains `bin/foglet_bbs`. The checked-in release overlay also
provides `bin/server` and `bin/migrate` scripts in release builds.

## Runtime environment

Set at least:

```sh
DATABASE_URL='ecto://USER:PASS@HOST/DATABASE'
SECRET_KEY_BASE='<generated-secret-key-base>'
PHX_SERVER='true'
PHX_HOST='bbs.example.net'
PORT='4000'
FOGLET_SSH_PORT='2222'
SSH_HOST_KEY_DIR='/srv/foglet/ssh'
```

Generate the secret with:

```sh
mix phx.gen.secret
```

Store these values in your service manager's environment file or secret store.
Do not commit them. Do not put them in Foglet's DB-backed configuration table.

## Host-key setup

Generate production SSH host keys once and keep them on persistent,
access-controlled storage:

```sh
install -d -o foglet -g foglet -m 0700 /srv/foglet/ssh
ssh-keygen -t ed25519 -f /srv/foglet/ssh/ssh_host_ed25519_key -N ''
chown foglet:foglet /srv/foglet/ssh/ssh_host_ed25519_key /srv/foglet/ssh/ssh_host_ed25519_key.pub
chmod 0600 /srv/foglet/ssh/ssh_host_ed25519_key
```

Back up this directory. A changed host key tells every returning caller that the
server identity changed.

## Service manager sketch

No unit file is committed. A minimal `systemd` unit would need to set the runtime
environment, run as the `foglet` user, start the release, and restart on failure.
Treat this as a sketch, not a pasted production policy:

```ini
[Unit]
Description=Foglet BBS
After=network-online.target
Wants=network-online.target

[Service]
User=foglet
Group=foglet
WorkingDirectory=/srv/foglet/current
EnvironmentFile=/etc/foglet/foglet.env
ExecStart=/srv/foglet/current/bin/server
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Add host hardening deliberately. Options such as `NoNewPrivileges`,
`ProtectSystem`, `PrivateTmp`, cgroup limits, and restricted door users affect
Door Games and file access. Test them with the exact features you intend to run.

## Reverse proxy and firewall

At minimum:

- forward public HTTPS to the Phoenix `PORT` for docs and `/up`
- expose the Foglet SSH port you chose, often public `22` or `2222`
- block direct database access from the public network
- keep the release user's SSH host-key directory private

The app does not enable TLS itself by default in production. `config/runtime.exs`
contains a commented Phoenix HTTPS example, but the committed Fly deployment
terminates TLS in front of the app. Most VPS deployments should do the same with
a reverse proxy or load balancer.

Health check:

```sh
curl -fsS https://bbs.example.net/up
```

SSH check:

```sh
ssh -p 2222 bbs.example.net
```

Use the port you actually exposed.

## Migrations and seeds

Run release-safe setup from the deployed release:

```sh
/srv/foglet/current/bin/foglet_bbs eval FogletBbs.Release.seed
```

That runs migrations and production-safe seeds. Do not run
`priv/repo/seeds.exs` on a real VPS instance; it creates demo accounts and
sample content.

For rollback, prefer a forward fix. If you must roll back the schema, verify a
backup and run:

```sh
/srv/foglet/current/bin/foglet_bbs eval 'FogletBbs.Release.rollback(FogletBbs.Repo, 20260101000000)'
```

Use the actual migration version you intend to roll back to.

## Backups

Carry at least:

- Postgres backups with restore drills.
- `/srv/foglet/ssh` or your chosen `SSH_HOST_KEY_DIR`.
- release tarballs or image references for rollback.
- `/etc/foglet/foglet.env` or whatever secret store replaces it.
- door manifests and persistent door state if you enable Door Games.

Any destructive restore, schema rollback, or manual data repair should name the
backup and target migration before it starts.

## Door Games on a VPS

A VPS can support the stronger external-door baseline better than the current
Docker/Fly image, because the operator can create a distinct OS user for door
processes.

If you enable untrusted external or classic doors:

- keep the Foglet app user and door user separate, such as `foglet` and
  `foglet-door`
- keep door files absolute, operator-owned, and narrowly executable
- prevent the door user from reading app secrets, database URLs, SMTP passwords,
  SSH host private keys, and backups
- verify timeout and disconnect cleanup before opening the door to callers

If you cannot prove the sandbox setup, disable untrusted doors rather than
running them as the app user.
