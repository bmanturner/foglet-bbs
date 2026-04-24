# Phase 11: posting-policy-enforcement - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the analysis.

**Date:** 2026-04-24T16:43:49Z
**Phase:** 11-posting-policy-enforcement
**Mode:** assumptions
**Areas analyzed:** Context Gate Placement, Actor And Policy Source, Locked Thread Bypass, TUI Error Presentation

## Assumptions Presented

### Context Gate Placement
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Posting-policy and locked-thread checks should live in `Foglet.Threads.create_thread/3` and `Foglet.Posts.create_reply/4`, before delegating successful writes to `Foglet.Boards.Server`. | Confident | `.planning/phases/11-posting-policy-enforcement/11-SPEC.md`, `.planning/ROADMAP.md`, `lib/foglet_bbs/threads.ex`, `lib/foglet_bbs/posts.ex`, `lib/foglet_bbs/boards/server.ex` |

### Actor And Policy Source
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| The create APIs can keep their current user-id-based signatures and load persisted user, board, and thread records inside the contexts to evaluate active status, role, `postable_by`, and `locked`. | Likely | `.planning/phases/11-posting-policy-enforcement/11-SPEC.md`, `lib/foglet_bbs/accounts/user.ex`, `lib/foglet_bbs/boards/board.ex`, `lib/foglet_bbs/threads/thread.ex`, `lib/foglet_bbs/tui/screens/new_thread.ex`, `lib/foglet_bbs/tui/screens/post_composer.ex` |

### Locked Thread Bypass
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Locked-thread bypass should use the existing authorization scope model: sysops bypass directly, and moderators bypass when `Foglet.Authorization.scopes_for/2` includes `:site` or a matching `{:board, board_id}` scope. | Confident | `.planning/phases/11-posting-policy-enforcement/11-SPEC.md`, `lib/foglet_bbs/authorization.ex`, `test/foglet_bbs/authorization_test.exs`, `lib/foglet_bbs/boards.ex`, `lib/foglet_bbs/threads.ex`, `lib/foglet_bbs/posts.ex` |

### TUI Error Presentation
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Contexts should return structured domain errors that TUI screens format into clear copy, with locked-thread rejection rendered exactly as `This thread is locked`; `PostComposer` must stop collapsing all create failures to `Failed to create post.` | Confident | `.planning/phases/11-posting-policy-enforcement/11-SPEC.md`, `lib/foglet_bbs/tui/screens/new_thread.ex`, `lib/foglet_bbs/tui/screens/post_composer.ex`, `test/foglet_bbs/tui/screens/new_thread_test.exs`, `test/foglet_bbs/tui/screens/post_composer_test.exs` |

## Corrections Made

No corrections — all assumptions confirmed.
