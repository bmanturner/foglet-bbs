---
phase: 29-sysop-tab-lifecycle-bodies
plan: 04
subsystem: ui
tags:
  - tui
  - sysop
  - invites
  - command-bar
  - layout

# Dependency graph
requires:
  - phase: 29-sysop-tab-lifecycle-bodies
    plan: 01
    provides: Sysop tagged-enum lifecycle, App-level load triad, render_tab_body lifecycle pattern-match
provides:
  - Focus-aware INVITES surface — focused row carries `theme.selected.fg/bg` styling at 80×24 SSH (D-24)
  - Two-step `[X] Revoke` gesture — Enter arms, X dispatches existing `InvitesActions.revoke_selected/2`; navigation clears (D-25)
  - Render-time `key_bar/1` (Account) and `key_list/1` (Moderation) replace compile-time module attributes (D-26)
  - Sysop `jump_hint` computes `"1-#{length(State.tab_labels(ss))}"` — no INVITES special-case (D-26)
  - Chrome `Tabs` group lifted to navigation priority so `←/→ Tab` + `1-N Jump` both survive at 64×22 (D-27)
  - Normalizer recognises any `1-<digit>` jump-key pattern (no longer hardcoded to 1-5 / 1-6)
affects:
  - Phase 29 closes — all SYSOP-01..07 requirements covered

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Focus indicator pattern: render the ConsoleTable for layout/headers + a separate `theme.selected.fg/bg`-styled focus line so selection is visibly distinct after ANSI stripping"
    - "Render-time key bar pattern: `defp key_bar(ss)` / `defp key_list(ss)` consult `length(tab_labels(ss))` so `1-N Jump` reflects the actor's visible tab count"
    - "Two-step gesture pattern: armed flag on screen state + Enter handler arms + dedicated keypress handler dispatches + tab/focus moves clear"
    - "Chrome priority hierarchy lift: navigation cluster (`←/→ Tab`, `1-N Jump`) at navigation_priority (0) so it survives 64×22 fit_highest_priority drops"

key-files:
  created: []
  modified:
    - "lib/foglet_bbs/tui/screens/shared/invites_surface.ex"
    - "lib/foglet_bbs/tui/screens/sysop/state.ex"
    - "lib/foglet_bbs/tui/screens/sysop.ex"
    - "lib/foglet_bbs/tui/screens/account.ex"
    - "lib/foglet_bbs/tui/screens/moderation.ex"
    - "lib/foglet_bbs/tui/widgets/chrome/normalizer.ex"
    - "test/foglet_bbs/tui/screens/shared/invites_surface_test.exs"
    - "test/foglet_bbs/tui/screens/sysop_test.exs"
    - "test/foglet_bbs/tui/layout_smoke_test.exs"
    - "test/foglet_bbs/tui/widgets/chrome/normalizer_test.exs"

key-decisions:
  - "D-24 audit: ConsoleTable selection styling is NOT visibly distinct at 80x24 (Raxol Table flattens cell styles into nested style: [{:fg, c}, :fg, c] entries that the ANSI-stripped renderer cannot surface as fg/bg). Step 2 wrapping was required."
  - "D-24 wrapping shape: keep ConsoleTable for layout + column headers (so existing `Code/Status/Created/Used by` assertions in moderation_test pass and column-width truncation still constrains rows at 64x22) and emit a separate focus indicator line below the table that carries `theme.selected.fg/bg`. This is a hybrid — neither pure SelectionList replacement nor pure ConsoleTable — and avoids regressions in the moderation INVITES smoke test."
  - "D-25 placement: `armed_revoke?` lives on `Sysop.State`, not on the shared `InvitesState`. Rationale (option b in plan): Account / Moderation also consume InvitesState; arming is a Sysop-specific UI gesture. Cost: a small accessor (Map.get with default) in maybe_add_revoke."
  - "D-26 chrome priority lift: at 64x22 the chrome's `fit_highest_priority` was dropping the second-listed item in the Tabs group (Jump) before navigation/system. Lifting `@tabs_group` from `@structured_priority` (10) to `@navigation_priority` (0) makes both `←/→ Tab` and `1-N Jump` survive. The pre-existing normalizer test that asserted Tabs priority == 10 was updated."
  - "D-26 normalizer regex: replaces hardcoded `[\"1-5\", \"1-6\"]` with `^1-\\d+$` so Account at 3-4 tabs and any future tab count work without editing the normalizer."

# Metrics
duration: 20min
completed: 2026-04-27
---

# Phase 29 Plan 04: Site Fields & Jump (INVITES Focus, Two-Step Revoke, 1-N Jump) — Summary

**Focus-aware INVITES rendering closes SYSOP-06's "operator can see which row is focused" gap, the two-step `[X] Revoke` gesture wires the existing `InvitesActions.revoke_selected/2` path to a guarded keypress, and `1-N Jump` consistency across Account / Moderation / Sysop closes SYSOP-07 — Phase 29 is fully complete.**

## Performance

- **Duration:** ~20 min
- **Started:** 2026-04-27 21:13 UTC
- **Completed:** 2026-04-27 21:34 UTC
- **Tasks:** 3 (Task 2 was TDD red+green)
- **Files modified:** 10 (4 lib screens, 1 lib widget, 5 test files)
- **Tests:** all 1975 project tests pass; 17 new tests this plan (3 INVITES focus, 8 X revoke gesture, 6 1-N Jump layout smoke + 5 grep guards = wait, that's more — recount below).

## Decision Locations

| Decision | Where it lives | Verification |
|----------|----------------|--------------|
| **D-24 audit + wrap** | `invites_surface.ex` `render_items(%InvitesState{...})` (lines 78-111) — splits empty-list and non-empty paths; non-empty emits ConsoleTable + `focused_invite_indicator/3` | `invites_surface_test.exs` `INVITES focused-row highlight` describe (3 tests) |
| **D-24 focus indicator** | `invites_surface.ex` `defp focused_invite_indicator/3` (lines ~178-194) + `defp focused_row_label/1` — emits a single `text(...)` node with `theme.selected.fg/bg` carrying the focused invite's compact summary | `invites_focus_highlight` test asserts focused row's text node has selected styling and unfocused rows do not |
| **D-25 armed flag** | `sysop/state.ex:74` — `armed_revoke?: false` field on `Sysop.State`. Typespec at line 54. | `[X] Revoke gesture` describe (8 tests) |
| **D-25 Enter handler** | `sysop.ex:264-279` — Enter clause arms when `(active_label, selected_item.status) == ("INVITES", non-:revoked)`; otherwise hands off to `do_handle_key/2` | `Enter on focused non-revoked INVITES row arms` test |
| **D-25 X handler** | `sysop.ex:288-303` — X clause dispatches `InvitesActions.revoke_selected/2` when armed + INVITES; clears flag; otherwise hands off | `X while armed dispatches InvitesActions.revoke_selected/2` test |
| **D-25 `[X] Revoke` advertising** | `sysop.ex:104-130` — `defp maybe_add_revoke/2` appended to `sysop_commands/2` pipe after `maybe_add_retry/2`. Triple-gated: active tab is INVITES, armed_revoke? true, focused row is non-:revoked | `Enter on focused :revoked INVITES row does NOT arm and does NOT advertise Revoke` test |
| **D-25 navigation clear** | `sysop.ex:351-352` (tab switch — `Map.merge` adds `armed_revoke?: false`) and `sysop.ex:381-393` (focus move — clears when InvitesActions returns a different selection_index) | `Moving focus within INVITES clears armed_revoke?` and `Switching tabs clears armed_revoke?` tests |
| **D-26 Account refactor** | `account.ex:65,72-83` — call site uses `key_bar(ss)`; `defp key_bar(ss)` inserts `{jump_hint(N), "Jump"}` between `←/→ Tab` and `Tab Field`; `defp jump_hint(n)` is the helper | `Account command bar contains '1-3 Jump'` and `'1-4 Jump'` tests in `layout_smoke_test.exs` (Phase 29 1-N Jump consistency describe) |
| **D-26 Moderation refactor** | `moderation.ex:126,131-141` — call site uses `key_list(ss)`; `defp key_list(ss)` builds the bar with `1-N Jump` from `tab_labels_from_tabs(ss.tabs)` length | `Moderation command bar contains '1-5 Jump'` and `'1-6 Jump'` tests |
| **D-26 Sysop refactor** | `sysop.ex:62-65` — `jump_hint = "1-#{length(State.tab_labels(ss))}"` replaces the if-expression | `Sysop command bar contains '1-N Jump'` tests |
| **D-26 chrome priority lift** | `widgets/chrome/normalizer.ex:122-129` — `@tabs_group` priority lifted from `@structured_priority` (10) to `@navigation_priority` (0) so the Jump pair survives 64×22 chrome drops | All 6 1-N Jump layout-smoke tests pass at 64×22 and 80×24 |
| **D-26 jump-key regex** | `widgets/chrome/normalizer.ex:99-110` — `tab_command?` replaces `key in ["←/→", "1-5", "1-6"]` with `key == "←/→" or jump_key?(key)`; `jump_key?` matches `^1-\d+$` so any tab count works | Normalizer test `commands/1` updated; new screens (Account at 3-4 tabs) classify correctly |

## Test Counts

| Describe / Block | Count | Status |
|------------------|-------|--------|
| `INVITES focused-row highlight (D-24, SYSOP-06)` (invites_surface_test.exs) | 3 | Green |
| `[X] Revoke gesture (D-25, SYSOP-06)` (sysop_test.exs) | 8 | Green |
| `Phase 29 1-N Jump consistency (D-26, D-27, SYSOP-07)` rendering tests (layout_smoke_test.exs) | 6 | Green |
| `Phase 29 1-N Jump consistency` grep guards (layout_smoke_test.exs) | 5 | Green |
| **New tests this plan** | **22** | **All green** |
| Existing test updates | 1 | normalizer_test.exs Tabs priority 10 → 0 |
| Full TUI suite | 1431 | Green |
| Full project suite | 1975 | Green |

## Confirmations

- **`{"1-6", "Jump"}` literal grep:** `grep -F '{"1-6", "Jump"}' lib/foglet_bbs/tui/screens/{account,moderation}.ex` returns 0 lines.
- **`if "INVITES" in State.tab_labels` grep:** `grep -n` against `sysop.ex` returns 0 lines.
- **`@key_bar` / `@key_list` module attributes:** removed from `account.ex` and `moderation.ex` (verified by grep guards).
- **No `▸` marker rendered:** `grep -n "▸" lib/foglet_bbs/tui/screens/shared/invites_surface.ex` returns 0 lines (D-24 explicit rejection).
- **No new revoke logic in invites_actions.ex:** `git diff HEAD~3 lib/foglet_bbs/tui/screens/shared/invites_actions.ex` returns 0 lines. The existing `revoke_selected/2` is the only side-effect path.
- **InvitesState unchanged:** D-25 placement option (b) — armed flag lives on `Sysop.State` only.

## Task Commits

Tasks committed atomically:

1. **Task 1: INVITES focus highlight** — `cc7af5c` (feat)
2. **Task 2 (RED):** `ad559e0` — `test(29-04): add failing tests for [X] Revoke gesture`
3. **Task 2 (GREEN):** `5f1fc32` — `feat(29-04): two-step [X] Revoke gesture`
4. **Task 3: 1-N Jump consistency** — `1af951b` (feat)

Note: Task 1's RED test (the audit-failure assertion) is not split into a separate commit — the test was added together with the GREEN wrapping fix in the same commit because the test would have passed on its own (the audit was a check, not a behavioral test). The plan's Task 1 description explicitly anticipated either path ("Step 1 — Audit" / "Step 2 — Add focus-row wrapping ... only if audit fails").

## Files Created/Modified

**Created:** none

**Modified:**

- `lib/foglet_bbs/tui/screens/shared/invites_surface.ex` — Split `render_items(%InvitesState{})` into empty-list (preserves ConsoleTable empty-state) and non-empty paths. Non-empty path emits ConsoleTable + new `focused_invite_indicator/3` line in `theme.selected.fg/bg`.
- `lib/foglet_bbs/tui/screens/sysop/state.ex` — Added `armed_revoke?: false` field with typespec; documents the two-step revoke gesture lifecycle inline.
- `lib/foglet_bbs/tui/screens/sysop.ex` — Added `:enter` handler that arms on focused non-revoked INVITES row; added `c in ["x", "X"]` handler that dispatches existing revoke when armed; `sysop_commands/2` now pipes through `maybe_add_retry |> maybe_add_revoke`; tab-switch and focus-move clear `armed_revoke?`. Refactored `jump_hint` from INVITES if-expression to `"1-#{length(State.tab_labels(ss))}"`.
- `lib/foglet_bbs/tui/screens/account.ex` — Removed `@key_bar` module attribute; added `defp key_bar(ss)` and `defp jump_hint(n)` helpers; render call-site uses `key_bar(ss)`.
- `lib/foglet_bbs/tui/screens/moderation.ex` — Removed `@key_list` module attribute; added `defp key_list(ss)` and `defp jump_hint(n)` helpers; render call-site uses `key_list(ss)`.
- `lib/foglet_bbs/tui/widgets/chrome/normalizer.ex` — Lifted `@tabs_group` priority to `@navigation_priority`; replaced hardcoded `[\"1-5\", \"1-6\"]` jump-key list with `^1-\d+$` regex via `jump_key?/1` helper.
- `test/foglet_bbs/tui/screens/shared/invites_surface_test.exs` — New `INVITES focused-row highlight` describe (3 tests) + private tree-walking helpers `find_text_nodes_containing/2` and `has_selected_styling?/2`.
- `test/foglet_bbs/tui/screens/sysop_test.exs` — New `[X] Revoke gesture` describe (8 tests) + private helpers `build_invites/2`, `activate_invites/3`, `count_revoke_tokens/1`.
- `test/foglet_bbs/tui/layout_smoke_test.exs` — New `Phase 29 1-N Jump consistency` describe with 6 rendering tests (3 screens × INVITES visible/hidden) at both 64×22 and 80×24, plus 5 grep guards (no `@key_bar`, no `@key_list`, no `{"1-6", "Jump"}` literal in account/moderation, sysop jump_hint pattern).
- `test/foglet_bbs/tui/widgets/chrome/normalizer_test.exs` — Updated existing `commands/1` test assertion: `Tabs` group priority 10 → 0 (D-27 chrome priority lift).

## Decisions Made

- **D-24 audit outcome — wrapping was required.** The plan anticipated either the audit passing (no code change) or failing (Step 2 wrapping). The audit failed because Raxol's upstream `Table.create_cells/7` flattens the `selected_row` style into `style: [{:fg, c}, :fg, c]` nested-list entries on the text node, rather than setting top-level `:fg` / `:bg`. After ANSI stripping in the test harness this is not visibly distinct from `theme.row.fg`. The fix wraps the focused row's content in an additional explicit `text(label, fg: theme.selected.fg, bg: theme.selected.bg)` line below the table.
- **D-24 hybrid render shape (vs. full SelectionList replacement).** The pattern map suggested mirroring UsersView's bespoke-row idiom directly. That would have removed the ConsoleTable header text, breaking `moderation_test.exs:798` ("INVITES tab renders ConsoleTable header with Code/Status/Created/Used by columns"). The hybrid (ConsoleTable for layout + bespoke focus indicator) preserves both contracts.
- **D-25 armed flag on Sysop.State (option b).** Plan recommended option b. Confirmed by audit: `InvitesState` is consumed by Account / Moderation (`InvitesSurface.render(ss.invites, theme)`) and arming is a Sysop-only gesture. Putting it on InvitesState would have required Account / Moderation to suppress the flag in their own arming-clear paths. Option b keeps the cross-cutting concern in the surface that owns it.
- **D-25 X handler hands off when not armed.** Mirrors the `[R] Retry` `do_handle_key/2` hand-off from Plan 02 (deviation 2 in 29-02-SUMMARY.md). Returning `:no_match` from a function clause does NOT fall through to the next clause — Elixir resolves clauses by pattern-match. The `do_handle_key(event, state)` hand-off ensures X on a non-armed INVITES tab still flows through the broader screen logic (relevant if a future feature ever rebinds X to something else).
- **D-27 chrome priority lift (vs. layout reflow).** Considered alternatives: (a) shorten group labels at 64×22, (b) merge Tabs and Field into a single Navigation group, (c) raise Jump-key priority specifically (not the whole Tabs group). Settled on lifting the entire Tabs group because both `←/→ Tab` and `1-N Jump` are equally important at the smallest size, and the group abstraction keeps related items together. The cost is the existing normalizer test had to update from priority 10 to 0 — a single literal change.
- **D-26 normalizer regex generalisation.** The pattern map suggested matching `1-5` / `1-6` only because Sysop / Moderation are the only screens that emit them. Account at 3 or 4 tabs introduces new `1-N` values. Replacing the hardcoded list with `^1-\d+$` avoids future edits when a tab is added or removed.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking] Worktree base mismatch + missing deps/_build symlinks**
- **Found during:** Worktree initial check
- **Issue:** `git merge-base HEAD <expected>` returned `3226ef9...` instead of `8f8646f...`; symlinks for `deps/` and `_build/` were absent.
- **Fix:** `git reset --hard 8f8646f` (per worktree_branch_check protocol); symlinked `deps/` and `_build/` from parent repo (consistent with Plans 01-03 prior worktree setup).
- **Committed in:** None (filesystem-only).

**2. [Rule 1 — Bug] D-24 audit outcome — Step 2 wrapping required**
- **Found during:** Task 1 RED audit assertion
- **Issue:** First-pass test (assert focused row's text token carries `theme.selected.fg/bg`) failed — the focused row had `fg: nil, bg: nil` and `style: [{:fg, "#cccccc"}, :fg, "#cccccc"]` (the unselected `theme.row.fg`). Root cause: Raxol's `Table.create_cells/7` flattens both row and selected-row styles into the nested `:style` list rather than top-level `:fg`/`:bg`, AND it applies the unselected style when the underlying `selected_row` doesn't match (InvitesState's `selected_index` is not propagated to the ConsoleTable's `selected_row` — the table's internal cursor stays at 0 unless arrow-key navigated).
- **Fix:** Added `focused_invite_indicator/3` to emit an explicit selected-styled text line below the table.
- **Files modified:** `lib/foglet_bbs/tui/screens/shared/invites_surface.ex`.
- **Verification:** All 3 focus-highlight tests pass; existing moderation INVITES test (`Code`/`Status`/`Created`/`Used by` header presence) still passes; layout-smoke INVITES bounds test at 64×22 / 80×24 still passes.
- **Committed in:** `cc7af5c` (Task 1).

**3. [Rule 1 — Bug] Chrome dropping `1-N Jump` at 64×22 due to priority/order tie**
- **Found during:** Task 3 GREEN — running new layout-smoke tests for the first time
- **Issue:** At 64×22 (and even 80×24 in the Account case) the rendered chrome had `Tabs ←/→ Tab` but no `1-N Jump`. Root cause: `CommandBar.fit_highest_priority/2` drops items by descending `{priority, order}` when the rendered width exceeds the budget. With both `←/→ Tab` and `1-N Jump` at `@structured_priority` (10), the tie-break by `:order` dropped Jump first.
- **Fix:** Lifted `@tabs_group` priority from `@structured_priority` to `@navigation_priority` so the navigation cluster is preserved over Field/Save/Refresh.
- **Files modified:** `lib/foglet_bbs/tui/widgets/chrome/normalizer.ex`.
- **Verification:** All 6 1-N Jump layout-smoke tests pass at both terminal sizes.
- **Committed in:** `1af951b` (Task 3).

**4. [Plan refinement] Existing normalizer test asserted Tabs priority == 10**
- **Found during:** Task 3 GREEN — full normalizer_test.exs run
- **Issue:** `commands/1` test in `normalizer_test.exs:39` asserted `group(groups, "Tabs") == [%{key: "←/→", label: "Switch tab", priority: 10}]`. After the priority lift, the value is 0.
- **Fix:** Updated the assertion's `priority: 10` to `priority: 0` with an inline comment explaining D-27.
- **Files modified:** `test/foglet_bbs/tui/widgets/chrome/normalizer_test.exs`.
- **Committed in:** `1af951b` (Task 3).

**5. [Plan refinement] Hardcoded `1-5` / `1-6` in normalizer would have rejected Account 1-3 / 1-4**
- **Found during:** Task 3 GREEN — running new Account layout-smoke tests after the @key_bar refactor
- **Issue:** `tab_command?/2` only matched `["←/→", "1-5", "1-6"]`. Account at 3 tabs (INVITES hidden) emits `1-3`, which fell through to `actions_group` rather than `tabs_group`. The Actions group renders at action_priority (30), so it was dropped early at 64×22.
- **Fix:** Replaced the literal list with `^1-\d+$` regex via `jump_key?/1`.
- **Files modified:** `lib/foglet_bbs/tui/widgets/chrome/normalizer.ex`.
- **Verification:** Account 1-3 and 1-4 tests pass at 64×22 and 80×24.
- **Committed in:** `1af951b` (Task 3).

**6. [Plan refinement] Comment-string in moderation.ex tripped grep guard**
- **Found during:** Task 3 GREEN — full layout_smoke_test.exs run
- **Issue:** The new `key_list/1` had a leading comment that said `The literal {"1-6", "Jump"} no longer appears in this module — verified by grep test`. The grep guard `refute String.contains?(contents, ~s|{"1-6", "Jump"}|)` matched the comment.
- **Fix:** Rewrote the comment to describe the contract without using the literal token form.
- **Files modified:** `lib/foglet_bbs/tui/screens/moderation.ex`.
- **Committed in:** `1af951b` (Task 3).

---

**Total deviations:** 6 (1 environmental, 2 audit-outcome bug fixes, 3 plan refinements / mechanical adjustments).
**Impact on plan:** None on scope. The audit outcome (deviation 2) was anticipated as one of two valid paths in the plan. The chrome priority lift (deviation 3) was the only surprise discovery, and it's a correctness fix rather than a scope change — without it the SYSOP-07 acceptance criterion (`1-N Jump` substring present at 64×22) couldn't be met.

## Issues Encountered

- **Worktree base mismatch on startup.** Recovered with `git reset --hard` per protocol.
- **Sigil delimiter conflicts in grep-guard tests.** Strings like `{"1-6", "Jump"}` and `if "INVITES" in State.tab_labels` contain quotes / parens that conflict with `~s(...)` and `~S(...)` delimiters. Switched to pipe-delimited `~s|...|` forms throughout the new layout-smoke describe.
- **Pre-existing typing-violation warning in sysop_test.exs.** Line 2310 has a `assert snap != nil` against a non-nullable struct type, which Elixir 1.19's typing emits as a warning. Pre-existing, unrelated to Plan 04 — left as-is.

## User Setup Required

None.

## Next Plan Readiness

**Phase 29 closes with this plan.** All SYSOP-01..07 requirements covered by Plans 01-04:
- SYSOP-01 / SYSOP-02 — tagged-enum lifecycle, App-level load triad, retry advertising / dispatch (Plans 01-02)
- SYSOP-03 — SiteForm draft echo + Saved./Esc-reseed (delivered by Phase 28; verified by Plan 03)
- SYSOP-04 — Site field description rewrites (Plan 03)
- SYSOP-05 — USERS keybind gating + from→to copy (Plan 02)
- SYSOP-06 — INVITES focus highlight + two-step `[X] Revoke` (this plan)
- SYSOP-07 — `1-N Jump` consistency across Account/Moderation/Sysop (this plan)

The orchestrator should run the wave-3 close-out: update `.planning/STATE.md` (advance to next phase), `.planning/ROADMAP.md` (Phase 29 progress to 100%), `.planning/REQUIREMENTS.md` (mark SYSOP-06 / SYSOP-07 complete), and the per-phase tracking artifacts.

## Threat Flags

No new security-relevant surface introduced beyond the threat model. T-29-13..T-29-16 mitigations all in place:

- **T-29-13 (Tampering — X without Enter):** mitigated. The X handler in `sysop.ex:288-303` guards on `Map.get(ss, :armed_revoke?, false) == true`. Without prior arming, X is a no-op (hands off to `do_handle_key/2`, where the broader screen logic does not bind X). Verified by `X while not armed is a no-op` test.
- **T-29-14 (Tampering — concurrent revoke race):** accepted. `InvitesActions.revoke_selected/2` already handles the already-revoked case at the boundary. UI just routes to the existing path; no new race introduced.
- **T-29-15 (EoP — armed flag persistence):** mitigated. `armed_revoke?` lives in `state.screen_state[:sysop]` (in-memory per-session). SSH disconnect clears the state. AGENTS.md persistence rule: ETS / process state is ephemeral.
- **T-29-16 (EoP — hidden Revoke keybind as authorization):** mitigated. The X dispatch routes to `InvitesActions.revoke_selected/2` which calls `Foglet.Accounts.Invites.revoke_invite/2` server-side; the boundary re-checks the actor's authorization regardless of UI gating. Same pattern as T-29-05 (Plan 02).

## Self-Check: PASSED

All claimed files exist; all task commits present in `git log`.

```
FOUND: lib/foglet_bbs/tui/screens/shared/invites_surface.ex
FOUND: lib/foglet_bbs/tui/screens/sysop/state.ex
FOUND: lib/foglet_bbs/tui/screens/sysop.ex
FOUND: lib/foglet_bbs/tui/screens/account.ex
FOUND: lib/foglet_bbs/tui/screens/moderation.ex
FOUND: lib/foglet_bbs/tui/widgets/chrome/normalizer.ex
FOUND: test/foglet_bbs/tui/screens/shared/invites_surface_test.exs
FOUND: test/foglet_bbs/tui/screens/sysop_test.exs
FOUND: test/foglet_bbs/tui/layout_smoke_test.exs
FOUND: test/foglet_bbs/tui/widgets/chrome/normalizer_test.exs
FOUND: cc7af5c — feat(29-04): focus-aware INVITES surface (D-24, SYSOP-06)
FOUND: ad559e0 — test(29-04): add failing tests for [X] Revoke gesture (D-25, SYSOP-06)
FOUND: 5f1fc32 — feat(29-04): two-step [X] Revoke gesture (D-25, SYSOP-06)
FOUND: 1af951b — feat(29-04): 1-N Jump consistency across Account/Moderation/Sysop (D-26, D-27, SYSOP-07)
```

---
*Phase: 29-sysop-tab-lifecycle-bodies*
*Completed: 2026-04-27*
