---
phase: 32-main-menu-chrome-polish
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - lib/foglet_bbs/tui/screens/main_menu.ex
autonomous: true
requirements:
  - MENU-01
  - MENU-03
  - MENU-04
  - MENU-05
tags:
  - tui
  - raxol
  - chrome
  - theme

must_haves:
  truths:
    - "Navigation panel top border row contains the substring '─ Navigation ─' at width 80×24 and 64×22"
    - "Oneliners panel top border row contains the substring '─ Oneliners ─' at width 80×24 and 64×22"
    - "No standalone body row consisting of only the literal 'Navigation' or 'Oneliners' appears in the rendered output"
    - "Each navigation row ends with a bracketed [X] token (e.g. [B], [C], [A], [M], [S], [Q])"
    - "The bracketed [X] token is rendered as a distinct text node from the label so it can carry theme.accent.fg while the label stays theme.primary.fg"
    - "Each navigation row begins with one space (U+0020) immediately after the panel's left │ border"
    - "lib/foglet_bbs/tui/screens/main_menu.ex contains zero matches for IO.ANSI, raw \\e[ escapes, atom-color shorthand (fg: :red), or hex color literals (fg: \"#...\")"
  artifacts:
    - path: "lib/foglet_bbs/tui/screens/main_menu.ex"
      provides: "MainMenu render shape — :panel-typed Navigation/Oneliners panels with embedded titles, multi-node nav rows with primary label + accent bracketed key, one-column inner indent, theme-only color routing"
      contains: "%{type: :panel"
      contains_also: "[B]"
  key_links:
    - from: "nav_panel/3"
      to: "Raxol.UI.Layout.Panels.process/3 via :panel element type"
      via: "%{type: :panel, attrs: %{title: \"Navigation\", title_attrs: %{fg: theme.title.fg}, border: :single, border_fg: theme.border.fg}, children: [...]}"
      pattern: "%\\{type: :panel"
    - from: "oneliners_panel/2"
      to: "Raxol.UI.Layout.Panels.process/3 via :panel element type"
      via: "%{type: :panel, attrs: %{title: \"Oneliners\", title_attrs: %{fg: theme.title.fg}, border: :single, border_fg: theme.border.fg}, children: [...]}"
      pattern: "%\\{type: :panel"
    - from: "nav_row/3 leading segment"
      to: "theme.primary.fg"
      via: "text(\" \" <> glyph <> \" \" <> label <> padding, fg: theme.primary.fg)"
      pattern: "fg:\\s*theme\\.primary\\.fg"
    - from: "nav_row/3 bracketed key segment"
      to: "theme.accent.fg"
      via: "text(\"[\" <> key <> \"]\", fg: theme.accent.fg)"
      pattern: "fg:\\s*theme\\.accent\\.fg"
---

<objective>
Reshape the Main Menu's two inner panels and navigation rows so:

1. Navigation and Oneliners panels render their titles embedded in the box top border (`┌─ Navigation ─...─┐`) using Raxol's native `%{type: :panel, ...}` element type instead of `box do…end` with a first-body-row title (MENU-01, D-01, D-02).
2. Each navigation row composes two text nodes — a primary-color leading segment (` glyph label padding`) and an accent-color trailing `[X]` segment — so the bracketed key carries `theme.accent.fg` while the label stays `theme.primary.fg` (MENU-03, D-06, D-08, D-10).
3. Each navigation row prefix is indented by one space inside the box's left border, with the right-align padding budget reduced by 1 so the `[X]` token still fits inside the 64×22 floor inner-width budget of 20 (MENU-04, D-09).
4. Every color attribute in `lib/foglet_bbs/tui/screens/main_menu.ex` continues to source from `theme.<slot>.fg`/`bg`/`style` — no `IO.ANSI.*`, no raw `\e[` escapes, no atom shorthand, no hex literals (MENU-05, D-11).

Purpose: Bring the inner Navigation and Oneliners panels in line with the outer ScreenFrame's border-embedded title pattern, give the navigation key column the accent-on-label visual treatment described in MENU-03, and tighten alignment with a one-column inner indent — all while preserving the strict theme-only color routing convention.

Output: Updated `lib/foglet_bbs/tui/screens/main_menu.ex` with revised `nav_panel/3`, `oneliners_panel/2`, `nav_row/3`, and (if needed) `nav_panel_inner_width/1`. No new files; no new widget modules (D-12).
</objective>

<execution_context>
@/Users/brendan.turner/Dev/personal/foglet_bbs/.claude/get-shit-done/workflows/execute-plan.md
@/Users/brendan.turner/Dev/personal/foglet_bbs/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@.planning/phases/32-main-menu-chrome-polish/32-SPEC.md
@.planning/phases/32-main-menu-chrome-polish/32-CONTEXT.md
@AGENTS.md
@lib/foglet_bbs/tui/screens/main_menu.ex
@lib/foglet_bbs/tui/text_width.ex
@lib/foglet_bbs/tui/theme.ex
@vendor/raxol/lib/raxol/ui/layout/panels.ex
@vendor/raxol/lib/raxol/ui/layout/engine.ex

<interfaces>
<!-- Key contracts the executor needs. Do not re-explore the codebase to discover them. -->

From `lib/foglet_bbs/tui/text_width.ex`:
```elixir
@spec display_width(term()) :: non_neg_integer()
def display_width(text)

@spec pad_trailing(term(), integer()) :: String.t()
def pad_trailing(text, width)
```

From `vendor/raxol/lib/raxol/ui/layout/panels.ex` (the contract this plan consumes):
```elixir
# Panels.process/3 handles elements shaped like:
#   %{type: :panel, attrs: %{
#       title: "Navigation",                      # rendered as " Navigation " overlaid at (space.x + 2, space.y)
#       title_attrs: %{fg: ..., style: ...},      # text attrs for the embedded title
#       border: :single,                           # passed through to the underlying :box
#       border_fg: <fg>                            # passed through to the underlying :box
#     }, children: [...]
#   }
# The cell merger overlays the " {title} " text onto the top border row,
# producing `┌─ Navigation ─...─┐`.
```

From `lib/foglet_bbs/tui/theme.ex` (slots already present in every seeded theme):
```elixir
# theme.title.fg     # e.g. "#ffb000" or "#33ff66" — bold style available via theme.title.style
# theme.border.fg    # e.g. "#555555"
# theme.primary.fg   # e.g. "#cccccc" or "#33ff66"
# theme.accent.fg    # e.g. "#ffb000" — bold style available via theme.accent.style (NOT used in this plan per D-10)
```

Current `main_menu.ex` shapes (TO BE REPLACED):
```elixir
# nav_panel/3 (lines 293-302) — current shape:
defp nav_panel(destinations, theme, inner_width) do
  box style: %{border: :single, border_fg: theme.border.fg} do
    column style: %{gap: 0} do
      [
        text("Navigation", fg: theme.title.fg)
        | Enum.map(destinations, &nav_row(&1, theme, inner_width))
      ]
    end
  end
end

# oneliners_panel/2 (lines 313-319) — current shape:
defp oneliners_panel(state, theme) do
  box style: %{border: :single, border_fg: theme.border.fg} do
    column style: %{gap: 0} do
      [text("Oneliners", fg: theme.title.fg) | oneliner_rows(state, theme)]
    end
  end
end

# nav_row/3 (lines 304-311) — current shape:
defp nav_row(%{key: key, label: label, glyph: glyph}, theme, inner_width) do
  prefix = glyph <> " " <> label
  prefix_width = TextWidth.display_width(prefix)
  key_width = TextWidth.display_width(key)
  padding_width = max(inner_width - prefix_width - key_width, 1)
  padding = TextWidth.pad_trailing("", padding_width)
  text(prefix <> padding <> key, fg: theme.primary.fg)
end
```
</interfaces>
</context>

<tasks>

<task type="auto" tdd="false">
  <name>Task 1: Convert nav_panel/3 and oneliners_panel/2 to use Raxol :panel with embedded titles</name>
  <files>lib/foglet_bbs/tui/screens/main_menu.ex</files>
  <read_first>
    - lib/foglet_bbs/tui/screens/main_menu.ex (entire file — see current `nav_panel/3` at line 293, `oneliners_panel/2` at line 313, and the `import Raxol.Core.Renderer.View` on line 29)
    - vendor/raxol/lib/raxol/ui/layout/panels.ex (Panels.process/3 line 36, create_title_element/3 line 82 — confirms the title is overlaid as ` " {title} " ` at `(space.x + 2, space.y)` over the top border row)
    - vendor/raxol/lib/raxol/ui/layout/engine.ex (process_element :panel routing at line 111 — confirms `%{type: :panel, attrs: ..., children: ...}` is the consumed shape)
    - lib/foglet_bbs/tui/theme.ex lines 102-220 (confirms `theme.title.fg`, `theme.border.fg` slots in every seeded palette)
  </read_first>
  <action>
    Replace `nav_panel/3` (currently at line 293) with a function that returns a raw map of shape:

    ```elixir
    defp nav_panel(destinations, theme, inner_width) do
      %{
        type: :panel,
        attrs: %{
          title: "Navigation",
          title_attrs: %{fg: theme.title.fg},
          border: :single,
          border_fg: theme.border.fg
        },
        children: [
          column style: %{gap: 0} do
            Enum.map(destinations, &nav_row(&1, theme, inner_width))
          end
        ]
      }
    end
    ```

    Replace `oneliners_panel/2` (currently at line 313) with the analogous shape:

    ```elixir
    defp oneliners_panel(state, theme) do
      %{
        type: :panel,
        attrs: %{
          title: "Oneliners",
          title_attrs: %{fg: theme.title.fg},
          border: :single,
          border_fg: theme.border.fg
        },
        children: [
          column style: %{gap: 0} do
            oneliner_rows(state, theme)
          end
        ]
      }
    end
    ```

    Critical points:
    - REMOVE the existing `text("Navigation", fg: theme.title.fg)` and `text("Oneliners", fg: theme.title.fg)` first-row title nodes — the `:panel` element overlays the title onto the top border instead, per D-01/D-02.
    - DO NOT add a `style:` field on `title_attrs` — color only per D-10 (skip the bold from `theme.title.style` for now).
    - DO NOT use `box do…end` with a `:title` keyword — that path is dead in Raxol per CONTEXT canonical_refs (the engine strips `title` during positioning); only `%{type: :panel}` works.
    - DO NOT create a new widget module under `lib/foglet_bbs/tui/widgets/chrome/` — D-12 mandates inline.
    - Keep the `import Raxol.Core.Renderer.View` (used by the inner `column` macro and by `nav_row/3`).
    - `column` and `text` are imported from `Raxol.Core.Renderer.View` (already in scope at line 29). `:panel` is a raw element-type map — Raxol does not provide a `panel` macro; the map shape is the contract Engine consumes.

    Run `rtk mix format lib/foglet_bbs/tui/screens/main_menu.ex` after editing.
  </action>
  <verify>
    <automated>rtk mix compile --warnings-as-errors 2>&1 | grep -E "warning|error" | head -20 ; rtk grep -nE 'IO\.ANSI|\\\\e\[|fg:\s*:[a-z]+|fg:\s*"#[0-9a-fA-F]' lib/foglet_bbs/tui/screens/main_menu.ex | grep -v '^#' | wc -l</automated>
  </verify>
  <acceptance_criteria>
    - `rtk grep -n '%{type: :panel' lib/foglet_bbs/tui/screens/main_menu.ex` returns at least 2 matches (one for nav_panel, one for oneliners_panel).
    - `rtk grep -n 'text("Navigation"' lib/foglet_bbs/tui/screens/main_menu.ex` returns 0 matches (the body-row title is gone).
    - `rtk grep -n 'text("Oneliners"' lib/foglet_bbs/tui/screens/main_menu.ex` returns 0 matches.
    - `rtk grep -nE 'IO\.ANSI|\\\\e\[|fg:\s*:[a-z]+|fg:\s*"#[0-9a-fA-F]' lib/foglet_bbs/tui/screens/main_menu.ex | grep -v '^#'` returns 0 matches (MENU-05 grep gate).
    - `rtk mix compile --warnings-as-errors` exits 0.
    - `rtk mix foglet.tui.render main_menu --width 80 --height 24` runs without crash AND its output contains the substring `─ Navigation ─` AND the substring `─ Oneliners ─` (verify with `rtk mix foglet.tui.render main_menu --width 80 --height 24 | grep -F '─ Navigation ─'` exit 0 and same for `─ Oneliners ─`).
    - `rtk mix foglet.tui.render main_menu --width 80 --height 24 | grep -E '^\s*│\s*Navigation\s*│'` returns 0 matches (no body-row title remains).
  </acceptance_criteria>
  <done>
    Both inner panels are `%{type: :panel}` elements with their titles overlaid on the top border line; the previous body-row title text nodes are removed; the file still passes the MENU-05 color-literal grep gate.
  </done>
</task>

<task type="auto" tdd="false">
  <name>Task 2: Refactor nav_row/3 into a multi-node row composition with primary label and accent [X] key</name>
  <files>lib/foglet_bbs/tui/screens/main_menu.ex</files>
  <read_first>
    - lib/foglet_bbs/tui/screens/main_menu.ex (current `nav_row/3` at lines 304-311 — single text node)
    - lib/foglet_bbs/tui/text_width.ex (entire file — `display_width/1` line 17, `pad_trailing/2` line 110)
    - lib/foglet_bbs/tui/theme.ex (confirm `theme.primary.fg` and `theme.accent.fg` slots exist on every seeded theme — they do, per CONTEXT canonical_refs)
    - The `column`/`row`/`text` View DSL is imported via `import Raxol.Core.Renderer.View` (line 29). `row` macro composes children left-to-right.
  </read_first>
  <action>
    Replace `nav_row/3` (currently at lines 304-311) with a multi-node composition. The new shape:

    ```elixir
    defp nav_row(%{key: key, label: label, glyph: glyph}, theme, inner_width) do
      indent = " "
      bracketed_key = "[" <> key <> "]"

      prefix_text = indent <> glyph <> " " <> label
      prefix_width = TextWidth.display_width(prefix_text)
      bracketed_key_width = TextWidth.display_width(bracketed_key)

      # Right-align math: indent + glyph + " " + label + padding + [key]  must be ≤ inner_width.
      # `inner_width` is the panel's inner width (already net of borders) from `nav_panel_inner_width/1`.
      padding_width = max(inner_width - prefix_width - bracketed_key_width, 1)
      padding = TextWidth.pad_trailing("", padding_width)

      row do
        [
          text(prefix_text <> padding, fg: theme.primary.fg),
          text(bracketed_key, fg: theme.accent.fg)
        ]
      end
    end
    ```

    Critical points:
    - The leading text node carries `theme.primary.fg`; the bracketed-key text node carries `theme.accent.fg`. These are TWO separate render nodes so the colors are independent (MENU-03 acceptance).
    - The bracket characters AND the key character all flow through `theme.accent.fg` together — single `text("[" <> key <> "]", fg: theme.accent.fg)` node per D-08.
    - DO NOT add `style: theme.accent.style` to the accent text — color only per D-10 (deferred until contrast review).
    - The leading `indent = " "` (one space, U+0020) implements the MENU-04 one-column inner indent (D-09). DO NOT use `box padding: 1` — would shift the title and add blank top/bottom rows.
    - Use `TextWidth.display_width/1` (NOT `String.length/1`) for `[X]` measurement; the bracket characters and the `↑/↓` candidate keys (not relevant for nav rows per D-07 but defensive) need terminal-cell width, not codepoint count.
    - Use `TextWidth.pad_trailing("", padding_width)` (NOT `String.duplicate(" ", padding_width)` and NOT plain string padding) — preserves the established convention.
    - `row` macro is imported from `Raxol.Core.Renderer.View` (already imported at line 29). It composes children horizontally.

    Inner-width budget sanity check at the 64×22 floor (`@nav_panel_min_inner_width = 20`):
      `" "` (1) + longest visible label `Moderation` (10) + glyph (1) + space (1) + `[X]` (3) = 16 cols → leaves 4 cols of trailing padding. Fits.

    Run `rtk mix format lib/foglet_bbs/tui/screens/main_menu.ex` after editing.
  </action>
  <verify>
    <automated>rtk mix compile --warnings-as-errors 2>&1 | grep -E "warning|error" | head -20 ; rtk mix foglet.tui.render main_menu --width 80 --height 24 2>&1 | grep -E '\[B\]|\[C\]|\[A\]|\[Q\]' | head -10</automated>
  </verify>
  <acceptance_criteria>
    - `rtk grep -nE 'fg:\s*theme\.accent\.fg' lib/foglet_bbs/tui/screens/main_menu.ex` returns at least 1 match (the bracketed-key node).
    - `rtk grep -n '"\[" <> key <> "\]"' lib/foglet_bbs/tui/screens/main_menu.ex` OR `rtk grep -nF '"[" <> key <> "]"' lib/foglet_bbs/tui/screens/main_menu.ex` returns at least 1 match (the bracketed-key string construction).
    - `rtk grep -nE 'IO\.ANSI|\\\\e\[|fg:\s*:[a-z]+|fg:\s*"#[0-9a-fA-F]' lib/foglet_bbs/tui/screens/main_menu.ex | grep -v '^#'` returns 0 matches (MENU-05 grep gate still clean).
    - `rtk mix compile --warnings-as-errors` exits 0.
    - `rtk mix foglet.tui.render main_menu --width 80 --height 24` output contains all of: `[B]`, `[C]`, `[A]` (assuming Account-visible role from RenderFixtures `@alice`), `[Q]`. Verify with: `rtk mix foglet.tui.render main_menu --width 80 --height 24 | grep -F '[B]'` exit 0; same for `[C]`, `[A]`, `[Q]`.
    - `rtk mix foglet.tui.render main_menu --width 80 --height 24 | grep -E '\s+B\s*│\s*$'` returns 0 matches (no bare-key right-edge token without brackets).
  </acceptance_criteria>
  <done>
    Each navigation row renders as two text nodes — primary-color leading segment and accent-color `[X]` segment — with right-align math driven by `TextWidth.display_width/1` and a one-space leading indent.
  </done>
</task>

<task type="auto" tdd="false">
  <name>Task 3: Verify width budget at 64×22 floor and inspect renders at all canonical sizes</name>
  <files>lib/foglet_bbs/tui/screens/main_menu.ex</files>
  <read_first>
    - lib/foglet_bbs/tui/screens/main_menu.ex (after Task 1 + 2 changes; review `nav_panel_inner_width/1` at lines 277-291)
    - lib/foglet_bbs/tui/text_width.ex (display_width/1)
  </read_first>
  <action>
    Verify the inner-width budget holds after Tasks 1 and 2:

    1. Render at the 64×22 floor:
       ```
       rtk mix foglet.tui.render main_menu --width 64 --height 22
       ```
       Inspect every nav row (rows containing `●`, `✎`, `◇`, `⚑`, `▣`, `↯`). The row content (excluding the box border `│`) MUST be ≤ 20 cells wide. The panel inner_width at 64×22 is 20 (the floor `@nav_panel_min_inner_width`).

    2. Confirm the existing `nav_panel_inner_width/1` math (lines 277-291) does not need changes — the indent is absorbed inside the existing inner-width budget by reducing the right-align padding. The inner-width budget formula (`max(left_alloc - box_border, @nav_panel_min_inner_width)`) is unchanged; only `nav_row/3`'s consumption of that budget changed.

       If a row at 64×22 overflows (`TextWidth.display_width(row) > inner_width`), the most likely cause is that `Moderation` (10 chars) + glyph (1) + space (1) + `[M]` (3) + indent (1) = 16, but a wider label could exceed. All current labels are ≤ 10 chars (`Moderation` is the longest). If overflow occurs anyway, narrow the right-align padding floor from `max(..., 1)` to `max(..., 0)` to give one more cell. Do NOT change the floor `@nav_panel_min_inner_width = 20`.

    3. Render at 80×24 and 132×50 to confirm widening behavior:
       ```
       rtk mix foglet.tui.render main_menu --width 80 --height 24
       rtk mix foglet.tui.render main_menu --width 132 --height 50
       ```
       Each nav row should still end with `[X]` right-aligned and start with one space after the `│`.

    4. Confirm the existing D-08 deferral comment block (lines 55-62) remains accurate — Phase 32 did NOT pick up per-glyph semantic coloring (the `●`/`✎`/`◇`/`⚑`/`▣`/`↯` glyphs still flow through `theme.primary.fg` via the leading text node, not separate per-glyph slot colors). No edits to that comment.

    No code changes expected in this task UNLESS overflow is observed at 64×22; in that case make the minimal right-align-floor adjustment described in step 2.
  </action>
  <verify>
    <automated>for w in 64 80 132; do rtk mix foglet.tui.render main_menu --width $w --height 22 2>&1 | grep -F '[B]' >/dev/null && echo "W=$w OK" || echo "W=$w MISSING [B]"; done</automated>
  </verify>
  <acceptance_criteria>
    - At width 64 height 22, `rtk mix foglet.tui.render main_menu --width 64 --height 22 | grep -E '│ ● Boards.*\[B\]'` returns at least 1 match (one space after `│`, label `Boards`, bracketed key `[B]`).
    - At width 80 height 24, the same `│ ● Boards ... [B]` pattern is present.
    - At all three widths (64, 80, 132), every nav row ends with a bracketed key token (`[B]`, `[C]`, `[A]`, `[M]` if visible, `[S]` if visible, `[Q]`).
    - `rtk mix compile --warnings-as-errors` exits 0.
    - The comment block at `lib/foglet_bbs/tui/screens/main_menu.ex:55-62` (the D-08 deferral) is unchanged — verify with `rtk grep -n 'per-glyph slot routing' lib/foglet_bbs/tui/screens/main_menu.ex` still returns a match in the same line range.
  </acceptance_criteria>
  <done>
    The render at 64×22, 80×24, and 132×50 shows correctly indented, bracketed nav rows; no overflow; the D-08 deferral comment is intact.
  </done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| TUI render → terminal | Untrusted user-visible text (e.g. oneliner body, user handle) flows through `text(...)` nodes. This plan does NOT change which text reaches the terminal — only the rendering shape (panel, row composition, indent, color slots). |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-32-01 | Information disclosure | nav_row/3 multi-node composition | accept | The bracketed-key token is built from `@main_menu_commands` static descriptors (`B`, `C`, `A`, `M`, `S`, `Q`) — no untrusted input flows into the `[X]` text. Label and glyph are also static. No new injection surface. |
| T-32-02 | Tampering | theme color routing in main_menu.ex | mitigate | MENU-05 grep gate (`IO\.ANSI|\\e\[|fg:\s*:[a-z]+|fg:\s*"#[0-9a-fA-F]`) is enforced as an acceptance criterion on every task. A regression to hardcoded colors would fail the verify step before the change can land. |
| T-32-03 | Denial of service | nav_panel_inner_width/1 floor | accept | Existing `@nav_panel_min_inner_width = 20` floor protects against pathological terminal sizes. No new arithmetic introduced; right-align padding floor stays `max(..., 1)` (or `max(..., 0)` if Task 3 finds overflow). |
</threat_model>

<verification>
- `rtk mix compile --warnings-as-errors` exits 0.
- `rtk grep -nE 'IO\.ANSI|\\\\e\[|fg:\s*:[a-z]+|fg:\s*"#[0-9a-fA-F]' lib/foglet_bbs/tui/screens/main_menu.ex | grep -v '^#'` returns 0 matches.
- `rtk mix foglet.tui.render main_menu --width 80 --height 24 | grep -F '─ Navigation ─'` exit 0.
- `rtk mix foglet.tui.render main_menu --width 80 --height 24 | grep -F '─ Oneliners ─'` exit 0.
- `rtk mix foglet.tui.render main_menu --width 80 --height 24 | grep -F '[B]'` exit 0; same for `[C]`, `[A]`, `[Q]`.
- `rtk mix foglet.tui.render main_menu --width 64 --height 22 | grep -E '│ ● Boards.*\[B\]'` exit 0.

Do not run `rtk mix precommit` in this plan; existing tests in `layout_smoke_test.exs:1077-1118` and `main_menu_test.exs` will fail on the new render shape — those updates land in Plan 32-03. `mix precommit` is the finish line for the whole phase, exercised after Plan 32-03 runs.
</verification>

<success_criteria>
- Both inner panels render via `%{type: :panel}` with embedded titles in the top border.
- Each navigation row composes two text nodes (primary label + accent bracketed key) with one-column inner indent.
- Zero hardcoded color literals in `lib/foglet_bbs/tui/screens/main_menu.ex`.
- 64×22 floor render shows no overflow; all nav rows fit within `inner_width = 20`.
- D-08 deferral comment block remains accurate (no opportunistic per-glyph coloring).
</success_criteria>

<output>
After completion, create `.planning/phases/32-main-menu-chrome-polish/32-01-SUMMARY.md` documenting:
- Final shape of `nav_panel/3`, `oneliners_panel/2`, `nav_row/3`.
- Whether `nav_panel_inner_width/1` needed adjustment (and if so, what).
- Render output at 64×22, 80×24, 132×50 (key lines, not the full grid).
- Confirmation that MENU-01, MENU-03, MENU-04, MENU-05 acceptance criteria pass.
- Status of the Oneliners `||||` artifact at widths 64/65/66/80/81 (handed to Plan 32-02 for verification).
</output>
