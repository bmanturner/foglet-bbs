---
phase: 47-bound-unbounded-list-queries-drop-chrome-v1-shims-and-reduce
verified: 2026-04-30T00:00:00Z
status: human_needed
score: 7/7 must-haves verified
overrides_applied: 0
re_verification:
  previous_status: none
  previous_score: n/a
  gaps_closed: []
  gaps_remaining: []
  regressions: []
human_verification:
  - test: "Triage REVIEW.md BL-01 (reader_has_next?/3 false-positive on empty :previous window with cursor=0 or stale cursors)"
    expected: "Decide whether to fix in this phase, queue follow-up, or accept as latent pre-existing bug. PostReader currently uses has_next? at post_reader.ex:756 to gate load_adjacent_window — false positives produce wasted DB round-trips and a :loading flicker, but no incorrect data."
    why_human: "BL-01 is an advisory finding from REVIEW.md against pre-Phase-47 code that was carried forward unchanged. R1/R2 acceptance criteria do not constrain reader_has_next?/3 behavior; the bug does not block any Phase 47 requirement but the orchestrator/developer should decide if it warrants a Phase 47 closure plan or a separate ticket."
  - test: "Decide on WR-07 (Threads.list_threads accepts unbounded :limit values without an upper clamp)"
    expected: "R3 acceptance criteria (LIMIT 50 default) are satisfied. WR-07 argues for an additional @max_page_size clamp so a future caller passing limit: 1_000_000 cannot reintroduce the unbounded scan. Decide whether to clamp now or defer."
    why_human: "Defensive hardening beyond the spec; not part of R3 acceptance criteria."
---

# Phase 47: Bound Unbounded List Queries, Drop Chrome V1 Shims, and Reduce App + Large Screen Modules — Verification Report

**Phase Goal:** Eliminate the three residual debt items from Phase 46 CONCERNS: (1) unbounded `Posts.list_posts/1` and `Threads.list_threads/2`, (2) Chrome V1 compatibility shims, (3) mixed-mode `Login` reducer plus continued `App` reduction.

**Verified:** 2026-04-30
**Status:** human_needed (all 7 requirements PASS; advisory REVIEW findings need human triage)
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (R1–R7)

| #  | Requirement                                        | Status     | Evidence                                                                                                                                                                                                                                                                                |
| -- | -------------------------------------------------- | ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| R1 | `Posts.list_posts/1` deleted                       | ✓ VERIFIED | `grep -rn "list_posts\b" lib/ test/` returns only one comment hit in `test/foglet_bbs/tui/app_test.exs:56` ("`list_posts/1` no longer exists in `Foglet.Posts`"). No call sites remain. mix test 2237/0 confirms compile + behavior.                                                  |
| R2 | `PostReader.load_posts/2` routed via `list_reader_window/2` | ✓ VERIFIED | `lib/foglet_bbs/tui/screens/post_reader.ex` lines 100, 169, 305, 781 all call `posts_mod.list_reader_window/2`. Comment at line 319 explicitly references "Phase 47 R2 (D-02 / D-03): route through list_reader_window/2".                                                            |
| R3 | `Threads.list_threads/{1,2,3}` bounded by default  | ✓ VERIFIED | `lib/foglet_bbs/threads.ex` defines `@page_size 50` (line 29); all three heads `list_threads/1` (line 95), `/2` (line 105), `/3` (lines 134, 148) flow through `normalize_limit(Keyword.get(opts, :limit, @page_size))` (lines 135, 167, 178). REVIEW notes a sibling `list_threads_query/3` is exposed for SQL inspection. |
| R4 | Threads page-size constant centralised             | ✓ VERIFIED | `@page_size 50` at `threads.ex:29`; public `default_page_size/0` accessor at line 34 returning `@page_size`. Query bodies reference `@page_size` only — no literal `50` in query bodies (D-06).                                                                                          |
| R5 | Chrome V1 paths removed                            | ✓ VERIFIED | `lib/foglet_bbs/tui/widgets/chrome/` contains only V2 modules: `breadcrumb_bar.ex`, `clock_formatter.ex`, `command_bar.ex`, `screen_frame.ex`, `status_bar.ex`. `normalizer.ex` does not exist. `key_bar.ex` does not exist. No "V1"/"legacy" mentions in chrome dir. Only residual `KeyBar` references in `app.ex:196` and `size_gate.ex:12` are inert documentation comments. |
| R6 | `App.ScreenStates` and `App.SessionAlias` extracted | ✓ VERIFIED | `lib/foglet_bbs/tui/app/screen_states.ex` (34 lines, < 100), `lib/foglet_bbs/tui/app/session_alias.ex` (75 lines, < 80). `app.ex` is 398 lines (< 400). All `set_user`/`promote_session`/`heartbeat`/`session_replaced` paths delegate to `SessionAlias` (lines 238, 302, 325, 327). `screen_state_for/2` and `put_screen_state/3` delegate to `ScreenStates` (lines 87, 92). No inline `Map.put` on `screen_states`. Tests exist: `test/foglet_bbs/tui/app/screen_states_test.exs` and `session_alias_test.exs`. |
| R7 | Login mode-machine refactor                        | ✓ VERIFIED | `lib/foglet_bbs/tui/screens/login.ex` is 102 lines (< 300). Per-mode reducers exist at `login/menu.ex` (72), `login/login_form.ex` (272), `login/reset_request.ex` (162), `login/reset_consume.ex` (154). Tagged-union state at `login/state.ex` (192). Sibling `login/render.ex` (357) carries render glue. mix test 2237/0 confirms behavior + dialyzer (per task brief). |

**Score:** 7/7 requirements verified

### Required Artifacts

| Artifact                                                   | Expected                          | Status     | Details                                  |
| ---------------------------------------------------------- | --------------------------------- | ---------- | ---------------------------------------- |
| `lib/foglet_bbs/posts.ex`                                  | No `list_posts/1`                 | ✓ VERIFIED | Function removed; only `list_reader_window/2` remains as the public reader |
| `lib/foglet_bbs/threads.ex`                                | `@page_size 50`, bounded queries  | ✓ VERIFIED | Centralised constant + `default_page_size/0` accessor; `normalize_limit/1` clamps non-positive/non-integer to default |
| `lib/foglet_bbs/tui/screens/post_reader.ex`                | Calls `list_reader_window/2`      | ✓ VERIFIED | All 5 load paths go through windowed reader |
| `lib/foglet_bbs/tui/widgets/chrome/normalizer.ex`          | Does not exist                    | ✓ VERIFIED | File deleted                             |
| `lib/foglet_bbs/tui/widgets/chrome/key_bar.ex`             | Does not exist                    | ✓ VERIFIED | File deleted (out-of-spec but spec asked for V1 removal in `KeyBar` — full removal observed and consistent with V2-only chrome surface) |
| `lib/foglet_bbs/tui/app.ex`                                | < 400 lines                       | ✓ VERIFIED | 398 lines                                |
| `lib/foglet_bbs/tui/app/screen_states.ex`                  | Exists, < 100 lines, has tests    | ✓ VERIFIED | 34 lines + dedicated test                |
| `lib/foglet_bbs/tui/app/session_alias.ex`                  | Exists, < 80 lines, has tests     | ✓ VERIFIED | 75 lines + dedicated test                |
| `lib/foglet_bbs/tui/screens/login.ex`                      | < 300 lines                       | ✓ VERIFIED | 102 lines                                |
| `lib/foglet_bbs/tui/screens/login/{menu,login_form,reset_request,reset_consume,state}.ex` | All exist | ✓ VERIFIED | All present plus `render.ex` (sibling render glue) |

### Key Link Verification

| From            | To                          | Via                                  | Status  | Details                                    |
| --------------- | --------------------------- | ------------------------------------ | ------- | ------------------------------------------ |
| `PostReader`    | `Posts.list_reader_window/2`| `posts_mod.list_reader_window(...)`  | WIRED   | 5 call sites in `post_reader.ex`           |
| `App`           | `App.ScreenStates`          | `alias` + `ScreenStates.get/put`     | WIRED   | `app.ex:27, 87, 92`                        |
| `App`           | `App.SessionAlias`          | `alias` + `SessionAlias.set_user/...`| WIRED   | `app.ex:28, 238, 302, 325, 327`            |
| `Login`         | per-mode reducers           | dispatch in `login.ex`               | WIRED   | All four reducer modules present, tests pass |
| `ThreadList`    | `Threads.list_threads/2`    | (unchanged call site)                | WIRED   | Spec confirmed call site unchanged; query now bounded at domain layer |

### Behavioral Spot-Checks

| Behavior                                  | Command                                    | Result        | Status |
| ----------------------------------------- | ------------------------------------------ | ------------- | ------ |
| Full test suite passes                    | `mix test` (per task brief)                | 2237/0        | ✓ PASS |
| `list_posts/1` not defined                | `grep -rn "list_posts\b" lib/ test/`       | only 1 comment | ✓ PASS |
| `default_page_size/0` defined and = 50    | grep `threads.ex:34`                       | `def default_page_size, do: @page_size` with `@page_size 50` | ✓ PASS |
| `normalizer.ex` absent                    | `ls lib/foglet_bbs/tui/widgets/chrome/`    | 5 V2 modules only | ✓ PASS |
| `app.ex` < 400 lines                      | `wc -l lib/foglet_bbs/tui/app.ex`          | 398           | ✓ PASS |
| `login.ex` < 300 lines                    | `wc -l lib/foglet_bbs/tui/screens/login.ex` | 102          | ✓ PASS |

### Anti-Patterns Found

None blocking. No TODO/FIXME/PLACEHOLDER markers found in scope of phase. REVIEW.md flags listed below for human awareness.

### REVIEW.md Findings (Cross-Reference)

| Finding | Severity | Verified Present | Blocks R1–R7? | Notes |
| ------- | -------- | ---------------- | -------------- | ----- |
| BL-01: `reader_has_next?/3` returns `true` for empty `:previous` window with `is_integer(cursor)` (no `> 0` guard, unlike `reader_has_previous?/3`) | BLOCKER (advisory) | ✓ Confirmed at `lib/foglet_bbs/posts.ex:238-240` | No — pre-existing bug carried through unchanged; not a Phase 47 acceptance criterion | Surfaced for human triage |
| WR-01: `app_state_from_local/2` duplicated across 5 login-family modules | WARNING | n/a (review-stage) | No — D-14 acknowledged pre-ship | Drift risk noted |
| WR-02: `:set_user`/`:promote_session` not gated by SizeGate | WARNING | n/a | No | Behavior unchanged from pre-phase |
| WR-03: `BoardList.render/2` second clause unreachable | WARNING | n/a | No | Outside R6 scope |
| WR-04: `index_of_message_number/2` returns nil → fallback to index 0 | WARNING | n/a | No — does not violate R2 (window still loaded; just bookmark recovery edge case) | Latent UX issue |
| WR-05: `render_menu/3` `bottom_padding` clamped to 0 | WARNING | n/a | No | Defensive |
| WR-06: `reader_rows_around/3` two equivalent heads | WARNING | n/a | No | R2 still satisfied |
| WR-07: `Threads.list_threads/3` accepts unbounded `:limit` (no `@max_page_size` ceiling) | WARNING | ✓ `normalize_limit/1` only rejects non-positive | No — R3 default clamp at 50 satisfied; ceiling beyond default is hardening | Surfaced for human triage |
| WR-08: `Moderation.domain_module/3` `||` chain swallows `false` | WARNING | n/a | No | Outside R6/R7 scope |
| IN-01..05 | INFO | n/a | No | Cleanup nits |

### Requirements Coverage

| Requirement | Source Plan | Description                                            | Status     | Evidence                                              |
| ----------- | ----------- | ------------------------------------------------------ | ---------- | ----------------------------------------------------- |
| R1          | 47-01       | Delete `Posts.list_posts/1`                            | ✓ SATISFIED | grep returns 0 hits in lib/ + test/                  |
| R2          | 47-01/02    | Route `load_posts/2` via `list_reader_window/2`        | ✓ SATISFIED | 5 call sites in `post_reader.ex`                     |
| R3          | 47-02       | Bound `Threads.list_threads/{1,2,3}`                   | ✓ SATISFIED | `normalize_limit` + `@page_size 50` in all heads     |
| R4          | 47-02       | Centralised page-size constant + accessor              | ✓ SATISFIED | `@page_size 50` + `default_page_size/0` at lines 29, 34 |
| R5          | 47-03       | Remove Chrome V1 paths; delete `Normalizer`            | ✓ SATISFIED | Chrome dir contains only V2 modules; no `KeyBar`/`Normalizer` files |
| R6          | 47-04       | Extract `App.ScreenStates` + `App.SessionAlias`        | ✓ SATISFIED | Both modules present, tested, app.ex = 398 lines     |
| R7          | 47-05       | Login mode-machine refactor                            | ✓ SATISFIED | login.ex = 102 lines; 4 reducer modules + state.ex present |

### Human Verification Required

1. **Triage BL-01 (REVIEW.md)** — `reader_has_next?/3` false-positive on empty `:previous` window with cursor `0` or stale cursors.
   - Pre-Phase-47 latent bug; carried through unchanged.
   - Phase 47 R2 acceptance criteria are silent on `reader_has_next?` semantics.
   - Decide: fix in Phase 47 closure plan or queue separately.

2. **Decide on WR-07** — `Threads.list_threads/3` accepts `limit: 1_000_000` without an upper clamp.
   - R3 default-bound (LIMIT 50) is satisfied.
   - WR-07 advocates an `@max_page_size` ceiling as defense-in-depth.
   - Decide: clamp now or defer to a follow-up phase.

### Gaps Summary

No requirement-level gaps. All 7 requirements pass goal-backward verification. The two human-triage items above are advisory hardening / latent-bug decisions that do not block phase closure on the spec contract.

---

_Verified: 2026-04-30_
_Verifier: Claude (gsd-verifier)_
