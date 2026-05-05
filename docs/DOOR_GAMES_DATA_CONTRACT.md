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
remains ephemeral. Classic dropfiles are written into the door working directory
for the life of the runner and removed during runner cleanup.

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

Wrappers should:

1. Read `FOGLET_DOOR_CONTEXT` or the minimal `FOGLET_*` environment values.
2. For classic doors, consume the generated dropfile(s) in the working directory.
3. Launch the target executable from the manifest working directory.
4. Preserve the child exit status.
5. Return cleanly to Foglet on normal exit.
6. Avoid logging context files, dropfile contents, inherited env, or terminal
   input/output as secrets could appear in third-party programs.

Foglet's runner writes requested dropfiles before launching a
`:classic_dropfile` manifest and removes them during normal exit, crash,
timeout, or disconnect cleanup.

## Classic dropfile model

`Foglet.Doors.classic_dropfile/2` supports:

- `:chain_txt` -> `CHAIN.TXT`
- `:door_sys` -> `DOOR.SYS`
- `:dorinfo_def` -> `DORINFO.DEF`

All lines are CRLF-terminated.

### CHAIN.TXT mapping

Preserved from the first Door Games slice:

1. handle
2. real name/display name
3. terminal columns
4. terminal rows
5. role
6. user id

### DOOR.SYS mapping

Foglet writes a conservative 40-line DOOR.SYS-style file. Safe Foglet values are
mapped where direct equivalents exist:

- BBS name: `Foglet BBS`
- User handle and display name
- Optional user location
- Terminal columns/rows
- User id
- Foglet role
- Session id, when available to the runner

Classic modem/security/accounting values that Foglet does not model yet use
explicit defaults such as `COM0:`, `38400`, `GR`, `1440`, `9999`, `0`, or `N`.
These defaults are compatibility hints, not assertions about a real modem,
security tier, or billing state.

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

- Normal exit: child exit status is reported; context and dropfiles are removed.
- Crash/non-zero exit: status is reported as crash; cleanup still runs.
- Timeout: runner terminates the OS process and removes context/dropfiles.
- Disconnect: runner terminates the process owner and removes context/dropfiles.
- Resize: helper-backed PTY children receive resize; plain/fallback children keep
  audit state but cannot receive TIOCSWINSZ.

Existing FOG-480 runner tests cover normal exit, crash, timeout, disconnect,
helper failure, and privacy-safe logging. FOG-880 adds classic dropfile runtime
coverage on top of that runner cleanup behavior.

## Compatibility tiers

- Tier 1: native Elixir doors.
- Tier 2: modern external CLI/PTY doors.
- Tier 3: classic dropfile-aware wrappers/native executables.
- Tier 4: DOS-era doors through DOSBox/dosemu-style wrappers, experimental/future.

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
