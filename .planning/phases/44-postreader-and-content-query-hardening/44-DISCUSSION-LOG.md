# Phase 44: PostReader And Content Query Hardening - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md - this log preserves the analysis.

**Date:** 2026-04-29
**Phase:** 44-postreader-and-content-query-hardening
**Mode:** assumptions
**Areas analyzed:** Bounded PostReader Loading, PostReader State Shape, Reader Navigation, Resize Cache Eviction, Render-Purity Guard, Soft-Delete Query Policy

## Assumptions Presented

### Bounded PostReader Loading
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Use a cursor/window API in `Foglet.Posts` rather than making PostReader slice a full list locally. The boundary should be message-number/cursor based, include `:user`, preserve tombstones, and return metadata such as direction/has_previous/has_next so PostReader can cross window edges. | Likely | `.planning/phases/44-postreader-and-content-query-hardening/44-SPEC.md`; `.planning/codebase/CONCERNS.md`; `lib/foglet_bbs/posts.ex`; `lib/foglet_bbs/tui/screens/post_reader.ex` |

### PostReader State Shape
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Keep `%PostReader.State{}.posts` as the active bounded window for compatibility with existing render/navigation helpers, and add separate navigation metadata instead of replacing `posts` with a new collection abstraction. | Likely | `lib/foglet_bbs/tui/screens/post_reader/state.ex`; `lib/foglet_bbs/tui/screens/post_reader.ex`; `test/foglet_bbs/tui/screens/post_reader_test.exs`; `.planning/phases/43-large-screen-decomposition/43-CONTEXT.md` |

### Reader Navigation
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Preserve `n/p/space/page_down/page_up` as post-to-post movement, loading adjacent windows only when selection crosses the current active window. `jump_last` should request the newest bounded window from the domain instead of loading all rows then choosing the last index. | Likely | `lib/foglet_bbs/tui/screens/post_reader.ex`; `lib/foglet_bbs/tui/screens/post_reader/state.ex`; `lib/foglet_bbs/tui/screens/post_composer.ex`; `test/foglet_bbs/tui/screens/post_reader_test.exs` |

### Resize Cache Eviction
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Evict stale-width entries inside the existing cache-warming reducer path when warming at the current terminal width; render remains read-only and may parse as fallback but must not write state. | Confident | `.planning/phases/44-postreader-and-content-query-hardening/44-SPEC.md`; `lib/foglet_bbs/tui/SCREEN_CONTRACT.md`; `lib/foglet_bbs/tui/screens/post_reader.ex`; `test/foglet_bbs/tui/screens/post_reader_test.exs` |

### Soft-Delete Query Policy
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Keep reader/history APIs tombstone-capable and add explicit list/summary coverage around `Threads.list_threads/1,2`, board directory unread/last-post summaries, and any shared `QueryHelpers.not_deleted/1` paths that affect user-visible lists. | Confident | `lib/foglet_bbs/posts.ex`; `test/foglet_bbs/posts/posts_test.exs`; `lib/foglet_bbs/threads.ex`; `lib/foglet_bbs/boards.ex`; `lib/foglet_bbs/query_helpers.ex` |

### Render-Purity Guard
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Preserve or strengthen the automated source/static guard that rejects state-write operations inside PostReader render helpers, updating its target if Phase 43 moves the render boundary into a sibling render module. | Confident | `.planning/phases/43-large-screen-decomposition/43-CONTEXT.md`; `.planning/phases/44-postreader-and-content-query-hardening/44-SPEC.md`; `lib/foglet_bbs/tui/SCREEN_CONTRACT.md`; `test/foglet_bbs/tui/screens/post_reader_test.exs` |

## Corrections Made

No corrections - all assumptions confirmed.
