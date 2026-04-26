---
phase: 25-operator-console-conversion
reviewed: 2026-04-26T12:49:37Z
depth: standard
files_reviewed: 29
files_reviewed_list:
  - .dialyzer_ignore.exs
  - lib/foglet_bbs/tui/app.ex
  - lib/foglet_bbs/tui/screens/account.ex
  - lib/foglet_bbs/tui/screens/account/prefs_form.ex
  - lib/foglet_bbs/tui/screens/account/profile_form.ex
  - lib/foglet_bbs/tui/screens/account/ssh_keys_actions.ex
  - lib/foglet_bbs/tui/screens/account/ssh_keys_state.ex
  - lib/foglet_bbs/tui/screens/account/ssh_keys_surface.ex
  - lib/foglet_bbs/tui/screens/account/state.ex
  - lib/foglet_bbs/tui/screens/moderation.ex
  - lib/foglet_bbs/tui/screens/moderation/state.ex
  - lib/foglet_bbs/tui/screens/shared/invites_actions.ex
  - lib/foglet_bbs/tui/screens/shared/invites_state.ex
  - lib/foglet_bbs/tui/screens/shared/invites_surface.ex
  - lib/foglet_bbs/tui/screens/sysop/limits_form.ex
  - lib/foglet_bbs/tui/screens/sysop/site_form.ex
  - lib/foglet_bbs/tui/widgets/modal/form.ex
  - lib/foglet_bbs/tui/widgets/modal/form/submit_stash.ex
  - test/foglet_bbs/tui/layout_smoke_test.exs
  - test/foglet_bbs/tui/screens/account_test.exs
  - test/foglet_bbs/tui/screens/moderation_test.exs
  - test/foglet_bbs/tui/screens/sysop_test.exs
  - test/foglet_bbs/tui/widgets/modal/form/submit_stash_test.exs
  - test/foglet_bbs/tui/widgets/modal/form_test.exs
  - test/support/foglet/tui/layout_smoke/account_helper.ex
  - test/support/foglet/tui/layout_smoke/moderation_helper.ex
  - test/support/foglet/tui/layout_smoke/sysop_helper.ex
  - test/support/foglet/tui/layout_smoke_helpers.ex
  - vendor/raxol/lib/raxol/ui/layout/engine.ex
findings:
  critical: 1
  warning: 3
  info: 0
  total: 4
status: issues_found
---

# Phase 25: Code Review Report

**Reviewed:** 2026-04-26T12:49:37Z
**Depth:** standard
**Files Reviewed:** 29
**Status:** issues_found

## Summary

Reviewed the configured TUI/operator-console conversion files at standard depth, including the account, moderation, sysop form surfaces, Modal.Form, Raxol layout engine changes, and related tests. The main blocker is an Account screen key-routing regression: the screen-level lowercase `q` handler runs before form/tab delegates, so users cannot type `q` into profile fields or SSH public keys. Additional warnings cover misleading submit affordances, a timing-dependent test, and broad Dialyzer suppressions added for touched files.

## Critical Issues

### CR-01: BLOCKER - Account screen captures lowercase `q` before focused forms

**File:** `lib/foglet_bbs/tui/screens/account.ex:77`
**Issue:** `Account.handle_key/2` exits to `:main_menu` for both `"q"` and `"Q"` before delegating to the active tab. The PROFILE and PREFS tabs are text forms, and the SSH KEYS add flow accepts arbitrary OpenSSH key material. Pressing lowercase `q` while editing any of those fields navigates away instead of inserting the character, making normal text entry and some public keys impossible through the live UI.
**Fix:**
```elixir
# Keep the explicit Back command, but let editable surfaces consume lowercase q.
def handle_key(%{key: :char, char: "Q"}, state) do
  {:update, %{state | current_screen: :main_menu}, []}
end

def handle_key(event, state) do
  ss = synced_screen_state(state)
  # Existing tab delegation continues here; lowercase "q" reaches ProfileForm,
  # PrefsForm, SSHKeysActions, or InvitesActions first.
end
```

If lowercase `q` must remain a global shortcut, handle it only after the active delegate returns `:no_match`, and never while `ss.ssh_keys.mode == :add` or the active tab is a form.

## Warnings

### WR-01: WARNING - SITE and LIMITS render `[Enter] Submit` but ignore Enter

**File:** `lib/foglet_bbs/tui/screens/sysop/site_form.ex:325`
**Issue:** The SITE form footer advertises `[Enter] Submit`, but `handle_key/2` only submits on Ctrl+S at line 84. Pressing Enter falls through to the catch-all at line 97 and does nothing. The LIMITS form has the same mismatch: it renders the same footer at `lib/foglet_bbs/tui/screens/sysop/limits_form.ex:186`, but only Ctrl+S submits at line 59. This is a user-facing regression because the rendered control contract is false.
**Fix:**
```elixir
# In both SiteForm and LimitsForm:
def handle_key(%{key: :enter}, state), do: submit(state)
def handle_key(%{key: :char, char: "s", ctrl: true}, state), do: submit(state)
```

Alternatively, keep Ctrl+S only and change the footer text to the actual keybinding.

### WR-02: WARNING - Test uses `Process.sleep/1` for synchronization

**File:** `test/foglet_bbs/tui/screens/sysop_test.exs:1197`
**Issue:** The project instructions explicitly say to avoid `Process.sleep/1` in tests. This test sleeps for 5 ms to make uptime advance, which is timing-dependent and can still be flaky under scheduler jitter or low timer resolution.
**Fix:** Avoid sleeping and assert the refresh behavior through controlled data or structural change. For example, inject a snapshot clock into `SystemSnapshot.init/1`/refresh in tests, or assert that refresh returns a valid snapshot and preserves monotonic non-regression without requiring wall-clock advancement.

### WR-03: WARNING - Dialyzer ignores now mask warnings in the reviewed implementation files

**File:** `.dialyzer_ignore.exs:45`
**Issue:** The ignore file adds broad file/type suppressions for Phase 25 conversion files, including `:pattern_match`, `:guard_fail`, and `:pattern_match_cov` for the Account form and SSH key state modules. These entries suppress any warning of that type in the entire file, so future real regressions in the same files will pass precommit. This also conflicts with the comment at lines 5-7 that the baseline should fail on new warnings and be removed when touching a file.
**Fix:** Fix or narrowly suppress the underlying warnings instead of ignoring whole warning classes per file. If an ignore is unavoidable, include the smallest supported match that pins the exact warning text/location, and remove the file-wide entries for touched Phase 25 modules.

---

_Reviewed: 2026-04-26T12:49:37Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
