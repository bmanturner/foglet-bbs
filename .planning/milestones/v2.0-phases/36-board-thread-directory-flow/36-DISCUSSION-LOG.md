# Phase 36: Board & Thread Directory Flow - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution
> agents. Decisions captured in CONTEXT.md - this log preserves the analysis.

**Date:** 2026-04-28
**Phase:** 36-board-thread-directory-flow
**Mode:** assumptions
**Areas analyzed:** BoardList Ownership, ThreadList Ownership, Route Params And
Navigation, Task Effects And App Boundary, Testing And Preservation

## Assumptions Presented

### BoardList Ownership

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| BoardList should become a new-contract screen whose local state owns the loaded directory, BoardTree cursor/expansion state, loading status, and subscription feedback. | Confident | `lib/foglet_bbs/tui/screens/board_list.ex`, `lib/foglet_bbs/tui/screens/board_list/state.ex`, `lib/foglet_bbs/tui/app.ex` board-load and subscription clauses |

### ThreadList Ownership

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| ThreadList should get a first-class State struct and own current board route params, loaded thread rows, selected index, loading/empty state, and task results. | Confident | `lib/foglet_bbs/tui/screens/thread_list.ex`, `.planning/phases/34-runtime-contract-effects/34-CONTEXT.md`, `.planning/phases/35-auth-home-screens/35-CONTEXT.md` |

### Route Params And Navigation

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Board/thread navigation should use `Effect.navigate/2` with route params, while preserving legacy top-level `current_board`/`current_thread` only where later unmigrated phases still need them until Phase 39 cleanup. | Likely | `lib/foglet_bbs/tui/app.ex` route helpers, `test/foglet_bbs/tui/app_runtime_contract_test.exs`, current PostReader/NewThread tests that still read top-level board/thread fields |

### Task Effects And App Boundary

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Directory loads, thread loads, and subscribe/unsubscribe mutations should move from legacy tuple commands into `Effect.task/3` results handled by `BoardList.update/3` and `ThreadList.update/3`. | Likely | `lib/foglet_bbs/tui/effect.ex`, `lib/foglet_bbs/tui/app.ex`, `test/foglet_bbs/tui/app_runtime_contract_test.exs` |

### Testing And Preservation

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Verification should migrate existing behavior tests toward reducer/effect assertions and keep render smoke checks focused on non-crash/layout preservation, not new visual/product behavior. | Confident | `test/foglet_bbs/tui/screens/board_list_test.exs`, `test/foglet_bbs/tui/screens/thread_list_test.exs`, `.planning/codebase/TESTING.md`, project testing instructions |

## Corrections Made

No corrections - all assumptions confirmed.
