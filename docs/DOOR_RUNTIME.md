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
│     └─ external executable Port    # Foglet PTY helper, script fallback, or plain pipe
│        └─ priv/doors/pty/foglet_pty_adapter.py
│           └─ child PTY + external command process group
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
  ownership, timeout/idle-timeout timers, context-file lifecycle, resize
  dispatch/audit, disconnect cleanup, and exit notification.
- `Foglet.Doors.PTYAdapter` owns external PTY helper protocol details so the
  runner does not shell-quote production PTY launches itself.
- Runner children are `restart: :temporary`; door exits are session events and
  must not be restarted behind the user's back.

Failure path table

| Event | Owner | Behavior | Evidence |
| --- | --- | --- | --- |
| Native normal exit | `Foglet.Doors.Runner` | emits final output, posts `{:door_exited, ..., :normal, nil}`, stops normally | `test/foglet_bbs/doors/runner_test.exs` native echo test |
| Native crash | `Foglet.Doors.Runner` | catches callback exception, posts `:crash`, stops without supervisor restart | native crash test |
| External normal exit | helper/plain `Port` -> runner | exit status `0` becomes `:normal`; helper-backed PTY sends framed child exit before port shutdown | external env test |
| External non-zero exit | helper/plain `Port` -> runner | non-zero status becomes `:crash` with status | external crash + helper crash tests |
| Timeout | runner timer | sends helper terminate when present, closes port, sends best-effort `TERM` to helper/plain OS pid, removes context file, reports `:timeout` | timeout test |
| SSH disconnect / session abandon | SSH interpreter should call `Runner.disconnect/1` | same cleanup path, reports `:disconnect` | disconnect test |
| Resize | SSH interpreter should call `Runner.resize/2` | native callback receives resize; helper-backed PTY receives framed resize and performs child `TIOCSWINSZ`; plain/fallback path records/notifies only | native resize + full-screen PTY resize tests |
| Helper unavailable | `Foglet.Doors.PTYAdapter` | explicit degraded fallback to `script(1)` when available, otherwise plain pipe | fallback test |

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
- `priv/doors/pty/foglet_pty_adapter.py` is the supported PTY backend for
  `pty?: true` external/classic doors. It opens a real child PTY, launches the
  command with structured `command` + `args`, bridges framed I/O through the
  Erlang Port, applies resize with `TIOCSWINSZ`, and terminates the child process
  group on cleanup. It requires Python 3 and POSIX PTY/ioctl support in the
  runtime image.
- `/usr/bin/script -qfec ... /dev/null` is now only an explicit degraded
  fallback when the Foglet helper is unavailable. It is acceptable for local
  demos but does not provide the supported resize/process-group semantics.
- A non-Elixir line demo is available at `priv/doors/demo/external_echo.sh`; a
  minimal alternate-screen probe is available at
  `priv/doors/demo/fullscreen_probe.py`. Runner tests launch both through the
  same `external_pty` path used for future SSH harness QA.

Residual risks / follow-up candidates

- FOG-522 still owns sandbox/process isolation, filesystem exposure, network
  policy, and deployment hardening for untrusted real-world door programs. The
  helper improves PTY fidelity; it is not a sandbox.
- Docker/release packaging now installs Python 3 in the final runtime image and
  includes `priv/doors/pty/foglet_pty_adapter.py` via the release `priv` tree.
  Deployments that remove Python 3 or override the helper path will degrade to
  the documented fallback instead of failing closed today.
- Door authorization, persistence/audit rows, and catalog policy are outside
  this runtime slice and should stay with the owning domain/platform issue.
