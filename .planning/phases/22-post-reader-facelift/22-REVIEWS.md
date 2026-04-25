---
phase: 22
reviewers: [claude]
reviewed_at: 2026-04-25T21:31:36Z
plans_reviewed:
  - .planning/phases/22-post-reader-facelift/22-01-PLAN.md
  - .planning/phases/22-post-reader-facelift/22-02-PLAN.md
  - .planning/phases/22-post-reader-facelift/22-03-PLAN.md
---

# Cross-AI Plan Review - Phase 22

## Claude Review

# Phase 22 Plan Review - Post Reader Facelift

## Summary

The three-plan set is well-structured, follows established v1.3 facelift patterns (Phase 16/19/20/21 precedents), and respects the locked CONTEXT decisions D-01 through D-16. The TDD-first sequencing (widget contract -> screen integration -> layout smoke + precommit) is sound and matches the project's prior phases. The main risks live in three areas: (1) the body-width budget contract between `reader_parts` and the parallel `warm_viewport` path, (2) under-specified `available_height` recomputation when adding two fixed reader rows at 64x22, and (3) loose guidance around an optional segmented progress indicator that could leak scope. None are blockers; all are tightenable in the plans before execution.

---

## Plan 22-01: PostCard Reader Helper

### Strengths

- Clear locked-contract truth list maps every D-decision to a testable artifact.
- Acceptance criteria use string-pattern checks the executor can verify mechanically.
- Threat model correctly rules in T-22-01/02/03 with proportionate mitigations.
- Reuses `get_handle/1`/`get_time_ago/1` rather than reinventing extraction.
- Pitfall 2 (gutter flattening markdown) is addressed by mandating row-element wrapping rather than stringification.

### Concerns

- **MEDIUM - Body-width budget contract is implicit.** The plan says "compute a body width budget with `TextWidth.display_width(gutter)`" but does not define a single function whose width-budget math is shared between `reader_parts/5` and any direct `render_body_lines/4` callers. Plan 22-02 needs `warm_viewport/4` to produce the same body-line list; if `warm_viewport` calls `render_body_lines(..., gutter: true)` directly while `reader_parts` does additional pre-computation, line counts could drift between render and scroll-clamp paths (Pitfall 4 in research).
- **MEDIUM - Optional segmented progress is not decided.** The plan permits but doesn't decide on segment glyphs. Open Question 1 in RESEARCH.md recommends shipping compact text first. Leaving this open invites scope creep in execution and makes acceptance criteria ambiguous.
- **LOW - Existing `render_body_lines/4` opts contract is "ignored".** The current test (`post_card_test.exs:176-188`) asserts that opts are ignored. Adding `gutter:`/`gutter_char:` keys is technically additive and should not break that test, but the contract docstring at `post_card.ex:99-102` says "the `opts` keyword is accepted for signature parity ... but has no effect". This docstring needs updating; otherwise readers will be surprised by the new gutter behavior.
- **LOW - `@spec` for `reader_parts/5` mandates `pos_integer()` width but no minimum-width safety.** At width = 1 with gutter=true, body width budget collapses to 0 and the `max(_, 1)` floor matters. The acceptance test for 64x22 won't exercise this, but a small-width property test would harden Pitfall 3.

### Suggestions

- Add a private helper such as `reader_body_lines(tuples, width, theme)` that is the single source of truth for gutter+body-width math, called from both `reader_parts/5` and any other path that warms `Viewport.children`.
- Decide explicitly: "Compact text only in Phase 22; segmented bar deferred to follow-up." Drop the optional-segment branch from Task 2's action language.
- Update the `render_body_lines/4` `@doc` to reflect the new `gutter:` opt instead of saying opts have no effect.
- Add one unit test that calls `reader_parts/5` with a missing handle, missing `inserted_at`, and missing `message_number` to verify graceful fallbacks (D-05 mentions degradation but only normal path is locked in tests).

### Risk: **LOW**

Self-contained widget change with strong test coverage and reuse of vetted helpers.

---

## Plan 22-02: PostReader Integration

### Strengths

- Preserves the high-risk surfaces (`handle_key/2`, `advance_post/2`, `scroll_post/2`, `flush_read_pointers/2`) explicitly in the action contract.
- Source-static assertion (Task 1) for `PostCard.reader` enforces D-04/READER-04 even if a future contributor adds new screen-local header text.
- Negative acceptance ("no longer contains `PostCard.author_line(post)` in `render_post_content/5`") is a strong regression guard.
- Threat model correctly elevates T-22-03 (read-pointer regression) to HIGH.

### Concerns

- **HIGH - `warm_viewport/4` body-line consistency is under-specified.** The plan says "use the same body-line helper/path as render so `scroll_post/2` and render agree on content height." But the current implementation at `post_reader.ex:455-463` calls `PostCard.render_body_lines(tuples, w, theme)` with full width and no gutter. After Phase 22, render uses guttered body lines via `reader_parts`. If `warm_viewport` is updated piecemeal (e.g., adds `gutter: true` but keeps full `w`), `Viewport.content_height` will exceed render's actual line count and `scroll_post/2` will let the user scroll past the visible last line. Pitfall 4 explicitly warns about this. The action language should mandate that both paths derive `body_lines` from the same function call shape (same `width`, same `gutter` flag, same theme).
- **MEDIUM - `available_height` recomputation is wishy-washy.** Current baseline is `max(h - 10, 5)`. Phase 22 adds two fixed rows (header + progress). The plan says "choose `max(h - 11, 5)` only if needed". At 64x22, h=22 -> current baseline = 12, after Phase 22 the body should be ~10 rows. `max(h - 12, 5)` is the honest budget. "Only if needed" defers a known math question to executor judgment and risks command-bar collision (Pitfall 5).
- **MEDIUM - Loading-state path is silent.** `render_loading/1` (`post_reader.ex:137`) renders a Spinner. Phase 22 does not change loading visuals, but the new screen-level test should explicitly confirm the Phase 22 facelift does not alter the spinner path. Existing tests at `post_reader_test.exs:148-164` assert "Loading..." - should still pass, but worth listing as a preservation truth.
- **MEDIUM - Test fixture's `inserted_at` may produce flaky age tokens.** Task 1 says "an inserted_at value close enough that `Foglet.TimeAgo.format/1` returns a short token." A relative time helper based on `DateTime.utc_now()` will return different tokens (`0s`, `1m`, `2h`) depending on CI clock and test ordering. Use a fixed offset like `DateTime.add(DateTime.utc_now(), -5 * 60, :second)` to deterministically yield `5m`.
- **LOW - `parts.body_lines` acceptance string check** in the criteria assumes the executor literally writes `parts.body_lines` rather than destructuring `%{body_lines: body_lines} = parts` or pattern matching. The intent is clear but the static check is brittle.

### Suggestions

- Replace the "use the same body-line helper" guidance with: "Refactor `warm_viewport/4` to call `PostCard.reader_parts(post, tuples, w, theme, index: idx, total: total).body_lines` (or a shared private helper), so render and warm produce byte-identical body-line lists."
- Hard-code `available_height = max(h - 12, 5)` (or whatever number is correct after counting fixed rows: top chrome, breadcrumb, header, progress, divider, command bar). Layout smoke at 64x22 will reveal if it's wrong.
- Use a fixed `inserted_at` offset in test fixtures to avoid time-flakiness.
- Loosen the static check from `parts.body_lines` to a regex like `body_lines\s*=` or `:body_lines\s*=>` so destructuring is acceptable.

### Risk: **MEDIUM**

The render/warm consistency contract is the highest-leverage failure mode and the plan's language allows it to slip through.

---

## Plan 22-03: Layout Smoke + Precommit

### Strengths

- Dimension triple `[{64,22},{80,24},{132,50}]` matches Phase 18/19/20/21 precedent.
- Asserts both content presence (sentinel strings) and bounds-respect (positioned overflow check).
- Adjacent-element non-overlap assertion mirrors the strong Phase 19 pattern (`layout_smoke_test.exs:629-645`).
- Header-above-body and progress-doesn't-collide-with-commands are the right ordering invariants.

### Concerns

- **MEDIUM - "Selected body sentinel" must survive viewport slicing.** With `selected_post_index: 2` and `available_height` budget around 5 rows at 64x22, the sentinel must appear in the first body line of post 3 to be visible. The fixture should put `Selected body sentinel` as the first line of the selected post's body, not buried in markdown. The plan's action language should explicitly state this.
- **MEDIUM - Real `Foglet.Markdown.render/1` is invoked in setup.** `session_context: %{theme: ...}` lacks `:domain`, so `parse_body/2` falls back to the real markdown parser. That's fine for a plain sentinel string, but if the body contains characters the parser tokenizes (asterisks, backticks, hashes), the rendered tree will differ from naive expectations. Use plain ASCII for sentinels.
- **MEDIUM - Breadcrumb at 64x22 may truncate.** Chrome V2 breadcrumb (`Foglet -> Boards -> General -> Reader Contract`) plus right status atoms can press against width budget. The smoke test should not assert breadcrumb text content (delegated to Phase 18 tests), only positioned-bounds for whatever breadcrumb renders.
- **LOW - Task 2 acceptance criteria over-specify precommit substeps.** The plan lists `mix format --check-formatted`, `mix credo`, `mix sobelow`, `mix dialyzer` as separate exit-0 gates. `rtk mix precommit` already runs all of these per AGENTS.md; the explicit list creates churn if precommit's internal command set changes.
- **LOW - `FogletBbs.DataCase, async: false` is heavyweight for a render-only test.** Existing layout smoke uses DataCase for Config seeding; that's why the new block inherits it. Not a blocker, but it does mean the test depends on Postgres being available. Worth noting in the action language so the executor doesn't strip DataCase.

### Suggestions

- Specify exactly: "Selected post (index=2, message_number=33) has `body: \"Selected body sentinel\n\nMore content here.\"`. Other posts can have any short body."
- Drop the per-step precommit acceptance items; keep only `rtk mix precommit` exits 0.
- Add an explicit assertion that the command-bar text (e.g., `Next`, `Back`, or one of the keys from `post_reader.ex:73-79`) appears at the bottom-most occupied row - this is the strongest check that progress didn't displace commands.
- Consider asserting that `Posts 3/12` appears at a y-coordinate strictly between header.y and command-bar.y (i.e., progress is in the right vertical band).

### Risk: **LOW**

Pure verification work with no behavioral changes; concerns are about test robustness, not correctness.

---

## Cross-Cutting Observations

- **Render/warm consistency is the linchpin.** A single `reader_parts` (or a shared private body-line function) used in both `render_post_content/5` and `warm_viewport/4` eliminates an entire class of bugs. This should be elevated from "should" to "must" in 22-02.
- **The "optional segmented progress" decision should be made at planning time, not execution time.** Defer it.
- **Plan type metadata is inconsistent.** 22-01 is `type: tdd`, 22-02 is `type: execute` despite its first task being explicitly test-first. Consider marking 22-02 as `tdd` for clarity.
- **No memory-of-prior-incidents check.** Plan 20 review history (referenced in research) flagged whole-screen flat-text width assertions as weak. Plan 22-03's per-element bounds check is stronger. Good - but the plan could explicitly call out that lesson to prevent regression.
- **Time-flaky test fixtures recur across plans.** Both 22-02 and 22-03 build fixtures with `DateTime.utc_now()`-derived timestamps. Standardize on fixed offsets.

## Overall Risk Assessment: **MEDIUM**

The plan set will likely succeed on first execution, but the render/warm body-line contract (Plan 22-02) and `available_height` budget under-specification are subtle enough to produce post-merge bugs that only surface during real SSH use at 64x22 - exactly the dimension Phase 22 is supposed to harden. Tightening 22-02's body-line consistency requirement from "use the same helper" to "call the same function with the same arguments" and pinning `available_height = max(h - 12, 5)` would drop the risk to LOW.

---

## Consensus Summary

This run used a single external reviewer (`claude`), so the summary below is a synthesis of that review rather than multi-reviewer consensus.

### Agreed Strengths

- The three-plan sequence is sound: widget contract first, screen integration second, layout smoke and precommit verification third.
- The plans generally respect Phase 22 boundaries and preserve important existing behavior around viewport ownership, navigation, read-pointer flushing, and markdown rendering.
- The test strategy is mostly well aligned with the 64x22 minimum terminal contract and prior v1.3 facelift patterns.

### Agreed Concerns

- `warm_viewport/4` and render-time body-line construction must share the exact same body-line path and arguments, otherwise scroll height can drift from rendered body height.
- The `available_height` budget should be pinned during planning rather than left to executor judgment.
- Optional segmented progress should be deferred or explicitly decided before execution to avoid scope creep.
- Tests that rely on relative timestamps or deeply buried body sentinels could become flaky or miss the intended contract.

### Divergent Views

- None. Only one external reviewer was invoked for this run.
