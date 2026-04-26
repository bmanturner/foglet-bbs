# Phase 24: Operator Console Primitives - Specification

**Created:** 2026-04-25
**Ambiguity score:** 0.11 (gate: <= 0.20)
**Requirements:** 8 locked

## Goal

Operator Console shared primitives change from scattered tab-body strings and generic widgets into a reusable console widget layer for badges, key/value grids, dense tables, optional inspectors, and refreshed modal forms, ready for Account/Moderation/Sysop conversion in Phase 25.

## Background

Phase 24 is part of the v1.3 SSH-first TUI screen facelift. `SCREENS.md` defines Operator Console as the denser administrative mode for Account, Moderation, and Sysop: tabs, tables, label/value grids, status cells, validation states, compact summaries, and optional selected-row inspectors. Phase 17 already added presentation metadata and theme mappings for `:operator`; Phase 18 added shared chrome; Phase 20 introduced `List.RichRow`; Phase 23 targets composer-specific widgets.

Current operator screens are functional but inconsistent. `Account` uses tabs with inline profile/preference forms and plain SSH-key rows. `Moderation` is mostly read-only text rows with status lines and hand-built truncation. `Sysop` has the richest surface, including forms, board/user rows, a system snapshot, and `Modal.Form` use for create/edit flows. `Display.Table` already exists as a themed stateful facade over Raxol's table component, but there is no Operator Console table API that standardizes dense row defaults, empty states, selected-row behavior, or console-specific presets. `Display.Badge`, `Display.KvGrid`, and `Workspace.Inspector` do not exist. `Modal.Form` exists and must keep its body-only overlay contract, but its visual treatment is still a basic title/divider/fields/hint column.

The visible gap is a missing shared console primitive layer. Phase 24 must create that layer and prove it with realistic fixture data, without converting Account, Moderation, and Sysop tab bodies yet.

## Requirements

1. **Badge primitive**: `Display.Badge` renders compact, theme-routed state labels for operator and shared UI states.
   - Current: Theme mappings include badge slots, but no `Foglet.TUI.Widgets.Display.Badge` module exists; screens use plain strings or ad hoc glyphs for states.
   - Target: A stateless `Display.Badge` widget supports at least required, subscribed, locked, sticky, pending, healthy, error, and neutral/info states, with stable label/value handling and theme-slot roles.
   - Acceptance: Widget tests verify each required state renders a recognizable label or glyph, routes styles through `Foglet.TUI.Theme`/`Foglet.TUI.Presentation.theme_mappings().badges`, and leaks no hardcoded terminal color atoms.

2. **Key/value grid primitive**: `Display.KvGrid` renders consistent label/value rows for operator summaries and compact forms.
   - Current: Sysop system snapshot and operator screen summaries use bespoke padded strings such as `"  #{label}#{value}"`; Account and Moderation have separate inline row formats.
   - Target: A stateless `Display.KvGrid` widget accepts label/value entries, optional state/badge metadata, and width options, then renders aligned label/value rows using display-width helpers and theme-routed label/value/status treatment.
   - Acceptance: Tests cover Account-profile-shaped rows, Sysop-system-shaped rows, site setting rows, limit rows, and status summary rows at 64-column and 80-column widths without text overlap or direct `String.length/1` layout assumptions.

3. **Console table module**: A new operator-console table module standardizes dense table configuration on top of the existing table foundation.
   - Current: `Display.Table` exists as a generic stateful Raxol facade with sortable/filterable/selectable support, but operator screens do not have shared presets for dense rows, empty states, selected-row details, or console table defaults.
   - Target: A new console table module, under the widget namespace, exposes an explicit public API for operator tables while reusing or wrapping `Display.Table` internally. It provides dense defaults for columns, rows, empty state copy, selection, sortable/filterable flags, and theme routing.
   - Acceptance: Tests instantiate the new module with LOG, USERS, BOARDS, SSH keys, and invite-shaped fixture data; render output includes headers and rows, empty tables render an honest compact empty state, selected-row navigation returns deterministic actions, and the implementation does not duplicate domain-specific screen logic.

4. **Workspace inspector primitive**: `Workspace.Inspector` provides an optional wide-terminal selected-row detail panel.
   - Current: No shared inspector exists; `SCREENS.md` treats selected-row inspectors as a future wide-terminal enhancement for operator workflows.
   - Target: A stateless or minimally stateful `Workspace.Inspector` widget renders selected item details and scoped actions from caller-provided data, and can be omitted or collapsed when width is below the configured threshold.
   - Acceptance: Tests verify the inspector renders details/actions for selected board/user/invite-shaped fixtures at wide width, returns an intentional empty/collapsed result below the threshold, and never creates or implies domain side effects on its own.

5. **Modal.Form visual refresh**: `Modal.Form` receives stronger visual hierarchy while preserving its body-only overlay contract and existing behavior.
   - Current: `Modal.Form.render/2` returns a bare column with a title, fixed divider, fields, base errors, and a hint; it must not draw its own modal border because `Foglet.TUI.App.render_modal_overlay/2` owns overlay chrome.
   - Target: `Modal.Form` still returns body-only content, but the body shows a stronger heading, clearer field labels, visible required markers, inline field errors, base errors, and an action footer for submit/cancel controls.
   - Acceptance: Existing `Modal.Form` behavior tests continue to pass; new render tests verify title, labels, required markers, inline/base errors, and action footer are visible; source/render tests verify no outer box/border is introduced by `Modal.Form`.

6. **Primitive size contracts**: Operator primitives are tested at the milestone terminal sizes.
   - Current: Width contracts exist for earlier facelift widgets, but the new console primitives do not exist and therefore have no 64x22, 80x24, or wide-terminal guarantees.
   - Target: Badge, KvGrid, console table, inspector, and refreshed Modal.Form each define and test their minimum viable behavior at 64x22, their compact target behavior at 80x24, and their richer behavior at one wide-terminal size.
   - Acceptance: Tests or layout smoke checks prove primitives do not overlap text or push required content out of bounds at 64x22, render their intended compact form at 80x24, and allow inspector/table detail enhancement only at wide width.

7. **Fixture-only adoption proof**: Phase 24 proves primitive usability with realistic operator data but does not convert the operator screens.
   - Current: Account, Moderation, and Sysop have existing screen behavior and tests; Phase 25 is responsible for converting those screens to the new console layouts.
   - Target: Phase 24 adds fixture/example coverage using Account, Moderation, and Sysop-shaped data for the primitives, without replacing tab bodies or changing screen workflows.
   - Acceptance: Source diff shows no broad Account/Moderation/Sysop tab-body conversion; primitive tests include realistic fixture rows for profile/prefs, SSH keys, invites, moderation log/users/boards, Sysop system metrics, users, and boards.

8. **Behavior preservation and theme hygiene**: The primitive layer is presentation-only and preserves existing operator behavior.
   - Current: Operator screen access checks, account saves, invite actions, sysop config writes, board/category modal flows, and moderation read-only honesty are implemented outside the missing primitive layer.
   - Target: New primitives are pure over caller-provided state, do not perform domain mutations, and route colors/styles through `Foglet.TUI.Theme` and `Foglet.TUI.Presentation` mappings.
   - Acceptance: Existing Account, Moderation, Sysop, `Display.Table`, and `Modal.Form` tests continue to pass; new widget tests include theme-hygiene checks; no domain context calls are introduced inside display/workspace primitive modules.

## Boundaries

**In scope:**
- `Foglet.TUI.Widgets.Display.Badge` for compact operator/shared states.
- `Foglet.TUI.Widgets.Display.KvGrid` for aligned label/value/status summaries.
- A new operator-console table module with dense defaults, empty states, selection behavior, and realistic operator fixture coverage.
- `Foglet.TUI.Widgets.Workspace.Inspector` or equivalent workspace widget for optional selected-row details/actions at wide width.
- `Modal.Form` visual body refresh: stronger heading, clearer labels, required markers, inline/base errors, and action footer.
- Primitive-level size contracts at 64x22, 80x24, and one wide-terminal layout.
- Fixture/example coverage using Account, Moderation, and Sysop-shaped data.
- Updates to the widget catalog README for new primitive modules.

**Out of scope:**
- Full Account, Moderation, or Sysop screen conversion - Phase 25 owns applying the primitives to the operator screens.
- New moderation queue, sanctions, review, suspend, archive, or destructive domain workflows - this phase is visual primitives, not workflow expansion.
- Browser-based admin UI or Phoenix end-user/admin workflows - Foglet remains SSH-first.
- Changing authorization, visibility, account save, sysop config, board/category mutation, invite, or moderation domain behavior - existing contexts remain authoritative.
- Making inspectors mandatory at 64x22 or 80x24 - inspectors are progressive wide-terminal enhancement.
- Replacing `Display.Table` internals wholesale when a wrapper/facade can preserve the existing tested table foundation.
- Adding modal overlay chrome inside `Modal.Form` - the app-level modal overlay remains the single owner of modal border/centering.

## Constraints

- The hard minimum terminal size is 64x22; 80x24 is the compact design target; larger terminals may progressively show inspectors and richer table detail.
- Operator primitives must be pure render/event helpers over caller-provided state and must not call domain contexts or perform persistence.
- Colors and styles route through `Foglet.TUI.Theme` and `Foglet.TUI.Presentation.theme_mappings/0`; new widget code must not introduce hardcoded terminal color atoms.
- Layout-sensitive alignment, padding, truncation, and width checks use `Foglet.TUI.TextWidth` or existing width-safe helpers rather than raw byte/string length assumptions.
- `Modal.Form` must preserve `init/1`, `handle_event/2`, `render/2`, `set_errors/2`, submit/cancel semantics, typed field coercion, focus movement, and body-only rendering.
- The new console table module must not fork domain-specific behavior into widgets; screens remain responsible for loading data, authorization, and mutation commands.

## Acceptance Criteria

- [ ] `Display.Badge` exists and renders required, subscribed, locked, sticky, pending, healthy, error, and neutral/info states with theme-routed styling.
- [ ] `Display.KvGrid` exists and renders Account, Sysop System, site setting, limit, and status summary fixture rows with width-safe label/value alignment.
- [ ] A new operator-console table module exists, wraps or reuses the existing table foundation, and covers dense rows, empty states, selected-row actions, sortable/filterable options, and console defaults.
- [ ] `Workspace.Inspector` exists and renders selected item details/actions at wide width while collapsing or omitting itself below its configured width threshold.
- [ ] `Modal.Form` keeps its body-only overlay contract and existing event behavior while rendering stronger heading, field labels, required markers, inline/base errors, and an action footer.
- [ ] Badge, KvGrid, console table, inspector, and Modal.Form have primitive-level tests for 64x22, 80x24, and at least one wide-terminal layout.
- [ ] Primitive tests use realistic Account, Moderation, and Sysop-shaped fixture data, but broad operator screen conversion is not included in this phase.
- [ ] Existing Account, Moderation, Sysop, `Display.Table`, and `Modal.Form` tests continue to pass.
- [ ] New primitive code passes theme-hygiene checks and does not leak hardcoded terminal color atoms.
- [ ] `rtk mix precommit` passes after implementation.

## Ambiguity Report

| Dimension           | Score | Min   | Status | Notes |
|---------------------|-------|-------|--------|-------|
| Goal Clarity        | 0.94  | 0.75  | met    | Shared console primitive layer is locked as the deliverable before Phase 25 conversion. |
| Boundary Clarity    | 0.84  | 0.70  | met    | Primitive creation and fixture proof are in scope; full screen conversion and domain workflows are out. |
| Constraint Clarity  | 0.78  | 0.65  | met    | 64x22/80x24/wide contracts, theme routing, width-safe helpers, and Modal.Form body-only contract are locked. |
| Acceptance Criteria | 0.82  | 0.70  | met    | Pass/fail checks cover each primitive, fixture proof, behavior preservation, size contracts, and precommit. |
| **Ambiguity**       | 0.11  | <=0.20| met    | Ready for discuss-phase. |

Status: met = dimension meets minimum; below minimum = planner treats as assumption.

## Interview Log

| Round | Perspective | Question summary | Decision locked |
|-------|-------------|------------------|-----------------|
| 1 | Researcher | What primitive set is required before Phase 25? | All four primitive families are required: Badge, KvGrid, console table, Workspace.Inspector, plus Modal.Form refresh. |
| 1 | Researcher | What should shared table presets mean? | Build a new operator-console table module rather than only adding docs or generic helper options. |
| 1 | Researcher | How much adoption proves usability? | Use realistic fixture examples only; broad Account/Moderation/Sysop conversion waits for Phase 25. |
| 2 | Researcher + Simplifier | What exact Modal.Form refresh is required? | Visual body upgrade: stronger heading, labels, required markers, inline/base errors, and action footer, while preserving body-only overlay. |
| 2 | Researcher + Simplifier | What responsive contract should primitives satisfy? | Each primitive is covered at 64x22, 80x24, and one wide layout; inspectors are wide-terminal enhancement. |

---

*Phase: 24-operator-console-primitives*
*Spec created: 2026-04-25*
*Next step: $gsd-discuss-phase 24 - implementation decisions (how to build what's specified above)*
