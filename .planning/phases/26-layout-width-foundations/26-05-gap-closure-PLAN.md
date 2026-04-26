---
phase: 26
plan: 05
type: execute
wave: 4
depends_on: [02, 03, 04]
files_modified:
  - lib/foglet_bbs/tui/widgets/input/tabs.ex
  - lib/foglet_bbs/tui/screens/account.ex
  - lib/foglet_bbs/tui/screens/sysop.ex
  - lib/foglet_bbs/tui/screens/board_list.ex
  - lib/foglet_bbs/tui/screens/moderation/state.ex
  - lib/foglet_bbs/tui/widgets/chrome/clock_formatter.ex
  - test/foglet_bbs/tui/widgets/input/tabs_test.exs
  - test/foglet_bbs/tui/screens/board_list_test.exs
  - test/foglet_bbs/tui/screens/moderation_test.exs
  - test/foglet_bbs/tui/layout_smoke_test.exs
autonomous: true
requirements:
  - LAYOUT-01
  - LAYOUT-03
  - LAYOUT-05
user_setup: []
tags:
  - tui
  - uat
  - gap-closure
  - elixir
must_haves:
  truths:
    - "The Account and Sysop tab rows end flush with the last visible tab at 64x22 and do not expose a trailing inner border glyph."
    - "The Boards directory uses the compact body region efficiently at 64x22 so the primary tree remains dense, framed, and navigable with oversized datasets."
    - "Moderation LOG timestamps respect the current user's timezone and 12h/24h clock preference rather than forcing a fixed 24-hour format."
    - "Each diagnosed UAT gap has a regression test or smoke assertion tied to the reported compact-width failure."
  artifacts:
    - path: ".planning/phases/26-layout-width-foundations/26-UAT.md"
      provides: "Diagnosed UAT gaps to close."
      contains: "## Gaps"
    - path: "lib/foglet_bbs/tui/widgets/input/tabs.ex"
      provides: "Shared compact tab-row rendering used by Account and Sysop."
      contains: "def render"
    - path: "lib/foglet_bbs/tui/screens/board_list.ex"
      provides: "Boards compact body budgeting."
      contains: "render_board_content"
    - path: "lib/foglet_bbs/tui/screens/moderation/state.ex"
      provides: "Moderation LOG timestamp formatting."
      contains: "format_log_timestamp"
---

<objective>
Close the four diagnosed Phase 26 UAT gaps so the phase is ready for a focused rerun of the failed compact-width and timestamp scenarios.
</objective>

<context>
@.planning/phases/26-layout-width-foundations/26-UAT.md
@.planning/STATE.md
@.planning/ROADMAP.md
@docs/raxol/getting-started/WIDGET_GALLERY.md
@lib/foglet_bbs/tui/widgets/README.md
@lib/foglet_bbs/tui/widgets/input/tabs.ex
@lib/foglet_bbs/tui/screens/account.ex
@lib/foglet_bbs/tui/screens/sysop.ex
@lib/foglet_bbs/tui/screens/board_list.ex
@lib/foglet_bbs/tui/screens/moderation/state.ex
@lib/foglet_bbs/tui/widgets/chrome/clock_formatter.ex
@test/foglet_bbs/tui/widgets/input/tabs_test.exs
@test/foglet_bbs/tui/screens/board_list_test.exs
@test/foglet_bbs/tui/screens/moderation_test.exs
@test/foglet_bbs/tui/layout_smoke_test.exs
</context>

<tasks>

<task type="auto">
  <name>Task 1: Remove the compact trailing tab-row border artifact for Account and Sysop</name>
  <files>lib/foglet_bbs/tui/widgets/input/tabs.ex, lib/foglet_bbs/tui/screens/account.ex, lib/foglet_bbs/tui/screens/sysop.ex, test/foglet_bbs/tui/widgets/input/tabs_test.exs, test/foglet_bbs/tui/layout_smoke_test.exs</files>
  <read_first>
    - .planning/phases/26-layout-width-foundations/26-UAT.md
    - lib/foglet_bbs/tui/widgets/input/tabs.ex
    - lib/foglet_bbs/tui/screens/account.ex
    - lib/foglet_bbs/tui/screens/sysop.ex
    - test/foglet_bbs/tui/widgets/input/tabs_test.exs
  </read_first>
  <action>
    Adjust the shared tab rendering contract so compact framed rows do not leave a visible boxed edge after the last tab label.

    Required target:
    - Keep Account and Sysop on the shared `Tabs.render/2` path; do not fork per-screen tab logic.
    - Treat the provided `width:` as the already-safe drawable tab-row budget inside the frame.
    - Render the row so the rightmost visible column is tab content or padding, never the inner vertical border glyph reported in UAT tests 1 and 5.
    - Preserve the active indicator and legibility at 64x22 without allowing flattened tab text to exceed the compact screen budget.
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/widgets/input/tabs_test.exs test/foglet_bbs/tui/layout_smoke_test.exs</automated>
  </verify>
  <acceptance_criteria>
    - `rtk rg -n "Tabs\\.render\\(.*width:" lib/foglet_bbs/tui/screens/account.ex lib/foglet_bbs/tui/screens/sysop.ex` returns matches for both screens.
    - Compact tab tests assert the final visible glyph at framed width is not a trailing boxed edge artifact.
    - Layout smoke covers Account and Sysop at `{64, 22}` and fails if tab text crosses the frame or leaves the trailing border glyph pattern reported in UAT.
    - `rtk mix test test/foglet_bbs/tui/widgets/input/tabs_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` exits 0.
  </acceptance_criteria>
</task>

<task type="auto">
  <name>Task 2: Rebalance compact Boards body height so oversized directories stay dense and navigable</name>
  <files>lib/foglet_bbs/tui/screens/board_list.ex, test/foglet_bbs/tui/screens/board_list_test.exs, test/foglet_bbs/tui/layout_smoke_test.exs</files>
  <read_first>
    - .planning/phases/26-layout-width-foundations/26-UAT.md
    - lib/foglet_bbs/tui/screens/board_list.ex
    - test/foglet_bbs/tui/screens/board_list_test.exs
    - test/foglet_bbs/tui/layout_smoke_test.exs
  </read_first>
  <action>
    Revisit the 64x22 Boards body budget so the tree receives the intended number of visible rows before optional detail and inspector surfaces consume space.

    Required target:
    - Primary tree density wins on compact screens. Feedback, detail strips, and spacer rows must yield when they would leave the directory underfilled.
    - Keep selection visibility and existing navigation behavior intact for oversized datasets.
    - Continue using drawable inner-frame width and height budgets rather than raw terminal dimensions.
    - Add a regression that captures the sparse/blank layout reported in UAT test 6.
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs test/foglet_bbs/tui/layout_smoke_test.exs</automated>
  </verify>
  <acceptance_criteria>
    - BoardList tests include an oversized directory case at `{64, 22}` and assert multiple visible board/category rows remain in-frame rather than a largely blank body.
    - Layout smoke for Boards at `{64, 22}` fails if rows render above the frame, below the command bar, or if the compact tree budget underfills the body.
    - `rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` exits 0.
  </acceptance_criteria>
</task>

<task type="auto">
  <name>Task 3: Route Moderation LOG timestamps through the preference-aware clock formatter</name>
  <files>lib/foglet_bbs/tui/screens/moderation/state.ex, lib/foglet_bbs/tui/widgets/chrome/clock_formatter.ex, test/foglet_bbs/tui/screens/moderation_test.exs, test/foglet_bbs/tui/layout_smoke_test.exs</files>
  <read_first>
    - .planning/phases/26-layout-width-foundations/26-UAT.md
    - lib/foglet_bbs/tui/screens/moderation/state.ex
    - lib/foglet_bbs/tui/widgets/chrome/clock_formatter.ex
    - test/foglet_bbs/tui/screens/moderation_test.exs
  </read_first>
  <action>
    Replace the fixed Moderation LOG timestamp format with the existing preference-aware formatter used by chrome/session surfaces.

    Required target:
    - Respect the current user's configured timezone and 12-hour or 24-hour preference.
    - Preserve a compact LOG-table-friendly timestamp width; if the shared formatter needs a compact variant, add it in the shared helper rather than re-hardcoding format strings in Moderation state.
    - Keep long body/reason cell truncation delegated to the width-aware table contract.
    - Add a regression for the exact UAT failure: a non-UTC user with a 12-hour preference must not still see `19:29`-style 24-hour output.
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/layout_smoke_test.exs</automated>
  </verify>
  <acceptance_criteria>
    - `rtk rg -n "ClockFormatter|time_format|12" lib/foglet_bbs/tui/screens/moderation/state.ex lib/foglet_bbs/tui/widgets/chrome/clock_formatter.ex` returns preference-aware formatting usage.
    - Moderation tests cover a non-UTC timezone plus 12-hour preference and assert the rendered LOG timestamp changes accordingly.
    - Layout smoke continues to pass for compact Moderation LOG rendering at `{64, 22}` and `{80, 24}`.
    - `rtk mix test test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` exits 0.
  </acceptance_criteria>
</task>

<task type="auto">
  <name>Task 4: Re-run focused verification for the diagnosed scenarios</name>
  <files>.planning/phases/26-layout-width-foundations/26-UAT.md, .planning/phases/26-layout-width-foundations/26-HUMAN-UAT.md</files>
  <read_first>
    - .planning/phases/26-layout-width-foundations/26-UAT.md
    - .planning/phases/26-layout-width-foundations/26-HUMAN-UAT.md
  </read_first>
  <action>
    After the code changes land, rerun the focused automated suites plus the four failed manual scenarios from the diagnosed UAT file, then overwrite the corresponding `26-UAT.md` and `26-HUMAN-UAT.md` entries with the new outcomes.
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/widgets/input/tabs_test.exs test/foglet_bbs/tui/screens/board_list_test.exs test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/layout_smoke_test.exs</automated>
    <manual>Re-run Phase 26 tests 1, 5, 6, and 8 from `26-UAT.md` in a real SSH terminal at the specified dimensions.</manual>
  </verify>
  <acceptance_criteria>
    - The four previously failing UAT scenarios are the explicit rerun target set.
    - No unrelated manual scenarios are required before gap-closure execution can be considered complete.
  </acceptance_criteria>
</task>

</tasks>

<threat_model>
These are presentation-path fixes only. Do not add new persistence, authorization, or SSH session side effects. Main regression risk is compact rendering logic diverging across screens; keep shared contracts shared and pin them with smoke tests.
</threat_model>

<verification>
- `rtk mix test test/foglet_bbs/tui/widgets/input/tabs_test.exs`
- `rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs`
- `rtk mix test test/foglet_bbs/tui/screens/moderation_test.exs`
- `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs`
- Re-run Phase 26 manual UAT scenarios 1, 5, 6, and 8 from `26-UAT.md`
</verification>

<success_criteria>
- All four diagnosed UAT gaps map directly to executable work.
- Shared tests exist for each compact rendering or timestamp regression.
- The resulting fixes are ready for `$gsd-execute-phase 26 --gaps-only`.
</success_criteria>
