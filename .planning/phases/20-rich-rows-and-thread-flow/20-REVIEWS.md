---
phase: 20
reviewers: [codex]
reviewed_at: 2026-04-25T00:00:00Z
plans_reviewed:
  - 20-01-PLAN.md
  - 20-02-PLAN.md
  - 20-03-PLAN.md
  - 20-04-PLAN.md
  - 20-05-PLAN.md
  - 20-06-PLAN.md
codex_model: gpt-5.5
---

# Cross-AI Plan Review — Phase 20: Rich Rows and Thread Flow

## Codex Review

### Summary

Phase 20 is generally well-scoped and the wave structure is sound: Wave 0 encodes the desired failures, Wave 1 builds the reusable widget, Wave 2 migrates `ThreadList`, and Wave 3 gates with precommit and validation. The plans align well with the v1.3 architecture: SSH-first TUI, Chrome V2 untouched, theme slots, Unicode-safe width helpers, and no persistence/context changes. The main risks are test brittleness, a few internal inconsistencies in the proposed `RichRow` implementation, and an important semantic mismatch around THREADS-02: the spec explicitly reframes "focused-thread details" as selection clarity, but the roadmap wording still says focused-thread details should appear. That should be called out as an accepted product decision, not treated as naturally satisfied.

### Strengths

- Strong phase boundary: only `RichRow`, `ThreadList`, and focused tests are in scope.
- Good dependency flow: widget tests precede widget implementation; screen tests precede screen migration; layout smoke precedes final gate.
- Width and theme constraints are explicit and mostly well grounded in existing `TextWidth`, `Theme`, `SelectionList`, and `ListRow` patterns.
- Good avoidance of domain creep: no schema, query, context, authorization, or navigation changes.
- The `RichRow.render/1` API is appropriately generic for later phases by accepting state atoms instead of thread-specific booleans.
- The plans preserve existing metadata formatting and keyboard behavior.
- Manual validation acknowledges terminal font risk for `⚿`, which automated tests cannot fully prove.

### Concerns

- **HIGH — Plan 20-04 implementation has a likely compile/runtime bug.**
  The proposed code includes `^cluster_width = TextWidth.display_width(cluster)` but `cluster_width` is not a variable in scope. There is a private `cluster_width/0` function, but it is not called. `^@cluster_width` is not valid in a pattern either, so use:
  ```elixir
  if TextWidth.display_width(cluster) != @cluster_width do
    raise ...
  end
  ```
  or simply assert via tests and avoid runtime crashing.

- **HIGH — Plan 20-04 likely breaks glyph style assertions for selected rows.**
  The selected branch renders the whole cluster with selected styling, meaning unread/sticky/locked glyphs no longer route through `accent/info/warning` when selected. If tests expect sticky glyph through `theme.info.fg` or locked through `theme.warning.fg`, selected cases will fail or weaken theme-routing guarantees. Decide whether selection overrides glyph colors or only row background. The plan currently says both.

- **HIGH — THREADS-02 is only satisfied by redefining it.**
  The roadmap says "focused-thread details appear without disrupting keyboard navigation." The spec says no details strip and THREADS-02 is satisfied by selection clarity only. That may be acceptable, but it is a requirement interpretation, not an implementation of "focused-thread details." This should be explicitly documented in plan summaries and validation as a scoped reinterpretation.

- **MEDIUM — Plan 20-02 cluster width invariant test is too weak.**
  The proposed screen-level test mostly checks `TextWidth.display_width(flat_locked) > 0` and absence of `[S]`. That does not prove read+plain rows reserve the same leading cluster width as full-state rows. This is not meaningful coverage for the stated acceptance.

- **MEDIUM — Plan 20-03 layout smoke tests may be brittle or not isolate row width.**
  `flatten_text(positioned)` includes chrome, breadcrumbs, key bars, and other text, so asserting glyphs and ellipsis against the whole screen can pass or fail for unrelated reasons. Width checks over every text element are useful, but "total row display width" is not actually asserted unless row text is isolated by coordinates.

- **MEDIUM — Plan 20-01 RED-first expectation may produce compile-time failure that prevents useful test enumeration.**
  If `alias Foglet.TUI.Widgets.List.RichRow` or calls to `RichRow.render/1` produce a compile failure, ExUnit may not report all 19 tests as RED. That is acceptable for a Wave 0 scaffold, but the plan asks to document RED count and named tests. Better to expect either compile failure or undefined function, not a full per-test RED matrix.

- **MEDIUM — `RichRow` generic-state behavior is underpowered for later reuse.**
  Unknown atoms rendering as whitespace means `[:subscribed, :required]` "renders without referencing Threads," but it does not prove the primitive can actually express future BoardList/operator states. The moduledoc says reserved atoms will be added later; that is fine, but the acceptance test should not overclaim reuse.

- **LOW — Plan 20-04 over-documents internal planning decisions in production moduledoc.**
  Including "Honours decisions: D-01…" and detailed phase IDs in a production widget moduledoc may age poorly. Public docs should document behavior, not planning archaeology.

- **LOW — Runtime invariant crash in a render path may be too aggressive.**
  Crashing the TUI because a glyph measures unexpectedly is useful during tests but harsh in production. Prefer compile/test coverage or a private `cluster_width!/1` only exercised in tests.

- **LOW — Plan 20-06 standalone command assumptions may not match aliases.**
  `rtk mix sobelow --exit Low` or `rtk mix format --check-formatted` may not match the repo's actual precommit alias. The plan should read `mix.exs` and follow the project-defined commands rather than assuming exact flags.

### Suggestions

- **Plan 20-04, implementation:** Replace the proposed runtime width pattern match with a safe helper:
  ```elixir
  defp fixed_cluster!(cluster) do
    if TextWidth.display_width(cluster) == @cluster_width do
      cluster
    else
      raise ArgumentError, "RichRow cluster width drifted"
    end
  end
  ```
  Or remove runtime raising and rely on tests.

- **Plan 20-04, styling:** Decide the selection-vs-state precedence explicitly. Recommended: selected row gets `theme.selected.bg` and bold, but glyph foregrounds still use state slots. That preserves both selection clarity and glyph semantics.

- **Plan 20-02, cluster invariant:** Add a helper that extracts the row text for a known title and compares the substring before the title across states using `TextWidth.display_width/1`. Do not use whole-screen width as a proxy.

- **Plan 20-03, layout smoke:** Isolate positioned elements for the thread-list row by y-coordinate or by locating the long title/metadata line, then assert that line's width and content. Whole-screen `flatten_text` is too coarse.

- **Plan 20-01, RED expectations:** Reword the acceptance from "all 19 named tests fail RED" to "the file is present and the targeted test command fails because `RichRow` is missing." That better matches compile-time behavior.

- **Plan 20-04, API:** Consider accepting `metadata: nil | ""` gracefully if future callers do not have metadata. The current contract says required `String.t()`, which is fine for ThreadList, but a reusable row primitive may benefit from `metadata: ""` default.

- **Plan 20-04, docs:** Keep the moduledoc user-facing and move phase-decision details into planning summaries. Production docs should say what the widget does and how to call it.

- **Plan 20-05, state order:** Since `maybe_state/3` prepends, `state_cluster` becomes reversed. RichRow currently maps by membership, so order does not matter. Add a short comment or use a clearer construction:
  ```elixir
  [
    unread? && :unread,
    Map.get(thread, :sticky, false) && :sticky,
    Map.get(thread, :locked, false) && :locked
  ]
  |> Enum.filter(& &1)
  ```

- **Plan 20-06, validation:** Add one validation row explicitly noting THREADS-02 is satisfied by the accepted selection-clarity interpretation, with no details strip in scope.

### Per-Plan Notes

- **20-01:** Good contract coverage, but likely compile-fails before individual tests execute. Adjust RED reporting expectations. Watch for brittle `assert_text_run/3` substring matches.
- **20-02:** Good screen-level intent. The fake locked adapter is useful. The cluster-width test needs strengthening; current version does not prove the contract.
- **20-03:** Valuable smoke coverage, but needs row isolation. Whole-screen flattening can mask regressions or fail due to chrome text unrelated to rows.
- **20-04:** Most attention needed. The proposed implementation has a definite variable bug and unresolved style precedence between selection and state glyphs. Also trim production moduledoc planning references.
- **20-05:** Clean, scoped migration. The helper is reasonable, though the state-list construction can be clearer. Good preservation of `thread_metadata/1` and navigation boundaries.
- **20-06:** Sensible final gate. Make sure the standalone commands reflect the repo's actual aliases, and avoid adding speculative Sobelow/Credo suppressions unless a real warning appears.

### Risk Assessment

**Overall risk: MEDIUM.**
The phase itself is low-risk functionally because it is pure rendering with no persistence or auth changes. The risk rises to medium because the plans contain a likely implementation bug, some brittle tests, and a requirement interpretation around THREADS-02 that could be disputed later. With the Plan 20-04 fixes and stronger row-isolated assertions in Plans 20-02/20-03, this becomes a low-risk phase.

---

## Consensus Summary

Only one external reviewer (Codex / `gpt-5.5`) was selected for this run, so this section condenses Codex's findings into the highest-priority work for the planner rather than synthesizing across reviewers. Re-run `/gsd-review --phase 20 --gemini --claude` (or `--all`) for true cross-AI consensus.

### Top Concerns to Address Before Execution

1. **Fix Plan 20-04's `cluster_width` invariant code path (HIGH).**
   The current `^cluster_width = TextWidth.display_width(cluster)` pattern will not compile. Replace with a guarded helper or move the invariant to tests only.
2. **Resolve selection-vs-state-glyph precedence in Plan 20-04 (HIGH).**
   Decide explicitly whether selection styling overrides glyph foregrounds or only row background. Recommend: glyph foregrounds keep state slots; selection only changes background+bold.
3. **Document THREADS-02 reinterpretation in Plan 20-06 / 20-VALIDATION.md (HIGH).**
   The spec satisfies THREADS-02 via selection clarity rather than a focused-details strip; this divergence from roadmap wording must be recorded as an accepted decision.
4. **Strengthen the cluster-width invariant test in Plan 20-02 (MEDIUM).**
   Prove leading-cluster width is identical across read/plain and unread/sticky/locked rows by isolating the row substring, not by measuring the entire screen.
5. **Isolate row content in the Plan 20-03 layout smoke tests (MEDIUM).**
   Use coordinates or row identification to assert row width and content; whole-screen `flatten_text` is too coarse and lets chrome text leak into the assertion.
6. **Re-word Plan 20-01's RED-first acceptance (MEDIUM).**
   Compile failure on the missing `RichRow` module will short-circuit per-test enumeration; accept "module missing → test command fails" rather than per-test counts.

### Lower-Priority Cleanups

- Strip planning archaeology (D-01 references, phase IDs) from `RichRow`'s production moduledoc (LOW).
- Soften the runtime invariant crash to a test-only assertion (LOW).
- Verify Plan 20-06 commands match the actual `mix.exs` precommit alias before execution (LOW).
- Clarify state-list construction in Plan 20-05's `maybe_state/3` helper.
- Optionally accept `metadata: nil | ""` as a default in `RichRow` for non-ThreadList callers.

### Open Questions for the Planner

- Should `RichRow` validate the cluster-width invariant at runtime, in tests only, or both? Codex prefers tests-only or guarded helper.
- Should `RichRow` default `metadata: ""` to enable BoardList/operator reuse without breaking the current contract?
- Should the validation log explicitly note THREADS-02 as a scoped reinterpretation rather than a satisfied requirement?
