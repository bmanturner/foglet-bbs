---
phase: 25
plan: 03
type: execute
wave: 2
depends_on: [01]
files_modified:
  - lib/foglet_bbs/tui/screens/moderation.ex
  - lib/foglet_bbs/tui/screens/moderation/state.ex
  - lib/foglet_bbs/tui/screens/shared/invites_state.ex
  - lib/foglet_bbs/tui/screens/shared/invites_surface.ex
  - test/foglet_bbs/tui/screens/moderation_test.exs
  - test/support/foglet/tui/layout_smoke/moderation_helper.ex
autonomous: true
requirements:
  - MOD-01
user_setup: []
tags:
  - tui
  - operator-console
  - moderation
  - elixir

must_haves:
  truths:
    - "Each Moderation tab (LOG, USERS, BOARDS, INVITES) renders a top scope/status block via Display.KvGrid with at least one Display.Badge value cell when status data is present."
    - "Each Moderation tab listing renders through Display.ConsoleTable with stable columns and an honest empty-state copy."
    - "Read-only tabs (LOG; non-actionable USERS/BOARDS rows) use ConsoleTable `selectable: false` so Enter is a no-op (Pitfall 7); only tabs with real domain side effects use `selectable: true`."
    - "Existing Moderation behavior tests (read-only honesty, scope-aware filtering, invite flows) pass unmodified (D-19)."
    - "Per-tab layout smoke at 64x22 and 80x24 passes for LOG, USERS, BOARDS, INVITES with primitive sentinels present (D-09, D-10)."
  artifacts:
    - path: "lib/foglet_bbs/tui/screens/moderation.ex"
      provides: "render_tab_body emits KvGrid summary + Badge status + ConsoleTable listing per tab; bespoke padded rows removed."
      contains: "ConsoleTable"
    - path: "lib/foglet_bbs/tui/screens/moderation/state.ex"
      provides: "Holds per-tab %ConsoleTable{} and KvGrid entry lists."
      contains: "ConsoleTable"
    - path: "lib/foglet_bbs/tui/screens/shared/invites_surface.ex"
      provides: "InvitesSurface.render/2 delegates to ConsoleTable; both Account and Moderation invite tabs benefit (RESEARCH Open Question 2)."
      contains: "ConsoleTable"
    - path: "test/support/foglet/tui/layout_smoke/moderation_helper.ex"
      provides: "Per-tab size-contract blocks for moderation log, users, boards, invites inside register_moderation_size_contracts/0 (Plan 01 stub)."
      contains: "moderation log tab — size contract"
  key_links:
    - from: "lib/foglet_bbs/tui/screens/moderation.ex"
      to: "lib/foglet_bbs/tui/widgets/display/{kv_grid,badge,console_table}.ex"
      via: "render_tab_body composition"
      pattern: "KvGrid.render|Badge.render|ConsoleTable.render"
    - from: "lib/foglet_bbs/tui/screens/shared/invites_surface.ex"
      to: "lib/foglet_bbs/tui/screens/{account,moderation}.ex"
      via: "shared invite-listing render call"
      pattern: "InvitesSurface.render"
---

<objective>
Convert Moderation tab bodies (LOG, USERS, BOARDS, INVITES) from bespoke padded-string rows + ad-hoc
status text to Phase 24 operator-console primitives: a top KvGrid scope/status summary with Badge value
cells, plus a ConsoleTable listing per tab with honest empty-state copy. Convert the shared
InvitesSurface once so both Account and Moderation benefit (RESEARCH Open Question 2). Preserve
read-only honesty (Pitfall 7) — no fake actions added.

Purpose: Moderation is the lowest-risk wave because tabs are mostly read-only; this plan establishes the
KvGrid + Badge summary + ConsoleTable listing pattern other operator surfaces will reuse.
Output: Refactored Moderation screen + state + shared invites surface; extended moderation_test.exs with
primitive-presence asserts; four new per-tab smoke blocks.
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
@lib/foglet_bbs/tui/widgets/display/console_table.ex
@lib/foglet_bbs/tui/widgets/display/kv_grid.ex
@lib/foglet_bbs/tui/widgets/display/badge.ex
@lib/foglet_bbs/tui/widgets/display/table.ex
@lib/foglet_bbs/tui/screens/sysop/boards_view.ex
@lib/foglet_bbs/tui/screens/moderation.ex
@lib/foglet_bbs/tui/screens/moderation/state.ex
@lib/foglet_bbs/tui/screens/shared/invites_state.ex
@lib/foglet_bbs/tui/screens/shared/invites_surface.ex
@lib/foglet_bbs/tui/screens/shared/invites_actions.ex
@lib/foglet_bbs/tui/presentation.ex
@test/foglet_bbs/tui/screens/moderation_test.exs
@test/support/foglet/tui/widget_helpers.ex
@test/support/foglet/tui/layout_smoke_helpers.ex
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Convert Moderation LOG, USERS, BOARDS tabs (KvGrid + Badge + ConsoleTable)</name>
  <files>lib/foglet_bbs/tui/screens/moderation.ex, lib/foglet_bbs/tui/screens/moderation/state.ex, test/foglet_bbs/tui/screens/moderation_test.exs</files>
  <read_first>
    - lib/foglet_bbs/tui/screens/moderation.ex (full file — current render_tab_body for LOG/USERS/BOARDS)
    - lib/foglet_bbs/tui/screens/moderation/state.ex (full file — current state struct + scope/status fields)
    - lib/foglet_bbs/tui/widgets/display/kv_grid.ex (lines 76-104 — `state:` and `badge:` per-row metadata)
    - lib/foglet_bbs/tui/widgets/display/badge.ex (full file — supported states `:required`, `:subscribed`, `:locked`, `:sticky`, `:pending`, `:healthy`, `:error`, `:neutral`, `:info`)
    - lib/foglet_bbs/tui/widgets/display/console_table.ex (full file — selectable contract; `selectable: false` makes Enter a no-op per Pitfall 7)
    - test/foglet_bbs/tui/screens/moderation_test.exs (existing read-only-honesty tests — must keep passing per D-19)
    - .planning/phases/25-operator-console-conversion/25-RESEARCH.md (Pattern 3, Pitfalls 3, 7, 9)
  </read_first>
  <behavior>
    - Test (new, primitive-presence): LOG tab render contains KvGrid scope/status summary AND ConsoleTable header with column labels (e.g., "When", "Actor", "Action", "Target") AND empty-state copy when fixture is empty.
    - Test (new, primitive-presence): LOG tab status block contains at least one `[…]` Badge label (e.g., `[info]` for read-only or `[error]` if scope load failed).
    - Test (new, behavior): LOG tab is `selectable: false` — pressing Enter does NOT dispatch any domain action (no Foglet.* call); ConsoleTable returns nil action.
    - Test (new, primitive-presence): USERS tab renders KvGrid summary, ConsoleTable header (e.g., "Handle", "Role", "Status"), Badge cells for status.
    - Test (new, primitive-presence): BOARDS tab renders KvGrid summary, ConsoleTable header (e.g., "Board", "Category", "State"), Badge cells for state where applicable.
    - Test (new, primitive-presence): empty fixtures for each tab render the ConsoleTable empty-state copy.
    - Test (new, behavior): for each of LOG/USERS/BOARDS, building an EMPTY-rows ConsoleTable and sending `%{key: :up}`, `%{key: :down}`, `%{key: :enter}` returns cleanly with no crash and no domain dispatch (Codex LOW suggestion — empty-table keypress coverage).
    - Test (preservation): all existing moderation_test.exs tests pass unmodified.
  </behavior>
  <action>
    Per D-04 and Pattern 3:

    1. **`moderation/state.ex`** — add per-tab fields:
       - `:log_table`, `:users_table`, `:boards_table` — each a `%ConsoleTable{}` (or `nil` until first
         load).
       - `:log_summary`, `:users_summary`, `:boards_summary` — each a list of KvGrid entries
         (`[%{label, value, state | badge}]`).
       Keep all current scope/status fields used by existing tests.

    2. **`moderation.ex` `render_tab_body/3`** — for LOG/USERS/BOARDS, emit:

       ```elixir
       column style: %{gap: 1} do
         [
           KvGrid.render(state.log_summary, theme: theme, width: 78, label_width: 16, gap: 2),
           ConsoleTable.render(state.log_table, theme: theme)
         ]
       end
       ```

       Build the summary entries per tab. Suggested shape (Claude's discretion per CONTEXT — adjust if
       a different keyset reads cleaner):
       - LOG: `[%{label: "Scope", value: scope_label, state: :info},
                %{label: "Events", value: Integer.to_string(count), state: :neutral},
                %{label: "Status", value: "Read-only", state: :info}]`
         (If `error != nil` on the scope load, replace the Status entry with `state: :error` and the
         error message.)
       - USERS: `[%{label: "Scope", value: scope_label, state: :info},
                  %{label: "Active", value: Integer.to_string(active_count), state: :healthy},
                  %{label: "Pending review", value: Integer.to_string(pending), badge: %{state:
                  :pending, label: "pending", role: :warning}}]`
       - BOARDS: similar shape — scope + counts + a badge for any board in a non-healthy state.

       Use Display.Badge ONLY via the KvGrid `state:` / `badge:` metadata (kv_grid.ex:76-104 routes
       internally) — do NOT call `Display.Badge.render/2` directly from screens. This preserves the
       single-source theme-routing path.

    3. **ConsoleTable column choices (Claude's discretion per CONTEXT)** — use these as starting points;
       verify at 64x22 via plan 05 smoke. All columns MUST have explicit `:width` (Pitfall 9):

       - LOG: `[%{key: :when, label: "When", width: 11}, %{key: :actor, label: "Actor", width: 14},
               %{key: :action, label: "Action", width: 14}, %{key: :target, label: "Target", width:
               20}]`. `selectable: false` (Pitfall 7 — LOG is read-only).
         `empty_state: "No moderation events in scope."`

       - USERS: `[%{key: :handle, label: "Handle", width: 16}, %{key: :role, label: "Role", width: 8},
                 %{key: :status, label: "Status", width: 12}]`. `selectable:` matches existing behavior
         — read moderation.ex first; if USERS currently has NO selection-driven action, set
         `selectable: false`. Do NOT introduce a new action.
         `empty_state: "No active users in scope."`

       - BOARDS: `[%{key: :name, label: "Board", width: 18}, %{key: :category, label: "Category",
                   width: 14}, %{key: :state, label: "State", width: 12}]`. `selectable:` matches
         existing behavior; if BOARDS currently has no Moderation-side action, `selectable: false`.
         `empty_state: "No boards in scope."`

       After each domain load, rebuild the `%ConsoleTable{}` via a fresh `ConsoleTable.init/1` (do not
       mutate rows on the live struct — the precedent in `boards_view.ex` re-inits).

    4. **Event routing** — `handle_key/2` for LOG/USERS/BOARDS:

       ```elixir
       {new_table, action} = ConsoleTable.handle_event(event, state.log_table)
       state = %{state | log_table: new_table}

       case action do
         _ -> {state, []}   # LOG is read-only; no dispatch
       end
       ```

       For USERS/BOARDS, if the existing screen had NO selection-driven domain action, mirror the
       LOG no-op pattern. If the existing screen DID dispatch a domain side effect on row selection,
       preserve it — read moderation.ex first to confirm.

       Per Pitfall 3: always route through `ConsoleTable.handle_event/2`; do not branch on empty rows.

    5. **`test/foglet_bbs/tui/screens/moderation_test.exs`** — ADD describe blocks for each converted
       tab: `"LOG primitive presence"`, `"USERS primitive presence"`, `"BOARDS primitive presence"`.
       Per Behavior section above. Use `flatten_text/1` from WidgetHelpers; for badge cells, assert that
       the text run contains a `[…]` substring matching one of the configured badge labels.

       For the read-only-honesty assertion (Pitfall 7): build a state with a non-empty rows fixture,
       send `%{key: :enter}` through the screen's handle_key, and assert NO mock domain function was
       called AND the returned commands list is empty.

       DO NOT modify or delete any existing test (D-19).
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/screens/moderation_test.exs</automated>
  </verify>
  <acceptance_criteria>
    - `grep -c "ConsoleTable" lib/foglet_bbs/tui/screens/moderation.ex` returns >= 3 (one per LOG/USERS/BOARDS).
    - `grep -c "KvGrid" lib/foglet_bbs/tui/screens/moderation.ex` returns >= 3.
    - `grep -nE "selectable:\s*false" lib/foglet_bbs/tui/screens/moderation/state.ex` returns at least one match (LOG must be read-only per Pitfall 7).
    - `grep -nE "empty_state:" lib/foglet_bbs/tui/screens/moderation/state.ex` returns >= 3 matches.
    - `grep -nE "fg: :(cyan|red|yellow|green|blue|magenta|white|black)" lib/foglet_bbs/tui/screens/moderation{,/state}.ex` returns 0 matches (theme hygiene).
    - `grep -n "LOG primitive presence\|USERS primitive presence\|BOARDS primitive presence" test/foglet_bbs/tui/screens/moderation_test.exs` returns >= 3 matches.
    - `rtk mix test test/foglet_bbs/tui/screens/moderation_test.exs` exits 0.
    - `git diff test/foglet_bbs/tui/screens/moderation_test.exs` shows only additive changes outside the new describe blocks.
  </acceptance_criteria>
  <done>LOG, USERS, BOARDS Moderation tabs render through KvGrid + Badge + ConsoleTable; LOG is `selectable: false` (read-only honesty preserved); existing moderation tests pass unmodified.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Convert shared InvitesSurface to ConsoleTable (covers Moderation INVITES)</name>
  <files>lib/foglet_bbs/tui/screens/shared/invites_state.ex, lib/foglet_bbs/tui/screens/shared/invites_surface.ex, lib/foglet_bbs/tui/screens/moderation.ex, lib/foglet_bbs/tui/screens/moderation/state.ex, test/foglet_bbs/tui/screens/moderation_test.exs</files>
  <read_first>
    - lib/foglet_bbs/tui/screens/shared/invites_surface.ex (full file — current bespoke render)
    - lib/foglet_bbs/tui/screens/shared/invites_state.ex (full file — current selection / state shape)
    - lib/foglet_bbs/tui/screens/shared/invites_actions.ex (full file — current generate/revoke contract)
    - lib/foglet_bbs/tui/widgets/display/console_table.ex (init + handle_event)
    - test/foglet_bbs/tui/screens/moderation_test.exs (existing invite-flow tests — must keep passing per D-19)
    - .planning/phases/25-operator-console-conversion/25-RESEARCH.md (Open Question 2)
  </read_first>
  <behavior>
    - Test (new, primitive-presence): INVITES tab body renders ConsoleTable header with column labels (e.g., "Code", "Status", "Created", "Used by").
    - Test (new, primitive-presence): empty INVITES fixture renders empty-state copy "No invites generated yet." (or chosen wording).
    - Test (new, behavior): pressing `:down` and `:up` cycles ConsoleTable cursor; pressing `:enter` on a row dispatches the SAME revoke/copy contract the bespoke version exposed (read existing tests to mirror).
    - Test (new, behavior): empty INVITES fixture handles `:up`/`:down`/`:enter` keypresses without crash and without dispatching any domain action (Codex LOW suggestion).
    - Test (preservation): all existing invite-flow tests in moderation_test.exs pass unmodified.
  </behavior>
  <action>
    Per RESEARCH Open Question 2, convert the shared `InvitesSurface` once so both Account and
    Moderation benefit. Account does not currently have an INVITES tab in its 3-tab list (per CONTEXT
    D-09: Account tabs are profile/prefs/ssh_keys), so this conversion lands in Moderation in this
    phase but uses the shared module to keep Account ready if it later adopts.

    1. **`shared/invites_state.ex`** — replace bespoke `selected_index` with a `:table` field holding
       `%ConsoleTable{}`:

       ```elixir
       ConsoleTable.init(
         columns: [
           %{key: :code,     label: "Code",     width: 14},
           %{key: :status,   label: "Status",   width: 10},
           %{key: :created,  label: "Created",  width: 11},
           %{key: :used_by,  label: "Used by",  width: 16}
         ],
         rows: [],
         selectable: true,
         empty_state: "No invites generated yet."
       )
       ```

       Pitfall 9: every column has explicit `:width`.

    2. **`shared/invites_surface.ex`** — replace the bespoke render with
       `ConsoleTable.render(state.table, theme: theme)`. Keep any header/footer text the existing
       surface displays (e.g., generation key hints) but route colors through `theme.dim.fg` /
       `theme.title.fg` — no hardcoded atoms.

    3. **Event routing** — in `invites_state.ex` `handle_key/2`:

       ```elixir
       {new_table, action} = ConsoleTable.handle_event(event, state.table)
       state = %{state | table: new_table}

       case action do
         {:row_selected, row} ->
           # preserve EXISTING contract — read invites_actions.ex first to identify the action atom
           {state, [{:invites_revoke_confirm, row.code}]}
         _ ->
           {state, []}
       end
       ```

       Read `invites_actions.ex` first to confirm the exact downstream contract; do NOT change the
       action atom or its payload shape (D-18 — no contract changes).

    4. **`moderation.ex` / `moderation/state.ex`** — wire INVITES tab to delegate to the shared
       InvitesSurface. If the existing moderation INVITES tab already delegates to the shared module,
       this is a no-op for moderation and the conversion is invisible to its render path. Confirm by
       reading moderation.ex render_tab_body/3.

    5. **`test/foglet_bbs/tui/screens/moderation_test.exs`** — ADD `describe "INVITES ConsoleTable
       primitive presence"` block. Tests per Behavior section. DO NOT modify existing invite tests
       (D-19).
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/screens/moderation_test.exs</automated>
  </verify>
  <acceptance_criteria>
    - `grep -c "ConsoleTable" lib/foglet_bbs/tui/screens/shared/invites_state.ex` returns >= 2.
    - `grep -c "ConsoleTable" lib/foglet_bbs/tui/screens/shared/invites_surface.ex` returns >= 1.
    - `grep -nE "selected_index" lib/foglet_bbs/tui/screens/shared/invites_state.ex` returns 0 matches (D-05).
    - `grep -nE "width:\s*[0-9]+" lib/foglet_bbs/tui/screens/shared/invites_state.ex` returns at least 4 matches (Pitfall 9).
    - `grep -n "empty_state:" lib/foglet_bbs/tui/screens/shared/invites_state.ex` returns at least one match.
    - `grep -n "INVITES ConsoleTable primitive presence" test/foglet_bbs/tui/screens/moderation_test.exs` returns at least one match.
    - `rtk mix test test/foglet_bbs/tui/screens/moderation_test.exs` exits 0.
  </acceptance_criteria>
  <done>Shared InvitesSurface renders through ConsoleTable; selection ownership lives in the widget per D-05; existing moderation invite-flow tests pass unmodified; Account is unblocked if it later adopts the shared surface.</done>
</task>

<task type="auto">
  <name>Task 3: Per-tab layout-smoke blocks for Moderation LOG / USERS / BOARDS / INVITES</name>
  <files>test/support/foglet/tui/layout_smoke/moderation_helper.ex</files>
  <read_first>
    - test/foglet_bbs/tui/layout_smoke_test.exs (lines 273-353 — D-11 precedent; plan 01 example block)
    - test/support/foglet/tui/layout_smoke_helpers.ex
    - lib/foglet_bbs/tui/widgets/display/kv_grid.ex (label rendering — sentinel candidate)
    - lib/foglet_bbs/tui/widgets/display/console_table.ex (column-header rendering — sentinel candidate)
    - .planning/phases/25-operator-console-conversion/25-CONTEXT.md (D-09, D-10, D-11)
  </read_first>
  <action>
    Add four `describe` blocks INSIDE the `register_moderation_size_contracts/0` macro body in
    `test/support/foglet/tui/layout_smoke/moderation_helper.ex` (Plan 01 stub). Do NOT modify
    `layout_smoke_test.exs` directly — Plan 01 wired the registry. This decoupling avoids merge
    conflicts with Plans 02/04 (Codex Concern 3). The four blocks are:

    1. `describe "moderation log tab — size contract"`
    2. `describe "moderation users tab — size contract"`
    3. `describe "moderation boards tab — size contract"`
    4. `describe "moderation invites tab — size contract"`

    Each follows the plan-01 example block + Phase 22/20 precedent (lines 273-353). Iterate
    `for {width, height} <- [{64, 22}, {80, 24}]`. For each, build representative state with non-empty
    fixture rows so that ConsoleTable header AND KvGrid summary AND at least one Badge cell are
    present.

    Per D-10 assertions:

    (a) **Bounds** — every text element fits within `width`/`height`.

    (b) **Primitive sentinel** — assert at least one of:
        - A KvGrid label substring (e.g., "Scope", "Status").
        - A ConsoleTable column-header substring (e.g., "When" for LOG, "Handle" for USERS, "Board"
          for BOARDS, "Code" for INVITES).
        - A `[…]` Badge label substring for tabs whose summary includes a badge.
        - The configured empty-state copy for the empty-fixture variant (test both empty + non-empty
          if a separate test case helps clarity).

    (c) **No-overlap** — no two text elements occupy the same `{x, y}`.

    Tag each `@tag :"moderation <tab> size contract"` for selective runs. No `132x50` block (D-10).
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs --only "moderation log size contract" --only "moderation users size contract" --only "moderation boards size contract" --only "moderation invites size contract"</automated>
  </verify>
  <acceptance_criteria>
    - `grep -n "moderation log tab — size contract" test/support/foglet/tui/layout_smoke/moderation_helper.ex` returns at least one match.
    - `grep -n "moderation users tab — size contract" test/support/foglet/tui/layout_smoke/moderation_helper.ex` returns at least one match.
    - `grep -n "moderation boards tab — size contract" test/support/foglet/tui/layout_smoke/moderation_helper.ex` returns at least one match.
    - `grep -n "moderation invites tab — size contract" test/support/foglet/tui/layout_smoke/moderation_helper.ex` returns at least one match.
    - Each block contains `for {width, height} <- [{64, 22}, {80, 24}]`.
    - Each `--only` filtered run yields at least 2 tests passing.
    - `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` exits 0.
  </acceptance_criteria>
  <done>Four per-tab smoke blocks exist for Moderation, each iterating 64x22 and 80x24; full smoke suite passes.</done>
</task>

</tasks>

<verification>
- `rtk mix test test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` exits 0.
- No domain mutation introduced into Moderation (Pitfall 7 — read-only honesty preserved).
- `Workspace.Inspector` not referenced from Moderation (verified globally in plan 05).
</verification>

<success_criteria>
- MOD-01 satisfied: LOG, USERS, BOARDS, INVITES tabs render through KvGrid + Badge + ConsoleTable.
- Read-only honesty preserved (LOG `selectable: false` + tests assert no Enter dispatch).
- All existing `moderation_test.exs` behavior tests pass unmodified (D-19).
- Per-tab smoke at 64x22 and 80x24 passes for all four Moderation tabs.
</success_criteria>

<output>
After completion, create `.planning/phases/25-operator-console-conversion/25-03-SUMMARY.md` capturing:
- Final ConsoleTable column widths chosen for each tab at 64x22 (Pitfall 9 record).
- Final empty-state copy strings per tab.
- Per-tab `selectable:` decision (`true`/`false`) with rationale (Pitfall 7).
- Whether Account currently consumes shared InvitesSurface (it does NOT in this phase, but record the readiness).
</output>
