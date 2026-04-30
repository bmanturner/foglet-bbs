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

## Pre-existing credo --strict warning in `lib/foglet_bbs/sessions/session.ex:196`

**Discovered during:** Plan 46-02 Task 3 (cadence gate).

**Verified pre-existing:** Yes. The warning fires against unmodified code at session.ex:196 — content unchanged from base commit c672accb. The plan-02 edits are confined to `lib/foglet_bbs/boards/server.ex` (moduledoc + two single-line comments above `|> Repo.transaction()` calls); they cannot influence Logger metadata configuration in `Foglet.Sessions.Session`.

**Warning text:**

```
[W] Logger metadata key event, session_pid, user_id, handle, ssh_peer,
    replacement not found in Logger config.
    lib/foglet_bbs/sessions/session.ex:196 #(Foglet.Sessions.Session.handle_cast)
```

**Effect:** `mix credo --strict` exits 16, which causes `mix precommit` to exit 16. `mix compile --warnings-as-errors`, `mix format --check-formatted`, and `mix sobelow --exit Low` all pass.

**Disposition:** Defer to plan 46-04 (QUAL-03). The fix is to register the missing Logger metadata keys in runtime config (or the Sessions Logger setup) — out of scope for DOM-02 documentation-only work.

## Pre-existing dialyzer warnings unrelated to phase 46 scope

**Discovered during:** Plan 46-03 Task 1 (initial dialyzer baseline run).

**Verified pre-existing:** Yes. Reproduced against base commit `a66ef4a7` before any phase 46 work; identical four warnings. Files were last modified during phase 45.

**Active warnings (not silenced by `.dialyzer_ignore.exs`):**

```
lib/foglet_bbs/ssh/cli_handler.ex:554:unmatched_return
  The expression produces a value of type:
    nil | [integer()] | integer()
  but this value is unmatched.

lib/foglet_bbs/ssh/cli_handler.ex:467:8:pattern_match
  The pattern can never match the type.
  Pattern: nil
  Type:    pid()

lib/foglet_bbs/tui/screens/post_reader/render.ex:26:guard_fail
  The guard clause:
    when _ :: {pos_integer(), pos_integer()} === nil
  can never succeed.
```

`lib/foglet_bbs/posts/reader_window.ex:14:23:unknown_type` (`Foglet.Posts.Post.t/0`) was the fourth pre-existing warning; plan 46-03 Task 3 added it to Bucket A of the cleaned `.dialyzer_ignore.exs` since it is the same Ecto schema `t/0` false positive class as the other Bucket A entries.

**Effect:** `rtk mix dialyzer` exits 2 with these three warnings, which propagates through `mix precommit`. Plan 46-03's QUAL-01 work (boards/server `:call_without_opaque` fix; C1 narrow pass; ignore-file restructure) is unaffected — the in-scope work introduced no new warnings, and the ignore-list line count is now 46 (down from 54 baseline) with every kept entry annotated.

**Disposition:** Defer to plan 46-04 (QUAL-03). These are real dialyzer hints in `cli_handler.ex` (unmatched `decrement_connection_count/0` return, `nil` pattern-match against `pid()`-typed `lifecycle_pid`) and `post_reader/render.ex` (guard against `nil` on a `terminal_size`-typed parameter that is always a tuple). All three are confined to files modified in phase 45 and can be triaged alongside the other QUAL-03 baseline work.

## Two unnecessary skips on the cleaned `.dialyzer_ignore.exs`

**Discovered during:** Plan 46-03 Task 3 (post-cleanup verification).

**Verified pre-existing:** Yes. The two `:no_match` string-pattern entries on `lib/foglet_bbs/tui/screens/account/prefs_form.ex` and `account/profile_form.ex` are reported by dialyxir as "Unnecessary Skips" — meaning dialyzer no longer emits the `"The pattern can never match the type true."` warning at those locations.

**Disposition:** Per CONTEXT D-06, these entries are **kept verbatim** even though they no longer match an active warning. The locked decision is to preserve the existing inline rationale documenting the Phase 25 defensive-fallback intent; removing them would erase the design comment. The "Unnecessary Skips: 2" line in dialyxir output is informational only (does not affect exit status).
