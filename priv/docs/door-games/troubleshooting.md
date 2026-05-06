%{
  title: "Troubleshooting",
  weight: 150
}
---

Start troubleshooting Door Games by deciding where the failure is: manifest load, visibility policy, executable launch, terminal handoff, or cleanup.

## Door does not appear

- Check `FOGLET_DOOR_MANIFEST_DIR` points to the directory you expect.
- Confirm the manifest file ends in `.json` and is a regular direct child of that directory.
- Check logs for `Door Games manifest rejected`.
- Inspect `Foglet.Doors.manifest_load_errors/0` from a diagnostic shell.
- Verify `visibility` allows the signed-in role.
- Remember that demo doors require `FOGLET_ENABLE_DEMO_DOORS=true`, `1`, or `yes`.

## Manifest rejected

Common causes:

- missing `id`, `slug`, `display_name`, `description`, `runtime`, `timeout_ms`, `visibility`, or `auth_scope`;
- non-absolute `command` or `working_dir` for external/classic doors;
- unknown runtime, visibility, output encoding, sandbox mode, or dropfile format;
- non-string `args` or env values;
- sensitive env names in `env` or `env_allowlist`;
- invalid JSON.

## Door launches but screen is wrong

- Prefer the helper-backed PTY path for full-screen programs.
- Confirm Python 3 and POSIX PTY/ioctl support are available.
- Avoid relying on fallback `script(1)` or plain pipes for resize-heavy doors.
- Test at 80x24 and at the smallest terminal size you intend to support.

## Sandbox launch fails

- Confirm the PTY helper file exists in the release.
- Confirm the configured OS user/group exists.
- Confirm Foglet has enough privilege to switch to that user/group.
- If the helper is unavailable, sandbox-required manifests fail closed by design.

## Door hangs

Set `timeout_ms` and consider `idle_timeout_ms`. The runner owns cleanup, but the best fix is a wrapper that exits cleanly when the door is done.
