#!/usr/bin/env python3
"""Regression tests for Foglet's PTY helper privilege-drop boundary."""

import importlib.util
import grp
import json
import os
import pathlib
import pwd
import struct
import subprocess
import sys
import tempfile
import textwrap
import unittest
from unittest import mock


HELPER_PATH = pathlib.Path(__file__).resolve().parents[4] / "priv" / "doors" / "pty" / "foglet_pty_adapter.py"


def load_helper():
    spec = importlib.util.spec_from_file_location("foglet_pty_adapter_under_test", HELPER_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class FakeOS:
    def __init__(self, *, inherited_groups=None, intended_groups=None, fail_initgroups=False, fail_setgroups=False):
        self.uid = 0
        self.gid = 0
        self.groups = list(inherited_groups or [])
        self.intended_groups = list(intended_groups or [])
        self.fail_initgroups = fail_initgroups
        self.fail_setgroups = fail_setgroups
        self.calls = []

    def geteuid(self):
        return self.uid

    def getegid(self):
        return self.gid

    def getgroups(self):
        return list(self.groups)

    def initgroups(self, user, gid):
        self.calls.append(("initgroups", user, gid))
        if self.fail_initgroups:
            raise OSError("forced initgroups failure")
        self.groups = list(self.intended_groups)

    def setgroups(self, groups):
        self.calls.append(("setgroups", list(groups)))
        if self.fail_setgroups:
            raise OSError("forced setgroups failure")
        self.groups = list(groups)

    def setgid(self, gid):
        self.calls.append(("setgid", gid))
        self.gid = gid

    def setuid(self, uid):
        self.calls.append(("setuid", uid))
        self.uid = uid


def decode_frames(data):
    frames = []
    offset = 0
    while offset + 4 <= len(data):
        frame_len = struct.unpack(">I", data[offset:offset + 4])[0]
        body = data[offset + 4:offset + 4 + frame_len]
        frames.append((body[:1], body[1:]))
        offset += 4 + frame_len
    return frames


class DropPrivilegesTest(unittest.TestCase):
    def setUp(self):
        self.helper = load_helper()
        self.run_as = {"user": "foglet-door", "uid": 1234, "gid": 2345}

    def patch_os(self, fake_os):
        return mock.patch.multiple(
            self.helper.os,
            geteuid=fake_os.geteuid,
            getegid=fake_os.getegid,
            getgroups=fake_os.getgroups,
            initgroups=fake_os.initgroups,
            setgroups=fake_os.setgroups,
            setgid=fake_os.setgid,
            setuid=fake_os.setuid,
        )

    def test_initgroups_failure_clears_inherited_supplementary_groups_before_uid_drop(self):
        secret_group = 4242
        fake_os = FakeOS(inherited_groups=[secret_group], fail_initgroups=True)

        def can_read_group_protected_secret():
            return secret_group in fake_os.getgroups()

        self.assertTrue(can_read_group_protected_secret())
        with self.patch_os(fake_os):
            self.helper.drop_privileges(self.run_as)

        self.assertFalse(can_read_group_protected_secret())
        self.assertEqual(fake_os.uid, self.run_as["uid"])
        self.assertEqual(fake_os.gid, self.run_as["gid"])
        self.assertEqual(fake_os.groups, [])
        self.assertIn(("setgroups", []), fake_os.calls)
        self.assertLess(fake_os.calls.index(("setgroups", [])), fake_os.calls.index(("setuid", self.run_as["uid"])))

    def test_group_setup_failure_fails_closed_before_setuid(self):
        fake_os = FakeOS(inherited_groups=[4242], fail_initgroups=True, fail_setgroups=True)

        with self.patch_os(fake_os):
            with self.assertRaisesRegex(RuntimeError, "sandbox_group_setup_failed"):
                self.helper.drop_privileges(self.run_as)

        self.assertNotIn(("setuid", self.run_as["uid"]), fake_os.calls)
        self.assertEqual(fake_os.uid, 0)
        self.assertEqual(fake_os.groups, [4242])

    def test_successful_initgroups_uses_target_users_intended_groups(self):
        fake_os = FakeOS(inherited_groups=[4242], intended_groups=[7777, 8888])

        with self.patch_os(fake_os):
            self.helper.drop_privileges(self.run_as)

        self.assertEqual(fake_os.uid, self.run_as["uid"])
        self.assertEqual(fake_os.gid, self.run_as["gid"])
        self.assertEqual(fake_os.groups, [7777, 8888])
        self.assertNotIn(("setgroups", []), fake_os.calls)


class TerminalOutputSanitizerTest(unittest.TestCase):
    def setUp(self):
        self.helper = load_helper()

    def test_strips_full_terminal_reset_without_dropping_neighboring_menu_output(self):
        sanitizer = self.helper.TerminalOutputSanitizer()

        self.assertEqual(
            sanitizer.filter(b"before\x1bcafter"),
            b"beforeafter",
        )

    def test_strips_split_full_terminal_reset_before_following_menu_output(self):
        sanitizer = self.helper.TerminalOutputSanitizer()

        self.assertEqual(sanitizer.filter(b"before\x1b"), b"before")
        self.assertEqual(sanitizer.filter(b"cafter"), b"after")

    def test_strips_door_terminal_mode_toggles_from_usurper_splash_prefix(self):
        sanitizer = self.helper.TerminalOutputSanitizer()

        self.assertEqual(
            sanitizer.filter(b"\x1b[?1h\x1b=\x1b[2J\x1b[Hdraw"),
            b"\x1b[2J\x1b[Hdraw",
        )

    def test_strips_split_application_keypad_toggle_before_following_output(self):
        sanitizer = self.helper.TerminalOutputSanitizer()

        self.assertEqual(sanitizer.filter(b"before\x1b"), b"before")
        self.assertEqual(sanitizer.filter(b"=after"), b"after")

    def test_defers_standalone_full_screen_clear_until_menu_redraw_arrives(self):
        sanitizer = self.helper.TerminalOutputSanitizer()

        self.assertEqual(sanitizer.filter(b"\x1b[2J\x1b[H"), b"")
        self.assertEqual(
            sanitizer.filter(b"Menu\r\nYour choice: "),
            b"\x1b[2J\x1b[HMenu\r\nYour choice: ",
        )

    def test_keeps_full_screen_clear_when_frame_contains_redraw_output(self):
        sanitizer = self.helper.TerminalOutputSanitizer()

        self.assertEqual(
            sanitizer.filter(b"\x1b[2J\x1b[HMenu\r\nYour choice: "),
            b"\x1b[2J\x1b[HMenu\r\nYour choice: ",
        )


class DirectHelperLaunchTest(unittest.TestCase):
    def test_broken_stdout_pipe_exits_without_traceback(self):
        helper = load_helper()

        class BrokenBuffer:
            def write(self, _data):
                raise BrokenPipeError("closed pipe")

            def flush(self):
                raise AssertionError("flush should not be reached")

        with mock.patch.object(helper.sys, "stdout", mock.Mock(buffer=BrokenBuffer())):
            with self.assertRaises(SystemExit) as raised:
                helper.write_frame(b"O", b"data")

        self.assertEqual(raised.exception.code, 0)

    def test_forced_group_setup_failure_reports_error_before_stdin_eof_can_terminate_child(self):
        current_user = pwd.getpwuid(os.getuid()).pw_name
        current_group = grp.getgrgid(pwd.getpwuid(os.getuid()).pw_gid).gr_name

        with tempfile.TemporaryDirectory(prefix="foglet-pty-helper-") as tmpdir:
            wrapper_path = pathlib.Path(tmpdir) / "force_group_failure.py"
            marker_path = pathlib.Path(tmpdir) / "executed-marker"
            wrapper_path.write_text(
                textwrap.dedent(
                    f"""
                    #!{sys.executable}
                    import os
                    import runpy

                    os.geteuid = lambda: 0
                    os.getegid = lambda: 0

                    def fail_initgroups(user, gid):
                        raise OSError("forced initgroups failure")

                    def fail_setgroups(groups):
                        raise OSError("forced setgroups failure")

                    os.initgroups = fail_initgroups
                    os.setgroups = fail_setgroups
                    os.setgid = lambda gid: None
                    os.setuid = lambda uid: None

                    runpy.run_path({str(HELPER_PATH)!r}, run_name="__main__")
                    """
                )
            )
            wrapper_path.chmod(0o700)

            result = subprocess.run(
                [
                    sys.executable,
                    str(wrapper_path),
                    "--cols",
                    "80",
                    "--rows",
                    "24",
                    "--sandbox-mode",
                    "restricted_user_process_group",
                    "--run-as-user",
                    current_user,
                    "--run-as-group",
                    current_group,
                    "--",
                    "/bin/sh",
                    "-c",
                    f"echo EXECUTED > {marker_path}",
                ],
                input=b"",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            frames = decode_frames(result.stdout)
            self.assertEqual(result.returncode, 126, result.stderr.decode("utf-8", "replace"))
            self.assertEqual(len(frames), 1)
            kind, payload = frames[0]
            self.assertEqual(kind, b"E")
            self.assertEqual(json.loads(payload.decode("utf-8")), {"reason": "sandbox_group_setup_failed"})
            self.assertFalse(marker_path.exists())
            self.assertNotIn(b"forced initgroups failure", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
