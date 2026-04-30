---
phase: 43-large-screen-decomposition
fixed_at: 2026-04-29T00:00:00Z
review_path: .planning/phases/43-large-screen-decomposition/43-REVIEW.md
iteration: 1
findings_in_scope: 2
fixed: 2
skipped: 0
status: all_fixed
---

# Phase 43: Code Review Fix Report

**Fixed at:** 2026-04-29
**Source review:** `.planning/phases/43-large-screen-decomposition/43-REVIEW.md`
**Iteration:** 1 (this file overwrites a prior iteration that addressed
different findings — the linked review is a fresh review cycle dated
2026-04-30T00:59:12Z)

**Summary:**
- Findings in scope: 2 (Critical + Warning; `--all` not set)
- Fixed: 2
- Skipped: 0

## Fixed Issues

### WR-01: PostReader Render Emits Warning Logs On Cache Misses

**Files modified:** `lib/foglet_bbs/tui/screens/post_reader/render.ex`
**Commit:** `380e5136`
**Applied fix:** Removed the inline `require Logger` and the
`Logger.warning("[PostReader] render cache miss ...")` call from the
cache-miss branch in `render_post_content/5`. The branch now falls back
to `PostReader.body_tuples_for/2` silently, restoring the documented
purity of the render boundary. Verified by re-running
`rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs` — the
`[PostReader] render cache miss` warnings no longer appear in test
output.

### WR-02: NewThread Silently Swallows Configuration Failures

**Files modified:**
- `lib/foglet_bbs/tui/screens/new_thread.ex`
- `test/foglet_bbs/tui/screens/new_thread_test.exs`

**Commits:**
- `8cac0556` — Narrowed the `rescue` in `safe_config_get/2` from a
  catch-all to `Ecto.NoResultsError`, matching the reviewer's suggested
  fix exactly. Genuine config/cache/DB failures now propagate instead
  of being masked by hardcoded defaults.
- `04556255` — Followup: the narrower rescue exposed a real
  eager-evaluation path in `context_with_config_limits/1`, which was
  calling `safe_config_get/2` even when `session_context` already
  carried valid positive integers for the limits. Replaced
  `put_new_positive/3` with a lazy variant `put_new_positive_lazy/3`
  so the producer (and any DB read it triggers) only runs when the key
  is missing. This matches the reviewer's "snapshot these limits before
  render/update through session context" recommendation. Also seeded
  compose limits in the failing `init/1` unit test's context so the
  test no longer depends on `Foglet.Config` DB access (the test module
  uses `ExUnit.Case`, not `Foglet.DataCase`).

**Applied fix description:** Together these commits ensure that
unexpected configuration read failures propagate to the caller, while
the legitimate "config row not seeded" path (`Ecto.NoResultsError`)
still falls back to the compile-time default. Callers that already
carry the limit in `session_context` no longer pay for an unnecessary
config read on the hot path.

## Verification

**Focused tests:**

```
rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs \
             test/foglet_bbs/tui/screens/new_thread_test.exs
```

Result: **157 tests, 0 failures**. No `[PostReader] render cache miss`
warnings observed in test output.

**`rtk mix precommit`:**

- `compile --warnings-as-errors`: pass
- `deps.unlock --unused`: pass
- `format`: pass (`mix format --check-formatted` exits 0)
- `credo --strict`: pass (1 pre-existing unrelated warning in
  `lib/foglet_bbs/sessions/session.ex:187` about a Logger metadata key
  replacement — not introduced by these fixes)
- `sobelow --exit Low`: pass
- `dialyzer`: 2 pre-existing warnings, **not** introduced by these
  fixes:
  - `lib/foglet_bbs/posts/reader_window.ex:14:23: unknown_type` for
    `Foglet.Posts.Post.t/0` (pre-existing; file not touched in this
    iteration).
  - `lib/foglet_bbs/tui/screens/post_reader/render.ex:26: guard_fail`
    for `terminal_size` defaulting (pre-existing; line 26 was not
    touched by the WR-01 fix, which targets lines 87–96).

  Both warnings exist on the pre-fix HEAD (`de3b7026`) and are out of
  scope for the WR-01 / WR-02 findings. They should be tracked as
  separate cleanup if desired.

---

_Fixed: 2026-04-29_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
