# Public Documentation Outline

This outline proposes the public-facing Foglet BBS documentation structure for
the NimblePublisher docs surface under `priv/docs/<category>/<page>.md`.

The goal is to build the docs in baby steps: start with the operator journey
that makes a self-hosted instance understandable, runnable, configurable, and
recoverable, then grow outward into deeper administration, user, and advanced
feature guides.

## Recommended Shape

### Start Here

- `overview` - What Foglet is: an SSH-first bulletin board system, with Phoenix
  as supporting infrastructure, not the main product UI.
- `requirements` - Runtime requirements: Elixir/Erlang release expectations,
  Postgres, SSH port, HTTP health port, SMTP optionality, persistent
  storage.
- `quickstart` - Fast local path from clone to first SSH connection. Keep it
  honest and minimal.

### Installation

- `manual-setup` - Source setup with deps, database creation/migration/seeds,
  host key generation (might be automatic, verify), and starting the app.
- `docker` - Docker image/container expectations, required environment
  variables, mounted persistent paths, database connection, exposed ports.
- `first-sysop` - Creating/promoting the first sysop via Mix tasks, then
  connecting over SSH.
- `connect-over-ssh` - SSH client basics, host key trust, default port behavior,
  public-key correlation, guest/read-only behavior.

### Deployment

- `production-checklist` - A preflight list: `DATABASE_URL`,
  `SECRET_KEY_BASE`, `PHX_HOST`, SSH host key persistence, SMTP, health check,
  backups.
- `fly-io` - Because the repo already has Fly deployment shape. Cover release
  command, ports, persistent mount, secrets, and caveats.
- `vps` - Later. Systemd/reverse proxy/firewall-oriented deployment for
  operators not using Fly or Docker.

### Configuration

- `environment` - Deploy-time environment variables: `DATABASE_URL`,
  `SECRET_KEY_BASE`, `PHX_HOST`, `PORT`, `FOGLET_SSH_PORT`,
  `SSH_HOST_KEY_DIR`, SMTP vars, timezone, guest mode.
- `site-settings` - DB-backed sysop-editable config: registration mode, invite
  generation policy, post/title limits, email delivery mode, verification,
  guest mode, invite caps.
- `email` - SMTP setup, no-email mode, verification/reset behavior, and sysop
  test email.

### Administration

- `users-and-roles` - `user`, `mod`, `sysop`; account statuses; what each role
  can do.
- `registration-and-invites` - Open, invite-only, sysop-approved registration;
  invite generation/revocation; pending approvals/rejections.
- `categories-and-boards` - Category/board organization, readable/postable
  policies, archived state, subscriptions.
- `threads-and-posts` - Threads, replies, locked/sticky state, soft deletion,
  upvotes, stable message numbers.
- `moderation` - Current moderation scope: lock/unlock, sticky, move/delete,
  oneliner hiding, audit trail. Avoid promising reports/sanctions until
  implemented.

### User Guide

- `terminal-basics` - How to navigate the SSH TUI, sign in/register, use account
  settings, and understand guest mode.
- `reading-and-posting` - Boards, threads, replies, read state, unread counts,
  subscriptions.
- `profile-and-ssh-keys` - Public profile fields, preferences, SSH keys,
  password recovery basics.

### Door Games

Door Games need a dedicated category. The existing docs already show that this
is a large product area with operator setup, runtime boundaries, manifest
validation, PTY behavior, classic BBS compatibility, sandbox caveats, TUI
handoff, and QA concerns.

- `overview` - What door games are in Foglet: full-terminal handoff over the
  caller's existing SSH session, then return to the BBS when the door exits.
  Cover the three supported registration styles: native Elixir doors, external
  executable/PTTY doors, and classic/dropfile doors.
- `support-status` - Current support boundaries. Door manifests are validated
  configuration data, not persisted database rows yet. There is no in-BBS door
  catalog editor yet. DOSBox/dosemu-style historical door compatibility is a
  future/experimental tier, not current support.
- `operator-setup` - How sysops install and expose doors: where door files live,
  using absolute `command` and `working_dir` paths, executable permissions,
  Python 3/PTTY helper requirement for `external_pty`, persistent deployment
  paths, and how to disable doors during an incident.
- `demo-doors` - The built-in demo/test doors and the
  `FOGLET_ENABLE_DEMO_DOORS` deployment switch. Make clear that this is for
  local development, QA, demos, and release verification, not normal caller
  copy or a future persisted catalog policy.
- `manifest-reference` - Full manifest field reference.
- `visibility-and-launch-policy` - Explain `:members`, `:mods_only`,
  `:sysop_only`, `:site`, future board scope shape, browsable versus launchable
  checks, guest behavior, and why launch eligibility is rechecked at runtime.
- `native-elixir-doors` - How to write first-party doors that implement
  `Foglet.Doors.Door`, when native doors are appropriate, callback shape,
  terminal resize handling, exit behavior, and cautions about running inside
  Foglet's OTP boundary.
- `external-pty-doors` - How to wrap Python, Node, Go, Rust, C, shell, or other
  terminal programs. Cover PTY helper behavior, structured `command` + `args`,
  context file, `FOGLET_*` env, `env -i`, timeouts, idle timeouts, process
  cleanup, and plain/script fallback caveats.
- `classic-dropfile-doors` - Classic compatibility contract for `CHAIN.TXT`,
  `DOOR.SYS`, and `DORINFO.DEF`. Explain generated per-launch working
  directories, `FOGLET_DROPFILES`, CRLF line endings, mappings, and why this is
  a compatibility bridge rather than full DOS-era door support.
- `adapter-contract` - Contract for modern external wrappers: read
  `FOGLET_DOOR_CONTEXT`, avoid logging context/dropfiles/input/output, preserve
  exit status, restore terminal state, and return cleanly to Foglet.
- `security-and-sandboxing` - External/classic doors are untrusted programs.
  Document what Foglet does and does not pass to doors, sensitive env rejection,
  audit redaction, timeout/disconnect cleanup, restricted-user/process-group
  sandbox mode, fail-closed behavior, and explicit limits: no filesystem,
  network, seccomp, namespace, container, microVM, or broad resource isolation
  is promised by the current baseline.
- `deployment-profiles` - Door-specific deployment posture: local POSIX dev,
  single Linux/systemd host with a distinct `foglet-door` user, Docker/Fly
  limitations.
- `runtime-boundary` - Process/supervision model: screen emits launch effect,
  App effects start `Foglet.Doors.Runner`, runner owns native callbacks,
  external ports, PTY helper protocol, timers, resize, context/dropfile cleanup,
  disconnect cleanup, and exit notification. Keep this public enough for
  operators debugging doors, with deeper internals linked for contributors.
- `tui-flow` - Door Games selector behavior: menu visibility only when doors
  are available, arrows select, Enter confirms, Esc backs out, launch copy,
  normal/crash/timeout return copy, and terminal-size expectations.
- `troubleshooting` - Missing door, immediate return, non-zero exit, timeout,
  bad permissions, missing Python/PTTY helper, sandbox user/group problems,
  wrong terminal state after exit, resize issues, needing extra env vars, and
  Docker/Fly sandbox divergence.
- `qa-and-release-checks` - Contributor/release-verification page for demo door
  gates, SSH harness scenarios, render checks, launch/return evidence,
  timeout/crash/disconnect cleanup, resize behavior, and privacy-safe logging.
  Keep seeded QA credentials and harness scripts here, not in normal operator
  docs.

### Operations

- `health-and-logs` - `/up`, application logs, SSH startup issues, doctor task
  if appropriate.
- `mix-tasks` - Operator CLI reference for Foglet-specific Mix tasks: creating
  and promoting users, approving/rejecting pending users, managing invites,
  inspecting verification/reset tokens, board subscriptions, board chat, QA
  mode, TUI rendering, and environment checks. Distinguish production-safe
  operator tasks from contributor/testing-only tasks.
- `backups-and-restore` - Postgres, runtime config rows, SSH host keys, secrets,
  persistent data. This should be early, not an afterthought.
- `upgrades` - Migrations, release-safe seeds, backup-before-upgrade, rollback
  expectations.
- `troubleshooting` - Symptom-based: database connection, missing environment
  variables, SSH login/port/firewall, SMTP, migrations, host keys.

### Concepts

- `architecture` - Small public architecture sketch: SSH/TUI primary surface,
  Phoenix docs/health/dashboard infrastructure, Postgres durable state,
  ETS/processes ephemeral.
- `data-model` - Public concepts only: users, categories, boards, threads,
  posts, read pointers, soft deletion (tombstone user), message numbers.
- `permissions` - Operator-friendly permissions matrix for sysops, mods, users,
  guests.

### Advanced / Later

- `board-chat` - Ephemeral/permanent board chat, retention, guest behavior.
- `development` - Contributor-only local dev/testing docs. Keep QA seeded
  accounts, harness scripts, `mix foglet.tui.render`, and Raxol internals here,
  not in public operator docs.

## Source Inputs

This outline reconciles two discovery tracks:

- A self-hosting documentation taxonomy based on first-principles operator
  needs and examples from current self-hostable projects such as Discourse,
  Mastodon, Synapse, Rocket.Chat, Plausible, Umami, and Coolify.
- A Foglet-specific codebase review covering SSH/TUI operation, runtime
  configuration, sysop administration, categories, boards, roles, permissions,
  registration, invites, moderation, deployment, and operational concerns.
- Existing Door Games docs under `docs/DOOR_GAMES.md`,
  `docs/DOOR_RUNTIME.md`, `docs/DOOR_GAMES_DATA_CONTRACT.md`,
  `docs/DEPLOYMENT.md`, `docs/ux/door-games-tui.md`, and
  `docs/qa/door-games-qa-strategy.md`.

## Keep Out Of Public Operator Docs

- QA seeded accounts, fixed QA passwords, QA Gates boards, and SSH harness
  scripts. These belong in contributor/testing docs.
- `mix foglet.tui.render`, render fixtures, and layout smoke patterns.
- `.planning/`, phase IDs, GSD artifacts, and internal review notes.
- Vendored `docs/raxol/**` content as canonical product documentation.
- Secrets, real host private keys, database URLs, Fly tokens, SMTP credentials,
  reset tokens, invite codes, and verification codes.
- Future or roadmap-only features such as full sanctions, reports,
  `mix foglet.archive`, and multi-node SSH clustering, except where explicitly
  called out as not yet supported.
