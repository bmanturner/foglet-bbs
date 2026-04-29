# Phase 40: Verification & Documentation - Specification

**Created:** 2026-04-29
**Ambiguity score:** 0.11 (gate: <= 0.20)
**Requirements:** 11 locked

## Goal

The v2.0 TUI runtime migration closes with green verification gates, resolved Phase 39 deferred cleanup, and documented guidance for adding or migrating screens under the `Context`/`Effect`/screen-callback contract.

## Background

Phase 34 introduced the target `Foglet.TUI.Screen` contract (`init/1`, `update/3`, `render/2`) and explicit `Foglet.TUI.Context` / `Foglet.TUI.Effect` boundaries. Phases 35-38 migrated production screen families into screen-owned state and reducer behavior. Phase 39 made `Foglet.TUI.App` a runtime shell: route storage, screen-state storage, context construction, effect interpretation, PubSub plumbing, modal/SizeGate precedence, and rendering dispatch remain in App, while screen-local behavior moved to screen modules.

The closeout artifacts from Phase 39 intentionally defer several items to Phase 40:

- `.planning/phases/39-app-shell-simplification/deferred-items.md` records two pre-existing `account_test.exs` failures and two remaining Dialyzer warnings.
- `.planning/phases/39-app-shell-simplification/39-SUMMARY.md` records Phase 40 scope for transitional callback removal, remaining breadcrumb migration, precommit closure, and full verification.
- `.planning/phases/39-app-shell-simplification/39-REVIEW-FIX.md` records skipped follow-up work around legacy dispatch paths, cross-screen legacy reads, source-string-grep tests, and App-shaped frame-state maps.

Phase 40 is therefore not a new architecture phase. It is the milestone close gate: fix or prove irrelevant the known deferred issues, verify the migrated runtime end to end, and leave concise documentation for future TUI work.

## Requirements

1. **Deferred-item register**: Phase 40 begins by consuming Phase 39 deferred artifacts and turning each relevant item into a tracked verification or cleanup task.
   - Current: Deferred items are scattered across `deferred-items.md`, `39-SUMMARY.md`, and `39-REVIEW-FIX.md`.
   - Target: Phase 40 planning and summary artifacts list every carried-forward item, its disposition, and the evidence for closure or exclusion.
   - Acceptance: A verifier can map each Phase 39 deferred item to a Phase 40 result without searching unrelated notes.

2. **Account doomed-submit failures**: The two pre-existing Account/MainMenu modal-submit tests no longer fail.
   - Current: `test/foglet_bbs/tui/screens/account_test.exs` has two known failures at the doomed oneliner and doomed hide-oneliner submit cases.
   - Target: Error routing leaves the modal/form state in a recoverable `{:error, _}` state and Escape dismissal remains covered.
   - Acceptance: The focused `account_test.exs` cases pass without deleting the behavioral checks or replacing them with text-presence assertions.

3. **Dialyzer cleanup**: The remaining Phase 39 Dialyzer warnings are resolved.
   - Current: `rtk mix precommit` is blocked by `board_list.ex` unreachable pattern coverage and `sysop.ex` impossible pattern warnings.
   - Target: The code shape is adjusted so Dialyzer emits no warnings for these paths.
   - Acceptance: `rtk mix dialyzer` exits 0, and the Phase 40 summary identifies the exact warnings that were removed.

4. **Transitional callback removal**: Production TUI runtime no longer depends on legacy `render/1`, `handle_key/2`, or `init_screen_state/1` callbacks.
   - Current: `Foglet.TUI.Screen` still declares transitional callbacks, App still contains a legacy `handle_key/2` fallback path, and several screens/tests still expose legacy callback functions.
   - Target: Production dispatch and migrated test fixtures use `init/1`, `update/3`, and `render/2`; transitional callback declarations and App legacy dispatch are removed unless a specific non-production compatibility need is documented and bounded.
   - Acceptance: Static inspection shows no production App dispatch through legacy callbacks, and any remaining legacy helper is explicitly documented as test-only or removed.

5. **Breadcrumb completion**: Remaining screens emit explicit `breadcrumb_parts` rather than relying on the `["Foglet"]` fallback.
   - Current: ThreadList, PostReader, PostComposer, NewThread, and Sysop have explicit breadcrumbs; Login breadcrumb tests are pending, and MainMenu, BoardList, Account, Moderation, Register, and Verify still need explicit coverage or confirmation.
   - Target: Each production screen renders a screen-appropriate breadcrumb through explicit `breadcrumb_parts`.
   - Acceptance: Pending `:phase39_login_breadcrumb_pending` tests are either made active and passing or replaced with behavior-equivalent active tests; no production screen relies on a fallback breadcrumb except where the intended breadcrumb is exactly `["Foglet"]` and that intent is tested.

6. **Screen reducer coverage**: Every migrated screen family has reducer/effect tests for key handling, task-result handling, and route-entry behavior that belongs to that screen.
   - Current: Coverage exists in slices from phases 35-39, but Phase 40 must prove it is complete across auth/home, board/thread, post/composer, account, moderation, and sysop families.
   - Target: Tests assert local state transitions and emitted `Effect` values at the screen reducer boundary.
   - Acceptance: A coverage inventory in Phase 40 artifacts names the test files and representative cases for each screen family.

7. **App-shell verification**: App tests prove the runtime shell interprets effects generically and does not mutate screen-specific state fields.
   - Current: Phase 39 tests cover struct shape, generic PubSub subscription routing, route-entry dispatch, modal precedence, and runtime-shell function attribution; the final milestone still needs a close-gate assertion set.
   - Target: App-shell tests cover generic effect interpretation, initial mount route-entry hydration, PubSub topic delegation, modal/SizeGate precedence, screen-state storage, and absence of screen-specific state mutation.
   - Acceptance: App-shell tests pass and include a regression for authenticated initial mount behavior so route-entry work is not skipped on first paint.

8. **Render smoke verification**: Canonical TUI renders pass at supported terminal sizes with explicit evidence.
   - Current: Phase 39 has five 80x24 render snapshots and documented breadcrumb-only deltas.
   - Target: Phase 40 verifies representative migrated screens at 64x22, 80x24, and 132x50 using existing render smoke patterns and `rtk mix foglet.tui.render`.
   - Acceptance: The Phase 40 summary records the commands, screens, terminal sizes, and pass/fail result; any expected visual delta is explained as a deliberate product-preserving change.

9. **Screen contract documentation**: Documentation explains how to add or migrate a screen using `Context`, `Effect`, and the new screen callbacks.
   - Current: `Foglet.TUI.Screen` module docs describe the contract, but an operator/developer-facing guide is required by `VERIFY-04`.
   - Target: `lib/foglet_bbs/tui/widgets/README.md` or an adjacent TUI doc links to screen contract guidance with examples for state ownership, effects, tasks, PubSub subscriptions, route params, modal requests, and rendering.
   - Acceptance: The doc contains a concrete checklist for new screens and migrated screens, and the link from the widget/TUI README is present.

10. **Targeted test hygiene**: Known brittle or policy-violating tests in the migrated TUI surface are cleaned up without attempting a broad whole-suite rewrite.
   - Current: Phase 39 review/fix notes source-string-grep tests and noisy text-presence assertions, and AGENTS.md forbids bullshit text-presence tests.
   - Target: Phase 40 removes or replaces known source-string-grep tests and pending markers in the migrated TUI area with behavior-level assertions; broad unrelated text assertion cleanup is out of scope.
   - Acceptance: The known source-string-grep sites from Phase 39 review/fix are gone or justified as static lint guards with a stronger replacement plan, and new Phase 40 tests do not assert merely on arbitrary text presence.

11. **Final green gates**: The milestone close gates are green.
   - Current: Phase 39 accepted baseline-relative results because pre-existing failures and warnings remained.
   - Target: `rtk mix test`, focused TUI render smoke checks, and `rtk mix precommit` complete successfully after Phase 40 changes.
   - Acceptance: Phase 40 summary records successful `rtk mix test`, `rtk mix precommit`, and render verification commands; any remaining blocker must be explicitly marked as pre-existing, non-regressed, owner-assigned, and approved as not blocking v2.0 close.

## Boundaries

**In scope:**
- Consuming Phase 39 deferred artifacts and closing or explicitly excluding each carried-forward item.
- Fixing known Account doomed-submit failures and remaining Dialyzer warnings.
- Removing or bounding transitional TUI callback/legacy dispatch paths after all screens are migrated.
- Completing explicit breadcrumb coverage for production screens affected by Phase 39.
- Adding or updating reducer/effect tests, App-shell tests, and render smoke verification for migrated TUI screens.
- Updating TUI developer documentation for the new screen contract.
- Running and documenting `rtk mix test`, render smoke commands, and `rtk mix precommit`.

**Out of scope:**
- New BBS product capabilities - v2.0 is an architecture/verification milestone.
- End-user browser workflows - Foglet remains SSH-first for this milestone.
- Replacing Raxol or changing the runtime process model - Phase 40 verifies the current architecture.
- Broad visual redesign of screens - render changes are allowed only when needed to restore or preserve existing behavior under the new contract.
- Broad cleanup of every text-presence assertion in the full test suite - Phase 40 targets known migrated TUI debt and avoids adding new weak tests.
- New routing/history architecture, typed route modules, or per-screen processes - these remain future requirements.
- Fixing unrelated historical debug notes outside the v2.0 TUI runtime migration unless they block the final gates.

## Constraints

- Use `rtk` for all shell commands in this repository.
- Keep domain workflows in contexts; Phase 40 TUI work must not add domain side effects in App, SSH handlers, or render functions.
- TUI screen behavior belongs in `Foglet.TUI.App` only when it is runtime-shell behavior; screen-local behavior belongs in screen reducers/state modules.
- Do not add tests that merely assert arbitrary text presence or absence.
- Use existing render smoke patterns and `mix foglet.tui.render` for visual verification.
- `rtk mix precommit` remains the canonical final precommit chain; `rtk mix test` is a separate required gate because precommit does not run the full test suite.

## Acceptance Criteria

- [ ] Phase 40 artifacts enumerate all carried-forward Phase 39 deferred items and their final disposition.
- [ ] The two known Account doomed-submit tests pass as behavior tests.
- [ ] `rtk mix dialyzer` exits 0 with the Phase 39 deferred warnings resolved.
- [ ] Production App dispatch no longer depends on legacy screen callbacks.
- [ ] Remaining production screens have explicit breadcrumb behavior covered by active tests or documented exact-fallback intent.
- [ ] Reducer/effect coverage is inventoried for every migrated screen family.
- [ ] App-shell tests cover generic effect interpretation, initial route-entry hydration, PubSub delegation, modal/SizeGate precedence, and no screen-specific state mutation.
- [ ] Render smoke verification runs for representative screens at 64x22, 80x24, and 132x50.
- [ ] TUI screen contract documentation is written and linked from the TUI/widget documentation surface.
- [ ] Known source-string-grep/pending migrated-TUI tests are removed, replaced, or explicitly justified with a stronger follow-up.
- [ ] `rtk mix test` exits 0.
- [ ] `rtk mix precommit` exits 0, or any remaining blocker is explicitly approved as non-blocking with evidence.

## Ambiguity Report

| Dimension           | Score | Min   | Status | Notes |
|---------------------|-------|-------|--------|-------|
| Goal Clarity        | 0.92  | 0.75  | met    | Phase 40 is the v2.0 close gate with green verification and documentation. |
| Boundary Clarity    | 0.90  | 0.70  | met    | Deferred items included; new product/browser/runtime architecture excluded. |
| Constraint Clarity  | 0.84  | 0.65  | met    | rtk, TUI ownership, no weak text tests, render smoke, and precommit/test gates locked. |
| Acceptance Criteria | 0.90  | 0.70  | met    | Pass/fail checks cover cleanup, tests, docs, render, and final gates. |
| **Ambiguity**       | 0.11  | <=0.20| met    | Ready for discuss-phase. |

## Interview Log

| Round | Perspective | Question summary | Decision locked |
|-------|-------------|------------------|-----------------|
| 1 | Researcher | Which deferred items should Phase 40 own? | All listed Phase 39 deferred items are in scope, including test failures, Dialyzer warnings, transitional callbacks, breadcrumb follow-up, and skipped review cleanup. |
| 1 | Researcher | What should count as complete? | Green gates are required: relevant/full TUI tests, render smoke checks, and `rtk mix precommit` must pass with no undocumented blockers. |
| 1 | Simplifier | How broad should test cleanup be? | Targeted cleanup only: known pending/source-grep/legacy migrated-TUI tests are addressed; broad whole-suite text assertion cleanup is out of scope. |

---

*Phase: 40-verification-documentation*
*Spec created: 2026-04-29*
*Next step: $gsd-discuss-phase 40 - implementation decisions (how to build what is specified above)*
