# Phase 37: Post & Composer Flow - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md - this log preserves the analysis.

**Date:** 2026-04-28
**Phase:** 37-post-composer-flow
**Mode:** assumptions
**Areas analyzed:** PostReader Ownership, Read-Pointer Flush Semantics, PostComposer Ownership, NewThread Ownership, App Boundary, Testing And Preservation

## Assumptions Presented

### PostReader Ownership

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| PostReader should absorb its current App-owned data into PostReader.State: posts/loading/error, selected index, viewport/render cache, selected board/thread route data, and pending read-pointer data. | Confident | `.planning/phases/37-post-composer-flow/37-SPEC.md`; `lib/foglet_bbs/tui/screens/post_reader.ex`; `lib/foglet_bbs/tui/screens/post_reader/state.ex`; `lib/foglet_bbs/tui/app.ex` |

### Read-Pointer Flush Semantics

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Read-pointer flush should become a PostReader task effect with retry-preserving local pending data; success clears only the flushed pending entry and failure keeps it. | Confident | `.planning/phases/37-post-composer-flow/37-SPEC.md`; `lib/foglet_bbs/tui/screens/post_reader.ex`; `lib/foglet_bbs/tui/app.ex`; `test/foglet_bbs/tui/screens/post_reader_test.exs` |

### PostComposer And NewThread Submission

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| PostComposer and NewThread submissions should move from synchronous handle_key calls to task effects returned by update/3. Route params/local state carry board/thread/reply/origin; successful reply reloads PostReader with jump_last; successful thread navigates to ThreadList and requests reload. | Confident | `lib/foglet_bbs/tui/screens/post_composer.ex`; `lib/foglet_bbs/tui/screens/new_thread.ex`; `lib/foglet_bbs/tui/effect.ex`; `test/foglet_bbs/tui/app_runtime_contract_test.exs` |

### App Boundary

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| App cleanup should remove only Phase 37 flow ownership now, while allowing generic runtime, route storage, modal/SizeGate, PubSub forwarding, and explicitly narrow Phase 39 compatibility. | Confident | `.planning/phases/36-board-thread-directory-flow/36-CONTEXT.md`; `.planning/phases/37-post-composer-flow/37-SPEC.md`; `lib/foglet_bbs/tui/app.ex`; `test/foglet_bbs/tui/app_runtime_contract_test.exs` |

## Corrections Made

No corrections - all assumptions confirmed.
