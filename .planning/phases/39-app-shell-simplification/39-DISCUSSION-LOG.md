# Phase 39: App Shell Simplification - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the analysis.

**Date:** 2026-04-29
**Phase:** 39-app-shell-simplification
**Mode:** assumptions
**Areas analyzed:** Route-entry mechanism, Subscriptions callback, Breadcrumb input, PubSub regression test seam, MainMenu first-load + render_fixtures migration

## Assumptions Presented

### Route-entry Mechanism Shape
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Generic `:on_route_enter` atom message dispatched via existing `route_screen_update/3`; no new `Effect` variant | Likely | `app.ex:851-865`, `app.ex:152-160`, `screen.ex:27,38`, Phase 34 D-04 forbids compatibility layer |
| Screens with entry-load needs (`MainMenu`, `Moderation`, `Sysop`, `ThreadList`, `PostReader`) implement `update(:on_route_enter, …)`; others use catch-all | Likely | Existing migrated screens already pattern on entry atoms (`thread_list.ex:36`, `post_reader.ex:75`); `update/3` message arg is `term()` |

Alternatives considered:
- A: New optional callback `screen_module.on_route_enter/2` — adds a fourth optional callback; rejected for surface area.
- B: Change `init/1` to return `{state, effects}` — breaks Phase 34 contract and every migrated screen; rejected.

### Subscriptions Callback Contract
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| `@callback subscriptions(local_state, Context.t()) :: [String.t()]`, optional callback | Confident | SPEC R6 acceptance check pins arity 2 and `function_exported?` shape |
| App invokes inside rebuilt `build_pubsub_topics/1` per `subscribe/1` call; `function_exported?/3`-gated | Confident | `app.ex:417-426` already rebuilds per call; idiom matches `app.ex:854,870,964` |
| No App-side topic-diffing or "current topics" state | Confident | `Subscription.custom(PubSubForwarder, …)` rebuild handled by Raxol |
| Only `PostReader` and `ThreadList` implement; other 10 production screens do not | Confident | `app.ex:478,517` — only these two screens have non-empty topic sets today |
| Each implementer falls back to `Context.route_params` when local state has no id | Confident | Matches today's precedence in `routed_thread_topic/1` / `thread_list_board_topic/1` |

### Breadcrumb Input Contract
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Screens pass `breadcrumb_parts: [String.t()]` on existing chrome map; no new struct | Confident | `breadcrumb_bar.ex:50-51`, `screen_frame.ex:185-196` already accept this shape |
| Delete `BreadcrumbBar.parts_for/1` and `:62-92` per-screen branches plus `board_name/1`/`thread_title/1` | Confident | These are the only readers of `:current_board`/`:current_thread` from App |
| Each affected screen derives labels from its local state in `render/2` | Confident | `ThreadList.State.board.name`, `PostReader.State.thread.title`, etc. already exist |

### App PubSub Broadcast Routing
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| `{:board_activity, …}` and `{:thread_activity, …}` lose `current_screen` gates and route generically | Confident | SPEC R8 acceptance: "no clause that gates a PubSub broadcast on a specific `current_screen` atom" |

### MainMenu First-load + render_fixtures
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| `MainMenu.update(:on_route_enter, …)` owns first-load; `:set_user`/`:promote_session` route through `Effect.navigate(:main_menu, %{})` | Likely | `main_menu.ex:138, 530`; `Effect.navigate` already invokes init+route-entry chain |
| Delete `:main_menu`-specific clause in `maybe_init_initial_screen_state/1` | Likely | Generic `init_route_screen_state/3` (`app.ex:777-794`) already handles MainMenu via `function_exported?/3` |
| `render_fixtures.ex:84-100` migration is a 5-line legacy-field deletion; no `populate/3` clause changes | Likely | Every `populate/3` clause already constructs `screen_state: %{...}` (clauses at 156, 174, 188-192, 203-211, 233-236, 257-260, 269-276) |

Alternative considered:
- A: Keep `:set_user`/`:promote_session` calling `route_screen_update(state, :main_menu, :on_route_enter)` directly. Cheaper but still names `:main_menu` literal — against R4's spirit. Rejected; planner may revisit if D-14 produces a worse diff.

### PubSub Regression Test Seam
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Keep five existing pin tests at `app_test.exs:1483-1607` for surviving cases | Confident | Tests assert subscription shape, allowed by AGENTS.md |
| Delete (do not migrate) tests at `app_test.exs:1531-1551, 1587-1607` — they construct deleted struct fields | Confident | Tests literally assign `state.current_board = …` and `state.current_thread = …` |
| Add new pin: authenticated `:main_menu` → `["user:<id>"]` only | Confident | Proves stateless screens correctly omit the optional callback |

## Corrections Made

No corrections — all assumptions confirmed.

## External Research

None performed. Phase 39 is a pure refactor of code owned end-to-end; no library or ecosystem question is unresolved.
