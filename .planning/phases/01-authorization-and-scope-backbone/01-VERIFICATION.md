---
phase: 01-authorization-and-scope-backbone
verified: 2026-04-24T14:09:58Z
status: passed
score: 3/3 must-haves verified
overrides_applied: 0
---

# Phase 1: Authorization and Scope Backbone Verification Report

**Phase Goal:** Operator actions are gated by actor-aware, scope-aware policy before sysop and moderation surfaces gain real behavior.
**Verified:** 2026-04-24T14:09:58Z
**Status:** passed
**Re-verification:** No -- initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Moderation and operator actions are enforced through actor-aware authorization rather than screen-only visibility checks. | VERIFIED | `Foglet.Authorization` implements `Bodyguard.Policy` and returns explicit decisions; `Foglet.Boards.create_category/2`, `update_category/3`, `archive_category/2`, `create_board/3`, `update_board/3`, `archive_board/2`, and `Foglet.Config.put/3` call `Bodyguard.permit/4` before mutation. Tests cover allowed sysop paths and forbidden mod/user/nil paths. |
| 2 | The authorization seam supports at least `:site` and `{:board, board_id}` scopes so future board-scoped moderation does not require API rewrites. | VERIFIED | `Foglet.Authorization.scope` type includes `:site | {:board, Ecto.UUID.t()}`; policy matrix covers both site and board scopes; `Foglet.Boards.scope_for/1`, `Foglet.Threads.scope_for/1`, and `Foglet.Posts.scope_for/1` return `{:board, id}` tuples. |
| 3 | Unauthorized operator actions return explicit forbidden results instead of silently succeeding or relying on hidden UI controls. | VERIFIED | Policy clauses return `{:error, :forbidden}` for nil, deleted, suspended, pending, unknown action, and unmatched actors/actions. Domain tests assert forbidden calls do not mutate DB rows. Bodyguard passthrough test confirms explicit `{:error, :forbidden}` is preserved. |

**Score:** 3/3 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `mix.exs` / `mix.lock` | Bodyguard dependency available | VERIFIED | `mix.exs` declares `{:bodyguard, "~> 2.4"}` and `mix.lock` resolves Bodyguard 2.4.3. Review fix removed the stale direct `raxol` Hex lock entry while preserving valid transitive Raxol packages. |
| `lib/foglet_bbs/authorization.ex` | Single Bodyguard policy source of truth | VERIFIED | Defines `@behaviour Bodyguard.Policy`, action allowlists, invalid-actor guards, unknown-action warning, sysop/mod/user rules, and `scopes_for/2`. No stub markers found. |
| `lib/foglet_bbs/boards.ex` | Actor-first board/category operator gates and board scope helper | VERIFIED | Board/category actor-aware functions call `Bodyguard.permit/4` at `:site` before Repo writes. `scope_for/1` returns `{:board, board.id}`. |
| `lib/foglet_bbs/config.ex` | Actor-aware config writer | VERIFIED | `put/3` authorizes `:edit_config` before validation or `do_put!/3`; returns tagged errors including `:forbidden`, `:unknown_key`, `:invalid_value`, and review-fixed `:db_error`. `put!/3` remains trusted bang path. |
| `lib/foglet_bbs/threads.ex` | Thread board-scope helper without Phase 8 signature changes | VERIFIED | `scope_for(%Thread{board_id: board_id})` returns `{:board, board_id}`. Existing thread operator functions still have non-actor signatures, matching D-20 deferral. |
| `lib/foglet_bbs/posts.ex` | Post board-scope helper without Phase 8 signature changes | VERIFIED | `scope_for(%Post{board_id: board_id})` returns `{:board, board_id}`. Existing post operator functions still have non-actor signatures, matching D-20 deferral. |
| Test files under `test/foglet_bbs/...` | Regression coverage for policy, domain gates, config, and scope helpers | VERIFIED | Focused test run covered authorization, boards, config, threads, and posts: 172 tests, 0 failures. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `lib/foglet_bbs/authorization.ex` | Bodyguard | `@behaviour Bodyguard.Policy` and `Bodyguard.permit/4` callers | WIRED | Policy module is loaded by `Bodyguard.permit/4` in tests and domain contexts. |
| `lib/foglet_bbs/boards.ex` | `Foglet.Authorization` | `Bodyguard.permit(Foglet.Authorization, action, actor, :site)` | WIRED | All actor-aware category and board mutations guard before Repo writes. |
| `lib/foglet_bbs/config.ex` | `Foglet.Authorization` | `Bodyguard.permit(Foglet.Authorization, :edit_config, actor, :site)` | WIRED | Authorization runs before schema validation and DB/ETS mutation. |
| `lib/foglet_bbs/boards.ex`, `threads.ex`, `posts.ex` | Future board-scoped moderation call sites | `scope_for/1` helpers returning `{:board, _}` | WIRED | Helpers exist and are tested with plain structs and persisted fixtures where applicable. Future Phase 8 consumes the seam. |
| Tests | Implementation | Direct calls to `Bodyguard.permit/4`, `Config.put/3`, board functions, and `scope_for/1` | WIRED | Manual grep verified direct test coverage. `gsd-sdk verify.key-links` had false negatives for escaped regexes in plan metadata, so links were checked manually. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `Foglet.Authorization.authorize/3` | actor/action/scope | Caller-provided actor and action scope through Bodyguard | Yes | VERIFIED -- policy returns live decisions from struct fields and allowlists, not static placeholders. |
| `Foglet.Authorization.scopes_for/2` | actor role/status/deleted state | `Foglet.Accounts.User` struct | Yes | VERIFIED -- sysop/mod produce `[:site]`; invalid actors and regular users produce `[]`. |
| `Foglet.Boards.scope_for/1` | board id | `%Board{id: id}` | Yes | VERIFIED -- returns the actual struct id. |
| `Foglet.Threads.scope_for/1` | thread board id | `%Thread{board_id: board_id}` | Yes | VERIFIED -- returns the actual struct board id. |
| `Foglet.Posts.scope_for/1` | post board id | `%Post{board_id: board_id}` | Yes | VERIFIED -- returns the actual struct board id. |
| `Foglet.Config.put/3` | config key/value | `Schema.validate/2` and `do_put!/3` | Yes | VERIFIED -- success path writes through existing DB-backed config upsert and invalidates ETS. |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Focused authorization backbone tests pass | `rtk mix test test/foglet_bbs/authorization_test.exs test/foglet_bbs/authorization/bodyguard_passthrough_test.exs test/foglet_bbs/boards/boards_test.exs test/foglet_bbs/config_test.exs test/foglet_bbs/threads/threads_test.exs test/foglet_bbs/posts/posts_test.exs` | 172 tests, 0 failures | PASS |
| Project compiles with warnings as errors | `rtk mix compile --warnings-as-errors` | Exit 0 after approved escalation for Mix local PubSub socket; only vendored Raxol warnings printed before project compile completed | PASS |
| Full project precommit gate | `rtk mix precommit` | Passed compile, format, Credo, Sobelow, and Dialyzer; Dialyzer reported 84 skipped warnings, all ignored | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| MODR-02 | 01-01, 01-04 | Moderation workspace only shows actions and data for scopes the current operator is authorized to manage. | SATISFIED | `scopes_for/2` provides operator visibility scopes; board/thread/post `scope_for/1` helpers provide stable `{:board, id}` target scopes for future moderation operations. Phase 8 populates the workspace using this seam. |
| MODR-03 | 01-01, 01-02, 01-03 | Moderation actions exposed in v1.1 are enforced through actor-aware authorization rather than screen-only visibility checks. | SATISFIED | Bodyguard policy exists and board/category/config operator mutations are actor-aware. Unauthorized paths return `{:error, :forbidden}` and tests assert no DB mutation on forbidden board/config/category paths. |

No additional Phase 1 requirement IDs were found in `.planning/REQUIREMENTS.md`.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| N/A | N/A | No TODO/FIXME/PLACEHOLDER, empty return, or hardcoded hollow-data patterns found in phase files | Info | No blocker or warning anti-patterns identified. |

### Review Findings

| Finding | Status | Verification |
|---------|--------|--------------|
| WR-01 stale `raxol` lock source | Fixed | Direct `raxol` Hex lock entry is absent; `mix.exs` retains path dependency and valid transitive Raxol Hex packages remain. |
| WR-02 `Board.changeset/2` casts `:category_id` | Accepted residual design risk | `01-REVIEW-FIX.md` records this was intentionally skipped because board category reassignment is desired product behavior. It does not block Phase 1's authorization/scope goal. |
| WR-03 `Config.put/3` exception escape | Fixed | `put/3` now rescues DB errors and returns `{:error, :db_error}` with spec updated. |
| WR-04 `move_thread/2` discarded `update_all` return | Fixed | Return value is pattern matched as `{_count, nil}` inside the transaction. |
| IN-01 Logger require location | Fixed | `require Logger` is module-level in `Foglet.Authorization`. |
| IN-02 sysop board-scoped policy coverage | Fixed | Authorization matrix includes sysop `:create_board` and `:edit_config` at `{:board, @board_id}`. |
| IN-03 fixture doc note | Fixed | `board_fixture/2` documents the `allow_board_server!` requirement for tests using the board server. |

### Human Verification Required

None. This phase is backend authorization/scope plumbing with automated behavioral coverage and no visual or external-service behavior to manually verify.

### Gaps Summary

No phase-blocking gaps found. The implementation achieves the Phase 1 goal: operator-facing mutation seams are actor-aware, the scope shape supports both site and board targets, unauthorized paths return explicit forbidden tuples, and focused plus precommit checks pass.

---

_Verified: 2026-04-24T14:09:58Z_
_Verifier: Claude (gsd-verifier)_
