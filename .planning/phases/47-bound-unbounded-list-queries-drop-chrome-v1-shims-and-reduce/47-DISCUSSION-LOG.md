# Phase 47: Bound Unbounded List Queries, Drop Chrome V1 Shims, and Reduce App + Large Screen Modules - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the analysis.

**Date:** 2026-04-30
**Phase:** 47-bound-unbounded-list-queries-drop-chrome-v1-shims-and-reduce
**Mode:** assumptions
**Areas analyzed:** PostReader window anchor, Threads opts API, Login state shape, Login dispatch, App extraction boundaries, Chrome V1 deletion order, Test migration

## Assumptions Presented

### PostReader Window Anchor Selection

| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Reuse existing `update(:load, …)` path; map read-pointer → `direction: :around, around_message_number`; no pointer → `:initial`; jump → `:last`. No new Posts API. | Likely | `posts.ex:107, 145-152`; `post_reader.ex:90-104, 567-609`, `:298-337` |

### Threads Pagination API

| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Add `list_threads/3` with `(board_id, user_id_or_nil, opts \\ [])`; arity-1 and arity-2 delegate. Reserve `:limit`/`:after`/`:before`; implement only `:limit`. No stub validation. `@page_size 50` + `default_page_size/0` in `Foglet.Threads`. | Likely | `threads.ex:106-152`; Phase 44 `posts.ex:107` precedent; SPEC R3/R4 |

### Login State Shape & Dispatch

| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| `LoginState` stays a map keyed by `:sub`. Four sibling reducers `Login.{Menu, LoginForm, ResetRequest, ResetConsume}` each `handle_key/2` + `handle_task_result/3`. Top-level keeps existing `case LoginState.sub(state)` dispatch. | Likely | `login.ex:83-152, 154, 157-164`; `login/state.ex:13-32, 88-115`; `Map.merge` calls at `:101, :116, :127, :139, :147` |
| Task results route by task atom, not `:sub`. | Confident | `login.ex:83-152` already does this; preserves delayed-result behavior |

### App.ScreenStates / App.SessionAlias Boundaries

| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| `App.ScreenStates` operates on existing `:screen_state` field (no rename); exposes get/2, put/3, update/4, delete/2. `App.SessionAlias` owns `:set_user`, `:promote_session`, `:session_replaced` clauses + session_context aliasing. | Likely | `app.ex:58, 68, 103-114, 270-272, 369-378, 384-412`; `routing.ex:53` (current home) |

### Chrome V1 Deletion Order

| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Five-step order: migrate call sites → remove Normalizer fallback in ScreenFrame → delete KeyBar → delete Normalizer → remove legacy-title branches. `@key_hints` body text out of scope. | Confident | Dependency graph `KeyBar → Normalizer → CommandBar`; `screen_frame.ex:27, 191-204`; `key_bar.ex:11-13, 23-25`; `status_bar.ex:37` |

### Test Migration

| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Delete fixture `list_posts/1` impls (including `BoundedFakePosts` raise-guard). Delete `posts_test.exs:410-450` outright (Phase 44 covers tombstones). V1 chrome tests deleted not skipped. New tests at `test/foglet_bbs/tui/app/{screen_states,session_alias}_test.exs`. | Likely | SPEC R1 grep acceptance; Phase 44 `44-CONTEXT.md:78-85` (D-13/D-14); SPEC R5 explicit "deleted not skipped" |

## Corrections Made

No corrections — all four user-visible forks were resolved by selecting the recommended option:

- **PostReader anchor:** Reuse `:around` + `around_message_number` (Recommended)
- **Threads opts API:** `list_threads/3` with `(board_id, user_id, opts)` (Recommended)
- **Login state:** Map-keyed by `:sub` + sibling reducer modules (Recommended)
- **App extraction:** ScreenStates over existing `:screen_state` field; SessionAlias owns `:set_user`/`:promote_session`/`:session_replaced` (Recommended)

## Auto-Resolved

Not applicable — interactive mode.

## External Research

None performed — entirely internal refactor against patterns established by Phases 41–44.
