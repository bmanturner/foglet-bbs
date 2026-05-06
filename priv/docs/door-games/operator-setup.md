%{
  title: "Operator setup",
  weight: 30
}
---

Operator doors are JSON manifests in a directory you control. Set the directory at deploy time, restart Foglet, and check the Door Games list over SSH.

## Create a manifest directory

```sh
mkdir -p /srv/foglet/doors/manifests
```

Put one manifest per `*.json` file. Foglet reads only direct regular JSON files. Hidden files and non-JSON files are ignored. Invalid manifests are omitted from the catalog and logged.

## Point Foglet at the directory

```sh
export FOGLET_DOOR_MANIFEST_DIR=/srv/foglet/doors/manifests
mix phx.server
```

In releases, set the same environment variable through your service manager. Application config `:door_manifest_dir` can also provide the path, but deploy-time env is the operator path most hosts understand.

## Minimal external door manifest

```json
{
  "id": "echo-door",
  "slug": "echo-door",
  "display_name": "Echo Door",
  "description": "Small external door used to verify launch and return.",
  "runtime": "external_pty",
  "command": "/srv/foglet/doors/echo.sh",
  "working_dir": "/srv/foglet/doors",
  "args": [],
  "timeout_ms": 900000,
  "idle_timeout_ms": 300000,
  "visibility": "members",
  "auth_scope": "site"
}
```

Use absolute paths for `command` and `working_dir`. Make the executable runnable by the OS user that starts Foglet, or configure the restricted-user sandbox for helper-backed launches.

## Check load errors

Foglet logs rejected manifests as warnings. In an IEx or diagnostic task context, `Foglet.Doors.manifest_load_errors/0` returns file names and validation errors.

## Restart after changes

Manifests are read by the Door Games context when the catalog is listed. A normal restart is still the clean operator habit after adding executables, permissions, or sandbox users. The machine remembers better when you make the shape explicit.
