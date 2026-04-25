# Phase 18: Chrome V2 - Specification

**Created:** 2026-04-25
**Ambiguity score:** 0.14 (gate: <= 0.20)
**Requirements:** 7 locked

## Goal

Every named TUI screen renders through shared Chrome V2 primitives that communicate breadcrumb location, mode-aware status, and grouped key commands without changing screen behavior.

## Background

The current TUI chrome lives in `Foglet.TUI.Widgets.Chrome.ScreenFrame`, `StatusBar`, and `KeyBar`. `ScreenFrame.render/4` wraps each screen in a single bordered box, renders a simple `Foglet BBS - {title}` status bar, then renders a centered flat key list from `{key, description}` tuples. Screens such as Login, MainMenu, BoardList, ThreadList, PostReader, NewThread, PostComposer, Account, Moderation, and Sysop pass plain title strings and flat key lists directly.

`SCREENS.md` defines the Chrome V2 target: breadcrumb-style locations such as `Foglet ▸ Boards ▸ general`, mode-specific right-side status atoms, and a grouped command bar inside the frame above the bottom border. Phase 17 locks the presentation-mode and theme-slot foundation, so Phase 18 can consume those contracts without forking the widget stack. What does not exist yet is a Chrome V2 breadcrumb/status/command primitive set, a grouped command data contract, responsive truncation behavior, or migration of current screen chrome callers away from the old flat footer implementation.

## Requirements

1. **Breadcrumb chrome**: Chrome V2 renders breadcrumb-style locations for all named TUI screens.
   - Current: `StatusBar` renders `Foglet BBS - {title}` from a plain title string.
   - Target: The chrome can render structured breadcrumb paths for Login, MainMenu, BoardList, ThreadList, PostReader, NewThread, PostComposer, Account, Moderation, and Sysop using screen-appropriate nouns such as `Foglet ▸ Boards ▸ general` and `Foglet ▸ Sysop ▸ Users`.
   - Acceptance: Tests verify each named screen or screen state resolves to a non-empty breadcrumb path rooted at `Foglet`.

2. **Mode-aware status**: Chrome V2 renders right-side status atoms based on the Phase 17 presentation mode.
   - Current: `StatusBar` renders only guest or `@handle | clock`.
   - Target: BBS-mode chrome can show handle, time, and unread/activity atoms when available; operator-mode chrome can show handle, scope, time, and system/status atoms when available.
   - Acceptance: Tests verify representative BBS and operator states produce different status atom sets, and missing optional data is omitted rather than rendered as fake or placeholder status.

3. **Grouped command bar**: `Chrome.CommandBar` renders grouped commands inside the frame and truncates lower-priority hints first.
   - Current: `Chrome.KeyBar` renders a centered flat list of key hints with no grouping or priority model.
   - Target: Commands are grouped by purpose, such as Navigate, Actions, System, Tabs, Field, Save, or Refresh, and each hint has enough priority metadata for width-based truncation.
   - Acceptance: Unit tests prove group labels and key hints render in priority order at roomy widths and drop lower-priority hints first under constrained widths.

4. **ScreenFrame integration**: `Chrome.ScreenFrame` composes the breadcrumb/status area, content, separator, grouped command bar, and bottom border as one shared frame.
   - Current: `ScreenFrame` composes `StatusBar`, a divider, content, and `KeyBar`.
   - Target: `ScreenFrame` uses the Chrome V2 primitives for the top bar and command bar while preserving the caller-supplied content element and existing screen behavior.
   - Acceptance: Render tests verify the command bar is inside the frame above the bottom border, content remains between top chrome and command chrome, and no screen-level renderer keeps a separate footer implementation.

5. **Caller migration**: Current screen chrome callers are migrated deliberately to the Chrome V2 command contract without keeping a parallel legacy footer.
   - Current: Screens pass flat `{key, description}` lists to `ScreenFrame.render/4`.
   - Target: Named screens either pass grouped command data directly or go through a short compatibility normalizer that feeds `Chrome.CommandBar`; the old simple key-list path does not continue as an independent `KeyBar` footer.
   - Acceptance: Static or unit tests verify named screen render paths route commands through `Chrome.CommandBar` and no production screen renders `Chrome.KeyBar` as a separate footer.

6. **Responsive chrome contract**: Chrome V2 remains usable at 64x22, reaches compact intended treatment around 80x24, and progressively shows more detail on wider terminals.
   - Current: Chrome has no explicit responsive contract for 64x22, 80x24, or wide layouts.
   - Target: At 64x22, chrome avoids text overlap and preserves core location plus essential commands; around 80x24, compact breadcrumbs and key groups are visible; at a wide size, additional status atoms or command details can appear.
   - Acceptance: Size-contract tests cover 64x22, 80x24, and at least one wide terminal size and assert chrome text does not overlap content or displace screen bodies incoherently.

7. **Login chrome only**: Login declares and consumes Classic Modern BBS chrome without authentication behavior changes.
   - Current: Login renders through the old `ScreenFrame` and owns login, register, reset, and quit behavior.
   - Target: Login receives Chrome V2 with BBS-mode breadcrumb/status/commands while preserving existing menu visibility, login form, reset request, registration, and quit behavior.
   - Acceptance: Existing login behavior tests continue to pass, and additional render tests verify Login uses BBS-mode Chrome V2 without changing auth flow state transitions.

## Boundaries

**In scope:**
- Chrome V2 primitives for breadcrumb/status rendering and grouped command rendering.
- `ScreenFrame` integration of Chrome V2 top chrome and command chrome.
- Migration of Login, MainMenu, BoardList, ThreadList, PostReader, NewThread, PostComposer, Account, Moderation, and Sysop chrome callers.
- Mode-aware status atoms using the Phase 17 `:bbs` and `:operator` contract.
- Width-aware truncation and size-contract tests for 64x22, 80x24, and one wide terminal size.
- Login receiving Chrome V2 while keeping the existing authentication behavior and form flow.

**Out of scope:**
- Main Menu dashboard redesign - Phase 19 owns selectable/social home-screen conversion.
- Rich thread rows or reusable rich-row primitive - Phase 20 owns row semantics and thread-flow facelift.
- Board directory row/tree facelift - Phase 21 owns category/board row conversion.
- Post reader card/progress facelift - Phase 22 owns message-oriented reader treatment.
- Composer editor-frame facelift - Phase 23 owns editor surface, preview tabs, and counters.
- Operator console badges, key/value grids, tables, inspectors, and modal refresh - Phases 24 and 25 own dense operator surface conversion.
- End-user browser workflows - Foglet remains SSH-first/TUI-first.
- Full ASCII fallback as the default rendering mode - Unicode is the primary Chrome V2 path; fallback work is limited to deliberate handling where required by existing runtime constraints.

## Constraints

- Chrome V2 must consume Phase 17 mode metadata and theme slots instead of deriving mode from active theme or duplicating mode logic in screens.
- New rendering code must route styles through `Foglet.TUI.Theme` and avoid hardcoded color atoms.
- Unicode glyph use must rely on the Phase 16 width foundation for measurement, truncation, and padding.
- Optional status data must be honest: absent unread, scope, terminal-size, connection, or system data is omitted rather than fabricated.
- Screen behavior, key handling, domain mutations, authentication flow, and navigation semantics must remain unchanged unless explicitly required for chrome rendering.

## Acceptance Criteria

- [ ] Each named TUI screen renders a breadcrumb path rooted at `Foglet`.
- [ ] BBS-mode chrome can render handle/time/unread or activity atoms when available.
- [ ] Operator-mode chrome can render handle/scope/time or system status atoms when available.
- [ ] `Chrome.CommandBar` renders grouped commands and truncates lower-priority hints before higher-priority hints.
- [ ] Current screen chrome callers route commands through `Chrome.CommandBar` and do not keep an independent `Chrome.KeyBar` footer.
- [ ] Chrome V2 render or contract tests cover 64x22, 80x24, and at least one wide terminal size without text overlap or incoherent content displacement.
- [ ] Login receives BBS-mode Chrome V2 while existing login, registration, reset-request, and quit behavior tests still pass.
- [ ] Phase 18 does not implement later screen facelift work for dashboards, rich rows, board rows, post cards, composer editor frames, or operator console primitives.

## Ambiguity Report

| Dimension           | Score | Min   | Status | Notes |
|---------------------|-------|-------|--------|-------|
| Goal Clarity        | 0.91  | 0.75  | met    | Primary deliverable is shared Chrome V2 across named screens. |
| Boundary Clarity    | 0.86  | 0.70  | met    | Later facelift phases and auth-flow changes are explicitly excluded. |
| Constraint Clarity  | 0.82  | 0.65  | met    | Mode/theme/width foundations, honest status data, and behavior preservation are locked. |
| Acceptance Criteria | 0.86  | 0.70  | met    | Pass/fail checks cover breadcrumbs, status, command grouping, migration, responsive sizes, and Login behavior. |
| **Ambiguity**       | 0.14  | <=0.20| met    | Gate passed after round 2. |

Status: met = met minimum, below = planner treats as assumption

## Interview Log

| Round | Perspective | Question summary | Decision locked |
|-------|-------------|------------------|-----------------|
| 1 | Researcher | Required deliverable shape | Build shared breadcrumb/status/command primitives plus adapt `ScreenFrame` so current screens can consume them. |
| 1 | Researcher | Minimum right-side status atoms | BBS chrome shows handle/time/unread when available; operator chrome shows handle/scope/time or system status when available. |
| 1 | Researcher | Login scope | Login receives Chrome V2 only; authentication, registration, reset, and quit behavior stay unchanged. |
| 2 | Researcher + Simplifier | Existing simple key-list path | Screen callers should be migrated deliberately to the grouped command contract, with no long-lived parallel footer. |
| 2 | Boundary Keeper | Responsive acceptance scope | Tests must cover 64x22, 80x24, and at least one wide terminal size. |
| 2 | Boundary Keeper | ASCII fallback strictness | Unicode is the primary Chrome V2 path; fallback work is deliberate and limited rather than defaulting to ASCII. |

---

*Phase: 18-chrome-v2*
*Spec created: 2026-04-25*
*Next step: $gsd-discuss-phase 18 - implementation decisions (how to build what's specified above)*
