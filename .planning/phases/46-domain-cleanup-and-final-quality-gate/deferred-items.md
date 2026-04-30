# Phase 46 — Deferred Items

Out-of-scope discoveries logged during plan execution. These are NOT introduced by phase 46 work; they pre-exist the phase base commit (a66ef4a7) and affect files unrelated to the active plan's changes. Routed to plan 46-04 (QUAL-03 baseline cleanup) for triage.

## Pre-existing test failures in `test/foglet_bbs/tui/app_test.exs`

**Discovered during:** Plan 46-01 Task 2 (cadence gate).

**Verified pre-existing:** Yes. Reproduced against `lib/foglet_bbs/boards/supervisor.ex` checked out at base commit `a66ef4a7` (before DOM-01 deletion). Same 13 failures, deterministic across seeds 0 and 1.

**Causal isolation:** DOM-01 deletes a no-op stub in `Foglet.Boards.Supervisor` that has no callers. `Foglet.TUI.AppTest` cannot reach it. The supervisor module compiles and links unchanged otherwise.

**Failure count:** `1 property, 2225 tests, 13 failures` when running `app_test.exs` alone (some failures appear to mask others when run in the full suite — full-suite run shows 5 failures intermittently).

**Failing tests (under `Foglet.TUI.AppTest`):**

1. `update/2 (SSH-06, SSH-08) {:screen_task_result, :post_composer, :submit_reply, result} routes through PostComposer local state`
2. `update/2 (SSH-06, SSH-08) navigating to post_reader initializes local state and queues generic post loading`
3. `update/2 (SSH-06, SSH-08) navigating post_reader from one thread to another refreshes route-owned local state`
4. `view/1 routing (SSH-07) renders without crashing for every current_screen value`
5. `PubSub message handlers (Audit #12) {:thread_activity, thread_id, event} on active :post_reader routes through local state`
6. `Phase 0 screen routing screen_module_for/1 maps :sysop — navigating and calling view/1 does not crash`
7. `App-routed sysop screen tasks (Phase 38) {:navigate, :sysop} on USERS-active state queues sysop screen task`
8. `App-routed sysop screen tasks (Phase 38) sysop task success sets slot to {:loaded, sub}`
9. `App-routed sysop screen tasks (Phase 38) sysop task forbidden result sets slot to {:error, :forbidden}`
10. `App-routed sysop screen tasks (Phase 38) sysop task timeout result sets slot to {:error, :timeout}`
11. `App-routed sysop screen tasks (Phase 38) {:navigate, :sysop} on SITE-active state emits no command (D-03 sync)`
12. `App-routed sysop screen tasks (Phase 38) {:navigate, :sysop} is idempotent — re-entering a {:loaded, _} tab emits no command`
13. `App-routed sysop screen tasks (Phase 38) all four lifecycle slots round-trip through screen task results`

**Disposition:** Defer to plan 46-04 (QUAL-03). The phase 46 baseline floor for D-14 will need to be re-stated against the actual current pass count once these are triaged.
