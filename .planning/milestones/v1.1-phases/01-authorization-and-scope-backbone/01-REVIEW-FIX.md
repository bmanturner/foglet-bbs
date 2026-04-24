---
phase: 01-authorization-and-scope-backbone
fixed_at: 2026-04-23T00:00:00Z
review_path: .planning/phases/01-authorization-and-scope-backbone/01-REVIEW.md
iteration: 1
findings_in_scope: 7
fixed: 6
skipped: 1
status: partial
---

# Phase 01: Code Review Fix Report

**Fixed at:** 2026-04-23
**Source review:** `.planning/phases/01-authorization-and-scope-backbone/01-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 7 (4 warnings, 3 info)
- Fixed: 6 (3 warnings, 3 info)
- Skipped: 1 (WR-02, intentional design)

**Verification:**
- `mix compile --warnings-as-errors` passes for `foglet_bbs` (pre-existing upstream warnings in vendored raxol are unchanged and unrelated).
- `mix precommit` passes: compile clean, credo `--strict` no issues, sobelow clean, dialyzer clean (78 skips, all pre-existing entries in `.dialyzer_ignore.exs`).
- Full test suite: **1040 tests, 1 property, 0 failures**.

## Fixed Issues

### WR-01: stale `raxol` hex entry in `mix.lock`

**Files modified:** `mix.lock`
**Commit:** `6d3b8c6`
**Applied fix:** Removed the stale `"raxol": {:hex, :raxol, "2.4.0", ...}` line from `mix.lock`. Confirmed via `mix deps` that `raxol` itself correctly resolves from `vendor/raxol` (the path dep in `mix.exs`). The `raxol_core`, `raxol_liveview`, `raxol_mcp`, `raxol_plugin`, `raxol_sensor`, and `raxol_terminal` hex entries were preserved because those are legitimate transitive Hex dependencies declared by `vendor/raxol/mix.exs`. `mix deps.get` now runs cleanly with no source-of-truth ambiguity.

### WR-03: `Foglet.Config.put/3` spec vs. exception escape

**Files modified:** `lib/foglet_bbs/config.ex`
**Commit:** `cb2c671`
**Applied fix:** Wrapped the `do_put!/3` call inside the `:ok` validation branch of `put/3` in a `try/rescue` that catches `Ecto.InvalidChangesetError`, `Postgrex.Error`, and `DBConnection.ConnectionError`. On failure the clause logs at `:error` level and returns `{:error, :db_error}`. Also extended the `@spec` to include `{:error, :db_error}`. `put!/3` (the trusted, raising variant) is unchanged.

### WR-04: `move_thread/2` silently discarded `update_all` return

**Files modified:** `lib/foglet_bbs/threads.ex`
**Commit:** `5ceb595`
**Applied fix:** Bound `Repo.update_all/2`'s return to `{_count, nil}` so an unexpected return shape now surfaces as a `MatchError` inside the transaction (which Ecto converts to a rollback). Did not add the richer `count == 0 and post_count > 0` rollback variant — the review called that a "you may also want to" suggestion; keeping the change small matches the reviewer's primary recommendation.

### IN-01: `require Logger` inside `authorize/3` function body

**Files modified:** `lib/foglet_bbs/authorization.ex`
**Commit:** `358cb7f`
**Applied fix:** Added `require Logger` at module level just under `@behaviour Bodyguard.Policy`; removed the inline `require Logger` from the unknown-action clause. The `Logger.warning/1` call continues to work from the function body.

### IN-02: sysop × board-scoped lifecycle actions not covered in matrix

**Files modified:** `test/foglet_bbs/authorization_test.exs`
**Commit:** `93c3a76`
**Applied fix:** Added two matrix entries — `{:sysop, :create_board, {:board, @board_id}, :ok}` and `{:sysop, :edit_config, {:board, @board_id}, :ok}` — with a comment explaining the regression-guard intent. Test count for the matrix suite went from 54 to 56; both new tests pass.

### IN-03: `board_fixture/2` missing doc note about `allow_board_server!`

**Files modified:** `test/support/boards_fixtures.ex`
**Commit:** `ac5de22`
**Applied fix:** Appended an `IMPORTANT:` paragraph to the `@doc` on `board_fixture/2` explaining that callers who will drive the Board Server must call `allow_board_server!(board.id)` afterward. Docstring-only; no behavior change.

## Skipped Issues

### WR-02: `Board.changeset/2` casts `:category_id`

**File:** `lib/foglet_bbs/boards/board.ex:30-41`
**Reason:** Skipped — intentional design. Boards can be reorganized to different categories as the community grows; `:category_id` mutability through `update_board/3` is a deliberate product decision, not an oversight. Per explicit user instruction, the create/update changeset split proposed by the reviewer was not applied.
**Original issue:** Reviewer argued that `:category_id` appears in the `cast/3` list for the general `changeset/2`, which is used by both `create_board/3` and `update_board/3`, letting callers silently reassign a board to a different category. The reviewer proposed splitting into `create_changeset/2` (with `:category_id`) and `update_changeset/2` (without). This is working as intended for this codebase.

---

_Fixed: 2026-04-23_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
