---
phase: 10-user-status-administration
reviewed: 2026-04-24T18:17:36Z
depth: standard
files_reviewed: 19
files_reviewed_list:
  - docs/DATA_MODEL.md
  - lib/foglet_bbs/accounts.ex
  - lib/foglet_bbs/accounts/email.ex
  - lib/foglet_bbs/accounts/user.ex
  - lib/foglet_bbs/authorization.ex
  - lib/foglet_bbs/tui/screens/login.ex
  - lib/foglet_bbs/tui/screens/register.ex
  - lib/foglet_bbs/tui/screens/sysop.ex
  - lib/foglet_bbs/tui/screens/sysop/state.ex
  - lib/foglet_bbs/tui/screens/sysop/users_view.ex
  - lib/mix/tasks/foglet.user.status.ex
  - priv/repo/migrations/20260424000000_add_rejected_user_status.exs
  - test/foglet_bbs/accounts/accounts_test.exs
  - test/foglet_bbs/accounts/user_status_test.exs
  - test/foglet_bbs/authorization_test.exs
  - test/foglet_bbs/tui/screens/login_test.exs
  - test/foglet_bbs/tui/screens/register_test.exs
  - test/foglet_bbs/tui/screens/sysop_test.exs
  - test/mix/tasks/foglet_user_status_test.exs
findings:
  critical: 0
  warning: 1
  info: 0
  total: 1
status: issues_found
---

# Phase 10: Code Review Report

**Reviewed:** 2026-04-24T18:17:36Z
**Depth:** standard
**Files Reviewed:** 19
**Status:** issues_found

## Summary

Reviewed the user status administration changes across Accounts, Authorization, TUI login/register/sysop flows, the Mix task, migration, and focused tests. The status transition graph is centralized in `Foglet.Accounts`, authorization is checked at the domain boundary, and rejected users are consistently blocked from login and operator scopes.

One issue remains: the USERS tab can mutate the status of the currently logged-in sysop while continuing to use the stale active `current_user` struct for later authorization checks in that same session.

## Warnings

### WR-01: Self-Suspension Leaves The Active Session Authorized With Stale User State

**File:** `lib/foglet_bbs/accounts.ex:303`
**Issue:** `list_user_status_admin_targets/1` returns every non-deleted user, including the actor, and `transition_user_status/3` allows `:active -> :suspended` without a self-target guard. From the TUI, `UsersView.transition/2` then calls the transition with `state.current_user` and refreshes only the UsersView rows (`lib/foglet_bbs/tui/screens/sysop/users_view.ex:114-121`). It does not update or demote the application-level `current_user`. If a sysop suspends their own account from the USERS tab, the persisted row becomes suspended, but the current SSH session still holds an active sysop struct and can continue passing `Bodyguard.permit/4` in the same session. That makes status-based authorization enforcement inconsistent.

**Fix:** Prevent self-status changes at the Accounts boundary, or return a session-level event that forces logout/reload when the target id matches the actor id. The narrower fix is to reject self-targeted status transitions:

```elixir
def transition_user_status(actor, target, target_status) do
  with :ok <- Bodyguard.permit(Foglet.Authorization, :manage_user_status, actor, :site),
       {:ok, status} <- normalize_status(target_status),
       {:ok, user} <- fetch_status_target(target),
       :ok <- ensure_not_self(actor, user),
       :ok <- ensure_not_deleted(user),
       :ok <- permit_status_transition(user.status, status),
       {:ok, updated} <- user |> User.status_changeset(%{status: status}) |> Repo.update() do
    ...
  end
end

defp ensure_not_self(%User{id: actor_id}, %User{id: actor_id}), do: {:error, :invalid_transition}
defp ensure_not_self(_actor, _user), do: :ok
```

Add coverage that a sysop cannot suspend/reactivate their own row through `Accounts.transition_user_status/3` and, if self-targeting should remain allowed, update the TUI command contract so the current session is terminated or reloaded immediately.

---

_Reviewed: 2026-04-24T18:17:36Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
