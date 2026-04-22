# Phase 7: NewThread - Context

**Gathered:** 2026-04-21
**Status:** Ready for planning
**Workstream:** phase-03-screen-audit

<domain>
## Phase Boundary

Audit `new_thread.ex` with a focused migration of title-input handling while
preserving established compose behavior:

- migrate the title line from hand-rolled input to `Input.TextInput`,
- keep body composition on `Compose` + `MultiLineInput` unchanged,
- enforce Phase-0 helper routing and terminal-size attribute policy,
- preserve load-bearing source-order semantics for key handling,
- satisfy audit-wide rubric constraints for this screen.

**In scope:**
- `NEWTHREAD-01..05` and inherited `AUDIT-05..22` checks.
- Title-input migration to `Input.TextInput`.
- `@default_terminal_size` + grep-gate cleanup for inline `{80,24}` fallbacks.
- Preserve source-order-sensitive `handle_key/2` clause behavior.
- Confirm canonical section order and `init_screen_state/1` compliance.

**Out of scope:**
- Replacing the body compose stack (`Compose` + `MultiLineInput`).
- New UI rows, sidebars, banners, or region-expanding layout changes.
- New shared modules beyond existing Phase-0 extractions.
- Reworking cross-screen keybinding paradigms.

</domain>

<decisions>
## Implementation Decisions

### Title input migration

- **D-01:** Replace the hand-rolled title-input rendering with `Input.TextInput`
  per Phase 1 precedent.
- **D-02:** Visual drift from the old `█` cursor is accepted as part of this
  migration.

### Body composer invariants

- **D-03:** Keep body composition pipeline unchanged: `Compose` wrapper,
  `MultiLineInput` state ownership, edit/preview behavior, and tab semantics.
- **D-04:** No behavior-changing refactor of body input path is allowed in this phase.

### Helper and terminal-size policy

- **D-05:** Add/keep `@default_terminal_size` and route all `{80,24}` fallbacks to
  that attribute.
- **D-06:** Ensure theme/domain lookups remain routed through Phase-0 helpers with
  zero regressions on grep gates #7/#8/#9.

### Source-order guard

- **D-07:** Preserve guarded `handle_key/2` clause order unchanged where Ctrl+S/Ctrl+C
  interception depends on clause ordering.
- **D-08:** Preserve the existing source-order warning note and semantics; do not
  reorder those guarded clauses.

### Audit guardrails

- **D-09:** Enforce strict audit guardrails: no visible-row growth, no protected
  region fills, canonical section order, and explicit `init_screen_state/1`
  compliance.
- **D-10:** If a change conflicts with guardrails, favor guardrail compliance over
  optional cleanup.

### the agent's Discretion

- Exact `Input.TextInput` wiring details for title field (event translation,
  focus-state shape, masking disabled).
- Exact refactor approach to minimize churn while preserving behavior.
- Exact section-level reordering needed for `AUDIT-18` compliance.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase requirements and rubric

- `.planning/workstreams/phase-03-screen-audit/ROADMAP.md` — Phase 7 goal,
  success criteria, and dependency constraints.
- `.planning/workstreams/phase-03-screen-audit/REQUIREMENTS.md` —
  `NEWTHREAD-01..05` plus inherited `AUDIT-05..22` constraints.
- `.planning/workstreams/phase-03-screen-audit/STATE.md` — workstream state and
  locked-decision continuity.

### Research and constraints

- `.planning/workstreams/phase-03-screen-audit/research/ARCHITECTURE.md` —
  NewThread architecture notes, section-order guidance, and reserved-region map.
- `.planning/workstreams/phase-03-screen-audit/research/PITFALLS.md` —
  anti-affordance traps and source-order/load-bearing warnings.
- `.planning/workstreams/phase-03-screen-audit/research/SUMMARY.md` —
  workstream-level recommendations and sequencing context.

### Prior phase context this phase inherits

- `.planning/workstreams/phase-03-screen-audit/phases/00-cross-cutting-extractions-prelude/00-CONTEXT.md` —
  helper API contracts for theme/domain lookup.
- `.planning/workstreams/phase-03-screen-audit/phases/01-login/01-CONTEXT.md` —
  TextInput migration precedent and accepted cursor visual drift.
- `.planning/workstreams/phase-03-screen-audit/phases/05-boardlist/05-CONTEXT.md` —
  current loading/guardrail discipline used in adjacent list screens.
- `.planning/workstreams/phase-03-screen-audit/phases/06-threadlist/06-CONTEXT.md` —
  recent audit guardrail decisions and strict contract style.

### Code to read before planning

- `lib/foglet_bbs/tui/screens/new_thread.ex` — audited target screen.
- `test/foglet_bbs/tui/screens/new_thread_test.exs` — behavior and key-flow coverage.
- `lib/foglet_bbs/tui/widgets/compose.ex` — compose wrapper behavior.
- `lib/foglet_bbs/tui/widgets/input/text_input.ex` — title-input target widget.
- `lib/foglet_bbs/tui/widgets/post/markdown_body.ex` — preview rendering behavior.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable assets

- `Theme.from_state/1` and `Screens.Domain.get/2` already exist and are in use.
- `init_screen_state/1` already exists and provides central screen-state defaults.
- `Compose` and `MultiLineInput` already cover body edit/preview workflows.

### Established patterns

- Title input is currently hand-rolled and cursor-rendered inline.
- Body input key events are source-order-sensitive due to Ctrl+S/Ctrl+C interception
  before generic body fallthrough.
- Existing tests cover title editing, body editing, tab behavior, submit/cancel paths,
  and title length constraints.

### Integration points

- Successful submit routes to `:thread_list` and dispatches `{:load_threads, board.id}`.
- Cancel/escape behavior is origin-aware (`:main_menu` vs `:thread_list`).
- Any title-input migration must preserve submit validation semantics and existing
  navigation/update commands.

</code_context>

<specifics>
## Specific Ideas

- Use `Input.TextInput` for title while preserving the existing user flow and
  validation semantics.
- Keep body composer untouched as a deliberate scope fence.
- Preserve clause-order-sensitive key handling and accompanying warning note.

</specifics>

<deferred>
## Deferred Ideas

- Any redesign of body editor UX beyond current `Compose` + `MultiLineInput`.
- Additional layout elements below char counters or in reserved regions.
- Cross-screen keybinding normalization work beyond this audit phase.

</deferred>

---

*Phase: 07-newthread*
*Context gathered: 2026-04-21*
