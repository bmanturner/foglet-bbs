# Codebase Concerns

**Analysis Date:** 2026-04-30

This document inventories tech debt, fragile areas, security considerations,
and under-tested zones for Foglet BBS as of v2.1 close (Phase 46 complete).
The previous CONCERNS audit (2026-04-29) annotated every v2.0 concern with a
`Disposition` line; the bulk of those items are now `Fixed` or `Covered`. This
refresh removes resolved entries and surfaces only concerns that still exist
in the current tree, plus several pre-existing issues newly catalogued during
Phase 46 (`deferred-items.md`).

The codebase is in a healthy state: most domain/runtime concerns surfaced in
v2.0 have been addressed across Phases 41-46. Remaining items are bounded
debt, defensive code paths, or pre-existing issues that were already routed
to a future cleanup phase.

## Tech Debt

### `mix precommit` does not currently pass cleanly

- Issue: `mix precommit` exits 16 due to a `credo --strict` warning about
  unregistered Logger metadata keys. `mix dialyzer` also exits 2 with three
  pre-existing hints. None block compilation, formatting, or Sobelow, but the
  precommit gate is effectively red.
- Files:
  - `lib/foglet_bbs/sessions/session.ex:196` — Logger metadata keys `event`,
    `session_pid`, `user_id`, `handle`, `ssh_peer`, `replacement` are not
    declared in Logger config.
  - `lib/foglet_bbs/ssh/cli_handler.ex:467` — `pattern_match` warning: a
    `nil` clause against a `pid()`-typed `lifecycle_pid` parameter that the
    success-typing says can never be `nil`.
  - `lib/foglet_bbs/ssh/cli_handler.ex:554` — `unmatched_return` on the
    `decrement_connection_count/0` return value (`nil | [integer()] | integer()`).
  - `lib/foglet_bbs/tui/screens/post_reader/render.ex:26` — `guard_fail` on a
    `nil` guard against a `terminal_size` parameter typed as
    `{pos_integer(), pos_integer()}`.
- Impact: Every contributor running the documented finish-line gate
  (`rtk mix precommit`) sees red output. The signal-to-noise ratio of the
  gate erodes; new real warnings can hide in the same exit code.
- Fix approach:
  - Register the Sessions Logger metadata keys in `config/config.exs` (or
    a dedicated `Logger.metadata/1` setup in the Sessions supervisor).
  - For the cli_handler warnings: either narrow `lifecycle_pid` to
    `pid() | nil` and keep the defensive nil clause, or drop the
    unreachable clause. Match `decrement_connection_count/0` with `_ =`.
  - For `post_reader/render.ex:26`: drop the unreachable nil guard or widen
    the `terminal_size` type alias.
- Tracked in: `.planning/phases/46-domain-cleanup-and-final-quality-gate/deferred-items.md`.

### `Foglet.TUI.AppTest` has 13 pre-existing failures

- Issue: `mix test test/foglet_bbs/tui/app_test.exs` reports 13 failures
  (5-13 intermittently in full-suite runs). The root cause is a
  `FakePosts.list_reader_window/2` undefined function in the test mock —
  PostReader migrated from `list_posts/1` to `list_reader_window/2` during
  Phase 44 but the test mock was not updated.
- Files:
  - `test/foglet_bbs/tui/app_test.exs:52-65` (FakePosts mock).
  - `lib/foglet_bbs/posts.ex:106-107` (real `list_reader_window/2`).
- Impact: AppTest no longer provides full coverage of route hydration,
  PubSub dispatch, sysop screen-task lifecycle, or PostReader navigation
  through the App layer. A regression on any of those surfaces would be
  masked by the existing failures.
- Fix approach: Add `list_reader_window/2` to FakePosts returning a
  `Foglet.Posts.ReaderWindow.t()` consistent with the real query shape.
  Verify all 13 listed tests recover.
- Tracked in: `.planning/phases/46-domain-cleanup-and-final-quality-gate/deferred-items.md`.

### Verify-screen state typing is half-narrowed

- Issue: `Foglet.TUI.Screens.Verify.State` introduces `@type t/0` and applies
  it to readers and `default/0` / `put/2`, but the two mutators
  `record_invalid_attempt/3` and `after_resend/2` keep `map() :: map()`
  specs even though every caller feeds a value returned from `get/1` (which
  the new contract promises is `t()`).
- Files:
  - `lib/foglet_bbs/tui/screens/verify/state.ex:74` (`record_invalid_attempt/3`).
  - `lib/foglet_bbs/tui/screens/verify/state.ex:95` (`after_resend/2`).
  - Callers: `lib/foglet_bbs/tui/screens/verify.ex:216,241`.
- Impact: Documentation drift only — the typing story for the module is
  inconsistent (`t()` for reads, `map()` for writes). No behavioural risk;
  no Pitfall-1 plain-map caller pressure (unlike `register/state.ex`).
- Fix approach: Change both specs to `t() :: t()` and rerun dialyzer.
  Both function bodies return `%{vs | ...}` over a struct-shaped map; the
  return narrowing is sound.
- Source: Phase 46 review WR-01 (`46-REVIEW.iter1.md`).

### `.dialyzer_ignore.exs` Bucket A header rationale is not fully accurate

- Issue: Bucket A's header reads "Mostly Ecto schemas where dialyzer cannot
  resolve `t/0` from `use Ecto.Schema`. `posts/reader_window.ex` is included
  because its `t/0` references `Foglet.Posts.Post.t/0`...". The
  reader_window inclusion was added during Phase 46 to silence a propagated
  unresolved-type warning, not because the module is itself an Ecto schema.
  The Phase 46 D-07 invariant commits to "every kept entry has a stated
  reason"; this entry has a stated reason but the bucket header makes it
  non-obvious.
- Files: `.dialyzer_ignore.exs:5-15`.
- Impact: Honesty/maintainability footgun. A future reader running the
  invariant audit may miss why reader_window is in this bucket. Behaviour
  unchanged.
- Fix approach: Already applied in part during Phase 46 fix iter — the
  header now mentions reader_window explicitly. If further drift accumulates,
  split into A1 (schemas) and A2 (propagated-from-schema) buckets.
- Source: Phase 46 review WR-02 (`46-REVIEW.iter1.md`).

### Two "unnecessary skip" entries kept in `.dialyzer_ignore.exs` for documentation

- Issue: The `:no_match` string-pattern entries on
  `lib/foglet_bbs/tui/screens/account/prefs_form.ex` and
  `account/profile_form.ex` no longer match active warnings — dialyxir
  reports "Unnecessary Skips: 2" for them. They are intentionally retained
  per Phase 46 CONTEXT D-06 because the inline rationale documents the
  Phase 25 defensive-fallback design intent.
- Files: `.dialyzer_ignore.exs:43-47`.
- Impact: Minor noise in dialyxir output. Locked decision; should be
  revisited only if the underlying defensive `:no_match` clauses in the
  forms are removed.
- Fix approach: Leave as-is until the Account form code itself is
  refactored. At that point, decide whether to delete the defensive clause
  along with its ignore entry, or document the intent inline in the
  source instead.

### Legacy Chrome V1 / flat-key-hint compatibility shims

- Issue: `Foglet.TUI.Widgets.Chrome.KeyBar`, `ScreenFrame`, `StatusBar`,
  and `Normalizer` carry explicit "compatibility wrapper for legacy flat
  key hint lists" / "legacy screen title string or Chrome V2 model" code
  paths. Both legacy `{key, description}` tuples and Chrome V2 grouped
  command bars are supported.
- Files:
  - `lib/foglet_bbs/tui/widgets/chrome/key_bar.ex:3-16`.
  - `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex:14-191`.
  - `lib/foglet_bbs/tui/widgets/chrome/status_bar.ex:42-101`.
  - `lib/foglet_bbs/tui/widgets/chrome/normalizer.ex:3-28`.
- Impact: Two shapes for the same data wherever chrome is rendered. Each
  caller has to know whether it's emitting V1 or V2 data; bug-fixes need
  to be tested against both branches.
- Fix approach: Audit screen call sites for remaining V1 emitters,
  migrate them to V2 grouped commands, then drop the normalizer/legacy
  branches. Deferred while migration is in progress.

### `Foglet.TUI.App` is still 483 lines and concentrates routing + effects

- Issue: After Phase 42 extracted `App.Routing`, `App.Modal`, `App.Effects`,
  and `App.Subscriptions`, the App module is down from 1006 to 483 lines —
  but it is still the largest non-screen module in `lib/` and still owns
  the runtime callbacks, screen-state plumbing, generic effect dispatch,
  and the `set_user`/`promote_session` aliasing.
- Files: `lib/foglet_bbs/tui/app.ex`.
- Impact: Adding a new screen still requires touching App in several
  places (route table, initial-route hook, novel effect dispatch). The
  blast radius is much smaller than v2.0 but non-trivial.
- Fix approach: Continue extracting helpers as new screen patterns
  emerge. No urgent refactor needed at current size.

### Several screen modules remain large

- Issue: After Phase 43 decomposition the largest screens are now:
  - `lib/foglet_bbs/tui/screens/post_reader.ex` — 867 lines
  - `lib/foglet_bbs/tui/widgets/modal/form.ex` — 683 lines
  - `lib/foglet_bbs/tui/screens/main_menu.ex` — 646 lines
  - `lib/foglet_bbs/tui/screens/sysop/boards_view.ex` — 644 lines
  - `lib/foglet_bbs/tui/screens/login.ex` — 606 lines
  - `lib/foglet_bbs/ssh/cli_handler.ex` — 590 lines
- Files: see paths above.
- Impact: Reducer logic and render/state helpers are split into sibling
  modules per Phase 43, but the primary reducer files still concentrate
  multi-mode key handling (especially `login.ex` with its menu /
  login_form / reset_request / reset_consume modes — see also the
  `:contract_supertype` ignore entry for that module's tagged-union
  problem).
- Fix approach: Login and Register would benefit from a tagged-union
  state refactor (called out in `46-CONTEXT D-03` as out of scope).
  PostReader is at its natural size given the bounded-window reducer +
  PubSub plumbing. Modal Form is a large widget by necessity.

## Known Bugs

No outstanding production bugs are tracked. The 13 AppTest failures and
3 unsilenced dialyzer warnings catalogued under Tech Debt above are
pre-existing test/typing-only issues, not user-visible bugs.

## Security Considerations

### `secret_key_base` committed to `config/dev.exs`

- Risk: `config/dev.exs:26` carries a literal `secret_key_base` string. This
  is the conventional Phoenix-generator behaviour for dev configs and is
  not used in production (production reads from `runtime.exs` /
  environment), but a git-history search would surface it.
- Files: `config/dev.exs:26`.
- Current mitigation: Production `secret_key_base` is environment-driven
  via `config/runtime.exs`. The dev secret is not used outside developer
  laptops.
- Recommendations: Either move the dev secret to `.env.local` (already
  sourced by `runtime.exs`) and generate a per-developer value, or accept
  the convention and document it explicitly.

### SSH guest-session promotion remains best-effort logged

- Risk: Phase 45 added structured `ssh_peer` audit metadata to guest→user
  promotions, but the audit goes through `Logger.info` rather than a
  dedicated audit row. Forensic reconstruction depends on log retention.
- Files: `lib/foglet_bbs/sessions/session.ex:196-203`.
- Current mitigation: Structured Logger metadata (peer IP, replacement
  marker, session pid) is attached to every promotion event. The
  `Foglet.SSH.PubkeyStash` TTL/sweep cleanup added in Phase 45 bounds the
  stash lifetime.
- Recommendations: For audit-heavy deployments, persist promotions to a
  dedicated `auth_events` table tied to `user_id` and peer context. Out
  of scope for v2.1.

### `Foglet.SSH.RateLimiter` fails open on ETS unavailability

- Risk: `RateLimiter.allow?/1` returns `true` (allow connection) if its
  ETS table is unavailable — for example during RateLimiter restart.
  Comment at `rate_limiter.ex:35` explicitly documents this as
  "Fail open if the ETS table is unavailable".
- Files: `lib/foglet_bbs/ssh/rate_limiter.ex:30-40`.
- Current mitigation: The hard 500-connection global ceiling in
  `Foglet.SSH.CLIHandler.check_connection_limit/0` still applies; a
  rate-limiter outage cannot lift the ceiling.
- Recommendations: Acceptable trade-off (fail-open during restart vs
  fail-closed and lock everyone out). Document in the operator playbook
  if/when one is written.

## Performance Bottlenecks

### `Foglet.Posts.list_posts/1` still loads every post in a thread

- Problem: `list_posts/1` returns every non-paginated post in a thread,
  ordered by `inserted_at` ascending, with `:user` preloaded. PostReader
  no longer uses this path (Phase 44 routed PostReader through
  `list_reader_window/2`), but other consumers — moderation views,
  search/export, future API surfaces — still hit the unbounded query.
- Files:
  - `lib/foglet_bbs/posts.ex:84-92` (`list_posts/1`).
  - `lib/foglet_bbs/posts.ex:106-107` (`list_reader_window/2` — bounded).
- Cause: `list_posts/1` is the legacy unbounded reader; bounded callers
  have migrated but the function itself is still public API.
- Improvement path: Audit remaining call sites. If they all tolerate
  a bounded variant, deprecate `list_posts/1` and migrate them. Otherwise
  document the unbounded contract and add a `LIMIT` ceiling guard.

### `Foglet.Threads.list_threads/2` runs a per-thread aggregation join

- Problem: When called with a `user_id`, `list_threads/2` joins thread
  read-pointer rows and computes per-thread unread state. No `LIMIT` is
  applied; very active boards return all threads.
- Files: `lib/foglet_bbs/threads.ex:106-152`.
- Cause: Board view requirements include "show every thread with unread
  state". Boards with thousands of threads will blow up the response.
- Improvement path: Add cursor pagination keyed by activity timestamp.
  Same shape as the PostReader bounded-window pattern from Phase 44.

## Fragile Areas

### Render-path purity invariant on PostReader is partially enforced

- Files: `lib/foglet_bbs/tui/screens/post_reader.ex:33-39`,
  `lib/foglet_bbs/tui/screens/post_reader/render.ex`.
- Why fragile: The moduledoc invariant ("No `defp render_*` helper may
  perform state writes") is now backed by a render module split (Phase
  43) and a Phase 44 hardening (`44-03-SUMMARY.md`) that scans the
  render module for forbidden state writes during tests. The reducer
  module still contains some `defp` helpers that look render-adjacent
  but are intentionally state-mutating (`warm_cache/4`, `warm_viewport/4`,
  `apply_flush_result/4`). The naming convention (`warm_` and friends
  for mutators, `render_` reserved for render module) is enforced by
  convention plus the test scan.
- Safe modification: New PostReader helpers must live in the appropriate
  module (`render.ex` for pure functions, `post_reader.ex` for reducer
  state plumbing). Adding a `defp render_*` to `post_reader.ex` would
  bypass the scan.
- Test coverage: Render-purity guard test (Phase 44) + render module
  decomposition (Phase 43).

### `Foglet.SSH.CLIHandler` cleanup is centralized but reads with stale dialyzer hints

- Files: `lib/foglet_bbs/ssh/cli_handler.ex` (entire file, especially
  `cleanup/2`, `decrement_connection_count/0`, lifecycle clauses).
- Why fragile: Phase 45 unified termination paths through a single
  `cleanup/2` helper with `cleanup_done?` and `counter_counted?` guards
  for exactly-once semantics across normal close, EOF, lifecycle EXIT,
  over-limit reject, rate-limit reject, and crash-during-init. The
  dispatch logic is now correct but dialyzer flags two real-looking
  hints (the `nil` pattern against `lifecycle_pid` and the unmatched
  `decrement_connection_count/0` return). These hints look like real
  bugs at first glance even though the runtime invariant holds.
- Safe modification: Any new termination path must funnel through
  `cleanup/2`. The dialyzer hints should be cleaned up so future
  warnings stand out.
- Test coverage: Connection-counter lifecycle proof tests and idempotent
  cleanup tests landed in Phase 45 (`45-03-SUMMARY.md`).

### Session replacement race window (`replace_then_promote`)

- Files: `lib/foglet_bbs/sessions/supervisor.ex:124-181`,
  `lib/foglet_bbs/sessions/session.ex:165-188`.
- Why fragile: Two-step protocol — send `:replaced_by_new_session`,
  monitor, wait up to 2s for `:DOWN`, fall through to
  `DynamicSupervisor.terminate_child` / `Process.exit(_, :kill)`. The
  `Process.exit/2` fall-through is a real path (not just defensive),
  kept for cases where `old_pid` is not a supervised child (test setup
  or partial crash). After the timeout, a fresh promote is cast even if
  termination was forced; the new session may briefly observe a Registry
  race.
- Safe modification: Any change to one-session-per-user must preserve
  the protocol that `promote_to_user/2` is only cast once the Registry
  slot is free. The `handle_cast({:promote_to_user, user}, ...)` clause
  explicitly logs an `error` if registration finds the slot held — this
  guard is load-bearing.
- Test coverage: Direct tests of replacement timing exist; the
  forced-termination (2s timeout) branch is rarely exercised under
  realistic load.

## Test Coverage Gaps

### `replace_then_promote/3` 2s-timeout fallback path

- What's not tested: The `Process.exit(old_pid, :kill)` branch inside
  the timeout, which fires only when
  `DynamicSupervisor.terminate_child/2` returns `{:error, _reason}`
  because `old_pid` is not a supervised child.
- Files: `lib/foglet_bbs/sessions/supervisor.ex:124-153`.
- Risk: Path is exercised in the wild when an old session crashed
  mid-replace but the Registry slot lingers. Loud-logged but otherwise
  silent on the outside.
- Priority: Low. Defensive code; exercising it requires careful test
  setup with hand-managed pids. Phase 45 hardened SSH-side cleanup but
  did not add coverage for this Sessions-side fallback.

### `Foglet.TUI.AppTest` is broken; route + PubSub coverage is partial

- What's not tested: 13 tests under `Foglet.TUI.AppTest` are currently
  failing due to an outdated `FakePosts` mock (see Tech Debt above).
  Affected coverage areas include sysop screen-task lifecycle, PostReader
  navigation hydration, and PubSub `:thread_activity` dispatch.
- Files: `test/foglet_bbs/tui/app_test.exs`.
- Risk: A regression on any of these surfaces is masked by the existing
  failures. Severity scales with how many of those features the
  regression touches.
- Priority: Medium. The fix is mechanical (extend FakePosts).

### Soft-delete-aware list paths

- What's not tested: A blanket assertion that every `Foglet.Posts.*`
  list/summary query applies `Foglet.QueryHelpers.not_deleted/1`.
  Phase 44 added focused coverage for the most-trafficked list paths
  (`44-04-SUMMARY.md`), but a property-style invariant test (every
  list query under `Foglet.Posts` excludes tombstones unless explicitly
  opted in) is not present.
- Files: `lib/foglet_bbs/posts.ex`, `lib/foglet_bbs/threads.ex`,
  `lib/foglet_bbs/query_helpers.ex:11-14`.
- Risk: A future query that forgets the filter renders deleted post
  bodies in a list. Most-trafficked paths are covered; less-trafficked
  paths (search, export, moderation queues) may not be.
- Priority: Low — Phase 44 closed the highest-risk surfaces.

---

*Concerns audit: 2026-04-30*
