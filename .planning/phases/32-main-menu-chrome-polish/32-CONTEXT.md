# Phase 32: main-menu-chrome-polish - Context

**Gathered:** 2026-04-27 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 32 polishes the Main Menu's two inner chrome panels (Navigation and Oneliners) so their titles render embedded in the box top border (`┌─ Navigation ─┐`-style) instead of as the first body row, eliminates the Oneliners top-border `||||`/repeated-glyph artifact at widths 64/65/66/80/81, renders each navigation row's key as a bracketed `[X]` token in `theme.accent.fg` against a `theme.primary.fg` label, indents nav rows one column inside the box border, and confirms zero hardcoded color literals in `lib/foglet_bbs/tui/screens/main_menu.ex`. Per-glyph semantic coloring (D-08 deferral), reusable border-title widgets, and Oneliners content rendering remain out of scope.
</domain>

<decisions>
## Implementation Decisions

### Border-Embedded Title Primitive

- **D-01:** Use Raxol's native `%{type: :panel, attrs: %{...}, children: [...]}` element type for the Navigation and Oneliners inner panels — not the `box do…end` macro with `:title`, not a new custom engine primitive. `Panels.process` (`vendor/raxol/lib/raxol/ui/layout/panels.ex:36-50`) already produces the box border PLUS a positioned `:text` overlay at `(space.x + 2, space.y)` whose content is `" {title} "`. The cell merger overlays the title onto the top border row, yielding the required `┌─ Navigation ─...─┐` substring.
- **D-02:** Theme route the title via `title_attrs: %{fg: theme.title.fg}` and the border via the panel's `border_fg` (matching the existing `box style: %{border: :single, border_fg: theme.border.fg}` shape). No `style:` field on the title (color only — see D-09).

### Oneliners Width-Math Artifact

- **D-03:** Verify-first, do not pre-commit to a fix location. After the D-01 `:panel` switch lands, the planner runs `mix foglet.tui.render main_menu --width <N>` at each of widths 64, 65, 66, 80, 81 to confirm whether the `||||` artifact persists. There is no current evidence that `split_pane(ratio: {2,3})` is the root cause; the artifact may resolve organically when the first-body-row title node is removed and panel borders are emitted via the `:panel` path.
- **D-04:** If the artifact persists after D-01, the planner investigates root cause through targeted reproduction before choosing a fix location (screen-level explicit child widths, `Panels.process` border math, or `split_pane` rounding). Fix lives in `main_menu.ex` if at all possible; vendor changes only if the root cause is unambiguously in `vendor/raxol/`.
- **D-05:** Verification surface is `mix foglet.tui.render main_menu --width <N> --height 22` (or `--height 24`) plus manual SSH inspection at the same widths. The Oneliners top border row must contain only characters from `{┌, ─, ┐, space}` plus the embedded title segment from D-01.

### Bracketed Accent Key — Multi-Node Nav Row

- **D-06:** Replace `nav_row/3`'s single `text(...)` node with a `row` layout (or equivalent multi-node composition) containing two `text` nodes: a primary-color leading segment (`" ● Boards               "`) and an accent-color trailing segment (`"[B]"`). Spacer width derives from `Foglet.TUI.TextWidth.display_width/1` to keep right-alignment.
- **D-07:** Only single-character destination keys (B, C, A, M, S, Q) appear as nav rows and get the `[X]` form. The `↑/↓` action key lives in the command bar, not in nav rows; it is not bracketed by this phase.
- **D-08:** The bracketed token is rendered as a single `text` node with content `"[X]"` (3 display columns) — bracket characters and the key character all flow through `theme.accent.fg` together.

### Inner Indent

- **D-09:** Indent by prepending one space character to each row's leading prefix and reducing the right-align padding budget by 1. Do **not** use box `padding: 1` — it would also shift the title vertically/horizontally and add blank top/bottom rows. Inner-width budget at 64×22 (floor 20) holds: `" "` (1) + longest visible label `Moderation` (10) + glyph (1) + space (1) + `[X]` (3) = 16, leaving 4 cols of trailing padding.

### Theme Routing

- **D-10:** Apply `fg: theme.accent.fg` to the `[X]` text node only. Skip `theme.accent.style` (`[:bold]` in seeded themes) — SPEC MENU-03 specifies color, not bold. If contrast is insufficient post-implementation, adding `style:` is a one-line follow-up.
- **D-11:** Maintain MENU-05 grep cleanliness: every color attribute in `main_menu.ex` (existing and new) must source from `theme.<slot>.fg` (or `bg`/`style`). The grep `IO\.ANSI|\\\\e\[|fg:\s*:[a-z]+|fg:\s*"#[0-9a-fA-F]` must return zero matches in `lib/foglet_bbs/tui/screens/main_menu.ex` after the change.

### Helper Module Placement

- **D-12:** All changes live inline in `lib/foglet_bbs/tui/screens/main_menu.ex`. Do not create a new widget module under `lib/foglet_bbs/tui/widgets/chrome/` or elsewhere. The reusable abstraction (the `:panel` element) already exists in `vendor/raxol/`; reuse for other screens, if any, is a future refactor (per SPEC out-of-scope).

### Test Updates

- **D-13:** Update `test/foglet_bbs/tui/layout_smoke_test.exs` (the `main_menu renders Navigation and Oneliners panels at distinct y positions` test at line 1077, and any matching assertions in `test/foglet_bbs/tui/screens/main_menu_test.exs`) to reflect the new render shape: border-embedded titles, bracketed `[X]` keys, and one-column indent. SPEC's "no new tests" rule applies to net-new test additions, not to keeping existing tests in sync — `mix precommit` would otherwise red-flag the diff.

### Claude's Discretion

- Exact `row`-vs-positioned-text composition for nav rows is a planner choice as long as the two color slots end up on distinct render nodes and the right-align math holds at the 64×22 floor.
- Whether to introduce a private `nav_row/3 → {prefix_node, key_node}` helper or inline the composition is a planner style choice.
- Existing D-08 deferral comment in `main_menu.ex` (per-glyph slot routing for `●`/`✎`/`◇`/`⚑`/`▣`/`↯`) stays accurate — this phase does not opportunistically pick up that deferral.

### Folded Todos

None.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase Definition
- `.planning/phases/32-main-menu-chrome-polish/32-SPEC.md` — Locked requirements (MENU-01..MENU-05), boundaries, constraints, acceptance criteria.
- `.planning/ROADMAP.md` — Phase 32 success criteria; Phase 26 dependency on shared width primitives.
- `.planning/REQUIREMENTS.md` — v1.4 milestone requirements (Main Menu Chrome Polish section).
- `.planning/PROJECT.md` — SSH/TUI-first product boundary; v1.4 stabilization scope.

### Phase 26 Dependency
- `.planning/phases/26-layout-width-foundations/26-CONTEXT.md` — Locked decisions on shared width primitives in `Foglet.TUI.TextWidth` (D-01) and screen-thinness convention (D-02). Phase 32 must consume `TextWidth.display_width/1` for any new width arithmetic (`[X]` measurement, embedded title segment, fill widths). Phase 26 added `TextWidth.wrap/2`; this phase does not need wrap, only `display_width` + `pad_trailing`.

### Source Files (target of change)
- `lib/foglet_bbs/tui/screens/main_menu.ex` — All Phase 32 implementation lives here. Existing `nav_panel/3` (line 293), `oneliners_panel/2` (line 313), `nav_row/3` (line 304), and `nav_panel_inner_width/1` (line 277) are the load-bearing functions to revise.

### Raxol Primitive Contracts (read-only reference)
- `vendor/raxol/lib/raxol/ui/layout/engine.ex` — `process_element(%{type: :panel}, ...)` (line 111) routes to `Panels.process`; `process_element(%{type: :foglet_screen_frame}, ...)` (line 288) shows the existing custom-primitive precedent (do **not** add a sibling primitive in this phase).
- `vendor/raxol/lib/raxol/ui/layout/panels.ex` — `Panels.process/3` (line 36) and `create_title_element/3` (line 82) define the title-on-border overlay shape consumed by D-01.
- `vendor/raxol/lib/raxol/ui/ui_renderer.ex` — `render_visible_element` for `:panel` (line 140) and `:box` (line 148) define cell-merge order.
- `vendor/raxol/lib/raxol/core/renderer/view/components/box.ex` — `Box.new/1` reference for keyword opts. **Note:** passing `title:` to `box do…end` is a dead path (Engine strips `title` during positioning); D-01's `:panel` is the working primitive.

### TUI Foundation
- `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex` — Outer chrome's border-embedded title pattern (precedent, not a primitive to reuse for inner panels in this phase).
- `lib/foglet_bbs/tui/text_width.ex` — `display_width/1` and `pad_trailing/2` for the new bracketed-key right-alignment math.
- `lib/foglet_bbs/tui/theme.ex` — `theme.accent.fg` slot exists in all seeded themes (lines 106, 122, 138, 154, 170, 186, 202, 218); `theme.title.fg`, `theme.border.fg`, `theme.primary.fg` already in use.

### Verification & Test Surface
- `mix foglet.tui.render main_menu --width <N> --height <M>` — Primary verification path. Used at widths 64, 65, 66, 80, 81 for Oneliners artifact verification (D-03/D-05) and at 80×24 for the embedded-title and bracketed-key assertions.
- `test/foglet_bbs/tui/layout_smoke_test.exs:1077-1118` — Existing main-menu render test; assertions on `text == "Navigation"`, `text =~ ~r/●.*Boards.*B$/` will fail under the new shape and must be updated (D-13).
- `test/foglet_bbs/tui/screens/main_menu_test.exs` — Mirrored screen-level test file; review for assertions that need parallel updates.

### Project Conventions
- `AGENTS.md` — `Foglet.TUI.Theme` is the single source of truth for TUI colors; widgets receive theme explicitly; render functions stay pure over loaded state. `mix precommit` is the finish line.
- `docs/raxol/getting-started/WIDGET_GALLERY.md` — Raxol layout primitive reference.
- `lib/foglet_bbs/tui/widgets/README.md` — Foglet widget catalog and theme-routing requirements.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **`Foglet.TUI.TextWidth`** (`lib/foglet_bbs/tui/text_width.ex`) — `display_width/1`, `pad_trailing/2`, `slice_to_width/2` already used by `nav_row/3`. New `[X]` measurement and indent math reuses these directly. Phase 26 added `wrap/2` (not needed here).
- **`Foglet.TUI.Theme`** (`lib/foglet_bbs/tui/theme.ex`) — `theme.accent.fg`, `theme.title.fg`, `theme.border.fg`, `theme.primary.fg` slots all exist in every seeded theme. No new theme slots required.
- **Raxol `:panel` element type** (`vendor/raxol/lib/raxol/ui/layout/panels.ex`) — Native border-embedded-title primitive. Currently unused in Foglet production code (no `%{type: :panel}` literals in `lib/`); Phase 32 is the first consumer.
- **Raxol `row`/`column`/`text` View DSL** — `import Raxol.Core.Renderer.View` already in `main_menu.ex:29`; `row do…end` for the multi-node nav-row composition is a one-liner.

### Established Patterns

- TUI render functions receive `theme` explicitly and stay pure over loaded state (`AGENTS.md`).
- Screen modules delegate display primitives where helpers exist; this phase intentionally stays inline (D-12) per SPEC out-of-scope.
- `Foglet.TUI.Widgets.Chrome.ScreenFrame` already embeds breadcrumb/status text in the outer screen border via the custom `:foglet_screen_frame` primitive — Phase 32 brings the same border-embedded title concept to inner panels via Raxol's standard `:panel`, not a new custom primitive.
- Color routing convention: every color attribute in TUI screen files flows through `theme.<slot>.fg` (or `bg`/`style`); MENU-05's grep gate enforces it for `main_menu.ex`.
- 64×22 is the hard minimum terminal size; 80×24 is the compact verification target. `nav_panel_inner_width/1` floors at `@nav_panel_min_inner_width = 20`.

### Integration Points

- **`MainMenu.render/1`** (`main_menu.ex:77-97`) calls `nav_panel/3`, `oneliners_panel/2`, then composes them via `split_pane(ratio: {2,3})` and wraps with `ScreenFrame.render/4`. Outer chrome is unchanged by this phase; the inner panels (`nav_panel/3` line 293 and `oneliners_panel/2` line 313) are the swap points.
- **`nav_row/3`** (`main_menu.ex:304-311`) is the single function that builds each navigation row as one string + one `text(...)` node. D-06 replaces this with a multi-node composition.
- **`nav_panel_inner_width/1`** (`main_menu.ex:277-291`) — Existing inner-width budget math. May need a 1-column reduction for the new indent (D-09) depending on whether the indent comes out of the inner budget or the box's reserved space.
- **`@main_menu_commands`** (`main_menu.ex:63-73`) — Single canonical command descriptor list (D-01 from Phase 19); destination entries already carry `:key`, `:label`, `:glyph`. No descriptor changes needed; only the renderer evolves.
- **`mix foglet.tui.render main_menu`** — Mix task wired to `Foglet.TUI.RenderFixtures` produces a synthetic main menu render with `@alice` (sysop role) so Account/Moderation/Sysop entries appear. Primary visual-inspection path.
- **`test/foglet_bbs/tui/layout_smoke_test.exs:1077`** — Existing assertion shape needs updates per D-13.
</code_context>

<specifics>
## Specific Ideas

- **Verify-first on the Oneliners artifact (D-03):** the user's correction explicitly rejects pre-judging the root cause as a `split_pane` rounding bug. The planner's first move is to land D-01 (the `:panel` switch) and re-render at widths 64, 65, 66, 80, 81 via `mix foglet.tui.render main_menu --width <N> --height 22` before deciding whether any further fix is required. If the artifact disappears, MENU-02 is satisfied without additional code.
- **D-08 deferral comment stays accurate:** per-glyph semantic coloring (`●` → `theme.success.fg`, `⚑` → `theme.warning.fg`, etc.) is NOT part of Phase 32. The existing comment block in `main_menu.ex:55-62` continues to describe accurate state after the phase.
</specifics>

<deferred>
## Deferred Ideas

- **Reusable border-title widget abstraction** for other screens (e.g., a `Foglet.TUI.Widgets.Chrome.TitledPanel` module) — explicitly out of scope per SPEC. If multiple screens need this pattern in a future milestone, lift the inline approach into a widget then.
- **Per-glyph semantic coloring** (`●` success, `✎` info, `⚑` warning, `▣` accent, `↯` neutral, `◇` muted) — D-08 deferral remains. This phase keeps glyphs at `theme.primary.fg` (label slot) and only differentiates the bracketed key segment.
- **Bold/style on the accent key** (`style: theme.accent.style`) — kept off (D-10) until visual review confirms the color-only treatment provides enough contrast across themes.
- **Custom `:foglet_titled_panel` engine primitive** — the `:foglet_screen_frame` precedent shows it's possible, but D-01 demonstrates the native `:panel` is sufficient. Reserve a custom primitive for a case where `:panel` falls short.

### Reviewed Todos (not folded)

None — no pending todos matched Phase 32.
</deferred>

---

*Phase: 32-main-menu-chrome-polish*
*Context gathered: 2026-04-27*
