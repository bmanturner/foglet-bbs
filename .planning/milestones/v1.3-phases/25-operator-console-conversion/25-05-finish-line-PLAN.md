---
phase: 25
plan: 05
type: execute
wave: 3
depends_on: [02, 03, 04]
files_modified:
  - test/foglet_bbs/tui/screens/account_test.exs
  - test/foglet_bbs/tui/screens/moderation_test.exs
  - test/foglet_bbs/tui/screens/sysop_test.exs
  - .planning/phases/25-operator-console-conversion/25-VALIDATION.md
  - .planning/phases/25-operator-console-conversion/25-05-SUMMARY.md
autonomous: true
requirements:
  - ACCOUNT-01
  - MOD-01
  - SYSOP-01
user_setup: []
tags:
  - tui
  - operator-console
  - finish-line
  - elixir

must_haves:
  truths:
    - "For each of the 12 converted tabs, `Foglet.TUI.WidgetHelpers.color_atom_leaked?/2` returns false for every name in `color_names/0` (D-12, R8)."
    - "`Workspace.Inspector` is referenced ZERO times under `lib/foglet_bbs/tui/screens/` (D-20)."
    - "`rtk mix precommit` exits 0 (compile-with-warnings-as-errors, formatter, Credo, Sobelow, Dialyzer) — phase finish-line gate (R8)."
    - "Every Phase 25 acceptance criterion in 25-SPEC.md §Acceptance Criteria checks green."
  artifacts:
    - path: "test/foglet_bbs/tui/screens/account_test.exs"
      provides: "Per-tab theme-hygiene test using color_atom_leaked?/2 for PROFILE, PREFS, SSH_KEYS."
      contains: "color_atom_leaked"
    - path: "test/foglet_bbs/tui/screens/moderation_test.exs"
      provides: "Per-tab theme-hygiene test for LOG, USERS, BOARDS, INVITES."
      contains: "color_atom_leaked"
    - path: "test/foglet_bbs/tui/screens/sysop_test.exs"
      provides: "Per-tab theme-hygiene test for SITE, LIMITS, BOARDS, USERS, SYSTEM AND a `Workspace.Inspector` deferral grep test (D-20)."
      contains: "Workspace.Inspector"
  key_links:
    - from: "test/foglet_bbs/tui/screens/sysop_test.exs"
      to: "lib/foglet_bbs/tui/screens/"
      via: "ExUnit test that runs `File.ls!/1` recursively and asserts no file contains `Workspace.Inspector`"
      pattern: "Workspace.Inspector"
    - from: "test/foglet_bbs/tui/screens/{account,moderation,sysop}_test.exs"
      to: "test/support/foglet/tui/widget_helpers.ex (color_atom_leaked?/2)"
      via: "render-and-assert hygiene loop"
      pattern: "color_atom_leaked"
---

<objective>
Close Phase 25's finish line: per-tab theme-hygiene assertions across all 12 converted tabs (D-12), the
`Workspace.Inspector` deferral grep gate (D-20), and the canonical `rtk mix precommit` gate (R8).
This plan adds NO production code; it only adds the hygiene tests that wave-2 plans intentionally
deferred to a single, consistent place and runs the precommit gate at the end of the phase.

Purpose: Plans 02/03/04 each ran their own focused tests; this plan provides the cross-cutting
guarantees the spec acceptance criteria require, in one place, after all parallel waves merged.
Output: Three test additions (one per screen test file) + a clean `rtk mix precommit` run.
</objective>

<execution_context>
@/Users/brendan.turner/Dev/personal/foglet_bbs/.claude/get-shit-done/workflows/execute-plan.md
@/Users/brendan.turner/Dev/personal/foglet_bbs/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/phases/25-operator-console-conversion/25-CONTEXT.md
@.planning/phases/25-operator-console-conversion/25-RESEARCH.md
@.planning/phases/25-operator-console-conversion/25-SPEC.md
@.planning/phases/25-operator-console-conversion/25-02-account-conversion-PLAN.md
@.planning/phases/25-operator-console-conversion/25-03-moderation-conversion-PLAN.md
@.planning/phases/25-operator-console-conversion/25-04-sysop-conversion-PLAN.md
@AGENTS.md
@test/support/foglet/tui/widget_helpers.ex
@test/support/foglet/tui/layout_smoke_helpers.ex
@test/foglet_bbs/tui/screens/account_test.exs
@test/foglet_bbs/tui/screens/moderation_test.exs
@test/foglet_bbs/tui/screens/sysop_test.exs
</context>

<tasks>

<task type="auto">
  <name>Task 1: Per-tab theme-hygiene tests (D-12, R8) for all 12 converted tabs</name>
  <files>test/foglet_bbs/tui/screens/account_test.exs, test/foglet_bbs/tui/screens/moderation_test.exs, test/foglet_bbs/tui/screens/sysop_test.exs</files>
  <read_first>
    - test/support/foglet/tui/widget_helpers.ex (lines 21, 38, 60 — `color_atom_leaked?/2` and `color_names/0` API)
    - test/foglet_bbs/tui/widgets/display/badge_test.exs (Phase 24 precedent for the hygiene-loop pattern referenced in RESEARCH)
    - test/foglet_bbs/tui/widgets/display/kv_grid_test.exs (same precedent)
    - test/support/foglet/tui/layout_smoke_helpers.ex (set_active_tab/2)
    - .planning/phases/25-operator-console-conversion/25-CONTEXT.md (D-12, D-13)
    - .planning/phases/25-operator-console-conversion/25-RESEARCH.md (Theme-hygiene assertion code example)
  </read_first>
  <action>
    For each converted tab, add a theme-hygiene test that renders the tab body and asserts NO color
    name in `Foglet.TUI.WidgetHelpers.color_names/0` leaks via `color_atom_leaked?/2`. Pattern after
    the RESEARCH "Theme-hygiene assertion (D-12)" code example. Per D-13, do NOT substitute a static
    source grep — the helper is the canonical assertion.

    Add ONE describe block per screen test file that loops over every converted tab in that screen:

    1. **`test/foglet_bbs/tui/screens/account_test.exs`** — append:

       ```elixir
       describe "Phase 25 theme hygiene (D-12)" do
         import Foglet.TUI.WidgetHelpers
         import Foglet.TUI.LayoutSmokeHelpers

         for tab <- ["PROFILE", "PREFS", "SSH_KEYS"] do
           @tab tab
           test "converted Account #{tab} tab leaks no color atoms" do
             theme = Foglet.TUI.Theme.default()  # or whatever the existing badge_test uses; verify
             ss = Account.init_screen_state() |> set_active_tab(@tab)
             state = build_app_state(:account, ss, {80, 24})

             serialized = state |> Account.render() |> inspect(limit: :infinity)

             for color <- color_names() do
               refute color_atom_leaked?(serialized, color),
                      "leaked :#{color} in converted Account #{@tab} tab"
             end
           end
         end
       end
       ```

       Use whichever `Foglet.TUI.Theme` constructor the existing badge/kv_grid tests use (assumption
       A4 — verify; adjust if `Theme.from_state/1` is required).

    2. **`test/foglet_bbs/tui/screens/moderation_test.exs`** — same shape, looping over
       `["LOG", "USERS", "BOARDS", "INVITES"]`.

    3. **`test/foglet_bbs/tui/screens/sysop_test.exs`** — same shape, looping over
       `["SITE", "LIMITS", "BOARDS", "USERS", "SYSTEM"]`.

    All three describe blocks are PURE additions — no existing tests modified. Use `set_active_tab/2`
    from plan 01 to switch tabs.

    If `build_app_state/3` is not a real helper in the file, inline the `%App{...} |> Map.from_struct()`
    construction shown in RESEARCH "Per-tab layout smoke test" example. Reuse whatever
    plans 02/03/04 used in their per-tab smoke blocks for consistency.
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/screens/account_test.exs test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/screens/sysop_test.exs --only describe:"Phase 25 theme hygiene (D-12)"</automated>
  </verify>
  <acceptance_criteria>
    - `grep -n "Phase 25 theme hygiene" test/foglet_bbs/tui/screens/account_test.exs` returns at least 1 match.
    - `grep -n "Phase 25 theme hygiene" test/foglet_bbs/tui/screens/moderation_test.exs` returns at least 1 match.
    - `grep -n "Phase 25 theme hygiene" test/foglet_bbs/tui/screens/sysop_test.exs` returns at least 1 match.
    - `grep -c "color_atom_leaked" test/foglet_bbs/tui/screens/account_test.exs` returns >= 1.
    - `grep -c "color_atom_leaked" test/foglet_bbs/tui/screens/moderation_test.exs` returns >= 1.
    - `grep -c "color_atom_leaked" test/foglet_bbs/tui/screens/sysop_test.exs` returns >= 1.
    - Per-tab loop generates 3 tests (Account) + 4 tests (Moderation) + 5 tests (Sysop) = 12 hygiene tests, all passing.
    - `rtk mix test test/foglet_bbs/tui/screens/account_test.exs test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/screens/sysop_test.exs` exits 0.
  </acceptance_criteria>
  <done>All 12 converted tabs (3 Account + 4 Moderation + 5 Sysop) have an automated theme-hygiene test that fails if any hardcoded color atom is reintroduced.</done>
</task>

<task type="auto">
  <name>Task 2: Workspace.Inspector deferral grep test (D-20) + final precommit gate (R8)</name>
  <files>test/foglet_bbs/tui/screens/sysop_test.exs</files>
  <read_first>
    - .planning/phases/25-operator-console-conversion/25-CONTEXT.md (D-20)
    - .planning/phases/25-operator-console-conversion/25-SPEC.md (Acceptance Criteria — final two bullets)
    - lib/foglet_bbs/tui/widgets/workspace/inspector.ex (confirm module exists; D-20 forbids consumption from screens)
  </read_first>
  <action>
    1. Add to `test/foglet_bbs/tui/screens/sysop_test.exs` (chosen because Sysop is the most likely
       module to accidentally reach for an inspector — but the test scope is global to
       `lib/foglet_bbs/tui/screens/`):

       ```elixir
       describe "Phase 25 Workspace.Inspector deferral (D-20)" do
         test "no screen module references Workspace.Inspector" do
           offenders =
             "lib/foglet_bbs/tui/screens/"
             |> Path.expand()
             |> Path.join("**/*.ex")
             |> Path.wildcard()
             |> Enum.filter(fn path ->
               path |> File.read!() |> String.contains?("Workspace.Inspector")
             end)

           assert offenders == [],
                  "Phase 25 D-20: Workspace.Inspector must not be referenced from screens; " <>
                  "offending files: #{inspect(offenders)}"
         end
       end
       ```

       This is a pure ExUnit test using the standard library — no external grep dependency. Memory
       directive applied (verify negative findings with a real read, not a sub-agent claim).

    2. Run `rtk mix precommit` as the final manual gate. The acceptance criterion below is the
       phase-level finish line per R8.
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/screens/sysop_test.exs --only describe:"Phase 25 Workspace.Inspector deferral (D-20)" && rtk mix precommit</automated>
  </verify>
  <acceptance_criteria>
    - `grep -n "Phase 25 Workspace.Inspector deferral" test/foglet_bbs/tui/screens/sysop_test.exs` returns at least 1 match.
    - `grep -n "Workspace.Inspector" test/foglet_bbs/tui/screens/sysop_test.exs` returns at least 1 match (the test itself references the module name).
    - `rtk mix test test/foglet_bbs/tui/screens/sysop_test.exs --only describe:"Phase 25 Workspace.Inspector deferral (D-20)"` exits 0.
    - Manual command `find lib/foglet_bbs/tui/screens -name '*.ex' -exec grep -l 'Workspace.Inspector' {} \;` returns ZERO files.
    - `rtk mix precommit` exits 0 (compile-warnings-as-errors, formatter, Credo, Sobelow, Dialyzer all green).
    - `rtk mix test` exits 0 (full suite green; phase-level R8 acceptance).
  </acceptance_criteria>
  <done>Workspace.Inspector deferral is enforced by an automated ExUnit test; `rtk mix precommit` passes; full test suite passes; phase finish-line gate is green.</done>
</task>

</tasks>

<verification>
- `rtk mix test` exits 0 (full suite).
- `rtk mix precommit` exits 0.
- All 8 acceptance criteria from `25-SPEC.md` §Acceptance Criteria are satisfied by the combined output of plans 02/03/04/05.
- 25-VALIDATION.md Per-Task Verification Map populated and `nyquist_compliant: true` set (separate doc update — see <output>).
</verification>

<success_criteria>
- All 12 converted-tab theme-hygiene tests pass.
- Workspace.Inspector deferral grep test passes.
- `rtk mix precommit` passes — phase R8 finish line green.
- Phase 25 ready for `/gsd-verify-work`.
</success_criteria>

<output>
After completion:
1. Create `.planning/phases/25-operator-console-conversion/25-05-SUMMARY.md` capturing:
   - Final precommit run timestamp + status.
   - Number of tests added (12 hygiene + 1 inspector grep = 13).
   - Any deviation from the plan (e.g., if `Theme.default/0` was not the right constructor and `Theme.from_state/1` was needed).
2. Update `.planning/phases/25-operator-console-conversion/25-VALIDATION.md`:
   - Populate the Per-Task Verification Map with each task from plans 01-05 (Plan, Wave, Requirement,
     Test Type, Automated Command, File Exists, Status).
   - Wave 0 Requirements: list the three plan-01 deliverables (Modal.Form Shift+Tab, field_value/2
     accessor, set_active_tab/2 helper).
   - Set frontmatter `nyquist_compliant: true` and `wave_0_complete: true`.
   - Approval: `green`.
</output>
