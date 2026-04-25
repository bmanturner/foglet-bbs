---
phase: 25
reviewers: [codex]
reviewed_at: 2026-04-25T23:25:09Z
plans_reviewed: [25-01-shared-scaffolding-PLAN.md, 25-02-account-conversion-PLAN.md, 25-03-moderation-conversion-PLAN.md, 25-04-sysop-conversion-PLAN.md, 25-05-finish-line-PLAN.md]
---

# Cross-AI Plan Review — Phase 25

## Codex Review

## Summary

The Phase 25 plans are strong overall: they are well scoped to presentation-layer conversion, preserve domain boundaries, explicitly sequence shared scaffolding before parallel screen work, and define concrete verification for primitive adoption, layout bounds, theme hygiene, and inspector deferral. The biggest risks are not architectural; they are plan consistency and execution risk from over-prescriptive implementation details, especially around `Modal.Form`, shared invites, layout smoke fixtures, and the tab count mismatch. With a few corrections, this is a solid executable plan set.

## Strengths

- Clear dependency ordering: Plan 01 handles shared `Modal.Form` and layout-smoke scaffolding before Account, Moderation, and Sysop conversion.
- Good boundary discipline: plans repeatedly protect domain contexts, authorization, PubSub, and SSH/TUI ownership boundaries.
- Strong test strategy: focused tests per screen, per-tab layout smoke at `64x22` and `80x24`, theme hygiene, and final `rtk mix precommit`.
- Good risk capture: explicit pitfalls for Shift+Tab shape, enum preview, empty tables, conditional visibility, read-only moderation, and explicit table widths.
- Good primitive alignment: plans consistently push screens toward `Modal.Form`, `ConsoleTable`, `KvGrid`, and `Badge` instead of inventing new widgets.
- Inspector deferral is well enforced by both scope text and an automated test.

## Concerns

- **HIGH: Tab count inconsistency.** The spec/context says 11 converted tabs in several places, but the actual set is 12: Account 3 + Moderation 4 + Sysop 5. Plan 05 notices this midstream but still contains stale “11” language. This can cause validation drift.
- **HIGH: Account invites scope mismatch.** SPEC requirement 2 mentions invite listings for Account/Moderation, but CONTEXT D-09 and Plan 02 define Account as only `profile`, `prefs`, `ssh_keys`. Plan 03 says Account does not currently consume `InvitesSurface`. That discrepancy should be resolved explicitly so ACCOUNT-01 acceptance is not ambiguous.
- **MEDIUM: Plan 01 may add a smoke-test helper against production state before converted tabs exist.** The helper is useful, but the example `Sysop.BoardsView` sentinel can become brittle if `Sysop.init_screen_state/0`, active-tab storage, or table initialization requires app context/fixtures.
- **MEDIUM: `Modal.Form` Process dictionary submit pattern is risky if over-expanded.** It follows existing precedent, but spreading it to multiple forms increases hidden coupling. The plans should require cleanup with `after`-style deletion or a helper to prevent stale payload leakage between events/tests.
- **MEDIUM: Theme hygiene test using serialized render trees can be noisy.** It is better than grep, but it may flag legitimate atom names in metadata or miss runtime style construction if rendering paths are fixture-thin. Keep it, but do not treat it as the only evidence for destructive styling.
- **MEDIUM: Layout smoke “no overlap by `{x, y}`” may false-positive.** Terminal render trees can contain layered/container text or adjacent styled runs at the same coordinate depending on renderer internals. The helper should compare occupied display cells, or limit overlap checks to final positioned text elements known to be visible.
- **MEDIUM: Parallelism claim is a little optimistic.** Plans 02, 03, and 04 all modify `layout_smoke_test.exs`, and Plan 03’s shared invites changes may affect Account tests. Parallel execution will likely produce merge conflicts unless test additions are serialized or split into per-screen helper files.
- **LOW: Some acceptance checks rely on grep counts.** Useful as guardrails, but they can encourage superficial implementation. The render/behavior tests should be the source of truth.
- **LOW: Performance risk is small but present.** Re-initializing `ConsoleTable` and forms on every load/change is fine at BBS scale, but the plans should avoid rebuilding tables on every render.
- **LOW: Finish-line plan says no production code, but also updates validation docs.** That is fine, but the `files_modified` list omits the validation and summary files.

## Suggestions

- Normalize the phase language to **12 converted tabs** everywhere, or explicitly explain why one tab is excluded from a given count.
- Resolve the Account invite discrepancy before execution: either add Account invites to Phase 25 scope/tests or amend SPEC acceptance to say invite conversion is shared/Moderation-only this phase.
- Add a shared `Modal.Form` submit-stash helper if the Process dictionary pattern is repeated in four modules, with guaranteed cleanup after each event.
- Make layout smoke additions less conflict-prone by moving per-screen smoke builders into helper modules, leaving `layout_smoke_test.exs` as a thin registry.
- Replace grep-count acceptance where possible with direct ExUnit assertions against rendered output or public state.
- Add explicit tests that empty `ConsoleTable` instances handle `:up`, `:down`, and `:enter` for every converted selectable/read-only table, not just one or two representative tables.
- For destructive styling, test the actual command data or style helper directly rather than relying on serialized render text.
- Add a small “fixture realism” note for smoke tests: use fixtures that exercise long handles, Unicode glyphs, missing optional data, and empty states at least once.
- Update Plan 05 `files_modified` to include `.planning/phases/25-operator-console-conversion/25-VALIDATION.md` and summary output.

## Risk Assessment

**Overall risk: MEDIUM.**

The architecture and scope are sound, and the plans are unusually well validated. The remaining risk is execution complexity: 12 tabs, multiple state modules, shared widget behavior, and a large shared smoke-test file create opportunities for merge conflicts and brittle tests. The inconsistencies around tab count and Account invites should be fixed before implementation; after that, the phase risk drops toward low-medium.

---

## Consensus Summary

Only one reviewer (Codex) was invoked, so there is no cross-AI consensus to synthesize. Treat the Codex findings above as a single independent perspective.

### Top Concerns to Address Before Execution

1. **HIGH — Tab count inconsistency (11 vs 12).** Plan/SPEC/CONTEXT use "11 tabs" but the actual sum is 12 (Account 3 + Moderation 4 + Sysop 5). Reconcile language across SPEC, CONTEXT, and all PLANs.
2. **HIGH — Account invites scope mismatch.** SPEC mentions Account invites; CONTEXT D-09 and Plan 02 exclude them. Resolve before execution to keep ACCOUNT-01 acceptance unambiguous.
3. **MEDIUM — Parallel execution risk.** Plans 02–04 all touch `layout_smoke_test.exs`; consider splitting per-screen helpers to avoid merge conflicts.
4. **MEDIUM — Modal.Form Process dictionary submit pattern.** Add a shared helper with guaranteed cleanup if reused across four modules.
5. **LOW — Plan 05 files_modified omits 25-VALIDATION.md and summary outputs.**
