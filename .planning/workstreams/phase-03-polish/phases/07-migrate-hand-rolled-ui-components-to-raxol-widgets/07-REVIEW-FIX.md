---
phase: 07-migrate-hand-rolled-ui-components-to-raxol-widgets
fixed_at: 2026-04-21T00:00:00Z
review_path: .planning/workstreams/phase-03-polish/phases/07-migrate-hand-rolled-ui-components-to-raxol-widgets/07-REVIEW.md
iteration: 1
findings_in_scope: 7
fixed: 7
skipped: 0
status: all_fixed
---

# Phase 07: Code Review Fix Report

**Fixed at:** 2026-04-21T00:00:00Z
**Source review:** `.planning/workstreams/phase-03-polish/phases/07-migrate-hand-rolled-ui-components-to-raxol-widgets/07-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 7 (0 critical, 2 warnings, 5 info)
- Fixed: 7
- Skipped: 0

All findings were applied. `mix format`, `mix compile --warnings-as-errors`, and `mix sobelow` are clean on the changed files. `mix credo --strict` reports the same 2 refactoring + 2 readability findings that existed before this fix run — none of them in files touched by these commits (they live in `post_composer.ex:274 do_submit`, `login.ex:263 submit_login`, and two alias-ordering nits in untouched test files). `mix test` runs 120 passes, 0 failures across the five affected test files (post_reader, post_composer, post_card, markdown_body, modal).

## Fixed Issues

### WR-01: Viewport.update/2 return-tuple match-assumption is fragile

**Files modified:** `lib/foglet_bbs/tui/screens/post_reader.ex`
**Commit:** `a2cf4db`
**Applied fix:** Replaced all five `{vp, []} = Viewport.update(...)` strict matches with `{vp, _cmds} = ...` — in `render_post_content/5`, `warm_viewport/4`, `advance_post/2`, and both calls inside `scroll_post/2`. A future Raxol upgrade that returns a non-empty command list no longer crashes the render hot path with a `MatchError`.

### WR-02: `handle_key/2` spec claims `:no_match` but helpers never actually return it during normal loading

**Files modified:** `lib/foglet_bbs/tui/screens/post_reader.ex`
**Commit:** `20dfd3f`
**Applied fix:** Chose option (a) from the review suggestion — `advance_post/2` and `scroll_post/2` now return `{:update, state, []}` (key absorbed) when `posts == []` or `post == nil`, instead of `:no_match`. PostReader's `handle_key/2` still has a top-level `:no_match` wildcard clause for keys it genuinely doesn't handle, preserving correct global-key dispatch.

### IN-01: `author_line/1`, `get_handle/1`, `get_time_ago/1` duplicated between PostReader and PostCard

**Files modified:** `lib/foglet_bbs/tui/widgets/post/post_card.ex`, `lib/foglet_bbs/tui/screens/post_reader.ex`
**Commit:** `2f843b9`
**Applied fix:** Promoted PostCard's `author_line/1`, `get_handle/1`, and `get_time_ago/1` from `defp` to `def` with `@doc false` and `@spec` annotations — public for cross-module use but excluded from ExDoc output. Deleted the three private duplicates from PostReader and its now-unused `Foglet.TimeAgo` alias. PostReader's header now calls `PostCard.author_line(post)`.

### IN-02: `get_handle/1` contracts diverge across three modules

**Files modified:** `lib/foglet_bbs/tui/screens/post_composer.ex`
**Commit:** `5d9f37e`
**Applied fix:** Replaced PostComposer's two `defp get_handle` clauses with a single delegating clause: `defp get_handle(post), do: PostCard.get_handle(post) || "unknown"`. This inherits PostCard's strict `is_binary(h) and h != ""` guard — an empty-string handle now renders as `"unknown"` instead of the visible-UI-bug `"@"`. Added the `PostCard` alias.

### IN-03: Dead parameters `_w` / `_h` in `render_post_content/5` empty-posts clause

**Files modified:** `lib/foglet_bbs/tui/screens/post_reader.ex`
**Commit:** `c3cd6bf`
**Applied fix:** Replaced the five-arg loading clause (which discarded four args with underscores) with `defp render_post_content(%{posts: posts}, _ss, theme, _w, _h) when posts in [[], nil]`, delegating to a new `defp render_loading(theme)` helper. Intent is now self-evident.

### IN-04: `render_body_lines/5` ignores the `post` parameter

**Files modified:** `lib/foglet_bbs/tui/widgets/post/post_card.ex`, `lib/foglet_bbs/tui/screens/post_reader.ex`, `test/foglet_bbs/tui/widgets/post/post_card_test.exs`
**Commit:** `0553ad3`
**Applied fix:** Dropped the unused `post` parameter from `PostCard.render_body_lines/5` (now arity 4 — `tuples, width, theme, opts \\ []`). Updated both PostReader call sites (`render_post_content/5:74` and `warm_viewport/4`) and six test call sites in `post_card_test.exs`. Removed the `_ = post` noise and simplified two tests that no longer needed their `post` binding.

### IN-05: `_ = opts` pattern noise in `render_tuples_as_lines/4`

**Files modified:** `lib/foglet_bbs/tui/widgets/post/markdown_body.ex`
**Commit:** `ea531e0`
**Applied fix:** Replaced the body-level `_ = opts` discard with an underscore-prefixed parameter in the function head (`_opts \\ []`). Conveys "deliberately ignored" at the declaration site and shrinks the function by one line.

---

_Fixed: 2026-04-21T00:00:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
