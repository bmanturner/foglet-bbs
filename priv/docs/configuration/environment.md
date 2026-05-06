%{
  title: "Environment",
  weight: 10
}
---

Environment variables are the deploy-time control surface for Foglet BBS. Set
these before the application boots. Changing them later requires a restart or a
new release boot; live sysop settings live in the database-backed SITE and
LIMITS screens instead.

Keep secrets in your deployment environment or secret manager. Do not put
`DATABASE_URL`, `SECRET_KEY_BASE`, SMTP passwords, or SSH private keys in the
runtime configuration table.

## Production minimum

A production boot needs at least the database URL and Phoenix secret key base.
Most deployments also set the public host, HTTP port, SSH port, and SSH host-key
location explicitly.

```sh
export DATABASE_URL='ecto://USER:PASS@HOST/DATABASE'
export SECRET_KEY_BASE='<generated-secret-key-base>'
export PHX_HOST='bbs.example.net'
export PORT='4000'
export FOGLET_SSH_PORT='2222'
export SSH_HOST_KEY_DIR='/data/ssh'
```

Generate `SECRET_KEY_BASE` with:

```sh
mix phx.gen.secret
```

## Environment variable reference

| Variable | Required | Default | What it controls |
| --- | --- | --- | --- |
| `DATABASE_URL` | Required in production | none | Postgres connection URL. Production raises at boot if it is missing. Development may also use it to override the local repo config. |
| `SECRET_KEY_BASE` | Required in production | none | Phoenix signing/encryption secret. Production raises at boot if it is missing. |
| `PHX_SERVER` | Usually set for releases | unset | Enables the Phoenix endpoint server when present. |
| `PHX_HOST` | Recommended in production | `example.com` | Public host used in the Phoenix endpoint URL. |
| `PORT` | Optional | `4000` | HTTP port for the Phoenix endpoint. This serves docs, health, and supporting Phoenix surfaces; SSH remains the primary product UI. |
| `POOL_SIZE` | Optional in production | `10` | Ecto database connection pool size. |
| `ECTO_IPV6` | Optional in production | false | Set to `true` or `1` to add IPv6 socket options for the database connection. |
| `DNS_CLUSTER_QUERY` | Optional in production | unset | DNS query string stored as `:foglet_bbs, :dns_cluster_query`. The current public docs do not promise multi-node SSH clustering. |
| `FOGLET_SSH_PORT` | Optional | `2222` | Overrides the SSH daemon listen port in every environment. |
| `SSH_HOST_KEY_DIR` | Optional in production | `priv/ssh` | Directory containing SSH host key files. Use persistent storage in production. |
| `FOGLET_DEFAULT_TIMEZONE` | Optional | OS timezone, then `Etc/UTC` | Default IANA timezone for new registrations and unauthenticated sessions. Invalid values are rejected at startup. |
| `FOGLET_GUEST_MODE_ENABLED` | Optional | DB-backed setting | Boot-time override for Guest Mode. Accepted values: `true`, `false`, `1`, `0`; invalid values fail startup. |
| `FOGLET_DOOR_MANIFEST_DIR` | Optional | unset | Directory for operator-managed Door Games manifests. When unset or blank, production/operator door loading is disabled. |
| `FOGLET_MAIL_FROM` | Optional | `no-reply@localhost` | Sender address used for transactional email. |
| `FOGLET_SMTP_RELAY` | Optional | unset | SMTP relay hostname. Setting this enables the SMTP adapter. |
| `FOGLET_SMTP_HOST` | Optional | unset | Backward-compatible SMTP relay hostname; used when `FOGLET_SMTP_RELAY` is not set. |
| `FOGLET_SMTP_PORT` | Optional with SMTP | `587` | SMTP port. |
| `FOGLET_SMTP_USERNAME` | Optional with SMTP | unset | SMTP username. |
| `FOGLET_SMTP_PASSWORD` | Optional with SMTP | unset | SMTP password. Keep it in secrets storage. |
| `FOGLET_SMTP_SSL` | Optional with SMTP | false | Set to `true` or `1` for implicit SSL. |
| `FOGLET_SMTP_TLS` | Optional with SMTP | `if_available` | STARTTLS mode passed to Swoosh as an atom, such as `always`, `never`, or `if_available`. |
| `FOGLET_SMTP_AUTH` | Optional with SMTP | `if_available` | SMTP auth mode passed to Swoosh as an atom, such as `always`, `never`, or `if_available`. |
| `FOGLET_ENABLE_DEMO_DOORS` | Optional | unset | Enables bundled demo/test door manifests when truthy (`true`, `1`, `yes`). This is for development, demos, and release checks, not normal operator policy. |
| `MIX_TEST_PARTITION` | Test only | unset | Suffix for partitioned test database names. |

## Development `.env.local`

In development only, `config/runtime.exs` loads `.env.local` with Dotenvy before
reading the rest of the runtime environment. Real environment variables win over
file values.

Use this for local convenience, not production secret management:

```sh
# .env.local
DATABASE_URL=ecto://postgres:postgres@localhost/foglet_bbs_dev
FOGLET_SSH_PORT=2222
FOGLET_DEFAULT_TIMEZONE=America/Chicago
```

There is no required checked-in `.env.local` template. Treat your local file as
private.

## SSH host keys

Foglet's SSH daemon reads host keys from `SSH_HOST_KEY_DIR` in production, or
`priv/ssh` by default. The Erlang SSH callback looks for standard host-key file
names such as `ssh_host_ed25519_key` and `ssh_host_rsa_key`.

The repository includes an Ed25519 host key for development. Do not reuse that
key for a public system. Generate or mount a production host key in persistent
storage and keep its permissions tight.

Example:

```sh
mkdir -p /data/ssh
ssh-keygen -t ed25519 -f /data/ssh/ssh_host_ed25519_key -N ''
chmod 700 /data/ssh
chmod 600 /data/ssh/ssh_host_ed25519_key
```

If callers see the host key change unexpectedly, stop and verify the mounted
key directory before asking them to trust the new key. A changed SSH host key is
a security event until proven otherwise.

## Precedence

Configuration layers apply in this order:

1. Base and environment-specific files in `config/` are compiled into the build.
2. `config/runtime.exs` reads environment variables at boot.
3. `Foglet.Config` reads and writes live, DB-backed sysop settings.

Use environment variables for deployment shape and secrets. Use sysop settings
for live site policy.
