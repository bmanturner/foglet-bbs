---
phase: 02-sysop-config-and-board-management
plan: 04
subsystem: tui-sysop
tags: [sysop, boards, categories, modal-form, syso-03]
requirements: [SYSO-03]
requires:
  - "02-02: actor-first create/update/archive_category in Foglet.Boards"
  - "02-03: Sysop.State per-tab fields + handle_key delegation pattern"
  - "01.1: Foglet.TUI.Widgets.Modal.Form primitive"
provides:
  - "Foglet.TUI.Screens.Sysop.BoardsView — BOARDS tab submodule (list + Modal.Form + confirm modal dispatch)"
  - "Sysop delegate_to_submodule/5 — shared submodule delegation helper (keeps delegate_to_active_tab under Credo's complexity cap as tabs are added)"
affects:
  - "Plan 02-05 SYSTEM tab slots into the same delegate_to_submodule/5 pattern."
key-files:
  created:
    - lib/foglet_bbs/tui/screens/sysop/boards_view.ex
  modified:
    - lib/foglet_bbs/tui/screens/sysop.ex
    - lib/foglet_bbs/tui/screens/sysop/site_form.ex
    - test/foglet_bbs/tui/screens/sysop_test.exs
decisions:
  - "Modal.Form on_submit adaptation: the primitive discards the closure's return value (form.ex:114 — `_ = state.on_submit.(payload)`), so BoardsView's submit closure stashes the typed payload under `Process.put({BoardsView, :pending_submit}, payload)` and handle_form_event/2 pops it after Modal.Form.handle_event/2 returns `:submitted`. Single-process TUI — no cross-process risk. Documented in the @moduledoc."
  - "Uppercase char 'D' on the highlighted row disambiguates board-vs-category archive (board when a :board row is highlighted, category when a :category row is highlighted) — the plan's nominal 'Shift+D' for category archive is not a distinct raxol event shape on this codepath."
  - "delegate_to_active_tab refactored into delegate_to_submodule/5 to keep cyclomatic complexity under Credo's max-9 cap once the BOARDS branch was added."
  - "Dead :db_error / :other error arms removed from handle_submit_payload/2: Foglet.Boards.{create,update}_* only returns :forbidden + %Ecto.Changeset{}, Dialyzer flagged the other clauses as unreachable. The confirm-flow keeps a {:error, _} catch-all for archive_changeset validation failures."
metrics:
  completed_date: 2026-04-23
---

# Phase 02 Plan 04: BOARDS tab — board + category CRUD via Modal.Form

Ships the BOARDS tab end-to-end: a categorized list of boards grouped by
category, with board + category create/edit through the Phase 1.1
`Foglet.TUI.Widgets.Modal.Form` primitive and archive through the existing
`%Foglet.TUI.Modal{type: :confirm}` prompt. All domain calls go through the
actor-aware `Foglet.Boards.*` functions from Plan 02-02; `:forbidden` routes
to the shared error modal + `:main_menu`. Satisfies SYSO-03 UI.

## Tasks Completed

| Task | Name                                                          | Commits  |
| ---- | ------------------------------------------------------------- | -------- |
| —    | Baseline fix: nil-safe ctrl/meta guard in SiteForm.handle_key | 8920ff6  |
| 1    | Implement Sysop.BoardsView submodule + Sysop delegation       | 47c71d7  |
| 2    | Add BOARDS tests + refactor delegate_to_active_tab            | 1f99ed2  |

## Files Modified

- `lib/foglet_bbs/tui/screens/sysop/boards_view.ex` (NEW) — BOARDS-tab
  submodule. Triplet contract (`init/1 + handle_key/2 + render/2`). Owns:
  categorized list rows, modal dispatch (Modal.Form + confirm), submit
  closures that route through `Foglet.Boards.{create,update,archive}_
  {board,category}` with `state.current_user` + `:site` scope.
- `lib/foglet_bbs/tui/screens/sysop.ex` — adds BoardsView alias and wires
  BOARDS through `delegate_to_submodule/5`, the shared per-tab delegation
  helper extracted from the previous SITE/LIMITS-only `case` (Credo
  complexity fix).
- `lib/foglet_bbs/tui/screens/sysop/site_form.ex` — one-line nil-safe guard
  fix (`or` → `||`) so unknown chars on the SITE tab don't crash.
- `test/foglet_bbs/tui/screens/sysop_test.exs` — six new describe blocks
  covering render, create, invalid submit, Pitfall 5, archive, category
  create, and :forbidden routing. Uses a local `put_boards_view/2` helper
  that avoids Access-behaviour pitfalls (Sysop.State is a struct).

## Tests

- `test/foglet_bbs/tui/screens/sysop_test.exs` — 24 tests, 0 failures.
- Full suite: `mix test` — 1110 tests, 2 failures (both pre-existing in
  `test/foglet_bbs/config/schema_test.exs`, logged to
  `deferred-items.md`; unrelated to this plan's scope).

## Decisions

- **Modal.Form on_submit adaptation (plan narrative Task 1).** The
  primitive discards the `on_submit` callback's return value
  (`form.ex:114`). To plumb the typed payload back, BoardsView's submit
  closure stashes it in the Process dictionary under
  `{Foglet.TUI.Screens.Sysop.BoardsView, :pending_submit}`;
  `handle_form_event/2` pops it immediately after `Modal.Form.handle_event/2`
  returns the `:submitted` action. Documented at length in the
  `boards_view.ex` `@moduledoc`.
- **Archive disambiguation by highlighted row.** Raxol char events for
  uppercase letters don't carry a distinct `:shift` flag, so the plan's
  nominal "Shift+D for category archive" is realised as: `D` while a
  `:category` row is highlighted archives the category; `D` on a `:board`
  row archives the board. The archive_target is set from the selection.
- **Shared `delegate_to_submodule/5` helper.** Adding a third BOARDS branch
  to `Sysop.delegate_to_active_tab` pushed its cyclomatic complexity from 7
  to 10, failing Credo's `--strict` max-9 cap. Refactor gives each tab a
  single-line case arm and a shared helper that handles lazy-init and the
  `apply_submodule_result` plumbing. Plan 02-05's SYSTEM tab will slot in
  without touching the helper.
- **Dead error arms removed.** `Foglet.Boards.{create,update}_*` returns
  only `:forbidden` or `%Ecto.Changeset{}` — never `:db_error`. Dialyzer
  flagged the unreachable `{:error, :db_error}` and `{:error, _other}` arms;
  removed. If the domain ever widens its error set, the changeset
  catch-all will need to grow — but speculative breadth there is
  structurally misleading per Dialyzer.

## Deviations from Plan

### [Rule 1 — bug] Pre-existing BadBooleanError in SiteForm.handle_key

- **Found during:** baseline sysop-test run before Plan 02-04 work began.
- **Issue:** `SiteForm.handle_key/2` guarded char events with
  `Map.get(event, :ctrl) or Map.get(event, :meta)`. `Map.get/2` returns nil
  when the key is absent, and Elixir's strict `or` raises BadBooleanError
  on a nil left operand. Every plain letter key without a ctrl/meta
  modifier crashed the SITE tab, including the existing `unknown key
  returns :no_match` test which had been failing on main.
- **Fix:** Swap `or` → `||`. Non-strict short-circuit accepts nil.
- **Commit:** 8920ff6.

### [Rule 3 — blocking test regression] Sysop `unknown key returns :no_match` regressed with initial lazy-init hack

- **Found during:** first test run after wiring BOARDS tab.
- **Issue:** The test at sysop_test.exs:166 sends `%{key: :char, char: "z"}`
  and expects `:no_match`. Initial BoardsView integration used a "force
  state change on lazy-init" branch in `delegate_to_submodule/5` so that
  any key on BOARDS would persist the freshly-initialised submodule. That
  also forced `:update` on SITE's no-op path, breaking the regression
  assertion.
- **Fix:** Revert the force-update branch; compare `new_sub` against the
  post-init `sub` as the original pattern. Tests that need a lazy-init
  hook into BoardsView now send `%{key: :down}` (which BoardsView handles
  as a real selection rotate) and the `activate_boards_tab/2` helper
  rewinds the selection to 0.
- **Commit:** 1f99ed2 (rolled into Task 2's commit because the refactor
  and the test rewire landed together).

### [Rule 3 — blocking] Worktree branched from pre-Plan-02 commit

- **Found during:** initial `git ls-files` — the worktree was branched
  from `0a5f7aa`, before any Plan 02 work existed on the branch. Plan
  dependencies (`Foglet.Boards.create_category/2` etc.) were on main but
  not in this branch.
- **Fix:** `git merge --no-edit main` into the worktree branch. Clean
  merge; no conflicts. Same pattern 02-02 used.
- **Commit:** (merge commit from `git merge`; no plan-code changes).

### [Conflict flagged — user decision invited] Pre-existing Credo failure in `lib/foglet_bbs/accounts.ex:94`

- **Situation:** `mix precommit` exits 8 because Credo `--strict` reports a
  "Last clause in `with` is redundant" refactoring opportunity on
  `Foglet.Accounts.register_invite_only_user/1`. Verified on a pristine
  stash checkout of main: the same failure exists *before* any Plan 02-04
  changes. The prompt's concurrency note explicitly says a separate
  session is working on `lib/foglet_bbs/accounts.ex` and this session must
  NOT touch it. The prompt also says "run `mix precommit` and fix
  issues", which here means fixing accounts.ex.
- **Chosen resolution:** Follow the concurrency note (don't touch
  accounts.ex). Commit the plan without a green `mix precommit`.
  `mix format` is green on my changed files; `mix compile
  --warnings-as-errors` is green; `mix test` is green for my scope;
  `mix dialyzer` is green (83 total, 83 skipped, 0 unnecessary skips).
  The Credo-strict failure is exclusively on phase 03 territory owned by
  the other session.
- **User decision invited:** If precommit green is strictly required,
  either the phase 03 session fixes `accounts.ex:94` (delete the redundant
  `{:ok, user} -> {:ok, user}` final `with` clause or add a Credo
  `@credo:disable-for-this-line` directive) or this plan can take the
  one-line fix after phase 03's work lands on main.

## Self-Check

- `lib/foglet_bbs/tui/screens/sysop/boards_view.ex` exists — FOUND.
- `grep -q 'Modal.Form' lib/foglet_bbs/tui/screens/sysop/boards_view.ex`  — FOUND.
- `grep -q 'Foglet.Boards.create_board' lib/foglet_bbs/tui/screens/sysop/boards_view.ex`  — FOUND.
- `grep -q 'Foglet.Boards.update_board' lib/foglet_bbs/tui/screens/sysop/boards_view.ex`  — FOUND.
- `grep -q 'Foglet.Boards.archive_board' lib/foglet_bbs/tui/screens/sysop/boards_view.ex`  — FOUND.
- `grep -q 'Foglet.Boards.create_category' lib/foglet_bbs/tui/screens/sysop/boards_view.ex`  — FOUND.
- `grep -q 'Foglet.Boards.update_category' lib/foglet_bbs/tui/screens/sysop/boards_view.ex`  — FOUND.
- `grep -q 'Foglet.Boards.archive_category' lib/foglet_bbs/tui/screens/sysop/boards_view.ex`  — FOUND.
- `grep -q 'BoardsView' lib/foglet_bbs/tui/screens/sysop.ex`  — FOUND (alias + delegate case).
- `mix compile --warnings-as-errors` — clean.
- `mix test test/foglet_bbs/tui/screens/sysop_test.exs` — 24/24 green.
- `mix format --check-formatted` on my three changed files — clean.
- `mix dialyzer` — 83 errors, 83 skipped, 0 unnecessary skips (no new issues).

## Self-Check: PASSED
