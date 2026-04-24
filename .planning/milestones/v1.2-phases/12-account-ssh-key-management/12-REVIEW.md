---
phase: 12-account-ssh-key-management
reviewed: 2026-04-24T17:51:19Z
depth: standard
files_reviewed: 12
files_reviewed_list:
  - lib/foglet_bbs/accounts.ex
  - lib/foglet_bbs/accounts/ssh_key.ex
  - lib/foglet_bbs/ssh/cli_handler.ex
  - lib/foglet_bbs/tui/screens/account.ex
  - lib/foglet_bbs/tui/screens/account/state.ex
  - lib/foglet_bbs/tui/screens/account/ssh_keys_actions.ex
  - lib/foglet_bbs/tui/screens/account/ssh_keys_state.ex
  - lib/foglet_bbs/tui/screens/account/ssh_keys_surface.ex
  - test/foglet_bbs/accounts/accounts_test.exs
  - test/foglet_bbs/accounts/ssh_key_test.exs
  - test/foglet_bbs/ssh/cli_handler_test.exs
  - test/foglet_bbs/tui/screens/account_test.exs
findings:
  critical: 1
  warning: 0
  info: 0
  total: 1
status: issues_found
---

# Phase 12: Code Review Report

**Reviewed:** 2026-04-24T17:51:19Z
**Depth:** standard
**Files Reviewed:** 12
**Status:** issues_found

## Summary

Reviewed the Phase 12 SSH key management domain, SSH channel integration, Account TUI state/actions/surface, and related tests. The self-service key list/add/revoke paths are generally ownership-scoped through `Foglet.Accounts`, and the TUI avoids rendering raw public-key material in the list.

One critical authorization regression remains: public-key authentication accepts any non-deleted owner and `CLIHandler` starts an authenticated TUI session directly at `:main_menu`, bypassing the password-login gates for account status and email verification.

## Critical Issues

### CR-01: Public-key login bypasses account status and verification gates

**File:** `lib/foglet_bbs/accounts.ex:732`
**Issue:** `authenticate_by_public_key/1` accepts any key whose owner is not deleted because `get_active_ssh_key_and_user/1` only filters on `is_nil(u.deleted_at)` at lines 749-755. `CLIHandler` then treats a successful match as authenticated at `lib/foglet_bbs/ssh/cli_handler.ex:315-317`, and `Foglet.TUI.App.init/1` routes any non-nil user straight to `:main_menu`. This bypasses the password-login checks that block `:pending` and `:suspended` users and that call `Accounts.post_login_screen/1` for unconfirmed users. A pending, suspended, rejected, or unverified account with a registered key can therefore skip the intended login/verification flow.

**Fix:**
Require the same eligibility rules in the public-key path before updating `last_used_at`, and add tests for pending, suspended, rejected, and unconfirmed owners.

```elixir
defp get_active_ssh_key_and_user(fingerprint) do
  Repo.one(
    from k in SSHKey,
      where: k.fingerprint == ^fingerprint,
      join: u in assoc(k, :user),
      where: is_nil(u.deleted_at) and u.status == :active,
      select: {k, u}
  )
end
```

Then make `CLIHandler` or `App.init/1` route unconfirmed public-key users through `Accounts.post_login_screen/1` instead of always starting at `:main_menu`, for example by building session context with the intended initial screen or by having `App.init/1` call the same post-login routing for authenticated users.

Add focused tests such as:

```elixir
test "public-key auth rejects inactive account statuses without last_used_at writes" do
  for status <- [:pending, :suspended, :rejected] do
    user = user_with_status(status, "pubkey_#{status}")
    key = AccountsFixtures.ssh_key_fixture(user)

    assert {:error, :not_found} =
             Accounts.authenticate_by_public_key(key.public_key)

    assert %SSHKey{last_used_at: nil} = Repo.get(SSHKey, key.id)
  end
end

test "pubkey-authenticated unconfirmed users do not start at main_menu when verification is required" do
  Foglet.Config.put!("require_email_verification", true)
  user = AccountsFixtures.user_fixture()

  {:ok, state} =
    Foglet.TUI.App.init(%{
      session_context: %{user: user, user_id: user.id, pubkey_authenticated: true},
      terminal_size: {80, 24}
    })

  assert state.current_screen == :verify
end
```

---

_Reviewed: 2026-04-24T17:51:19Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
