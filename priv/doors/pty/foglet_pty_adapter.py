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
import pty
import select
import signal
import struct
import sys
import termios
import tty


def write_frame(kind: bytes, payload: bytes = b"") -> None:
    body = kind + payload
    sys.stdout.buffer.write(struct.pack(">I", len(body)))
    sys.stdout.buffer.write(body)
    sys.stdout.buffer.flush()


def write_json(kind: bytes, payload: dict) -> None:
    write_frame(kind, json.dumps(payload, separators=(",", ":")).encode("utf-8"))


def set_winsize(fd: int, cols: int, rows: int) -> None:
    packed = struct.pack("HHHH", rows, cols, 0, 0)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, packed)


def terminate_child(child_pid: int) -> None:
    if child_pid <= 0:
        return
    try:
        os.killpg(child_pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    except OSError:
        try:
            os.kill(child_pid, signal.SIGTERM)
        except OSError:
            return


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
        child_pid, master_fd = pty.fork()
    except Exception as exc:
        write_json(b"E", {"reason": "pty_fork_failed", "detail": repr(exc)})
        return 126

    if child_pid == 0:
        try:
            if args.cwd:
                os.chdir(args.cwd)
            # Make the child terminal raw-ish from the start; full-screen apps may
            # still configure their own modes after exec.
            try:
                tty.setraw(0)
            except Exception:
                pass
            os.execvpe(command[0], command, os.environ.copy())
        except Exception as exc:
            os.write(2, ("foglet-pty exec failed: %r\r\n" % (exc,)).encode("utf-8", "replace"))
            os._exit(127)

    set_winsize(master_fd, args.cols, args.rows)
    stdin_fd = sys.stdin.buffer.fileno()
    os.set_blocking(stdin_fd, False)
    os.set_blocking(master_fd, False)
    control_buffer = b""
    running = True

    while True:
        exit_payload = reap_child(child_pid)
        if exit_payload is not None:
            write_json(b"X", exit_payload)
            return exit_payload["status"] if exit_payload["status"] is not None else 128 + int(exit_payload.get("signal") or 0)

        read_fds = [master_fd]
        if running:
            read_fds.append(stdin_fd)
        try:
            ready, _, _ = select.select(read_fds, [], [], 0.1)
        except InterruptedError:
            continue

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
                terminate_child(child_pid)
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
