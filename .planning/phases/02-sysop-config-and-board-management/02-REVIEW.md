---
phase: 02-sysop-config-and-board-management
reviewed: 2026-04-23T00:00:00Z
depth: standard
files_reviewed: 12
files_reviewed_list:
  - lib/foglet_bbs/boards.ex
  - lib/foglet_bbs/boards/category.ex
  - lib/foglet_bbs/config.ex
  - lib/foglet_bbs/config/schema.ex
  - lib/foglet_bbs/tui/screens/sysop.ex
  - lib/foglet_bbs/tui/screens/sysop/boards_view.ex
  - lib/foglet_bbs/tui/screens/sysop/limits_form.ex
  - lib/foglet_bbs/tui/screens/sysop/site_form.ex
  - lib/foglet_bbs/tui/screens/sysop/state.ex
  - test/foglet_bbs/boards/boards_test.exs
  - test/foglet_bbs/config_test.exs
  - test/foglet_bbs/tui/screens/sysop_test.exs
findings:
  critical: 0
  warning: 3
  info: 5
  total: 8
status: issues_found
---

# Phase 02: Code Review Report

**Reviewed:** 2026-04-23
**Depth:** standard
**Files Reviewed:** 12
**Status:** issues_found

## Summary

Phase 02 delivers the sysop configuration and board-management surface: typed
config schema + ETS cache, actor-aware `Foglet.Boards` CRUD, and three Sysop
TUI submodules (SITE, LIMITS, BOARDS). The code is well-documented, authorization
is consistently funnelled through `Bodyguard.permit/4`, and validation is
centralised in `Foglet.Config.Schema`. Tests are thorough for the domain layer
(auth matrices, monotonic pointer, idempotent subscribe, schema error shapes).

No critical or security issues. Findings below are largely robustness concerns
(silent failure modes, non-exhaustive case clauses) and minor code-quality
nits. Nothing blocks the phase.

## Warnings

### WR-01: `create_board/3` silently downgrades Board Server start failures to success

**File:** `lib/foglet_bbs/boards.ex:133-142`
**Issue:** When `BoardSupervisor.start_board/1` returns `{:error, reason}` for
any reason other than `:already_started`, the code logs an error but still
returns `{:ok, board}` to the caller. The board row is inserted but its server
is not running — callers (including the TUI's `BoardsView.dispatch_submit/3`)
treat this as a complete success, refresh the list, and close the modal. The
user has no signal that writes to that board will fail until they attempt one.
The log message acknowledges this ("a future application restart will start its
server"), but "restart the app" is not a recoverable UX for a sysop action.
**Fix:** Consider one of:
1. Return a distinct success-with-warning tuple and surface it in the TUI
   (e.g. an info toast), or
2. Delete the just-inserted board row on start failure and return
   `{:error, :board_server_unavailable}`, or
3. At minimum, emit a telemetry event so this condition is observable without
   tailing logs.
```elixir
{:error, reason} ->
  require Logger
  Logger.error("Failed to start Board Server for #{board.slug} ...")
  # Option 2 — fail loud:
  Repo.delete(board)
  {:error, :board_server_unavailable}
```

### WR-02: `handle_confirm_event/2` has a non-exhaustive `case` on `modal_kind`

**File:** `lib/foglet_bbs/tui/screens/sysop/boards_view.ex:563-567`
**Issue:** The Y-confirm handler matches only `:archive_board` and
`:archive_category`:
```elixir
result =
  case kind do
    :archive_board -> Boards.archive_board(state.current_user, target)
    :archive_category -> Boards.archive_category(state.current_user, target)
  end
```
If `modal_kind` is ever anything else while a `%Modal{type: :confirm}` is
active (today impossible, but defensively: any future confirm flow —
unsubscribe-all, purge, etc. — that forgets to add a clause), this raises
`CaseClauseError` and crashes the TUI session. The confirm-modal branch is
only gated on `%Modal{type: :confirm}`, not on `modal_kind`, so the coupling
is implicit.
**Fix:** Add a fallthrough that resets the modal and surfaces an error, or
assert the invariant:
```elixir
result =
  case kind do
    :archive_board -> Boards.archive_board(state.current_user, target)
    :archive_category -> Boards.archive_category(state.current_user, target)
    other ->
      require Logger
      Logger.error("BoardsView confirm: unexpected modal_kind #{inspect(other)}")
      {:error, :unknown_confirm_kind}
  end
```

### WR-03: `subscribe_to_defaults/1` logs but swallows subscription errors

**File:** `lib/foglet_bbs/boards.ex:215-232`
**Issue:** Called from `Foglet.Accounts.create_user/1` (per the moduledoc).
If the insert returns `{:error, changeset}` for reasons other than conflict
(e.g., FK violation because the user row was concurrently hard-deleted, or a
new NOT NULL column added to `subscriptions`), the error is logged at
`:warning` and iteration continues. The caller sees `:ok` regardless. For
account-creation flow this means a new user can exist without their default
subscriptions, and no code path will ever retry. This is consistent with
"best-effort post-registration" semantics, but the log level understates the
impact — a user with zero default subscriptions after registration is a
data-integrity issue for a BBS, not a warning.
**Fix:** At minimum raise the log to `:error` so it reaches alerting, and
consider returning `{:ok, :all}` vs `{:ok, {:partial, failed_ids}}` so the
caller can decide policy:
```elixir
Logger.error(
  "subscribe_to_defaults: failed to subscribe #{user_id} to #{board_id}: ..."
)
```

## Info

### IN-01: Dead binding `_ = kind` in `:forbidden` branch

**File:** `lib/foglet_bbs/tui/screens/sysop/boards_view.ex:471-472`
**Issue:** The pattern `_ = kind` pins a variable for no observable reason —
`kind` is already in scope and unused on this branch.
**Fix:** Delete the line. If it was meant to silence an unused-variable
warning from an earlier revision, the warning no longer applies (kind is
matched in the enclosing function head).

### IN-02: Redundant `Map.pop` / `Map.get` pair in edit-board dispatch

**File:** `lib/foglet_bbs/tui/screens/sysop/boards_view.ex:484-492`
**Issue:** The code pops `category_id` from `payload` into `_cat_id` (discarded),
normalizes the remaining attrs, then re-reads `category_id` from the original
`payload` via `Map.get/2` and re-inserts it. The net result is equivalent to
just normalizing the full payload.
**Fix:**
```elixir
defp dispatch_submit(:edit_board, payload, state) do
  Boards.update_board(state.current_user, state.edit_target, normalize_board_attrs(payload))
end
```
(Assuming `normalize_board_attrs/1` is safe for the `category_id` key — it is,
since the current implementation only touches `:postable_by`.)

### IN-03: Enum prefix-match is ambiguous when options share a prefix

**File:** `lib/foglet_bbs/tui/screens/sysop/site_form.ex:127-132`
**Issue:** For string-enum fields, typing a letter picks the first enum value
that `String.starts_with?/2` — meaning `"m"` matches `"mods"` but could
ambiguously match `"mods_only"` if the list order changes. Current enum
lists avoid this, but the dependency is implicit. Not a bug today; a latent
footgun for future schema entries.
**Fix:** Document the ordering dependency in the moduledoc, or match on the
full first character plus a unique-prefix assertion.

### IN-04: `apply_submodule_result` only surfaces the first `:error_modal` event

**File:** `lib/foglet_bbs/tui/screens/sysop.ex:173-183`
**Issue:** `Enum.find/2` returns the first matching event. If a submodule ever
emits multiple error modals in a single key handler, only the first is shown;
subsequent modals are silently dropped. Today no submodule emits more than
one, so this is theoretical.
**Fix:** Either document the "at most one error_modal per event" contract on
the submodule behaviour, or concatenate messages.

### IN-05: `require Logger` inside function bodies instead of at module top

**File:** `lib/foglet_bbs/boards.ex:134, 226` and `lib/foglet_bbs/config.ex:152`
**Issue:** `require Logger` is scattered inside function bodies on the error
path. This works, but it's idiomatic to `require Logger` once at the top of
the module. In-function requires add a small amount of compile-time work each
call-site and obscure the module's dependencies.
**Fix:** Add `require Logger` at the top of each module and remove the
per-clause requires.

---

_Reviewed: 2026-04-23_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
