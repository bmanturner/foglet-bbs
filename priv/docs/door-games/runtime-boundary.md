%{
  title: "Runtime boundary",
  weight: 130
}
---

The Door Games runtime boundary keeps process launch out of screen reducers. The TUI asks; the supervised runner owns the door.

```text
Foglet.TUI.Screens.DoorList
  -> Foglet.TUI.Effect.launch_door/2
  -> Foglet.TUI.App effects handling
  -> Foglet.Doors.Supervisor.start_runner/1
  -> Foglet.Doors.Runner
     -> native callback or external Port/PTX helper
```

## Runner ownership

`Foglet.Doors.Runner` owns:

- native callback execution;
- external executable Port ownership;
- PTY adapter selection;
- context file creation and deletion;
- dropfile working directory and cleanup;
- input and resize forwarding;
- timeout and idle-timeout timers;
- disconnect cleanup;
- crash and normal-exit reporting.

Runner children are temporary. A door exit is a session event; the supervisor must not restart it behind the caller's back.

## Failure behavior

- Normal exit returns the caller to Foglet.
- Non-zero external exit or native callback crash reports a door crash.
- Timeout and disconnect trigger cleanup.
- Helper-backed PTY launches terminate the child process group.
- Sandbox-required launches fail closed when the helper or configured OS user is unavailable.

This boundary is part of the product shape: a door may scatter, but the BBS has to cohere afterward.
