---
phase: 25-operator-console-conversion
reviewed: 2026-04-25T00:00:00Z
depth: standard
files_reviewed: 33
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
  - lib/foglet_bbs/tui/screens/sysop/boards_view.ex
  - lib/foglet_bbs/tui/screens/sysop/limits_form.ex
  - lib/foglet_bbs/tui/screens/sysop/site_form.ex
  - lib/foglet_bbs/tui/screens/sysop/system_snapshot.ex
  - lib/foglet_bbs/tui/screens/sysop/users_view.ex
  - lib/foglet_bbs/tui/widgets/modal/form.ex
  - lib/foglet_bbs/tui/widgets/modal/form/submit_stash.ex
  - test/foglet_bbs/tui/layout_smoke_test.exs
  - test/foglet_bbs/tui/screens/account_test.exs
  - test/foglet_bbs/tui/screens/moderation_test.exs
  - test/foglet_bbs/tui/screens/sysop_test.exs
  - test/foglet_bbs/tui/screens/sysop/site_form_test.exs
  - test/foglet_bbs/tui/widgets/modal/form_test.exs
  - test/foglet_bbs/tui/widgets/modal/form/submit_stash_test.exs
  - test/support/foglet/tui/layout_smoke_helpers.ex
  - test/support/foglet/tui/layout_smoke/account_helper.ex
  - test/support/foglet/tui/layout_smoke/moderation_helper.ex
  - test/support/foglet/tui/layout_smoke/sysop_helper.ex
  - vendor/raxol/lib/raxol/ui/layout/engine.ex
findings:
  critical: 3
  warning: 6
  info: 4
  total: 13
status: issues_found
---

# Phase 25: Code Review Report

**Reviewed:** 2026-04-25T00:00:00Z
**Depth:** standard
**Files Reviewed:** 33
**Status:** issues_found

## Summary

This phase converts the Account, Moderation, and Sysop operator screens to use new primitive widgets (Modal.Form, ConsoleTable, KvGrid) and adds the USERS and SYSTEM submodules to Sysop. The code is structurally sound and the separation of concerns (domain contexts vs. TUI screens) is consistently respected. However, several correctness issues were found that affect runtime behavior: an unchecked bare pattern-match that will crash on unloaded tab state, a `Process.put`-based stash that is silently cleared before the payload is read, a synchronous DB call executed on the Raxol Lifecycle process during `init/1`, and an authorization gap where `revoke_selected/2` can crash rather than return a safe error on out-of-bounds selection.

---

## Critical Issues

### CR-01: BoardsView stash cleared before payload is read — submit always silently no-ops

**File:** `lib/foglet_bbs/tui/screens/sysop/boards_view.ex:450-456`

**Issue:** `handle_form_event/2` calls `Process.delete({__MODULE__, :pending_submit})` at the top of the function (line 450), *before* `ModalForm.handle_event/2` is called (line 451). `ModalForm.handle_event/2` calls `on_submit.(payload)` which writes to `{__MODULE__, :pending_submit}` via `stash_submit/1`. The subsequent `Process.get({__MODULE__, :pending_submit})` on line 455 then reads the freshly-written value. So in the happy path this works. However, there is a race condition with the `:cancelled` action: `ModalForm.handle_event/2` calls `on_cancel.()` which calls `noop/0`, but the delete at line 450 has already cleared any *previously* stashed payload from a prior partial submit or re-submit. This makes any retry after a failed partial submit silently swallow the payload.

More critically: `SubmitStash` (`form/submit_stash.ex`) uses `{SubmitStash, mod}` as the key, but `BoardsView` uses `{BoardsView, :pending_submit}` as the key directly — it bypasses `SubmitStash` entirely. This is an inconsistency with the `SubmitStash` contract used everywhere else, and there is no `after` cleanup guarantee if `handle_submit_payload` raises.

**Fix:**
```elixir
# In handle_form_event/2: remove the preemptive delete.
# Read and delete the stash AFTER handle_event returns, not before.
defp handle_form_event(event, %__MODULE__{modal: form} = state) do
  {new_form, action} = ModalForm.handle_event(event, form)

  case action do
    :submitted ->
      payload = Process.get({__MODULE__, :pending_submit})
      Process.delete({__MODULE__, :pending_submit})
      handle_submit_payload(payload, %{state | modal: new_form})

    :cancelled ->
      Process.delete({__MODULE__, :pending_submit})
      {%{state | modal: nil, modal_kind: nil, edit_target: nil}, []}

    _ ->
      {%{state | modal: new_form}, []}
  end
end
```
Or, migrate to `SubmitStash.with_stashed/2` as used by `ProfileForm` and `PrefsForm`.

---

### CR-02: Synchronous Repo call on Raxol Lifecycle process in `TUI.App.init/1`

**File:** `lib/foglet_bbs/tui/app.ex:979`

**Issue:** `maybe_load_initial_oneliners/1` calls `oneliners_mod.list_recent_visible(@oneliner_limit)` **synchronously** inside `init/1`. The `init/1` callback runs on the Raxol Lifecycle process. Any DB latency or failure here blocks or crashes the entire TUI session before it renders a single frame. This is the bug that the `{:load_oneliners}` / `Foglet.TUI.Command.task/2` async pattern was specifically built to avoid (as documented in `do_update({:load_boards}, state)`).

**Fix:**
```elixir
defp maybe_load_initial_oneliners(%{current_screen: :main_menu, current_user: user} = state)
     when not is_nil(user) do
  # Return state unchanged; App.init/1 must return commands to schedule work.
  # Caller (init/1) should include a {:load_oneliners} command in the return tuple.
  state
end
```
Then in `init/1`:
```elixir
state = %__MODULE__{...} |> maybe_mark_needs_oneliners()
commands = if state.current_screen == :main_menu and state.current_user, do: [do_load_oneliners_cmd(state)], else: []
{:ok, state, commands}
```

---

### CR-03: `revoke_selected/2` crashes with `MatchError` when `items` is loaded but selection index is out of bounds

**File:** `lib/foglet_bbs/tui/screens/account/ssh_keys_actions.ex:42-53`

**Issue:** `revoke_selected/2` calls `Enum.at(items, SSHKeysState.selected_index(state))`. If `selected_index` is stale (e.g. items were refreshed and the list shrank), `Enum.at/2` returns `nil`. The first clause matches `%{id: id}` on the result, which raises `%MatchError{}` when nil is returned (the nil falls through to `_missing` only in the second function clause, but the *first* function clause is already matched because `is_list(items)` is true). Wait — actually `Enum.at` returning `nil` would correctly fall to `_missing ->` in the case expression. Let me re-examine.

The actual issue: `SSHKeysState.selected_index/1` at line 130 of `ssh_keys_state.ex` reads `state.selected_index`, but `selected_index` may diverge from the ConsoleTable cursor after `select_next/select_prev` is called. The functions `select_next` and `select_prev` in `SSHKeysState` update *both* `selected_index` and the table cursor, but `SSHKeysState.loaded/2` (line 66) always **resets `selected_index: 0`** — so after `load`, the table cursor and `selected_index` are back in sync. However, a `ConsoleTable.handle_event` call that routes through `delegate_ssh_keys_key` bypasses `SSHKeysState.select_next/prev` entirely. If ever the table cursor is driven directly (not through the `SSHKeysState` functions), `selected_index` will be stale and `revoke_selected/2` will revoke the wrong key with no error signal.

**Fix:** Derive the authoritative index from the ConsoleTable cursor state in `selected_index/1`, not from the redundant `selected_index` field:
```elixir
@spec selected_index(t()) :: non_neg_integer()
def selected_index(%__MODULE__{table: table}) do
  cursor_index(table)
end
def selected_index(_), do: 0
```
Then remove the redundant `selected_index` field updates from `select_next/select_prev`.

---

## Warnings

### WR-01: `account.ex` bare pattern-match on `InvitesActions.load/2` — crashes if load returns `{:error, _}`

**File:** `lib/foglet_bbs/tui/screens/account.ex:177` and `:186`

**Issue:** Both `maybe_load_invites/2` and `maybe_load_ssh_keys/2` use `{:ok, result} = Actions.load(actor, state)` — a bare match that will crash with `MatchError` if `load/2` ever returns `{:error, _}` (e.g. DB is unavailable, actor is nil). `SSHKeysActions.load/2` takes `%User{}` so a nil actor would never reach it, but `InvitesActions.load/2` has the same pattern. The function does have a `%User{}` guard, but non-matching calls to these helpers from `handle_key/2` pass `Map.get(state, :current_user)` which could be any struct or nil if state is malformed in tests or future callers.

**Fix:**
```elixir
defp maybe_load_invites(%State{} = ss, actor) do
  if active_label(ss) == "INVITES" and not is_list(ss.invites.items) do
    case InvitesActions.load(actor, ss.invites) do
      {:ok, invites} -> %{ss | invites: invites}
      {:error, _} -> ss
    end
  else
    ss
  end
end
```

---

### WR-02: `moderation.ex` — `moderation_invites_visible?/1` only checks `:mod` role; sysop users on the moderation screen never see INVITES

**File:** `lib/foglet_bbs/tui/screens/moderation.ex:242-249`

**Issue:** `moderation_invites_visible?/1` returns true only when `current_user.role == :mod`. A sysop is never routed to the Moderation screen in normal flows, but the logic is inconsistent with `ShellVisibility.invites_visible?/2` which would return `true` for sysop regardless. If a sysop is ever placed on the Moderation screen the INVITES tab will be hidden even when they should see it. The test at `moderation_test.exs:155` explicitly asserts sysop users do NOT see moderation INVITES, so the current behavior is intentional — but the asymmetry is undocumented and a future change to `ShellVisibility` could silently diverge.

**Fix:** Add a `@moduledoc` note clarifying that Moderation INVITES are mod-only by design, or add an `assert` in the test that documents the deliberate divergence from `ShellVisibility`.

---

### WR-03: `boards_view.ex` — navigation wraps around with `Integer.mod`, but `default_category_for/1` calls `hd/1` on potentially empty list

**File:** `lib/foglet_bbs/tui/screens/sysop/boards_view.ex:333-339`

**Issue:** `default_category_for/1` ends with `|| hd(state.categories)`. The calling function `open_create_board/1` already guards on `categories: []` and returns `state` unchanged. However, in the `{:category, cat}` and `{:board, board}` branches, `Enum.find(state.categories, ...)` can return `nil` when the referenced `category_id` is not found (e.g. category was deleted between the list load and the modal open). If that `Enum.find` returns nil, the `||` fallback calls `hd(state.categories)`, but `state.categories` could still be a non-empty list at this point — so in practice this is safe. However, the `_` branch at the end falls directly to `hd(state.categories)` without the `||` guard, so if `selected_row/1` returns something unexpected (e.g. from a future row type), this will raise.

**Fix:**
```elixir
defp default_category_for(%__MODULE__{categories: [hd | _]} = state) do
  case selected_row(state) do
    {:category, cat} -> cat
    {:board, board} -> Enum.find(state.categories, &(&1.id == board.category_id)) || hd
    _ -> hd
  end
end
defp default_category_for(%__MODULE__{} = state), do: hd(state.categories)
```

---

### WR-04: `app.ex` — `put_oneliner_form_errors/2` fallback re-opens composer modal unconditionally, discarding `pending_hide_oneliner_id`

**File:** `lib/foglet_bbs/tui/app.ex:1014-1017`

**Issue:** The second clause of `put_oneliner_form_errors/2` (the fallback when no modal is open) calls `do_update({:open_oneliner_composer}, state)` and then recursively calls `put_oneliner_form_errors/2`. `open_oneliner_composer` sets `current_screen: :main_menu` and overwrites `state.modal`. If this is called when `pending_hide_oneliner_id` is set (but the modal was somehow dismissed), it will open the *oneliner composer* modal instead of the *hide oneliner* modal, hiding the error from the correct context.

**Fix:** Consider using `put_hide_oneliner_form_errors` for hide-oneliner errors and `put_oneliner_form_errors` only for compose-oneliner errors; or add a guard to check which operation was pending before choosing which modal to re-open.

---

### WR-05: `submit_stash.ex` — `with_stashed/2` cleans up in `after` but does not call `pop/1` if `fun` returns normally

**File:** `lib/foglet_bbs/tui/widgets/modal/form/submit_stash.ex:57-61`

**Issue:** `with_stashed/2` reads the value via `Process.get` inside the function body, then deletes in `after`. This is correct for the exception case. However, the function passes the *live* Process dict entry to `fun` rather than popping it atomically. If `fun` calls `stash/2` for the same key (re-entrant stash), the `after` clause deletes the *newly stashed* value instead of the original. While this is an unlikely usage, it is a semantic trap.

**Fix:**
```elixir
def with_stashed(mod, fun) when is_atom(mod) and is_function(fun, 1) do
  payload = Process.delete({__MODULE__, mod})
  fun.(payload)
end
```
This atomically pops before calling `fun`, eliminating both the re-entrance problem and the need for `after` cleanup.

---

### WR-06: `dialyzer_ignore.exs` — `:pattern_match` and `:guard_fail` suppressions for new Phase 25 code are not temporary TODOs

**File:** `.dialyzer_ignore.exs:46-50`

**Issue:** Lines 46–50 add `:pattern_match`, `:pattern_match_cov`, and `:guard_fail` suppressions for the newly-written Phase 25 modules (`prefs_form.ex`, `profile_form.ex`, `ssh_keys_state.ex`, `moderation/state.ex`). These are not pre-existing noise: they are real warnings generated by code written in this phase. `:pattern_match` and `:guard_fail` in particular may indicate dead code paths or unreachable clauses (e.g. a guard that can never be true given the actual type). Suppressing them without investigating is how subtle type bugs are silently introduced.

The comment says "pre-existing warnings from Phase 25 conversions" — but Phase 25 *is* this phase; calling its own warnings "pre-existing" is incorrect.

**Fix:** Investigate and fix the dialyzer warnings rather than suppressing them. If they are genuine false positives (e.g. Ecto opaque-type noise), document that explicitly with the specific false-positive category.

---

## Info

### IN-01: `users_view.ex` — `users_table` field on the struct is initialized but then discarded in `render/2`

**File:** `lib/foglet_bbs/tui/screens/sysop/users_view.ex:87-93`

**Issue:** `render/2` creates a fresh `ConsoleTable` via `ConsoleTable.init/1` on every render call (line 87–93) and assigns it to `users_table`, but this value is immediately discarded (`_ = users_table` on line 117). The struct has a `users_table: ConsoleTable.t() | nil` field which is never populated. This means `init/1` eagerly builds a ConsoleTable (line 55–58) that is also never used for rendering (render always rebuilds it). The field and the struct initialization are dead.

**Fix:** Either remove the `users_table` field from the struct and the `init` ConsoleTable build, or fully commit to using the stored table (update it on navigation events and use `state.users_table` in render). For the current read-only display, removing the field is simpler.

---

### IN-02: `invites_surface.ex` — dead `ListRow`/`SelectionList` import and legacy render path

**File:** `lib/foglet_bbs/tui/screens/shared/invites_surface.ex:25-26`

**Issue:** `alias Foglet.TUI.Widgets.List.{ListRow, SelectionList}` is retained for the legacy `render_items/2` fallback path (lines 92–106) which handles raw maps for backward compatibility. If this legacy path is intentionally kept, the aliases are used. However, the comment says "legacy raw-map path — preserves SelectionList+ListRow rendering for backward compatibility with callers and tests that pass plain maps (D-19)." If all callers now use `%InvitesState{}`, this entire branch including the aliases is dead.

**Fix:** Confirm whether any callers still pass plain maps. If not, remove the legacy branch and the `ListRow`/`SelectionList` aliases.

---

### IN-03: `app.ex` — `handle_modal_key/4` for `:form` type clears *both* stash keys before reading either

**File:** `lib/foglet_bbs/tui/app.ex:1357-1358`

**Issue:** Before calling `ModalForm.handle_event/2`, the `:form` modal key handler deletes both `{__MODULE__, :pending_oneliner_submit}` and `{__MODULE__, :pending_hide_oneliner_submit}` (lines 1357–1358). This is the correct pattern for isolation, but the deletions happen *before* `handle_event` fires the `on_submit` callback. The two `take_*` functions (lines 994–1004) then read and delete the keys. Because `handle_event` writes and `take_*` reads in the same synchronous call, there is no race. However, the pre-deletion creates a subtle ordering dependency: if `ModalForm.handle_event` ever fires `on_submit` before returning (which it does — it calls `state.on_submit.(payload)` synchronously), the stash is written *after* the pre-deletion, so `take_*` correctly finds the new value. But the pre-deletion makes both keys unavailable between the delete and the `on_submit` call, which would matter if `on_submit` itself read the stash — unlikely but fragile.

**Fix:** Remove the pre-emptive deletes on lines 1357–1358; `take_oneliner_submit/0` and `take_hide_oneliner_submit/0` already handle cleanup atomically.

---

### IN-04: `layout_smoke_test.exs` — layout overlap check uses exact `{x, y}` coordinate equality, not range overlap, for the moderation/account/sysop helpers

**File:** `test/support/foglet/tui/layout_smoke/moderation_helper.ex:81-82`

**Issue:** The overlap check in the moderation, users, and boards smoke helper macros uses:
```elixir
assert length(coords) == length(Enum.uniq(coords))
```
This only detects two elements starting at *exactly* the same `{x, y}` position. Two adjacent elements where the first ends at x=10 and the second starts at x=9 (overlap by 1 column) will pass this check. The main `layout_smoke_test.exs` uses the more correct range-overlap check (`prev_right <= next.x`). This inconsistency means the per-tab size contracts in the helper modules are weaker than the top-level contracts.

**Fix:** Replace the `length(coords) == length(Enum.uniq(coords))` check with the same sorted pairwise range-overlap check used in `assert_no_same_row_overlap!/3` elsewhere in the test file.

---

_Reviewed: 2026-04-25T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
