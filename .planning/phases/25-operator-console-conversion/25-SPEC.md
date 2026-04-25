# Phase 25: Operator Console Conversion - Specification

**Created:** 2026-04-25
**Ambiguity score:** 0.18 (gate: <= 0.20)
**Requirements:** 8 locked

## Goal

Account, Moderation, and Sysop screens convert from bespoke tab-body strings, hand-built rows, and inline form layouts to dense, consistent operator workbenches built on the Phase 24 console primitives (`Display.Badge`, `Display.KvGrid`, `Display.ConsoleTable`, refreshed `Modal.Form`), so the three operator surfaces share a coherent terminal-workbench look that remains usable at 64x22 and reads cleanly at 80x24.

## Background

Phase 24 shipped the operator console primitive layer with fixture-only proof:

- `Foglet.TUI.Widgets.Display.Badge` — theme-routed state labels for required/subscribed/locked/sticky/pending/healthy/error/neutral.
- `Foglet.TUI.Widgets.Display.KvGrid` — aligned label/value rows with optional state metadata.
- `Foglet.TUI.Widgets.Display.ConsoleTable` — dense table preset wrapping `Display.Table` with empty-state copy and selection.
- `Foglet.TUI.Widgets.Modal.Form` — refreshed body-only form with stronger heading, required markers, inline/base errors, and an action footer.
- `Foglet.TUI.Widgets.Workspace.Inspector` — exists as a primitive but **deferred to v1.4** for live wiring.

Operator screens today live at:

- `lib/foglet_bbs/tui/screens/account.ex` (+ `screens/account/`: `profile_form.ex`, `prefs_form.ex`, `ssh_keys_*.ex`, `state.ex`).
- `lib/foglet_bbs/tui/screens/moderation.ex` (+ `screens/moderation/state.ex`). Tab bodies are mostly read-only text rows and hand-built truncation across log, users, boards, and invites.
- `lib/foglet_bbs/tui/screens/sysop.ex` (+ `screens/sysop/`: `site_form.ex`, `limits_form.ex`, `boards_view.ex`, `users_view.ex`, `system_snapshot.ex`, `state.ex`).

These screens already declare `:operator` mode (Phase 17), share chrome (Phase 18), and use unicode-width-aware row primitives (Phases 16, 20). They authorize via `Foglet.Authorization`, route mutations through contexts (`Foglet.Accounts`, `Foglet.Boards`, `Foglet.Config`), and have existing behavior tests. Phase 25 is a presentation-layer conversion — domain workflows must not change.

The visible gap: the screens still render bespoke padded strings, ad-hoc status text, and inline form layouts instead of the new primitives. Phase 24 explicitly excluded broad tab-body conversion; Phase 25 closes that gap.

## Requirements

1. **Account profile and preferences forms use refreshed Modal.Form treatment.**
   - Current: `screens/account/profile_form.ex` and `prefs_form.ex` render forms with custom title rows, plain field labels, and inline error strings without consistent required markers or action footers.
   - Target: Profile and preferences tab bodies render through `Modal.Form` (or a tab-body adapter that uses the same heading/label/required-marker/inline-error/action-footer treatment) while preserving existing dirty/saved/error states, change tracking, and save behavior. Theme swatches for preferences render through `Display.Badge` or `Display.KvGrid` value cells.
   - Acceptance: Render tests assert visible heading, labeled fields with required markers where applicable, inline errors when validation fails, base error region, and a save/cancel-shaped action footer. Existing profile/prefs save, dirty, and error behavior tests continue to pass without modification of expected behavior.

2. **Account SSH keys tab and shared invite listings render through `Display.ConsoleTable`.**
   - **AMENDED 2026-04-25 (post-Codex review):** Account scope this phase is `profile`, `prefs`, `ssh_keys` only — Account does NOT consume the shared `InvitesSurface` in this phase (per CONTEXT D-09). Invite-listing conversion is **Moderation-only** in Phase 25. The shared `InvitesSurface` module is converted once so Account remains ready to adopt it in a later phase without re-work, but no Account tab renders invite listings here.
   - Current: `ssh_keys_surface.ex` builds SSH key rows by hand; the shared `InvitesSurface` (consumed by Moderation) uses bespoke padded strings.
   - Target: SSH-key listing (Account) and the shared invite listing (Moderation) are produced by `Display.ConsoleTable` with stable column definitions, dense row defaults, an honest empty state, and selection behavior matching today's keyboard interactions.
   - Acceptance: Render tests for the Account SSH keys tab and the Moderation invite listing assert the table primitive produces header + rows for sample data, that the empty fixture renders the primitive's empty-state copy, and that current selection/keybindings continue to operate. No domain mutations move into the primitive. Account invite-listing acceptance is explicitly out of scope this phase.

3. **Moderation tabs use `Display.KvGrid` summaries, `Display.Badge` status, and `Display.ConsoleTable` listings.**
   - Current: `screens/moderation.ex` renders scope/status as plain text lines, status indicators as ad-hoc strings, and log/users/boards/invites as hand-padded rows.
   - Target: Each Moderation tab renders a top scope/status block via `Display.KvGrid` with `Display.Badge` value cells, and the log/users/boards/invites listings render through `Display.ConsoleTable` with honest empty states. Read-only honesty is preserved (no fake actions added).
   - Acceptance: Render tests per moderation tab assert (a) presence of the kv-grid summary primitive, (b) at least one badge in the summary cell when status data is present, (c) the console-table primitive for the tab's listing, and (d) the configured empty-state copy renders for an empty fixture. Existing moderation tests continue to pass.

4. **Sysop site and limits forms convert to refreshed `Modal.Form` body treatment.**
   - Current: `sysop/site_form.ex` and `sysop/limits_form.ex` render forms with bespoke titles and field layouts.
   - Target: Both forms render through the refreshed `Modal.Form` body treatment with required markers, inline/base errors, action footer, preserving current `Foglet.Config` write paths and authorization checks.
   - Acceptance: Render tests assert heading, labeled fields, required markers, inline errors on invalid input, base error region, and an action footer. Existing site/limits save and validation behavior tests continue to pass.

5. **Sysop boards, users, and categories render through `Display.ConsoleTable`; system snapshot uses `Display.KvGrid` with metric badges.**
   - Current: `sysop/boards_view.ex`, `sysop/users_view.ex`, and `sysop/system_snapshot.ex` produce bespoke rows and padded label/value strings; existing board/category create/edit modals already use `Modal.Form`.
   - Target: Board/category and user listings render through `Display.ConsoleTable`. The system snapshot renders through `Display.KvGrid` with metric values badge-decorated for healthy/error/pending states. Board/category create/edit modals continue to use the now-refreshed `Modal.Form`.
   - Acceptance: Render tests assert console-table presence for boards, users, and categories with selection preserved; kv-grid presence in system snapshot with at least one badge cell when metric data implies a status; existing modal flows for board/category create/edit pass unchanged.

6. **Cautious destructive-action styling on Sysop and Moderation actions.**
   - Current: Destructive actions (delete board/category, ban user, etc.) render with the same emphasis as routine actions in tab bodies.
   - Target: Destructive actions in converted tab bodies route through the theme's destructive-emphasis slot (e.g., footer hint or action-row treatment) so they read distinctly from routine/save actions, without changing key bindings or confirmation flows.
   - Acceptance: Source/render checks confirm destructive actions in the affected tabs reference the theme's destructive slot rather than a hardcoded color atom or a routine-action style. Existing confirmation flows and key bindings remain unchanged.

7. **Converted tabs degrade cleanly at 64x22 and render their compact form at 80x24.**
   - Current: Existing operator screens have not been size-smoke-tested against the new primitives.
   - Target: Each converted tab body (Account: profile, prefs, ssh_keys; Moderation: log, users, boards, invites; Sysop: site, limits, boards, users, system) has a layout smoke check at 64x22 and 80x24 verifying no required content is pushed out of bounds and primitives do not overlap.
   - Acceptance: A layout smoke test (extending or adjacent to `test/foglet_bbs/tui/layout_smoke_test.exs`) iterates the converted tabs at 64x22 and 80x24 and asserts the rendered output stays within bounds with primitives present. Wide-terminal enhancement is not required.

8. **Behavior preservation, theme hygiene, and inspector deferral.**
   - Current: Operator screens authorize via `Foglet.Authorization`, mutate via contexts, and have existing behavior tests; the Phase 24 `Workspace.Inspector` widget exists but is unused in live screens.
   - Target: No domain logic, authorization checks, or PubSub wiring moves into widgets. All colors and emphasis route through `Foglet.TUI.Theme` / `Foglet.TUI.Presentation` mappings. `Workspace.Inspector` remains unused in production screens this phase and is explicitly out of scope.
   - Acceptance: All existing Account, Moderation, and Sysop test suites pass without weakening assertions; grep checks confirm no hardcoded color atoms (e.g., `:cyan`, `:red`, `:yellow`) are introduced inside the converted tab modules; grep confirms `Workspace.Inspector` is not referenced from `lib/foglet_bbs/tui/screens/`. `mix precommit` passes.

## Boundaries

### In Scope

- Conversion of all Account tab bodies (profile, prefs, ssh_keys) to use `Modal.Form`-style body treatment, `Display.ConsoleTable`, `Display.Badge`, and `Display.KvGrid`.
- Conversion of all Moderation tab bodies (log, users, boards, invites) to use `Display.KvGrid` summaries with `Display.Badge` status cells and `Display.ConsoleTable` listings.
- Conversion of all Sysop tab bodies (site, limits, boards, users, system) to use refreshed `Modal.Form`, `Display.ConsoleTable`, `Display.KvGrid`, and `Display.Badge`.
- Cautious destructive-action styling routed through the theme.
- 64x22 and 80x24 layout smoke checks for the converted tabs.
- Per-tab render tests asserting primitive usage and empty-state copy.

### Out of Scope

- **Live wiring of `Workspace.Inspector`** — Deferred to v1.4 (UI-02). Phase 25 ships no production usage of the inspector primitive; wide-terminal selected-row inspector behavior is not required.
- **New behavior tests** — No new tests for save/error/dirty/selection/modal flows beyond what existing screen tests already cover. Phase 25 is a presentation conversion; behavior preservation is verified by the existing suites continuing to pass.
- **Wide-terminal layout work** — Wide-terminal layouts beyond 80x24 are an enhancement (UI-05); not required this phase.
- **Theme palette tuning** — Beyond using existing semantic slots, no new color tokens or palette adjustments (UI-03).
- **New moderation case-management workflows** — Queue review, sanctions, etc. are deferred (UI-04).
- **Domain or authorization changes** — No changes to `Foglet.Accounts`, `Foglet.Boards`, `Foglet.Config`, `Foglet.Authorization`, or PubSub wiring.
- **New chrome or footer commands** — Ultra-compact chrome variants (UI-01) are deferred.

## Acceptance Criteria

- [ ] All Account tab bodies (profile, prefs, ssh_keys) render through Phase 24 primitives; render tests assert primitive presence and empty-state copy where applicable.
- [ ] All Moderation tab bodies (log, users, boards, invites) render kv-grid summaries with badge status cells and console-table listings; empty-state copy verified per tab.
- [ ] All Sysop tab bodies (site, limits, boards, users, system) render refreshed Modal.Form forms, console tables, and kv-grid system snapshot with metric badges.
- [ ] Destructive actions in converted tabs route through the theme's destructive-emphasis slot and not hardcoded color atoms.
- [ ] Layout smoke test passes at 64x22 and 80x24 for every converted tab.
- [ ] All pre-existing Account, Moderation, Sysop, `Display.Table`, and `Modal.Form` test suites pass without weakened assertions.
- [ ] Grep confirms zero hardcoded color atoms introduced in the converted tab modules.
- [ ] Grep confirms `Workspace.Inspector` is not referenced from `lib/foglet_bbs/tui/screens/`.
- [ ] `mix precommit` passes (compile-with-warnings-as-errors, formatter, Credo, Sobelow, Dialyzer).

## Ambiguity Report

| Dimension          | Score | Min  | Status |
|--------------------|-------|------|--------|
| Goal Clarity       | 0.85  | 0.75 | ✓      |
| Boundary Clarity   | 0.85  | 0.70 | ✓      |
| Constraint Clarity | 0.75  | 0.65 | ✓      |
| Acceptance Criteria| 0.80  | 0.70 | ✓      |
| **Ambiguity**      | **0.18** | ≤ 0.20 | ✓ |

Resolved during interview:
- Scope: all tab bodies of all three screens (vs. read-only-only or partial-screen scope).
- Inspector: deferred entirely to v1.4 (vs. shipping wired on wide terminals).
- Test depth: render + size smoke per tab (vs. full new behavior coverage or render-only).

## References

- ROADMAP entry: `.planning/ROADMAP.md` — Phase 25 success criteria.
- Requirements: `ACCOUNT-01`, `MOD-01`, `SYSOP-01` in `.planning/REQUIREMENTS.md`.
- Phase 24 spec and primitives: `.planning/phases/24-operator-console-primitives/24-SPEC.md`.
- Operator screens: `lib/foglet_bbs/tui/screens/{account,moderation,sysop}{,.ex}`.
- Layout smoke baseline: `test/foglet_bbs/tui/layout_smoke_test.exs`.
- Mode metadata + theme: `Foglet.TUI.Presentation`, `Foglet.TUI.Theme`.
- Project conventions: `AGENTS.md` (TUI boundaries, theme routing, testing rules).
