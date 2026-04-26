---
phase: 25
plan: 02
type: execute
wave: 2
depends_on: [01]
files_modified:
  - lib/foglet_bbs/tui/screens/account.ex
  - lib/foglet_bbs/tui/screens/account/state.ex
  - lib/foglet_bbs/tui/screens/account/profile_form.ex
  - lib/foglet_bbs/tui/screens/account/prefs_form.ex
  - lib/foglet_bbs/tui/screens/account/ssh_keys_state.ex
  - lib/foglet_bbs/tui/screens/account/ssh_keys_surface.ex
  - test/foglet_bbs/tui/screens/account_test.exs
  - test/support/foglet/tui/layout_smoke/account_helper.ex
autonomous: true
requirements:
  - ACCOUNT-01
user_setup: []
tags:
  - tui
  - operator-console
  - account
  - elixir

must_haves:
  truths:
    - "Account PROFILE tab body renders through Modal.Form (heading, labeled fields, required markers, inline errors, action footer)."
    - "Account PREFS tab body renders through Modal.Form with `:enum` fields for theme/time-format; arrow-cycle still triggers the live preview side effect via the field_value/2 accessor from plan 01."
    - "Account SSH_KEYS tab renders through Display.ConsoleTable with stable columns, honest empty-state copy, selection-driven revoke flow."
    - "Existing Account behavior tests (save/dirty/error/load/revoke) pass unmodified — no assertion weakening (D-19)."
    - "Account profile, prefs, and ssh_keys tabs render within bounds at 64x22 and 80x24 with at least one Phase 24 primitive sentinel present (D-09, D-10)."
    - "No hardcoded color atoms introduced in converted Account modules (D-12, R8)."
    - "Account does NOT consume the shared InvitesSurface in this phase — Account scope is profile/prefs/ssh_keys only per CONTEXT D-09; see SPEC §2 amendment (post-Codex review). The shared InvitesSurface is converted in Plan 03 for Moderation only."
  artifacts:
    - path: "lib/foglet_bbs/tui/screens/account/state.ex"
      provides: "Holds %Modal.Form{} for profile + prefs and %ConsoleTable{} for ssh_keys."
      contains: "Modal.Form"
    - path: "lib/foglet_bbs/tui/screens/account/profile_form.ex"
      provides: "Renders via Modal.Form.render/2; routes events through Modal.Form.handle_event/2; uses Process-dictionary stash adapter for submit payload (Pattern 1 / Pitfall 2)."
      contains: "Modal.Form.render"
    - path: "lib/foglet_bbs/tui/screens/account/prefs_form.ex"
      provides: "Modal.Form-backed prefs with `:enum` fields; preserves candidate_theme_id live preview via field_value/2 diffing after each handle_event/2."
      contains: "field_value"
    - path: "lib/foglet_bbs/tui/screens/account/ssh_keys_surface.ex"
      provides: "Renders via ConsoleTable.render/2; SelectionList usage removed."
      contains: "ConsoleTable.render"
    - path: "test/support/foglet/tui/layout_smoke/account_helper.ex"
      provides: "Per-tab size-contract blocks for `account profile`, `account prefs`, `account ssh_keys` at [{64,22},{80,24}] inside register_account_size_contracts/0 (Plan 01 stub)."
      contains: "account profile tab — size contract"
  key_links:
    - from: "lib/foglet_bbs/tui/screens/account.ex"
      to: "lib/foglet_bbs/tui/screens/account/{profile_form,prefs_form,ssh_keys_surface}.ex"
      via: "render_tab_body dispatch by active_tab"
      pattern: "active_tab"
    - from: "lib/foglet_bbs/tui/screens/account/prefs_form.ex"
      to: "lib/foglet_bbs/tui/widgets/modal/form.ex Modal.Form.field_value/2"
      via: "post-event field-value diff for live theme preview"
      pattern: "Modal.Form.field_value"
    - from: "lib/foglet_bbs/tui/screens/account/ssh_keys_state.ex"
      to: "lib/foglet_bbs/tui/widgets/display/console_table.ex ConsoleTable.handle_event/2"
      via: "selection cursor + {:row_selected, row} action"
      pattern: "ConsoleTable.handle_event"
---

<objective>
Convert all three Account tab bodies (profile, prefs, ssh_keys) from bespoke padded-string + SelectionList
rendering to the Phase 24 operator-console primitives (Modal.Form for forms; ConsoleTable for ssh_keys).
Preserve every existing behavior — save/dirty/error tracking, prefs candidate-theme live preview, SSH key
load/revoke confirmation flow, and all keybindings — per D-18/D-19. Add per-tab layout-smoke blocks for
PROFILE, PREFS, SSH_KEYS at 64x22 and 80x24.

Purpose: Account becomes the first dense, consistent operator workbench using the canonical
`sysop/boards_view.ex` Modal.Form-as-tab-body precedent (D-01) and the ConsoleTable selection-ownership
precedent (D-05).
Output: Refactored Account screen + state + sub-modules; extended account_test.exs with primitive-presence
asserts (no behavior-test changes); three new per-tab smoke blocks.
</objective>

<execution_context>
@/Users/brendan.turner/Dev/personal/foglet_bbs/.claude/get-shit-done/workflows/execute-plan.md
@/Users/brendan.turner/Dev/personal/foglet_bbs/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/phases/25-operator-console-conversion/25-CONTEXT.md
@.planning/phases/25-operator-console-conversion/25-RESEARCH.md
@.planning/phases/25-operator-console-conversion/25-SPEC.md
@.planning/phases/25-operator-console-conversion/25-01-shared-scaffolding-PLAN.md
@.planning/phases/24-operator-console-primitives/24-VERIFICATION.md
@AGENTS.md
@lib/foglet_bbs/tui/widgets/modal/form.ex
@lib/foglet_bbs/tui/widgets/display/console_table.ex
@lib/foglet_bbs/tui/widgets/display/badge.ex
@lib/foglet_bbs/tui/widgets/display/kv_grid.ex
@lib/foglet_bbs/tui/screens/sysop/boards_view.ex
@lib/foglet_bbs/tui/screens/account.ex
@lib/foglet_bbs/tui/screens/account/state.ex
@lib/foglet_bbs/tui/screens/account/profile_form.ex
@lib/foglet_bbs/tui/screens/account/prefs_form.ex
@lib/foglet_bbs/tui/screens/account/ssh_keys_state.ex
@lib/foglet_bbs/tui/screens/account/ssh_keys_surface.ex
@lib/foglet_bbs/tui/screens/account/ssh_keys_actions.ex
@lib/foglet_bbs/tui/presentation.ex
@test/foglet_bbs/tui/screens/account_test.exs
@test/support/foglet/tui/widget_helpers.ex
@test/support/foglet/tui/layout_smoke_helpers.ex
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Convert Account PROFILE and PREFS forms to Modal.Form</name>
  <files>lib/foglet_bbs/tui/screens/account/state.ex, lib/foglet_bbs/tui/screens/account/profile_form.ex, lib/foglet_bbs/tui/screens/account/prefs_form.ex, lib/foglet_bbs/tui/screens/account.ex, test/foglet_bbs/tui/screens/account_test.exs</files>
  <read_first>
    - lib/foglet_bbs/tui/screens/sysop/boards_view.ex (lines 34, 147-148, 235-294, 436-494 — canonical Modal.Form-as-tab-body precedent including Process-dict stash)
    - lib/foglet_bbs/tui/widgets/modal/form.ex (full file — init/handle_event/render/set_errors API)
    - lib/foglet_bbs/tui/screens/account/profile_form.ex (full file — current bespoke render + field handling)
    - lib/foglet_bbs/tui/screens/account/prefs_form.ex (full file — pay attention to lines 160-220 candidate_theme_id live preview)
    - lib/foglet_bbs/tui/screens/account/state.ex (full file — current state struct shape)
    - lib/foglet_bbs/tui/screens/account.ex (full file — render_tab_body dispatch)
    - test/foglet_bbs/tui/screens/account_test.exs (existing behavior tests — these MUST keep passing per D-19)
    - .planning/phases/25-operator-console-conversion/25-RESEARCH.md (Pattern 1, Pitfalls 1-5)
    - .planning/phases/25-operator-console-conversion/25-01-shared-scaffolding-PLAN.md (Modal.Form Shift+Tab + field_value/2 outcome)
  </read_first>
  <behavior>
    - Test (new, primitive-presence): rendered PROFILE tab body contains the Modal.Form footer sentinel "[Enter] Submit" (or whatever the refreshed Modal.Form footer copy is — read form.ex:144-169) AND the form heading text.
    - Test (new, primitive-presence): rendered PROFILE tab body contains a labeled field row for each field defined by profile_fields/1.
    - Test (new, primitive-presence): when `Modal.Form.set_errors/2` is applied (e.g., via simulating a domain {:error, changeset}), inline error text renders adjacent to the affected field.
    - Test (new, primitive-presence): rendered PREFS tab body contains Modal.Form footer sentinel AND a `:enum` field rendering for theme selection (RadioGroup-style choice list).
    - Test (preservation, existing): all existing tests in `test/foglet_bbs/tui/screens/account_test.exs` related to profile save/dirty/error and prefs save/dirty/error pass unmodified.
    - Test (new): cycling the prefs `:enum` theme field via `%{key: :down}` results in the screen state's `candidate_theme_id` updating (live preview preserved).
  </behavior>
  <action>
    Mirror `lib/foglet_bbs/tui/screens/sysop/boards_view.ex` exactly (Pattern 1 in RESEARCH).

    1. **`account/state.ex`** — add fields `:profile_form` and `:prefs_form` (both `%Modal.Form{} | nil`).
       Keep all existing fields. Do NOT remove any current state field until task 1 completes and tests
       are green; remove the now-unused fields (e.g., per-form `:focus`, `:errors` maps if Modal.Form
       owns them) in a follow-up step inside this same task — verify each existing test still passes
       after each removal.

    2. **`account/profile_form.ex`** — replace the bespoke render with `Modal.Form.render(form, theme:
       theme)`. Build `fields:` from the user's editable profile attributes (handle, location, signature,
       etc. — read the current `cast` keys to identify the exact set). Use `:text` field types; mark
       required fields with `required: true` (Modal.Form will render the required marker). Wire
       `on_submit:` to the Process-dict stash adapter exactly as in `boards_view.ex:436-439`:

       ```elixir
       defp stash_submit(payload) do
         Process.put({__MODULE__, :pending_submit}, payload)
         :ok
       end
       ```

       In `handle_key/2` (or whatever the entrypoint is — match the existing module's public API), call
       `Modal.Form.handle_event/2`, inspect the action, and on `:submitted` read the stashed payload and
       call `Foglet.Accounts.update_profile/2` (or whichever existing context function — DO NOT add
       authorization or context calls; reuse the exact call the current bespoke form makes). On
       `{:error, %Ecto.Changeset{} = cs}`, call `Modal.Form.set_errors(form, changeset_errors(cs))`
       to fan inline errors back to the form. Reuse any existing `changeset_errors/1` helper; if none
       exists, add a private one that returns `%{field => [String.t()]}`.

       Per Pitfall 4: do NOT wrap the `Modal.Form.render/2` output in a box/border — body-only contract.

    3. **`account/prefs_form.ex`** — same pattern as profile_form. Field types: `:enum` for theme and
       any other choice-based pref (use the form_test.exs accessor confirmed in plan 01); `:text` /
       `:integer` / `:boolean` for others as appropriate. After every `Modal.Form.handle_event/2` call,
       diff `Modal.Form.field_value(new_form, :theme_id)` against
       `Modal.Form.field_value(old_form, :theme_id)` and, if changed, set
       `state.candidate_theme_id` to the new value (preserves the existing live-preview side effect per
       A1 / Pitfall 5). Reference plan 01 SUMMARY for the documented accessor.

    4. **`account.ex`** — `render_tab_body` for PROFILE and PREFS now delegates to the converted
       sub-modules. Confirm `:active_tab` (or equivalent — verify name from state.ex) drives dispatch.
       Do not change tab-bar wiring; do not change chrome (Phase 18 owns it).

    5. **`test/foglet_bbs/tui/screens/account_test.exs`** — ADD a `describe "PROFILE Modal.Form
       primitive presence"` block and a `describe "PREFS Modal.Form primitive presence"` block.
       Render each tab body and assert via `Foglet.TUI.WidgetHelpers.flatten_text/1` (or the file's
       existing render-text helper — read it first) that:
         - Modal.Form footer sentinel string is present (read the exact copy from form.ex:144-169 — do
           not invent).
         - Form heading text is present.
         - Each expected field label appears.
         - For PREFS only: cycling `:down` on the focused theme `:enum` field updates
           `state.account.candidate_theme_id`.
         - For at least one field with `required: true`: required marker glyph (read form.ex for the
           exact glyph — likely `*`) appears next to the label.
         - Inline error: simulate domain failure by injecting `Modal.Form.set_errors(form, %{handle:
           ["is too short"]})` and assert the error text renders.
       DO NOT modify or delete any existing test in this file (D-19).

    Per D-18: no domain logic, authorization, or PubSub wiring moves. Reuse the same `Foglet.Accounts.*`
    function calls the bespoke forms made.

    Per D-12 / R8: no hardcoded color atoms. All theme access via `theme.<slot>.fg/bg/style` reads from
    the passed `theme` arg — never `:cyan`, `:red`, etc.
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/screens/account_test.exs</automated>
  </verify>
  <acceptance_criteria>
    - `grep -c "Modal.Form" lib/foglet_bbs/tui/screens/account/profile_form.ex` returns >= 2.
    - `grep -c "Modal.Form" lib/foglet_bbs/tui/screens/account/prefs_form.ex` returns >= 2.
    - `grep -n "Modal.Form.field_value\|field_value(" lib/foglet_bbs/tui/screens/account/prefs_form.ex` returns at least one match (live-preview integration).
    - `grep -n "Modal.Form.SubmitStash\|SubmitStash" lib/foglet_bbs/tui/screens/account/profile_form.ex` returns at least 1 match (Codex Concern 4 — uses shared helper, not raw Process.put).
    - `grep -n "Modal.Form.SubmitStash\|SubmitStash" lib/foglet_bbs/tui/screens/account/prefs_form.ex` returns at least 1 match.
    - `grep -nE "Process\.(put|get)\(" lib/foglet_bbs/tui/screens/account/{profile_form,prefs_form}.ex` returns 0 matches (Codex Concern 4 — raw process-dict access forbidden in converted modules; use SubmitStash instead).
    - `grep -nE "fg: :(cyan|red|yellow|green|blue|magenta|white|black)" lib/foglet_bbs/tui/screens/account/{profile_form,prefs_form,state}.ex` returns 0 matches (theme hygiene per D-12/R8 — Plan 05 also runs the canonical `color_atom_leaked?/2` test).
    - `grep -n "PROFILE Modal.Form primitive presence\|PREFS Modal.Form primitive presence" test/foglet_bbs/tui/screens/account_test.exs` returns matches.
    - `rtk mix test test/foglet_bbs/tui/screens/account_test.exs` exits 0 (all existing + new tests pass).
    - `git diff test/foglet_bbs/tui/screens/account_test.exs` shows only additive changes outside the new describe blocks (no `assert` deletions or `refute` weakenings).
  </acceptance_criteria>
  <done>PROFILE and PREFS tabs render through Modal.Form with required markers, inline errors, action footer, and preserved live-preview behavior; account_test.exs exits 0 with new primitive-presence asserts and unchanged behavior tests.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Convert Account SSH_KEYS surface to ConsoleTable</name>
  <files>lib/foglet_bbs/tui/screens/account/ssh_keys_state.ex, lib/foglet_bbs/tui/screens/account/ssh_keys_surface.ex, lib/foglet_bbs/tui/screens/account/ssh_keys_actions.ex, test/foglet_bbs/tui/screens/account_test.exs</files>
  <read_first>
    - lib/foglet_bbs/tui/widgets/display/console_table.ex (full file — init opts, handle_event return shape `{state, action}`, selectable contract, empty_state rendering)
    - lib/foglet_bbs/tui/widgets/display/table.ex (lines 88-110, 194 — width default 20 vs ConsoleTable's 12, Pitfall 9; empty-row guard, Pitfall 3)
    - lib/foglet_bbs/tui/screens/account/ssh_keys_state.ex (full file — current selected_index field per D-05)
    - lib/foglet_bbs/tui/screens/account/ssh_keys_surface.ex (full file — current SelectionList/ListRow render)
    - lib/foglet_bbs/tui/screens/account/ssh_keys_actions.ex (full file — current revoke confirm flow)
    - lib/foglet_bbs/tui/screens/sysop/boards_view.ex (lines 443-485 — canonical ConsoleTable.handle_event + action-tuple precedent)
    - .planning/phases/25-operator-console-conversion/25-RESEARCH.md (Pattern 2, Pitfalls 3, 7, 9)
  </read_first>
  <behavior>
    - Test (new, primitive-presence): SSH_KEYS tab body with non-empty fixture renders ConsoleTable header row containing column labels "Label", "Fingerprint", "Created", "Last used".
    - Test (new, primitive-presence): SSH_KEYS tab body with EMPTY fixture renders the configured empty-state copy (e.g., "No SSH keys registered yet.").
    - Test (new, behavior): Pressing `:down` on a non-empty list moves the ConsoleTable cursor (verify via `ConsoleTable` cursor inspection or rendered-row highlight assertion).
    - Test (new, behavior): Pressing `:enter` on a row dispatches the existing revoke-confirm flow — assert the same downstream effect the bespoke version produced (read existing test for `revoke` flow to mirror its assertion).
    - Test (new, behavior): Pressing `:up`, `:down`, AND `:enter` on an EMPTY ssh-keys list each returns cleanly — no crash, no revoke dispatch (Pitfall 3 + Codex LOW suggestion — empty-table keypress coverage).
    - Test (preservation): all existing SSH-key load / revoke / confirm tests in `account_test.exs` pass unmodified.
  </behavior>
  <action>
    Per D-04 and D-05:

    1. **`account/ssh_keys_state.ex`** — replace the bespoke `selected_index` (or whatever the current
       cursor field is named) with a `:table` field holding a `%ConsoleTable{}`. Initialize via:

       ```elixir
       ConsoleTable.init(
         columns: [
           %{key: :label,       label: "Label",       width: 20},
           %{key: :fingerprint, label: "Fingerprint", width: 24},
           %{key: :created,     label: "Created",     width: 11},
           %{key: :last_used,   label: "Last used",   width: 18}
         ],
         rows: [],
         selectable: true,
         empty_state: "No SSH keys registered yet."
       )
       ```

       Per Pitfall 9: every column MUST specify `:width` explicitly. Verify the chosen widths fit
       within 64-col viewport minus chrome (~62 usable). At 64x22, `Last used` may overflow — drop or
       tighten widths as needed; Plan 05's per-tab smoke test will catch overflow.

       After `Foglet.Accounts.list_ssh_keys/1` (or current call) returns items, rebuild rows via a new
       `set_items/2` helper that re-inits the ConsoleTable with the same columns + empty_state and the
       freshly-mapped row maps. Each row map MUST include an `:id` field (used for revoke dispatch).

    2. **`account/ssh_keys_surface.ex`** — replace the SelectionList-based render with
       `ConsoleTable.render(state.table, theme: theme)`. Keep the surrounding key-hint footer text
       (existing copy) but route any color via `theme.dim.fg` (no hardcoded atoms).

    3. **Event routing** — in `ssh_keys_state.ex` `handle_key/2` (or `ssh_keys_actions.ex`, depending on
       which currently owns key handling — read both first):

       ```elixir
       def handle_key(event, state) do
         {new_table, action} = ConsoleTable.handle_event(event, state.table)
         state = %{state | table: new_table}

         case action do
           {:row_selected, row} ->
             # dispatch the SAME revoke-confirm flow the bespoke version used
             {state, [{:account_revoke_key_confirm, row.id}]}
           _ ->
             {state, []}
         end
       end
       ```

       Read the existing handle_key first to identify the exact action atom name and downstream
       contract. DO NOT change the contract — only the event source (now ConsoleTable instead of
       bespoke arithmetic).

       Per Pitfall 3: do not branch on `state.rows == []`; always route through
       `ConsoleTable.handle_event/2`. The widget short-circuits empty cases safely.

       Per Pitfall 7 spirit (read-only honesty doesn't apply here — SSH keys ARE selection-driven —
       but still verify `selectable: true` is intentional).

    4. **`test/foglet_bbs/tui/screens/account_test.exs`** — ADD a `describe "SSH_KEYS ConsoleTable
       primitive presence"` block. Test cases per the Behavior section above. Use `flatten_text/1` from
       WidgetHelpers (or the file's existing helper) to assert column-header strings and empty-state
       copy. For the empty-list arrow-key test, assert no exception is raised.

       DO NOT modify existing SSH-key tests (D-19).
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/screens/account_test.exs</automated>
  </verify>
  <acceptance_criteria>
    - `grep -c "ConsoleTable" lib/foglet_bbs/tui/screens/account/ssh_keys_state.ex` returns >= 2.
    - `grep -c "ConsoleTable.render\|ConsoleTable" lib/foglet_bbs/tui/screens/account/ssh_keys_surface.ex` returns >= 1.
    - `grep -nE "selected_index|SelectionList|ListRow" lib/foglet_bbs/tui/screens/account/ssh_keys_{state,surface,actions}.ex` returns 0 matches (D-05 — bespoke selection state and SelectionList removed).
    - `grep -n "empty_state:" lib/foglet_bbs/tui/screens/account/ssh_keys_state.ex` returns at least one match.
    - `grep -nE "width:\s*[0-9]+" lib/foglet_bbs/tui/screens/account/ssh_keys_state.ex` returns at least 4 matches (one per column — Pitfall 9).
    - `grep -n "SSH_KEYS ConsoleTable primitive presence" test/foglet_bbs/tui/screens/account_test.exs` returns at least one match.
    - `rtk mix test test/foglet_bbs/tui/screens/account_test.exs` exits 0.
  </acceptance_criteria>
  <done>SSH_KEYS tab renders through ConsoleTable with explicit column widths, honest empty-state copy, and selection-driven revoke; all existing SSH-key behavior tests still pass; bespoke selection_index and SelectionList references removed from converted modules.</done>
</task>

<task type="auto">
  <name>Task 3: Per-tab layout-smoke blocks for Account PROFILE / PREFS / SSH_KEYS</name>
  <files>test/support/foglet/tui/layout_smoke/account_helper.ex</files>
  <read_first>
    - test/foglet_bbs/tui/layout_smoke_test.exs (lines 273-353 — Phase 22/20 size-contract precedent per D-11)
    - test/support/foglet/tui/layout_smoke_helpers.ex (set_active_tab/2 from plan 01)
    - .planning/phases/25-operator-console-conversion/25-CONTEXT.md (D-09, D-10, D-11)
    - .planning/phases/25-operator-console-conversion/25-RESEARCH.md ("Per-tab layout smoke test" code example)
    - lib/foglet_bbs/tui/widgets/modal/form.ex (lines 144-169 — exact footer copy used as primitive sentinel)
    - lib/foglet_bbs/tui/widgets/display/console_table.ex (empty_state render copy / column header rendering for sentinel)
  </read_first>
  <action>
    Add three `describe` blocks INSIDE the `register_account_size_contracts/0` macro body in
    `test/support/foglet/tui/layout_smoke/account_helper.ex` (the stub created in Plan 01 Task 3).
    Do NOT modify `test/foglet_bbs/tui/layout_smoke_test.exs` directly — Plan 01 already wired it as a
    thin registry that invokes the macro. This decoupling avoids merge conflicts with Plans 03/04
    (Codex Concern 3).

    The three blocks are:

    1. `describe "account profile tab — size contract"`
    2. `describe "account prefs tab — size contract"`
    3. `describe "account ssh_keys tab — size contract"`

    Each block follows the Phase 22/20 precedent at lines 273-353 (D-11) and uses the
    `Foglet.TUI.LayoutSmokeHelpers.set_active_tab/2` helper. For each, iterate
    `for {width, height} <- [{64, 22}, {80, 24}]`. Per D-10, each test asserts:

    (a) **Bounds** — every text element satisfies
        `el.x + Foglet.TUI.TextWidth.display_width(el.text) <= width`
        AND `el.y + height_of(el) <= height`.

    (b) **Primitive sentinel** — at least one of these substrings appears in the rendered text:
        - PROFILE / PREFS: the Modal.Form footer string (read exact copy from form.ex:144-169).
        - SSH_KEYS (non-empty fixture): the column-header label "Label" (or whatever ConsoleTable
          renders as the header row sentinel — read console_table.ex render output).

    (c) **No-overlap** — no two text elements occupy the same `{x, y}` position.

    Build representative state. For PROFILE/PREFS, the form must be initialized with sample fields
    (build a small `current_user` fixture and invoke `Account.init_screen_state/0` plus the
    set-active-tab helper, then trigger any required form-init callback the screen exposes). For
    SSH_KEYS, supply 1-2 sample key rows so the table renders header + body (empty case is verified by
    the primitive-presence test in task 2; smoke tests use non-empty fixtures so that header sentinel
    is reliably present).

    Tag each test with `@tag :"account <tab> size contract"` for selective runs.

    Do NOT add any wide-terminal `132x50` block (D-10 explicitly excludes).
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs --only "account profile size contract" --only "account prefs size contract" --only "account ssh_keys size contract"</automated>
  </verify>
  <acceptance_criteria>
    - `grep -n "account profile tab — size contract" test/support/foglet/tui/layout_smoke/account_helper.ex` returns at least one match.
    - `grep -n "account prefs tab — size contract" test/support/foglet/tui/layout_smoke/account_helper.ex` returns at least one match.
    - `grep -n "account ssh_keys tab — size contract" test/support/foglet/tui/layout_smoke/account_helper.ex` returns at least one match.
    - Each describe block contains a `for {width, height} <- [{64, 22}, {80, 24}]` loop.
    - `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs --only "account profile size contract"` runs at least 2 tests and they pass.
    - `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs --only "account prefs size contract"` runs at least 2 tests and they pass.
    - `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs --only "account ssh_keys size contract"` runs at least 2 tests and they pass.
    - `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` exits 0 (no regression in any other smoke block).
  </acceptance_criteria>
  <done>Three per-tab smoke blocks exist for Account, each iterating 64x22 and 80x24 with bounds + primitive-sentinel + no-overlap assertions; full smoke suite passes.</done>
</task>

</tasks>

<verification>
- `rtk mix test test/foglet_bbs/tui/screens/account_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` exits 0.
- No domain context (`Foglet.Accounts`, `Foglet.Authorization`) function added or removed.
- No new field added to any context schema or struct outside `account/state.ex`.
- `Workspace.Inspector` is not referenced from any Account module (verified globally in plan 05).
</verification>

<success_criteria>
- ACCOUNT-01 satisfied: profile, prefs, ssh_keys tabs render through Phase 24 primitives.
- All existing `account_test.exs` behavior tests pass unmodified (D-19).
- Live theme-preview side effect on prefs cycling is preserved.
- Per-tab smoke at 64x22 and 80x24 passes for all three Account tabs.
</success_criteria>

<output>
After completion, create `.planning/phases/25-operator-console-conversion/25-02-SUMMARY.md` capturing:
- Final field list per converted form (profile + prefs).
- Final ConsoleTable column widths chosen for SSH_KEYS at 64x22 (Pitfall 9 record).
- Confirmation that candidate_theme_id live preview is preserved with reference to the diff site in prefs_form.ex.
- Any state.ex fields removed during cleanup.
</output>
