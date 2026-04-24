---
phase: 13-board-subscription-management
reviewed: 2026-04-24T21:17:59Z
depth: standard
files_reviewed: 17
files_reviewed_list:
  - docs/DATA_MODEL.md
  - lib/foglet_bbs/boards.ex
  - lib/foglet_bbs/boards/board.ex
  - lib/foglet_bbs/tui/app.ex
  - lib/foglet_bbs/tui/screens/board_list.ex
  - lib/foglet_bbs/tui/screens/board_list/state.ex
  - lib/foglet_bbs/tui/screens/new_thread.ex
  - lib/foglet_bbs/tui/screens/new_thread/state.ex
  - lib/foglet_bbs/tui/screens/sysop/boards_view.ex
  - lib/mix/tasks/foglet.board_subscriptions.ex
  - priv/repo/migrations/20260424130100_add_required_subscription_to_boards.exs
  - priv/repo/seeds.exs
  - test/foglet_bbs/boards/boards_test.exs
  - test/foglet_bbs/tui/screens/board_list_test.exs
  - test/foglet_bbs/tui/screens/new_thread_test.exs
  - test/foglet_bbs/tui/screens/sysop_test.exs
  - test/mix/tasks/foglet.board_subscriptions_test.exs
findings:
  critical: 0
  warning: 2
  info: 0
  total: 2
status: issues_found
---

# Phase 13: Code Review Report

**Reviewed:** 2026-04-24T21:17:59Z
**Depth:** standard
**Files Reviewed:** 17
**Status:** issues_found

## Summary

Reviewed the Phase 13 board subscription management changes across domain, schema, migration, TUI screens, Mix task, seeds, and focused tests. The core context APIs are mostly well-scoped, but two behavior gaps can leave users with incorrect subscription state in the terminal UI or allow "required" boards to remain absent from existing users' subscriptions.

## Warnings

### WR-01: Board Directory Tree Keeps Stale Subscription Data After Reload

**File:** `lib/foglet_bbs/tui/app.ex:418`
**Issue:** `{:boards_loaded, boards}` only updates `state.board_list`. `BoardList.render/1` prefers the existing `screen_state[:board_list].tree` over rebuilding from the refreshed directory (`lib/foglet_bbs/tui/screens/board_list.ex:62`), and subscribe/unsubscribe handlers read focused board metadata from that same tree. After a successful subscription change, the app reloads the directory at `lib/foglet_bbs/tui/app.ex:455-457`, but the visible labels and focused node data can still say `[unsubscribed]` or `[subscribed]`. Users can then see stale status and dispatch the wrong next action until the screen state is recreated.
**Fix:** Rebuild or clear the BoardList tree whenever fresh board data is loaded. For example:

```elixir
defp do_update({:boards_loaded, boards}, state) do
  screen_state =
    case Map.get(state.screen_state || %{}, :board_list) do
      %Screens.BoardList.State{} = ss ->
        Map.put(state.screen_state || %{}, :board_list, %{ss | tree: nil})

      _ ->
        state.screen_state || %{}
    end

  {%{state | board_list: boards, screen_state: screen_state}, []}
end
```

Alternatively expose a BoardList helper that rebuilds the tree from the refreshed directory while preserving the cursor when possible.

### WR-02: Marking A Board Required Does Not Ensure Existing Users Are Subscribed

**File:** `lib/foglet_bbs/boards.ex:166`
**Issue:** `update_board/3` can set `required_subscription: true` through the normal board changeset, but it only updates the board row. Existing users who were not subscribed before the flag change remain unsubscribed, even though the board is now displayed and enforced as a required subscription. New users get default subscriptions through `subscribe_to_defaults/1`, and `unsubscribe_user_from_board/2` blocks future removals, but there is no backfill or transactional invariant for current users when the required flag is enabled.
**Fix:** Route required-subscription transitions through a context function that updates the board and inserts missing `board_subscriptions` rows in one transaction. For example:

```elixir
def update_board(actor, %Board{} = board, attrs) do
  with :ok <- Bodyguard.permit(Foglet.Authorization, :update_board, actor, :site) do
    Repo.transact(fn ->
      {:ok, updated} =
        board
        |> Board.changeset(attrs)
        |> Repo.update()

      if updated.required_subscription do
        subscribe_all_users_to_board(updated.id)
      end

      {:ok, updated}
    end)
  end
end
```

The helper should insert only missing rows with `on_conflict: :nothing`, and tests should cover toggling an existing board from optional to required with pre-existing unsubscribed users.

---

_Reviewed: 2026-04-24T21:17:59Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
