---
phase: 32-main-menu-chrome-polish
plan: 01
subsystem: ui
tags: [tui, raxol, chrome, theme, panel, render]

# Dependency graph
requires:
  - phase: 26-layout-width-foundations
    provides: Foglet.TUI.TextWidth display_width/1 + pad_trailing/2 used for nav row right-align math
  - phase: 19-main-menu (predecessor of canonical descriptor list)
    provides: "@main_menu_commands single-source descriptor list with key/label/glyph/visibility"
provides:
  - "MainMenu Navigation panel renders title embedded in top border via Raxol :panel"
  - "MainMenu Oneliners panel renders title embedded in top border via Raxol :panel"
  - "Navigation rows compose two text nodes — primary-color label + accent-color [X] key"
  - "Navigation rows have one-column inner indent inside the panel left border"
  - "lib/foglet_bbs/tui/screens/main_menu.ex stays color-literal-free (MENU-05 grep clean)"
affects:
  - 32-02-oneliners-artifact (must own SplitPane horizontal-divider artifact fix; this plan handed it off after confirming the panel switch did not resolve it)
  - 32-03-test-updates (layout_smoke_test.exs and main_menu_test.exs assertions need updates to match new shape)

tech-stack:
  added: []
  patterns:
    - "Raxol :panel element type — first production consumer in Foglet, used for border-embedded titles on inner panels"
    - "Multi-node row composition for split-color text — primary label + accent bracketed key in one row"
    - "Sentinel large width/height (9999) on :panel to force full-pane fill via apply_constraints clamp"

key-files:
  created: []
  modified:
    - "lib/foglet_bbs/tui/screens/main_menu.ex"

key-decisions:
  - "Pass explicit width: 9999, height: 9999 on :panel attrs so Panels.apply_constraints/2 clamps to available_space; without these the panel shrinks to children-measured size and the title segment is truncated"
  - "Use `row [], do: ...` not `row do ... end` — the bare form matches Raxol View's `row/1` function (loses do-block contents) instead of the `row/2` macro"
  - "Inner indent absorbed into right-align padding budget (D-09); no @nav_panel_min_inner_width adjustment needed at the 64×22 floor"

patterns-established:
  - "Border-embedded titles for inner panels: %{type: :panel, attrs: %{title:, title_attrs:, border:, border_fg:, width: 9999, height: 9999}, children: [...]}"
  - "Multi-color rows: row [], do: [text(prefix, fg: theme.primary.fg), text(accent_token, fg: theme.accent.fg)]"

requirements-completed:
  - MENU-01
  - MENU-03
  - MENU-04
  - MENU-05

# Metrics
duration: 10min
completed: 2026-04-28
---

# Phase 32 Plan 01: Render Shape Summary

**MainMenu Navigation and Oneliners panels switched to Raxol `:panel` border-embedded titles, nav rows refactored to two-node row layout with primary label + accent-color `[X]` key and one-column inner indent — all under strict theme-only color routing.**

## Performance

- **Duration:** 10 min
- **Started:** 2026-04-28T02:38:25Z
- **Completed:** 2026-04-28T02:48:23Z
- **Tasks:** 3 (Task 3 verification-only, no commit)
- **Files modified:** 1 (`lib/foglet_bbs/tui/screens/main_menu.ex`)

## Accomplishments

- Navigation and Oneliners panels emit `%{type: :panel}` element shape so Raxol's `Panels.process/3` overlays the title (`" Navigation "` / `" Oneliners "`) onto the top border row instead of rendering as a body text node (MENU-01, D-01, D-02).
- Each navigation row is now a two-node `row` composition: a primary-color leading segment (`" " <> glyph <> " " <> label <> padding`, theme.primary.fg) and an accent-color trailing token (`"[" <> key <> "]"`, theme.accent.fg) (MENU-03, D-06, D-08, D-10).
- Nav rows are indented one column inside the panel's left border by prepending a space and absorbing the cost from the right-align padding budget (MENU-04, D-09). At the 64×22 floor (`@nav_panel_min_inner_width = 20`), the longest-label row (`Moderation`, 10 chars) consumes 16 cells, leaving 4 cols of trailing padding — no floor adjustment needed.
- `lib/foglet_bbs/tui/screens/main_menu.ex` remains color-literal-free: zero `IO.ANSI`, raw escapes, atom-color shorthand, or hex literals. Every color flows through `theme.<slot>.fg` (MENU-05).

## Task Commits

1. **Task 1: Convert nav_panel/3 and oneliners_panel/2 to use Raxol :panel with embedded titles** — `667bedf` (feat)
2. **Task 2: Refactor nav_row/3 into a multi-node row composition with primary label and accent [X] key** — `f7af3d5` (feat)
3. **Task 3: Verify width budget at 64×22 floor and inspect renders at all canonical sizes** — no commit (verification-only; no code changes required since the budget held without floor adjustment)

## Files Created/Modified

- `lib/foglet_bbs/tui/screens/main_menu.ex` — replaced `nav_panel/3` and `oneliners_panel/2` `box do…end` shapes with raw `:panel` maps; rewrote `nav_row/3` from a single `text(...)` node to a `row [], do: [text(...), text(...)]` composition with primary/accent color split.

## Render Output (Key Lines)

### 64×22 (floor)

```
│┌─ Navigation ─────────┐||||||||||||||||||||─────────────────┐│
││ ● Boards          [B]│ │> @unknown  Welcome to Foglet      ││
││ ✎ Compose         [C]│ │  @unknown  New thread in /ge      ││
││ ◇ Account         [A]│ │                                   ││
││ ⚑ Moderation      [M]│ │                                   ││
││ ▣ Sysop           [S]│ │                                   ││
││ ↯ Logout          [Q]│ │                                   ││
```

### 80×24

```
│┌─ Navigation ───────────────┐||||||||||||||||||||||─────────────────────────┐│
││ ● Boards                [B]│ │> @unknown  Welcome to Foglet                ││
││ ✎ Compose               [C]│ │  @unknown  New thread in /ge                ││
││ ◇ Account               [A]│ │                                             ││
││ ⚑ Moderation            [M]│ │                                             ││
││ ▣ Sysop                 [S]│ │                                             ││
││ ↯ Logout                [Q]│ │                                             ││
```

### 132×50 (just nav rows)

```
│┌─ Navigation ────────────────────────────────────┐||||||||||||...||──────────────────────────────┐│
││ ● Boards                                     [B]│ │> @unknown  Welcome to Foglet ...
││ ✎ Compose                                    [C]│
││ ◇ Account                                    [A]│
││ ⚑ Moderation                                 [M]│
││ ▣ Sysop                                      [S]│
││ ↯ Logout                                     [Q]│
```

At all three widths: nav row begins with one space after `│`, glyph + label render in primary fg, padding right-aligns `[X]` against the inner border, brackets carry accent fg. No overflow at the 64×22 floor.

## Acceptance Criteria Status

- **MENU-01 — Border-embedded panel titles**: PASS at 64/80/132. `─ Navigation ─` substring present on the Navigation panel top border row at all three widths.
- **MENU-03 — Bracketed accent key glyph**: PASS. Each visible nav row ends with `[B]`/`[C]`/`[A]`/`[M]`/`[S]`/`[Q]`. The bracketed token is a distinct render node (`fg: theme.accent.fg`) from the leading label segment (`fg: theme.primary.fg`).
- **MENU-04 — Inner-indent alignment**: PASS. Every visible nav row's first cell after the panel's left `│` is U+0020. Verified at 64×22, 80×24, 132×50 via `mix foglet.tui.render` output.
- **MENU-05 — Theme-only color routing**: PASS. `grep -nE 'IO\.ANSI|\\e\[|fg:\s*:[a-z]+|fg:\s*"#[0-9a-fA-F]' lib/foglet_bbs/tui/screens/main_menu.ex` returns 0 matches.

MENU-02 (Oneliners top-border `||||` artifact) is **not in this plan's scope** and is handed to Plan 32-02 — see "Oneliners Artifact Status" below.

## Decisions Made

- **`width: 9999, height: 9999` on `:panel` attrs**: Raxol's `Panels.apply_constraints/2` clamps any explicit dimension down to `available_space`, so passing a sentinel large value forces the panel to fill its split-pane allocation. Without this, `measure_panel/2` returns `children_size + double_border` (a much smaller value), causing the panel border to be drawn at the children-measured edge and the title segment to be truncated. Documented inline as a note above `nav_panel/3`.
- **`row [], do: ...` (not `row do ... end`)**: The `Raxol.Core.Renderer.View.row/1` FUNCTION takes precedence over the `row/2` MACRO when no opts argument is supplied. The function reads `Keyword.get(opts, :children, [])` from the `[do: <block>]` opts, never finds `:children`, and silently returns a flex with `children: []`. Confirmed via direct AST inspection during Task 2 — `row/2` macro requires explicit `[]` or other opts list to be invoked. Documented inline above the macro call site.
- **No `nav_panel_inner_width/1` adjustment**: The one-column inner indent comes out of the right-align padding budget (`max(inner_width - prefix - bracketed_key, 1)`); the floor `@nav_panel_min_inner_width = 20` does not need to change. At the floor, `Moderation` (longest visible label) consumes `1 (indent) + 1 (glyph) + 1 (space) + 10 (label) + 3 ([M]) = 16` cells, leaving 4 cols of trailing padding.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking] Added `width: 9999, height: 9999` to `:panel` attrs**
- **Found during:** Task 1 (after the initial `:panel` switch landed)
- **Issue:** Without explicit width/height, `Panels.measure_panel/2` returns `children_size + double_border` (vendor/raxol/lib/raxol/ui/layout/panels.ex:171-201). The panel was drawn at children-measured size — narrow box with truncated title — instead of filling the split-pane allocation. The plan's specified shape (`%{type: :panel, attrs: %{title:, title_attrs:, border:, border_fg:}, children: [...]}` with no width/height) does not produce a full-width panel.
- **Fix:** Added `width: 9999, height: 9999` to both `nav_panel/3` and `oneliners_panel/2` attrs. `Panels.apply_constraints/2` clamps these down to `available_space`, so the panels fill their pane allocations.
- **Files modified:** `lib/foglet_bbs/tui/screens/main_menu.ex`
- **Verification:** Render at 64/80/132 shows panels filling their full allocated width; Navigation title `─ Navigation ─` is visible.
- **Committed in:** `667bedf` (Task 1 commit)

**2. [Rule 1 — Bug] Switched from `row do ... end` to `row [], do: ...`**
- **Found during:** Task 2 (initial implementation; nav rows rendered as empty space)
- **Issue:** `row do [text(...), text(...)] end` invokes the `Raxol.Core.Renderer.View.row/1` FUNCTION (vendor/raxol/lib/raxol/core/renderer/view.ex:87) — not the `row/2` macro at line 92. The function sees `opts = [do: <block>]`, calls `Keyword.get(opts, :children, [])` (no `:children` key), and returns a flex with `children: []`. The do-block contents are silently discarded.
- **Fix:** Pass explicit `[]` opts arg: `row [], do: [text_a, text_b]`. This matches the macro arity and the macro injects the do-block as `children:`.
- **Files modified:** `lib/foglet_bbs/tui/screens/main_menu.ex`
- **Verification:** Direct AST inspection of the rendered tree showed nav row flex elements transitioning from `children: []` to populated `children` list. Render output then showed nav rows correctly.
- **Committed in:** `f7af3d5` (Task 2 commit)

**3. [Rule 4 — Architectural; deferred to Plan 32-02] Oneliners title clobbered by SplitPane horizontal-divider artifact**
- **Found during:** Task 1 verification
- **Issue:** Plan 32-01 Task 1's acceptance criterion required `─ Oneliners ─` substring in render output. The Oneliners title element IS correctly emitted at `(x=34, y=1, text=" Oneliners ", fg: "#ffb000")` — verified by direct element inspection. However, `vendor/raxol/lib/raxol/ui/layout/split_pane.ex:235` paints a horizontal divider as `String.duplicate("|", space.height)` at `(x=split_x, y=row_0)` — a row of pipes painted left-to-right instead of a column painted top-to-bottom. At 80×24 the divider is `||||||||||||||||||||||` (22 chars) on row y=1, which overpaints the Oneliners title.
- **Why not auto-fixed in this plan:** This is a vendor/raxol bug (architectural — fix lives in `vendor/raxol/lib/raxol/ui/layout/split_pane.ex`, not in `main_menu.ex`). Plan 32-01's `<output>` spec line 391 explicitly hands "Status of the Oneliners `||||` artifact at widths 64/65/66/80/81 ... to Plan 32-02 for verification." The plan author anticipated the artifact persisting after the `:panel` switch.
- **Verification artifact for Plan 32-02:** At all 5 canonical widths (64/65/66/80/81), the Oneliners panel top-border row at row index 2 (inside the outer ScreenFrame) shows the pattern `┐|||...|||─...─┐` where the pipe count = `available_space.height - 2 = 20`. The pipes overpaint the Oneliners title segment and a portion of the border dashes. See "Oneliners Artifact Status" below for per-width samples.
- **Status:** Handed to Plan 32-02.

---

**Total deviations:** 3 (1 Rule 3 blocking auto-fix, 1 Rule 1 bug auto-fix, 1 Rule 4 architectural handoff)
**Impact on plan:** Auto-fixes 1 and 2 were necessary to make the plan's specified render shape actually work; both are documented inline in `main_menu.ex` for future readers. The Rule 4 handoff is anticipated by the plan's own output spec.

## Oneliners Artifact Status (Plan 32-02 input)

The `||||` top-border artifact persists after the `:panel` switch at all 5 canonical widths. Top-border rows of the Oneliners panel (row index 2 of the outer screen, after the chrome top):

| Width | Oneliners panel top-border row (excerpt around the artifact) |
|-------|--------------------------------------------------------------|
| 64×22 | `┌─ Navigation ─────────┐\|\|\|\|\|\|\|\|\|\|\|\|\|\|\|\|\|\|\|\|─────────────────┐` |
| 65×22 | `┌─ Navigation ─────────┐\|\|\|\|\|\|\|\|\|\|\|\|\|\|\|\|\|\|\|\|──────────────────┐` |
| 66×22 | `┌─ Navigation ──────────┐\|\|\|\|\|\|\|\|\|\|\|\|\|\|\|\|\|\|\|\|──────────────────┐` |
| 80×22 | `┌─ Navigation ───────────────┐\|\|\|\|\|\|\|\|\|\|\|\|\|\|\|\|\|\|\|\|───────────────────────────┐` |
| 81×22 | `┌─ Navigation ────────────────┐\|\|\|\|\|\|\|\|\|\|\|\|\|\|\|\|\|\|\|\|───────────────────────────┐` |

**Root cause** (Plan 32-02 owns the fix): `vendor/raxol/lib/raxol/ui/layout/split_pane.ex:228-247` `build_divider(:horizontal, ...)` constructs:

```elixir
%{
  type: :text,
  x: x,
  y: space.y,
  text: String.duplicate("|", space.height),
  ...
}
```

A single `:text` element with `text` = `space.height` pipe characters at a single `(x, y)` position. The `paint_text` function in `lib/foglet_bbs/tui/ascii_renderer.ex` paints text left-to-right horizontally, so the pipes are laid out across `space.height` columns starting at `(x, y=space.y)` — instead of being painted as a vertical column from `(x, space.y)` down to `(x, space.y + space.height - 1)`.

The Oneliners title element at `(x=34, y=1, text=" Oneliners ")` is overpainted by these horizontal pipes. The Navigation title at `(x=3, y=1)` is unaffected because it sits to the left of the divider's x position.

This bug pre-existed Plan 32-01 (we observed `||||||||||||||||||||||` in the pre-change render output too — see commit context for `667bedf`); the panel switch only made the Oneliners title visibility newly dependent on it.

## Issues Encountered

None beyond the auto-fixed deviations above.

## TDD Gate Compliance

Plan type is `execute` (not `tdd`); no RED/GREEN gate sequence is required. Existing `layout_smoke_test.exs:1077-1118` and `main_menu_test.exs` assertions on the prior shape will fail under the new render — those test updates are owned by Plan 32-03 per this plan's `<verification>` note.

## Next Phase Readiness

- Plan 32-02 (oneliners-artifact) inherits the divider-overpaint diagnosis above with concrete file/line pointers and per-width artifact samples.
- Plan 32-03 (test-updates) inherits a stable render shape — both panel structure and nav row layout are now load-bearing observable behaviors that tests can assert against.
- `mix precommit` was deliberately NOT run in this plan (per `<verification>` note); finish line is after Plan 32-03.

## Self-Check: PASSED

- **Created files exist:** `.planning/phases/32-main-menu-chrome-polish/32-01-render-shape-SUMMARY.md` — written by this commit.
- **Modified files exist:** `lib/foglet_bbs/tui/screens/main_menu.ex` — modified.
- **Commits exist:**
  - `667bedf` — `git log --all | grep 667bedf` finds it.
  - `f7af3d5` — `git log --all | grep f7af3d5` finds it.

---
*Phase: 32-main-menu-chrome-polish*
*Completed: 2026-04-28*
