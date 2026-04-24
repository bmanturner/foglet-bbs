---
phase: 04-shared-invite-surface-activation
reviewed: 2026-04-24T02:05:54Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - lib/foglet_bbs/tui/screens/moderation.ex
  - lib/foglet_bbs/tui/screens/moderation/state.ex
  - test/foglet_bbs/tui/screens/moderation_test.exs
findings:
  critical: 0
  warning: 0
  info: 0
  total: 0
status: clean
---

# Phase 04: Code Review Report

**Reviewed:** 2026-04-24T02:05:54Z
**Depth:** standard
**Files Reviewed:** 3
**Status:** clean

## Summary

Re-reviewed the current Moderation invite visibility fix after commit `53ae443`, scoped to the Moderation screen, Moderation screen state, and Moderation tests.

Prior warning `WR-01` is resolved. `lib/foglet_bbs/tui/screens/moderation.ex` now applies a Moderation-specific invite visibility predicate that only delegates to `ShellVisibility.invites_visible?/2` for `:mod` actors, and returns false for sysops, regular users, nil users, and any other actor shape. This keeps the Moderation `INVITES` tab aligned with the phase rule: moderators see it only under the `"mods"` runtime policy, while sysops use their own Sysop invite surface.

The regression coverage in `test/foglet_bbs/tui/screens/moderation_test.exs` now verifies:

- moderators see `INVITES` under `"mods"`;
- moderators do not see `INVITES` under `"any_user"` or `"sysop_only"`;
- regular and nil users do not see `INVITES`;
- sysops do not see Moderation `INVITES` under `"any_user"`, `"mods"`, or `"sysop_only"`;
- stale active `INVITES` state is clamped away when runtime policy no longer permits the tab.

All reviewed files meet quality standards. No issues found.

## Verification

Ran:

```bash
mix test test/foglet_bbs/tui/screens/moderation_test.exs
```

Result: `20 tests, 0 failures`.

The command emitted existing warnings from vendored `raxol` modules during compilation, but no Moderation test failures.

---

_Reviewed: 2026-04-24T02:05:54Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
