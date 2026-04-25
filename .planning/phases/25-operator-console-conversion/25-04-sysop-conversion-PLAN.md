---
phase: 25
plan: 04
type: execute
wave: 2
depends_on: [01]
files_modified:
  - lib/foglet_bbs/tui/screens/sysop.ex
  - lib/foglet_bbs/tui/screens/sysop/state.ex
  - lib/foglet_bbs/tui/screens/sysop/site_form.ex
  - lib/foglet_bbs/tui/screens/sysop/limits_form.ex
  - lib/foglet_bbs/tui/screens/sysop/users_view.ex
  - lib/foglet_bbs/tui/screens/sysop/system_snapshot.ex
  - lib/foglet_bbs/tui/screens/sysop/boards_view.ex
  - test/foglet_bbs/tui/screens/sysop_test.exs
  - test/foglet_bbs/tui/screens/sysop/site_form_test.exs
  - test/foglet_bbs/tui/screens/sysop/config_accountability_test.exs
  - test/foglet_bbs/tui/layout_smoke_test.exs
autonomous: true
requirements:
  - SYSOP-01
user_setup: []
tags:
  - tui
  - operator-console
  - sysop
  - elixir

must_haves:
  truths:
    - "Sysop SITE and LIMITS forms render through Modal.Form (heading, required markers, inline errors, action footer); existing Foglet.Config.put/3 write paths and authorization checks unchanged (D-18)."
    - "SITE form respects visible_keys/1 conditional visibility — `invite_generation_per_user_limit` only appears when `invite_code_generators == \"any_user\"` (Pitfall 6)."
    - "Sysop USERS tab renders through ConsoleTable with selection-driven status transitions preserved."
    - "Sysop SYSTEM snapshot renders through KvGrid with metric badges (`:healthy`/`:error`/`:pending`/`:info`) for value cells where status is implied."
    - "Sysop BOARDS tab — already converted to Modal.Form per the boards_view.ex precedent — destructive command-bar entries (Archive board, Archive category) route through `Foglet.TUI.Presentation.theme_mappings().commands.destructive` (D-07)."
    - "All existing Sysop tests (sysop_test.exs, sysop/site_form_test.exs, sysop/config_accountability_test.exs) pass unmodified (D-19)."
    - "Per-tab layout smoke at 64x22 and 80x24 passes for SITE, LIMITS, BOARDS, USERS, SYSTEM (D-09, D-10)."
  artifacts:
    - path: "lib/foglet_bbs/tui/screens/sysop/state.ex"
      provides: "Holds %Modal.Form{} for site + limits and %ConsoleTable{} for users; KvGrid entries for system snapshot."
      contains: "Modal.Form"
    - path: "lib/foglet_bbs/tui/screens/sysop/site_form.ex"
      provides: "Modal.Form-backed SITE form respecting visible_keys/1 (re-init on invite_code_generators change per Pitfall 6)."
      contains: "Modal.Form"
    - path: "lib/foglet_bbs/tui/screens/sysop/limits_form.ex"
      provides: "Modal.Form-backed LIMITS form."
      contains: "Modal.Form"
    - path: "lib/foglet_bbs/tui/screens/sysop/users_view.ex"
      provides: "ConsoleTable-backed USERS listing with selection-driven status-transition dispatch."
      contains: "ConsoleTable"
    - path: "lib/foglet_bbs/tui/screens/sysop/system_snapshot.ex"
      provides: "KvGrid-backed snapshot with metric badges (healthy/info)."
      contains: "KvGrid"
    - path: "test/foglet_bbs/tui/layout_smoke_test.exs"
      provides: "Per-tab size-contract blocks for sysop site, limits, boards, users, system."
      contains: "sysop site tab — size contract"
  key_links:
    - from: "lib/foglet_bbs/tui/screens/sysop/site_form.ex"
      to: "lib/foglet_bbs/tui/widgets/modal/form.ex"
      via: "Modal.Form.init re-invocation when invite_code_generators changes (Pitfall 6)"
      pattern: "visible_keys"
    - from: "lib/foglet_bbs/tui/screens/sysop/users_view.ex"
      to: "Foglet.Accounts.transition_status/3"
      via: "{:row_selected, %{id: user_id}} dispatch"
      pattern: "Foglet.Accounts.transition_status"
    - from: "lib/foglet_bbs/tui/screens/sysop/boards_view.ex"
      to: "Foglet.TUI.Presentation.theme_mappings().commands.destructive"
      via: "destructive command-bar styling per D-07"
      pattern: "destructive"
---

<objective>
Convert Sysop's five tab bodies (SITE, LIMITS, BOARDS, USERS, SYSTEM) to Phase 24 operator-console
primitives. SITE and LIMITS adopt Modal.Form; USERS adopts ConsoleTable with selection-driven status
transitions; SYSTEM snapshot adopts KvGrid with metric badges. BOARDS is already converted (canonical
precedent) — verify destructive-action styling routes through `commands.destructive` per D-07. Preserve
all `Foglet.Config` and `Foglet.Accounts` mutation paths and authorization checks (D-18). Honor SITE's
conditional `visible_keys/1` (Pitfall 6).

Purpose: Sysop is the highest-surface conversion (5 tabs) and gates `SYSOP-01`. This plan pushes every
remaining bespoke padded-string surface in operator screens through the primitive layer.
Output: Refactored Sysop screen + state + sub-modules; extended sysop tests with primitive-presence
asserts (no behavior changes); five per-tab smoke blocks.
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
@lib/foglet_bbs/tui/widgets/display/kv_grid.ex
@lib/foglet_bbs/tui/widgets/display/badge.ex
@lib/foglet_bbs/tui/widgets/chrome/command_bar.ex
@lib/foglet_bbs/tui/screens/sysop.ex
@lib/foglet_bbs/tui/screens/sysop/state.ex
@lib/foglet_bbs/tui/screens/sysop/boards_view.ex
@lib/foglet_bbs/tui/screens/sysop/site_form.ex
@lib/foglet_bbs/tui/screens/sysop/limits_form.ex
@lib/foglet_bbs/tui/screens/sysop/users_view.ex
@lib/foglet_bbs/tui/screens/sysop/system_snapshot.ex
@lib/foglet_bbs/tui/presentation.ex
@test/foglet_bbs/tui/screens/sysop_test.exs
@test/foglet_bbs/tui/screens/sysop/site_form_test.exs
@test/foglet_bbs/tui/screens/sysop/config_accountability_test.exs
@test/support/foglet/tui/widget_helpers.ex
@test/support/foglet/tui/layout_smoke_helpers.ex
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Convert Sysop SITE and LIMITS forms to Modal.Form (with visible_keys re-init for SITE)</name>
  <files>lib/foglet_bbs/tui/screens/sysop/state.ex, lib/foglet_bbs/tui/screens/sysop/site_form.ex, lib/foglet_bbs/tui/screens/sysop/limits_form.ex, lib/foglet_bbs/tui/screens/sysop.ex, test/foglet_bbs/tui/screens/sysop_test.exs, test/foglet_bbs/tui/screens/sysop/site_form_test.exs</files>
  <read_first>
    - lib/foglet_bbs/tui/screens/sysop/boards_view.ex (lines 34, 147-148, 235-294, 436-494 — canonical precedent)
    - lib/foglet_bbs/tui/screens/sysop/site_form.ex (full file — pay attention to lines 69-77 visible_keys/1 conditional logic for `invite_generation_per_user_limit`)
    - lib/foglet_bbs/tui/screens/sysop/limits_form.ex (full file)
    - lib/foglet_bbs/tui/screens/sysop/state.ex (full file — current state struct)
    - lib/foglet_bbs/tui/widgets/modal/form.ex (full — init/handle_event/render/set_errors)
    - test/foglet_bbs/tui/screens/sysop_test.exs (existing config save / dirty / error tests)
    - test/foglet_bbs/tui/screens/sysop/site_form_test.exs (existing visible-key tests — these MUST keep passing per D-19)
    - test/foglet_bbs/tui/screens/sysop/config_accountability_test.exs (existing accountability test)
    - .planning/phases/25-operator-console-conversion/25-RESEARCH.md (Pattern 1, Pitfalls 1, 2, 4, 6)
    - .planning/phases/25-operator-console-conversion/25-01-shared-scaffolding-PLAN.md (Modal.Form scaffolding outcome)
  </read_first>
  <behavior>
    - Test (new, primitive-presence): SITE tab body renders Modal.Form footer sentinel + heading + each visible field label.
    - Test (new, behavior — Pitfall 6): when `invite_code_generators == "any_user"`, the SITE form's fields list includes `:invite_generation_per_user_limit`; when `invite_code_generators` has any other value, the field is absent. Re-init the form when the controlling field changes.
    - Test (new, primitive-presence): LIMITS tab body renders Modal.Form footer sentinel + heading + each field label, with required markers where `required: true`.
    - Test (new, behavior): on simulated domain `{:error, %Ecto.Changeset{}}`, inline error text renders via `Modal.Form.set_errors/2`.
    - Test (preservation): all existing tests in sysop_test.exs, sysop/site_form_test.exs, and sysop/config_accountability_test.exs pass unmodified.
  </behavior>
  <action>
    Mirror the `sysop/boards_view.ex` precedent (D-01 + Pattern 1).

    1. **`sysop/state.ex`** — add `:site_form` and `:limits_form` (each `%Modal.Form{} | nil`). Keep
       all existing state fields used by current tests until the conversion is complete and tests are
       green; remove any now-unused fields (e.g., per-form focus / error maps the bespoke forms owned)
       only after each removal is verified by the existing test suite passing.

    2. **`sysop/site_form.ex`** — replace bespoke render with `Modal.Form.render(form, theme: theme)`.
       Build `fields:` from `visible_keys(state)` (the existing helper at lines 69-77). Field types
       come from each Sysop config schema entry (`Foglet.Config.Schema` — read it to identify whether
       each key is `:string`/`:integer`/`:boolean`/`:enum`/etc. and map to Modal.Form field types).
       Mark fields with `required: true` per the schema's required flag.

       Wire `on_submit:` to a Process-dict stash adapter exactly as in `boards_view.ex:436-439`.

       In `handle_key/2`, after each `Modal.Form.handle_event/2` call, check whether the value of
       `:invite_code_generators` (read via `Modal.Form.field_value/2` from plan 01) has changed. If so,
       re-init the entire `%Modal.Form{}` via `Modal.Form.init/1` with the freshly-computed
       `visible_keys/1` field list — preserving any pending values from the prior form by reading
       each field via `Modal.Form.field_value/2` first and seeding the new init's `value:` (Pitfall 6).
       Document this in a code comment referencing Pitfall 6.

       On `:submitted`, read the stashed payload and call the EXISTING `Foglet.Config.put/3` (or the
       wrapper the bespoke form currently uses — read site_form.ex first to identify the exact call
       and authorization shape; do NOT change either per D-18). On `{:error, %Ecto.Changeset{}}`, call
       `Modal.Form.set_errors(form, changeset_errors(cs))`.

       Per Pitfall 4: do NOT wrap the Modal.Form output in box/border.

    3. **`sysop/limits_form.ex`** — same Modal.Form pattern. No conditional-visibility logic for
       LIMITS unless current code has one (read first); if not, plain `fields:` from the static keyset.

    4. **`sysop.ex`** — `render_tab_body` for SITE and LIMITS delegates to the converted sub-modules.
       Confirm the active-tab dispatch key (likely `:active_tab`).

    5. **Tests**:
       - `test/foglet_bbs/tui/screens/sysop_test.exs` — ADD `describe "SITE Modal.Form primitive
         presence"` and `describe "LIMITS Modal.Form primitive presence"` blocks per Behavior section.
       - `test/foglet_bbs/tui/screens/sysop/site_form_test.exs` — ADD `describe "visible_keys
         re-init (Pitfall 6)"` block: build a SITE form state with `invite_code_generators = "any_user"`,
         assert the field list includes `:invite_generation_per_user_limit`; mutate to a different
         value and trigger the re-init path (e.g., simulate the field-value change handler), assert
         the field is now absent. DO NOT modify or delete existing visible-keys tests.

    Per D-12 / R8: no hardcoded color atoms in any converted module.
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/screens/sysop_test.exs test/foglet_bbs/tui/screens/sysop/site_form_test.exs test/foglet_bbs/tui/screens/sysop/config_accountability_test.exs</automated>
  </verify>
  <acceptance_criteria>
    - `grep -c "Modal.Form" lib/foglet_bbs/tui/screens/sysop/site_form.ex` returns >= 2.
    - `grep -c "Modal.Form" lib/foglet_bbs/tui/screens/sysop/limits_form.ex` returns >= 2.
    - `grep -n "visible_keys" lib/foglet_bbs/tui/screens/sysop/site_form.ex` returns at least one match (re-init path uses it).
    - `grep -n "Pitfall 6\|invite_code_generators" lib/foglet_bbs/tui/screens/sysop/site_form.ex` returns at least one match documenting the re-init logic.
    - `grep -n "stash_submit\|pending_submit" lib/foglet_bbs/tui/screens/sysop/site_form.ex` returns matches.
    - `grep -n "stash_submit\|pending_submit" lib/foglet_bbs/tui/screens/sysop/limits_form.ex` returns matches.
    - `grep -nE "fg: :(cyan|red|yellow|green|blue|magenta|white|black)" lib/foglet_bbs/tui/screens/sysop/{site_form,limits_form,state}.ex` returns 0 matches.
    - `grep -n "SITE Modal.Form primitive presence\|LIMITS Modal.Form primitive presence" test/foglet_bbs/tui/screens/sysop_test.exs` returns matches.
    - `grep -n "visible_keys re-init\|Pitfall 6" test/foglet_bbs/tui/screens/sysop/site_form_test.exs` returns at least one match.
    - All three test commands pass (`rtk mix test test/foglet_bbs/tui/screens/sysop_test.exs test/foglet_bbs/tui/screens/sysop/site_form_test.exs test/foglet_bbs/tui/screens/sysop/config_accountability_test.exs` exits 0).
  </acceptance_criteria>
  <done>SITE and LIMITS render through Modal.Form; SITE re-inits on invite_code_generators change preserving Pitfall 6 visibility logic; all existing Sysop tests pass unmodified.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Convert Sysop USERS to ConsoleTable + SYSTEM snapshot to KvGrid; verify BOARDS destructive styling</name>
  <files>lib/foglet_bbs/tui/screens/sysop/state.ex, lib/foglet_bbs/tui/screens/sysop/users_view.ex, lib/foglet_bbs/tui/screens/sysop/system_snapshot.ex, lib/foglet_bbs/tui/screens/sysop/boards_view.ex, test/foglet_bbs/tui/screens/sysop_test.exs</files>
  <read_first>
    - lib/foglet_bbs/tui/screens/sysop/users_view.ex (full file — current SelectionList + selection logic + status-transition dispatch)
    - lib/foglet_bbs/tui/screens/sysop/system_snapshot.ex (full file — current `pad_trailing` rows at lines 36-57)
    - lib/foglet_bbs/tui/screens/sysop/boards_view.ex (lines 1-120, 230-300, 435-494 — verify destructive command-bar usage; confirm A3)
    - lib/foglet_bbs/tui/widgets/display/console_table.ex (full)
    - lib/foglet_bbs/tui/widgets/display/kv_grid.ex (lines 76-104 — `state:` / `badge:` per-row metadata)
    - lib/foglet_bbs/tui/widgets/chrome/command_bar.ex (lines 26, 87, 250 — `destructive?: true` precedent)
    - lib/foglet_bbs/tui/presentation.ex (lines 42-46, 96-101 — `commands.destructive` mapping)
    - .planning/phases/25-operator-console-conversion/25-RESEARCH.md (Pattern 2, Pattern 3, Pattern 4, Pitfalls 3, 7, 9; Code Examples — KvGrid conversion)
  </read_first>
  <behavior>
    - Test (new, primitive-presence): USERS tab renders ConsoleTable header (e.g., "Handle", "Role", "Status") + Badge cells for status (route via row metadata where applicable, or via Display.Badge inside an explicit cell render — Claude's discretion).
    - Test (new, behavior): pressing `:enter` on a user row dispatches `Foglet.Accounts.transition_status/3` (or the existing function — read users_view.ex) with the SAME payload shape the bespoke version produced.
    - Test (new, primitive-presence): SYSTEM snapshot renders KvGrid label/value rows including at least one cell with `state: :healthy` or `state: :info` (badge appears as `[…]`).
    - Test (new, behavior): SYSTEM `[r] Refresh` continues to refresh the snapshot — preserve existing key handling.
    - Test (new, source check): BOARDS view's destructive command-bar entries (Archive board, Archive category) set `destructive?: true` AND inline destructive emphasis routes through `Foglet.TUI.Presentation.theme_mappings().commands.destructive` (D-07) rather than hardcoded color atoms.
    - Test (preservation): all existing Sysop USERS, SYSTEM, BOARDS behavior tests pass unmodified.
  </behavior>
  <action>
    1. **`sysop/state.ex`** — add `:users_table` (`%ConsoleTable{} | nil`) and `:system_entries`
       (`[KvGrid entry] | nil`). Remove any bespoke `users_selected_index` only after the conversion
       passes its tests (D-05).

    2. **`sysop/users_view.ex`** — replace the SelectionList-based render with
       `ConsoleTable.render(state.users_table, theme: theme)`. Initialize via:

       ```elixir
       ConsoleTable.init(
         columns: [
           %{key: :handle, label: "Handle", width: 16},
           %{key: :role,   label: "Role",   width: 8},
           %{key: :status, label: "Status", width: 12},
           %{key: :since,  label: "Since",  width: 11}
         ],
         rows: load_users(...) |> Enum.map(&row_for/1),
         selectable: true,
         empty_state: "No users in scope."
       )
       ```

       Pitfall 9: explicit widths. `handle_key/2`:

       ```elixir
       {new_table, action} = ConsoleTable.handle_event(event, state.users_table)
       state = %{state | users_table: new_table}

       case action do
         {:row_selected, %{id: user_id}} ->
           # preserve EXISTING contract — read users_view.ex to identify the exact transition
           # function and authorization preflight; do NOT change either (D-18).
           {state, [{:sysop_user_transition_confirm, user_id}]}
         _ ->
           {state, []}
       end
       ```

       Pitfall 3: always route through `ConsoleTable.handle_event/2`.

       For the status column, Claude's discretion per CONTEXT: either (a) render plain text status
       and let the per-tab smoke focus on table sentinels, or (b) embed Badge labels in the row by
       providing `status: "[active]"` style strings — but PREFER routing through Display.Badge inside
       a status-cell render hook if ConsoleTable exposes one; otherwise plain text is acceptable and
       the badge requirement (`MOD-01`-style summary) is satisfied by the SYSTEM snapshot KvGrid in
       step 3.

    3. **`sysop/system_snapshot.ex`** — replace `snapshot_row/3` and the `pad_trailing` row builders
       (lines 36-57) with a single `KvGrid.render/2` call following the RESEARCH "Convert a bespoke
       padded-string row block to KvGrid" code example verbatim:

       ```elixir
       entries = [
         %{label: "Version",       value: s.version},
         %{label: "Uptime",        value: format_uptime(s.uptime_ms)},
         %{label: "Sessions",      value: Integer.to_string(s.session_count), state: :healthy},
         %{label: "Active boards", value: Integer.to_string(s.board_count),   state: :healthy},
         %{label: "OTP processes", value: Integer.to_string(s.process_count)},
         %{label: "DB pool size",  value: Integer.to_string(s.db_pool_size),  state: :info}
       ]

       column style: %{gap: 0} do
         [text("System snapshot", fg: theme.title.fg, style: [:bold]),
          text(""),
          KvGrid.render(entries, theme: theme, width: 60, label_width: 16, gap: 2),
          text(""),
          text("[r] Refresh", fg: theme.dim.fg)]
       end
       ```

       Per D-08: do NOT add new theme slots. The existing `theme.title.fg` and `theme.dim.fg` are
       reused. Adjust which entries get `state:` vs none based on what the current snapshot fields
       semantically imply (e.g., `db_pool_size` near limit -> `state: :pending`; pool exhausted
       -> `state: :error`). Keep this conservative — Claude's discretion per CONTEXT.

    4. **`sysop/boards_view.ex`** — VERIFY (do not rewrite — A3): the destructive command-bar entries
       (e.g., "Archive board", "Archive category") set `destructive?: true` on their command-bar entry
       AND any inline destructive emphasis (e.g., confirm-prompt accents) routes through:

       ```elixir
       slot = Foglet.TUI.Presentation.theme_mappings().commands.destructive  # :error
       Map.fetch!(theme, slot)
       ```

       If the current code references `theme.error` directly in destructive contexts, replace with the
       indirect mapping lookup so D-07's "single source of truth" routing holds. Add a code comment
       referencing D-07. Do NOT add a new `:destructive` theme slot (D-08).

    5. **Tests** — `test/foglet_bbs/tui/screens/sysop_test.exs`:
       - ADD `describe "USERS ConsoleTable primitive presence"` block per Behavior.
       - ADD `describe "SYSTEM KvGrid primitive presence"` block per Behavior.
       - ADD `describe "BOARDS destructive styling routes through commands.destructive (D-07)"` block.
         Test approach: render BOARDS tab body, serialize via `inspect(limit: :infinity)`, assert it
         contains a substring evidence of the destructive mapping (e.g., the destructive command-bar
         entry struct has `destructive?: true`). Alternatively, unit-test a private helper that
         computes the destructive style and assert it equals
         `Map.fetch!(theme, Foglet.TUI.Presentation.theme_mappings().commands.destructive)`.

       DO NOT modify or delete any existing tests.
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/screens/sysop_test.exs</automated>
  </verify>
  <acceptance_criteria>
    - `grep -c "ConsoleTable" lib/foglet_bbs/tui/screens/sysop/users_view.ex` returns >= 2.
    - `grep -nE "selected_index|SelectionList" lib/foglet_bbs/tui/screens/sysop/users_view.ex` returns 0 matches (D-05).
    - `grep -n "KvGrid" lib/foglet_bbs/tui/screens/sysop/system_snapshot.ex` returns at least 1 match.
    - `grep -nE "pad_trailing" lib/foglet_bbs/tui/screens/sysop/system_snapshot.ex` returns 0 matches (bespoke padded rows removed).
    - `grep -n "commands.destructive\|D-07" lib/foglet_bbs/tui/screens/sysop/boards_view.ex` returns at least 1 match.
    - `grep -nE "fg: :(cyan|red|yellow|green|blue|magenta|white|black)" lib/foglet_bbs/tui/screens/sysop/{users_view,system_snapshot,boards_view,state}.ex` returns 0 matches.
    - `grep -n "USERS ConsoleTable primitive presence\|SYSTEM KvGrid primitive presence\|BOARDS destructive styling" test/foglet_bbs/tui/screens/sysop_test.exs` returns at least 3 matches.
    - `rtk mix test test/foglet_bbs/tui/screens/sysop_test.exs` exits 0.
  </acceptance_criteria>
  <done>USERS uses ConsoleTable with selection-driven status transitions; SYSTEM uses KvGrid with metric badges; BOARDS destructive styling verified to route through commands.destructive; all existing Sysop tests pass unmodified.</done>
</task>

<task type="auto">
  <name>Task 3: Per-tab layout-smoke blocks for Sysop SITE / LIMITS / BOARDS / USERS / SYSTEM</name>
  <files>test/foglet_bbs/tui/layout_smoke_test.exs</files>
  <read_first>
    - test/foglet_bbs/tui/layout_smoke_test.exs (lines 273-353 — D-11 precedent; plan 01 example block for sysop boards)
    - test/support/foglet/tui/layout_smoke_helpers.ex
    - .planning/phases/25-operator-console-conversion/25-CONTEXT.md (D-09, D-10, D-11)
  </read_first>
  <action>
    Add five `describe` blocks to `test/foglet_bbs/tui/layout_smoke_test.exs`:

    1. `describe "sysop site tab — size contract"`
    2. `describe "sysop limits tab — size contract"`
    3. `describe "sysop boards tab — size contract"` — REPLACE the example block from plan 01 if it
       exists (the plan 01 block was a sentinel; this is the canonical version for the phase). Keep
       it semantically equivalent.
    4. `describe "sysop users tab — size contract"`
    5. `describe "sysop system tab — size contract"`

    Each follows the Phase 22/20 precedent + plan 01 example. Iterate
    `for {width, height} <- [{64, 22}, {80, 24}]`. Use representative non-empty fixtures so primitive
    sentinels are present. Per D-10:

    (a) Bounds — every text element fits.
    (b) Primitive sentinel — at least one of:
        - SITE/LIMITS: Modal.Form footer copy (read form.ex:144-169 for exact string).
        - BOARDS: ConsoleTable column header (e.g., "Board") OR Modal.Form footer if a create/edit
          modal is open.
        - USERS: ConsoleTable column header (e.g., "Handle").
        - SYSTEM: KvGrid label substring (e.g., "Sessions") AND a `[…]` Badge label substring (e.g.,
          `[healthy]`).
    (c) No-overlap.

    Tag each `@tag :"sysop <tab> size contract"`. No `132x50` (D-10).
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs --only "sysop site size contract" --only "sysop limits size contract" --only "sysop boards size contract" --only "sysop users size contract" --only "sysop system size contract"</automated>
  </verify>
  <acceptance_criteria>
    - `grep -n "sysop site tab — size contract" test/foglet_bbs/tui/layout_smoke_test.exs` returns at least 1 match.
    - `grep -n "sysop limits tab — size contract" test/foglet_bbs/tui/layout_smoke_test.exs` returns at least 1 match.
    - `grep -n "sysop boards tab — size contract" test/foglet_bbs/tui/layout_smoke_test.exs` returns at least 1 match.
    - `grep -n "sysop users tab — size contract" test/foglet_bbs/tui/layout_smoke_test.exs` returns at least 1 match.
    - `grep -n "sysop system tab — size contract" test/foglet_bbs/tui/layout_smoke_test.exs` returns at least 1 match.
    - Each block contains `for {width, height} <- [{64, 22}, {80, 24}]`.
    - Each `--only` filtered run yields at least 2 tests passing.
    - `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` exits 0.
  </acceptance_criteria>
  <done>Five per-tab smoke blocks exist for Sysop, each iterating 64x22 and 80x24; full smoke suite passes.</done>
</task>

</tasks>

<verification>
- `rtk mix test test/foglet_bbs/tui/screens/sysop_test.exs test/foglet_bbs/tui/screens/sysop/ test/foglet_bbs/tui/layout_smoke_test.exs` exits 0.
- `Foglet.Config.put/3` and `Foglet.Accounts.*` call sites unchanged in name and shape (D-18).
- `Workspace.Inspector` not referenced from any Sysop module (verified globally in plan 05).
</verification>

<success_criteria>
- SYSOP-01 satisfied: SITE, LIMITS, BOARDS, USERS, SYSTEM tabs render through Phase 24 primitives.
- SITE conditional visibility (visible_keys/1) preserved via re-init on invite_code_generators change.
- BOARDS destructive styling verified to route through commands.destructive (D-07).
- All existing Sysop tests pass unmodified (D-19).
- Per-tab smoke at 64x22 and 80x24 passes for all five Sysop tabs.
</success_criteria>

<output>
After completion, create `.planning/phases/25-operator-console-conversion/25-04-SUMMARY.md` capturing:
- Final ConsoleTable column widths chosen for USERS at 64x22 (Pitfall 9 record).
- Final field list per converted form (SITE visible_keys variants + LIMITS).
- Re-init trigger for SITE form (which field-value-change events cause re-init) and how nested values are preserved across re-init.
- BOARDS verification: was destructive styling already correct, or required code changes?
- Final KvGrid entries chosen for SYSTEM (which fields got `state: :healthy/:info` and why).
</output>
