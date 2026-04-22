---
phase: 01-login
fixed_at: 2026-04-21T00:00:00Z
findings_in_scope: 4
fixed: 3
skipped: 1
iteration: 1
status: all_fixed
---

# Phase 01: Code Review Fix Report

**Fixed:** 2026-04-21
**Scope:** all (Critical + Warning + Info)
**Status:** all_fixed

## Summary

All actionable findings resolved. WR-01 was already committed prior to this fix pass (removed from REVIEW.md). WR-02 and IN-01 fixed together in a single commit. IN-02 accepted with no code change required per review guidance.

---

## Fixes Applied

### WR-01: Password mask lost after failed login — pre-existing fix

**Status:** Already fixed (committed before this fix pass)
**Commit:** see git log for `fix(01)` commits prior to `951757b`

`TextInput.init([])` on the error branch was updated to `TextInput.init(mask_char: "*")` before this fix pass ran. Finding was removed from REVIEW.md.

---

### WR-02 + IN-01: Deterministic pending-user test + dead password branch

**Status:** Fixed
**Commit:** `951757b`
**File:** `test/foglet_bbs/tui/screens/login_test.exs`

WR-02 (non-deterministic `case` assertion) and IN-01 (dead `attrs["password"]` branch) were fixed together:

- Replaced `valid_user_attributes()` with `valid_user_attributes(%{password: password})` using an explicit seed password
- Replaced the `case new_state.modal` fallback with direct pattern match assertions
- Eliminated the `attrs[:password] || attrs["password"]` dead branch (now unused)

---

### IN-02: `get_login_ss/1` fallback nil defaults — accepted

**Status:** Skipped (no code change required)

Per the review: "No code change is required if the invariant is trusted; this is a clarity note." The invariant (submit_login/1 only reachable when :login_form is active) is structural and enforced by the call chain. No fix applied.

---

_Fixed: 2026-04-21_
_Fixer: Claude (gsd-code-fixer)_
