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
│              └─ optional restricted OS user/group drop before exec
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
| Timeout | runner timer | sends helper terminate when present, helper sends TERM then bounded KILL to the child process group, closes port, removes context file, reports `:timeout` | timeout + sandbox child/grandchild process-tree test |
| SSH disconnect / session abandon | SSH interpreter should call `Runner.disconnect/1` | same cleanup path, reports `:disconnect` | disconnect + sandbox child/grandchild process-tree test |
| Resize | SSH interpreter should call `Runner.resize/2` | native callback receives resize; helper-backed PTY receives framed resize and performs child `TIOCSWINSZ`; plain/fallback path records/notifies only | native resize + full-screen PTY resize tests |
| Helper unavailable | `Foglet.Doors.PTYAdapter` | unsandboxed PTY manifests may degrade to `script(1)`/plain; sandbox-required manifests fail closed with `{:sandbox_unavailable, :pty_helper_missing}` | fallback + sandbox fail-closed tests |
| Sandbox user/group missing or insufficient privilege | PTY helper | emits a framed helper error before command exec; runner exits without app-user fallback | sandbox missing-user test; same-user test covers local non-root execution |

Security notes

- External helper-backed doors receive only an allowlisted metadata set:
  `FOGLET_DOOR_ID`, `FOGLET_USER_ID`, `FOGLET_USERNAME`,
  `FOGLET_SESSION_ID`, `FOGLET_TERMINAL_WIDTH`, `FOGLET_TERMINAL_HEIGHT`, and
  `FOGLET_DOOR_CONTEXT`.
- The generated JSON context file contains the same narrow user/session/terminal
  metadata and is removed during runner cleanup.
- Application secrets, database credentials, API keys, and full session structs
  are not passed to helper-backed door processes. The helper rebuilds the child
  environment instead of forwarding the Foglet service environment.
- Executable allowlisting/registration policy is intentionally not solved in
  this OTP slice; it belongs with the Door catalog/config/domain slice.
- `priv/doors/pty/foglet_pty_adapter.py` is the supported PTY backend for
  `pty?: true` external/classic doors. It opens a real child PTY, optionally
  drops to the manifest sandbox user/group, launches the command with structured
  `command` + `args`, bridges framed I/O through the Erlang Port, applies resize
  with `TIOCSWINSZ`, and terminates the child process group on cleanup. It
  requires Python 3 and POSIX PTY/ioctl support in the runtime image.
- `/usr/bin/script -qfec ... /dev/null` is now only an explicit degraded
  fallback when the Foglet helper is unavailable. It is acceptable for local
  demos but does not provide the supported resize/process-group semantics.
- A non-Elixir line demo is available at `priv/doors/demo/external_echo.sh`; a
  minimal alternate-screen probe is available at
  `priv/doors/demo/fullscreen_probe.py`. Runner tests launch both through the
  same `external_pty` path used for future SSH harness QA.

Runtime config contract

Sandboxed external-door manifest shape:

```elixir
sandbox: %{
  mode: :restricted_user_process_group,
  user: "foglet-door",
  group: "foglet-door",
  process_tree: :process_group,
  fail_closed?: true
}
```

Only `:none` and `:restricted_user_process_group` are valid modes in this
baseline. `process_tree` is intentionally only `:process_group`. If sandboxing is
required and the helper cannot resolve/drop to the configured OS user/group, the
launch fails closed before the door command executes. cgroup/systemd-scope,
bubblewrap/firejail, namespaces, containers, and microVMs remain out of this
branch unless the board approves a broader platform slice.

Residual risks / follow-up candidates

- This baseline does not isolate filesystem mounts, network, seccomp, or resource
  usage. Host/container setup must provide the restricted `foglet-door`-style
  user and directory permissions for real deployments.
- Docker/release packaging now installs Python 3 in the final runtime image and
  includes `priv/doors/pty/foglet_pty_adapter.py` via the release `priv` tree.
  Deployments that remove Python 3 or override the helper path will degrade to
  the documented fallback instead of failing closed today.
- Door authorization, persistence/audit rows, and catalog policy are outside
  this runtime slice and should stay with the owning domain/platform issue.
