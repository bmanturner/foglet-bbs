---
phase: 25-operator-console-conversion
fixed_at: 2026-04-26T13:25:52Z
review_path: .planning/phases/25-operator-console-conversion/25-REVIEW.md
iteration: 1
findings_in_scope: 4
fixed: 4
skipped: 0
status: all_fixed
---

# Phase 25: Code Review Fix Report

**Fixed at:** 2026-04-26T13:25:52Z
**Source review:** .planning/phases/25-operator-console-conversion/25-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 4
- Fixed: 4
- Skipped: 0

## Fixed Issues

### CR-01: BLOCKER - Account screen captures lowercase `q` before focused forms

**Files modified:** `lib/foglet_bbs/tui/screens/account.ex`, `test/foglet_bbs/tui/screens/account_test.exs`
**Commit:** 601f6d1, 8a8da04, bd8cc00
**Applied fix:** Account no longer treats lowercase `q` as a screen-level back command before focused forms can consume it. Test coverage now asserts lowercase `q` stays on the Account screen and dirties the active profile form, while the current back command uses the explicit Ctrl+Q contract.

### WR-01: WARNING - SITE and LIMITS render `[Enter] Submit` but ignore Enter

**Files modified:** `lib/foglet_bbs/tui/screens/sysop/site_form.ex`, `lib/foglet_bbs/tui/screens/sysop/limits_form.ex`
**Commit:** c25242a
**Applied fix:** Added `%{key: :enter}` submit handling to both SiteForm and LimitsForm so the rendered `[Enter] Submit` footer matches behavior. Ctrl+S remains supported.

### WR-02: WARNING - Test uses `Process.sleep/1` for synchronization

**Files modified:** `test/foglet_bbs/tui/screens/sysop_test.exs`
**Commit:** 620604d, 155eff2
**Applied fix:** Removed the sleep and changed the SYSTEM refresh test to assert that handling `r` leaves a valid, non-regressing snapshot without relying on wall-clock advancement or scheduler timing.

### WR-03: WARNING - Dialyzer ignores now mask warnings in the reviewed implementation files

**Files modified:** `.dialyzer_ignore.exs`, `lib/foglet_bbs/tui/screens/account/prefs_form.ex`, `lib/foglet_bbs/tui/screens/account/profile_form.ex`, `lib/foglet_bbs/tui/screens/account/ssh_keys_state.ex`, `lib/foglet_bbs/tui/screens/moderation/state.ex`
**Commit:** 62a5e76
**Applied fix:** Removed the broad Phase 25 file/type ignores, fixed the SSH key cursor helper and moderation summary specs in source, simplified Account form submit branches that Dialyzer proved unreachable, and retained only two strict message-level Account form ignores for the intentional defensive `:no_match` fallback.

## Skipped Issues

None.

---

_Fixed: 2026-04-26T13:25:52Z_
_Fixer: the agent (gsd-code-fixer)_
_Iteration: 1_
