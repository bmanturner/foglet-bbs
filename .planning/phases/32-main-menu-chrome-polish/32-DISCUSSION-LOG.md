# Phase 32: main-menu-chrome-polish - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the analysis.

**Date:** 2026-04-27
**Phase:** 32-main-menu-chrome-polish
**Mode:** assumptions
**Areas analyzed:** Border-Embedded Title Primitive, Oneliners Width-Math Fix, Bracketed Accent Key, Inner Indent, Helper Module Placement, Theme Routing, Test Updates

## Assumptions Presented

### Border-Embedded Title Primitive

| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Use Raxol's native `%{type: :panel}` element type with `title:` + `title_attrs:` (not `box do…end`, not a custom engine primitive). | Likely | `vendor/raxol/lib/raxol/ui/layout/panels.ex:36-90` — `Panels.process` produces `:box` element + positioned title `:text` overlay at `(x+2, y)`. `engine.ex:111` routes `:panel` to `Panels.process`. `box do…end` is a dead path: Engine's `:box` `process_element` (engine.ex:263-286) strips `title` during positioning. |

### Oneliners Width-Math Fix

| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Replace `split_pane(ratio: {2,3})` with explicit child widths derived from `nav_panel_inner_width/1`; fix lives in `main_menu.ex`. | Unclear | Artifact appears at widths 64, 65, 66, 80, 81 — pattern suggests fractional rounding in split_pane allocation, but no direct evidence. Hypothesis only. |

### Bracketed Accent Key — Multi-Node Nav Row

| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Replace `nav_row/3`'s single `text(...)` node with `row` layout containing two `text` nodes (primary leading + accent `[X]`). | Likely | SPEC MENU-03 requires distinct render nodes. Current `nav_row/3` (`main_menu.ex:304-311`) emits one node. `row do…end` Raxol primitive is in scope via existing `import Raxol.Core.Renderer.View`. |
| Only single-char destination keys (B/C/A/M/S/Q) get `[X]` form; `↑/↓` stays in command bar. | Confident | `@main_menu_commands` (`main_menu.ex:63-73`) tags `↑/↓` as `:action`; nav rows iterate destination entries only (`nav_panel/3` line 293). |

### Inner Indent

| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Prepend `" "` to row prefix; reduce right-align budget by 1. Do not use box `padding: 1`. | Confident | SPEC MENU-04 acceptance specifies `U+0020` after `│`. `padding: 1` would also pad title row vertically. Inner-width budget at floor 20 holds for longest label `Moderation` (10 cols). |

### Helper Module Placement

| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| All work inline in `main_menu.ex`; no new widget module. | Confident | SPEC out-of-scope explicit: "Generalizing border-embedded titles into a reusable widget abstraction available to other screens — out of scope". |

### Theme Routing

| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| `fg: theme.accent.fg` only; skip `style: theme.accent.style`. | Confident | SPEC MENU-03 specifies color, not bold. MENU-05 grep clean. `theme.accent.fg` exists in all seeded themes (`theme.ex:106,122,138,154,170,186,202,218`). |

### Test Updates

| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Update `layout_smoke_test.exs:1077-1118` and `screens/main_menu_test.exs` to match new shape. | Confident | Existing assertions (`text == "Navigation"`, `~r/●.*Boards.*B$/`) will fail under new render; `mix precommit` would red-flag the diff. SPEC out-of-scope rule is "no new tests", not "delete existing tests". |

## Corrections Made

### Oneliners Width-Math Fix

- **Original assumption:** Replace `split_pane(ratio: {2,3})` with explicit child widths derived from `nav_panel_inner_width/1`; fix lives in `main_menu.ex`. (Pre-committed to a `split_pane` root cause.)
- **User correction:** Verify-first via `mix foglet.tui.render`. Switch to `:panel` first (D-01) and re-render at widths 64/65/66/80/81 to see whether the artifact resolves organically. No evidence `split_pane` is the culprit — do not pre-judge fix location.
- **Reason:** Artifact may be caused by the current `box do…end` + first-body-row title node interaction that the `:panel` switch eliminates anyway. Investigating root cause before locking the fix prevents over-engineering. Recorded as D-03/D-04/D-05 in CONTEXT.md.

## Auto-Resolved

Not applicable — interactive mode.

## External Research

Not performed — codebase evidence was sufficient (vendor/raxol primitive contracts, existing screen frame precedent, theme slot definitions, existing test shapes).
