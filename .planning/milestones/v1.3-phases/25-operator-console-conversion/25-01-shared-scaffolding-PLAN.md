---
phase: 25
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - lib/foglet_bbs/tui/widgets/modal/form.ex
  - lib/foglet_bbs/tui/widgets/modal/form/submit_stash.ex
  - test/foglet_bbs/tui/widgets/modal/form_test.exs
  - test/foglet_bbs/tui/widgets/modal/form/submit_stash_test.exs
  - test/support/foglet/tui/layout_smoke_helpers.ex
  - test/support/foglet/tui/layout_smoke/account_helper.ex
  - test/support/foglet/tui/layout_smoke/moderation_helper.ex
  - test/support/foglet/tui/layout_smoke/sysop_helper.ex
  - test/foglet_bbs/tui/layout_smoke_test.exs
autonomous: true
requirements:
  - ACCOUNT-01
  - MOD-01
  - SYSOP-01
user_setup: []
tags:
  - tui
  - operator-console
  - elixir
  - raxol

must_haves:
  truths:
    - "Modal.Form.handle_event/2 accepts both %{key: :shift_tab} and %{key: :tab, shift: true} for back-tab navigation."
    - "Account prefs theme-cycle live preview path (D-03 / Pitfall 5 / A1) has a documented integration approach screens can follow without changing public Modal.Form API surface, OR has a minimal Modal.Form extension shipped."
    - "Layout-smoke tests have a shared helper to activate a named tab inside a screen_state map for the per-tab size-contract loop (D-09, D-11)."
    - "Wave 0 verification confirms whether prefs `:enum` field plus screen-level field-state inspection is sufficient (A1 resolved); decision is recorded in Modal.Form @moduledoc or a code comment."
    - "Modal.Form.SubmitStash helper exists with stash/2, pop/1, with_stashed/2 and guaranteed cleanup, so converted form consumers (Plans 02/04) avoid raw Process.put/Process.get — Codex Concern 4."
  artifacts:
    - path: "lib/foglet_bbs/tui/widgets/modal/form.ex"
      provides: "Shift+Tab event-shape coverage AND (per A1 outcome) either an on_field_change callback option OR a documented public field_states accessor for screen-level enum-cycle interception."
      contains: "shift_tab"
    - path: "test/foglet_bbs/tui/widgets/modal/form_test.exs"
      provides: "Unit tests pinning both shift-tab event shapes; tests for the chosen prefs-cycle hook (A1)."
      contains: "shift_tab"
    - path: "lib/foglet_bbs/tui/widgets/modal/form/submit_stash.ex"
      provides: "Centralized submit-payload stash with guaranteed cleanup; replaces raw Process.put/Process.get sprinkled across form consumers (Codex Concern 4)."
      exports: ["stash", "pop", "with_stashed"]
    - path: "test/support/foglet/tui/layout_smoke_helpers.ex"
      provides: "set_active_tab/2 helper for use in per-tab size-contract tests across Account/Moderation/Sysop."
      exports: ["set_active_tab"]
    - path: "test/support/foglet/tui/layout_smoke/account_helper.ex"
      provides: "Per-tab smoke-test registry for Account tabs; Plan 02 adds PROFILE/PREFS/SSH_KEYS blocks here (NOT in layout_smoke_test.exs) to avoid wave-2 merge conflicts."
      exports: ["register_account_size_contracts"]
    - path: "test/support/foglet/tui/layout_smoke/moderation_helper.ex"
      provides: "Per-tab smoke-test registry for Moderation tabs; Plan 03 adds LOG/USERS/BOARDS/INVITES blocks here."
      exports: ["register_moderation_size_contracts"]
    - path: "test/support/foglet/tui/layout_smoke/sysop_helper.ex"
      provides: "Per-tab smoke-test registry for Sysop tabs; Plan 04 adds SITE/LIMITS/BOARDS/USERS/SYSTEM blocks here."
      exports: ["register_sysop_size_contracts"]
    - path: "test/foglet_bbs/tui/layout_smoke_test.exs"
      provides: "Thin registry: imports the three per-screen helpers and invokes their register_*_size_contracts macros. Plans 02/03/04 do NOT modify this file directly — they own their per-screen helper module."
      contains: "set_active_tab"
  key_links:
    - from: "lib/foglet_bbs/tui/widgets/modal/form.ex"
      to: "Foglet.TUI.Widgets.Input.RadioGroup (already used at form.ex:332-335)"
      via: "field_states for :enum cycling"
      pattern: "RadioGroup"
    - from: "test/support/foglet/tui/layout_smoke_helpers.ex"
      to: "Account.State / Moderation.State / Sysop.State active-tab fields"
      via: "screen_state[:active_tab] mutation helper"
      pattern: "set_active_tab"
---

<objective>
Establish the shared Wave 0 scaffolding required before Account, Moderation, and Sysop tab-body conversions
can run in parallel (D-14, D-15). Resolve assumption A1 (prefs `:enum` live-preview side effect) and
pitfall 1 (Shift+Tab event-shape mismatch) inside Modal.Form so all four converted forms can rely on a
single, documented contract. Provide a `set_active_tab/2` test helper so the 12 per-tab layout smoke
blocks added in plans 02/03/04/05 share a single fixture pattern (D-09, D-11).

Purpose: Avoid duplicate fixes inside each parallel wave-2 plan and prevent the converted prefs form from
silently losing the existing instant theme preview behavior (Pitfall 5).
Output: Modal.Form patches + tests, layout-smoke helper module, one example per-tab block proving the
helper works.
</objective>

<execution_context>
@/Users/brendan.turner/Dev/personal/foglet_bbs/.claude/get-shit-done/workflows/execute-plan.md
@/Users/brendan.turner/Dev/personal/foglet_bbs/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@.planning/ROADMAP.md
@.planning/REQUIREMENTS.md
@.planning/phases/25-operator-console-conversion/25-CONTEXT.md
@.planning/phases/25-operator-console-conversion/25-RESEARCH.md
@.planning/phases/25-operator-console-conversion/25-SPEC.md
@.planning/phases/24-operator-console-primitives/24-CONTEXT.md
@.planning/phases/24-operator-console-primitives/24-VERIFICATION.md
@AGENTS.md
@lib/foglet_bbs/tui/widgets/modal/form.ex
@lib/foglet_bbs/tui/widgets/input/radio_group.ex
@lib/foglet_bbs/tui/screens/account/prefs_form.ex
@test/foglet_bbs/tui/widgets/modal/form_test.exs
@test/foglet_bbs/tui/layout_smoke_test.exs
@test/support/foglet/tui/widget_helpers.ex
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Modal.Form Shift+Tab event-shape parity + tests (Pitfall 1)</name>
  <files>lib/foglet_bbs/tui/widgets/modal/form.ex, test/foglet_bbs/tui/widgets/modal/form_test.exs</files>
  <read_first>
    - lib/foglet_bbs/tui/widgets/modal/form.ex (lines 1-30 docstring, 90-115 handle_event head, 230-260 :enum field handling)
    - test/foglet_bbs/tui/widgets/modal/form_test.exs (existing structure)
    - lib/foglet_bbs/tui/screens/account/profile_form.ex (line 137 — `%{key: :shift_tab}` shape)
    - lib/foglet_bbs/tui/screens/account/prefs_form.ex (line 215 — `%{key: :shift_tab}` shape)
    - .planning/phases/25-operator-console-conversion/25-RESEARCH.md (Pitfall 1)
  </read_first>
  <behavior>
    - Test: `Modal.Form.handle_event(%{key: :tab, shift: true}, form)` moves focus to previous field (Raxol shape — already supported).
    - Test: `Modal.Form.handle_event(%{key: :shift_tab}, form)` ALSO moves focus to previous field (Foglet/CLIHandler-translated shape).
    - Test: forward Tab `%{key: :tab}` and `%{key: :tab, shift: false}` continue to advance focus (regression).
    - Test: existing forward-tab / submit / cancel behaviors are unchanged (run existing form_test.exs unmodified — no assertion weakening per D-19).
  </behavior>
  <action>
    In `lib/foglet_bbs/tui/widgets/modal/form.ex` `handle_event/2`, add a clause that matches the
    Foglet-translated shape `%{key: :shift_tab}` and routes it to the same back-tab branch as
    `%{key: :tab, shift: true}`. Keep the existing Raxol-shape clause; do not remove it. Place the new
    clause adjacent to the existing tab clause so the pattern is visually obvious.

    Concretely (paraphrased — adapt to the file's existing case/def structure):

    ```elixir
    def handle_event(%{key: :tab, shift: true}, form), do: focus_prev(form)
    def handle_event(%{key: :shift_tab}, form), do: focus_prev(form)   # NEW — D-25-Pitfall-1
    def handle_event(%{key: :tab}, form), do: focus_next(form)
    ```

    If the current implementation inlines the back-tab logic instead of using a helper, extract it into a
    private `focus_prev/1` (or equivalent) so both clauses share one body. Do NOT change the return-tuple
    shape (`{form, action_atom_or_nil}`).

    In `test/foglet_bbs/tui/widgets/modal/form_test.exs`, add a `describe "shift+tab event shapes"` block
    asserting both shapes return identical `{form, _}` results (focus index decrements; same `action`).
    Use existing form fixture builders in the file — do not invent new ones. Reference Pitfall 1 in a
    test comment for traceability ("D-25 Pitfall 1: shift_tab event-shape parity").

    Per D-19: do not modify existing tests; only add new ones.
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/widgets/modal/form_test.exs</automated>
  </verify>
  <acceptance_criteria>
    - `grep -n "shift_tab" lib/foglet_bbs/tui/widgets/modal/form.ex` returns at least one match.
    - `grep -n "shift+tab event shapes\|shift_tab" test/foglet_bbs/tui/widgets/modal/form_test.exs` returns matches for the new describe block.
    - `rtk mix test test/foglet_bbs/tui/widgets/modal/form_test.exs` exits 0.
    - `rtk mix test test/foglet_bbs/tui/widgets/modal/form_test.exs --only describe:"shift+tab event shapes"` runs at least 2 tests and they pass (one per event shape).
    - No tests deleted or assertions weakened (`git diff test/foglet_bbs/tui/widgets/modal/form_test.exs` shows only additions in the new describe block plus optionally a single-line comment near pre-existing tab tests).
  </acceptance_criteria>
  <done>Both shift-tab event shapes route through the same Modal.Form back-tab branch; new tests pin both shapes; existing form tests still pass.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Resolve A1 — prefs `:enum` live-preview integration path</name>
  <files>lib/foglet_bbs/tui/widgets/modal/form.ex, test/foglet_bbs/tui/widgets/modal/form_test.exs</files>
  <read_first>
    - lib/foglet_bbs/tui/widgets/modal/form.ex (lines 230-260 — `:enum` field handling; lines 332-335 — RadioGroup.render call)
    - lib/foglet_bbs/tui/screens/account/prefs_form.ex (lines 160-220 — `:candidate_theme_id` instant preview side effect)
    - lib/foglet_bbs/tui/widgets/input/radio_group.ex (handle_event return shape)
    - .planning/phases/25-operator-console-conversion/25-RESEARCH.md (Pitfall 5, Open Question 1, Assumption A1)
    - .planning/phases/25-operator-console-conversion/25-CONTEXT.md (D-03)
  </read_first>
  <behavior>
    - Test: After `Modal.Form.handle_event(%{key: :down}, form)` on a focused `:enum` field, the screen can read the post-event focused-field value (the new enum choice) WITHOUT calling submit. This is what the prefs theme-cycle preview needs.
    - Test: The chosen accessor (either a public `field_states/1` accessor OR an `:on_field_change` opt) returns/fires with the changed field name and new value.
    - Test: Cycling does NOT mark the form `:submitted` and does NOT lose dirty tracking.
  </behavior>
  <action>
    Per D-03 and discretion granted in CONTEXT.md ("Whether the Wave 0 RadioGroup field becomes a public
    Modal.Form field type or a private internal addition"), choose path (a) from RESEARCH Open Question 1:
    a screen-level interception via a public read accessor on `Modal.Form`. This is the lower-API-surface
    option and avoids changing the public field-type list (D-19 spirit).

    Implementation:

    1. In `lib/foglet_bbs/tui/widgets/modal/form.ex`, expose (or confirm public) a `field_value/2`
       accessor: `field_value(%Form{} = form, field_name) :: term | nil` that returns the current value
       of the named field from the form's internal field-state map. If a similar accessor already exists
       under a different name, prefer that and add a `@doc` callout that screens use it for enum-cycle
       interception. Do not change struct internals beyond what is needed to expose this.

    2. Add a `@moduledoc` (or extend existing) note titled "Enum field cycling and screen-side preview
       (D-25 D-03 / Pitfall 5)" explaining: screens that need a live side effect on `:enum` cycling
       should call `Modal.Form.field_value(form, :theme_id)` after every `handle_event/2` and diff
       against the previous value to trigger the preview. Reference `Foglet.TUI.Screens.Account.PrefsForm`
       as the consumer.

    3. In `test/foglet_bbs/tui/widgets/modal/form_test.exs`, add a `describe "enum field value accessor"`
       block with: build a form containing one `:enum` field with choices `[:dark, :light, :amber]` and
       value `:dark`; send `%{key: :down}`; assert `Modal.Form.field_value(form_after, :theme_id) ==
       :light`; send `%{key: :down}` again; assert `:amber`; assert no `:submitted` action returned.

    If during implementation it becomes clear that the existing `:enum` handling does NOT update the
    in-struct field value on cycle (only on submit), then the minimum extension is: ensure the per-field
    state IS updated on cycle so `field_value/2` reflects the cycled choice. This is the actual gap
    Pitfall 5 anticipates. Do not add a public `:on_field_change` callback option in this phase
    (deferred unless the read-accessor path proves insufficient during plan 02 execution).

    Per D-19: do not weaken or modify existing form tests.
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/widgets/modal/form_test.exs</automated>
  </verify>
  <acceptance_criteria>
    - `grep -n "field_value\|@doc.*enum\|D-03\|Pitfall 5" lib/foglet_bbs/tui/widgets/modal/form.ex` returns at least one match for `field_value` and at least one match referencing the new doc note.
    - `grep -n "enum field value accessor\|field_value" test/foglet_bbs/tui/widgets/modal/form_test.exs` returns matches for the new describe block.
    - `rtk mix test test/foglet_bbs/tui/widgets/modal/form_test.exs --only describe:"enum field value accessor"` runs at least 1 test and passes.
    - `rtk mix test test/foglet_bbs/tui/widgets/modal/form_test.exs` exits 0 (no regression in existing tests).
  </acceptance_criteria>
  <done>Modal.Form exposes a documented `field_value/2` accessor that returns the post-cycle enum choice; tests pin the behavior; existing tests pass; the prefs conversion in plan 02 has a clear, documented integration path that does NOT require a new public field type or callback.</done>
</task>

<task type="auto">
  <name>Task 3: Layout-smoke `set_active_tab/2` helper + example per-tab block</name>
  <files>test/support/foglet/tui/layout_smoke_helpers.ex, test/foglet_bbs/tui/layout_smoke_test.exs</files>
  <read_first>
    - test/foglet_bbs/tui/layout_smoke_test.exs (lines 273-353 — Phase 22/20 size-contract loop precedent per D-11)
    - test/foglet_bbs/tui/layout_smoke_test.exs (lines 1735-1830 — shell-only operator tests; explicitly NOT the precedent)
    - test/support/foglet/tui/widget_helpers.ex (existing test-support module shape)
    - lib/foglet_bbs/tui/screens/account/state.ex (active-tab field name)
    - lib/foglet_bbs/tui/screens/moderation/state.ex (active-tab field name)
    - lib/foglet_bbs/tui/screens/sysop/state.ex (active-tab field name)
    - .planning/phases/25-operator-console-conversion/25-CONTEXT.md (D-09, D-10, D-11)
  </read_first>
  <action>
    Create `test/support/foglet/tui/layout_smoke_helpers.ex` exporting:

    ```elixir
    defmodule Foglet.TUI.LayoutSmokeHelpers do
      @moduledoc """
      Test-support helpers for per-tab size-contract smoke tests added in Phase 25
      (D-09, D-11). Plans 02/03/04 use `set_active_tab/2` to activate a named tab
      inside a screen_state map before rendering.
      """

      @doc """
      Set the active tab on a screen_state map. Tab name is the upcased label
      (e.g. "PROFILE", "PREFS", "SSH_KEYS", "LOG", "USERS", "BOARDS", "INVITES",
      "SITE", "LIMITS", "SYSTEM"). Returns the updated screen_state.

      Reads the appropriate `active_tab` (or equivalent) key from the screen's
      sibling `state.ex` struct. Adapter functions per screen are private —
      callers pass the screen atom and tab label.
      """
      def set_active_tab(screen_state, tab_name) when is_binary(tab_name)
      # implementation: pattern-match on the screen_state struct module and set
      # the documented active-tab field. Read each screen's state.ex to determine
      # the exact field name (likely `:active_tab` storing a string or atom).
    end
    ```

    The implementation must inspect the actual field name(s) used by each screen's `state.ex`. If the
    three screens use different field names, the helper handles each via a `case` on the struct module.
    Do NOT modify production state.ex modules to normalize field names — adapt the helper.

    Then add ONE example per-tab block to `test/foglet_bbs/tui/layout_smoke_test.exs` (placed adjacent to
    the existing 273-353 precedent) targeting the already-shipped `Sysop.BoardsView` (the canonical
    Phase 24 precedent — already uses Modal.Form, so it exercises the helper without needing plans
    02/03/04 to have completed). The block:

    ```elixir
    describe "sysop boards tab — size contract (Phase 25 helper sentinel)" do
      for {width, height} <- [{64, 22}, {80, 24}] do
        @width width
        @height height
        @tag :"sysop boards size contract"
        test "at #{width}x#{height} primitives render within bounds" do
          ss =
            Sysop.init_screen_state()
            |> Foglet.TUI.LayoutSmokeHelpers.set_active_tab("BOARDS")

          state = build_app_state(:sysop, ss, {@width, @height})
          tree = Sysop.render(state)
          positioned = apply_at_size(tree, {@width, @height})

          for el <- text_elements(positioned) do
            assert el.x + Foglet.TUI.TextWidth.display_width(el.text) <= @width
          end
        end
      end
    end
    ```

    Reuse existing helpers (`apply_at_size/2`, `text_elements/1`, `build_app_state/3` if present —
    inspect lines 273-353 to identify them). If `build_app_state/3` is not a real helper in the file,
    inline the `%App{...} |> Map.from_struct()` construction shown in RESEARCH "Per-tab layout smoke
    test" example.

    Add `test/support/foglet/tui/layout_smoke_helpers.ex` to the test_helpers compile path if the
    project does not already auto-load `test/support/**`. Inspect `mix.exs` and `test/test_helper.exs`
    first; do not duplicate existing wiring.

    **Per-screen helper modules (NEW — addresses Codex Concern 3, merge-conflict avoidance):**

    Create three additional support modules so Plans 02/03/04 each own a disjoint test-support file
    instead of all three modifying `layout_smoke_test.exs` in parallel:

    - `test/support/foglet/tui/layout_smoke/account_helper.ex` — defines
      `Foglet.TUI.LayoutSmoke.AccountHelper`. Exports a macro `register_account_size_contracts/0`
      (or equivalent). In this Plan 01 task, ship the module with a stub body (just defines the
      module + macro shell with NO tab blocks yet). Plan 02 fills in PROFILE/PREFS/SSH_KEYS blocks.

    - `test/support/foglet/tui/layout_smoke/moderation_helper.ex` —
      `Foglet.TUI.LayoutSmoke.ModerationHelper.register_moderation_size_contracts/0` stub.
      Plan 03 fills in LOG/USERS/BOARDS/INVITES.

    - `test/support/foglet/tui/layout_smoke/sysop_helper.ex` —
      `Foglet.TUI.LayoutSmoke.SysopHelper.register_sysop_size_contracts/0` stub.
      Plan 04 fills in SITE/LIMITS/BOARDS/USERS/SYSTEM.

    Then update `test/foglet_bbs/tui/layout_smoke_test.exs` to act as a thin registry: at the bottom of
    the test module, invoke each macro:

    ```elixir
    require Foglet.TUI.LayoutSmoke.AccountHelper
    require Foglet.TUI.LayoutSmoke.ModerationHelper
    require Foglet.TUI.LayoutSmoke.SysopHelper

    Foglet.TUI.LayoutSmoke.AccountHelper.register_account_size_contracts()
    Foglet.TUI.LayoutSmoke.ModerationHelper.register_moderation_size_contracts()
    Foglet.TUI.LayoutSmoke.SysopHelper.register_sysop_size_contracts()
    ```

    The Plan-01 example sysop boards block can live either in `layout_smoke_test.exs` directly OR
    inside the `SysopHelper` macro stub as the first block (preferred — proves the macro pattern works).
    Either is acceptable; document the choice in the SUMMARY.

    **Fixture realism (Codex LOW suggestion):** Smoke fixtures across plans 02/03/04 should
    collectively exercise: long handles (>16 chars to test truncation), at least one Unicode glyph
    (e.g. wide CJK, emoji, or diacritic to exercise `TextWidth`), missing optional fields (nil
    `last_used`, nil `used_by`), AND empty-state at least once per screen. Each plan does not need
    every realism case — they can be distributed across tabs as long as the smoke suite as a whole
    covers all four classes. Plan 05 SUMMARY records which tabs cover which case.

    **Result:** Plans 02/03/04 each modify ONE file (`<screen>_helper.ex`) that no other plan touches.
    `layout_smoke_test.exs` is touched only by Plan 01. Wave-2 merge conflict surface goes to zero.

    If macros feel heavy for this case, an alternative shape is acceptable: each helper exports a
    plain function called from inside a `describe` block in `layout_smoke_test.exs` per screen, but
    that puts text back in the shared file — prefer the macro shape unless macro cost is high.
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs --only "sysop boards size contract"</automated>
  </verify>
  <acceptance_criteria>
    - `test/support/foglet/tui/layout_smoke_helpers.ex` exists and defines `Foglet.TUI.LayoutSmokeHelpers`.
    - `grep -n "def set_active_tab" test/support/foglet/tui/layout_smoke_helpers.ex` returns at least one match.
    - `test/support/foglet/tui/layout_smoke/account_helper.ex` exists and defines `Foglet.TUI.LayoutSmoke.AccountHelper`.
    - `test/support/foglet/tui/layout_smoke/moderation_helper.ex` exists and defines `Foglet.TUI.LayoutSmoke.ModerationHelper`.
    - `test/support/foglet/tui/layout_smoke/sysop_helper.ex` exists and defines `Foglet.TUI.LayoutSmoke.SysopHelper`.
    - `grep -n "register_account_size_contracts\|register_moderation_size_contracts\|register_sysop_size_contracts" test/foglet_bbs/tui/layout_smoke_test.exs` returns at least 3 matches (registry invocations).
    - `grep -n "set_active_tab" test/foglet_bbs/tui/layout_smoke_test.exs` returns at least one match (or inside one of the helper modules — the example block can live in `sysop_helper.ex`).
    - `grep -rn "sysop boards tab — size contract\|sysop boards size contract" test/support/foglet/tui/layout_smoke/sysop_helper.ex test/foglet_bbs/tui/layout_smoke_test.exs` returns matches.
    - `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` exits 0 (no regression).
    - `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs --only "sysop boards size contract"` runs at least 2 tests (one per `[{64,22},{80,24}]` size) and they pass.
  </acceptance_criteria>
  <done>Shared `set_active_tab/2` helper exists, example per-tab smoke block proves it works at 64x22 and 80x24 against the already-converted Sysop boards tab, and downstream plans 02/03/04 can copy the block pattern verbatim per D-11.</done>

<task type="auto" tdd="true">
  <name>Task 4: Modal.Form.SubmitStash helper for Process-dictionary submit pattern (Codex Concern 4)</name>
  <files>lib/foglet_bbs/tui/widgets/modal/form/submit_stash.ex, test/foglet_bbs/tui/widgets/modal/form/submit_stash_test.exs</files>
  <read_first>
    - lib/foglet_bbs/tui/screens/sysop/boards_view.ex (lines 436-485 — current raw `Process.put`/`Process.get` precedent)
    - lib/foglet_bbs/tui/widgets/modal/form.ex (line 114 — `_ = state.on_submit.(payload)` discards return)
    - .planning/phases/25-operator-console-conversion/25-RESEARCH.md (Pattern 1 / Pitfall 2)
    - .planning/phases/25-operator-console-conversion/25-REVIEWS.md (Codex Concern 4)
  </read_first>
  <behavior>
    - Test: `SubmitStash.stash(MyModule, payload)` followed by `SubmitStash.pop(MyModule)` returns the same `payload` and clears the entry (subsequent `pop/1` returns `nil`).
    - Test: `SubmitStash.with_stashed(MyModule, fn payload -> ... end)` runs the function with the stashed payload and guarantees deletion in an `after` clause even when the function raises.
    - Test: stash key is namespaced by the calling module (passed as the first arg), so two modules can stash concurrently within one process tick without collision.
    - Test: `pop/1` on empty stash returns `nil` (no crash).
  </behavior>
  <action>
    Create `lib/foglet_bbs/tui/widgets/modal/form/submit_stash.ex`:

    ```elixir
    defmodule Foglet.TUI.Widgets.Modal.Form.SubmitStash do
      @moduledoc """
      Per-process submit-payload stash for `Modal.Form.on_submit` callbacks.

      `Modal.Form` deliberately discards the `on_submit` callback return value
      (form.ex:114 — `_ = state.on_submit.(payload)`), so screens that need to
      capture the submitted payload park it in the process dictionary and read
      it back from `handle_event/2`'s caller after the event returns.

      This helper centralizes the pattern (Phase 25, Codex review Concern 4) so
      every consumer uses the same key shape and cleanup discipline. Always
      prefer `with_stashed/2` over manual `stash`/`pop` to guarantee cleanup
      even on exceptions.
      """

      @type module_key :: module()
      @type payload :: term()

      @doc "Stash a payload keyed by the calling module."
      @spec stash(module_key, payload) :: :ok
      def stash(mod, payload) when is_atom(mod) do
        Process.put({__MODULE__, mod}, payload)
        :ok
      end

      @doc "Pop a stashed payload (and delete it). Returns nil when absent."
      @spec pop(module_key) :: payload | nil
      def pop(mod) when is_atom(mod) do
        Process.delete({__MODULE__, mod})
      end

      @doc """
      Run `fun` with the stashed payload (or `nil`) and guarantee deletion.

          SubmitStash.with_stashed(__MODULE__, fn
            nil     -> :no_submit
            payload -> handle_save(payload)
          end)
      """
      @spec with_stashed(module_key, (payload | nil -> term())) :: term()
      def with_stashed(mod, fun) when is_atom(mod) and is_function(fun, 1) do
        try do
          fun.(Process.get({__MODULE__, mod}))
        after
          Process.delete({__MODULE__, mod})
        end
      end
    end
    ```

    Add `test/foglet_bbs/tui/widgets/modal/form/submit_stash_test.exs` covering all four behaviors
    above. Use `start_supervised!/1` is unnecessary (this is process-dict only). DO NOT use
    `Process.sleep/1`.

    Plans 02 and 04 will adopt this helper for their Modal.Form on_submit closures (acceptance
    criteria require `Foglet.TUI.Widgets.Modal.Form.SubmitStash` usage AND assert that raw
    `Process.put`/`Process.get` does NOT appear in the converted screen modules). Plan 03 does not
    use this helper because its converted surfaces are listings/read-only (no Modal.Form submits).

    Optionally, refactor `lib/foglet_bbs/tui/screens/sysop/boards_view.ex` to use the new helper for
    consistency. If touched, add a single test asserting the existing boards_view submit flow still
    works (do NOT modify any existing boards_view test). If the refactor risks scope creep, defer to
    Plan 04 Task 1 (which already touches boards_view for D-07 verification).
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/widgets/modal/form/submit_stash_test.exs</automated>
  </verify>
  <acceptance_criteria>
    - `lib/foglet_bbs/tui/widgets/modal/form/submit_stash.ex` exists and defines `Foglet.TUI.Widgets.Modal.Form.SubmitStash`.
    - `grep -n "def stash\|def pop\|def with_stashed" lib/foglet_bbs/tui/widgets/modal/form/submit_stash.ex` returns at least 3 matches.
    - `grep -n "after" lib/foglet_bbs/tui/widgets/modal/form/submit_stash.ex` returns at least 1 match (cleanup guarantee).
    - `test/foglet_bbs/tui/widgets/modal/form/submit_stash_test.exs` exists.
    - `rtk mix test test/foglet_bbs/tui/widgets/modal/form/submit_stash_test.exs` exits 0 with at least 4 tests run.
  </acceptance_criteria>
  <done>SubmitStash helper exists with stash/pop/with_stashed and cleanup-on-raise; downstream form consumers (Plans 02/04) can use it instead of raw Process.put/get.</done>
</task>

</tasks>

<verification>
- All three tasks pass their automated verify commands.
- `rtk mix test test/foglet_bbs/tui/widgets/modal/ test/foglet_bbs/tui/layout_smoke_test.exs` exits 0.
- No production code outside `lib/foglet_bbs/tui/widgets/modal/form.ex` is modified.
- No existing tests modified or assertions weakened (D-19 spot-check via `git diff --stat`).
</verification>

<success_criteria>
- Shift+Tab event-shape parity shipped in Modal.Form with regression tests.
- Prefs `:enum` live-preview integration path resolved per A1: documented `field_value/2` accessor + tests.
- Layout-smoke `set_active_tab/2` helper exists and is proven by one working per-tab block.
- Plans 02/03/04 can begin in parallel without re-litigating Pitfalls 1 and 5 or inventing per-screen smoke fixtures.
</success_criteria>

<output>
After completion, create `.planning/phases/25-operator-console-conversion/25-01-SUMMARY.md` capturing:
- Whether `field_value/2` already existed or was added; the resolved A1 outcome.
- Confirmed active-tab field name(s) per screen state module.
- Any deviation from the plan (e.g., if existing `:enum` cycling already updates field state and the doc note alone resolves A1).
</output>
