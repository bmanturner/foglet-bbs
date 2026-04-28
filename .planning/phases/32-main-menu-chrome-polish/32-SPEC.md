# Phase 32: Main Menu Chrome Polish — Specification

**Created:** 2026-04-27
**Ambiguity score:** 0.16 (gate: ≤ 0.20)
**Requirements:** 5 locked

## Goal

The Main Menu's Navigation and Oneliners inner panels render their titles embedded in the top border line (`┌─ Navigation ─┐`-style), eliminate the Oneliners top-border `||||` glyph artifact, present each navigation row's key as a bracketed `[X]` token in `theme.accent.fg` against a `theme.primary.fg` label, indent navigation rows one column inside the box border, and route every color decision in `lib/foglet_bbs/tui/screens/main_menu.ex` through `Foglet.TUI.Theme` (zero hardcoded color literals).

## Background

`lib/foglet_bbs/tui/screens/main_menu.ex` builds two inner panels with `box style: %{border: :single, border_fg: theme.border.fg}` and prepends a plain `text("Navigation", fg: theme.title.fg)` / `text("Oneliners", fg: theme.title.fg)` row as the first body line — so the panel "title" sits *inside* the box, one row below the top border, instead of being embedded in the border itself.

`nav_row/3` (line 304) renders each row as a single `text(...)` node coloring the entire string (`glyph + label + padding + key`) with `theme.primary.fg`. The key character is emitted bare (`B`, `A`, `C`, etc.) — there is no `[X]` bracket form anywhere in the screen today, and there is no path that gives the key a different color slot than the label. The leading body characters sit flush against the box's left border (no inner indent).

The Oneliners panel exhibits a `||||`/repeated-glyph artifact along its top border at certain terminal widths (called out in ROADMAP success criterion #2 at 64, 65, 66, 80, 81 columns) — a width-math off-by-one elsewhere in the chrome stack that this phase must close.

The destination glyph color routing referenced by the `D-08` comment in `main_menu.ex` (per-slot coloring of `●`, `✎`, `◇`, `⚑`, `▣`, `↯`) remains intentionally deferred — that comment stays accurate after this phase.

The screen-level outer chrome already embeds breadcrumb/status text in the border (`Foglet.TUI.Widgets.Chrome.ScreenFrame` does this for the screen frame). This phase brings the same border-embedded title pattern down to the inner Navigation and Oneliners panels.

## Requirements

1. **MENU-01 — Border-embedded panel titles**: Both inner panels render their titles inside the top border line, not as a body row.
   - Current: `nav_panel/3` and `oneliners_panel/2` emit `text("Navigation"|"Oneliners", fg: theme.title.fg)` as the first child of their inner column, sitting one row below an unbroken `┌──────────┐` top border.
   - Target: The Navigation panel's top border renders as `┌─ Navigation ─...─┐` and the Oneliners panel's top border renders as `┌─ Oneliners ─...─┐`, with the title text colored via `theme.title.fg` and the surrounding border via `theme.border.fg`. The first body row is the first navigation/oneliner entry.
   - Acceptance: `mix foglet.tui.render main_menu --width 80 --height 24` shows the literal substring `─ Navigation ─` on the Navigation panel's top border row, and `─ Oneliners ─` on the Oneliners panel's top border row. No standalone `Navigation`/`Oneliners` row appears below those borders in the rendered output.

2. **MENU-02 — Oneliners top-border artifact removed**: The Oneliners panel top border is a clean horizontal rule at all supported widths.
   - Current: At 64, 65, 66, 80, and 81-column SSH widths, the Oneliners panel top border shows a repeated-glyph artifact (e.g. `||||`) caused by an off-by-one in the panel's width math.
   - Target: The top border consists exclusively of `┌`, `─`, the embedded title segment from MENU-01, and `┐` — no `|`, no doubled separators, no truncation glyphs.
   - Acceptance: Rendering `main_menu` at widths 64, 65, 66, 80, and 81 (e.g. via `mix foglet.tui.render main_menu --width <N> --height 22`) produces an Oneliners panel top border line whose only non-space characters are drawn from `{┌, ─, ┐}` plus the embedded title characters from MENU-01. Manual SSH inspection at the same widths shows no visible `||||` or repeated-glyph artifact.

3. **MENU-03 — Bracketed accent key glyph**: Each navigation row's key renders as a bracketed `[X]` token in the theme accent slot, separate from the label.
   - Current: `nav_row/3` builds a single string `glyph <> " " <> label <> padding <> key` and renders it as one `text(..., fg: theme.primary.fg)` node — the bare key (e.g. `B`) inherits the primary color and there are no brackets.
   - Target: Each navigation row renders the key as `[X]` (e.g. `[B]`, `[A]`, `[Q]`) right-aligned within the panel inner width, colored via `theme.accent.fg`, while the leading glyph + label tokens render via `theme.primary.fg`. The row is composed of multiple `text` nodes inside a row layout so the two colors are independent.
   - Acceptance: `mix foglet.tui.render main_menu --width 80 --height 24` shows each visible nav row ending with `[X]` (square-bracket-wrapped single character or `↑/↓` for the multi-char case), and the brackets/key segment renders distinctly from the label segment. No bare `B`/`A`/etc. token appears at the right edge of a nav row without surrounding brackets.

4. **MENU-04 — Inner-indent alignment**: Navigation rows are indented one column inside the panel's left border.
   - Current: `nav_row/3` builds rows that begin with the glyph flush at column 0 of the inner panel — sitting directly against the box's left border (`│●  Boards ...`).
   - Target: Each navigation row starts with one space of left padding before the glyph, so the inner panel reads `│ ● Boards               [B] │`. The right edge math still keeps the `[X]` token inside the inner width.
   - Acceptance: `mix foglet.tui.render main_menu --width 80 --height 24` shows each visible nav row beginning with a space character immediately after the panel's left `│` border (verifiable by inspecting any row containing `Boards`, `Compose`, `Account`, `Moderation`, `Sysop`, or `Logout` — the character following `│` is U+0020, not a glyph).

5. **MENU-05 — Theme-only color routing**: `main_menu.ex` contains zero hardcoded color literals; every color flows through `Foglet.TUI.Theme` slots.
   - Current: The screen already routes `theme.title.fg`, `theme.border.fg`, and `theme.primary.fg` for existing nodes, but reintroducing accent and any new title/border embedding work risks regressing to hardcoded `IO.ANSI.*` calls or raw escape sequences.
   - Target: Every color attribute in `lib/foglet_bbs/tui/screens/main_menu.ex` (including the new bordered title and the new bracketed key) is sourced from `theme.<slot>.fg` (or `bg`/`style`). No `IO.ANSI.`, no `"\e["` literal, no atom literal `:red`/`:yellow`/etc. appears in the file.
   - Acceptance: `grep -nE 'IO\.ANSI|\\\\e\[|fg:\s*:[a-z]+|fg:\s*"#[0-9a-fA-F]' lib/foglet_bbs/tui/screens/main_menu.ex` returns zero matches. Switching to the operator-console theme (e.g. by toggling `state.session_context.theme`) re-renders both panels with the new theme's slot colors throughout — confirmable via `mix foglet.tui.render` output comparison if needed.

## Boundaries

**In scope:**
- Border-embedded titles for the Navigation and Oneliners inner panels in `main_menu.ex`.
- Width-math fix that eliminates the Oneliners `||||` top-border artifact (whether the fix lives in `main_menu.ex` or in a shared chrome helper is a discuss-phase decision).
- Introducing the `[X]` bracket form on navigation row keys and routing the bracketed token through `theme.accent.fg` while the label remains `theme.primary.fg`.
- One-column inner indent for navigation rows so the row body sits one space inside the box's left border.
- Confirming/maintaining 100% theme-slot color routing in `main_menu.ex` (no hardcoded literals).

**Out of scope:**
- Per-slot semantic coloring of the leading destination glyphs (`●` → `theme.success.fg`, `⚑` → `theme.warning.fg`, etc.) — explicitly deferred per the existing D-08 comment in `main_menu.ex`; that comment remains accurate after this phase.
- Generalizing border-embedded titles into a reusable widget abstraction available to other screens — this phase scopes to the Main Menu's two inner panels; reuse, if any, is a future refactor.
- Changes to the Oneliners selected-row marker (`> ` vs `  `), the oneliner body/handle clip widths, or any other Oneliners content rendering beyond the top border + title and indent that this phase touches.
- Changes to `ScreenFrame` outer chrome (top breadcrumb/status row, bottom command bar) — those are already border-embedded and not what this phase polishes.
- Changes to keybindings, navigation actions, or `handle_key/2` behavior — purely a presentation phase.
- Adding ExUnit/snapshot tests for the visual changes — the user has explicitly opted for "fix it, don't test it"; verification is via `mix foglet.tui.render` inspection and the grep-based color-literal check.

## Constraints

- Must preserve the existing right-align math for nav rows: the panel inner width budget (`nav_panel_inner_width/1`, floored at `@nav_panel_min_inner_width = 20`) is what fits at 64×22; the new `[X]` token plus inner indent must still fit at that floor.
- Must keep using `Foglet.TUI.TextWidth` for any new width arithmetic (e.g. measuring `[X]`, the embedded title segment, fill widths) — no byte-counting or naive `String.length/1`.
- Must not break the AGENTS.md invariant that `Foglet.TUI.Theme` is the single source of truth for colors in TUI screens.
- Must continue to render correctly with `Raxol.Core.Renderer.View` `box`/`column`/`row`/`text` primitives; introducing a new low-level rendering primitive is out of scope for the spec, though discuss-phase may pick a helper module location.
- No regression of the existing `mix foglet.tui.render main_menu` output for parts of the screen this phase does not touch (oneliners selection, command bar, breadcrumb).

## Acceptance Criteria

- [ ] At width 80×24, the Navigation panel's top border line contains `─ Navigation ─` and the Oneliners panel's top border line contains `─ Oneliners ─`.
- [ ] At width 80×24, no separate body row containing only the literal `Navigation` or `Oneliners` appears below the embedded titles.
- [ ] At each of widths 64, 65, 66, 80, and 81 (height 22 or 24), the Oneliners panel top border row contains only characters from `{┌, ─, ┐, space}` plus the embedded title segment — no `|`, no repeated-glyph artifact.
- [ ] Every visible navigation row in the rendered output ends with a bracketed `[X]` token (single char or `↑/↓`) — there is no bare key character at the right edge.
- [ ] The bracketed key segment in each nav row is a distinct render node from the label segment so they can take different theme slots.
- [ ] Every visible navigation row's first character after the panel's left `│` border is U+0020 (space), giving one column of inner indent.
- [ ] `grep -nE 'IO\.ANSI|\\\\e\[|fg:\s*:[a-z]+|fg:\s*"#[0-9a-fA-F]' lib/foglet_bbs/tui/screens/main_menu.ex` returns zero matches.
- [ ] Manual SSH inspection at 64×22 and 80×24 (or equivalent `mix foglet.tui.render` output) confirms no visible `||||` or repeated-glyph artifact and shows the new title/indent/accent layout.
- [ ] The existing D-08 comment block in `main_menu.ex` (deferring per-glyph slot routing) remains accurate — this phase did not opportunistically pick up that deferral.

## Ambiguity Report

| Dimension          | Score | Min  | Status | Notes                                                   |
|--------------------|-------|------|--------|---------------------------------------------------------|
| Goal Clarity       | 0.92  | 0.75 | ✓      | 5 specific, named changes; brackets confirmed introduced |
| Boundary Clarity   | 0.85  | 0.70 | ✓      | D-08 deferral, widget reuse, oneliners selection out    |
| Constraint Clarity | 0.75  | 0.65 | ✓      | TextWidth + Theme + Raxol primitives required           |
| Acceptance Criteria| 0.80  | 0.70 | ✓      | Render-output + grep-based pass/fail; no ExUnit tests    |
| **Ambiguity**      | 0.16  | ≤0.20| ✓      |                                                         |

Status: ✓ = met minimum, ⚠ = below minimum (planner treats as assumption)

## Interview Log

| Round | Perspective       | Question summary                                  | Decision locked                                                       |
|-------|-------------------|---------------------------------------------------|-----------------------------------------------------------------------|
| 0     | Researcher (scout)| What exists today in `main_menu.ex`?              | Inner-row title nodes; one-text-node nav rows; bare key char; primary-only color |
| 1     | Boundary Keeper   | Does this phase introduce `[X]` brackets?         | Yes — brackets + accent color are both this phase's scope             |
| 1     | Boundary Keeper   | Per-glyph semantic color routing for `●`/`⚑`/etc.?| Stay deferred — out of scope; D-08 comment remains accurate           |
| 1     | Boundary Keeper   | Test/verification surface area?                   | No tests required — manual fix + render-output and grep verification  |

---

*Phase: 32-main-menu-chrome-polish*
*Spec created: 2026-04-27*
*Next step: /gsd-discuss-phase 32 — implementation decisions (border-title rendering primitive, indent strategy, where the width fix lives)*
