# Door runner runtime boundary (FOG-516)

This slice establishes the OTP boundary for Door Games without moving launch
behavior into screen reducers.

Process / supervision map

```
FogletBbs.Supervisor (:one_for_one)
├─ Foglet.Sessions.Supervisor        # existing per-SSH-session state
├─ Foglet.Doors.Supervisor           # DynamicSupervisor, one child per active door
│  └─ Foglet.Doors.Runner            # temporary GenServer, one door handoff
│     ├─ native door callbacks       # in-runner callback boundary
│     └─ external executable Port    # optional `/usr/bin/script` PTY wrapper
└─ Foglet.SSH.Supervisor / CLIHandler # SSH channel lifecycle, resize/disconnect source

Foglet.TUI.Screen reducer
  -> Foglet.TUI.Effect.launch_door/2
  -> Foglet.TUI.App.Effects
  -> Foglet.Doors.Supervisor.start_runner/1
```

Ownership rules

- Screen reducers select a door and emit an explicit `%Foglet.TUI.Effect{}`.
  They do not spawn OS processes.
- `Foglet.TUI.App.Effects` interprets the launch effect and starts a supervised
  `Foglet.Doors.Runner`.
- `Foglet.Doors.Runner` owns native callback execution, external `Port`
  ownership, timeout/idle-timeout timers, context-file lifecycle, resize audit,
  disconnect cleanup, and exit notification.
- Runner children are `restart: :temporary`; door exits are session events and
  must not be restarted behind the user's back.

Failure path table

| Event | Owner | Behavior | Evidence |
| --- | --- | --- | --- |
| Native normal exit | `Foglet.Doors.Runner` | emits final output, posts `{:door_exited, ..., :normal, nil}`, stops normally | `test/foglet_bbs/doors/runner_test.exs` native echo test |
| Native crash | `Foglet.Doors.Runner` | catches callback exception, posts `:crash`, stops without supervisor restart | native crash test |
| External normal exit | external `Port` -> runner | exit status `0` becomes `:normal` | external env test |
| External non-zero exit | external `Port` -> runner | non-zero status becomes `:crash` with status | external crash test |
| Timeout | runner timer | closes port, sends best-effort `TERM` to OS pid, removes context file, reports `:timeout` | timeout test |
| SSH disconnect / session abandon | SSH interpreter should call `Runner.disconnect/1` | same cleanup path, reports `:disconnect` | disconnect test |
| Resize | SSH interpreter should call `Runner.resize/2` | native callback receives resize; external runner records size and notifies owner for concrete PTY adapter handling | native resize + external resize tests |

Security notes

- External doors receive only an allowlisted metadata set:
  `FOGLET_DOOR_ID`, `FOGLET_USER_ID`, `FOGLET_USERNAME`,
  `FOGLET_SESSION_ID`, `FOGLET_TERMINAL_WIDTH`, `FOGLET_TERMINAL_HEIGHT`, and
  `FOGLET_DOOR_CONTEXT`.
- The generated JSON context file contains the same narrow user/session/terminal
  metadata and is removed during runner cleanup.
- Application secrets, database credentials, API keys, and full session structs
  are not passed to door processes.
- Executable allowlisting/registration policy is intentionally not solved in
  this OTP slice; it belongs with the Door catalog/config/domain slice.
- `/usr/bin/script -qfec ... /dev/null` is the first-slice PTY wrapper only.
  FOG-575 chose a Foglet-owned external PTY adapter helper as the supported
  production direction before arbitrary full-screen doors are enabled. See
  `docs/DOOR_PTY_BACKEND_DECISION.md`.
- A non-Elixir demo executable is available at
  `priv/doors/demo/external_echo.sh`; runner tests launch it through the same
  `external_pty` path used for future SSH harness QA.

Residual risks / follow-up candidates

- A stronger Foglet-owned external PTY adapter should replace the `script(1)`
  fallback before arbitrary full-screen doors run in production. FOG-575 records
  the selected adapter direction in `docs/DOOR_PTY_BACKEND_DECISION.md`.
- Process-tree cleanup is best effort using the immediate port OS pid. A future
  sandbox/runner adapter should launch doors into an isolated process group or
  container before untrusted doors are enabled.
- Door authorization, persistence/audit rows, and catalog policy are outside
  this runtime slice and should stay with the owning domain/platform issue.
