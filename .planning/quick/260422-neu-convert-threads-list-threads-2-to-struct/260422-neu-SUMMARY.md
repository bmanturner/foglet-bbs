---
phase: quick-260422-neu
plan: 01
subsystem: threads
tags: [elixir, ecto, struct, dialyzer, tui, thread-list]

# Dependency graph
requires: []
provides:
  - "%Foglet.Threads.ThreadEntry{} struct with 13 fields and @type t"
  - "list_threads/2 returns [ThreadEntry.t()] instead of [map()]"
  - "preload_created_by/1 uses struct update syntax"
  - "annotate_no_user/1 builds %ThreadEntry{} explicitly"
  - "ThreadList and App fallback paths produce %ThreadEntry{} structs"
affects: [thread-list-rendering, post-reader, dialyzer]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Read-model struct pattern: plain Elixir struct (not Ecto schema) for query projections"
    - "Post-query struct conversion: keep Ecto select: as bare map, convert with Enum.map(&struct(ThreadEntry, &1))"

key-files:
  created:
    - lib/foglet_bbs/threads/thread_entry.ex
  modified:
    - lib/foglet_bbs/threads.ex
    - lib/foglet_bbs/tui/screens/thread_list.ex
    - lib/foglet_bbs/tui/app.ex
    - test/foglet_bbs/threads/threads_test.exs

key-decisions:
  - "Keep Ecto select: as bare map literal — Ecto cannot materialize non-schema structs; convert post-query with struct/2"
  - "Explicit field selection in annotate_no_user/1 and annotate_fallback/1 — avoids leaking Ecto internal fields (__meta__, :board, :posts) via Map.from_struct"
  - "Tighten App @type t current_thread from map() to ThreadEntry.t() while adding alias"

patterns-established:
  - "Read-model projection pattern: one-struct-per-file, no module nesting, @type t, no constructor needed"
  - "Struct update %{row | field: value} for structs in preload helpers (not Map.put/3)"

requirements-completed: [LIST-03]

# Metrics
duration: 3min
completed: 2026-04-22
---

# Quick Task 260422-neu: Convert ThreadEntry Summary

**Promoted `list_threads/2` return from anonymous `[map()]` to typed `[ThreadEntry.t()]` with dialyzer-visible struct, eliminating Map.from_struct leaks at all four call sites**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-04-22T21:59:16Z
- **Completed:** 2026-04-22T22:02:15Z
- **Tasks:** 3
- **Files modified:** 5 (1 created, 4 updated)

## Accomplishments

- New `%Foglet.Threads.ThreadEntry{}` struct with 13 fields and `@type t` gives dialyzer full visibility into the thread-list shape
- `list_threads/2` spec updated from `[map()]` to `[ThreadEntry.t()]`; query pipeline now converts Repo results via `Enum.map(&struct(ThreadEntry, &1))` before `preload_created_by/1`
- `preload_created_by/1` switched from `Map.put/3` to struct update `%{row | created_by: ...}`
- `annotate_no_user/1`, `ThreadList.annotate_fallback/1`, and `App.load_threads_for_user/3` all rewritten to construct `%ThreadEntry{}` explicitly instead of using `Map.from_struct/1`
- `App.@type t` tightened: `current_thread: map() | nil` → `ThreadEntry.t() | nil`
- Threads test gains `assert %Foglet.Threads.ThreadEntry{} = t` shape assertion
- All 119 tests pass; `mix precommit` exits 0

## Task Commits

1. **Task 1: Define %Foglet.Threads.ThreadEntry{} struct** - `3e16a41` (feat)
2. **Task 2: Update Foglet.Threads — spec, builder, preload, annotate** - `3fcd704` (feat)
3. **Task 3: Update call sites in ThreadList, App, and threads test** - `f01ff43` (feat)

## Files Created/Modified

- `lib/foglet_bbs/threads/thread_entry.ex` - New read-model struct with 13 fields and `@type t`
- `lib/foglet_bbs/threads.ex` - Updated alias, spec, `list_threads/2` pipeline, `preload_created_by/1`, `annotate_no_user/1`
- `lib/foglet_bbs/tui/screens/thread_list.ex` - Updated alias and `annotate_fallback/1` both clauses
- `lib/foglet_bbs/tui/app.ex` - Updated alias, `load_threads_for_user/3` fallback, `@type t`
- `test/foglet_bbs/threads/threads_test.exs` - Added `%ThreadEntry{}` shape assertion

## Decisions Made

- **Keep `select:` as bare map:** Ecto cannot materialize non-schema structs in `select:`, so conversion happens post-`Repo.all` via `Enum.map(&struct(ThreadEntry, &1))`.
- **Explicit field selection everywhere:** `Map.from_struct/1` on a `%Thread{}` would include Ecto internals (`__meta__`, `:board`, `:posts`). Each call site now selects only the 13 `ThreadEntry` fields by name.
- **Struct update in preload:** Since rows are now `%ThreadEntry{}` structs, `Map.put/3` won't work — switched to `%{row | created_by: ...}`.

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## Known Stubs

None — all fields are populated from real data sources.

## Next Phase Readiness

- `ThreadEntry` struct is ready to be used by any downstream consumer (PostReader, board stats, etc.)
- Dialyzer will now catch type violations on thread-list shapes
- No blockers

---
*Quick task: 260422-neu*
*Completed: 2026-04-22*
