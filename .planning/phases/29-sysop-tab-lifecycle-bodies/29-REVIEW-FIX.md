---
phase: 29-sysop-tab-lifecycle-bodies
fixed_at: 2026-04-27T22:15:57Z
review_path: .planning/phases/29-sysop-tab-lifecycle-bodies/29-REVIEW.md
iteration: 1
findings_in_scope: 7
fixed: 7
skipped: 0
status: all_fixed
---

# Phase 29: Code Review Fix Report

**Fixed at:** 2026-04-27T22:15:57Z
**Source review:** `.planning/phases/29-sysop-tab-lifecycle-bodies/29-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 7 (all warnings; no blockers were reported)
- Fixed: 7
- Skipped: 0
- Worktree branch: `review-fix-29-21830` (foreground session held `main`,
  so commits land on a temporary branch that the orchestrator can fast-forward
  / merge into `main`)

## Fixed Issues

### WR-01: LIMITS schema descriptions leak planning IDs to operators

**Files modified:** `lib/foglet_bbs/config/schema.ex`,
`test/foglet_bbs/config/schema_test.exs`
**Commits:** `db553a6` (fix + broaden test) and `157a169`
(follow-up: update locked decision-table assertions to the new copy)
**Applied fix:** Rewrote the three operator-facing integer-key
descriptions (`max_post_length`, `max_thread_title_length`,
`email_verify_resend_cooldown_seconds`) to remove planning markers
(`D-31`, `D-13`, `phase-03-polish Phase 4`, `Phase 6 D-02`) and end with a
period. Broadened the SYSOP-04 hygiene test from a hardcoded `@site_keys`
list to `Schema.entries()` so any future renamed/added key is covered
automatically. The two follow-up commits were necessary because three
"locked decision table" assertions in `schema_test.exs` had baked the old
description strings into struct equality assertions; they were updated to
the new copy.

### WR-02: `Foglet.TUI.Screens.Sysop` writes via `Map.put(state.screen_state, ...)` without nil-coalescing

**Files modified:** `lib/foglet_bbs/tui/screens/sysop.ex`
**Commit:** `aa5722b`
**Applied fix:** Extracted a private `put_sysop_state/2` helper that
nil-coalesces (`state.screen_state || %{}`) and routed all six write sites
through it. The helper is documented inline with the rationale (sibling
Moderation screen and the App itself defensively coalesce; routing every
Sysop write through the helper keeps the slot mutation symmetric).

### WR-03: `delete_user/1` `Repo.update_all` does not bump `updated_at` on rewritten posts

**Files modified:** `lib/foglet_bbs/accounts.ex`
**Commit:** `47e70bc`
**Applied fix:** Compute a single anonymization timestamp inside the
deletion transaction and add `updated_at: now` to the `set:` clause so
all tombstone-rewritten posts share one anonymization timestamp. The
audit-trail rationale is captured in a comment above the call.

### WR-04: `summarize_form_errors/1` truncation may surface a misleading "shortest message"

**Files modified:** `lib/foglet_bbs/tui/app.ex`
**Commit:** `a2318c4`
**Applied fix:** Replaced the `Enum.min_by(&String.length/1, ...)` shortest
selector with a case statement:
- 0 binary errors → `"Validation error."` (defensive fallback,
  period-terminated)
- 1 binary error → that error verbatim
- 2 or more → `"Please correct the highlighted fields."`

The multi-error prompt avoids ranking errors by length and points the
operator at the per-field rendering for detail.

### WR-05: `App.do_update({:load_sysop_*}, _)` flips slot to `:loading` redundantly when called from screen-emitted commands

**Files modified:** `lib/foglet_bbs/tui/screens/sysop.ex`,
`test/foglet_bbs/tui/screens/sysop_test.exs`
**Commit:** `dd2d9c8`
**Applied fix:** Made the App the single writer for the lifecycle
`:loading` transition. Removed the screen-side `Map.put(ss, slot,
:loading)` from both `dispatch_if_not_loaded/3` (tab-switch path) and the
`[R]` Retry handler. The screen now only emits the `{:load_sysop_*}`
dispatch tuple. The App's `process_screen_commands/2` runs synchronously
before returning to Raxol, so `do_update({:load_sysop_*}, _)` flips the
slot to `:loading` via `put_sysop_loading/2` before any next event can
observe `:not_loaded` / `{:error, _}`. Six tests updated to assert
post-screen state matches the new contract (slot stays `:not_loaded` or
`{:error, _}` until the App processes the dispatch); the
`{:error, :forbidden}` and `{:loaded, _}` no-op tests still pass without
changes because they `refute` `:loading`.

### WR-06: `sysop.ex` `delegate_to_invites/3` clears `armed_revoke?` only on selected_index change, not on action

**Files modified:** `lib/foglet_bbs/tui/screens/sysop.ex`
**Commit:** `3fb7879`
**Applied fix:** Replaced the index-only check with a small named
predicate `invites_arm_preserved?/3` that returns `true` only when the
InvitesActions key was a vertical move (`:up/:down/j/k/J/K`) AND the
focused row is unchanged. Any other key (R Refresh, G Generate, refresh
side effects) clears the arm, restoring the D-25 row-identity gesture
contract.

### WR-07: `Foglet.TUI.Screens.Sysop.handle_key/2` Enter on INVITES revoked-row falls through to tab widget instead of staying on the row

**Files modified:** `lib/foglet_bbs/tui/screens/sysop.ex`,
`test/foglet_bbs/tui/screens/sysop_test.exs`
**Commit:** `8fa9310`
**Applied fix:** Added a dedicated `{"INVITES", %{status: :revoked}}`
clause to the Enter handler that calls
`InvitesState.with_error(ss.invites, "Invite already revoked.")` and
explicitly clears the arm flag. Added a complementary test that asserts
the new error message surfaces; the existing
`Enter on focused :revoked INVITES row does NOT arm and does NOT
advertise Revoke` test still passes because both assertions
(`armed_revoke?` and revoke-token count) hold under the new clause.

## Skipped Issues

None.

## Notes for the Verifier

**`mix precommit` status:** The full precommit pipeline (compile +
warnings-as-errors → format → credo --strict → sobelow → dialyzer) does
not exit clean, but every surface that fails predates these fixes:

- **format:** clean.
- **compile --warnings-as-errors:** no project warnings; the only
  warnings come from the `raxol` dependency's image renderer / benchmark
  modules referencing optional deps (`Mogrify`, `Benchee.Formatter`).
  Pre-existing on `main`.
- **credo --strict:** 3 readability findings, all in files I did not
  touch — `test/foglet_bbs/tui/screens/account_test.exs:1084` (alias
  ordering inside a Phase 28 describe block) and
  `test/foglet_bbs/tui/layout_smoke_test.exs:2555,2562` (sigil
  recommendation). Verified pre-existing on `main` via
  `git show main:...` and a separate `mix credo --strict` run on the
  base branch — both produced the same 3 findings.
- **sobelow:** clean.
- **dialyzer:** 1 warning at
  `lib/foglet_bbs/tui/widgets/chrome/normalizer.ex:106:8`
  (`pattern_match_cov`). Verified pre-existing on `main`. Not in any file
  modified by this fix pass.

These pre-existing issues are out-of-scope for the WR-01..WR-07 fix
session; flagging here so the human reviewer can decide whether to file
follow-up tickets or fold them into a separate hygiene pass.

**Test suite:** `rtk mix test` runs 1 property + 1976 tests with 0
failures after all 8 commits (WR-01..WR-07 plus the WR-01 follow-up).

**Worktree branch:** Commits land on `review-fix-29-21830` (a temporary
branch the worktree created off `main`) rather than directly on `main`,
because `main` is checked out by the foreground session and git refuses
to attach a second worktree to the same branch. The orchestrator should
fast-forward / merge `review-fix-29-21830` into `main` after reviewing
the 8 commits below:

```
157a169 fix(29): WR-01 follow-up — update locked decision-table tests
8fa9310 fix(29): WR-07 surface explanatory error on Enter against revoked invite
3fb7879 fix(29): WR-06 clear armed_revoke? on any non-vertical-move invites action
dd2d9c8 fix(29): WR-05 make App the single writer for :loading slot transition
a2318c4 fix(29): WR-04 prefer generic prompt over shortest error in summarize_form_errors/1
47e70bc fix(29): WR-03 bump updated_at on tombstone-rewritten posts
aa5722b fix(29): WR-02 nil-coalesce sysop screen_state writes via helper
db553a6 fix(29): WR-01 strip planning IDs from LIMITS schema descriptions
```

---

_Fixed: 2026-04-27T22:15:57Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
