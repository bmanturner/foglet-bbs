---
phase: 02-sysop-config-and-board-management
plan: 02
subsystem: boards
tags: [sysop, categories, authorization, bodyguard]
requirements: [SYSO-03]
provides:
  - "Foglet.Boards.create_category/2 (actor-first, sysop-gated)"
  - "Foglet.Boards.update_category/3 (actor-first, sysop-gated)"
  - "Foglet.Boards.archive_category/2 (actor-first, sysop-gated)"
  - "Foglet.Boards.Category.archive_changeset/1 (defensive single-field cast)"
affects:
  - "Plan 04 BoardsView TUI — consumes these three functions from Modal.Form submit handlers"
key-files:
  modified:
    - lib/foglet_bbs/boards/category.ex
    - lib/foglet_bbs/boards.ex
    - test/foglet_bbs/boards/boards_test.exs
decisions:
  - "Mirrored create_board/3 + archive_board/2 patterns verbatim (D-15): with-Bodyguard.permit/4 wrapper returning {:error, :forbidden} on deny."
  - "Kept legacy create_category/1 alongside new arity-2 (D-10 additive)."
  - "Category.archive_changeset/1 casts only :archived (defensive — prevents piggybacking other field mutations through the archive path)."
  - "Did NOT introduce a shared setup block for sysop/mod/category fixtures — mirrored the file's existing pattern of calling sysop_actor()/mod_actor() helpers and category_fixture() inline per test, which is what the create_board/3 and archive_board/2 describes already do."
metrics:
  completed_date: 2026-04-23
---

# Phase 02 Plan 02: Category CRUD Backend (Actor-First) Summary

Authorized category CRUD now exists at the domain layer so Plan 04's BOARDS tab can consume it: three new `Foglet.Boards` functions (create/update/archive) and one new `Category.archive_changeset/1`, each wrapped in `Bodyguard.permit(Foglet.Authorization, ..., :site)`.

## Tasks Completed

| Task | Name | Commits |
| ---- | ---- | ------- |
| 1 | `Category.archive_changeset/1` | `caa9226` (RED test), `4300be6` (GREEN impl) |
| 2+3 | Actor-first `create/update/archive_category` + test coverage | `0a8fbeb` (RED tests for T2+T3), `c72f8fc` (GREEN impl) |

(Exact SHAs may differ — see `git log --oneline -5`.)

## Files Modified

- `lib/foglet_bbs/boards/category.ex` — added `archive_changeset/1` mirroring `Board.archive_changeset/1`.
- `lib/foglet_bbs/boards.ex` — added `create_category/2`, `update_category/3`, `archive_category/2`.
- `test/foglet_bbs/boards/boards_test.exs` — aliased `Category`; added describe blocks for `Category.archive_changeset/1`, `create_category/2 (SYSO-03, actor-first)`, `update_category/3 (SYSO-03)`, `archive_category/2 (SYSO-03)` (happy + forbidden + changeset-invalid coverage).

## Verification

- `mix test test/foglet_bbs/boards/boards_test.exs` — 43 tests, 0 failures.
- `mix precommit` — compile --warnings-as-errors clean, format clean, credo --strict clean, sobelow clean, dialyzer 0 non-skipped errors.
- `mix format --check-formatted` — clean for all three modified files.

## Decisions Made

- **Mirror existing Board pattern exactly.** The plan's `create_board/3` and `archive_board/2` are the canonical shape; the new category functions use the same `with :ok <- Bodyguard.permit(...)` short-circuit so that both happy-path `{:ok, struct} | {:error, changeset}` and `{:error, :forbidden}` flow through the same pipe (D-15).
- **Keep `create_category/1` unchanged.** Seeds and internal trusted callers still use it (D-10). The new arity-2 form is additive; no existing call-sites needed migration.
- **Changeset shape unchanged.** Plan 02-02 explicitly forbids introducing new changeset functions; `update_category` reuses `Category.changeset/2` with the same casted field list (`:name, :description, :display_order, :archived`) since the schema has no slug (unlike Board), so slug-immutability concerns from the plan narrative don't apply here.
- **Test fixture style.** The file has no shared `setup` block exposing `%{sysop:, mod:, category:}`; it uses `sysop_actor()`/`mod_actor()` helpers and inline `category_fixture()` calls. I matched that existing style instead of introducing a new setup.

## Deviations from Plan

1. **Plan example used `slug: "tech"` in create_category attrs — Category has no `slug` field.** The plan's Task 3 example code passed `%{name: "Tech", slug: "tech"}` to `create_category/2` and expected `{:ok, %Category{slug: "tech"}}`. `Foglet.Boards.Category` has fields `:name, :description, :display_order, :archived` — no `:slug`. I used `%{name: "Tech", display_order: 3}` and asserted on `name` + `display_order` instead. This is a plan-narrative slip (confusing Category with Board), not a schema gap — no Category changes warranted.

2. **Added a `regular user is forbidden` test in addition to `mod is forbidden` and `nil is forbidden`.** The plan's Task 3 example only listed sysop/mod/nil cases explicitly, but the existing `create_board/3 authorization (D-27)` describe covers regular user + mod + nil. Matching that style gives consistent coverage across the codebase and costs nothing (Rule 2 — correctness/coverage parity).

3. **Merged phase-branch plans into worktree before executing.** The worktree was branched from commit `0a5f7aa` (before phase 02 plans existed on the phase branch). I ran `git merge --no-edit phase/02-sysop-config-and-board-management` to pick up the plan, context, and research files. Clean merge, no conflicts. No file-scope deviation.

No Rule-4 (architectural) deviations. No auth gates.

## Self-Check: PASSED

- `lib/foglet_bbs/boards/category.ex` — `grep -q 'def archive_changeset'` FOUND.
- `lib/foglet_bbs/boards.ex` — `grep -c 'def create_category'` == 2 (arity-1 + arity-2); `def update_category(actor` and `def archive_category(actor` both FOUND.
- `test/foglet_bbs/boards/boards_test.exs` — `grep -q 'create_category/2 (SYSO-03'`, `update_category/3 (SYSO-03'`, `archive_category/2 (SYSO-03'` all FOUND; `async: false` unchanged.
- Commits for T1 RED, T1 GREEN, T2+T3 RED, T2 GREEN all present in `git log --oneline`.
- `mix test test/foglet_bbs/boards/boards_test.exs` — 43/43 green.
- `mix precommit` — green.
