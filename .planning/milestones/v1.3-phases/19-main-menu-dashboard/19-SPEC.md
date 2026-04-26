# Phase 19: Main Menu Dashboard - Specification

**Created:** 2026-04-25
**Ambiguity score:** 0.19 (gate: <= 0.20)
**Requirements:** 5 locked

## Goal

The main menu becomes a side-by-side, social BBS home screen with visible direct destination keys, useful oneliner context, and a non-duplicative Chrome command bar while preserving existing navigation behavior.

## Background

`Foglet.TUI.Screens.MainMenu` currently renders through Chrome V2 as `Foglet > Home` with a left welcome/hotkey list and a right recent-oneliners strip. Direct hotkeys already open destinations: `B` opens boards, `C` starts the composer flow, `A` opens Account when visible, `M` opens Moderation for moderators/sysops, `S` opens Sysop for sysops, `O` opens the oneliner composer for authenticated users, and `Q` logs out. Role-gated destinations are absent when unavailable. Up/Down currently select only recent oneliners for hide-oneliner actions; there is no destination cursor and no Enter-to-open destination behavior.

Phase 18 already migrated Main Menu into Chrome V2, so this phase is not a chrome rewrite. Phase 19 tightens the main-menu body into the intended front porch: direct keys are visible in the navigation panel, the command bar does not repeat those destination keys, recent oneliners remain the required social activity source, and the side-by-side dashboard remains usable at the 64x22 minimum.

## Requirements

1. **Visible direct destination keys**: Main Menu navigation rows show each available destination with its direct selection key, and those direct hotkeys continue to perform their existing actions.
   - Current: The menu shows simple rows such as `[B] Browse Boards`, and direct hotkeys already route to boards, composer, account, moderation, sysop, oneliner composer, or logout.
   - Target: The main menu presents destination rows as the primary navigation surface with visible direct keys for every available destination.
   - Acceptance: Rendering the main menu for user, moderator, and sysop roles shows the expected available destination keys in the body, and pressing each visible key triggers the same screen transition or command as before.

2. **No destination cursor requirement**: Phase 19 does not add a destination `selected_index`, destination cursor, or Enter-to-open behavior for main-menu destinations.
   - Current: `MainMenu` is stateless for destinations; Enter returns `:no_match`; Up/Down are reserved for selected oneliners.
   - Target: Destination selection remains direct-key based; any existing oneliner row selection behavior is preserved, but destination rows are not opened by cursor selection.
   - Acceptance: Tests confirm Enter does not open a destination from the main menu and no `screen_state[:main_menu]` destination selection state is required by the screen.

3. **Non-duplicative CommandBar**: Main Menu's Chrome command bar omits destination hotkeys that are already visible in the navigation body.
   - Current: `visible_menu_keys/1` includes destination commands such as Boards, Compose, Account, Moderation, Sysop, Oneliner, and Logout, duplicating the body menu.
   - Target: The command bar shows only generic controls or actions that are not already visible as destination rows in the body.
   - Acceptance: Rendering Main Menu shows destination keys in the body and does not repeat those same destination labels as command-bar commands.

4. **Required oneliner context**: Recent oneliners remain the required activity/social context for the home dashboard, including the empty state.
   - Current: Main Menu reads `state.recent_oneliners`, renders up to five oneliner rows, supports a no-oneliners empty state, and uses width-aware clipping.
   - Target: The dashboard continues to render recent oneliners side-by-side with navigation, including no-oneliner and long-text cases.
   - Acceptance: Tests cover nil/empty oneliners, one oneliner, more than the display limit, and long Unicode-safe clipping without multiline overflow.

5. **Side-by-side responsive layout**: The dashboard keeps navigation and oneliner panels side-by-side at 64x22, 80x24, and wider terminal sizes without text overlap.
   - Current: Main Menu uses a horizontal split pane with plain menu and oneliner columns; prior width work made oneliner clipping display-width aware.
   - Target: Navigation and oneliner panels remain side-by-side at the 64x22 minimum and 80x24 compact target, with richer spacing or detail allowed only when it still fits.
   - Acceptance: Layout smoke or focused render tests verify 64x22, 80x24, and at least one wide terminal render without overlapping text or exceeding the intended viewport bounds.

## Boundaries

**In scope:**
- Main Menu body layout for the authenticated home screen.
- Visible direct destination rows and their existing hotkey behavior.
- Preservation of existing role-gated destination absence.
- CommandBar contents for Main Menu only, specifically avoiding duplicated destination hotkeys already visible in the body.
- Recent oneliners as the required activity/social panel, including empty and long-row states.
- Size-contract coverage for 64x22, 80x24, and one wider side-by-side layout.

**Out of scope:**
- Destination cursor, destination `selected_index`, or Enter-to-open destination behavior - the user explicitly rejected cursor-based destination navigation for this phase.
- New board, unread, session, or moderation dashboard data queries - Phase 19 renders existing app-state oneliners and existing destination availability only.
- New moderation queue or system metric panels - the main menu must stay a social BBS front porch, not an operator dashboard.
- Account, Moderation, Sysop, Board Directory, Thread List, Post Reader, or Composer screen facelifts - those are covered by later roadmap phases.
- End-user browser UI - Foglet remains SSH-first/TUI-first for this milestone.
- Chrome V2 frame rewrites - Phase 18 owns the shared chrome shell and this phase only adjusts the Main Menu body and its command-bar inputs.

## Constraints

- Foglet remains SSH-first/TUI-first; no browser workflow is introduced.
- Main Menu must continue to use `ScreenFrame.render/4` and theme-routed TUI primitives.
- Role-gated destinations remain absent rather than disabled.
- Destination hotkeys remain the authoritative selection mechanism.
- Navigation and oneliners must remain side-by-side even at 64x22.
- New dashboard data queries are not allowed in this phase.
- Any text clipping must use existing display-width helpers rather than byte length or grapheme count assumptions.

## Acceptance Criteria

- [ ] User, moderator, and sysop renders show only the destination keys available to that role in the Main Menu body.
- [ ] Existing direct hotkeys `B`, `C`, `A`, `M`, `S`, `O`, and `Q` keep their current behavior whenever their destination is visible.
- [ ] Unavailable role-gated destinations remain absent from both the body navigation and actionable key handling.
- [ ] Main Menu does not require destination cursor state and Enter does not open a destination.
- [ ] The Main Menu command bar does not duplicate destination hotkeys already visible in the body navigation.
- [ ] Recent oneliners render nil/empty, one-row, many-row, and long-row cases without multiline overflow.
- [ ] The side-by-side navigation/oneliner layout renders within 64x22, 80x24, and one wider terminal size without overlap.
- [ ] No new board, unread, session, or moderation count query is added for the dashboard.

## Ambiguity Report

| Dimension          | Score | Min   | Status | Notes |
|--------------------|-------|-------|--------|-------|
| Goal Clarity       | 0.82  | 0.75  | met    | Main Menu becomes a side-by-side direct-key dashboard, not cursor navigation. |
| Boundary Clarity   | 0.90  | 0.70  | met    | Destination cursor, new data queries, and operator metrics are explicitly out of scope. |
| Constraint Clarity | 0.78  | 0.65  | met    | Side-by-side at 64x22 and no new dashboard queries are locked constraints. |
| Acceptance Criteria| 0.76  | 0.70  | met    | Pass/fail checks cover role visibility, key behavior, command bar duplication, oneliners, and size contracts. |
| **Ambiguity**      | 0.19  | <=0.20| met    | Gate passed. |

Status: met = meets minimum, below = planner treats as assumption

## Interview Log

| Round | Perspective | Question summary | Decision locked |
|-------|-------------|------------------|-----------------|
| 1 | Researcher | What is the required user-visible delta from today's main menu? | Destination rows remain the primary visible navigation surface and direct hotkeys continue to work. |
| 1 | Researcher | Which activity context is mandatory? | Oneliners are mandatory; other counts are not required. |
| 1 | Researcher | Should CommandBar duplicate visible nav keys? | No. Keys already visible in the navigation body should not be repeated in the CommandBar. |
| 2 | Simplifier | Should selection controls add Enter-to-open destination behavior? | No destination cursor; direct keys such as `B` and `C` remain the way users select destinations. |
| 2 | Simplifier | Which layout shape should be locked? | Main Menu should remain side-by-side rather than stacked. |
| 3 | Boundary Keeper | Should new dashboard data queries be included? | No new data queries; use existing oneliner state and destination availability only. |
| 4 | Failure Analyst | What may be reduced at 64x22 to avoid overlap? | Nothing special is intentionally reduced; the side-by-side layout is expected to fit. Verification must prove it. |

---

*Phase: 19-main-menu-dashboard*
*Spec created: 2026-04-25*
*Next step: $gsd-discuss-phase 19 - implementation decisions (how to build what's specified above)*
