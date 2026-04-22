# Phase 8: PostComposer - Context

**Gathered:** 2026-04-22
**Status:** Ready for planning
**Workstream:** phase-03-screen-audit

<domain>
## Phase Boundary

Audit `post_composer.ex` with a constrained refactor and hygiene pass:

- rewrite publish submission from nested `case` shape to a `with` shape while preserving existing behavior and modal branches,
- add a load-bearing source-order warning comment for `handle_key/2` clauses,
- enforce Phase-0 helper routing and terminal-size attribute policy,
- keep `Compose` + `MultiLineInput` behavior unchanged.

**In scope:**
- `COMPOSER-01..05` and inherited `AUDIT-05..22`.
- Minimal-risk `with` rewrite for publish path branch parity.
- `@default_terminal_size` adoption for inline terminal fallback cleanup.
- Source-order guard note above `handle_key/2` clause block.
- Guardrail verification (behavior + sparseness + rubric closure).

**Out of scope:**
- Reworking composer UX, layout expansion, or new visible rows.
- Replacing `Compose` or `MultiLineInput`.
- New shared modules beyond already-shipped Phase 0 helpers.

</domain>

<decisions>
## Implementation Decisions

### Submit flow rewrite

- **D-01:** Use a minimal-risk `with` around publish creation only, not a full top-to-bottom `with` rewrite.
- **D-02:** Keep existing pre-check guard behavior (empty body, max length, logged-in requirement) and preserve modal messages bit-for-bit.
- **D-03:** Preserve success branch behavior exactly: return to `:post_reader`, clear composer state, and dispatch `{:load_posts, thread.id, jump_last: true}`.

### Source-order safety

- **D-04:** Add a source-order warning comment above `handle_key/2` clauses with PostComposer-specific wording.
- **D-05:** Preserve clause order semantics (`:tab`, `Ctrl+S`, `Ctrl+C`, fallback forwarding) as load-bearing behavior.

### Terminal and helper hygiene

- **D-06:** Add `@default_terminal_size {80, 24}` and replace inline fallback usage with the module attribute.
- **D-07:** Keep `Theme.from_state/1` and `Screens.Domain.get/2` as the only theme/domain resolution paths.

### Audit guardrails

- **D-08:** Enforce full guardrail closure for Phase 8 (`COMPOSER-01..05` + inherited `AUDIT-05..22`) with behavior and sparseness preserved.
- **D-09:** **Phase-8-specific AUDIT-16 override:** line-count increase is acceptable for this phase if visible row count does not increase and protected layout regions remain untouched.

### the agent's Discretion

- Exact `with` clause shape and helper extraction boundaries, provided branch parity is preserved.
- Exact wording of the PostComposer-specific source-order warning comment.
- Exact test-level implementation details needed to prove branch-preserving behavior.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase scope and rubric

- `.planning/workstreams/phase-03-screen-audit/ROADMAP.md` — Phase 8 goal, dependency ordering, success criteria.
- `.planning/workstreams/phase-03-screen-audit/REQUIREMENTS.md` — `COMPOSER-01..05`, inherited `AUDIT-05..22`, and `AUDIT-16` context.
- `.planning/workstreams/phase-03-screen-audit/STATE.md` — current workstream state and inherited locked decisions.

### Prior phase decisions to inherit

- `.planning/workstreams/phase-03-screen-audit/phases/00-cross-cutting-extractions-prelude/00-CONTEXT.md` — helper contracts for theme/domain access.
- `.planning/workstreams/phase-03-screen-audit/phases/01-login/01-CONTEXT.md` — `with`-chain migration precedent and branch-parity discipline.
- `.planning/workstreams/phase-03-screen-audit/phases/07-newthread/07-CONTEXT.md` — source-order comment precedent and compose-path constraints.

### Research and architectural constraints

- `.planning/workstreams/phase-03-screen-audit/research/ARCHITECTURE.md` — section-order expectations and screen-level audit structure.
- `.planning/workstreams/phase-03-screen-audit/research/PITFALLS.md` — source-order and anti-affordance landmines.
- `.planning/workstreams/phase-03-screen-audit/research/SUMMARY.md` — phase sequencing and audit strategy.

### Target code and tests

- `lib/foglet_bbs/tui/screens/post_composer.ex` — audited target screen.
- `test/foglet_bbs/tui/screens/post_composer_test.exs` — branch and key-flow verification surface.
- `lib/foglet_bbs/tui/widgets/compose.ex` — key-event translation and render integration.
- `lib/foglet_bbs/tui/screens/domain.ex` — domain helper contract in use.
- `lib/foglet_bbs/tui/theme.ex` — theme helper contract in use.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- `Theme.from_state/1` already used by PostComposer for theme lookup.
- `Domain.get/2` already used for posts module lookup fallback.
- `Compose.translate_key/1` + `Compose.render_input/3` already bridge input events/rendering.
- `MultiLineInput` state is already centralized in `state.screen_state[:post_composer].input_state`.

### Established Patterns

- `handle_key/2` ordering is behavior-sensitive because explicit control-key clauses must intercept before generic input forwarding.
- Existing submit path already models branch outcomes clearly (`{:ok, _post}` success and modal-error failure path).
- Composer cleanup convention uses `screen_state: Map.delete(..., :post_composer)` and `composer_draft: nil`.

### Integration Points

- Success returns to `:post_reader` and triggers post reload with `jump_last: true`.
- Modal error messaging is consumed by app-level modal rendering and must remain stable.
- Terminal-width fallback currently appears in preview/init helpers and is the cleanup target for `@default_terminal_size`.

</code_context>

<specifics>
## Specific Ideas

- Keep refactor local to `post_composer.ex` and its tests, with no cross-screen churn.
- Treat branch-parity and key-clause ordering as primary correctness constraints.
- Enforce row-density restraint even if implementation line count grows.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 08-postcomposer*
*Context gathered: 2026-04-22*
