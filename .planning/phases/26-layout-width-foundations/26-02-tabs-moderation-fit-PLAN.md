---
phase: 26
plan: 02
type: execute
wave: 2
depends_on: [01]
files_modified:
  - lib/foglet_bbs/tui/widgets/input/tabs.ex
  - lib/foglet_bbs/tui/screens/moderation.ex
  - lib/foglet_bbs/tui/screens/moderation/state.ex
  - lib/foglet_bbs/tui/screens/shared/invites_state.ex
  - test/foglet_bbs/tui/widgets/input/tabs_test.exs
  - test/foglet_bbs/tui/screens/moderation_test.exs
  - test/foglet_bbs/tui/layout_smoke_test.exs
autonomous: true
requirements:
  - LAYOUT-01
  - LAYOUT-02
  - LAYOUT-04
  - LAYOUT-05
user_setup: []
tags:
  - tui
  - tabs
  - moderation
  - elixir
must_haves:
  truths:
    - "Account, Moderation, and Sysop inherit the tab-row artifact fix through `Input.Tabs.render/2`."
    - "Moderation LOG/USERS/BOARDS compact rendering prioritizes the table area at 64x22 and collapses secondary summaries when needed."
    - "Moderation LOG timestamps use current-user timezone with deterministic `Etc/UTC` fallback."
    - "Sysop/Shared INVITES table column definitions use responsive width semantics from Plan 01."
---

<objective>
Fix the shared tab-row trailing border artifact and make Moderation's LOG, USERS, and BOARDS tabs fit the 64x22 frame while preserving responsive LOG and INVITES table contracts.
</objective>

<context>
@.planning/phases/26-layout-width-foundations/26-CONTEXT.md
@.planning/phases/26-layout-width-foundations/26-RESEARCH.md
@.planning/phases/26-layout-width-foundations/26-SPEC.md
@lib/foglet_bbs/tui/widgets/input/tabs.ex
@lib/foglet_bbs/tui/screens/moderation.ex
@lib/foglet_bbs/tui/screens/moderation/state.ex
@lib/foglet_bbs/tui/screens/shared/invites_state.ex
@lib/foglet_bbs/tui/widgets/chrome/clock_formatter.ex
@test/foglet_bbs/tui/widgets/input/tabs_test.exs
@test/foglet_bbs/tui/screens/moderation_test.exs
@test/foglet_bbs/tui/layout_smoke_test.exs
</context>

<tasks>

<task type="auto">
  <name>Task 1: Clamp Input.Tabs render width</name>
  <files>lib/foglet_bbs/tui/widgets/input/tabs.ex, test/foglet_bbs/tui/widgets/input/tabs_test.exs, test/foglet_bbs/tui/layout_smoke_test.exs</files>
  <read_first>
    - lib/foglet_bbs/tui/widgets/input/tabs.ex
    - test/foglet_bbs/tui/widgets/input/tabs_test.exs
    - test/foglet_bbs/tui/layout_smoke_test.exs
  </read_first>
  <action>
    Extend `Tabs.render/2` to accept optional `width:`. Build the tab text sequence, then clamp/pad it so the rendered tab strip does not exceed `width`.

    Required target:
    - `Tabs.render(ss.tabs, theme: theme, width: width)` is used by Account, Moderation, and Sysop where those screens know inner width.
    - If labels exceed `width`, truncate inactive labels first using `TextWidth.truncate/2`; preserve the active indicator `▌` and at least one visible character of each active label when possible.
    - The outer `box` must render at the given width or emit children whose flattened text width is `<= width`.
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/widgets/input/tabs_test.exs test/foglet_bbs/tui/layout_smoke_test.exs</automated>
  </verify>
  <acceptance_criteria>
    - `rtk rg -n "width:" lib/foglet_bbs/tui/widgets/input/tabs.ex` returns at least one match.
    - `rtk rg -n "Tabs\\.render\\(.*width:" lib/foglet_bbs/tui/screens/account.ex lib/foglet_bbs/tui/screens/moderation.ex lib/foglet_bbs/tui/screens/sysop.ex` returns matches for all three screens.
    - `tabs_test.exs` includes a compact-width test where flattened tab text display width is `<= 60`.
    - `rtk mix test test/foglet_bbs/tui/widgets/input/tabs_test.exs` exits 0.
  </acceptance_criteria>
</task>

<task type="auto">
  <name>Task 2: Fit Moderation compact tabs and timezone LOG rows</name>
  <files>lib/foglet_bbs/tui/screens/moderation.ex, lib/foglet_bbs/tui/screens/moderation/state.ex, test/foglet_bbs/tui/screens/moderation_test.exs, test/foglet_bbs/tui/layout_smoke_test.exs</files>
  <read_first>
    - lib/foglet_bbs/tui/screens/moderation.ex
    - lib/foglet_bbs/tui/screens/moderation/state.ex
    - lib/foglet_bbs/tui/widgets/display/console_table.ex
    - lib/foglet_bbs/tui/widgets/chrome/clock_formatter.ex
    - test/foglet_bbs/tui/screens/moderation_test.exs
    - test/foglet_bbs/tui/layout_smoke_test.exs
  </read_first>
  <action>
    Pass both width and body-height into Moderation tab rendering.

    Concrete changes:
    - Add `body_height(state)` mirroring `inner_width/1`; for `{cols, rows}` use `max(rows - 4, 0)` as the body region after frame/chrome/command rows.
    - Call `Tabs.render(ss.tabs, theme: theme, width: width)`.
    - For LOG/USERS/BOARDS at compact height (`body_height <= 18`), omit or collapse `KvGrid` summary rows and render the `ConsoleTable` as the primary content.
    - Rebuild LOG/USERS/BOARDS tables with `width: width` and a page size derived from body height, e.g. `max(body_height - 4, 3)`.
    - Change `State.build_log_table/1` to `State.build_log_table(rows, opts \\ [])`; accept `:timezone` and `:width`.
    - Format LOG timestamps as `%m-%d %H:%M` or equivalent compact timestamp after shifting into the current user's valid IANA timezone. Invalid/nil timezone must fall back to `Etc/UTC`.
    - Remove fixed `truncate(..., 13)` / `truncate(..., 9)` from LOG row builder; allow table cell truncation from Plan 01 to elide long body/reason values.
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/layout_smoke_test.exs</automated>
  </verify>
  <acceptance_criteria>
    - `rtk rg -n "body_height" lib/foglet_bbs/tui/screens/moderation.ex` returns at least one match.
    - `rtk rg -n "build_log_table\\(rows, opts" lib/foglet_bbs/tui/screens/moderation/state.ex` returns one match.
    - `rtk rg -n "Etc/UTC|ClockFormatter|Tzdata" lib/foglet_bbs/tui/screens/moderation/state.ex lib/foglet_bbs/tui/screens/moderation.ex` returns at least one timezone fallback match.
    - `rtk rg -n "truncate\\(body, 13\\)|truncate\\(reason, 9\\)" lib/foglet_bbs/tui/screens/moderation/state.ex` returns 0 matches.
    - Moderation tests include a non-UTC user timezone case and assert the rendered LOG timestamp is not the old `YYYY-MM-DD` only format.
    - Layout smoke includes 64x22 LOG, USERS, and BOARDS assertions with no element y-position outside the screen height.
    - `rtk mix test test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` exits 0.
  </acceptance_criteria>
</task>

<task type="auto">
  <name>Task 3: Make shared invite columns responsive</name>
  <files>lib/foglet_bbs/tui/screens/shared/invites_state.ex, test/foglet_bbs/tui/screens/moderation_test.exs, test/foglet_bbs/tui/screens/sysop_test.exs</files>
  <read_first>
    - lib/foglet_bbs/tui/screens/shared/invites_state.ex
    - lib/foglet_bbs/tui/screens/shared/invites_surface.ex
    - test/foglet_bbs/tui/screens/moderation_test.exs
    - test/foglet_bbs/tui/screens/sysop_test.exs
  </read_first>
  <action>
    Update invite table column definitions to use Plan 01 responsive width semantics.

    Target columns:
    - `%{key: :code, label: "Code", width: {:ratio, 4}}`
    - `%{key: :status, label: "Status", width: {:ratio, 2}}`
    - `%{key: :created, label: "Created", width: {:ratio, 2}}`
    - `%{key: :used_by, label: "Used by", width: {:ratio, 3}}`

    Ensure `InvitesState.build_table/2` accepts optional `opts \\ []`, reads `:width`, and passes it to `ConsoleTable.init/1`. Keep existing call sites working with defaults.
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/screens/sysop_test.exs</automated>
  </verify>
  <acceptance_criteria>
    - `rtk rg -n "\\{:ratio, 4\\}|\\{:ratio, 3\\}" lib/foglet_bbs/tui/screens/shared/invites_state.ex` returns matches.
    - Sysop or shared invite tests assert `Code`, `Status`, `Created`, and `Used by` all render at compact width with separator whitespace.
    - `rtk mix test test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/screens/sysop_test.exs` exits 0.
  </acceptance_criteria>
</task>

</tasks>

<threat_model>
Presentation-only changes. Existing authorization and invite mutation checks remain in `Foglet.Accounts` and `InvitesActions`; this plan must not add new domain side effects from render functions. Compact rendering must not hide authorization errors; error summaries may collapse only if a clear table/inline error remains visible.
</threat_model>

<verification>
- `rtk mix test test/foglet_bbs/tui/widgets/input/tabs_test.exs`
- `rtk mix test test/foglet_bbs/tui/screens/moderation_test.exs`
- `rtk mix test test/foglet_bbs/tui/screens/sysop_test.exs`
- `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs`
</verification>

<success_criteria>
- 64x22 layout smoke passes for tabbed screens and Moderation compact tabs.
- Moderation LOG uses timezone-aware compact timestamps and table-level ellipsis.
- Shared INVITES columns remain visibly separated at compact widths.
</success_criteria>

