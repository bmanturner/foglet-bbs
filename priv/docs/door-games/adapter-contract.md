%{
  title: "Adapter contract",
  weight: 100
}
---

External and classic adapters receive a small, explicit contract: a validated manifest, narrow context metadata, explicit environment values, terminal size, and optional dropfile paths. They do not receive Foglet internals.

## Context JSON

The runner writes a temporary context file and exposes its path as `FOGLET_DOOR_CONTEXT`. The context includes:

- `door_id`
- `user_id`
- `handle`
- `role`
- `session_id`
- `terminal_width`
- `terminal_height`

The context file is removed during runner cleanup.

## Environment variables

Foglet supplies:

- `FOGLET_DOOR_ID`
- `FOGLET_USER_ID`
- `FOGLET_USERNAME`
- `FOGLET_SESSION_ID`
- `FOGLET_TERMINAL_WIDTH`
- `FOGLET_TERMINAL_HEIGHT`
- `FOGLET_DOOR_CONTEXT`
- `FOGLET_DROPFILES`

Classic doors may also receive:

- `FOGLET_DROPFILE_DIR`
- `FOGLET_DROPFILE_DOOR32_SYS`
- `FOGLET_DROPFILE_DOOR_SYS`
- `FOGLET_DROPFILE_CHAIN_TXT`
- `FOGLET_DROPFILE_DORINFO_DEF`

Manifest `env` entries are merged with these values. Foglet-owned `FOGLET_*` variables win.

## Audit metadata

`Foglet.Doors.launch_audit/1` builds a redacted record with door id, user id, handle, start/end times, terminal size, runtime, allowlisted env values, and safe status keys. It is a contract for runtime/reporting code, not a persistent database table yet.
