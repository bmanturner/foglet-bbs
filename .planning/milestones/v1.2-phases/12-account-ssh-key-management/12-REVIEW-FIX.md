---
phase: 12-account-ssh-key-management
fixed_at: 2026-04-24T20:18:00Z
status: all_fixed
findings_in_scope: 1
fixed: 1
skipped: 0
iteration: 1
fix_scope: critical_warning
---

# Phase 12: Code Review Fix Report

## Summary

Fixed CR-01: public-key login no longer bypasses account status and verification gates.

## Fixes Applied

### CR-01: Public-key login bypasses account status and verification gates

**Status:** Fixed

Changes:

- `Foglet.Accounts.get_user_by_public_key/1` now only matches registered keys whose owner is not deleted and has `status == :active`.
- `Foglet.TUI.App.init/1` now uses `Accounts.post_login_screen/1` for authenticated startup instead of always routing non-nil users to `:main_menu`.
- Added a focused account test proving pending, suspended, and rejected public-key owners return `{:error, :not_found}` without updating `last_used_at`.
- Added a focused TUI app test proving an unconfirmed pubkey-authenticated user routes to `:verify` when email verification is required.

## Verification

Passed:

```bash
rtk mix test test/foglet_bbs/accounts/accounts_test.exs:707 test/foglet_bbs/tui/app_test.exs:64
```

Known non-fix failure during broader verification:

```bash
rtk mix test test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/tui/app_test.exs
```

This broader run produced 3 pre-existing `DBConnection.OwnershipError` failures in `Foglet.TUI.AppTest` `App.view/1` cases that render login/config paths under async sandbox ownership. The new focused tests passed.
