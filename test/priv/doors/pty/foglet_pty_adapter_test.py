#!/usr/bin/env python3
"""Regression tests for Foglet's PTY helper privilege-drop boundary."""

import importlib.util
import pathlib
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


if __name__ == "__main__":
    unittest.main()
