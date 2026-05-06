#!/usr/bin/env python3
"""Foglet external door PTY adapter helper.

Protocol over stdin/stdout uses Erlang Port packet mode with 4-byte big-endian
length prefixes supplied by the BEAM port driver. Payloads are one-byte typed:

  D<bytes>   door stdin bytes
  R<json>    resize control, {"cols": int, "rows": int}
  T          terminate child process group

Helper-to-BEAM frames:

  O<bytes>   door PTY output bytes
  X<json>    child exit status, {"status": int|null, "signal": int|null}
  E<json>    helper/launch error
"""

import argparse
import errno
import fcntl
import json
import os
import grp
import pwd
import pty
import select
import signal
import struct
import sys
import termios
import time


def write_frame(kind: bytes, payload: bytes = b"") -> None:
    body = kind + payload
    try:
        sys.stdout.buffer.write(struct.pack(">I", len(body)))
        sys.stdout.buffer.write(body)
        sys.stdout.buffer.flush()
    except BrokenPipeError:
        # The owning BEAM port/SSH channel has already gone away (for example,
        # a client disconnect while the door is still emitting output). Exit
        # quietly so disconnect cleanup does not leave scary helper tracebacks.
        silence_stdout_for_shutdown()
        raise SystemExit(0)


def silence_stdout_for_shutdown() -> None:
    try:
        devnull_fd = os.open(os.devnull, os.O_WRONLY)
        try:
            os.dup2(devnull_fd, sys.stdout.fileno())
        finally:
            os.close(devnull_fd)
    except (AttributeError, OSError, TypeError, ValueError):
        sys.stdout = None


def write_json(kind: bytes, payload: dict) -> None:
    write_frame(kind, json.dumps(payload, separators=(",", ":")).encode("utf-8"))


def set_winsize(fd: int, cols: int, rows: int) -> None:
    packed = struct.pack("HHHH", rows, cols, 0, 0)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, packed)


def signal_child_group(child_pid: int, sig: signal.Signals = signal.SIGTERM) -> None:
    if child_pid <= 0:
        return
    try:
        os.killpg(child_pid, sig)
    except ProcessLookupError:
        return
    except OSError:
        try:
            os.kill(child_pid, sig)
        except OSError:
            return


def terminate_child(child_pid: int) -> None:
    signal_child_group(child_pid, signal.SIGTERM)
    # Escalate for process-tree cleanup. Grandchildren are not waitable here,
    # so this is a bounded best-effort process-group KILL after TERM.
    time.sleep(0.1)
    signal_child_group(child_pid, signal.SIGKILL)


def resolve_run_as(user: str | None, group: str | None):
    if not user:
        return None
    try:
        pw = pwd.getpwnam(user)
    except KeyError:
        raise RuntimeError("sandbox_user_not_found")

    if group:
        try:
            gid = grp.getgrnam(group).gr_gid
        except KeyError:
            raise RuntimeError("sandbox_group_not_found")
    else:
        gid = pw.pw_gid

    uid = pw.pw_uid
    current_euid = os.geteuid()
    if current_euid != 0 and uid != current_euid:
        raise RuntimeError("sandbox_privileges_insufficient")

    return {"user": user, "uid": uid, "gid": gid}


def drop_privileges(run_as) -> None:
    if not run_as:
        return
    if os.geteuid() == 0:
        try:
            os.initgroups(run_as["user"], run_as["gid"])
        except OSError:
            # Fail closed unless inherited supplementary groups can be cleared.
            # This keeps minimal/user-namespace deployments from executing doors
            # with the Foglet service account's supplemental group access.
            try:
                os.setgroups([])
            except OSError:
                raise RuntimeError("sandbox_group_setup_failed")

        os.setgid(run_as["gid"])
        os.setuid(run_as["uid"])

        if os.geteuid() != run_as["uid"] or os.getegid() != run_as["gid"]:
            raise RuntimeError("sandbox_identity_setup_failed")


def child_environment() -> dict[str, str]:
    # The BEAM port process may inherit application secrets from the service
    # environment. External doors receive only the variables Foglet intentionally
    # supplied to this helper: Foglet metadata plus explicitly configured safe
    # terminal locale variables.
    allowed_prefixes = ("FOGLET_",)
    allowed_names = {"TERM", "LANG", "LC_ALL", "LC_CTYPE", "COLORTERM"}
    return {
        key: value
        for key, value in os.environ.items()
        if key.startswith(allowed_prefixes) or key in allowed_names
    }


def reap_child(child_pid: int):
    try:
        waited_pid, status = os.waitpid(child_pid, os.WNOHANG)
    except ChildProcessError:
        return {"status": None, "signal": None}
    if waited_pid == 0:
        return None
    if os.WIFEXITED(status):
        return {"status": os.WEXITSTATUS(status), "signal": None}
    if os.WIFSIGNALED(status):
        return {"status": None, "signal": os.WTERMSIG(status)}
    return {"status": None, "signal": None}


FINAL_DRAIN_MAX_BYTES = 64 * 1024
FINAL_DRAIN_MAX_FRAMES = 16
FINAL_DRAIN_MAX_SECONDS = 0.05


def drain_pty_output(
    master_fd: int,
    *,
    max_bytes: int = FINAL_DRAIN_MAX_BYTES,
    max_frames: int = FINAL_DRAIN_MAX_FRAMES,
    max_seconds: float = FINAL_DRAIN_MAX_SECONDS,
) -> bool:
    """Forward bounded buffered PTY output before reporting child exit.

    A fast child can write its final bytes and exit before the adapter's next
    event-loop iteration. If the helper reports X(exit) first, Foglet's runner
    stops and test/SSH owners may observe the exit before the final output.

    This drain must stay strictly bounded: a forked grandchild can keep the PTY
    slave open and write forever after the direct child exits. An unbounded
    pre-termination drain would let that survivor delay process-group cleanup
    and the X(exit) frame indefinitely.
    """
    deadline = time.monotonic() + max_seconds
    bytes_forwarded = 0
    frames_forwarded = 0

    while bytes_forwarded < max_bytes and frames_forwarded < max_frames:
        if time.monotonic() >= deadline:
            return True

        try:
            read_size = min(8192, max_bytes - bytes_forwarded)
            data = os.read(master_fd, read_size)
        except BlockingIOError:
            return True
        except OSError as exc:
            if exc.errno in (errno.EIO, errno.EBADF):
                return False
            write_json(b"E", {"reason": "pty_read_failed", "detail": repr(exc)})
            return False

        if not data:
            return False

        write_frame(b"O", data)
        bytes_forwarded += len(data)
        frames_forwarded += 1

    return True


def write_sandbox_error(error_fd: int | None, reason: str) -> None:
    if error_fd is None:
        return
    try:
        os.write(error_fd, reason.encode("utf-8", "replace"))
    except OSError:
        return


def door_environment() -> dict:
    """Return the already-sanitized environment supplied by Foglet.

    The Elixir PTY adapter launches this helper through `env -i` with only
    manifest env entries, required FOGLET_* metadata, and a narrow PATH. Keep
    the exec environment explicit here instead of merging in a fresh host env.
    """
    return dict(os.environ)


def handle_control(payload: bytes, master_fd: int, child_pid: int) -> bool:
    if not payload:
        return True
    kind, body = payload[:1], payload[1:]
    if kind == b"D":
        if body:
            os.write(master_fd, body)
    elif kind == b"R":
        data = json.loads(body.decode("utf-8"))
        set_winsize(master_fd, int(data["cols"]), int(data["rows"]))
        try:
            os.killpg(child_pid, signal.SIGWINCH)
        except OSError:
            pass
    elif kind == b"T":
        terminate_child(child_pid)
        return False
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description="Foglet external door PTY adapter")
    parser.add_argument("--cols", type=int, required=True)
    parser.add_argument("--rows", type=int, required=True)
    parser.add_argument("--cwd")
    parser.add_argument("--sandbox-mode", choices=["none", "restricted_user_process_group"], default="none")
    parser.add_argument("--run-as-user")
    parser.add_argument("--run-as-group")
    parser.add_argument("--", dest="dashdash", action="store_true")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()

    command = args.command
    if command and command[0] == "--":
        command = command[1:]
    if not command:
        write_json(b"E", {"reason": "missing_command"})
        return 127

    try:
        run_as = resolve_run_as(args.run_as_user, args.run_as_group)
    except RuntimeError as exc:
        write_json(b"E", {"reason": str(exc)})
        return 126

    if args.sandbox_mode == "restricted_user_process_group" and not run_as:
        write_json(b"E", {"reason": "sandbox_user_required"})
        return 126

    error_read_fd, error_write_fd = os.pipe()

    try:
        child_pid, master_fd = pty.fork()
    except Exception as exc:
        os.close(error_read_fd)
        os.close(error_write_fd)
        write_json(b"E", {"reason": "pty_fork_failed", "detail": repr(exc)})
        return 126

    if child_pid == 0:
        os.close(error_read_fd)
        try:
            set_winsize(0, args.cols, args.rows)
            if args.cwd:
                os.chdir(args.cwd)
            drop_privileges(run_as)
            os.close(error_write_fd)
            os.execvpe(command[0], command, door_environment())
        except RuntimeError as exc:
            write_sandbox_error(error_write_fd, str(exc))
            os._exit(126)
        except Exception as exc:
            os.write(2, ("foglet-pty exec failed: %r\r\n" % (exc,)).encode("utf-8", "replace"))
            os._exit(127)

    os.close(error_write_fd)
    set_winsize(master_fd, args.cols, args.rows)
    stdin_fd = sys.stdin.buffer.fileno()
    os.set_blocking(stdin_fd, False)
    os.set_blocking(master_fd, False)
    os.set_blocking(error_read_fd, False)
    control_buffer = b""
    running = True
    stdin_eof_pending = False

    while True:
        if error_read_fd is not None:
            try:
                reason_bytes = os.read(error_read_fd, 256)
            except BlockingIOError:
                reason_bytes = None
            except OSError:
                reason_bytes = b"sandbox_group_setup_failed"

            if reason_bytes:
                reason = reason_bytes.decode("utf-8", "replace")
                drain_pty_output(master_fd)
                terminate_child(child_pid)
                write_json(b"E", {"reason": reason})
                return 126
            if reason_bytes == b"":
                os.close(error_read_fd)
                error_read_fd = None
                if stdin_eof_pending:
                    terminate_child(child_pid)

        exit_payload = reap_child(child_pid)
        if exit_payload is not None:
            drain_pty_output(master_fd)
            terminate_child(child_pid)
            drain_pty_output(master_fd)
            write_json(b"X", exit_payload)
            return exit_payload["status"] if exit_payload["status"] is not None else 128 + int(exit_payload.get("signal") or 0)

        read_fds = [master_fd]
        if error_read_fd is not None:
            read_fds.append(error_read_fd)
        if running:
            read_fds.append(stdin_fd)
        try:
            ready, _, _ = select.select(read_fds, [], [], 0.1)
        except InterruptedError:
            continue

        if error_read_fd is not None and error_read_fd in ready:
            try:
                reason_bytes = os.read(error_read_fd, 256)
                reason = reason_bytes.decode("utf-8", "replace")
            except OSError:
                reason_bytes = b""
                reason = "sandbox_group_setup_failed"
            if reason:
                drain_pty_output(master_fd)
                terminate_child(child_pid)
                write_json(b"E", {"reason": reason})
                return 126
            if not reason_bytes:
                os.close(error_read_fd)
                error_read_fd = None

        if master_fd in ready:
            try:
                data = os.read(master_fd, 8192)
                if data:
                    write_frame(b"O", data)
            except OSError as exc:
                if exc.errno not in (errno.EIO, errno.EBADF):
                    write_json(b"E", {"reason": "pty_read_failed", "detail": repr(exc)})
                terminate_child(child_pid)
                running = False

        if stdin_fd in ready:
            try:
                chunk = os.read(stdin_fd, 8192)
            except BlockingIOError:
                chunk = b""
            if not chunk:
                if error_read_fd is None:
                    terminate_child(child_pid)
                else:
                    # Direct helper launches and fast setup failures can present
                    # stdin EOF before the child has reported sandbox setup over
                    # the side pipe. Defer termination until setup has either
                    # failed with an E frame or succeeded and closed the pipe, so
                    # EOF cannot race a privacy-safe sandbox error into X/SIGTERM.
                    stdin_eof_pending = True
                running = False
            control_buffer += chunk
            while len(control_buffer) >= 4:
                frame_len = struct.unpack(">I", control_buffer[:4])[0]
                if len(control_buffer) < 4 + frame_len:
                    break
                frame = control_buffer[4:4 + frame_len]
                control_buffer = control_buffer[4 + frame_len:]
                running = handle_control(frame, master_fd, child_pid) and running


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
