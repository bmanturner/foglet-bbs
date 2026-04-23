---
phase: 01-authorization-and-scope-backbone
reviewed: 2026-04-23T00:00:00Z
depth: standard
files_reviewed: 15
files_reviewed_list:
  - lib/foglet_bbs/authorization.ex
  - lib/foglet_bbs/boards.ex
  - lib/foglet_bbs/boards/board.ex
  - lib/foglet_bbs/config.ex
  - lib/foglet_bbs/posts.ex
  - lib/foglet_bbs/threads.ex
  - mix.exs
  - mix.lock
  - test/foglet_bbs/authorization_test.exs
  - test/foglet_bbs/authorization/bodyguard_passthrough_test.exs
  - test/foglet_bbs/boards/boards_test.exs
  - test/foglet_bbs/config_test.exs
  - test/foglet_bbs/posts/posts_test.exs
  - test/foglet_bbs/threads/threads_test.exs
  - test/support/boards_fixtures.ex
findings:
  critical: 0
  warning: 4
  info: 3
  total: 7
status: issues_found
---

# Phase 01: Code Review Report

**Reviewed:** 2026-04-23
**Depth:** standard
**Files Reviewed:** 15
**Status:** issues_found

## Summary

This phase introduces the authorization policy (`Foglet.Authorization` / Bodyguard), actor-aware writes to `Foglet.Config`, scope helpers on `Foglet.Boards`, `Foglet.Threads`, and `Foglet.Posts`, and supporting test infrastructure. The overall structure is solid: the policy matrix is well-modeled, the safe-default-deny clause is correct, and the `scopes_for/2` API boundary is cleanly frozen for Phase 8.

Four warnings require attention before this phase can be called complete. None are security issues. The most consequential is the `mix.lock` vs `mix.exs` path/hex mismatch for raxol, which will cause CI breakage for anyone running `mix deps.get` fresh. The `Board.changeset/2` category_id mutability and `Foglet.Config.put/3` exception escape are correctness concerns in the runtime path.

---

## Warnings

### WR-01: `mix.lock` resolves `:raxol` from Hex but `mix.exs` declares a local path dep

**File:** `mix.exs:64` / `mix.lock:47`

**Issue:** `mix.exs` declares `{:raxol, path: "vendor/raxol"}`, meaning Mix should resolve it from the local `vendor/raxol` directory. However, `mix.lock` records raxol as a Hex package (`{:hex, :raxol, "2.4.0", ...}`). These are inconsistent: a fresh `mix deps.get` on a clean checkout will either fail with a lock conflict or silently use the wrong source. If `vendor/raxol` contains local patches, those patches will be silently ignored in any environment that uses the lock file without the local vendor tree.

**Fix:** Either (a) remove the `mix.lock` entry for raxol and re-lock so it resolves from the path, or (b) change `mix.exs` to `{:raxol, "~> 2.4"}` if the vendored path is no longer needed. Run `mix deps.get` after either change to verify the lock is consistent.

---

### WR-02: `Board.changeset/2` casts `:category_id`, allowing category reassignment through `update_board/3`

**File:** `lib/foglet_bbs/boards/board.ex:30-41`

**Issue:** `:category_id` appears in the `cast/3` list for the general `changeset/2`. This changeset is used for both creation (`create_board/3`) and updates (`update_board/3`). A caller invoking `update_board(sysop, board, %{category_id: other_id})` can silently move a board to a different category. This is almost certainly unintentional — `category_id` is a creation-time structural decision, not an attribute that should be freely mutable through the standard update path.

**Fix:** Introduce a `create_changeset/2` that includes `:category_id` in its cast list, and a separate `update_changeset/2` that does not. Use `create_changeset` in `create_board/3` and `update_changeset` in `update_board/3`.

```elixir
# In Board module:
@create_fields [:slug, :name, :description, :display_order,
                :readable_by, :postable_by, :archived,
                :default_subscription, :category_id]

@update_fields [:slug, :name, :description, :display_order,
                :readable_by, :postable_by, :archived,
                :default_subscription]

def create_changeset(board, attrs) do
  board
  |> cast(attrs, @create_fields)
  |> validate_required([:slug, :name, :category_id])
  |> validate_slug()
  |> validate_length(:name, min: 1, max: 100)
  |> unique_constraint(:slug)
  |> foreign_key_constraint(:category_id)
end

def update_changeset(board, attrs) do
  board
  |> cast(attrs, @update_fields)
  |> validate_required([:slug, :name])
  |> validate_slug()
  |> validate_length(:name, min: 1, max: 100)
  |> unique_constraint(:slug)
end
```

---

### WR-03: `Foglet.Config.put/3` spec promises tagged tuples but a DB exception can escape

**File:** `lib/foglet_bbs/config.ex:138-156`

**Issue:** The `@spec` for `put/3` declares `{:ok, Entry.t()} | {:error, :forbidden} | {:error, :unknown_key} | {:error, :invalid_value}`. However, `do_put!/3` (called on the success path at line 147) uses `Repo.insert!/1` and `Repo.update!/1` — both raise on DB failure. An unexpected Postgres error (constraint violation, connection loss) will propagate as an uncaught exception rather than returning `{:error, _}`. This breaks the contract promised to interactive callers (TUI sysop screen) and makes the calling code harder to write defensively.

**Fix:** Wrap the `do_put!` call inside `put/3` in a `try/rescue`:

```elixir
def put(actor, key, value) when is_binary(key) do
  with :ok <- Bodyguard.permit(Foglet.Authorization, :edit_config, actor, :site) do
    case Schema.validate(key, value) do
      :ok ->
        try do
          {:ok, do_put!(key, value, actor && actor.id)}
        rescue
          e in [Ecto.InvalidChangesetError, Postgrex.Error, DBConnection.ConnectionError] ->
            require Logger
            Logger.error("Config.put/3 DB failure for key #{inspect(key)}: #{inspect(e)}")
            {:error, :db_error}
        end

      {:error, {:unknown_key, ^key}} ->
        {:error, :unknown_key}

      {:error, %{reason: _reason}} ->
        {:error, :invalid_value}
    end
  end
end
```

Alternatively, refactor `do_put!` to return a tagged tuple and use `Repo.insert/1` / `Repo.update/1` internally, reserving the bang variants for the trusted `put!/3` path.

---

### WR-04: `move_thread/2` discards the `update_all` return value — zero-update case is silent

**File:** `lib/foglet_bbs/threads.ex:195-208`

**Issue:** After updating the thread's `board_id`, `Repo.update_all/2` is called to relocate all posts. Its return value (`{count, nil}`) is discarded. If `count` is 0 — which should not happen for a thread with posts — the operation succeeds silently with the thread in the new board but its posts still pointing to the old board. The foreign key on `posts.board_id` does not constrain against this since both boards exist.

**Fix:** Assert on the returned count or check it:

```elixir
with {:ok, updated_thread} <-
       thread
       |> Ecto.Changeset.change(%{board_id: new_board_id})
       |> Repo.update() do
  {_count, nil} =
    Repo.update_all(
      from(p in Post, where: p.thread_id == ^thread.id),
      set: [board_id: new_board_id]
    )

  {:ok, updated_thread}
end
```

The `{_count, nil} =` pattern match will raise `MatchError` if `update_all` returns something unexpected, surfacing the problem during development. For production you may also want to `Repo.rollback({:error, :posts_not_moved})` if `count == 0 and thread.post_count > 0`.

---

## Info

### IN-01: `require Logger` inside a function body

**File:** `lib/foglet_bbs/authorization.ex:95`

**Issue:** `require Logger` is called inside the `authorize/3` function clause for unknown actions. While this works, it is an unusual pattern; the macro expansion runs every time the clause matches. The conventional Elixir idiom is to `require Logger` at module level so it is compiled once.

**Fix:** Move `require Logger` to the module body, alongside the other module-level attributes (after line 21):

```elixir
require Logger
```

Then remove the inline `require Logger` at line 95.

---

### IN-02: Test matrix for `authorization_test.exs` has no coverage of sysop at board-scoped lifecycle actions

**File:** `test/foglet_bbs/authorization_test.exs:25-76`

**Issue:** The matrix tests sysop at `:site` scope for all board lifecycle actions (`:create_board`, `:archive_board`, etc.) and at `{:board, @board_id}` scope for thread/post actions. It does not test that sysop is also permitted for board-lifecycle actions at `{:board, _}` scope. The policy passes sysop for any scope (line 105 of `authorization.ex`), so the behavior is correct, but the coverage gap means a future regression (e.g., accidentally adding a board scope guard before the sysop clause) would not be caught.

**Fix:** Add a few matrix entries:

```elixir
{:sysop, :create_board, {:board, @board_id}, :ok},
{:sysop, :edit_config, {:board, @board_id}, :ok},
```

---

### IN-03: `board_fixture/2` silently ignores `allow_board_server!` requirement in tests that call it without the server

**File:** `test/support/boards_fixtures.ex:27-46`

**Issue:** `board_fixture/2` calls `Foglet.Boards.create_board/3`, which starts a Board Server. Tests using `board_fixture` inside `async: true` or without sandbox-allowing the Board Server's PID will hit sandbox ownership errors when the server tries to use the Repo. The current pattern (each test manually calling `allow_board_server!`) is correct but fragile — it's easy to add a new test using `board_fixture` and forget the allow step.

The fixture itself is not broken, but there is no guard or documentation directing callers to call `allow_board_server!` after creating a board via the fixture if they intend to use the Board Server.

**Fix:** Add a doc note to `board_fixture/2` reminding callers of the requirement:

```elixir
@doc """
Create a board in a category via `Foglet.Boards.create_board/3`.
Starts a Board Server automatically.

IMPORTANT: If the test will use the Board Server (thread/post creation),
call `allow_board_server!(board.id)` after this fixture to grant sandbox
access to the server process.
"""
```

---

_Reviewed: 2026-04-23_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
