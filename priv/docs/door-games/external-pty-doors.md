%{
  title: "External PTY doors",
  weight: 80
}
---

External PTY doors launch an executable outside the BEAM and bridge the caller's terminal through Foglet's runner. Use this for trusted command-line programs that need terminal I/O.

## Required manifest fields

External doors use `runtime: "external_pty"` and require absolute `command` and `working_dir` paths. `args` must be a list of strings. `pty` defaults to `true`.

## Helper-backed path

When `priv/doors/pty/foglet_pty_adapter.py` is available, Foglet uses it as the supported PTY backend. The helper opens a child PTY, launches the command with structured command and args, bridges framed I/O, applies resize, and terminates the child process group on cleanup. It requires Python 3 and POSIX PTY/ioctl support.

## Fallback paths

If the helper is unavailable and no sandbox is required, Foglet may degrade to `script(1)` or a plain pipe. These paths are useful for local demos, but they do not provide the same resize and process-group semantics. If a sandbox is requested, helper absence fails closed instead of falling back.

## Environment

External doors receive a clean environment assembled by Foglet. They do not inherit the service environment. Foglet supplies explicit manifest `env` values plus minimal `FOGLET_*` variables such as door id, user id, handle, session id, terminal size, and context path.

The default `PATH` is narrow when no manifest `PATH` is supplied. Prefer absolute paths anyway; it leaves fewer grains for the machine to misread.
