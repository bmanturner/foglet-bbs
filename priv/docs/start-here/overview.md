%{
  title: "Overview",
  weight: 10
}
---

Foglet is an SSH-first bulletin board system. This page explains what it is,
what it is not, and whether you are in the right place.

Foglet's front door is SSH. Callers connect with a normal SSH client and use a
terminal UI for registration, login, boards, threads, replies, account settings,
SSH keys, oneliners, door games, and the sysop workflows that are implemented in
the TUI.

The Phoenix web endpoint is still important, but it is not the product surface.
It serves the home page, these public docs, the `/up` health check, development
LiveDashboard when dev routes are enabled, PubSub, telemetry, mail plumbing, and
other operational infrastructure. Foglet is not a browser forum.

## What Foglet is for

Foglet fits when you want:

- a small self-hosted community with a sysop in charge;
- terminal-native access over SSH, not a web-first forum;
- named categories and boards, threaded discussion, replies, read state, and
  stable per-board message numbers;
- password login and SSH public-key login after a user has a key on file;
- operator-owned registration, invites, account status, roles, boards, runtime
  settings, and moderation flows where those features are implemented;
- an in-TUI inbox for durable notifications such as replies and @mentions;
- door games that hand off the caller's terminal session and return to the BBS
  when the door exits.

Foglet is built with Elixir/OTP, Phoenix, Postgres, and Raxol. Postgres is the
durable store. OTP processes, ETS caches, PubSub, and per-board servers are
runtime machinery and must be recoverable after restart.

## What Foglet is not

Do not run Foglet as though these exist today:

- an end-user web forum;
- a browser admin console;
- a hosted Foglet cloud service;
- federation;
- a mobile app;
- direct messages or private mail;
- email digests;
- webhook notifications;
- a full case-management moderation suite.

If you need one of those as a hard requirement, Foglet is probably not the right
system yet.

## Public docs map

Start here if you are deciding whether to run Foglet:

- [Requirements](/docs/start-here/requirements) covers the tools, services,
  ports, and persistent state Foglet expects.
- [Quickstart](/docs/start-here/quickstart) gives the shortest local path from
  clone to SSH login.
- [Manual setup](/docs/installation/manual-setup) expands the local setup path
  and common variants.
- [Environment configuration](/docs/configuration/environment) covers deploy-time
  environment variables.
- [Health and logs](/docs/operations/health-and-logs) covers `/up`, logs, and
  startup checks.

Contributor-only material, QA credentials, internal planning notes, and test
harness details are intentionally left out of these operator docs.
