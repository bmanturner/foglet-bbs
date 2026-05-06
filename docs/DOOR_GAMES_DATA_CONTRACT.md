# Door Games Domain/Data Contract (FOG-515 / FOG-880)

This document captures the domain/data contract for the Door Games foundation and
FOG-880 classic compatibility adapters. It stays narrower than the full runtime
umbrella: no persistent door catalog or audit table is introduced here.

## Source verification

FOG-880 extends the existing `Foglet.Doors` context, `%Foglet.Doors.Manifest{}`,
`Foglet.Doors.Runner`, and door tests. Current persistence docs remain in
`docs/DATA_MODEL.md`; this work does not add door tables or migrations.

## Persistence decision

Door manifests remain validated configuration data, and launch/dropfile metadata
remains ephemeral. Classic dropfiles are written into a runner-owned per-launch
working directory for the life of the runner and removed during runner cleanup.
The configured manifest `working_dir` remains the validated base for the door,
but Foglet does not write per-session dropfiles into that shared directory.

Rationale:

- Compatibility examples need safe adapter behavior before a durable game catalog.
- Dropfiles contain session/user metadata and should not become durable records.
- Persistent audit rows should wait until the runtime emits authoritative launch
  and exit events as product policy requires.

Migration notes: none; no migration was generated.
Rollback notes: remove the FOG-880 adapter helpers/examples/docs/tests. No
database rollback is required.

## Context boundary

`Foglet.Doors` owns:

- manifest validation and normalization;
- actor-aware launch eligibility checks;
- redacted launch/exit audit record construction;
- classic dropfile generation from Foglet user/session metadata;
- safe adapter context/env helpers for external and classic wrappers;
- fixed-name dropfile writes for requested formats.

Callers such as TUI screens should treat `launchable?/2` as advisory list
filtering. Any command/runtime launch boundary must call the context again before
side effects.

## Manifest shape

Validated manifests are `%Foglet.Doors.Manifest{}` structs with:

- `id` / `slug`
- `display_name`
- `description`
- `runtime`: `:native_elixir`, `:external_pty`, or `:classic_dropfile`
- `command`: absolute executable path for external/classic doors
- `args`: string argument list
- `working_dir`: absolute path for external/classic doors
- `dropfile_formats`: requested classic formats for `:classic_dropfile`
- `env_allowlist`: uppercase environment names safe to expose in audit summaries
- `timeout_ms`
- `idle_timeout_ms`
- `visibility`: `:members`, `:mods_only`, or `:sysop_only`
- `auth_scope`: `:site` or `{:board, board_id}` for future scoped policy
- `env`: explicit string environment values; sensitive names are rejected
- `sandbox`: `%Foglet.Doors.Sandbox{}` with `:none` by default or `:restricted_user_process_group` for the helper-backed sandbox baseline

Sensitive variables such as database URLs, secret keys, API keys, and tokens are
rejected from both `env` and `env_allowlist`. Runtime env passed to doors is
built from the manifest's explicit `env` plus Foglet's minimal `FOGLET_*` keys;
it is not a promise of process sandboxing.

## Audit record shape

`%Foglet.Doors.AuditRecord{}` is the first-slice audit contract:

- `door_id`
- `user_id`
- `handle`
- `started_at`
- `ended_at`
- `terminal_size`
- `runtime`
- redacted `env`
- bounded `status`

Only safe status keys are retained: `:exit_status`, `:reason`, `:signal`,
`:timed_out`, `:crashed`, and `:disconnected`. Output streams, arbitrary
metadata, and non-allowlisted environment values are not retained.

## Adapter/wrapper contract

Use this section when writing a Python, Node, Rust, Go, C, or shell program that
runs as a Foglet door.

External and classic wrappers receive only safe Foglet context:

- Environment:
  - `FOGLET_DOOR_ID`
  - `FOGLET_USER_ID`
  - `FOGLET_USERNAME`
  - `FOGLET_SESSION_ID`
  - `FOGLET_TERMINAL_WIDTH`
  - `FOGLET_TERMINAL_HEIGHT`
  - `FOGLET_DOOR_CONTEXT`
  - `FOGLET_DROPFILES` for classic/dropfile manifests, colon-separated paths
- JSON context file at `FOGLET_DOOR_CONTEXT`:
  - `door_id`
  - `user_id`
  - `handle`
  - `role`
  - `session_id`
  - `terminal_width`
  - `terminal_height`

The JSON file is the preferred interface for modern doors. The environment
values are present for small scripts and wrappers that cannot easily parse JSON.

Wrapper checklist:

1. Read `FOGLET_DOOR_CONTEXT`, or read the minimal `FOGLET_*` environment values
   if the language/runtime makes JSON awkward.
2. For classic doors, consume the generated dropfile(s) in the current working
   directory or from the explicit paths listed in `FOGLET_DROPFILES`.
3. Launch the target executable from Foglet's runner-owned current working
   directory for that session. The manifest `working_dir` is a shared validated
   base path, not a place for per-session dropfile writes.
4. Forward terminal input/output without writing a separate transcript by
   default.
5. Preserve the child exit status.
6. Return cleanly to Foglet on normal exit.
7. Avoid logging context files, dropfile contents, inherited env, or terminal
   input/output. Third-party programs may ask users for secrets.

Foglet's runner creates a unique temporary working directory for each
`:classic_dropfile` launch, writes requested fixed-name dropfiles there before
launch, sets the child cwd to that isolated directory, exposes the generated
paths through `FOGLET_DROPFILES`, and removes the directory during normal exit,
crash, timeout, or disconnect cleanup. Cleanup only targets runner-owned files
and directories; pre-existing `CHAIN.TXT`, `DOOR.SYS`, or `DORINFO.DEF` files in
the configured manifest base directory are not overwritten or removed.

## Classic dropfile model

`Foglet.Doors.classic_dropfile/2` supports:

- `:chain_txt` -> `CHAIN.TXT`
- `:door_sys` -> `DOOR.SYS`
- `:dorinfo_def` -> `DORINFO.DEF`

All lines are CRLF-terminated (`\r\n`). The generated files are compatibility
bridges for dropfile-aware programs; they are not a claim that every historical
DOS door will run unchanged.

### CHAIN.TXT mapping

Preserved from the first Door Games slice:

1. handle
2. real name/display name
3. terminal columns
4. terminal rows
5. role
6. user id

### DOOR.SYS mapping

Foglet writes a conservative 40-line DOOR.SYS-style file with CRLF line endings.
The layout keeps parser-critical fields at classic/Usurper-compatible indexed
positions and fills unsupported modem/accounting fields with explicit defaults:

1. COM port: `COM0:`
2. baud: `38400`
4. node number, default `1`
10. full/display name
11. optional user location
16. coarse role security level: user `50`, mod `90`, sysop `100`
20. minutes remaining, default `1440`
21. graphics mode: `GR`
22. screen/page length from terminal rows, default `24`
26. numeric user record number derived from the Foglet user id when possible,
    otherwise `0`
36. sysop name (`FOGLET_BBS_SYSOP_NAME` if present, otherwise `Foglet Sysop`)
37. alias/handle
40. Foglet session id when available to the runner

Other classic modem/security/accounting values that Foglet does not model yet
use defaults such as `8`, `Y`, `N`, blank strings, `9999`, `0`, or fixed legacy
dates. These defaults are compatibility hints, not assertions about a real
modem, security tier, or billing state. The demo probe now reads the DOOR.SYS
alias from line 37 instead of the earlier loose fixture's line 5.

### DORINFO.DEF mapping

Foglet writes a 10-line DORINFO.DEF-style file:

1. `Foglet BBS`
2. sysop first name (`FOGLET_BBS_SYSOP_NAME` if present, otherwise `Foglet`)
3. sysop last name (`Sysop` by default)
4. `COM0`
5. `38400 BAUD,N,8,1`
6. node number `0`
7. user handle
8. display name
9. optional user location
10. coarse role security level: user `10`, mod `80`, sysop `100`

## Built-in examples

FOG-880 adds executable examples under `priv/doors/demo`:

- `external_echo.sh`: existing shell external-door smoke example.
- `python_context_demo.py`: Python external door that reads safe Foglet context
  and returns on `/quit`.
- `classic_dropfile_demo.py`: classic/dropfile-style Python demo that reads a
  generated dropfile and returns on `/quit`.

These examples are intentionally small and testable; they are not a game catalog
or a sandbox.

## Process and cleanup behavior

Process ownership remains in `Foglet.Doors.Runner` under the Door supervisor:

- Normal exit: child exit status is reported; context and runner-owned dropfile
  directory are removed.
- Crash/non-zero exit: status is reported as crash; cleanup still runs.
- Timeout: runner terminates the OS process and removes context/dropfiles.
- Disconnect: runner terminates the process owner and removes context/dropfiles.
- Resize: helper-backed PTY children receive resize; plain/fallback children keep
  audit state but cannot receive TIOCSWINSZ.

Existing FOG-480 runner tests cover normal exit, crash, timeout, disconnect,
helper failure, and privacy-safe logging. FOG-880 adds classic dropfile runtime
coverage on top of that runner cleanup behavior.

## Compatibility tiers

- Tier 1: native Elixir doors. These run inside Foglet/OTP and can integrate
  directly with Foglet code.
- Tier 2: modern external CLI/PTY doors. These are ordinary executables launched
  under a PTY with safe Foglet context.
- Tier 3: classic dropfile-aware wrappers/native executables. These consume
  generated `CHAIN.TXT`, `DOOR.SYS`, or `DORINFO.DEF` files from the working
  directory.
- Tier 4: DOS-era doors through DOSBox/dosemu-style wrappers. This tier is
  experimental/future and is not delivered by FOG-880.

## FOG-522 alignment and sandbox limits

FOG-880 is compatibility/examples work. It does not claim stronger sandboxing,
container isolation, seccomp, cgroups, network isolation, or third-party binary
trust. Stronger isolation remains the FOG-522 / PR #94 track.

Current safeguards are narrower:

- validated absolute command and working-directory paths;
- minimal Foglet context/env exposure;
- redaction in audit/log helpers;
- runner-owned timeout/disconnect cleanup;
- generated dropfile cleanup.

Do not run arbitrary third-party doors by default solely because they can consume
DOOR.SYS or DORINFO.DEF.

## Residual risks / future follow-up candidates

- Persistent launch/exit audit tables should be revisited after the OTP runner
  emits authoritative lifecycle events.
- The FOG-830 runtime baseline adds a restricted-user/process-group manifest
  contract for helper-backed external doors. Full filesystem/network/seccomp or
  container isolation remains a platform concern.
- Strong sandbox posture remains a runtime/platform concern tracked by FOG-522.
- DOSBox/dosemu wrappers are future tier-4 compatibility, not covered here.
