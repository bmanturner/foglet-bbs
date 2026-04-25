---
phase: 21
reviewers: [codex]
reviewed_at: 2026-04-25T21:23:55Z
plans_reviewed:
  - 21-01-PLAN.md
  - 21-02-PLAN.md
  - 21-03-PLAN.md
  - 21-04-PLAN.md
---

# Cross-AI Plan Review — Phase 21

## Codex Review

## Summary

Overall, the four-plan sequence is well decomposed and mostly implementable: 21-01 isolates the data prerequisite, 21-02/21-03 use a clear RED/GREEN widget contract, and 21-04 handles screen integration plus smoke coverage. The main risks are contract drift around `RichRow`, over-coupling `BoardList` to `BoardTree`'s internal `Display.Tree`, and a few tests that assert less than the stated acceptance criteria. I would not call the plan blocked, but I would tighten several items before execution.

## Strengths

- Clear wave ordering: data layer and widget contract first, widget implementation second, screen migration last.
- `last_post_at` query strategy is sound: rooted on `Board`, left join filter in the join condition, grouped aggregate, no per-board query.
- Good preservation of existing workflows and feedback strings in 21-04.
- Dedicated `BoardTree` wrapper is the right direction for BOARDS-04; it avoids mutating generic `Display.Tree`.
- Plans correctly identify key pitfalls: `TimeAgo.format(nil)`, deleted threads, Phase 20 dependency, and fixture drift.
- Test placement is appropriate: context tests in `boards_test`, widget tests beside list widgets, integration tests in `board_list_test`, layout tests in `layout_smoke_test`.

## Concerns

- **[HIGH 21-03] Subscription glyph theme routing is promised but not actually achieved.**
  The proposed `BoardTree` passes `"⚿ name"`, `"✓ name"`, or `"+ name"` as a plain `RichRow` title string. Unless `RichRow` supports styled title fragments, `BoardTree` cannot route `⚿` to `theme.warning`, `✓` to `theme.info`, and `+` to `theme.dim` independently. This violates D-10b despite the source containing no hardcoded color atoms.

- **[HIGH 21-02/21-03/21-04] Read-state contract says `◆/◇`, but tests and implementation only require `◆` or absence.**
  BOARDS-01 says users distinguish read/unread boards visually, and 21-02 must-haves mention `◆/◇`. The actual scaffold only asserts unread has `◆` and read lacks `◆`. If the intended read marker is `◇`, lock it in tests and implementation. If whitespace is acceptable, update the plan language and success criteria.

- **[MEDIUM 21-04] `BoardList` couples to `BoardTree` internals.**
  Pattern matching `%BoardTree{tree: %Display.Tree{raxol_state: ...}}` makes `BoardList` depend on internal storage and Raxol state shape. This is the fragility called out in Pitfall 5. A small `BoardTree.focused_data/1` or `BoardTree.focused_board_entry/1` API would preserve encapsulation and simplify 21-04.

- **[MEDIUM 21-04] Layout smoke overlap assertion is too weak.**
  "No two text elements share `{x, y}`" does not catch overlapping spans at different `x` positions on the same row. It should compare intervals `{x, x + display_width(text)}` for each `y`.

- **[MEDIUM 21-04] The layout-smoke seam is explicitly uncertain.**
  The plan includes two possible approaches for injecting fake board data. That uncertainty should be resolved before execution by reading the existing `layout_smoke_test.exs` seam and specifying the exact fixture pattern. Otherwise this plan may burn time during implementation.

- **[MEDIUM 21-01] Tests pattern-match the whole directory too tightly.**
  Assertions like `[%{boards: [entry]}] = directory` assume only one category/board appears. If fixtures or default setup introduce additional rows, tests become brittle. Prefer locating the entry by `board.id`.

- **[MEDIUM 21-02/21-04] Time-based assertions are brittle.**
  `@ten_min_ago DateTime.add(DateTime.utc_now(), -600, :second)` at module compile time plus exact `"10m"` assertions can drift to `"11m"` in slower runs. Use runtime timestamps inside fixture functions, freeze time if the project has a helper, or assert a controlled timestamp through `TimeAgo.format/1`.

- **[MEDIUM 21-03] Size math in context and implementation disagree on indent/cluster assumptions.**
  D-05 assumes indent 4 and cluster 2, while the proposed implementation uses `depth * 2` indent and `RichRow` has `@cluster_width = 4`. The 64-cell budget probably still holds, but the plan should recalculate against actual `RichRow` width, focus marker, and `BoardTree` indent.

- **[LOW 21-02] RED scaffold claims all failures are due to missing module, but one test fails because the source file is missing.**
  That is acceptable RED behavior, but the acceptance text should not require every failure to be `UndefinedFunctionError`.

- **[LOW 21-02] Negative text-label assertion is weaker than stated.**
  The test only rejects bracketed labels, not the words `required`, `subscribed`, or `subscribe` as standalone row words. If that matters, use word-boundary regexes on board rows.

- **[LOW 21-03] Category rows lack width/truncation coverage.**
  Category names can still overflow at narrow widths. Phase 21 focuses board rows, but a long category name should be sliced or covered by smoke tests.

## Suggestions

- Add a `BoardTree.focused_entry/1` or `focused_board_entry/1` function and have `BoardList` use that instead of reaching into `%BoardTree{tree: %Display.Tree{...}}`.

- Decide explicitly whether read boards render `◇` or blank space. Then update 21-02, 21-03, 21-04 must-haves and tests to match.

- Reconcile subscription glyph styling. Either:
  - extend/use `RichRow` support for styled title fragments, or
  - drop the claim that each glyph routes through its own theme slot and document that the title uses row-level styling.

- Resolve the `layout_smoke_test.exs` fixture seam before implementation and replace the "if existing seam requires…" language with a concrete pattern.

- Make data-layer tests find the target board entry by ID rather than destructuring the whole directory.

- Replace exact `"10m"` / `"2h"` assertions with `TimeAgo.format(fixed_dt)` values or regex expectations tied to controlled timestamps.

- Strengthen layout overlap detection to check horizontal spans per row, not just duplicate start coordinates.

- Add a Phase 20 preflight at the start of 21-02 or 21-03: confirm `RichRow.render/1` signature, title truncation, metadata behavior, cluster width, and focus marker before locking tests.

## Risk Assessment

**Overall risk: MEDIUM.**

The architecture is directionally strong and the plan is detailed enough to execute, but several contract mismatches could cause churn: `RichRow` may not support the intended glyph styling, `BoardList` depends on `BoardTree` internals, and the tests do not fully lock some stated visual requirements. The data-layer portion is low risk; most risk sits in TUI rendering contracts and integration tests. Once the read-state glyph decision, theme-routing reality, and layout-smoke seam are tightened, this should become a low-to-medium risk phase.

---

## Consensus Summary

Single reviewer (Codex) — no cross-reviewer consensus available. The summary below restates the highest-priority items the planner should address before `/gsd-execute-phase 21`.

### Top Concerns To Address

1. **[HIGH 21-03] Subscription glyph theme routing is unachievable as designed** — passing `"⚿ name"` as a single `RichRow` title string cannot independently theme the glyph (warning) vs. the name (default). Either extend RichRow with styled title fragments, or formally drop D-10b's per-glyph theme routing and document that the prefix inherits row-level fg.

2. **[HIGH 21-02/21-03/21-04] Read-state read-marker glyph (`◇`) is undefined in tests/implementation** — only `◆` (unread) and absence are locked. CONTEXT and ROADMAP imply `◇` for read boards; if so, lock it across all three plans. If whitespace is intended, amend the language.

3. **[MEDIUM 21-04] `BoardList` reaches into `%BoardTree{tree: %Display.Tree{raxol_state: ...}}`** — add `BoardTree.focused_board_entry/1` (or `focused_entry/1`) so the screen does not depend on Raxol's internal state shape (Pitfall 5 fragility).

4. **[MEDIUM 21-04] Layout-smoke fixture seam is left ambiguous** — the plan offers two patterns ("if the existing seam requires…"). Resolve by reading the existing thread_list size-contract block in `layout_smoke_test.exs` before execution and pinning the exact pattern.

5. **[MEDIUM 21-04] Layout overlap assertion checks only duplicate `{x,y}` start coords, not horizontal spans** — strengthen to interval-based per-row collision detection (`{x, x + display_width(text)}`).

6. **[MEDIUM 21-02/21-04] Compile-time `DateTime.utc_now()` fixtures with exact `"10m"`/`"2h"` assertions are clock-flaky** — move timestamps into runtime setup blocks or use a frozen-time helper / regex.

7. **[MEDIUM 21-03] Size math reconciliation** — CONTEXT D-05 assumes cluster=2, indent=4; implementation uses depth×2 indent and RichRow @cluster_width=4. Recalculate the 64-cell budget against the actual constants before locking 21-02 width assertions.

8. **[MEDIUM 21-01] Tests destructure full directory `[%{boards: [entry]}]`** — brittle if fixtures grow; locate by `board.id` instead.

### Suggested Pre-Execution Adjustments

- Add a Phase 20 RichRow preflight to 21-02 or 21-03 (signature, title truncation, cluster width, focus marker, theme routing of title) before locking the RED contract.
- Add a `BoardTree.focused_board_entry/1` API and consume it from `BoardList` (resolves concern 3 and trims 21-04 Task 1).
- Resolve the `◇` read-marker question explicitly in CONTEXT (or add a discretion note that whitespace is acceptable).
- Add a category-row long-name truncation case to either 21-02 or the 21-04 layout-smoke block.
- Replace `[%{boards: [entry]}] = directory` patterns with id-based lookup in 21-01 tests.

### Divergent Views

N/A — single reviewer.

---

*Generated via /gsd-review --phase 21 --codex on 2026-04-25.*
*Feed back into planning: `/gsd-plan-phase 21 --reviews`.*
