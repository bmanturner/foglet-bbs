---
phase: 02-sysop-config-and-board-management
fixed_at: 2026-04-23T00:00:00Z
review_path: .planning/phases/02-sysop-config-and-board-management/02-REVIEW.md
iteration: 1
findings_in_scope: 8
fixed: 8
skipped: 0
status: all_fixed
---

# Phase 02: Code Review Fix Report

**Fixed at:** 2026-04-23
**Source review:** `.planning/phases/02-sysop-config-and-board-management/02-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 8 (3 warnings + 5 info, fix_scope=all)
- Fixed: 8
- Skipped: 0

All fixes passed `mix precommit` (compile --warnings-as-errors, format, credo --strict, sobelow, dialyzer).

## Fixed Issues

### WR-01: `create_board/3` silently downgrades Board Server start failures

**Files modified:** `lib/foglet_bbs/boards.ex`
**Commit:** 13e2d15
**Applied fix:** Switched to Option 2 from the review. On `BoardSupervisor.start_board/1` failure (other than `:already_started`), the just-inserted board row is now deleted via `Repo.delete/1` and the function returns `{:error, :board_server_unavailable}`. The caller (`BoardsView.dispatch_submit/3`) falls into the `{:error, _}` branch, which surfaces an error modal via the existing generic-error path. Also hoisted `require Logger` to the top of the module (partial IN-05) since the inline require was removed.

### WR-02: `handle_confirm_event/2` non-exhaustive case

**Files modified:** `lib/foglet_bbs/tui/screens/sysop/boards_view.ex`
**Commit:** 82027ed
**Applied fix:** Added a fallthrough `other ->` clause that logs the unexpected `modal_kind` at `Logger.error` and returns `{:error, :unknown_confirm_kind}`. The existing `{:error, _}` catch-all in the result handler surfaces this via an error modal instead of crashing the TUI session.

### WR-03: `subscribe_to_defaults/1` swallows subscription errors at warning level

**Files modified:** `lib/foglet_bbs/boards.ex`
**Commit:** 39decf9
**Applied fix:** Raised the log level from `Logger.warning` to `Logger.error` so registration-time subscription failures reach alerting. Removed the inline `require Logger` since it was hoisted to the module top in the WR-01 commit (completes IN-05 for this module).

### IN-01: Dead `_ = kind` binding

**Files modified:** `lib/foglet_bbs/tui/screens/sysop/boards_view.ex`
**Commit:** 4a8906c
**Applied fix:** Deleted the `_ = kind` line in the `:forbidden` branch. Compiled with `--warnings-as-errors` and saw no new warnings — `kind` is still used upstream in `dispatch_submit(kind, ...)`.

### IN-02: Redundant `Map.pop` / `Map.get` in edit-board dispatch

**Files modified:** `lib/foglet_bbs/tui/screens/sysop/boards_view.ex`
**Commit:** ef81264
**Applied fix:** Dropped the no-op pop/put and now pass `normalize_board_attrs(payload)` directly to `Boards.update_board/3`. Updated the inline comment to explicitly note that `normalize_board_attrs/1` only touches `:postable_by`, so `:category_id` survives untouched.

### IN-03: Enum prefix-match ordering dependency

**Files modified:** `lib/foglet_bbs/tui/screens/sysop/site_form.ex`
**Commit:** 6c976c1
**Applied fix:** Added an "Enum entry ordering" section to the moduledoc documenting that `apply_char/2` picks the first enum value whose name starts with the typed character, making Schema enum order load-bearing. Guidance: prefer disjoint leading characters, or list shorter/more-common values first.

### IN-04: `apply_submodule_result` only surfaces first `:error_modal`

**Files modified:** `lib/foglet_bbs/tui/screens/sysop.ex`
**Commit:** 4ca7cee
**Applied fix:** Added a comment above `apply_submodule_result/6` documenting the submodule contract: at most one `:error_modal` per `handle_key/2` return, additional ones are silently dropped, combine at the submodule boundary if needed.

### IN-05: `require Logger` inside function bodies

**Files modified:** `lib/foglet_bbs/boards.ex` (via WR-01 + WR-03 commits), `lib/foglet_bbs/config.ex`
**Commit:** 30c5b4a (config.ex); boards.ex portion folded into 13e2d15 and 39decf9
**Applied fix:** Hoisted `require Logger` to module top in both `Foglet.Boards` and `Foglet.Config`, and removed the three per-clause inline requires. The boards.ex changes were made as part of the WR-01 and WR-03 commits to avoid a broken intermediate state (removing the inline require requires the top-level require to be present). The config.ex change is a standalone commit for this finding.

## Skipped Issues

None.

---

_Fixed: 2026-04-23_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
