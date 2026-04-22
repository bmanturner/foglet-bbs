---
phase: 09-postreader
verified: 2026-04-22T14:30:00Z
status: gaps_found
score: 4/7 must-haves verified
overrides_applied: 0
gaps:
  - truth: "READER and inherited AUDIT rubric gates pass with mix precommit."
    status: failed
    reason: "AUDIT-05 Gate 7 fails: {80, 24} appears inline 5 times in post_reader.ex without a @default_terminal_size module attribute. Phases 7 (new_thread.ex) and 8 (post_composer.ex) both added @default_terminal_size as part of their audits. ROADMAP Phase 9 SC-6 explicitly requires grep gates #7/#8/#9 to return zero."
    artifacts:
      - path: "lib/foglet_bbs/tui/screens/post_reader.ex"
        issue: "Lines 62, 155, 216, 429, 468: `state.terminal_size || {80, 24}` appears inline. @default_terminal_size attribute missing."
    missing:
      - "Add `@default_terminal_size {80, 24}` module attribute near top of post_reader.ex (after aliases, before @spec)."
      - "Replace all occurrences of `state.terminal_size || {80, 24}` with `state.terminal_size || @default_terminal_size`."
  - truth: "READER and inherited AUDIT rubric gates pass with mix precommit."
    status: failed
    reason: "AUDIT-16 line-count delta violated: file grew from 449 to 502 lines (+53). AUDIT-16 requires equal-or-lower. The SUMMARY acknowledges the increase ('purely documentation/comments') but provides no developer override. REGISTER-05 set the precedent: any line-count increase requires an explicit developer override recorded in the VERIFICATION.md frontmatter and REQUIREMENTS.md. No such override exists here."
    artifacts:
      - path: "lib/foglet_bbs/tui/screens/post_reader.ex"
        issue: "Pre-phase: 449 lines. Post-phase: 502 lines. Delta: +53. AUDIT-16 permits zero or negative delta only."
    missing:
      - "Either: (a) trim the +53 increase by condensing moduledoc prose and @doc audit notes to stay at or under 449 lines, OR"
      - "(b) obtain a developer override decision documented in REQUIREMENTS.md (mirroring the REGISTER-05 precedent: 'line count deviation accepted (developer override YYYY-MM-DD — <reason>)') and carry the override into this VERIFICATION.md frontmatter."
  - truth: "READER and inherited AUDIT rubric gates pass with mix precommit."
    status: failed
    reason: "AUDIT-19 violated: PostReader has state stored at `state.screen_state[:post_reader]` (three keys: selected_post_index, viewport, render_cache), but exposes no public `init_screen_state/1` function. The AUDIT-19 exemption path ('document as intentionally stateless') does not apply — the screen IS stateful. Every other stateful screen in the codebase exposes this function: board_list, thread_list, verify, new_thread, register, post_composer, login. ROADMAP Phase 9 SC-6 explicitly lists 'init_screen_state/1 AUDIT-19 present or intentional-stateless documented' as a success criterion."
    artifacts:
      - path: "lib/foglet_bbs/tui/screens/post_reader.ex"
        issue: "defp default_screen_state/0 exists (private) but no public @spec init_screen_state(keyword()) :: map() function. `PostComposer.init_screen_state/1` is already called from handle_key/2 at line 158, demonstrating the correct pattern."
    missing:
      - "Rename or wrap `defp default_screen_state/0` as `def init_screen_state(_opts \\ [])` (public), add `@spec init_screen_state(keyword()) :: map()`. The existing `get_screen_state/1` caller merges defaults over existing state — that path is unchanged. Only the default-state constructor needs to be exposed."
      - "Add `init_screen_state/1` to the @moduledoc 'Screen state' section noting it returns the default screen_state map."
---

# Phase 09: PostReader Verification Report

**Phase Goal:** Close READER-01..07 and inherited AUDIT-05..22 for the PostReader screen, completing the screen audit workstream
**Verified:** 2026-04-22T14:30:00Z
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | PostReader loading states render a spinner-based loading affordance without increasing visible row count (per D-05, D-06). | VERIFIED | `Spinner.render/2` used at `post_reader.ex:128`; `render_loading/1` wraps it in a single-row `column/row` composition. SUMMARY confirms row count unchanged (one row, same density). |
| 2 | PostReader retains helper-based domain resolution with existing fallbacks for posts/boards/threads/markdown (per D-01, D-02). | VERIFIED | `Domain.get(ctx, :posts)` at line 209, `:boards` at 264, `:threads` at 270, `:markdown` at 361. Fallbacks `Foglet.Posts`, `Foglet.Boards`, `Foglet.Threads`, `Foglet.Markdown` all present. AUDIT-05 gates #8 and #9 pass (zero inlined theme/domain extraction). |
| 3 | Public callback functions `load_posts/2` and `flush_read_pointers/2` remain intentional contract surface with explicit dead-code-audit evidence (per D-03, D-04). | VERIFIED | Both functions carry `@doc` sections with "Dead-code audit (READER-02, D-03, D-04)" text at lines 196-202 and 249-255. Test file has ownership comments at lines 101 and 173 (`# intentional callback surface (READER-02, D-03, D-04)`). |
| 4 | Render helpers remain mutation-free (`defp render_*` has no state writes) while cache and viewport writes stay in non-render helpers (per D-07, D-08). | VERIFIED | AWK scan of `defp render_*` bodies finds zero `put_in(`, `%{state \|`, or `Map.put(` occurrences. Static source inspection test in `post_reader_test.exs` at line 234 enforces this at test time. |
| 5 | PostReader moduledoc explicitly documents the load-absorb behavior for navigation/scroll keys during loading. | VERIFIED | `@moduledoc` "Load-absorb behavior" section at lines 11-18 documents `advance_post/2` and `scroll_post/2` returning `{:update, state, []}` when `posts == [] or nil`. AUDIT-18 deviation note included. |
| 6 | READER and inherited AUDIT rubric gates pass with `mix precommit`. | FAILED | Three AUDIT rubric gates fail — see Gaps Summary below. |
| 7 | (Implicit per ROADMAP SC-1) PostCard + Viewport pipeline unchanged; render_cache warms on first render and hits on re-renders; read pointers flush on screen exit. | VERIFIED | `render_post_content/5` pipeline unchanged. 40/40 tests pass including cache warm/hit tests, Q-flush test, and seed-fixture smoke tests. |

**Score:** 4/7 truths verified (truths 1-5 pass individually; truth 6 fails on 3 sub-gates; truth 7 passes)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/foglet_bbs/tui/screens/post_reader.ex` | Spinner loading, moduledoc sections, callback audit docs, render purity | PARTIAL | Spinner present; moduledoc expanded; callback @doc audit notes present; render purity enforced. Missing: `@default_terminal_size` attribute, public `init_screen_state/1`. Line count +53 violates AUDIT-16. |
| `test/foglet_bbs/tui/screens/post_reader_test.exs` | Loading render tests, callback ownership evidence, purity guard, load-absorb tests | VERIFIED | `describe "render/1 loading state"` at line 115 confirmed. Callback ownership comments at lines 92-98. Purity guard static test at line 233. Load-absorb describe block at line 194 (6 tests). All 40 tests pass. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `post_reader.ex` | `lib/foglet_bbs/tui/widgets/progress/spinner.ex` | `render_loading/1` composition | WIRED | `alias Foglet.TUI.Widgets.Progress.Spinner` at line 52; `Spinner.render(frame, style: :line, theme: theme)` at line 128. |
| `post_reader.ex` | `lib/foglet_bbs/tui/screens/domain.ex` | Domain helper fallback branches | WIRED | 4 `Domain.get(ctx/sc, :key)` call sites at lines 209, 264, 270, 361. Each has an `{:error, :not_configured}` fallback. |
| `post_reader_test.exs` | `post_reader.ex` | Loading/callback/purity assertions | WIRED | `PostReader.load_posts/2` called at lines 102, 107; `PostReader.flush_read_pointers/2` at line 185; `PostReader.render/1` at multiple describe blocks. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `post_reader.ex` (render_loading path) | `frame` (spinner frame index) | `System.monotonic_time/1` + `Spinner.frame_duration_ms/0` | Yes — monotonic time is real | FLOWING |
| `post_reader.ex` (render_post_content path) | `posts` | `state.posts` populated by `load_posts/2` via `posts_mod.list_posts/1` | Yes — domain module query | FLOWING |
| `post_reader.ex` (render_cache) | `render_cache[{post.id, w}]` | `warm_cache/4` via `parse_body/2` via `markdown_mod.render/1` | Yes — domain module call | FLOWING |

### Behavioral Spot-Checks

Tests are the runnable check path for this phase. No standalone CLI entry points.

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| 40 tests pass | `mix test test/foglet_bbs/tui/screens/post_reader_test.exs` | 40 tests, 0 failures | PASS |
| Spinner + Loading… present in render_loading/1 | `rg -n 'Spinner\.render\|Loading…' lib/foglet_bbs/tui/screens/post_reader.ex` | Lines 128-129 match | PASS |
| Domain.get 4 call sites present | `rg -n 'Domain\.get\(' lib/foglet_bbs/tui/screens/post_reader.ex` | Lines 209, 264, 270, 361 | PASS |
| AUDIT-05 gates #8 and #9 (inlined theme/domain extraction) | `rg` gate patterns | Zero matches | PASS |
| AUDIT-05 gate #7 ({80, 24} inline) | `rg '\{80, 24\}' lib/.../post_reader.ex` | 5 matches — GATE FAILS | FAIL |
| Render purity: no writes in defp render_* | AWK scan for put_in/Map.put/state mutation | 0 violations | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| READER-01 | 09-01-PLAN | Theme + domain lookups use Phase 0 helpers (3 call sites) | SATISFIED | `Domain.get/2` at all 4 domain call sites; `Theme.from_state/1` in `render/1`. Gates #8/#9 pass. |
| READER-02 | 09-01-PLAN | `load_posts/2` and `flush_read_pointers/2` dead-code audit | SATISFIED | Both kept public. @doc audit notes at lines 196-202 and 249-255. Documented as intentional contract surface. |
| READER-03 | 09-01-PLAN | Loading text → spinner (AUDIT-10) | SATISFIED | `Spinner.render/2` in `render_loading/1`. Canonical "Loading…" text. No row-count growth. |
| READER-04 | 09-01-PLAN | PostCard + MarkdownBody + Viewport pipeline kept (inherited decision) | SATISFIED | Pipeline unchanged. Render tests (RENDER-01, RENDER-02) still pass. |
| READER-05 | 09-01-PLAN | Render-path purity: no state writes in `defp render_*` | SATISFIED | AWK scan and static source test both confirm zero violations. |
| READER-06 | 09-01-PLAN | AUDIT-05..22 pass; mix precommit green; low/no size growth | BLOCKED | AUDIT-05 Gate 7 fails ({80,24} inline). AUDIT-16 fails (line +53 without override). AUDIT-19 fails (no public init_screen_state/1). These three sub-items block READER-06. |
| READER-07 | 09-01-PLAN | @moduledoc documents load-absorb pattern (AUDIT-18 deviation) | SATISFIED | "Load-absorb behavior" moduledoc section at lines 11-18. Load-absorb tests at lines 194-224 cover n/p/space/j/k on nil and empty posts. |
| AUDIT-05 (Gates 1-6, 8-9) | Inherited rubric | Grep gates: color atoms, hex literals, ANSI escapes, theme mutation, nested border, IO writes, inlined theme/domain | SATISFIED | All 8 gates pass with zero matches. |
| AUDIT-05 Gate 7 | Inherited rubric | No `{80, 24}` inlined outside `@default_terminal_size` | BLOCKED | 5 inline uses. No `@default_terminal_size` attribute present. |
| AUDIT-06 | Inherited rubric | handle_key clause order; render purity; no modal inspection | SATISFIED | No `state.modal` inspection. handle_key clauses in expected order (n/p/space/j/k/r/q/catch-all). render/1 is pure. |
| AUDIT-07 | Inherited rubric | Widget invocations pass `theme: theme` | SATISFIED | `Spinner.render(frame, style: :line, theme: theme)` at line 128. `PostCard.render_body_lines/3` and `Viewport.render/2` accept theme via pre-themed output. |
| AUDIT-08 | Inherited rubric | ScreenFrame.render wraps content | SATISFIED | `ScreenFrame.render(state, "Thread: #{thread_title}", post_content, [...])` at line 66. |
| AUDIT-10 | Inherited rubric | Spinner adoption evaluation for async loading ops | SATISFIED | Spinner adopted for `load_posts` loading window. Visible row count unchanged (READER-03). |
| AUDIT-11 | Inherited rubric | Canonical "Loading…" phrasing | SATISFIED | "Loading…" at line 129. Test at line 121 asserts canonical text and rejects "Loading posts...". |
| AUDIT-12 | Inherited rubric | Dead-code audit of public load/flush callbacks | SATISFIED | Both callbacks kept public with @doc audit evidence (lines 196-202, 249-255) and test ownership markers. |
| AUDIT-13 | Inherited rubric | Scope fence: only post_reader.ex + test modified | SATISFIED | Commits bd9a51b and 0f585cd touch only `lib/foglet_bbs/tui/screens/post_reader.ex` and `test/foglet_bbs/tui/screens/post_reader_test.exs`. |
| AUDIT-14 | Inherited rubric | No new shared modules | SATISFIED | No new shared modules. `Spinner` and `Domain` are existing Phase-0 extractions. |
| AUDIT-15 | Inherited rubric | mix precommit green (SUMMARY claims) | NEEDS HUMAN | SUMMARY reports mix precommit green. Re-run needed after fixing AUDIT-05/16/19 gaps to confirm. |
| AUDIT-16 | Inherited rubric | Size delta ≤ 0 (line count and visible row count) | BLOCKED | Line count: 449 → 502 (+53). Visible row count unchanged. No developer override documented (compare REGISTER-05 override pattern). |
| AUDIT-17 | Inherited rubric | Protected layout regions not filled | SATISFIED | Header strip content is existing (post index, author, divider). Footer not filled. No new content in reserved regions. |
| AUDIT-18 | Inherited rubric | Canonical section order; deviations in moduledoc | SATISFIED | render_cache plumbing at §9 deviation documented in moduledoc at lines 33-34. Load-absorb deviation documented at lines 11-18 ("READER-07, AUDIT-18 deviation note"). |
| AUDIT-19 | Inherited rubric | Public init_screen_state/1 or documented intentionally stateless | BLOCKED | PostReader is stateful but has no public `init_screen_state/1`. `defp default_screen_state/0` exists (private). No "intentionally stateless" documentation. |
| AUDIT-20 | Workstream-wide anti-affordance | No `box style.*border` across all screens | SATISFIED | Zero matches in post_reader.ex. |
| AUDIT-21 | Inherited anti-affordance | No misused Display.Table / Input.* widgets | SATISFIED | Zero prohibited widget usages found. |
| AUDIT-22 | Inherited anti-affordance | No ASCII banners, decorative dividers, or layout additions | SATISFIED | header_divider (`─` char) is existing structural element, not decorative addition. No new layout structure. |

### Anti-Patterns Found

| File | Line(s) | Pattern | Severity | Impact |
|------|---------|---------|----------|--------|
| `post_reader.ex` | 62, 155, 216, 429, 468 | `state.terminal_size \|\| {80, 24}` inline (AUDIT-05 Gate 7) | Blocker | Fails AUDIT-05 Gate 7, which blocks READER-06 and ROADMAP SC-6. Peer screens (new_thread.ex, post_composer.ex, main_menu.ex) all use `@default_terminal_size` attribute instead. |
| `post_reader.ex` | whole file | Line count +53 (449 → 502) without developer override (AUDIT-16) | Blocker | Fails AUDIT-16 size-delta constraint. REGISTER-05 required an explicit developer override for an equivalent increase; same applies here. |
| `post_reader.ex` | — | No public `init_screen_state/1` for stateful screen (AUDIT-19) | Blocker | Fails AUDIT-19. All other stateful screens expose this function; PostReader is the only exception. |

### Human Verification Required

None required for the automated checks. Once the three gaps above are fixed, the following require a re-run of `mix precommit` to confirm green status:

1. **mix precommit green after gap fixes**
   - **Test:** Run `mix precommit` after adding `@default_terminal_size`, extracting `init_screen_state/1`, and resolving AUDIT-16 (either by reducing lines or obtaining developer override).
   - **Expected:** All five sub-checks (compile --warnings-as-errors, format, credo --strict, sobelow, dialyzer) pass.
   - **Why human:** Cannot run mix precommit from verification context.

### Gaps Summary

Three rubric gates block READER-06 and ROADMAP SC-6. All three share the root cause: the implementation plan (09-01-PLAN.md) focused narrowly on READER-01..05 and READER-07 deliverables without including the AUDIT-05 Gate 7 (`@default_terminal_size`), AUDIT-16 (line count governance), and AUDIT-19 (`init_screen_state/1`) items that were correctly included in peer phases 7 and 8.

**Gap 1 — AUDIT-05 Gate 7 (`@default_terminal_size`):**  
`post_reader.ex` uses `{80, 24}` inline at 5 locations. New_thread and PostComposer both added `@default_terminal_size {80, 24}` as part of their Phase 7/8 audits. The ROADMAP Phase 9 description explicitly lists "grep gate #7 return zero" as a success criterion. Fix: add `@default_terminal_size {80, 24}` module attribute and replace all inline `{80, 24}` references.

**Gap 2 — AUDIT-16 (line count delta):**  
Line count grew +53 (449 → 502). The SUMMARY notes this but treats it as self-evidently acceptable. AUDIT-16 is a hard "equal or lower" constraint and the REQUIREMENTS.md precedent (REGISTER-05) shows that an increase requires an explicit developer decision. Either the moduledoc prose can be condensed to recover the delta, or the developer must accept the increase with an override note (matching the REGISTER-05 pattern).

**Gap 3 — AUDIT-19 (`init_screen_state/1`):**  
PostReader is stateful but the private `defp default_screen_state/0` was never promoted to a public `def init_screen_state/1`. Every other stateful screen in the codebase exposes this function. The fix is minimal: change `defp default_screen_state/0` to `def init_screen_state(_opts \\ [])` with a `@spec` and update `get_screen_state/1` to call it.

All three gaps are mechanical and can be resolved in a single focused edit to `post_reader.ex` (plus a documentation decision for Gap 2). No behavioral changes required.

---

_Verified: 2026-04-22T14:30:00Z_
_Verifier: Claude (gsd-verifier)_
