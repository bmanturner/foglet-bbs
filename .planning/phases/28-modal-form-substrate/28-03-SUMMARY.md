---
phase: 28-modal-form-substrate
plan: 03
subsystem: ui
tags: [tui, raxol, modal, form, account, esc, cancel, status_message]

# Dependency graph
requires:
  - phase: 28-modal-form-substrate
    provides: Modal.Form substrate (FORM-01..05) and Account.State.seed_from_user/2 reseeding contract from Wave 1
provides:
  - Account.ProfileForm honest Esc (FORM-06 Account half) — drafts revert, status_message stays nil
  - Account.PrefsForm honest Esc (FORM-06 Account half) — drafts revert, candidate_theme_id clears, status_message stays nil
  - 4 forward-locking tests asserting field reversion + null status_message + absence of "discarded" copy
affects:
  - 29-sysop-tab-lifecycle (precedent for SiteForm honest Esc; Sysop Site half delivered separately by Plan 04)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Honest cancel pattern (D-10/D-11): the visible cancel signal is the field values themselves reverting on the next render — no flash status row. The global command bar is the single advertiser of [Esc] Cancel."
    - "FORM-06 testing pattern: assert (a) draft equality with saved-user values, (b) dirty? cleared, (c) status_message == nil, (d) absence of any 'discarded' substring in inspect(state)."

key-files:
  created: []
  modified:
    - lib/foglet_bbs/tui/screens/account/profile_form.ex
    - lib/foglet_bbs/tui/screens/account/prefs_form.ex
    - test/foglet_bbs/tui/screens/account_test.exs

key-decisions:
  - "Removed 'discarded' from BOTH the production status_message AND from in-file moduledoc/comment text so the plan's literal acceptance grep (`grep -E discarded ... returns no matches`) holds. Documentation rephrased to 'No flash status row' and 'flash status row' to capture the intent without the loaded word."
  - "Reused the existing State.seed_from_user/2 contract (built in Phase 25) — it already clears candidate_theme_id, so the PrefsForm Esc branch needs no extra cleanup."
  - "Test fixture uses CONTEXT example values verbatim (location: 'Berlin', tagline: 'hi', timezone: 'Etc/UTC', theme: 'gray') so future readers can trace the test back to the directive in CONTEXT D-10/D-11."
  - "Sanity-only assertion on the typed field value: tests assert the live form's :location/:timezone differs from the saved value and contains 'X' after the typing event, rather than asserting an exact string. Cursor-position semantics in Modal.Form's text input are not load-bearing for FORM-06 — only that the live form differs from the saved user is."

patterns-established:
  - "Honest cancel: replace per-form flash copy with field reversion; rely on the global command bar for the [Esc] Cancel hint. Future SiteForm migration (Plan 04) will follow the same shape."

requirements-completed: [FORM-06]

# Metrics
duration: ~10min
completed: 2026-04-27
---

# Phase 28 Plan 03: Honest Esc on Account Profile + Preferences Summary

**Account.ProfileForm and Account.PrefsForm now treat Esc as an honest cancel: drafts reseed to the saved user via `State.seed_from_user/2`, `status_message` stays nil, and the user-visible signal is the field values themselves reverting on the next render — no `"Profile changes discarded."` / `"Preference changes discarded."` flash row.**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-04-27T18:07:12Z
- **Completed:** 2026-04-27T18:17:00Z
- **Tasks:** 1 (TDD RED → GREEN)
- **Files modified:** 3
- **New test cases added:** 4

## Accomplishments

- **FORM-06 (Account Profile):** `:cancelled` action in `ProfileForm.handle_key/3` now sets `status_message: nil` after reseeding via `State.seed_from_user/2`. The `"Profile changes discarded."` copy is gone.
- **FORM-06 (Account Preferences):** `:cancelled` action in `PrefsForm.handle_key/3` now sets `status_message: nil` after reseeding. `candidate_theme_id` is cleared by `seed_from_user/2`, so theme-preview state is also reverted in the same call. The `"Preference changes discarded."` copy is gone.
- **Tests:** Four new tests in `test/foglet_bbs/tui/screens/account_test.exs` assert (per CONTEXT D-10/D-11):
  1. Profile Esc reseeds draft + clears dirty + clears status_message; the rendered form's first-field value reverts.
  2. Profile Esc produces no `"discarded"` substring anywhere in the returned state map.
  3. Prefs Esc reseeds draft + clears dirty + clears status_message + clears candidate_theme_id.
  4. Prefs Esc produces no `"discarded"` substring anywhere in the returned state map.

## Task Commits

| Task | Phase | Commit | Description |
|------|-------|--------|-------------|
| 1 | RED | `1aca585` | `test(28-03): add failing tests for honest Esc on Account Profile/Prefs (FORM-06)` — 4 tests fail at `status_message == nil` |
| 1 | GREEN | `62a1970` | `feat(28-03): drop flash status copy on Account honest Esc (FORM-06)` — `:cancelled` branches set `status_message: nil`; moduledocs updated; full suite green |

## Files Modified

### `lib/foglet_bbs/tui/screens/account/profile_form.ex`
- **`:cancelled` branch (do_handle_key/3):** Replaced `status_message: "Profile changes discarded."` with `status_message: nil`. Added comment referencing FORM-06 / D-10 / D-11.
- **`@moduledoc`:** Appended a paragraph describing the new honest-Esc contract: drafts reseed via `State.seed_from_user/2`; the field values reverting on the next render are the visible signal; "no flash status row" because the global command bar already advertises `[Esc] Cancel`.

### `lib/foglet_bbs/tui/screens/account/prefs_form.ex`
- **`:cancelled` branch (do_handle_key/3):** Replaced `status_message: "Preference changes discarded."` with `status_message: nil`. Added comment noting that `seed_from_user/2` also clears `candidate_theme_id`, so the theme-preview branch needs no extra cleanup.
- **`@moduledoc`:** Same FORM-06 paragraph as ProfileForm, with the additional note that `candidate_theme_id` is cleared via `seed_from_user/2`.

### `test/foglet_bbs/tui/screens/account_test.exs`
- **New `build_user_with_profile/1` test fixture** with CONTEXT example values as defaults.
- **New `describe "FORM-06 honest Esc on Account Profile (Phase 28 D-10, D-11)"`** with 2 tests.
- **New `describe "FORM-06 honest Esc on Account Preferences (Phase 28 D-10, D-11)"`** with 2 tests.
- No existing tests asserted on the `"discarded"` strings — `grep -rn "discarded" test/` returned only an unrelated PostReader test about cache-discard semantics. So no test edits were necessary beyond adding the new ones.

## Diffs

### ProfileForm `:cancelled` branch

**Before:**
```elixir
:cancelled ->
  reseeded = State.seed_from_user(state, current_user)
  {:ok, %{reseeded | status_message: "Profile changes discarded."}, []}
```

**After:**
```elixir
:cancelled ->
  # FORM-06 / D-10, D-11: Esc reseeds drafts; the visible signal is the
  # field values reverting on the next render. No flash status row —
  # Account screens already advertise [Esc] Cancel in the global
  # command bar.
  reseeded = State.seed_from_user(state, current_user)
  {:ok, %{reseeded | status_message: nil}, []}
```

### PrefsForm `:cancelled` branch

**Before:**
```elixir
:cancelled ->
  reseeded = State.seed_from_user(state, current_user)
  {:ok, %{reseeded | status_message: "Preference changes discarded."}, []}
```

**After:**
```elixir
:cancelled ->
  # FORM-06 / D-10, D-11: Esc reseeds drafts (which clears
  # candidate_theme_id via seed_from_user); no flash status row.
  reseeded = State.seed_from_user(state, current_user)
  {:ok, %{reseeded | status_message: nil}, []}
```

## Decisions Made

- **No existing-test edits required.** A pre-implementation `grep -rn "discarded" test/` showed only one unrelated match in `post_reader_test.exs` (about cache-discard semantics). The `"Profile changes discarded."` and `"Preference changes discarded."` strings appeared only in the two production files we were modifying. So no consumer-test inversions were needed (unlike Plan 01, which had to flip 6 footer-presence assertions).
- **Documentation rewording.** The plan's acceptance criterion `grep -E "discarded" lib/foglet_bbs/tui/screens/account/profile_form.ex lib/foglet_bbs/tui/screens/account/prefs_form.ex returns no matches` is literal — it covers the entire file, not just runtime emissions. My initial moduledoc/comment drafts contained the word "discarded" in narrative form (e.g. `No "Profile changes discarded." chrome row`). I rephrased them to "No flash status row" / "flash status row" so the literal grep passes. The intent is preserved and arguably clearer (calling it a "flash row" is closer to UI-vocabulary).
- **Tests reach into the live form via `Modal.Form.handle_event(%{key: :char, char: "X"}, form)`** rather than via Account.handle_key. This makes the cause-and-effect chain explicit — the test mutates the form, sets `profile_dirty?: true`, then dispatches Esc through ProfileForm.handle_key — and avoids confounding with Account-level routing logic.
- **Sanity assertion on typed value uses substring/inequality, not exact-string equality.** The first version of the test asserted `field_value == "BerlinX"`, but the actual value was `"XBerlin"` because `TextInput`'s default cursor sits at column 0. The exact cursor position is not load-bearing for FORM-06 — only the fact that the live form value differs from the saved user. Updated to `!= "Berlin"` and `=~ "X"`. This is more robust to any future cursor-default changes in `TextInput`.

## CONTEXT Amendment in Effect

The user's directive in CONTEXT D-10/D-11 amends SPEC FORM-06 acceptance criterion (b) to drop the flash row. Criterion (a) — `state.profile_draft == saved-user values` and `state.profile_dirty? == false` after Esc — stands. Both criteria are now enforced by the new tests:

- Criterion (a) verified by Test 1 (Profile) and Test 3 (Prefs): both assert exact draft equality with saved-user values + `dirty? == false`.
- Amended criterion (b) verified by Test 2 (Profile) and Test 4 (Prefs): both refute the presence of `"discarded"` anywhere in `inspect(state, limit: :infinity)`.

The Sysop Site half of FORM-06 is delivered by Plan 04 alongside the SiteForm migration (parallel wave 3 worktree).

## Deviations from Plan

None — the plan executed as written. The acceptance criteria, behavior list, and action steps were precise enough that no rule-1/2/3 fixups or rule-4 escalations were required.

The single judgment call (rephrasing moduledoc/comment text to avoid the literal word "discarded") is documented in *Decisions Made* above; it preserves the plan's intent and makes the literal acceptance grep pass.

## TDD Gate Compliance

Task 1 followed a strict RED → GREEN cycle:

- **RED:** `1aca585` — 4 failing tests committed first; full output confirms all 4 fail at the `status_message == nil` assertion (the production code emits `"Profile changes discarded."` / `"Preference changes discarded."`).
- **GREEN:** `62a1970` — `:cancelled` branches updated to set `status_message: nil`; moduledocs/comments rephrased; all 4 new tests pass; full suite (1864 tests) green.
- **REFACTOR:** None needed — the change is a 2-line semantic flip in each module plus moduledoc text. No structural cleanup warranted.

## Verification

- `rtk mix test test/foglet_bbs/tui/screens/account_test.exs` → 50 tests, 0 failures (covers FORM-06 Account half).
- `rtk mix test` (full suite) → 1 property, 1864 tests, 0 failures.
- `rtk mix precommit` → passed (compile, formatter, Credo, Sobelow, Dialyzer all clean).
- `rtk mix foglet.tui.render account 2>&1 | grep -ic "discard"` → `0` (no rendered "discarded" copy on the Account screens).
- Acceptance grep checks (all match the plan):
  - `grep -c "Profile changes discarded" lib/foglet_bbs/tui/screens/account/profile_form.ex` → `0`
  - `grep -c "Preference changes discarded" lib/foglet_bbs/tui/screens/account/prefs_form.ex` → `0`
  - `grep -c "status_message: nil" lib/foglet_bbs/tui/screens/account/profile_form.ex` → `1`
  - `grep -c "status_message: nil" lib/foglet_bbs/tui/screens/account/prefs_form.ex` → `1`
  - `grep -E "discarded" lib/foglet_bbs/tui/screens/account/profile_form.ex lib/foglet_bbs/tui/screens/account/prefs_form.ex` → no matches (exit 1)

## Issues Encountered

- **Worktree base mismatch on startup:** The worktree was initially based on `3226ef9e` (older `main`) instead of the expected `b739cec` (Phase 28 wave-2 merged). Hard-reset to the correct base per the `<worktree_branch_check>` protocol; no work was lost (worktree was empty).
- **First-pass test had a wrong precondition assertion.** The test asserted `field_value(form_after_type, :location) == "BerlinX"` but the actual value was `"XBerlin"` because `TextInput` inserts at the default cursor position (column 0). This is a test-only bug — the FORM-06 behavior under test is unaffected. Fixed by relaxing the precondition to `!= "Berlin"` and `=~ "X"`. Since this happened during the RED phase before the commit, it appears in the RED commit as the corrected version.

## Next Phase Readiness

- **Plan 04 (SiteForm migration):** Plan 04 delivers the Sysop Site half of FORM-06 alongside the SiteForm migration. The pattern established here (replace per-form flash with field reversion) is directly transferable.
- **Phase 29 (Sysop tab lifecycle):** Phase 29 inherits the now-stable honest-cancel contract: any new tabbed editor downstream should follow the same `state.seed_from_user/2` (or analogous reseeder) + `status_message: nil` shape.

## Self-Check: PASSED

**Files exist:**
- `lib/foglet_bbs/tui/screens/account/profile_form.ex` — FOUND (modified)
- `lib/foglet_bbs/tui/screens/account/prefs_form.ex` — FOUND (modified)
- `test/foglet_bbs/tui/screens/account_test.exs` — FOUND (modified)

**Commits exist:**
- `1aca585` — FOUND (test RED)
- `62a1970` — FOUND (feat GREEN)

---
*Phase: 28-modal-form-substrate*
*Completed: 2026-04-27*
