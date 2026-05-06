%{
  title: "Support status",
  weight: 20
}
---

Door Games are available as a first-slice runtime. Use them for controlled operator-configured doors and demos. Treat broad third-party door hosting as experimental until you have reviewed the executable, filesystem access, runtime user, and deployment profile.

## Supported

- Loading direct `*.json` manifest files from `FOGLET_DOOR_MANIFEST_DIR`.
- Hiding invalid manifests from the Door Games list and logging validation errors.
- Role-based visibility: members, moderators, and sysops.
- Native Elixir doors inside the BEAM.
- External commands launched with a clean environment.
- PTY-backed external doors when the helper is available.
- Classic dropfile generation for `CHAIN.TXT`, `DOOR.SYS`, `DOOR32.SYS`, and `DORINFO.DEF`.
- Timeout, idle-timeout, disconnect, resize, crash, and normal-exit cleanup in the runner.

## Partly supported

- `script(1)` and plain-pipe fallback for external doors when the helper is unavailable. These are degraded paths, not the full supported PTY behavior.
- Restricted OS-user sandboxing through the helper. It is fail-closed when requested, but it is process-user isolation, not a container.
- Classic BBS compatibility. Foglet writes fixed-name dropfiles with current metadata; each old door still needs operator testing.

## Unsupported

- A web or sysop-screen editor for door manifests.
- Persistent launch audit rows. The current audit record is an in-memory contract.
- Arbitrary dropfile filenames or caller-supplied paths.
- Inheriting host environment variables into doors.
- Database credentials, secret keys, API tokens, or full user/session structs in door env/context.
- Strong isolation such as seccomp, namespaces, microVMs, or network policy.
- Production arbitrary third-party code on Docker/Fly unless you accept the container-path sandbox limits.
