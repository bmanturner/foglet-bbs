%{
  title: "Architecture overview",
  description: "How the application is laid out at a glance.",
  weight: 1
}
---
# Architecture overview

Foglet is a single OTP application running on the BEAM. It exposes two
network-facing interfaces:

1. **SSH server** — the primary user interface. Each connection drives a TUI.
2. **Phoenix endpoint** — Channels (for the future Go CLI client),
   LiveDashboard (sysop-only observability), and this read-only `/docs`
   surface.

Both interfaces terminate into the same domain core: boards, threads, posts,
sessions, presence, chat, moderation. There is one source of truth for
durable state (Postgres) and one for ephemeral state (ETS, via Phoenix
Presence and local tables).

For the full breakdown, see `docs/ARCHITECTURE.md` in the repository.

## Where things live

| Namespace | Responsibility |
|---|---|
| `Foglet.*` | Application/domain (accounts, boards, threads, posts, sessions). |
| `FogletBbs.*` / `FogletBbsWeb.*` | Phoenix infrastructure (endpoint, router, channels). |
| `Foglet.SSH.*` | Erlang `:ssh` daemon and channel integration. |
| `Foglet.TUI.*` | Raxol app, screens, widgets — the user-facing terminal UI. |
