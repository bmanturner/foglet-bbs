# Phase 17: Theme and Mode Metadata - Specification

**Created:** 2026-04-25
**Ambiguity score:** 0.11 (gate: <= 0.20)
**Requirements:** 5 locked

## Goal

Foglet TUI screens declare either Classic Modern BBS or Operator Console presentation mode, and shared theme slots expose the semantic states needed by later facelift widgets without changing visible screen layouts in this phase.

## Background

The current TUI already routes most rendering through `Foglet.TUI.Theme.from_state/1`, and the widget catalog requires explicit theme passing and no hardcoded color atoms. `Foglet.TUI.Theme` currently exposes core slots such as `border`, `primary`, `dim`, `accent`, `title`, `error`, `warning`, `selected`, `unselected`, and `status_bar`. `SCREENS.md` defines two related visual modes, Classic Modern BBS and Operator Console, and calls out future semantic slots such as `success`, `info`, and `badge`.

What does not exist today is a screen-level presentation-mode contract, explicit mode declarations for the named screens, or concrete `success`, `info`, and `badge` slots across all theme palettes. Later facelift phases need those contracts before Chrome V2, rich rows, board/post/composer surfaces, and operator console primitives consume them.

## Requirements

1. **Mode contract**: The TUI exposes a shared presentation-mode contract with exactly two supported modes: `:bbs` and `:operator`.
   - Current: Screens render from `current_screen` and `screen_state`, but no shared contract identifies BBS-flow versus operator-console rhythm.
   - Target: Code can resolve a supported presentation mode for each named TUI screen through a single documented contract.
   - Acceptance: Tests prove only supported modes are returned for the named screens and unsupported screen ids are handled deliberately.

2. **Screen declarations**: The named screens declare their intended presentation mode.
   - Current: Login, MainMenu, BoardList, ThreadList, PostReader, NewThread, PostComposer, Account, Moderation, and Sysop do not expose explicit mode metadata.
   - Target: Login, MainMenu, BoardList, ThreadList, PostReader, NewThread, and PostComposer declare `:bbs`; Account, Moderation, and Sysop declare `:operator`.
   - Acceptance: A test enumerates the named screens and verifies the exact screen-to-mode mapping.

3. **Semantic theme slots**: `Foglet.TUI.Theme` includes concrete `success`, `info`, and `badge` slots across every registered palette and resolved theme snapshot.
   - Current: `SCREENS.md` identifies these semantic slots as needed, but `Foglet.TUI.Theme` does not define them in the struct, slot list, or palette maps.
   - Target: Every palette supplies `success`, `info`, and `badge`, and `Theme.resolve/1`, `Theme.default/0`, and `Theme.from_state/1` return snapshots containing those slots.
   - Acceptance: Theme tests verify all theme ids resolve with non-empty `success`, `info`, and `badge` maps.

4. **Theme-slot mappings**: Tabs, rows, badges, command hints, and editor states have documented and tested mappings to theme slots.
   - Current: `SCREENS.md` describes desired mappings, while existing widget tests cover only some concrete widgets and older slots.
   - Target: A project-local contract documents which theme slot each listed UI state must use, including selected/unselected tabs, row states, badge states, command groups/keys/destructive labels, and composer/editor focus and counter states.
   - Acceptance: Tests or documentation checks verify the mapping contract includes tabs, rows, badges, command hints, and editor states and references only slots present on `Foglet.TUI.Theme`.

5. **Theme changes do not affect mode**: User-selected theme controls color treatment only and does not change a screen's presentation mode or layout category.
   - Current: User theme snapshots are stored in session context and can be previewed or persisted from Account, but no test asserts independence between theme and screen mode.
   - Target: Presentation mode is derived from screen identity or screen metadata, not from the active theme id or theme snapshot.
   - Acceptance: Tests verify at least two different active themes resolve the same mode for representative BBS and operator screens.

## Boundaries

**In scope:**
- Shared presentation-mode contract for `:bbs` and `:operator`.
- Explicit mode declarations or equivalent single-source mapping for Login, MainMenu, BoardList, ThreadList, PostReader, NewThread, PostComposer, Account, Moderation, and Sysop.
- Concrete `success`, `info`, and `badge` slots on `Foglet.TUI.Theme`.
- Palette updates for every existing theme id.
- Documentation and tests for theme-slot mappings used by tabs, rows, badges, command hints, and editor states.
- Tests proving mode resolution is independent from active user theme.

**Out of scope:**
- Chrome V2 breadcrumb, status, or command-bar rendering - that is Phase 18.
- New `Display.Badge`, `List.RichRow`, `Composer.EditorFrame`, table presets, inspectors, or modal visual redesign - those belong to later widget/screen phases.
- Visible screen layout conversion for MainMenu, BoardList, ThreadList, PostReader, NewThread, PostComposer, Account, Moderation, or Sysop - Phase 17 only locks metadata and theme contracts.
- Browser workflows or Phoenix end-user UI - Foglet remains SSH-first/TUI-first.
- Additional theme palette tuning beyond making the new semantic slots available - contrast tuning can follow real SSH screenshots in later phases.

## Constraints

- Phase 17 depends on Phase 16's width foundation and must not introduce new glyph-heavy aligned layouts before width-safe rendering is available.
- The mode contract must not fork the widget stack; both modes consume shared primitives and shared theme slots.
- New or updated TUI rendering code must route styles through `Foglet.TUI.Theme` slots and must not introduce hardcoded color atoms.
- Existing user theme selection and preview behavior must continue to change colors without changing screen mode or navigation behavior.
- No end-user browser workflow is introduced.

## Acceptance Criteria

- [ ] `:bbs` and `:operator` are the only supported presentation modes in the Phase 17 contract.
- [ ] Login, MainMenu, BoardList, ThreadList, PostReader, NewThread, and PostComposer resolve to `:bbs`.
- [ ] Account, Moderation, and Sysop resolve to `:operator`.
- [ ] Every existing theme id resolves with non-empty `success`, `info`, and `badge` slots.
- [ ] Tabs, rows, badges, command hints, and editor states have documented mappings that reference existing `Foglet.TUI.Theme` slots.
- [ ] Tests prove active theme changes do not change screen mode for at least one BBS screen and one operator screen.
- [ ] Phase 17 does not add Chrome V2, rich-row, badge-widget, command-bar, editor-frame, or screen-layout conversion behavior.

## Ambiguity Report

| Dimension          | Score | Min   | Status | Notes |
|--------------------|-------|-------|--------|-------|
| Goal Clarity       | 0.93  | 0.75  | met    | Primary deliverable is the combined mode and theme foundation. |
| Boundary Clarity   | 0.92  | 0.70  | met    | Visible redesign and new widget primitives are explicitly excluded. |
| Constraint Clarity | 0.84  | 0.65  | met    | Theme independence, no widget-stack fork, and SSH-first constraints are locked. |
| Acceptance Criteria| 0.86  | 0.70  | met    | Pass/fail checks cover modes, slots, mappings, and non-goals. |
| **Ambiguity**      | 0.11  | <=0.20| met    | Gate passed after round 2. |

Status: met = met minimum, below = planner treats as assumption

## Interview Log

| Round | Perspective | Question summary | Decision locked |
|-------|-------------|------------------|-----------------|
| 1 | Researcher | Primary deliverable | Phase 17 delivers both screen mode declarations and semantic theme slots as one foundation. |
| 1 | Researcher | Screen mode scope | The named BBS-flow and operator screens must all have explicit mode declarations. |
| 1 | Researcher | Theme slot scope | Add concrete `success`, `info`, and `badge` slots now. |
| 2 | Researcher + Simplifier | Minimum successful version | Contract, tests, and documentation are enough; no visible redesign is required. |
| 2 | Boundary Keeper | Out-of-scope adjacent work | Chrome V2, new facelift widgets, command bars, editor frames, and screen conversions are deferred. |
| 2 | Failure Analyst | Verifier rejection condition | Missing mode declarations, missing new slots, or undocumented/untested mappings reject the phase. |

---

*Phase: 17-theme-and-mode-metadata*
*Spec created: 2026-04-25*
*Next step: $gsd-discuss-phase 17 - implementation decisions (how to build what's specified above)*
