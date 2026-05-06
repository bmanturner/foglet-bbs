%{
  title: "Connect over SSH",
  weight: 40
}
---

Foglet's main interface is the SSH terminal UI. This page covers how callers
connect, what the host-key prompt means, and how public-key correlation differs
from ordinary shell login.

## Basic connection

Use a normal OpenSSH client:

```bash
ssh HOST -p PORT
```

For a local development server:

```bash
ssh localhost -p 2222
```

For a public server exposed on the standard SSH port, the command may be only:

```bash
ssh bbs.example.net
```

If you need to choose a specific client key:

```bash
ssh -i ~/.ssh/id_ed25519 HOST -p PORT
```

## Host-key trust

The first time you connect, your SSH client asks whether to trust the server's
host key. That key identifies the BBS server, not your user account.

Accept it only when the hostname and fingerprint are the ones your sysop gave
you. After acceptance, your client records the key in `known_hosts` and warns if
it changes later.

A changed host key can mean either:

- the sysop replaced or lost the server host key, or
- you are not reaching the same server.

Stop and verify before removing a `known_hosts` entry for a public or shared
BBS. Operators should keep `SSH_HOST_KEY_DIR` on persistent storage so callers
do not have to re-trust the host after every deploy.

## Authentication model

Foglet's SSH daemon advertises `publickey` authentication only. It accepts the
public key your client offers so the application can decide what identity, if
any, that key belongs to.

That means:

- the SSH transport does not prompt for your Foglet password.
- password login happens inside the TUI.
- an unknown SSH key can still reach the login or guest flow.
- a known SSH key can start an authenticated session for its account.

This is intentional. Foglet needs the offered key before the terminal UI starts,
so it can correlate returning callers without turning the SSH layer into the
account system.

If your client refuses to connect because it has no key to offer, create one or
point SSH at an existing key:

```bash
ssh-keygen -t ed25519 -C "you@example.net"
ssh -i ~/.ssh/id_ed25519 HOST -p PORT
```

## Usernames in the SSH command

OpenSSH accepts commands like:

```bash
ssh HANDLE@HOST -p PORT
```

Foglet does not trust that SSH username as proof of identity. Account identity
comes from a matched public key or from signing in inside the TUI. The username
can still be useful as a client-side habit or for sysop log context, but it is
not a passwordless login by itself.

## Guest and login flow

When guest mode is enabled, unknown callers can enter the read-only guest flow
where the TUI allows it. When guest mode is disabled, unknown callers are routed
toward login or registration instead.

Actual access still depends on account status and site configuration. Users who
must verify email, are pending approval, or are disabled can connect but are
shown the appropriate gate instead of the normal board list.

## Terminal expectations

Foglet expects an interactive terminal session. Use a modern terminal emulator
and a normal SSH client. Window resize events are forwarded to the TUI, so the
interface should redraw when you resize the terminal.

If the screen looks garbled:

- reconnect from a modern terminal.
- avoid piping SSH through non-interactive wrappers.
- try a wider terminal before reporting a layout bug.

## Common SSH failures

| Symptom | Likely cause | What to do |
| --- | --- | --- |
| `Connection refused` | The SSH daemon is not listening on that host/port. | Check the server is running and confirm `FOGLET_SSH_PORT` or host port mapping. |
| `Permission denied (publickey)` | The client did not offer a usable key, or the server rejected the handshake before the TUI could start. | Run `ssh -v HOST -p PORT` and confirm a key is offered. |
| Host-key warning | The server identity changed from what your client recorded. | Verify with the sysop before removing `known_hosts` entries. |
| You see login even though you added a key | The offered key may not match the key on the account. | Use `ssh -i` with the expected private key, then check account SSH key settings after login. |
