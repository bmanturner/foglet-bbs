# Door PTY backend decision (FOG-575)

## Source verification

FOG-575 was verified against a clean worktree created from `origin/main` at
`18101a561039981949b083151271baee22724ec2`.

The current implementation still uses `System.find_executable("script")` and
runs external PTY doors through `script -qfec <command> /dev/null` when a door
manifest has `pty?: true`. See `lib/foglet_bbs/doors/runner.ex` and
`docs/DOOR_RUNTIME.md`.

This decision only covers PTY fidelity for external doors. It does not solve the
FOG-522 sandbox/process-isolation work, executable allowlisting, catalog policy,
or DOS/dropfile compatibility beyond the existing runner contract.

## Requirements

A production-ready external door PTY backend must:

- preserve bidirectional interactive I/O for full-screen terminal programs;
- launch the door attached to a real child PTY rather than a pipe;
- propagate terminal resize events to the child PTY where the host supports it;
- distinguish normal exit, nonzero exit, timeout/stop, crash, and SSH disconnect;
- restore Foglet to a sane terminal state after the child exits or is stopped;
- keep native/native-crash failure isolated from the BEAM VM;
- avoid passing Foglet secrets or full session/user structs to door processes;
- be testable from ExUnit and from the SSH harness at normal and cramped sizes;
- be explicit about Docker/container requirements without coupling this slice to
  sandboxing.

## Options compared

### 1. Keep `script(1)` as-is and document limits

`script(1)` is already available on many Linux systems and gave the first Door
Games slice a cheap PTY-ish wrapper. It is easy to reason about and did not add
build dependencies.

Tradeoffs:

- Portability: mixed. GNU util-linux `script` and BSD `script` differ in flags
  and behavior.
- Deployment complexity: low when present, but behavior changes by image/base OS.
- Security posture: no BEAM-native crash risk, but shell wrapping remains part of
  the launch path and process-tree control is weak.
- Resize support: inadequate. Foglet records resize events but cannot perform a
  child PTY `TIOCSWINSZ` through `script`.
- Cleanup/restoration: best effort only; child process groups and alternate
  screen/raw-mode recovery are not under Foglet's direct control.
- Testability: enough for line-oriented demos, not enough for full-screen TUI
  semantics.

Decision: reject as the long-term backend. Keep it only as a temporary fallback
if the stronger adapter is unavailable and the manifest explicitly accepts that
limited mode.

### 2. Stronger OS PTY wrapper executable managed by Foglet

Add a small Foglet-owned helper executable that opens a PTY, forks/execs the
external door on the slave side, bridges data between Foglet and the PTY master,
and accepts resize/stop control messages from `Foglet.Doors.Runner`.

Recommended shape:

- helper lives under `priv/doors/pty/` and is built/packaged with the release;
- helper is a separate OS process launched through an Erlang `Port`, not a NIF;
- parent/helper protocol uses framed messages (for example `Port` packet mode)
  so door input bytes cannot be confused with resize/stop control messages;
- initial terminal size and narrow context/environment are passed at launch;
- resize messages call the host PTY resize ioctl (`TIOCSWINSZ` on Linux/BSD);
- timeout/disconnect paths tell the helper to terminate the child process group
  and then close the port if the helper does not exit promptly;
- the runner owns status mapping and terminal restoration messages back to the
  SSH/TUI layer.

Tradeoffs:

- Portability: good for Foglet's Linux-first deployment target; macOS/BSD can be
  supported by the same POSIX PTY APIs with CI/runtime caveats.
- Deployment complexity: moderate. A helper binary must be built or packaged in
  Docker/releases.
- Security posture: better than a NIF because helper crashes cannot corrupt the
  VM. It also enables process-group cleanup. It is not a sandbox by itself.
- Resize support: strong; resize can be propagated directly to the child PTY.
- Cleanup/restoration: strong enough for this slice when paired with process
  groups, runner timeout handling, and explicit SSH/TUI restoration.
- Testability: strong; ExUnit can exercise the helper with a minimal alternate
  screen/raw-mode demo, and the SSH harness can validate terminal recovery.

Decision: choose this approach.

### 3. Erlang/Elixir PTY library, port driver, or NIF

A dependency could provide PTY operations inside an Elixir-facing API.

Tradeoffs:

- Portability: depends on the library and OTP/version support.
- Deployment complexity: high if it adds NIF compilation and release-specific
  native artifacts.
- Security posture: a NIF or port driver expands the VM crash surface. A plain
  external port helper gives most of the benefit with less blast radius.
- Resize support: potentially strong if maintained.
- Cleanup/restoration: depends on the library exposing process-group controls.
- Testability: mixed; native dependency failures can make CI noisy.

Decision: do not choose a NIF/port driver for this slice. A library that shells
out to a helper is acceptable only if it preserves the separate-process failure
boundary and has a clear maintenance story.

### 4. Container/process-isolated PTY launch paired with FOG-522

Launching each door inside a container or stronger sandbox can pair naturally
with PTY allocation and process cleanup.

Tradeoffs:

- Portability: depends on Docker/container runtime availability.
- Deployment complexity: high for the first robust PTY slice.
- Security posture: strongest once designed, but it must also cover filesystem,
  network, UID/GID, cgroups, and operator configuration.
- Resize support: possible through the same helper/exec model, but not automatic.
- Cleanup/restoration: strong if the sandbox runtime owns process lifecycle.
- Testability: slower and more environment-dependent.

Decision: keep sandboxing in FOG-522. The FOG-575 PTY adapter should be designed
so FOG-522 can launch the helper inside an isolated process/container later, but
FOG-575 should not block on the full sandbox design.

## Chosen direction

Implement a Foglet-owned external PTY adapter helper executable, launched and
supervised by `Foglet.Doors.Runner` through an Erlang `Port` with a framed
control/data protocol.

The first implementation should replace the direct `script -qfec` wrapper for
`pty?: true` external/classic doors when the helper is available. `script(1)` may
remain as an explicitly documented degraded fallback for local demos, but the
production path and docs should treat the helper as the supported backend.

## Implementation notes for the Elixir OTP owner

- Add a boundary module such as `Foglet.Doors.PTYAdapter` or
  `Foglet.Doors.ExternalPTY` so `Runner` does not grow helper protocol details.
- Keep `Runner` as the lifecycle owner: start, input, resize, timeout,
  disconnect, exit status mapping, context-file cleanup, and owner notifications.
- Use process groups/sessions in the helper so timeout/disconnect can terminate
  the door tree, not only the immediate wrapper process.
- Ensure shell quoting is not the primary launch interface for the helper path.
  Pass command/args as structured helper arguments or framed launch metadata.
- Keep the environment allowlist from `Runner.external_env/1`; do not pass
  secrets, full user structs, or session structs.
- Add a minimal full-screen demo that enters alternate screen/raw-ish behavior,
  echoes input, handles resize, and restores on exit. It can be intentionally
  tiny; it exists to prove terminal semantics, not game quality.
- Add focused tests for normal exit, nonzero exit, timeout, crash/helper failure,
  disconnect cleanup, resize propagation, and fallback behavior if the helper is
  unavailable.
- Update `docs/DOOR_RUNTIME.md` and `docs/DOOR_GAMES.md` to make the supported
  backend, fallback limits, deployment requirements, and FOG-522 boundary clear.

## QA and Ops gates

- QA must verify via the SSH harness at 80x24 and at one cramped size after the
  implementation branch exists.
- Ops must review any Docker/release/package changes required to build and ship
  the helper, including how deployments fail or degrade if the helper is missing.

## Residual risk

This decision improves terminal fidelity and cleanup but does not make arbitrary
external doors safe. Before enabling untrusted real-world door programs, FOG-522
must still define sandboxing/process isolation, filesystem exposure, network
policy, and operator configuration.
