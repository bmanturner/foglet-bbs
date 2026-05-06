%{
  title: "Overview",
  weight: 10
}
---

Door Games let an authenticated caller hand the current SSH terminal to a game or external program, then return to Foglet when that program exits. This section is for sysops deciding whether to enable doors and for contributors wiring a door into the current runtime.

The current implementation is real, but narrow. Door manifests are JSON configuration loaded at runtime. Foglet validates them, shows launchable entries in the terminal UI, starts a supervised runner for one active door session, and cleans up temporary context and dropfile files when the run ends.

## What ships now

Foglet supports three door runtimes:

- `native_elixir`: in-BEAM doors that implement the Foglet door callback.
- `external_pty`: external executables launched through the PTY adapter or a degraded fallback.
- `classic_dropfile`: external executables plus generated classic BBS dropfiles.

Operator manifests come from `FOGLET_DOOR_MANIFEST_DIR` or the `:door_manifest_dir` application config. If neither is set, production doors are empty. Built-in demo doors are hidden unless `FOGLET_ENABLE_DEMO_DOORS` is truthy.

## What does not ship yet

There is no database-backed door catalog, in-BBS manifest editor, persistent door audit table, scoring system, sanctions/reporting flow, or general-purpose DOS emulator integration. Foglet can launch configured programs; it does not make arbitrary third-party games safe.

## The shape of a launch

```text
SSH caller
  -> Door Games selector
  -> launch confirmation
  -> Foglet.Doors.Runner
  -> native callback or external process
  -> cleanup and return message
  -> Foglet TUI
```

The runner is the owner of the dangerous part. TUI screens select and request; they do not spawn OS processes.
