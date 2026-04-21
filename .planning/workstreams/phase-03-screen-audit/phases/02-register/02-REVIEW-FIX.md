---
phase: 02-register
fixed_at: 2026-04-21T00:00:00Z
review_path: .planning/workstreams/phase-03-screen-audit/phases/02-register/02-REVIEW.md
fix_scope: all
findings_in_scope: 5
fixed: 5
skipped: 0
status: all_fixed
iteration: 1
---

# Phase 02: Code Review Fix Report

**Fixed at:** 2026-04-21
**Source review:** `.planning/workstreams/phase-03-screen-audit/phases/02-register/02-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 5
- Fixed: 5
- Skipped: 0

## Fixed Issues

### WR-01: Stale login-form state fixture causes KeyError crash in smoke tests

**Files modified:** `test/foglet_bbs/tui/layout_smoke_test.exs`
**Commit:** 164a064
**Applied fix:** Replaced all three stale `form: %{handle:, password:, error:}` state fixtures in the smoke test with the current post-TextInput shape (`handle_input:`, `password_input:`, `error:` at top level). Added a per-test `alias TextInput, as: TI` to the first two tests; used the full module name for the third (inline in the `screens` list). Affected test bodies: "login form renders handle and password fields", "login form with handle='alice' shows 'alice'", and the "all four screens fit within 24 rows" login entry.

---

### WR-02: @spec handle_key/2 in register.ex is missing `| :no_match`

**Files modified:** `lib/foglet_bbs/tui/screens/register.ex`
**Commit:** 98db75d
**Applied fix:** Added `| :no_match` to the `@spec handle_key(map(), map())` return type at line 76, aligning it with every other screen's spec and eliminating the Dialyzer warning about the `:no_match` branch being unreachable.

---

### WR-03: do_update({:register_wizard, event}) round-trip has no app-level integration test

**Files modified:** `test/foglet_bbs/tui/screens/register_test.exs`
**Commit:** 5b4f151
**Applied fix:** Added a new `describe "App.update/2 round-trip — invite_code step (WR-03)"` block with one test that calls `App.update({:key, %{key: :enter}}, state)` from a pre-seeded `:invite_code` step state (using the existing `invite_state/1` helper with `invite_code: "VALIDCODE1"`), then asserts `step == :combined`, `focused_field == :handle`, and `collected.invite_code == "VALIDCODE1"`. This exercises the full dispatch chain through `process_screen_commands` and `do_update({:register_wizard, ...})`.

**Note:** This test uses `App.update/2` directly (not via the Raxol lifecycle), which is the same entry point used by the runtime. The test result requires human verification of the logic path being exercised correctly.

---

### IN-01: init_screen_state/1 hardcodes mode: "open"

**Files modified:** `lib/foglet_bbs/tui/screens/register.ex`
**Commit:** 9de78b7
**Applied fix:** Added a `@doc` block to `init_screen_state/1` explicitly documenting that it always returns `mode: "open"` / `step: :combined` regardless of opts or runtime config, explains that mode-aware callers should rely on the lazy `get_register_ss/1` → `init_screen_state_for/1` path, and flags the divergence as intentional and tracked for Phase 8 (D-04, D-05).

---

### IN-02: Bare `rescue _ ->` in login test setup swallows all exception types

**Files modified:** `test/foglet_bbs/tui/screens/login_test.exs`
**Commit:** 8518b71
**Applied fix:** Replaced the 6-line `try/rescue _ ->` block with a single call to `Foglet.Config.get("require_email_verification", :not_seeded)`. `Config.get/2` exists and already handles the missing-key case with a default internally, so the try/rescue wrapper is redundant. This narrows the exception handling to only the cases `Config.get/2` is designed to swallow (missing key / ETS miss), rather than silently catching all exception types.

---

_Fixed: 2026-04-21_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
