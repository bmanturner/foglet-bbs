---
phase: 47-bound-unbounded-list-queries-drop-chrome-v1-shims-and-reduce
fixed_at: 2026-04-30T09:30:00Z
review_path: .planning/phases/47-bound-unbounded-list-queries-drop-chrome-v1-shims-and-reduce/47-REVIEW.md
iteration: 3
findings_in_scope: 8
fixed: 8
skipped: 0
status: all_fixed
---

# Phase 47: Code Review Fix Report (Iteration 3)

**Fixed at:** 2026-04-30
**Source review:** `47-REVIEW.md` (iteration 2 re-review)
**Iteration:** 3

**Summary:**
- Findings in scope: 8 (4 warnings, 4 info)
- Fixed: 8
- Skipped: 0

All in-scope findings from the iteration 2 re-review were fixed and
committed atomically. Each fix was verified with `mix compile` and
targeted tests; the full suite (`mix test` — 1 property, 2,241 tests)
remains green at the end of the pass.

## Fixed Issues

### WR-01: `Moderation.render/2` has the same unreachable fallback that BoardList's WR-03 fix removed

**Files modified:** `lib/foglet_bbs/tui/screens/moderation.ex`
**Commit:** `3e7836c4`
**Applied fix:** Deleted the unreachable `def render(local_state, %Context{})`
fallback head and replaced it with a comment mirroring the BoardList
WR-03 rationale so future grep audits do not rediscover the same
conclusion. `Routing.render_local_state/4` always either returns a
stored `%State{}` or invokes `Moderation.init/1` (which returns
`State.new(...)`), so the fallback could never fire in production.

### WR-02: `@max_page_size` ceiling has no test coverage

**Files modified:** `test/foglet_bbs/threads/threads_test.exs`
**Commit:** `d82f0754`
**Applied fix:** Added a regression test that uses
`Ecto.Adapters.SQL.to_sql/3` to verify the clamp at the SQL parameter
list. Ecto parameterises the `LIMIT` value (the literal `500` is never
embedded in the SQL string — it lives in the params slot as
`LIMIT $N`), so the assertion inspects `params` rather than the SQL
text. Test covers both query paths (user-scoped, anonymous), the
boundary value (`limit: 500` passes through unchanged), and a
sub-ceiling value (`limit: 25` is not clamped up).

The original review's snippet (`assert sql =~ "LIMIT 500"`) was adapted
to the actual Ecto behaviour after a first attempt failed — the fix is
otherwise faithful to the review's intent.

### WR-03: WR-04 fallback has no test coverage; the fix doc itself flags this

**Files modified:** `test/foglet_bbs/tui/screens/post_reader_test.exs`
**Commit:** `ec75dca8`
**Applied fix:** Added two new fake-posts modules and three regression
tests for the iteration 1 WR-04 fallback chain in
`place_selection_after_load/4`:

- `GappedFakePosts` — simulates a soft-deleted post at
  `message_number = 150` (the post is omitted from the loaded window).
  Test asserts selection lands on `message_number = 151` (the closest
  post with `message_number >= pointer`).
- `PointerBeforeWindowFakePosts` — pointer below the entire loaded
  window (200..210). Test pins the semantics: the fallback's "first
  post with `message_number >= pointer`" rule selects index 0 when
  every loaded post satisfies that.
- `BoundedFakePosts` (existing) — regression guard that the new
  fallback does not displace the primary path; exact-match still wins
  when the pointer's post is in the loaded window.

### WR-04: `Posts.list_reader_window/2` silently coerces unknown `:direction` values

**Files modified:** `lib/foglet_bbs/posts.ex`
**Commit:** `9725b97b`
**Applied fix:** Replaced the silent catch-all clause in
`normalize_reader_direction/1` with a `Logger.warning` mirroring the
iteration 1 WR-06 fix in `reader_rows_around/3`. A typo'd or
mis-typed direction (e.g. `:before` instead of `:previous`, `"next"`
string instead of `:next`) now leaves a breadcrumb in logs while
preserving the defensive `:initial` fallback. The 21 existing
`posts_test.exs` tests still pass.

### IN-01: `ThreadList.dispatch_thread_load/3` `list_threads/1` fallback comment is now stale

**Files modified:** `lib/foglet_bbs/tui/screens/thread_list.ex`
**Commit:** `1da4a736`
**Applied fix:** Added a docstring-style comment block above
`dispatch_thread_load/3` explicitly noting that both `list_threads/1`
and `list_threads/2` are bounded by `@page_size` since Phase 47, and
that the `/1` fallback exists only for minimal test adapters
(FakeThreads). Preserves the production behaviour rationale for future
readers without misleading them about the unbounded-vs-bounded
distinction.

### IN-02: PostReader and PostComposer still inline-pattern-match `:task_result` shapes

**Files modified:** `.planning/codebase/CONCERNS.md`
**Commit:** `44bc8963`
**Applied fix:** Chose the second of the two acceptable options the
review proposed ("either migrate in a follow-up phase, or track
explicitly so it doesn't get lost — TODO with `(IN-02)` tag or an entry
in CONCERNS.md"). Added a Tech Debt entry with file references, impact
classification (cosmetic / consistency, no correctness issue), and a
defined fix approach for a future cleanup phase. The full migration was
deferred deliberately — the review explicitly accepted CONCERNS.md as
sufficient tracking.

### IN-03: `Threads.move_thread/2` carries a stale "WR-04" comment from a different phase

**Files modified:** `lib/foglet_bbs/threads.ex`
**Commit:** `de826df9`
**Applied fix:** Replaced the stale `(WR-04)` reference with a
self-contained rationale that does not depend on a cross-phase finding
ID. Phase 47's WR-04 is the PostReader selection fallback; the
`move_thread` comment's "WR-04" predated Phase 47 and produced false
positives when grepping.

### IN-04: `Moderation.kv_grid_column/3` is reachable but only via one site; consider inlining

**Files modified:** `lib/foglet_bbs/tui/screens/moderation.ex`
**Commit:** `6f38d251`
**Applied fix:** Inlined `kv_grid_column/3` at its single caller
(`compact_table_children/5`). The list-flattening rationale that was
in the helper's docstring is now an inline comment at the use site.
The 53 existing moderation tests still pass.

## Verification

All fixes were verified at three levels:

1. **Tier 1 (re-read):** Every modified file was re-read after the
   `Edit` to confirm the fix text was present and surrounding code was
   intact.
2. **Tier 2 (compile):** `mix compile` ran cleanly after every code
   fix (exit 0; pre-existing raxol/Mogrify dependency warnings are
   ignored per the verification strategy).
3. **Tier 3 (focused tests):** Targeted test runs after each
   test-touching fix:
   - WR-02: `mix test test/foglet_bbs/threads/threads_test.exs:763`
     (1 test, 0 failures).
   - WR-03: `mix test test/foglet_bbs/tui/screens/post_reader_test.exs:1888`
     (3 tests, 0 failures).
   - WR-04: `mix test test/foglet_bbs/posts/posts_test.exs`
     (21 tests, 0 failures).
   - IN-04: `mix test test/foglet_bbs/tui/screens/moderation_test.exs`
     (53 tests, 0 failures).

**Final whole-suite run:** `mix test` — 1 property, 2,241 tests,
**0 failures**. `mix credo --strict` reports 4 pre-existing TODO design
suggestions (`TODO(WR-01)` tags in `register.ex`, `verify.ex`,
`login/render.ex`, `login/login_form.ex`); none introduced or touched
by this iteration. `mix precommit` exits 0.

## Skipped Issues

None — all 8 in-scope findings were fixed.

---

_Fixed: 2026-04-30_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 3_
