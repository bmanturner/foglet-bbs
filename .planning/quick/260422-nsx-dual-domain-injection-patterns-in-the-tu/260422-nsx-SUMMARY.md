---
phase: quick-260422-nsx
plan: 01
subsystem: ui
tags: [tui, domain, elixir, raxol]

requires: []
provides:
  - domain_module/2 private helper in Foglet.TUI.App
  - single canonical path for all domain-module lookups in app.ex
affects: [tui, domain injection, foglet_bbs.tui.app]

tech-stack:
  added: []
  patterns:
    - "All domain-module lookups in app.ex route through domain_module/2 -> Domain.get/2"
    - "default_domain_module/1 provides dialyzer-safe per-key fallbacks"

key-files:
  created: []
  modified:
    - lib/foglet_bbs/tui/app.ex

key-decisions:
  - "Removed default_domain_module(:markdown) clause — no call site in app.ex passes :markdown; Dialyzer correctly flagged the pattern as unreachable"
  - "Used key-dispatch default_domain_module/1 clauses (one per key) rather than a map lookup so Dialyzer can verify exhaustiveness at each call site"

requirements-completed: [quick-260422-nsx]

duration: 10min
completed: 2026-04-22
---

# Quick Task 260422-nsx Summary

**Eliminated all 5 legacy `get_in(ctx, [:domain, key]) || FallbackMod` blocks in `app.ex` by routing through a new `domain_module/2` helper backed by `Domain.get/2`**

## Performance

- **Duration:** ~10 min
- **Completed:** 2026-04-22
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- Added `alias Foglet.TUI.Screens.Domain` to the alias block in alphabetical position
- Implemented `domain_module/2` private helper that delegates to `Domain.get/2` with per-key fallback via `default_domain_module/1`
- Migrated all 5 `do_update` clauses (`{:load_boards}`, `{:load_boards_for_new_thread}`, `{:load_threads, board_id}`, `{:load_posts, thread_id, opts}`, `{:flush_read_pointers, ctx}`) to use `domain_module/2`
- Removed stale 3-line comment from `{:load_boards}` that documented the deliberate non-use of `Domain.get/2`
- Zero occurrences of `get_in(_, [:domain, _])` remain in `app.ex`

## Task Commits

1. **Task 1: Add alias + domain_module/2 helper** - `a7a0078` (feat)
2. **Task 2: Migrate 5 do_update clauses to domain_module/2** - `1118185` (feat)

## Files Created/Modified

- `lib/foglet_bbs/tui/app.ex` - Alias added, helpers added, 5 do_update clauses migrated

## Decisions Made

- Dropped `default_domain_module(:markdown)` clause: Dialyzer flagged it as an unreachable pattern because no call site in `app.ex` passes `:markdown`. Removing it is correct — if a `:markdown` call site is added later, the clause can be restored then.
- Kept `default_domain_module/1` as explicit per-key clauses (rather than a map) so Dialyzer tracks which atoms are valid inputs.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed unreachable `default_domain_module(:markdown)` clause**
- **Found during:** Task 2 (post-migration `mix precommit` run)
- **Issue:** Dialyzer `pattern_match` warning — the `:markdown` clause in `default_domain_module/1` can never match because all call sites pass only `:boards`, `:threads`, or `:posts`. The plan's template included `:markdown` for completeness, but no `do_update` clause in `app.ex` touches markdown domain.
- **Fix:** Removed the `defp default_domain_module(:markdown), do: Foglet.Markdown` clause.
- **Files modified:** `lib/foglet_bbs/tui/app.ex`
- **Verification:** `mix precommit` exits 0 with no Dialyzer errors after removal.
- **Committed in:** `1118185` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 — dead code pattern caught by Dialyzer)
**Impact on plan:** Minimal scope adjustment; the clause was never reachable. Plan intent fully achieved.

## Issues Encountered

None beyond the Dialyzer pattern_match warning resolved above.

## Self-Check

Files verified:
- `lib/foglet_bbs/tui/app.ex` — exists, contains `domain_module/2`, zero `get_in.*:domain` matches

Commits verified:
- `a7a0078` — present
- `1118185` — present

## Self-Check: PASSED

---
*Phase: quick-260422-nsx*
*Completed: 2026-04-22*
