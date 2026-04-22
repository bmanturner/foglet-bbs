# Phase 9: PostReader - Context

**Gathered:** 2026-04-22
**Status:** Ready for planning
**Workstream:** phase-03-screen-audit

<domain>
## Phase Boundary

Audit `post_reader.ex` as the final screen audit phase:

- complete helper hygiene on domain lookups,
- resolve `load_posts/2` and `flush_read_pointers/2` ownership as public App callbacks,
- apply loading-state spinner adoption for this screen under `AUDIT-10`,
- enforce strict render-path purity boundaries around cache/viewport behavior.

**In scope:**
- `READER-01..07` and inherited `AUDIT-05..22`.
- Full `Domain.get/2` helper adoption with fallback parity.
- Callback contract clarity for `load_posts/2` and `flush_read_pointers/2`.
- Spinner adoption for loading states.
- Purity guardrails: no state mutation in `defp render_*`.

**Out of scope:**
- Feature additions (search, reply tree, oneliner, upvote, moderation indicators).
- Replacing `PostCard + MarkdownBody + Viewport` pipeline.
- Cross-screen behavior changes outside PostReader + its tests.

</domain>

<decisions>
## Implementation Decisions

### Domain/helper adoption

- **D-01:** Apply full helper adoption now: all domain module resolution in load/flush paths uses `Domain.get/2`.
- **D-02:** Preserve existing fallbacks exactly (`Foglet.Posts`, `Foglet.Boards`, `Foglet.Threads`) with no behavior drift.

### Public callback ownership

- **D-03:** Keep `load_posts/2` and `flush_read_pointers/2` public as App-dispatched screen callbacks.
- **D-04:** Treat them as intentional contract surface, not dead code; enforce with call-site and test verification.

### Loading-state behavior

- **D-05:** Adopt spinner-based loading for this phase (`AUDIT-10`) rather than plain `"Loading posts..."` text.
- **D-06:** Spinner adoption remains bounded by sparseness constraints: no visible row growth and no protected-region fill.

### Render-path purity and cache boundaries

- **D-07:** Enforce strict render purity: no state writes inside any `defp render_*`.
- **D-08:** Mutations remain limited to non-render paths (`load_posts`, `advance_post`, `scroll_post`, cache/viewport warm helpers) with tests guarding this boundary.

### the agent's Discretion

- Exact spinner placement and style details that satisfy row/region constraints.
- Exact test additions to prove callback contracts and purity boundaries.
- Exact helper extraction/refactor shape that keeps diffs minimal and behavior stable.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase scope and requirements

- `.planning/workstreams/phase-03-screen-audit/ROADMAP.md` — Phase 9 goal, sequencing, and success criteria.
- `.planning/workstreams/phase-03-screen-audit/REQUIREMENTS.md` — `READER-01..07` plus inherited `AUDIT-05..22`.
- `.planning/workstreams/phase-03-screen-audit/STATE.md` — current workstream status and inherited decisions.

### Prior phase context to inherit

- `.planning/workstreams/phase-03-screen-audit/phases/00-cross-cutting-extractions-prelude/00-CONTEXT.md` — helper contracts.
- `.planning/workstreams/phase-03-screen-audit/phases/06-threadlist/06-CONTEXT.md` — domain callback and correctness-fix discipline.
- `.planning/workstreams/phase-03-screen-audit/phases/08-postcomposer/08-CONTEXT.md` — recent audit guardrail framing and branch-parity approach.

### Research and architecture

- `.planning/workstreams/phase-03-screen-audit/research/ARCHITECTURE.md` — section order and PostReader-specific deviation rules.
- `.planning/workstreams/phase-03-screen-audit/research/PITFALLS.md` — render purity and source-order landmines.
- `.planning/workstreams/phase-03-screen-audit/research/SUMMARY.md` — final-phase expectations and risk profile.

### Target implementation files

- `lib/foglet_bbs/tui/screens/post_reader.ex` — audited screen.
- `test/foglet_bbs/tui/screens/post_reader_test.exs` — primary behavior/contract test surface.
- `lib/foglet_bbs/tui/widgets/post/post_card.ex` — author/body rendering pipeline dependency.
- `lib/foglet_bbs/tui/widgets/post/markdown_body.ex` — markdown render dependency.
- `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex` — loading/render integration boundary.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- `Domain.get/2` is already used in PostReader and can be normalized across remaining paths.
- `Theme.from_state/1` is already in place for render-path theming.
- `Viewport` state model already encapsulates scroll behavior and supports prewarming.

### Established Patterns

- PostReader currently separates render-time reads from state-mutation helpers and must preserve that split.
- Public callback functions are invoked by `TUI.App.update/2` command handling, not direct screen-key dispatch.
- Read-pointer flush and post loading are lifecycle hooks and must remain stable during navigation transitions.

### Integration Points

- `{:load_posts, ...}` and `{:flush_read_pointers, ...}` command tuples bridge PostReader with App update loop.
- Spinner behavior must coexist with existing ScreenFrame layout and keybar without expanding vertical density.
- Cache/viewport warm behavior must continue to avoid reparse churn and first-scroll clamping glitches.

</code_context>

<specifics>
## Specific Ideas

- Preserve existing navigation semantics (`n/p`, `j/k`, `Space`, `r`, `q`) while refactoring internals.
- Keep final-phase bias toward safety: contract clarity and purity checks over novelty.
- Treat spinner adoption as UX signal, not decorative motion.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 09-postreader*
*Context gathered: 2026-04-22*
