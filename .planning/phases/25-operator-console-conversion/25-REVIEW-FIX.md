---
phase: 25-operator-console-conversion
fixed_at: 2026-04-25T00:00:00Z
review_path: .planning/phases/25-operator-console-conversion/25-REVIEW.md
iteration: 1
findings_in_scope: 13
fixed: 12
skipped: 1
status: partial
---

# Phase 25: Code Review Fix Report

**Fixed at:** 2026-04-25T00:00:00Z
**Source review:** .planning/phases/25-operator-console-conversion/25-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 13
- Fixed: 12
- Skipped: 1

## Fixed Issues

### CR-01: BoardsView stash cleared before payload is read

**Files modified:** `lib/foglet_bbs/tui/screens/sysop/boards_view.ex`
**Commit:** 20d247d
**Applied fix:** Removed the preemptive `Process.delete({__MODULE__, :pending_submit})` call at the top of `handle_form_event/2`. The stash is now read and deleted only after `ModalForm.handle_event/2` returns in the `:submitted` branch; the `:cancelled` branch cleans up after the cancel is confirmed. This eliminates the race condition where a retry after a failed partial submit would silently swallow the stashed payload.

---

### CR-02: Synchronous Repo call on Raxol Lifecycle process in `TUI.App.init/1`

**Files modified:** `lib/foglet_bbs/tui/app.ex`, `test/foglet_bbs/tui/app_test.exs`
**Commit:** 6e5ec51
**Applied fix:** Replaced the synchronous `oneliners_mod.list_recent_visible/1` call in `maybe_load_initial_oneliners/1` with an async message send. `init/1` now calls `maybe_schedule_initial_oneliners/1` which sends `{:load_oneliners}` to self when the initial screen is `:main_menu` and a user is present. `update/2` handles this message via the existing async `do_update({:load_oneliners}, state)` task path. The test at line 51 was updated to reflect that `recent_oneliners` is initially empty and `{:load_oneliners}` is scheduled rather than executed inline.

**Note: requires human verification** — the async behavior change means tests that previously asserted immediate oneliner loading in init now assert the scheduled message instead. Verify end-to-end session startup loads oneliners correctly.

---

### CR-03: `revoke_selected/2` crashes with stale `selected_index`

**Files modified:** `lib/foglet_bbs/tui/screens/account/ssh_keys_state.ex`
**Commit:** b12d970
**Applied fix:** Changed `selected_index/1` to derive the authoritative index from `cursor_index(table)` (the ConsoleTable cursor state) rather than the redundant `selected_index` struct field. Added a second clause `def selected_index(_), do: 0` for safety. The `select_next/select_prev` functions still update the `selected_index` field for backward compatibility with existing tests, but `revoke_selected/2` now always reads from the single source of truth. Added a comment explaining the migration path.

---

### WR-01: `account.ex` bare pattern-match on `InvitesActions.load/2`

**Files modified:** `lib/foglet_bbs/tui/screens/account.ex`
**Commit:** bde4063
**Applied fix:** Replaced `{:ok, invites} = InvitesActions.load(...)` and `{:ok, ssh_keys} = SSHKeysActions.load(...)` bare matches with `case` expressions. On `{:error, _}` the state is returned unchanged, preventing a crash if the DB is unavailable or the actor is unexpectedly nil.

---

### WR-02: `moderation_invites_visible?/1` only checks `:mod` role — asymmetry undocumented

**Files modified:** `lib/foglet_bbs/tui/screens/moderation.ex`
**Commit:** ae98ba6
**Applied fix:** Added a module-level comment above `moderation_invites_visible?/1` documenting that the mod-only restriction is intentional and deliberate — sysop users are not routed to the Moderation screen in normal flows, and moderation INVITES is a moderator-specific workflow by design. Points to `moderation_test.exs` for the explicit assertion.

---

### WR-03: `default_category_for/1` — `_` branch calls `hd/1` on potentially unknown row type

**Files modified:** `lib/foglet_bbs/tui/screens/sysop/boards_view.ex`
**Commit:** 84d4f0c
**Applied fix:** Refactored to two clauses: `default_category_for(%__MODULE__{categories: [hd | _]} = state)` handles all three row-type branches with `hd` as a bound variable, and a second clause `default_category_for(%__MODULE__{} = state), do: hd(state.categories)` covers the unreachable empty-list case (the caller already guards on empty). The `{:board, board}` branch now uses `|| hd` against the bound variable rather than `|| hd(state.categories)`, avoiding a double-hd call.

---

### WR-04: `put_oneliner_form_errors/2` fallback re-opens composer unconditionally

**Files modified:** `lib/foglet_bbs/tui/app.ex`
**Commit:** 74cb0b9
**Applied fix:** Added a guard to the fallback clause of `put_oneliner_form_errors/2` that only re-opens the composer modal when `pending_hide_oneliner_id` is nil or empty. A new final catch-all clause returns `state` unchanged when a hide-oneliner operation is pending, preventing the composer modal from clobbering the hide-oneliner context. Added a comment explaining the separation from `put_hide_oneliner_form_errors/2`.

---

### WR-05: `submit_stash.ex` `with_stashed/2` — non-atomic pop allows re-entrant stash corruption

**Files modified:** `lib/foglet_bbs/tui/widgets/modal/form/submit_stash.ex`
**Commit:** daff8b8
**Applied fix:** Changed `with_stashed/2` to atomically pop the stash via `Process.delete/1` before calling `fun`, eliminating both the re-entrance problem and the `after` cleanup clause. `Process.delete/1` returns the old value (or nil if absent), so the semantics are identical for the common case. Added a comment explaining the re-entrance rationale.

---

### WR-06: `dialyzer_ignore.exs` — Phase 25 warnings labeled as "pre-existing"

**Files modified:** `.dialyzer_ignore.exs`
**Commit:** c922db2
**Applied fix:** Replaced the misleading "pre-existing warnings from Phase 25 conversions" comment with an accurate description of each suppression category, notes on which fixes in this phase may resolve some of them (CR-03 for `:guard_fail`/`:pattern_match_cov`, WR-05 for `:pattern_match`), and a directive to remove each suppression after confirming `mix dialyzer` passes without it. The `:contract_supertype` suppression for `moderation/state.ex` is correctly annotated as matching the style of existing suppressions.

---

### IN-01: `users_view.ex` — `users_table` field is dead (never populated, always discarded)

**Files modified:** `lib/foglet_bbs/tui/screens/sysop/users_view.ex`
**Commit:** 6f67841
**Applied fix:** Removed the `users_table: ConsoleTable.t() | nil` field from the `@type t` typespec and the `defstruct`. The `render/2` function already creates a local `users_table` on each call; the struct field was never written to and the `init/1` did not populate it.

---

### IN-03: `app.ex` — pre-emptive stash deletes in `:form` modal key handler

**Files modified:** `lib/foglet_bbs/tui/app.ex`
**Commit:** 2fa0bd8
**Applied fix:** Removed the two `Process.delete` calls for `{__MODULE__, :pending_oneliner_submit}` and `{__MODULE__, :pending_hide_oneliner_submit}` that executed before `ModalForm.handle_event/2`. The `take_oneliner_submit/0` and `take_hide_oneliner_submit/0` functions already handle atomic read-and-delete after `handle_event` fires the `on_submit` callback. Added a comment explaining the ordering contract.

---

### IN-04: `moderation_helper.ex` — weak `{x,y}` uniqueness overlap check

**Files modified:** `test/support/foglet/tui/layout_smoke/moderation_helper.ex`
**Commit:** f1be621
**Applied fix:** Replaced the `length(coords) == length(Enum.uniq(coords))` check in all four `defmacro` blocks (LOG, USERS, BOARDS, INVITES) with the same sorted pairwise range-overlap check used by `assert_no_same_row_overlap!/3` in the main test file. The new check groups elements by row, sorts by x, and asserts each element's right edge (`x + TextWidth.display_width(text)`) does not exceed the start of the next element. This catches overlap-by-1-column cases that the old check missed.

---

## Skipped Issues

### IN-02: `invites_surface.ex` — dead `ListRow`/`SelectionList` import and legacy render path

**File:** `lib/foglet_bbs/tui/screens/shared/invites_surface.ex:25-26`
**Reason:** The legacy raw-map render path is still actively used by `invites_surface_test.exs` (lines 106-140 pass plain maps with `%{items: [...], selected_index: 1}`). The aliases are therefore not dead — removing them would break existing tests. The code already has a comment documenting the legacy path. Removal should be deferred until the tests are migrated to `%InvitesState{}` structs.
**Original issue:** Potential dead aliases and legacy branch if all callers now use `%InvitesState{}`.

---

_Fixed: 2026-04-25T00:00:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
