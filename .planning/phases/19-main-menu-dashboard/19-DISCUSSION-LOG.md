# Phase 19: main-menu-dashboard - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the analysis.

**Date:** 2026-04-25
**Phase:** 19-main-menu-dashboard
**Mode:** assumptions
**Areas analyzed:** Dedup architecture, Body destinations vs. command bar actions, Body row presentation, Side-by-side layout, Test coverage shape

## Assumptions Presented

### A. Dedup Architecture

| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Build canonical "visible destinations" list inside `MainMenu`; derive both body rows and CommandBar input from it; subtract destination keys from CommandBar before building groups. `CommandBar` and `Normalizer` remain passive widgets. | Confident | `lib/foglet_bbs/tui/screens/main_menu.ex:168-192` (parallel `visible_menu_items/1` and `visible_menu_keys/1`); `lib/foglet_bbs/tui/widgets/chrome/command_bar.ex:56-77` (`normalize_groups/1` is passive); Phase 18 D-01/D-02; `lib/foglet_bbs/tui/screens/board_list.ex:23-35` and `lib/foglet_bbs/tui/screens/account.ex:42-72` (sibling Chrome V2 callers do not push filtering into the widget). |

### A2. Command Bar Contents After Dedup

| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| After filtering destination keys, only `H` "Hide oneliner" remains as a non-destination action; the bar may render empty for normal users / when no hideable oneliner is focused. Don't invent generic affordances. | Likely | `lib/foglet_bbs/tui/screens/main_menu.ex:177-192` (every key except `H` is a destination); `main_menu.ex:262-274` (`hideable_oneliner?/2` is gated by `Bodyguard.permit?(:hide_oneliner, ...)`); `lib/foglet_bbs/tui/widgets/chrome/command_bar.ex:59` (`Enum.reject(&(&1.commands == []))` handles empty groups); `.planning/phases/19-main-menu-dashboard/19-SPEC.md:29-32`. |

### B. Body Row Presentation

| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Keep the existing `  [K] Label` plain-text rows. No richer dashboard primitive, no theme-routed key glyph, no role/scope hint, no multi-column layout. Phase 19 delta is verifying role-gated visibility + dedup, not redesigning rows. | Likely | `.planning/phases/19-main-menu-dashboard/19-SPEC.md:21-22` (acceptance is "shows the expected available destination keys"); `.planning/phases/19-main-menu-dashboard/19-SPEC.md:58-60` (boundaries: no facelift to other screens, only adjusts Main Menu body and command-bar inputs); `test/foglet_bbs/tui/screens/main_menu_test.exs:233-237, 375` (existing tests lock the `[K] Label` strings); `test/foglet_bbs/tui/layout_smoke_test.exs:264-268` (Login uses the same shape — project-wide convention). |

### C. Side-by-Side Layout & 64x22 Fit

| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Keep existing `split_pane(direction: :horizontal, ratio: {2, 3}, min_size: 24)`; prove the 64x22 / 80x24 / wider contract via positioned-render tests using `Raxol.UI.Layout.Engine.apply_layout/2` at `[{64,22}, {80,24}, {132,50}]`. No new compact-mode threshold, no manual `TextWidth` column math, no `split_pane` replacement. | Likely | `lib/foglet_bbs/tui/screens/main_menu.ex:70` (only horizontal `split_pane` callsite in `lib/foglet_bbs/tui`); `.planning/phases/18-chrome-v2/18-CONTEXT.md` D-11/D-13; `test/foglet_bbs/tui/layout_smoke_test.exs:119-183, 318-378` (Phase 18 size-contract triple, existing Main Menu render check); `lib/foglet_bbs/tui/screens/main_menu.ex:318-320` (oneliner clipping already uses `TextWidth.slice_to_width/2`); SPEC interview round 4 (line 105) "Nothing special is intentionally reduced; verification must prove it." |

### D. Test Coverage Shape

| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Extend `test/foglet_bbs/tui/screens/main_menu_test.exs` for behavior coverage and extend `test/foglet_bbs/tui/layout_smoke_test.exs` with a Main Menu 3-size positioned-render block. No new `main_menu_layout_test.exs`. | Confident | `test/foglet_bbs/tui/screens/main_menu_test.exs:72-228, 285-396` (already owns role visibility and oneliner cases); `test/foglet_bbs/tui/layout_smoke_test.exs:318-378` (already has Main Menu render check); `test/foglet_bbs/tui/layout_smoke_test.exs:119-183` (Phase 18 placed size contracts in `layout_smoke_test.exs`). |

## Corrections Made

### A2. Command Bar Contents After Dedup
- **Original assumption:** Only `H` remains in the command bar; bar may render empty for normal users; don't invent affordances.
- **User correction:** "The destination list is for destinations, not actions. So O for add oneliner should be in the command bar, not destination list. Also, H is for mods and sysops only, so make sure that's enforced."
- **Resulting decision (CONTEXT.md D-03/D-04/D-05):** Body shows destinations only (`B/C/A/M/S/Q`). Command bar shows actions: `O` Post Oneliner (always for authenticated users), `H` Hide oneliner (mod/sysop with hideable focus, gated through `Bodyguard.permit?(:hide_oneliner, ...)`), and `↑/↓ Select` (when `recent_oneliners` is non-empty).
- **Reason:** Body is canonically "destinations" (screen transitions and session controls), not all hotkeys. `O` opens the oneliner composer modal — that is an action, not a screen transition. `H` was already correctly enforced via `Bodyguard.permit?` at `lib/foglet_bbs/authorization.ex:58` and `main_menu.ex:271`; the user wants role visibility tests to lock that contract.

### B. Body Row Presentation
- **Original assumption:** Keep the existing `  [K] Label` plain-text rows; no richer presentation.
- **User correction:** "Reference SCREENS.md for what the Main Menu should look like."
- **Resulting decision (CONTEXT.md D-07/D-08/D-09/D-10):** Adopt SCREENS.md visual: boxed `┌ Navigation ┐` panel with rows shaped as `glyph + label + right-aligned key`. Recommended glyphs from `SCREENS.md` §Main Menu lines 270-280: `●` Boards, `✎` Compose, `◇` Account, `⚑` Moderation, `▣` Sysop, `↯` Logout. Glyphs route through theme slots. ASCII fallback if positioned-render tests show width breakage. Adopt visual shape only — NOT SCREENS.md's selection-list / Up-Down / Enter-to-open destination behavior, since SPEC requirement 2 explicitly rejects a destination cursor.
- **Reason:** SCREENS.md is the milestone PRD for v1.3 visual direction. The original "keep plain rows" assumption underweighted the user's intent for the Classic Modern BBS facelift on Home.

### C. Side-by-Side Layout & 64x22 Fit
- **Original assumption:** Keep current layout; just add a 3-size positioned-render test block.
- **User correction:** "SCREENS.md should show you what we're aiming for (minus the activity box)."
- **Resulting decision (CONTEXT.md D-07 / D-12 / D-13):** Adopt SCREENS.md side-by-side layout MINUS the Activity panel. Final body has two boxed panels side-by-side: `┌ Navigation ┐` (left) and `┌ Oneliners ┐` (right). `split_pane` continues but planner may tune ratio/min_size so both boxed panels fit at 64x22. 3-size positioned-render block at `[{64,22}, {80,24}, {132,50}]` per Phase 18 precedent. No Activity panel and no new dashboard data queries.
- **Reason:** "Minus the activity box" is consistent with SPEC out-of-scope on new dashboard data queries. The user explicitly directed me to SCREENS.md as the visual target.

## Clarifications Captured

### Q (Logout) placement
- **Question:** Should Q (Logout) live in the body Navigation panel (matching SCREENS.md sketch) or in the command bar as an action?
- **User choice:** Body Navigation panel — match the SCREENS.md sketch.
- **Rationale captured in D-03 / Specific Ideas:** Treat the Navigation panel as "every top-level keystroke a Home user can issue to leave Home", not strictly "screen transitions only". Q is a session-control row alongside destination rows.

### `↑/↓ Select` oneliner hint
- **Question:** When oneliners exist, should the command bar surface an `↑/↓ Select` affordance?
- **User choice:** Yes, show it conditionally — visible when `recent_oneliners` is non-empty; hidden otherwise.
- **Rationale captured in D-04:** Surfaces the existing oneliner row-selection behavior so it is discoverable, without polluting the empty-state.

## Auto-Resolved

Not applicable — assumptions mode without `--auto`.

## External Research

None. Phase 19 is a tightening of an existing screen with already-shipped Chrome V2 (Phase 18), `TextWidth` (Phase 16), theme slots (Phase 17), `ShellVisibility` predicates, and the `Raxol.UI.Layout.Engine.apply_layout/2` size-contract harness. SCREENS.md is the only product-direction reference and lives in-repo. The codebase contains every contract Phase 19 needs.
