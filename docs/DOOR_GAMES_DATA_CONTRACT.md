# Door Games Domain/Data Contract (FOG-515)

This document captures the first-slice domain/data contract for FOG-480 Door Games.
It is deliberately narrower than the full runtime umbrella: no OTP runner, SSH PTY
handoff, TUI menu, or persistent audit table is introduced here.

## Source verification

Current source inspection found no existing `Foglet.Doors` context, door schemas,
door migrations, or door tests in the canonical `fog-480-door-games` worktree.
`docs/DATA_MODEL.md` remains the current persistence contract for existing Foglet
schemas; it does not yet define door tables.

## Persistence decision

First slice uses validated configured/seeded manifests and plain audit/dropfile
structs. It does not add a database table or migration.

Rationale:

- The umbrella requires a safe domain boundary before runtime/TUI integration.
- Door catalog editing is not in first-slice scope.
- Persisting audit rows before the OTP runner owns launch/exit lifecycle would
  create a premature schema around events not yet emitted by runtime code.

Migration notes: none; no migration was generated.
Rollback notes: remove `Foglet.Doors*`, this document, and tests. No database
rollback is required.

## Context boundary

`Foglet.Doors` owns:

- manifest validation and normalization;
- actor-aware launch eligibility checks;
- redacted launch/exit audit record construction;
- classic dropfile generation from Foglet user/session metadata.

Callers such as TUI screens should treat `launchable?/2` as advisory list
filtering. Any future command/runtime launch boundary must call the context again
before side effects.

## Manifest shape

Validated manifests are `%Foglet.Doors.Manifest{}` structs with:

- `id` / `slug`
- `display_name`
- `description`
- `runtime`: `:native_elixir`, `:external_pty`, or `:classic_dropfile`
- `command`: absolute executable path for external/classic doors
- `args`: string argument list
- `working_dir`: absolute path for external/classic doors
- `env_allowlist`: uppercase environment names safe to expose
- `timeout_ms`
- `idle_timeout_ms`
- `visibility`: `:members`, `:mods_only`, or `:sysop_only`
- `auth_scope`: `:site` or `{:board, board_id}` for future scoped policy
- `env`: explicit string environment values; sensitive names are rejected
- `sandbox`: `%Foglet.Doors.Sandbox{}` with `:none` by default or `:restricted_user_process_group` for the helper-backed sandbox baseline

Sensitive variables such as database URLs, secret keys, API keys, and tokens are
rejected from both `env` and `env_allowlist`.

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
`:timed_out`, `:crashed`, and `:disconnected`. Output streams, arbitrary metadata,
and non-allowlisted environment values are not retained.

## Classic dropfile model

First-slice support implements `:chain_txt` generation only. The boundary is
`Foglet.Doors.classic_dropfile/2`, which can later grow `:door_sys` and
`:dorinfo_def` formats without exposing persistence or TUI implementation details.

Current CHAIN.TXT fixture order:

1. handle
2. real name/display name
3. terminal columns
4. terminal rows
5. role
6. user id

Lines are CRLF-terminated for classic door compatibility.

## Residual risks / future follow-up candidates

- Persistent launch/exit audit tables should be revisited after the OTP runner
  emits authoritative lifecycle events.
- The FOG-830 runtime baseline adds a restricted-user/process-group manifest
  contract for helper-backed external doors. Full filesystem/network/seccomp or
  container isolation remains a platform concern.
- DOOR.SYS and DORINFO.DEF are intentionally deferred behind the same dropfile
  adapter boundary.
