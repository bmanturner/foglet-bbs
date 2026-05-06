%{
  title: "Demo doors",
  weight: 40
}
---

Foglet includes demo doors for local development, QA, and release checks. They are hidden by default so production instances do not advertise fixtures as games.

## Enable demos

```sh
FOGLET_ENABLE_DEMO_DOORS=true mix phx.server
```

Truthy values are `true`, `1`, and `yes`, after trimming whitespace and ignoring case. Empty, absent, or any other value hides the demo doors. This is not a database-backed site setting and does not appear in the Sysop SITE screen.

## Included demo manifests

- `native-hello`: an in-BEAM door that opens, says hello, and returns.
- `external-echo`: a shell-script door that verifies external launch and return.
- `python-context-demo`: a Python door that reads the safe context/env.
- `classic-dropfile-demo`: a classic-style door that reads generated dropfiles.

Each demo uses member visibility and site auth scope. The external demos live under `priv/doors/demo` and use the same runner path as operator-configured external doors.

## Production guidance

Do not treat the demo switch as a catalog. Real operator doors belong in `FOGLET_DOOR_MANIFEST_DIR`. Leave demo doors off unless you are actively testing or showing the launch path.
