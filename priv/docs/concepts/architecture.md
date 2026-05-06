%{
  title: "Architecture",
  weight: 10
}
---

Foglet is an SSH-first bulletin board system. The application runs as one OTP
system: the SSH daemon carries the caller experience, Phoenix serves supporting
HTTP endpoints and public documentation, and Postgres holds durable BBS state.

This page is for operators who want the shape of the system before they run or
troubleshoot it. For contributor-level module notes, see the source tree.

## The public shape

Foglet exposes two network surfaces:

- SSH, for the terminal BBS. This is the product surface callers use.
- HTTP, for Phoenix infrastructure such as health checks, LiveDashboard when
  enabled, and the `/docs` public documentation surface.

There is no separate browser BBS workflow. If an operator wants callers to use
Foglet, they give them the SSH host and port.

```text
caller terminal
    |
    | ssh
    v
Foglet.SSH.Supervisor
    |
    v
Foglet.SSH.CLIHandler
    |
    v
Foglet.TUI.App and screens
    |
    v
Foglet.Accounts / Boards / Threads / Posts / Config
    |
    v
Postgres
```

Phoenix sits beside that SSH path:

```text
browser or health checker
    |
    | http
    v
FogletBbsWeb.Endpoint
    |
    +-- /docs from priv/docs/**/*.md
    +-- Phoenix infrastructure
```

## Supervision at runtime

`FogletBbs.Application` starts the runtime cache and SSH public-key stash, then
starts the supervised children. The current tree includes:

- `FogletBbs.Repo` for Postgres access.
- `Phoenix.PubSub` under `FogletBbs.PubSub`.
- `Foglet.TUI.MinuteClock` for minute-level TUI refreshes.
- `Foglet.Accounts.RedemptionThrottle` for invite redemption throttling.
- `Foglet.BoardRegistry` and `Foglet.Boards.Supervisor` for per-board servers.
- `Foglet.Sessions.Registry` and `Foglet.Sessions.Supervisor` for live sessions.
- Door-game, presence, board-screen, and board-chat supervisors.
- `FogletBbsWeb.Endpoint` for HTTP.
- `Foglet.SSH.Supervisor` when the SSH daemon is enabled.

After the supervisor starts, the application calls `Foglet.Boards.boot_board_servers/0`.
That starts a board server for every non-archived board. Archived boards do not
get active board server processes.

## Durable and ephemeral state

Postgres is the source of truth for accounts, boards, threads, posts,
subscriptions, read pointers, configuration, invites, SSH keys, and other
durable records. If the VM restarts, those records are what Foglet rebuilds
from.

ETS and OTP processes are working memory. They hold things such as runtime
configuration cache entries, public-key correlation during SSH login, presence,
board-server counters, chat buffers, and live session state. Operators should
expect these to disappear on restart. The system is designed to reconstruct the
important pieces from Postgres.

## Context boundaries

The public domain modules are the main trust boundaries:

- `Foglet.Accounts` owns users, roles, statuses, invites, tokens, SSH keys, and
  account deletion.
- `Foglet.Boards` owns categories, boards, subscriptions, board read pointers,
  and board-server boot.
- `Foglet.Threads` owns thread queries, thread read pointers, locking, sticky
  state, moving, and deletion.
- `Foglet.Posts` owns replies, post queries, editing, soft deletion, upvotes,
  and reader windows.
- `Foglet.Config` owns database-backed site settings and the ETS cache.
- `Foglet.Authorization` owns operator authorization checks.

Phoenix controllers and SSH callbacks should hand work to those contexts rather
than owning domain rules themselves. That matters operationally: when behavior
seems wrong, inspect the context first, not the screen that called it.

## Board servers and message numbers

Foglet preserves the old-network idea that a board has stable message numbers.
Thread creation and reply creation route through `Foglet.Boards.Server`, one
GenServer per active board. The board server serializes allocation so two
callers cannot receive the same number on the same board.

On startup, a board server reads the current maximum `posts.message_number` for
its board and resumes at the next number. The database also stores
`boards.next_message_number`, but the server rebuilds from posts so a restart
after a partial failure does not strand the counter.

Message numbers are per-board, not global. Soft-deleted posts keep their
numbers. Foglet does not fill gaps.

## SSH session path

`Foglet.SSH.Supervisor` wraps the Erlang `:ssh` daemon. Each SSH channel is
handled by `Foglet.SSH.CLIHandler`, which connects authentication context,
keyboard input, terminal resize events, and Raxol lifecycle events to the TUI.

The TUI is organized around `Foglet.TUI.App` and screen modules. The app owns
global routing, modals, commands, PubSub subscriptions, and screen switching.
Screens own local rendering and key handling. Widgets render reusable terminal
pieces.

## Public documentation path

The page you are reading is compiled by `FogletBbsWeb.Docs` from Markdown files
under `priv/docs/**/*.md` using NimblePublisher. The URL is based on the folder
and filename; for example, this file lives at `priv/docs/concepts/architecture.md`
and is served under the `concepts` category.

Frontmatter controls title and ordering. The docs surface is public operator
documentation, so it should not include internal planning notes, QA-only
credentials, or future promises that the running code does not support.

## Operational caveats

- Keep Postgres backed up. It is the durable body of the BBS.
- Persist SSH host keys. If host keys change unexpectedly, callers will see SSH
  trust warnings and should treat them seriously.
- Do not rely on in-memory state surviving deploys or restarts.
- If a board is archived, its board server is not started at boot.
- HTTP is supporting infrastructure. Opening HTTP does not create a browser BBS.
