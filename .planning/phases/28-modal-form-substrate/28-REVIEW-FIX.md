---
phase: 28-modal-form-substrate
fixed_at: 2026-04-27T15:05:00Z
review_path: .planning/phases/28-modal-form-substrate/28-REVIEW.md
iteration: 1
findings_in_scope: 5
fixed: 5
skipped: 0
status: all_fixed
---

# Phase 28: Code Review Fix Report

**Fixed at:** 2026-04-27T15:05:00Z
**Source review:** `.planning/phases/28-modal-form-substrate/28-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 5 (0 critical, 2 warning, 3 info — `--all` scope)
- Fixed: 5
- Skipped: 0

All five findings from the gap-closure review were fixed. Each fix was committed atomically; the targeted test files were rerun after every commit, and a final full `mix test` sweep on the post-fix tree reported `1896 tests, 0 failures`. `mix precommit` is green for the files in scope (one pre-existing Credo readability warning at `account_test.exs:1084` — alias ordering inside a `describe` block — predates this iteration and is out of scope).

## Fixed Issues

### WR-01: `SiteForm.finalize_submit/2` `_other` branch can wedge the form at `:submitting`

**Files modified:** `lib/foglet_bbs/tui/screens/sysop/site_form.ex`
**Commit:** `3825878`
**Applied fix:** Drove `new_form` to `:idle` via `ModalForm.set_submit_state/2` before `sync_back/2` in the defensive `_other ->` branch. Previously the form's `:submitting` value (set by Modal.Form's Enter-on-last-field clause that just fired) was persisted onto SState; the per-render rebuild then re-seeded a locked form forever. Added a short comment explaining the BL-01 contract.
**Verification:** `mix test test/foglet_bbs/tui/screens/sysop/site_form_test.exs` — 33/33 pass.

### WR-02: SiteForm bypasses `Modal.Form.set_submit_state/2`'s `:submitting` guard via direct `Map.put`

**Files modified:** `lib/foglet_bbs/tui/widgets/modal/form.ex`, `lib/foglet_bbs/tui/screens/sysop/site_form.ex`
**Commit:** `e3cca9f`
**Applied fix:** Added a public `Modal.Form.replay_submit_state/2` that accepts the full submit-state lifecycle including `:submitting`, with @doc explaining it is the documented escape hatch for the D-17 rebuild-and-replay pattern (only). Replaced all three `Map.put(:submit_state, state.submit_state)` call sites in SiteForm (`render/2`, `handle_key/2`, `submit/1`) with the new function. Updated comments to refer to the new public API. Now `set_submit_state/2` keeps its terminal-state contract intact and `replay_submit_state/2` is the single sanctioned bypass for the rebuild path. Comments in `site_form.ex` that previously cited stale `form.ex:164-166` / `form.ex:178-184` line numbers were rewritten to use phrase anchors as a side effect.
**Verification:** `mix test test/foglet_bbs/tui/widgets/modal/form_test.exs test/foglet_bbs/tui/screens/sysop/site_form_test.exs` — 95/95 pass.

### IN-01: Stale `form.ex:N-M` line references in module documentation

**Files modified:** `lib/foglet_bbs/tui/widgets/modal/form.ex`
**Commit:** `af8774b`
**Applied fix:** Replaced the two stale numeric refs in the Submit-state lifecycle moduledoc (`form.ex:233-244` for the Enter clause; `form.ex:164-166` for the lock guard) with phrase anchors that match in-file clause headings ("Clause 4: Enter", "Clause 0: Lock"). These survive future line shifts. The analogous stale refs in `site_form.ex` (lines 89/90 cited in REVIEW.md) were already cleaned during the WR-02 commit when the surrounding comments were rewritten.
**Verification:** `mix compile --warnings-as-errors` clean for the touched files (only pre-existing vendor warnings from `raxol`'s `Mogrify` shim remain).

### IN-02: `summarize_form_errors/1` comment claims "shortest representative" but picks first by key order

**Files modified:** `lib/foglet_bbs/tui/app.ex`
**Commit:** `671e93f`
**Applied fix:** Chose option (a) from the review — made the implementation honour the docstring by switching from `case Map.values(errors), do: [first | _]` to `errors |> Map.values() |> Enum.filter(&is_binary/1) |> Enum.min_by(&String.length/1, fn -> "validation" end)`. With the existing single-error callers behaviour is unchanged; multi-error inputs (today none, tomorrow possible) now surface the genuinely shortest binary. Updated the comment to clarify tie-breaking ("ties resolve to the first match").
**Verification:** `mix test test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/screens/account_test.exs` — 170/170 pass.

### IN-03: `Modal.Form.init/1` does not validate `:fields` is a list

**Files modified:** `lib/foglet_bbs/tui/widgets/modal/form.ex`
**Commit:** `466ef96`
**Applied fix:** Replaced the single-condition `if fields == []` with a `cond` that first checks `not is_list(fields)` and surfaces the bad value via `inspect/1`, then keeps the existing empty-list branch. Updated the @doc to describe both raised conditions. Non-list inputs (`nil`, atoms, maps) now produce a friendly `ArgumentError` instead of the confusing `Protocol.UndefinedError` that would otherwise come from `Enum.map/2` downstream.
**Verification:** `mix test test/foglet_bbs/tui/widgets/modal/form_test.exs` — 62/62 pass.

## Skipped Issues

None — all in-scope findings were fixed.

## Notes

- A pre-existing Credo readability warning at `test/foglet_bbs/tui/screens/account_test.exs:1084` (alias ordering inside a `describe` block) was observed during the final `mix precommit` sweep. It was introduced in commit `89aeb94` (Phase 28 Plan 05 RED) and is unrelated to any of the five findings in this review. Out of scope for this iteration.
- All five fixes were performed in an isolated worktree at `/tmp/sv-28-reviewfix-0J05fv` attached to `main` via `git worktree add --force` (the primary working tree had `main` checked out). Commits advance `main` directly. The worktree was removed via `git worktree remove --force` after report generation.
- Full regression sweep on the post-fix tree: `1896 tests, 0 failures`.

---

_Fixed: 2026-04-27_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
