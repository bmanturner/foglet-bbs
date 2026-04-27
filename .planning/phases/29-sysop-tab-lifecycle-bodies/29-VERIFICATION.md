---
phase: 29-sysop-tab-lifecycle-bodies
verified: 2026-04-27T21:47:03Z
status: human_needed
score: 8/8 must-haves verified
overrides_applied: 0
requirements_verified:
  - SYSOP-01
  - SYSOP-02
  - SYSOP-03
  - SYSOP-04
  - SYSOP-05
  - SYSOP-06
  - SYSOP-07
test_results:
  total: 1975
  failures: 0
  property_tests: 1
human_verification:
  - test: "SSH into the BBS as a sysop user, navigate to the Sysop screen, and switch through Boards / Limits / System / Users tabs"
    expected: "Each tab auto-loads on entry without any 'Press any key to load' gating; loaded data renders with no manual key required."
    why_human: "Live SSH session with real Repo and PubSub — the auto-load + render path involves Raxol command runtime, the SSH channel, and ANSI styling that integration tests stub. Visual confirmation needed at the terminal."
  - test: "Force a load failure on a Sysop tab (e.g. simulate a transient DB error or run as a non-sysop) and observe the rendered tab body"
    expected: "Non-forbidden errors render 'Could not load <tab>. Press R to retry.' with `[R] Retry` in the command bar; pressing R re-dispatches and clears the error. `:forbidden` errors render 'Insufficient role to view this tab.' with no `[R] Retry` advertising."
    why_human: "Distinguishing the forbidden panel copy from the generic-error panel copy at 80×24 SSH requires visual confirmation; the colors (theme.warning.fg vs theme.error.fg) only matter in a live ANSI terminal."
  - test: "On Sysop Site, focus a field, type/cycle to a draft value, confirm the displayed value echoes the draft (not the saved Config), then press Enter and observe a `Saved.` confirmation row"
    expected: "Draft echo while focused; Enter persists via `Foglet.Config.put/3`; `Saved.` row appears for one render cycle then resets to idle. Pressing Esc on a dirtied field reverts the displayed value to the saved Config value with no `discarded` copy. Esc does not navigate."
    why_human: "Visual draft echo, the one-cycle Saved. flicker, and the absence of a discard status row are all rendered behaviors best confirmed in a live SSH session."
  - test: "On Sysop Users, focus a row whose status is `:active` and inspect the command-bar footer; then press A"
    expected: "`[A] Approve` is NOT advertised on `:active` rows (only `[S] Suspend` shows). Pressing A is a no-op (status_message stays nil, no boundary call). Triggering a stale-row `:invalid_transition` boundary error renders `Cannot change @<handle> from <from> to <to>.` — never the substring `invalid_transition`."
    why_human: "Operator-facing copy and per-row keybind advertising depend on layout/wrapping decisions that materialize only at the terminal."
  - test: "On Sysop Invites at 80×24 SSH, move focus across rows; observe the focused row's visible distinction; press Enter then X"
    expected: "Focused row highlighted via theme.selected.fg/bg distinguishable from unfocused rows. Enter on a non-:revoked focused row reveals `[X] Revoke` in the command bar. X dispatches the existing `InvitesActions.revoke_selected/2` path. Moving focus or switching tabs clears the armed state and the `[X] Revoke` advertisement disappears."
    why_human: "ANSI styling distinction at 80×24 is ANSI-stripped in the harness; the focus indicator's visible appearance must be confirmed on a real terminal."
  - test: "Open Account, Moderation, and Sysop screens at both 64×22 and 80×24 SSH"
    expected: "Each screen's command bar advertises a `1-N Jump` group where N matches the visible tab count for the actor. No hardcoded `1-6` literal appears when only 5 tabs are visible. The `←/→ Tab` and `1-N Jump` pair survive at 64×22 (chrome priority lift)."
    why_human: "Layout smoke tests assert the substring is present, but visual placement / overflow at 64×22 across all three screens is best confirmed in a live SSH session."
---

# Phase 29: Sysop Tab Lifecycle Bodies Verification Report

**Phase Goal:** Sysop tabs auto-load on entry through `Foglet.TUI.Command`, render distinct loading/error/loaded states with a `[R] Retry` keybind on errors, and Sysop Site/Users/Invites surfaces actually function for an operator.

**Verified:** 2026-04-27T21:47:03Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (Roadmap Success Criteria)

| # | Truth (Success Criterion) | Status | Evidence |
|---|---------------------------|--------|----------|
| 1 | Sysop tabs (Boards/Limits/System/Users) auto-dispatch load on tab switch / digit jump exactly once, no "Press any key to load" gating; loaded data renders. | ✓ VERIFIED | `grep -n "Press any key" lib/foglet_bbs/tui/screens/sysop.ex` returns 0 lines. `app.ex` exposes 4 `do_update({:load_sysop_*}, _)` dispatch clauses (lines 555/576/589/601), 8 result clauses (lines 612–633), and `put_sysop_loading/loaded/error` helpers (lines 1236/1239/1242). `sysop.ex` has `maybe_dispatch_lifecycle_load` + idempotent `:not_loaded`-guarded dispatch in the tab-changed branch. `delegate_to_submodule/5` requires `{:loaded, sub}` per D-09. Tests: `lifecycle tagged-enum`, `render_tab_body lifecycle`, `delegate_to_submodule guard`, tab-switch dispatch describes — all green. |
| 2 | Simulated load failure renders honest error + `[R] Retry`; `{:error, :forbidden}` renders distinct "Insufficient role" panel. | ✓ VERIFIED | `sysop.ex:145` advertises `%{key: "R", label: "Retry", priority: 5}` via `maybe_add_retry/2` (line 138) — guarded on `match?({:error, reason}, _) and reason != :forbidden`. R-keypress handler at line 237 re-dispatches `{:load_sysop_*}` via `dispatch_for/1`. `forbidden_panel/1` at line 247 emits `"Insufficient role to view this tab."` in `theme.warning.fg`; `error_panel/2` at line 253 emits `"Could not load <tab>. Press R to retry."` in `theme.error.fg`. Pattern-match order matches forbidden BEFORE generic in all 4 lifecycle clauses (lines 200/210/220/230 — Pitfall 3). Tests: `[R] Retry advertising` (3 tests) and `[R] Retry dispatch` (5 tests) green. |
| 3 | Sysop Site: focused field types echo draft (not saved Config); Enter persists via `Foglet.Config.put/3` with inline confirm; Esc resets draft to saved; Site field subtitles contain no REQ-IDs / phase refs / internal planning notes. | ✓ VERIFIED | `site_form.ex:206` calls `Modal.Form.set_submit_state(form, :saved)` on the all-keys-success branch; `validate_delivery_verification_pair/1` is the on_submit pre-flight; `SState.reseed_drafts/1` reloads from `Config.get!/1` on Esc. `site_form.ex` contains zero `status_message` references. Schema descriptions for the 5 `@site_keys` (`registration_mode`, `invite_code_generators`, `delivery_mode`, `require_email_verification`, `invite_generation_per_user_limit`) are operator-facing copy: lines 54/63/90/99/118 — no `(D-XX)`, `(MAIL-XX)`, `(Phase X)`, `(INVT-XX)`, or `deliverable` tokens. `Foglet.Config.SchemaTest` + Phase 29 SiteForm regression suite (6 tests across "Enter persistence" and "Esc reseed" describes) green. |
| 4 | Sysop Users: `:approved` (`:active`) user does not advertise `[A] Approve`; disallowed transitions show user-facing copy not raw `:invalid_status_transition`. | ✓ VERIFIED | `users_view.ex:153` builds `footer_text/1` from `Accounts.valid_status_transitions(focused_status)`; `[A] Approve` is gated on `focused_status == :pending and :active in allowed`. `maybe_transition/3` at line 114 enforces source-status gating — pressing A on `:active` is a no-op. `invalid_transition_message/3` at line 287 emits `"Cannot change @#{handle} from #{from} to #{to}."` — `users_from_to_copy` describe asserts no `"invalid_transition"` substring leaks. `Accounts.valid_status_transitions/1` is public (lines 217–220, 4 clauses) with 4 unit tests green. |
| 5 | Sysop Invites at 80x24 SSH: focused row highlight changes; Enter on focused row reveals row-level actions (e.g. `[X] Revoke`) in command bar. | ✓ VERIFIED | `invites_surface.ex:183` emits `focused_invite_indicator/3` with `theme.selected.fg/bg`. `Sysop.State` has `armed_revoke?: false` field (state.ex:54/74). `sysop.ex:264-279` arms on Enter when active tab is INVITES + focused row not `:revoked`. `sysop.ex:127` advertises `%{key: "X", label: "Revoke", priority: 5}` via `maybe_add_revoke/2` (line 113) — triple-gated (active = INVITES, armed = true, focused row not `:revoked`). `sysop.ex:298` dispatches `InvitesActions.revoke_selected(state.current_user, ss.invites)`. Navigation/focus moves clear `armed_revoke?` per Plan 04 D-25 implementation. Tests: `[X] Revoke gesture` describe (8 tests) + `INVITES focused-row highlight` describe (3 tests) green. |
| 6 | Command bar on Account, Moderation, Sysop consistently advertises `1-N Jump` group at both 64x22 and 80x24 SSH. | ✓ VERIFIED | `account.ex:72` defines `defp key_bar(ss)` with `{jump_hint(N), "Jump"}` between Tab and Field; `moderation.ex:132` defines `defp key_list(ss)`; both modules expose `defp jump_hint(n) when is_integer(n) and n > 0, do: "1-#{n}"` (account.ex:83, moderation.ex:140). Sysop's `jump_hint = "1-#{length(State.tab_labels(ss))}"` replaces the prior INVITES special-case. `chrome/normalizer.ex:105` uses `defp jump_key?(key) when is_binary(key), do: Regex.match?(~r/^1-\d+$/, key)` — no hardcoded `["1-5", "1-6"]` literal. Chrome `@tabs_group` priority lifted to `@navigation_priority` so `1-N Jump` survives 64×22. Tests: `Phase 29 1-N Jump consistency (D-26, D-27, SYSOP-07)` describe in `layout_smoke_test.exs:2358` (6 rendering tests + 5 grep guards) green. |
| 7 (PLAN) | No `Raxol.Core.Runtime.Command.task` literal under `lib/foglet_bbs/tui/screens/sysop/` or `sysop.ex` (D-04). | ✓ VERIFIED | `grep -rE "Raxol\.Core\.Runtime\.Command\.task" lib/foglet_bbs/tui/screens/sysop.ex lib/foglet_bbs/tui/screens/sysop/` returns 0 lines. All task wrapping happens via `Foglet.TUI.Command.task/2` in `app.ex` (4 occurrences). |
| 8 (PLAN) | Re-entering a `{:loaded, _}` tab is idempotent — no second dispatch is emitted. | ✓ VERIFIED | `dispatch_if_not_loaded/3` in `sysop.ex` only emits a command when slot is `:not_loaded`; `maybe_dispatch_initial_sysop_load/1` in `app.ex` mirrors the guard. Tab-switch dispatch describe asserts idempotent re-entry. |

**Score:** 8/8 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/foglet_bbs/tui/screens/sysop/state.ex` | Tagged-enum `lifecycle/1` typespec; `:not_loaded` defaults; `armed_revoke?` field | ✓ VERIFIED | Lines 54/63–66/74; all 4 lifecycle slots default `:not_loaded`; `armed_revoke?` typespec + defstruct present |
| `lib/foglet_bbs/tui/app.ex` | 4 dispatch + 8 result + 5 helper functions for the Sysop load triad | ✓ VERIFIED | Dispatch lines 555/576/589/601; result lines 612–633; helpers lines 1236/1239/1242 + `update_sysop_slot`/`sysop_screen_state` |
| `lib/foglet_bbs/tui/screens/sysop.ex` | `render_tab_body` lifecycle pattern-match; `delegate_to_submodule` `{:loaded, _}` guard; `maybe_add_retry/2`; `maybe_add_revoke/2`; `R` & `X` keypress handlers; `jump_hint = "1-#{length(State.tab_labels(ss))}"` | ✓ VERIFIED | All confirmed via grep at expected locations; D-04 enforcement clean |
| `lib/foglet_bbs/tui/screens/sysop/users_view.ex` | render-time `footer_text/1`; `maybe_transition/3` source-status gate; `invalid_transition_message/3` | ✓ VERIFIED | Lines 114/146/153/266/287/288; `[A] Approve` advertised only when `focused_status == :pending` |
| `lib/foglet_bbs/accounts.ex` | Public `valid_status_transitions/1` (4 clauses, derived from `permit_status_transition/2`) | ✓ VERIFIED | Lines 215/217/218/219/220; placed adjacent to private `permit_status_transition/2` (lines 203–212) |
| `lib/foglet_bbs/config/schema.ex` | 5 `@site_keys` descriptions rewritten as user-facing copy | ✓ VERIFIED | Lines 54/63/90/99/118 — exact target literals present |
| `lib/foglet_bbs/tui/screens/sysop/site_form.ex` | `set_submit_state(form, :saved)`, `validate_delivery_verification_pair`, no `status_message` | ✓ VERIFIED | Line 206 sets `:saved`; pre-flight via SState; zero `status_message` occurrences |
| `lib/foglet_bbs/tui/screens/shared/invites_surface.ex` | Focused-row indicator using `theme.selected.fg/bg` | ✓ VERIFIED | Line 183 + line 196 emit selected-styled text node; no `▸` marker (D-24 rejection honored) |
| `lib/foglet_bbs/tui/screens/account.ex` | render-time `key_bar(ss)` with `1-N Jump` group | ✓ VERIFIED | Line 72 (`defp key_bar(ss)`) + line 83 (`defp jump_hint(n)`); no `@key_bar` module attribute |
| `lib/foglet_bbs/tui/screens/moderation.ex` | render-time `key_list(ss)` with `1-N Jump` group | ✓ VERIFIED | Line 132 (`defp key_list(ss)`) + line 140 (`defp jump_hint(n)`); no `@key_list` module attribute |
| `lib/foglet_bbs/tui/widgets/chrome/normalizer.ex` | `^1-\d+$` regex via `jump_key?/1`; `@tabs_group` lifted to navigation priority | ✓ VERIFIED | Line 98/105/106; replaces hardcoded `["1-5", "1-6"]` |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| `sysop.ex` tab-changed branch | `{:load_sysop_*}` dispatch tuple | `maybe_dispatch_lifecycle_load/2` | ✓ WIRED | Returns `{ss', commands}`; dispatch tuple flows into `process_screen_commands/2` |
| `app.ex do_update({:load_sysop_*}, state)` | `Foglet.TUI.Command.task/2` | bound `user`/`accounts_mod` outside closure (Pitfall 8) | ✓ WIRED | Lines 549–565 (users), parallel for boards/limits/system |
| `app.ex do_update({:sysop_*_loaded, _}, state)` | `put_sysop_loaded/3` or `put_sysop_error/3` | result-tuple pattern match | ✓ WIRED | 8 result clauses confirmed at lines 612–633 |
| `users_view.ex` render-time footer | `Accounts.valid_status_transitions/1` | aliased call | ✓ WIRED | Lines 114/153 |
| `sysop.ex` R keypress | `{:load_sysop_*}` via App | `dispatch_for/1` | ✓ WIRED | Active-tab + slot inspection emits matching dispatch tuple |
| `users_view.ex` `{:error, :invalid_transition}` branch | `invalid_transition_message/3` | case-match in `transition/2` | ✓ WIRED | Line 266 binds focused-row `from`/target `to`/handle |
| Sysop INVITES Enter handler | `ss.armed_revoke?` | direct map update on Sysop.State | ✓ WIRED | Line 275 (true) + line 295 (X consumes flag) |
| Sysop X keypress (when armed) | `InvitesActions.revoke_selected/2` | guarded clause | ✓ WIRED | Line 298 |
| `sysop_commands/2` | `maybe_add_revoke/2` | pipe step after `maybe_add_retry/2` | ✓ WIRED | Lines 103–104 |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|---------------------|--------|
| `Sysop.render_tab_body("USERS", ss, theme)` | `ss.users_view` | `Foglet.Accounts.list_user_status_admin_targets/1` via `app.ex:558` task closure | Yes — DB-backed `Accounts` module returns real groups; `UsersView.from_groups/2` shapes payload | ✓ FLOWING |
| `Sysop.render_tab_body("BOARDS"`, _, _)` | `ss.boards_view` | `BoardsView.init(current_user: user)` invoked inside task closure (`app.ex:579`) | Yes — `BoardsView.init/1` reads from Boards/Categories contexts | ✓ FLOWING |
| `SiteForm.render` | `state.drafts` | `SState.reseed_drafts/1` → `Foglet.Config.get!/1` | Yes — ETS-backed Config cache | ✓ FLOWING |
| `InvitesSurface.render_items` | `ss.invites.rows` | InvitesActions/list flow (unchanged in this phase) | Yes (pre-existing path) | ✓ FLOWING |
| `Sysop.sysop_commands(ss, jump_hint)` | `length(State.tab_labels(ss))` | `Sysop.State.tab_labels/1` derived from operator scope | Yes — actor-derived tab list | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Full Mix test suite passes | `rtk mix test` | `1 property, 1975 tests, 0 failures` | ✓ PASS |
| Compile clean with warnings-as-errors | `rtk mix compile --warnings-as-errors` | exit 0 (only vendored Mogrify warning, unrelated) | ✓ PASS |
| Zero "Press any key" literals in sysop.ex | `grep -n "Press any key" lib/foglet_bbs/tui/screens/sysop.ex` | 0 matches | ✓ PASS |
| `valid_status_transitions/1` exposed | `grep -n "def valid_status_transitions" lib/foglet_bbs/accounts.ex` | 4 public clauses (lines 217–220) | ✓ PASS |
| `[R] Retry` advertised on errored slots | `grep 'key: "R", label: "Retry"' lib/foglet_bbs/tui/screens/sysop.ex` | line 145 — gated by `maybe_add_retry/2` | ✓ PASS |
| `[X] Revoke` armed flow in invites surface | `grep 'key: "X", label: "Revoke"' lib/foglet_bbs/tui/screens/sysop.ex` | line 127 — gated by `maybe_add_revoke/2` | ✓ PASS |
| `1-N Jump` regex in normalizer | `grep 'jump_key' lib/foglet_bbs/tui/widgets/chrome/normalizer.ex` | line 105 — `Regex.match?(~r/^1-\d+$/, key)` | ✓ PASS |
| D-04 grep gate (no direct Raxol task in Sysop) | `grep -rE "Raxol\.Core\.Runtime\.Command\.task" lib/foglet_bbs/tui/screens/sysop.ex lib/foglet_bbs/tui/screens/sysop/` | 0 matches | ✓ PASS |
| All 5 `@site_keys` descriptions clean | manual inspection of `lib/foglet_bbs/config/schema.ex:54,63,90,99,118` | all 5 read as user-facing copy with no planning IDs | ✓ PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| SYSOP-01 | 29-01 | Sysop tabs auto-load on tab switch via `Foglet.TUI.Command`, no "Press any key" gating | ✓ SATISFIED | Truth #1 verified — load triad + tab-switch + first-entry dispatch all in place |
| SYSOP-02 | 29-01, 29-02 | Tagged `:not_loaded\|:loading\|{:loaded, _}\|{:error, _}` lifecycle with honest error + `[R] Retry` | ✓ SATISFIED | Truths #1 + #2 verified |
| SYSOP-03 | 29-03 | Sysop Site editable: draft echo, Enter→`Config.put/3` confirm, Esc reseed | ✓ SATISFIED | Truth #3 verified — Phase 28 substrate + Phase 29 regression tests |
| SYSOP-04 | 29-03 | Site field subtitles user-facing operator copy, no planning notes/REQ-IDs | ✓ SATISFIED | Truth #3 verified — schema regex test enforces invariant |
| SYSOP-05 | 29-02 | Users tab keybind gating + `:invalid_status_transition` mapped to user-facing copy | ✓ SATISFIED | Truth #4 verified |
| SYSOP-06 | 29-04 | Invites tab row-level focus + Enter reveals contextual actions (Revoke) | ✓ SATISFIED | Truth #5 verified |
| SYSOP-07 | 29-04 | All tabbed screens advertise consistent `1-N Jump` group | ✓ SATISFIED | Truth #6 verified |

All 7 requirement IDs accounted for; no orphaned IDs (REQUIREMENTS.md `Phase 29` section maps exactly SYSOP-01..SYSOP-07).

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `test/foglet_bbs/tui/screens/sysop_test.exs` | 2310 | `assert snap != nil` against non-nullable struct (Elixir 1.19 typing-violation warning) | ℹ️ Info | Pre-existing assertion; documented in 29-04-SUMMARY.md as unrelated to Phase 29. Not a blocker. |
| `lib/foglet_bbs/config/schema.ex` | 72, 81, 108–109 | Non-`@site_keys` entries (`max_post_length`, `max_thread_title_length`, `email_verify_resend_cooldown_seconds`) still contain `(D-31)`, `(D-13, phase-03-polish Phase 4)`, `(Phase 6 D-02)` | ℹ️ Info | These keys are NOT in `@site_keys` — out of scope per Plan 03 (`SiteForm.State.@site_keys` is the 5-key set the regex test guards). Documented as future hygiene work. |

No blockers; no unintended stub patterns; no TODO/FIXME comments introduced.

### Human Verification Required

Six items routed to live SSH UAT — see `human_verification:` block in the YAML frontmatter for the full structured list. They cover:

1. Live tab-switch auto-load on the four lifecycle Sysop tabs.
2. Forbidden vs generic error panel visual distinction + `[R] Retry` keypress at 80×24.
3. Sysop Site draft echo + `Saved.` flicker + Esc revert behavior.
4. USERS tab `[A] Approve` gating on `:active` rows + from→to error copy on stale-row failures.
5. INVITES focus-row visual distinction + two-step `[X] Revoke` gesture + clear-on-navigation.
6. `1-N Jump` advertising at 64×22 and 80×24 across Account / Moderation / Sysop.

These items are not blockers — every observable truth is wired and unit/integration-tested at the data layer. They exist because the rendered ANSI output, theme color application, and live SSH command runtime cannot be programmatically inspected from Mix tests (output is ANSI-stripped in the test harness).

### Gaps Summary

No goal-blocking gaps. All 8 must-have truths verified at all four levels (existence, substantive, wired, data-flow). All 7 requirement IDs satisfied. Full test suite (1975 tests + 1 property) passes. Compile is warning-clean for project code. The phase implementation matches the plan and SUMMARY narrative; spot-greps confirm every claim.

The only outstanding work is the live-SSH UAT pass listed above — required to confirm visual / ANSI / terminal behaviors that the test harness ANSI-strips.

---

_Verified: 2026-04-27T21:47:03Z_
_Verifier: Claude (gsd-verifier)_
