---
phase: 26
plan: 04
type: execute
wave: 3
depends_on: [02, 03]
files_modified:
  - lib/foglet_bbs/tui/widgets/post/markdown_body.ex
  - test/foglet_bbs/tui/widgets/post/markdown_body_test.exs
  - test/foglet_bbs/tui/screens/post_reader_test.exs
  - .planning/phases/26-layout-width-foundations/26-HUMAN-UAT.md
autonomous: false
requirements:
  - POST-01
  - LAYOUT-01
  - LAYOUT-02
  - LAYOUT-03
  - LAYOUT-04
  - LAYOUT-05
  - LAYOUT-06
user_setup:
  - "Run or assist with manual SSH checks at 64x22 and 80x24."
tags:
  - tui
  - markdown
  - verification
  - elixir
must_haves:
  truths:
    - "MarkdownBody preserves soft line breaks and emits exactly one blank visible line for two-or-more consecutive newline separators."
    - "PostReader inherits the paragraph behavior through shared MarkdownBody rendering."
    - "Phase 26 has a human UAT artifact with exact terminal-size scenarios and results."
---

<objective>
Fix shared post markdown paragraph rendering, then complete Phase 26 with focused automated tests, `rtk mix precommit`, and a human terminal verification checklist.
</objective>

<context>
@.planning/phases/26-layout-width-foundations/26-CONTEXT.md
@.planning/phases/26-layout-width-foundations/26-RESEARCH.md
@.planning/phases/26-layout-width-foundations/26-SPEC.md
@.planning/phases/26-layout-width-foundations/26-VALIDATION.md
@lib/foglet_bbs/tui/widgets/post/markdown_body.ex
@test/foglet_bbs/tui/widgets/post/markdown_body_test.exs
@test/foglet_bbs/tui/screens/post_reader_test.exs
</context>

<tasks>

<task type="auto">
  <name>Task 1: Preserve blank paragraph lines in MarkdownBody</name>
  <files>lib/foglet_bbs/tui/widgets/post/markdown_body.ex, test/foglet_bbs/tui/widgets/post/markdown_body_test.exs, test/foglet_bbs/tui/screens/post_reader_test.exs</files>
  <read_first>
    - lib/foglet_bbs/tui/widgets/post/markdown_body.ex
    - test/foglet_bbs/tui/widgets/post/markdown_body_test.exs
    - test/foglet_bbs/tui/screens/post_reader_test.exs
  </read_first>
  <action>
    Replace `group_by_newline/1` so newline runs are counted instead of rejected.

    Required target:
    - `"First\nSecond"` produces two rendered line groups: `"First"` and `"Second"` with no blank group between them.
    - `"First\n\nSecond"` produces three rendered line groups: `"First"`, `""`, `"Second"`.
    - `"First\n\n\nSecond"` also produces exactly three rendered line groups: `"First"`, `""`, `"Second"`.
    - `render_tuples_as_lines/4`, `render_tuples/4`, `render/4`, and `line_count/1` all use the same grouping behavior.
    - Blank groups render as `text("", fg: theme.primary.fg)` and contain no literal `"\n"` content.
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/widgets/post/markdown_body_test.exs test/foglet_bbs/tui/screens/post_reader_test.exs</automated>
  </verify>
  <acceptance_criteria>
    - MarkdownBody tests assert `top_level_line_count(MarkdownBody.render("First\\n\\nSecond", 80, theme())) == 3`.
    - MarkdownBody tests assert `top_level_line_count(MarkdownBody.render("First\\n\\n\\nSecond", 80, theme())) == 3`.
    - MarkdownBody tests assert `MarkdownBody.line_count("First\\n\\nSecond") == 3`.
    - Existing "does not emit literal `\\n` characters" test remains present and passes.
    - `rtk mix test test/foglet_bbs/tui/widgets/post/markdown_body_test.exs test/foglet_bbs/tui/screens/post_reader_test.exs` exits 0.
  </acceptance_criteria>
</task>

<task type="manual">
  <name>Task 2: Record human SSH verification for Phase 26</name>
  <files>.planning/phases/26-layout-width-foundations/26-HUMAN-UAT.md</files>
  <read_first>
    - .planning/phases/26-layout-width-foundations/26-SPEC.md
    - .planning/phases/26-layout-width-foundations/26-VALIDATION.md
  </read_first>
  <action>
    Create `.planning/phases/26-layout-width-foundations/26-HUMAN-UAT.md` with frontmatter:

    ```yaml
    ---
    phase: 26
    started: 2026-04-26
    updated: 2026-04-26
    status: pending
    ---
    ```

    Include a checklist for these exact scenarios:
    - 64x22 Account tab row.
    - 64x22 Moderation LOG, USERS, BOARDS tab rows and primary tables.
    - 64x22 Sysop tab row.
    - 64x22 Boards overlarge directory.
    - 80x24 Sysop INVITES with available, consumed, revoked rows.
    - 80x24 Moderation LOG with long body/reason and non-UTC user timezone.
    - Post Reader body containing `soft\nbreak`, `First\n\nSecond`, and `First\n\n\nSecond`.

    Mark each scenario `pending`, `pass`, or `fail` as it is run. If manual SSH cannot be run in the execution session, leave status `pending` and document the blocker.
  </action>
  <verify>
    <manual>Open the HUMAN-UAT file and confirm every Phase 26 acceptance criterion maps to a scenario.</manual>
  </verify>
  <acceptance_criteria>
    - `.planning/phases/26-layout-width-foundations/26-HUMAN-UAT.md` exists.
    - `rtk rg -n "64x22 Account|64x22 Moderation LOG|64x22 Boards|80x24 Sysop INVITES|Post Reader" .planning/phases/26-layout-width-foundations/26-HUMAN-UAT.md` returns matches.
    - Every scenario has a `Status:` line.
  </acceptance_criteria>
</task>

<task type="auto">
  <name>Task 3: Run final focused and precommit verification</name>
  <files>.planning/phases/26-layout-width-foundations/26-HUMAN-UAT.md</files>
  <read_first>
    - .planning/phases/26-layout-width-foundations/26-VALIDATION.md
    - .planning/phases/26-layout-width-foundations/26-HUMAN-UAT.md
  </read_first>
  <action>
    Run the final automated verification commands:
    - `rtk mix test test/foglet_bbs/tui/text_width_test.exs test/foglet_bbs/tui/widgets/display/table_test.exs test/foglet_bbs/tui/widgets/display/console_table_test.exs`
    - `rtk mix test test/foglet_bbs/tui/widgets/input/tabs_test.exs test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/screens/board_list_test.exs test/foglet_bbs/tui/widgets/post/markdown_body_test.exs test/foglet_bbs/tui/layout_smoke_test.exs`
    - `rtk mix precommit`

    Append a `## Automated Verification` section to `26-HUMAN-UAT.md` with command names and pass/fail outcomes.
  </action>
  <verify>
    <automated>rtk mix precommit</automated>
  </verify>
  <acceptance_criteria>
    - `rtk mix precommit` exits 0, or the HUMAN-UAT file records the exact failure and why it is outside/inside Phase 26.
    - `rtk rg -n "Automated Verification|rtk mix precommit" .planning/phases/26-layout-width-foundations/26-HUMAN-UAT.md` returns matches.
  </acceptance_criteria>
</task>

</tasks>

<threat_model>
Markdown rendering is presentation-only and consumes already-rendered `Foglet.Markdown.render/1` tuples. Ensure blank-line handling never emits raw control characters into text nodes. Manual verification records evidence only and must not contain secrets, invite codes intended for real users, reset tokens, or private SSH keys.
</threat_model>

<verification>
- `rtk mix test test/foglet_bbs/tui/widgets/post/markdown_body_test.exs test/foglet_bbs/tui/screens/post_reader_test.exs`
- `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs`
- `rtk mix precommit`
</verification>

<success_criteria>
- Shared markdown body rendering preserves paragraph breaks exactly as specified.
- HUMAN-UAT artifact exists and maps to all Phase 26 acceptance criteria.
- Final automated verification is recorded.
</success_criteria>

