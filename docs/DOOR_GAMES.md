# Door Games

Door Games let Foglet hand a caller's existing SSH terminal to a native game or external program, then bring the caller back to the BBS when the door exits.

This guide is for sysops and contributors adding doors to a self-hosted Foglet instance. It describes the current manifest and runner contract on the dropfile compatibility branch; it does not promise full DOS-door compatibility.

## Current support

Foglet supports three door runtimes:

- `:native_elixir` — first-party doors that implement `Foglet.Doors.Door` inside the BEAM.
- `:external_pty` — external executables launched by `Foglet.Doors.Runner` through the PTY adapter.
- `:classic_dropfile` — external executables plus generated classic BBS dropfiles.

Classic/dropfile support currently renders these fixed filenames:

- `:chain_txt` -> `CHAIN.TXT`
- `:door_sys` -> `DOOR.SYS`
- `:door32_sys` -> `DOOR32.SYS`
- `:dorinfo_def` -> `DORINFO.DEF`

The renderer owns line order and CRLF endings. Manifests can declare which formats a door needs, but cannot choose arbitrary filenames or paths.

Door manifests are configuration data in this slice. They are validated by `Foglet.Doors.validate_manifest/1`, normalized into `%Foglet.Doors.Manifest{}`, and are not stored in database tables yet. There is no in-BBS catalog editor yet.

## Built-in demo door switch

Foglet ships demo/test doors for local development, QA, demos, and release verification. They are hidden unless this deployment environment variable is truthy:

```sh
FOGLET_ENABLE_DEMO_DOORS=true mix phx.server
```

Truthy values are `true`, `1`, and `yes`, after trimming whitespace and ignoring case. Absent, empty, or other values hide the demo doors.

This switch is not stored in `Foglet.Config`, is not backed by the database, and does not appear in the Sysop SITE screen. Do not mention it in normal caller copy.

Current demo/test manifests behind the switch are:

- `native-hello`
- `external-echo`
- `python-context-demo`
- `classic-dropfile-demo`

Production/operator doors are not hard-coded in this list. Add them through the manifest directory described below.

## Safety model

Treat external and classic doors as untrusted programs until a sysop reviews the executable, filesystem access, persistence path, and runtime account.

Foglet narrows what a door receives:

- a validated manifest
- user/session metadata needed by the door adapter
- explicit non-secret manifest `env` entries
- required `FOGLET_*` variables
- a narrow default `PATH` (`/usr/bin:/bin`) when no manifest `PATH` is supplied
- a temporary JSON context file
- generated dropfiles for classic/dropfile doors

External/classic launches use a clean environment (`env -i`) across the helper-backed PTY, plain-pipe, and `script(1)` fallback paths. The child does not inherit the BEAM or helper process environment. `env_allowlist` only controls what manifest env names may appear unredacted in audit metadata; it does not inherit host environment variables.

Foglet does not pass database credentials, app secrets, API keys, private tokens, full user structs, full session structs, or broad host environments to door processes.

This is a baseline sandbox, not full containment. Unsandboxed doors still use allowlisted paths, environment hygiene, timeouts, cleanup, and audit metadata. Sandboxed helper-backed doors add fail-closed restricted OS-user execution plus process-group cleanup, but they do not isolate filesystem mounts, network, seccomp, namespaces, containers, microVMs, or broad resource access.

Docker/Fly currently diverge from the strongest host baseline because the release image runs as `nobody` and cannot switch to a second door user without an approved runtime change. Treat arbitrary third-party code as unsupported on that container path until that divergence is resolved.

## Manifest fields

Required for every door:

- `id` — stable internal id, for example `"usurper-reborn"`
- `slug` — stable config-friendly name, for example `"usurper-reborn"`
- `display_name` — name shown to callers
- `description` — one-sentence selector description
- `runtime` — `:native_elixir`, `:external_pty`, or `:classic_dropfile`
- `timeout_ms` — positive integer absolute lifetime cap in milliseconds
- `visibility` — `:members`, `:mods_only`, or `:sysop_only`
- `auth_scope` — `:site` or `{:board, board_id}`

Required for `:native_elixir`:

- `module` — a module implementing `Foglet.Doors.Door`

Required for `:external_pty` and `:classic_dropfile`:

- `command` — absolute path to the executable or wrapper
- `working_dir` — absolute working directory for the configured door assets

Optional shared fields:

- `args` — list of string arguments; no shell is inserted by Foglet
- `env` — explicit non-secret environment values
- `env_allowlist` — uppercase manifest env names safe to show unredacted in audit records
- `idle_timeout_ms` — optional positive idle timeout in milliseconds
- `pty?` — whether the runner should request the PTY adapter path (`true` by default)
- `sandbox` — sandbox contract, for example `%{mode: :restricted_user_process_group, user: "foglet-door", group: "foglet-door", process_tree: :process_group, fail_closed?: true}`

Optional classic/dropfile fields:

- `dropfile_formats` — simple list such as `[:chain_txt, :door_sys]`
- `dropfiles` — detailed declarations when a door needs per-format metadata

Each detailed `dropfiles` entry supports:

- `format` — `:chain_txt`, `:door_sys`, `:door32_sys`, or `:dorinfo_def`
- `identity` — currently `:handle`
- `transport` — currently `:filesystem`
- `encoding` — `:cp437` or `:utf8`
- `cwd` — `:door_working_dir` or `:session_working_dir`
- `expose_path` — `:env` or `:none`

Foglet rejects dropfile declarations that try to set filenames or paths. Fixed filenames come from `Foglet.Doors.Dropfiles`.

Do not put secrets in `env` or `env_allowlist`. Foglet rejects known sensitive names such as database URLs, secret key bases, tokens, and API keys. Env names must be uppercase shell-style names.

## Runner behavior for external and classic doors

`Foglet.Doors.Runner` owns one active door session. It writes a temporary JSON context file before launch, starts the door, forwards input and resize events, watches timeout/idle timeout/disconnect/crash paths, and removes generated files during cleanup.

For `pty?: true`, `Foglet.Doors.PTYAdapter` launches the configured command through `priv/doors/pty/foglet_pty_adapter.py` when available. The helper opens the child PTY, launches `command` with `args` as separate arguments, bridges input/output with framed messages, applies resize with `TIOCSWINSZ` on POSIX hosts, and supports the restricted-user/process-group sandbox contract. If the helper is unavailable and the manifest does not require sandboxing, Foglet may fall back to `script(1)` or a plain pipe; those fallbacks are development/demo paths and do not provide the same resize or cleanup semantics.

The runner exposes these standard variables to external/classic doors:

- `FOGLET_DOOR_ID`
- `FOGLET_USER_ID`
- `FOGLET_USERNAME`
- `FOGLET_SESSION_ID`
- `FOGLET_TERMINAL_WIDTH`
- `FOGLET_TERMINAL_HEIGHT`
- `FOGLET_DOOR_CONTEXT`
- `FOGLET_DROPFILES`

`FOGLET_DOOR_CONTEXT` points to the temporary JSON context file. `FOGLET_DROPFILES` is a colon-separated list of generated dropfile paths.

When a dropfile declaration has `expose_path: :env`, Foglet also exposes a format-specific path:

- `FOGLET_DROPFILE_CHAIN_TXT`
- `FOGLET_DROPFILE_DOOR_SYS`
- `FOGLET_DROPFILE_DOOR32_SYS`
- `FOGLET_DROPFILE_DORINFO_DEF`
- `FOGLET_DROPFILE_DIR` for the generated dropfile directory

Classic doors run from a runner-owned per-launch directory after dropfiles are generated. The runner removes generated dropfiles, the per-launch dropfile directory, and the temporary context file during cleanup. Pre-existing files in the configured manifest `working_dir` are not overwritten or removed by dropfile cleanup.

Manifest arg templates are resolved after dropfiles exist. Supported tokens are:

- `{dropfile:door32_sys}`
- `{dropfile:door_sys}`
- `{dropfile:chain_txt}`
- `{dropfile:dorinfo_def}`
- `{dropfile_dir}`
- `{user:handle}`
- `{terminal:cols}`
- `{terminal:rows}`

Unknown or malformed tokens fail the launch. User handles used in argv are normalized to letters, numbers, `_`, `.`, and `-`.

## Operator-managed manifest directory

Production Door Games are loaded from an operator-managed JSON manifest directory. Set `FOGLET_DOOR_MANIFEST_DIR` to an absolute directory path before starting Foglet, or set `config :foglet_bbs, :door_manifest_dir` in runtime config. When the setting is unset or blank, production/operator doors are disabled by default; only demo fixtures can appear, and only when `FOGLET_ENABLE_DEMO_DOORS` is explicitly truthy.

A sysop adds a door by creating one reviewed `*.json` file in that directory and restarting/reloading the application according to deployment practice. Foglet scans only direct regular JSON files in that directory, validates each manifest with the same `Foglet.Doors` safety checks used by code/test fixtures, and fails closed per file: symlinks, device files, invalid JSON, or unsafe fields are omitted from the launchable catalog. Diagnostics can call `Foglet.Doors.manifest_load_errors/0`, and runtime logs include the rejected file and field errors.

Manifest JSON uses the same field names shown below, with enum values as strings, for example `"classic_dropfile"`, `"members"`, `"site"`, and `"door32_sys"`. Do not put secrets in `env`; inherited environments are not passed through.

The repository includes `priv/doors/manifests/usurper-reborn.json` as a copyable sample. A deployment can copy it into the configured operator directory and adjust paths for that host without editing Elixir source.

## Add a native Elixir door

Use a native Elixir door when the game is small, first-party, and safe to run inside Foglet's OTP supervision boundary.

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

  def handle_input(data, state), do: {:ok, state, ["echo> ", data]}

  @impl true
  def handle_resize(size, state), do: {:ok, %{state | size: size}, "resized\n"}
end
```

Register and validate it with a manifest:

```elixir
attrs = %{
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

{:ok, manifest} = Foglet.Doors.validate_manifest(attrs)
```

## Add an external executable door

Use an external executable door when the game is written outside Elixir: Python, Node, Go, Rust, C, a shell script, or another terminal program.

```elixir
attrs = %{
  id: "external-demo",
  slug: "external-demo",
  display_name: "External Demo",
  description: "A small external demo door.",
  runtime: :external_pty,
  command: "/srv/foglet/doors/external-demo/run.sh",
  args: ["--ansi"],
  working_dir: "/srv/foglet/doors/external-demo",
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

{:ok, manifest} = Foglet.Doors.validate_manifest(attrs)
```

When `sandbox.mode` is `:restricted_user_process_group`, the helper resolves the configured user and optional group before launch. If the user/group is missing, Python/PTY support is unavailable, Foglet lacks permission to drop to that user, or supplementary groups cannot be safely set or cleared, the door fails closed before the command starts.

Keep wrappers boring:

- use absolute paths in manifests
- keep working directories under operator-owned door directories
- pass command arguments as structured args, not shell-built strings
- avoid shelling out to arbitrary user input
- do not read app secrets from the environment
- exit with status `0` for normal completion and non-zero for crashes/errors

## Add a classic/dropfile door

Use `:classic_dropfile` when a wrapper or modern door executable needs classic BBS-style metadata files.

```elixir
attrs = %{
  id: "classic-demo",
  slug: "classic-demo",
  display_name: "Classic Demo",
  description: "A classic door wrapper that reads generated dropfiles.",
  runtime: :classic_dropfile,
  command: "/srv/foglet/doors/classic-demo/run.sh",
  args: ["--dropfile-dir", "{dropfile_dir}"],
  working_dir: "/srv/foglet/doors/classic-demo",
  dropfile_formats: [:chain_txt, :door_sys, :door32_sys, :dorinfo_def],
  env: %{"TERM" => "xterm-256color"},
  env_allowlist: ["TERM"],
  timeout_ms: 20 * 60 * 1_000,
  idle_timeout_ms: 5 * 60 * 1_000,
  visibility: :members,
  auth_scope: :site,
  pty?: true
}

{:ok, manifest} = Foglet.Doors.validate_manifest(attrs)
```

The wrapper is responsible for passing generated files to the target program in the shape that program expects. Foglet generates compatibility metadata; it does not emulate DOS, provide a FOSSIL driver, or make arbitrary historical doors work.

## Add Usurper Reborn

Usurper Reborn is the current concrete production compatibility target. The branch includes a copyable JSON sample at `priv/doors/manifests/usurper-reborn.json`; when that directory or a copied manifest directory is configured, it validates to this shape:

```elixir
%{
  id: "usurper-reborn",
  slug: "usurper-reborn",
  display_name: "Usurper Reborn",
  description: "Shared-world fantasy BBS game for Foglet callers.",
  runtime: :classic_dropfile,
  command: "/opt/foglet/doors/usurper/UsurperReborn",
  args: [
    "--door32",
    "{dropfile:door32_sys}",
    "--db",
    "/data/usurper/usurper_online.db",
    "--stdio"
  ],
  working_dir: "/opt/foglet/doors/usurper",
  dropfiles: [
    %{
      format: :door32_sys,
      identity: :handle,
      transport: :filesystem,
      encoding: :cp437,
      cwd: :door_working_dir,
      expose_path: :env
    }
  ],
  timeout_ms: 12 * 60 * 60 * 1_000,
  idle_timeout_ms: 60 * 60 * 1_000,
  visibility: :members,
  auth_scope: :site,
  output_encoding: :cp437,
  sandbox: %{
    mode: :restricted_user_process_group,
    user: "foglet-door",
    group: "foglet-door",
    process_tree: :process_group,
    fail_closed?: true
  }
}
```

Start-to-finish sysop path:

1. Choose the runtime.
   Use `"classic_dropfile"` in JSON because Usurper Reborn accepts a DOOR32-style launch file and runs as an external terminal program.

2. Install the executable.
   Put the Usurper Reborn binary and required assets under an operator-owned directory such as `/opt/foglet/doors/usurper`. The project Dockerfile downloads the public Linux x64 release at build time and installs it there.

3. Choose the shared state path.
   Use a durable SQLite database path such as `/data/usurper/usurper_online.db`. The deployment must make that directory writable by the runtime user that will actually execute the door.

4. Declare one DOOR32.SYS dropfile.
   Use `"dropfiles": [{"format": "door32_sys", ...}]`, not a hand-written filename. Foglet will write `DOOR32.SYS` into the per-launch directory and substitute its generated path into `{dropfile:door32_sys}`.

5. Pass generated paths safely.
   Prefer argv tokens such as `{dropfile:door32_sys}` over wrapper-side path guessing. With `expose_path: :env`, wrappers can also read `FOGLET_DROPFILE_DOOR32_SYS` and `FOGLET_DROPFILE_DIR`.

6. Keep cwd expectations narrow.
   The manifest's configured `working_dir` points at the installed door assets. During classic/dropfile launch, the runner switches the process working directory to the generated per-launch dropfile directory so programs can open fixed dropfile names safely. If the target executable also needs assets relative to its install directory, pass absolute asset paths or use a reviewed wrapper.

7. Configure the sandbox contract.
   Prefer `restricted_user_process_group` on host deployments that can create and use a locked-down `foglet-door` account. If that account cannot be applied, the launch should fail closed instead of running the door as the Foglet app user.

8. Expose the door.
   Copy `priv/doors/manifests/usurper-reborn.json` into the configured operator manifest directory, adjust host-specific paths if needed, set `FOGLET_DOOR_MANIFEST_DIR`, and restart/reload Foglet. The door is not hard-coded in Elixir and will not appear when the manifest directory is unset or invalid.

9. Verify launch and cleanup.
   Run focused door tests and SSH/TUI QA before enabling the door for real callers. Verify that Usurper starts with `--door32 <generated path> --db /data/usurper/usurper_online.db --stdio`, returns cleanly, and leaves no runner-owned temp context or dropfile directory behind.

Residual limitation: if upstream Usurper requires a MUD relay, socket proxy, or protocol adapter for production-quality multiplayer behavior, keep that as a separate runtime/architecture issue. Do not describe the current dropfile path as a complete relay solution until implementation and QA evidence prove it.

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

For built-in demo/test doors, check `FOGLET_ENABLE_DEMO_DOORS`. For production doors, check `FOGLET_DOOR_MANIFEST_DIR`, `Foglet.Doors.manifest_load_errors/0`, manifest validation, caller visibility, and that the launch path rechecks `Foglet.Doors.launchable?/2` before starting the runner.

### The door launches and immediately returns

Check the external command, generated args, working directory assumptions, executable permissions, sandbox user/group, and exit status. Foglet treats non-zero external exits as crashes.

### The door cannot find a dropfile

Check whether the manifest declares the required format, whether the argv token matches the format name, and whether the target expects to open the file by name in cwd or receive an explicit path. Use `{dropfile:door32_sys}` or `FOGLET_DROPFILE_DOOR32_SYS` when the program accepts an explicit path.

### The door needs assets and generated dropfiles

Do not copy assets into the generated dropfile directory. Keep assets in the installed door directory and pass absolute paths or use a reviewed wrapper. The generated directory is per-launch state and will be removed.

### The door times out

Increase `timeout_ms` or `idle_timeout_ms` only after confirming the door is healthy. Timeouts are part of the cleanup and safety model.

### The terminal looks wrong after exit

The door may have left the terminal in an unusual mode or used unsupported full-screen behavior. Prefer wrappers that restore terminal state before exit, and capture SSH harness evidence before enabling the door for real users.

### A door needs more environment variables

Add only specific non-secret values to manifest `env`, and add the same names to `env_allowlist` only when those values are safe to display unredacted in audit records. Do not allowlist or pass database URLs, app secrets, API keys, tokens, or broad inherited environments.

## Copy review checklist

Before shipping a new door surface or guide, verify:

- callers are never asked to type slugs, ids, schema names, env var names, or magic values
- normal caller copy does not mention `FOGLET_ENABLE_DEMO_DOORS`
- launch copy explains full-terminal takeover without sounding alarming
- error copy is short and recoverable; logs carry technical detail
- docs distinguish current support from future hardening
- external/classic docs do not imply full sandboxing or full DOS compatibility
- examples use fake paths and fake user ids unless documenting the branch's built-in Usurper paths
- examples do not contain credentials, private tokens, or production secrets
- TUI copy has been checked at normal and cramped terminal sizes

## Related documents

- `docs/DOOR_GAMES_DATA_CONTRACT.md` — domain/data contract
- `docs/DOOR_RUNTIME.md` — runner and OTP boundary
- `docs/ux/door-games-tui.md` — TUI interaction design
- `docs/qa/door-games-qa-strategy.md` — QA evidence plan
