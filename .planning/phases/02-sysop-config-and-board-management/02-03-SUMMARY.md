---
phase: 02-sysop-config-and-board-management
plan: 03
subsystem: tui-sysop
tags: [sysop, site, limits, config, invt-06, invt-07, syso-02]
requires:
  - "02-01: invite_generation_per_user_limit schema key"
provides:
  - "Foglet.TUI.Screens.Sysop.SiteForm — inline SITE tab editor (@site_keys)"
  - "Foglet.TUI.Screens.Sysop.LimitsForm — inline LIMITS tab editor (@limits_keys)"
  - "Sysop.State.{site_form, limits_form, boards_view, system_snapshot} fields"
  - "Sysop.handle_key delegation + {:error_modal, msg, dest} translation"
affects:
  - "Sysop BOARDS tab (Plan 04) slots into the existing boards_view field"
  - "Sysop SYSTEM tab (Plan 05) slots into the existing system_snapshot field"
key_files:
  created:
    - lib/foglet_bbs/tui/screens/sysop/site_form.ex
    - lib/foglet_bbs/tui/screens/sysop/limits_form.ex
  modified:
    - lib/foglet_bbs/tui/screens/sysop/state.ex
    - lib/foglet_bbs/tui/screens/sysop.ex
    - test/foglet_bbs/tui/screens/sysop_test.exs
decisions:
  - "D-19 fallback taken: rendered SITE/LIMITS as plain-text rows with a focus marker (▸) rather than wiring TextInput/Checkbox/RadioGroup primitives. Modal.Form is not used here (required only for BOARDS in Plan 04)."
  - "Ctrl+S event shape: matched the codebase's %{key: :char, char: \"s\", ctrl: true} convention (new_thread.ex:257) — not the plan-specified %{key: :ctrl_s}. The project's Raxol event stream uses the ctrl: true modifier key."
  - "Render guards submodule state: when a tab's submodule is still nil, render shows 'Press any key to load …' placeholder. Lazy init happens on first delegate. This keeps Sysop.render/1 DB-free for existing layout-smoke tests."
metrics:
  duration_min: 35
  completed: "2026-04-23"
---

# Phase 02 Plan 03: SITE/LIMITS tab forms summary

Implements inline full-tab SITE and LIMITS editors driven by `Schema.entries/0` iteration with a hard-coded `@site_keys`/`@limits_keys` partition; Ctrl+S writes through `Config.put/3` with inline error surfacing and `%Modal{type: :error}` + `:main_menu` routing for `:forbidden` / `:db_error`; `invite_generation_per_user_limit` row is hidden unless `invite_code_generators == "any_user"` (INVT-07 / D-04).

## Tasks Completed

| Task | Name                                                                | Commit   |
| ---- | ------------------------------------------------------------------- | -------- |
| 1    | Extend Sysop.State with :site_form / :limits_form / :boards_view / :system_snapshot | 5c8dcdb |
| 2    | Implement Sysop.SiteForm inline editor                              | c72d6e3* |
| 3    | Implement Sysop.LimitsForm inline editor                            | 45e88b8* |
| 4    | Wire tab delegation + partition / render / Ctrl+S tests             | (HEAD)   |

*Hashes recorded during this run; see `git log --oneline` on the worktree branch for exact values.

## Files Modified

- `lib/foglet_bbs/tui/screens/sysop/state.ex` — added four nil-default per-tab fields on the State struct.
- `lib/foglet_bbs/tui/screens/sysop/site_form.ex` (NEW) — inline SITE editor with `@site_keys`, `visible_keys/1` (D-04 conditional), Tab focus rotation, Space to toggle/cycle, digit entry for integer fields, Ctrl+S submit via `Config.put/3`, inline error + modal-event output.
- `lib/foglet_bbs/tui/screens/sysop/limits_form.ex` (NEW) — inline LIMITS editor with `@limits_keys`, all-integer field handling.
- `lib/foglet_bbs/tui/screens/sysop.ex` — added `SiteForm` / `LimitsForm` / `Modal` aliases; `build_content` now takes `ss` and dispatches SITE/LIMITS bodies to the submodules; `handle_key` falls back to a `delegate_to_active_tab/3` path that lazy-inits the active tab's submodule with `state.current_user` and translates `{:error_modal, msg, dest}` events to `%Foglet.TUI.Modal{type: :error}` + navigation to `dest`.
- `test/foglet_bbs/tui/screens/sysop_test.exs` — converted to `FogletBbs.DataCase, async: false`; setup seeds every schematized config key via `Config.put!/3` so lazy-init's `Config.get!/1` has rows; added partition / SITE render / conditional-visibility / Ctrl+S inline-error / Ctrl+S forbidden-modal / LIMITS render describes.

## Key Decisions

- **D-19 fallback (plain text rows + focus marker):** Avoids per-field adapter plumbing for this first inline-form consumer. `Modal.Form` remains the required primitive for the BOARDS tab in Plan 04.
- **Ctrl+S event shape:** Matched the live `new_thread.ex` precedent (`%{key: :char, char: "s", ctrl: true}`) rather than the plan's nominal `%{key: :ctrl_s}`. See Deviations for the rationale; the behavior contract is preserved.
- **Render without DB side effects:** `Sysop.render/1` must not lazy-init forms (because a bare render call — e.g. the LayoutSmokeTest — runs without a DB sandbox). Lazy-init is confined to `handle_key/2` delegation. Render shows a `"Press any key to load …"` placeholder until then.
- **Hidden rows are never submitted:** `submit/1` iterates `visible_keys(state)`, not `@site_keys` — stale drafts for a hidden `invite_generation_per_user_limit` cannot be written (Pitfall 6 / T-02-04).
- **`nil`-actor `:forbidden` test instead of a role-only struct:** Using a non-sysop `%User{}` with a random UUID passes authorization but fails the `configuration.updated_by_id` FK, muddying the test. `nil` trips `Foglet.Authorization.authorize(_, nil, _)` cleanly (D-24 semantics).

## Deviations from Plan

### [Rule 2 — correctness] Ctrl+S key event shape mismatch between plan and codebase

- **Found during:** Task 2 implementation, confirmed against `new_thread.ex:257`.
- **Issue:** Plan spec's `<interfaces>` block nominally uses `%{key: :ctrl_s}`, but every existing screen in `lib/foglet_bbs/tui/screens/` (notably `new_thread.ex:257-259`) matches `%{key: :char, char: "s", ctrl: true}`. The plan also acknowledged this uncertainty ("match whatever `new_thread.ex` matches").
- **Fix:** Implemented `handle_key(%{key: :char, char: "s", ctrl: true}, state)` in both `SiteForm` and `LimitsForm`; tests assert the same shape.
- **Commit:** c72d6e3 (SiteForm), 45e88b8 (LimitsForm).

### [Rule 3 — blocking test regression] Existing "no fake config writes" render guard removed

- **Found during:** Task 4 test run.
- **Issue:** The Phase 0 test `renders scaffold-only placeholder copy (no fake config writes)` `refute`s the substring `"Save"` anywhere in the SITE tab's render output. Now that Plan 02-03 ships real SITE/LIMITS forms, the `[Ctrl+S] Save` footer legitimately contains `"Save"` — the refute would always fire.
- **Fix:** Removed the test and replaced it with a one-line comment noting Plan 02-03's transition. The equivalent guarantee ("screen never dispatches fake config commands") survives under the existing `handle_key/2` describe block, which iterates representative keys and refutes `:save_config` / `:apply_config` / `:set_config` tuples in the returned events.
- **Commit:** (Task 4 commit).

### [Rule 3 — blocking test regression] sysop_test.exs converted to DataCase

- **Found during:** Task 4 test run.
- **Issue:** Previously `use ExUnit.Case, async: true` because the Phase 0 scaffold never touched Config. Lazy-init of `SiteForm` / `LimitsForm` now calls `Config.get!/1` during test `render`/`handle_key` paths, which requires the Ecto sandbox and a populated `configuration` table.
- **Fix:** Converted to `use FogletBbs.DataCase, async: false`; setup seeds all schematized defaults via `Config.put!/3` and invalidates the ETS cache before/after each test (the pattern from `config_test.exs:17-23`).
- **Commit:** (Task 4 commit).

### [Rule 2 — correctness] Guarded `render/1` against DB hits

- **Found during:** Full-suite run after Task 4 — `LayoutSmokeTest` sysop shell case regressed with a `DBConnection.OwnershipError`.
- **Issue:** Initially, `render_tab_body("SITE", …)` fell back to `SiteForm.init(current_user: nil)` if `ss.site_form` was nil — causing any non-DataCase caller of `Sysop.render/1` to crash.
- **Fix:** Replaced the fallback with a `"Press any key to load …"` placeholder. Lazy-init is now strictly a `handle_key/2` concern. The three new SITE/LIMITS render tests were updated to send a `%{key: :tab}` event before asserting rendered text, which triggers lazy-init.
- **Commit:** (Task 4 commit).

## Verification

- `mix test test/foglet_bbs/tui/screens/sysop_test.exs` → **16 tests, 0 failures.**
- `mix test test/foglet_bbs/tui/screens/sysop_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` → **34 tests, 0 failures** (confirming LayoutSmokeTest regression resolved).
- `mix test` (full suite) → **1102 tests, 16 failures** — all 16 failures are pre-existing on `main` (pre-Plan 02-03: 1096 tests, 16 failures; the 6 new tests are all the ones added in this plan, and they all pass).
- `mix precommit` → clean (compile --warnings-as-errors, format, credo --strict, sobelow, dialyzer — dialyzer reports 83 total errors, 83 skipped, 0 unnecessary skips; no new errors).

## Threat Model Confirmation

- **T-02-01 (EoP):** `SiteForm.submit/1` and `LimitsForm.submit/1` pass `state.current_user` into every `Config.put/3` call; `:forbidden` → `{:error_modal, …, :main_menu}` event → modal + navigation.
- **T-02-02 (Tampering):** All writes flow through `Config.put/3` → `Schema.validate/2`. Test `invalid integer surfaces inline error, no modal` proves the path.
- **T-02-03 (InfoDisclosure):** Submodules iterate only `@site_keys` / `@limits_keys`; the partition test asserts `MapSet.union == MapSet.new(Schema.entries keys)` AND `disjoint?`.
- **T-02-04 (Tampering on hidden draft):** `submit/1` iterates `visible_keys(state)` — hidden `invite_generation_per_user_limit` drafts are never submitted.

## Self-Check: PASSED

- `lib/foglet_bbs/tui/screens/sysop/state.ex` contains `site_form:` / `limits_form:` / `boards_view:` / `system_snapshot:` — FOUND.
- `lib/foglet_bbs/tui/screens/sysop/site_form.ex` exists — FOUND; contains `@site_keys`, `def init`, `def handle_key`, `def render`, `def visible_keys`, `Foglet.Config.put` (not `put!`).
- `lib/foglet_bbs/tui/screens/sysop/limits_form.ex` exists — FOUND; contains `@limits_keys`, `"max_post_length"`, `Foglet.Config.put`.
- `lib/foglet_bbs/tui/screens/sysop.ex` contains `SiteForm.handle_key` + `LimitsForm.handle_key` — FOUND.
- `test/foglet_bbs/tui/screens/sysop_test.exs` contains `SITE / LIMITS tab partition`, `hides invite_generation_per_user_limit`, `:forbidden from Config.put` — FOUND.
- Per-task commits present on worktree branch: 5c8dcdb (Task 1) + two subsequent for Task 2/3 + Task 4 HEAD commit.
