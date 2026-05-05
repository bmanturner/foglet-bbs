# Door Games

Door games let Foglet hand a caller's existing SSH terminal to a small game or external program, then bring the caller back to the BBS when the door exits.

This guide covers the first Door Games slice. It is for sysops and contributors adding doors to a self-hosted Foglet instance.

## What is supported in this slice

Foglet's first Door Games contract supports three registration styles:

- native Elixir doors that implement `Foglet.Doors.Door`
- external executable doors that run through the supervised door runner
- classic/dropfile doors that use the same external runner path plus generated classic BBS metadata

The first classic format is `CHAIN.TXT`. `DOOR.SYS` and `DORINFO.DEF` are intentionally left behind the same adapter boundary for later work.

For external and classic manifests with `pty?: true`, the supported backend is
Foglet's own helper at `priv/doors/pty/foglet_pty_adapter.py`. The runner starts
that helper through an Erlang Port; the helper opens the child PTY, launches the
configured `command` with structured `args`, bridges input/output with framed
messages, and applies terminal resize using `TIOCSWINSZ` on POSIX hosts. If the
helper is unavailable, Foglet may degrade to `script(1)` when present, then to a
plain pipe. That fallback is for demos/development only: it does not provide the
same resize or process-group cleanup semantics.

Deployment requirement: releases/Docker images that enable `external_pty` doors
need Python 3 and `priv/doors/pty/foglet_pty_adapter.py`. The project Dockerfile
installs Python 3 in the final runtime image and includes the helper via the
release `priv` tree. The FOG-830 baseline adds an optional fail-closed
restricted-user/process-group sandbox contract for helper-backed external doors.

Door manifests are configuration data in this slice. They are not stored in database tables yet, and there is no in-BBS catalog editor yet.

## Safety model

Treat external and classic doors as untrusted programs.

Foglet narrows what a door receives:

- a validated manifest
- a small set of Foglet metadata such as user id, handle, session id, and terminal size
- explicit non-secret manifest `env` entries plus required `FOGLET_*` variables
- a narrow default `PATH` (`/usr/bin:/bin`) when no manifest `PATH` is supplied, so `/usr/bin/env` shebangs can still find interpreters
- a temporary JSON context file for external doors
- generated dropfiles for classic/dropfile doors

External/classic launches use `env -i` across the helper-backed PTY, plain-pipe, and `script(1)` fallback paths, so the child door process does not inherit the BEAM/helper process environment. `env_allowlist` controls which manifest env names may be displayed unredacted in audit metadata; it is not a request to inherit host env.

Foglet does not pass database credentials, app secrets, API keys, private tokens, full user structs, full session structs, or broad inherited host environments to door processes.

This is a baseline sandbox, not full containment. Unsandboxed doors still use allowlisted paths, environment hygiene, timeouts, cleanup, and audit metadata. Sandboxed helper-backed doors add fail-closed restricted OS-user execution plus process-group TERM/KILL cleanup, but they do not isolate filesystem mounts, network, seccomp, namespaces, containers, microVMs, or broad resource access. The approved stronger baseline is documented in `docs/DEPLOYMENT.md`: external/classic doors should run as a restricted OS user plus a per-door process group, and launches must fail closed when the configured restricted user cannot be applied. Docker/Fly currently diverge because the release image runs as `nobody` and cannot switch to a second door user without an approved runtime change. Treat untrusted third-party doors as unsupported on that container path until the divergence is resolved; do not run arbitrary third-party code as a door without an operator-reviewed host/container posture.

## Door manifest fields

A door manifest is validated by `Foglet.Doors.validate_manifest/1` and normalized into `%Foglet.Doors.Manifest{}`.

Required fields:

- `id` — stable internal id, for example `"native-echo"`
- `slug` — stable URL/config-friendly name, for example `"native-echo"`
- `display_name` — name shown to callers, for example `"Native Echo"`
- `description` — one-sentence description for the selector
- `runtime` — one of `:native_elixir`, `:external_pty`, or `:classic_dropfile`
- `timeout_ms` — positive integer timeout in milliseconds
- `visibility` — `:members`, `:mods_only`, or `:sysop_only`
- `auth_scope` — `:site` or `{:board, board_id}`

External and classic doors also require:

- `command` — absolute path to the executable or wrapper
- `working_dir` — absolute working directory

Optional fields:

- `module` — native Elixir module for `:native_elixir` doors
- `args` — list of string arguments
- `env` — explicit non-secret environment variables to pass to the door
- `env_allowlist` — uppercase manifest `env` names safe to show unredacted in audit records
- `idle_timeout_ms` — optional positive integer idle timeout in milliseconds
- `pty?` — whether the external runner should request the supported helper-backed PTY path (`true`) or a plain pipe (`false`)
- `env` — explicit string environment values to pass to the door; sensitive names are rejected
- `sandbox` — optional `%{mode: :restricted_user_process_group, user: "foglet-door", group: "foglet-door", process_tree: :process_group, fail_closed?: true}` contract for helper-backed external doors

Do not put secrets in `env` or `env_allowlist`. Foglet rejects known sensitive names such as database URLs, secret key bases, tokens, and API keys.

## Add a native Elixir door

Use a native Elixir door when the game is small, first-party, and comfortable running inside Foglet's OTP supervision boundary.

Native doors implement `Foglet.Doors.Door`. They receive a narrow launch context and return iodata for Foglet to write back to the terminal. They should not own SSH channel state directly.

Minimal native door shape:

```elixir
defmodule Foglet.Doors.Demo.NativeEcho do
  @behaviour Foglet.Doors.Door

  @impl true
  def init(%{session: session, terminal_size: {cols, rows}}) do
    handle = Map.get(session, :handle) || "guest"
    {:ok, %{size: {cols, rows}}, ["Native Echo ready for ", handle, "\n"]}
  end

  @impl true
  def handle_input("/quit" <> _rest, state) do
    {:stop, :normal, state, "Leaving Native Echo.\n"}
  end

  def handle_input(data, state) do
    {:ok, state, ["echo> ", data]}
  end

  @impl true
  def handle_resize(size, state) do
    {:ok, %{state | size: size}, "resized\n"}
  end
end
```

Register it with a manifest like:

```elixir
%{
  id: "native-echo",
  slug: "native-echo",
  display_name: "Native Echo",
  description: "A tiny first-party echo door for testing the handoff.",
  runtime: :native_elixir,
  module: Foglet.Doors.Demo.NativeEcho,
  timeout_ms: 15 * 60 * 1_000,
  idle_timeout_ms: nil,
  visibility: :members,
  auth_scope: :site
}
```

Then validate it before listing or launching:

```elixir
{:ok, manifest} = Foglet.Doors.validate_manifest(attrs)
```

## Add an external executable door

Use an external executable door when the game is written outside Elixir: Python, Node, Go, Rust, C, a shell script, or another terminal program.

External doors run under `Foglet.Doors.Runner`. Screen reducers do not spawn OS processes; they emit a launch effect, and the app/runtime boundary starts a supervised runner.

Example manifest:

```elixir
%{
  id: "trade-wars-demo",
  slug: "trade-wars-demo",
  display_name: "Trade Wars Demo",
  description: "A small external demo door.",
  runtime: :external_pty,
  command: "/srv/foglet/doors/trade-wars-demo/run.sh",
  args: ["--ansi"],
  working_dir: "/srv/foglet/doors/trade-wars-demo",
  env: %{"TERM" => "xterm-256color", "LANG" => "C.UTF-8"},
  env_allowlist: ["TERM", "LANG"],
  timeout_ms: 30 * 60 * 1_000,
  idle_timeout_ms: 5 * 60 * 1_000,
  visibility: :members,
  auth_scope: :site,
  pty?: true,
  sandbox: %{
    mode: :restricted_user_process_group,
    user: "foglet-door",
    group: "foglet-door",
    process_tree: :process_group,
    fail_closed?: true
  }
}
```

When `pty?: true`, Foglet passes `command` and `args` to the helper as separate
arguments rather than building the production launch path with shell quoting.
Wrappers can still be shell scripts, but shell interpretation is then explicit in
the wrapper you own.

When `sandbox.mode` is `:restricted_user_process_group`, the helper resolves the
configured `user`/optional `group` before launch. If the user/group is missing,
Python/PTY support is unavailable, the Foglet OS process lacks privileges to
drop to that user, or supplementary groups cannot be set to the target user's
intended memberships or cleared, the door fails closed before the command
starts. Foglet never silently falls back to app-user execution for a
sandbox-required manifest. Use a locked-down OS account such as `foglet-door`
with only the filesystem access needed by reviewed door assets.

The runner adds Foglet metadata for the external process:

- `FOGLET_DOOR_ID`
- `FOGLET_USER_ID`
- `FOGLET_USERNAME`
- `FOGLET_SESSION_ID`
- `FOGLET_TERMINAL_WIDTH`
- `FOGLET_TERMINAL_HEIGHT`
- `FOGLET_DOOR_CONTEXT`

`FOGLET_DOOR_CONTEXT` points to a temporary JSON file with the same narrow metadata. The runner removes that file during cleanup.

Keep wrappers boring:

- use absolute paths in manifests
- keep working directories under an operator-owned door directory
- avoid shelling out to arbitrary user input
- do not read app secrets from the environment
- exit with status `0` for normal completion and non-zero for crashes/errors

## Add a classic/dropfile door

Classic/dropfile doors are external doors with extra BBS metadata. Foglet supports
`CHAIN.TXT`, `DOOR.SYS`, and `DORINFO.DEF` generation for these wrappers.

Use `:classic_dropfile` when a wrapper needs classic BBS-style user/session fields. Foglet currently generates dropfile content through:

```elixir
{:ok, text} = Foglet.Doors.classic_dropfile(:chain_txt, %{user: user, session: session})
```

The generated `CHAIN.TXT` lines are CRLF-terminated and ordered as:

1. handle
2. real name or display name
3. terminal columns
4. terminal rows
5. role
6. user id

Example content:

```text
alice\r\nAlice Liddell\r\n132\r\n37\r\nuser\r\nuser-1\r\n
```

A classic door manifest follows the external-door shape, but uses `runtime: :classic_dropfile`:

```elixir
%{
  id: "chain-demo",
  slug: "chain-demo",
  display_name: "CHAIN.TXT Demo",
  description: "A classic door wrapper that reads CHAIN.TXT metadata.",
  runtime: :classic_dropfile,
  command: "/srv/foglet/doors/chain-demo/run.sh",
  args: [],
  working_dir: "/srv/foglet/doors/chain-demo",
  env: %{"TERM" => "xterm-256color"},
  env_allowlist: ["TERM"],
  timeout_ms: 20 * 60 * 1_000,
  idle_timeout_ms: 5 * 60 * 1_000,
  visibility: :members,
  auth_scope: :site,
  pty?: true
}
```

Foglet writes fixed-name dropfiles only inside a runner-owned per-launch working
directory. The child process starts with that isolated directory as cwd, so a
classic program can open `CHAIN.TXT`, `DOOR.SYS`, or `DORINFO.DEF` by filename.
Wrappers can also read the explicit colon-separated paths from `FOGLET_DROPFILES`.
Pre-existing dropfiles in the configured manifest `working_dir` are not
overwritten or removed by runner cleanup.

The wrapper is responsible for passing those generated files to the target
classic program. Do not assume every historical DOS door works yet. Treat these
formats as a compatibility contract, not a full DOS compatibility layer.

## Door list and launch copy

Use this copy for the first terminal UI surface unless the interaction changes:

- menu destination: `Door Games`
- selector title: `Foglet > Door Games`
- empty state: `No door games are available right now.`
- loading state: `Loading door games...`
- load error: `Unable to load door games.`
- confirmation title: `Launch Door Game?`
- confirmation body: `Foglet will hand this terminal to <door name>. When the game exits, you'll return here.`
- external/classic safety line: `If it stops responding, disconnecting will clean up the session.`
- normal return: `<door name> ended. You're back in Foglet.`
- crash return: `<door name> stopped unexpectedly. You're back in Foglet.`
- timeout return: `<door name> timed out. You're back in Foglet.`

Keep the selector simple: arrows choose a door, Enter opens confirmation, and Esc goes back. Do not ask callers to type door ids, slugs, runtime names, or config values.

## Troubleshooting

### The door is missing from the list

Check that the manifest validates, the current caller is allowed by `visibility`, and the launch path rechecks `Foglet.Doors.launchable?/2` before starting the runner.

### The door launches and immediately returns

Check the external command, working directory, executable permissions, and exit status. Foglet treats non-zero external exits as crashes.

### The door times out

Increase `timeout_ms` or `idle_timeout_ms` only after confirming the door is healthy. Timeouts are part of the cleanup and safety model.

### The terminal looks wrong after exit

The door may have left the terminal in an unusual mode or used unsupported full-screen behavior. Prefer wrappers that restore terminal state before exit, and capture SSH harness evidence before enabling the door for real users.

### A door needs more environment variables

Add only specific non-secret values to manifest `env`, and add the same names to `env_allowlist` only when those values are safe to display unredacted in audit records. Do not allowlist or pass database URLs, app secrets, API keys, tokens, or broad inherited environments.

## Copy review checklist

Before shipping a new door surface or guide, verify:

- callers are never asked to type slugs, ids, schema names, env var names, or magic values
- launch copy explains full-terminal takeover without sounding alarming
- error copy is short and recoverable; logs carry technical detail
- docs distinguish current support from future hardening
- external/classic docs do not imply full sandboxing
- examples use fake paths and fake user ids only
- examples do not contain credentials, private tokens, or production paths
- TUI copy has been checked at normal and cramped terminal sizes

## Related documents

- `docs/DOOR_GAMES_DATA_CONTRACT.md` — domain/data contract
- `docs/DOOR_RUNTIME.md` — runner and OTP boundary
- `docs/ux/door-games-tui.md` — TUI interaction design
- `docs/qa/door-games-qa-strategy.md` — QA evidence plan
