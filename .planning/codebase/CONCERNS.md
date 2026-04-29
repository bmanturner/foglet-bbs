# Codebase Concerns

**Analysis Date:** 2026-04-29

This document inventories tech debt, fragile areas, security considerations, and
under-tested zones for Foglet BBS as of v2.0 close (Phase 40 complete). The
post-Phase-40 codebase passes `rtk mix precommit` and the full `rtk mix test`
suite (1 property + 2161 tests, 0 failures), so most concerns below are latent
risks, bounded compatibility shims, or ergonomic debt — not active failures.

## Tech Debt

### TUI: Bounded compatibility callback surface still attached to `Foglet.TUI.Screen`

- Issue: `Foglet.TUI.Screen` still declares `render/1`, `handle_key/2`, and
  `init_screen_state/1` as optional callbacks "for older smoke/compat tests"
  even though production `Foglet.TUI.App` dispatch only calls `update/3` and
  `render/2`. Every screen module that still implements these (NewThread,
  PostComposer, etc.) carries duplicate code paths.
- Files: `lib/foglet_bbs/tui/screen.ex` (lines 19-36, 65-88),
  `lib/foglet_bbs/tui/screens/new_thread.ex` (lines 140, 278, 294, 624),
  `lib/foglet_bbs/tui/screens/post_composer.ex` (lines 156, 188, 415, 446-465),
  `lib/foglet_bbs/tui/screens/sysop.ex:680`.
- Impact: New screens may continue implementing the legacy callbacks "to be
  safe", drifting from the canonical contract documented in
  `lib/foglet_bbs/tui/SCREEN_CONTRACT.md`. Each duplicate path is one more
  place a bug can hide.
- Fix approach: Land a follow-up cleanup phase that (a) deletes the optional
  callbacks from `Foglet.TUI.Screen`, (b) deletes the legacy `render/1` /
  `handle_key/2` clauses from each production screen, and (c) migrates the
  remaining smoke/compat tests onto `update/3` + `render/2` seams.

### TUI: Process-dictionary modal-submit handoff (`take_screen_modal_submit`)

- Issue: The `Modal.Form` submit handoff stashes payloads in the process
  dictionary keyed by `{Foglet.TUI.App, :pending_screen_modal_submit}` and
  reads them on the next event tick. Phase 40 explicitly retained this as a
  "bounded App-owned modal runtime seam" instead of redesigning the modal
  protocol.
- Files: `lib/foglet_bbs/tui/app.ex:795-799,885,891`,
  `lib/foglet_bbs/tui/screens/main_menu.ex:562`,
  `lib/foglet_bbs/tui/screens/sysop/boards_view.ex:443,455`,
  `lib/foglet_bbs/tui/widgets/modal/form/submit_stash.ex:35,58`,
  `lib/foglet_bbs/tui/screens/sysop/limits_form.ex:190`,
  `lib/foglet_bbs/tui/screens/account/profile_form.ex:12`.
- Impact: Process-dictionary writes are invisible to reducer tests, hide
  cross-event coupling, and are fragile under any future move to spawn modal
  reducers off the App process. Errors here surface as silent
  "submit did nothing" UX bugs.
- Fix approach: Make the modal submit a first-class `%Effect{}` (e.g.
  `Effect.modal_submit(screen_key, kind, payload)`) emitted by the form
  reducer, interpreted by App, and routed through the target screen's
  `update/3`. Tracked under Phase 39 carry-forward `WR-04` (Excluded for v2.0).

### TUI: `Foglet.TUI.App` is still 1006 lines and concentrates routing/effects

- Issue: After v2.0 simplification `app.ex` is still the single biggest file in
  `lib/` (1006 lines), holding: route encoding, screen-state plumbing, modal
  dismissal, dynamic PubSub refresh, generic effect interpretation, screen
  initial-route hydration, and a handful of "transitional compat clauses"
  (e.g. `{:set_user, user}` → `{:promote_session, user}` aliasing).
- Files: `lib/foglet_bbs/tui/app.ex` (entire file).
- Impact: Any change to the runtime shell still has wide blast radius. Adding
  a new screen still requires touching App in several places (route table,
  initial-route hook, effect interpretation if novel).
- Fix approach: Extract dedicated modules — e.g. `App.Routing`, `App.Modal`,
  `App.Subscriptions`, `App.Effects` — each with a narrow API the App calls
  into. Keep the App struct and runtime callbacks in `app.ex`.

### Domain: Screen modules are large and concentrate complexity

- Issue: Several screen modules exceed 800-1000 lines of mixed reducer + render
  helpers:
  - `lib/foglet_bbs/tui/screens/post_reader.ex` — 1025 lines
  - `lib/foglet_bbs/tui/screens/sysop.ex` — 914 lines
  - `lib/foglet_bbs/tui/screens/login.ex` — 908 lines
  - `lib/foglet_bbs/tui/screens/main_menu.ex` — 829 lines
  - `lib/foglet_bbs/tui/screens/new_thread.ex` — 772 lines
  - `lib/foglet_bbs/tui/screens/account.ex` — 687 lines
- Files: see paths above.
- Impact: Reducer logic, render helpers, and cache-warming sit side by side;
  the contract between "render path is pure" and "non-render helpers may
  mutate" is enforced only by convention (`README` / module docs).
- Fix approach: Continue the Phase 38/39 pattern — split each screen into
  `screens/<name>/state.ex` + `screens/<name>/render.ex` + the reducer module
  itself; PostReader and several others already use a sibling state module
  but still keep render helpers inline.

### Boards.Supervisor.boot_board_servers/0 stub still present

- Issue: `Foglet.Boards.Supervisor.boot_board_servers/0` is a no-op stub with a
  doc comment that says "Plan 03 implements the real query." The real
  implementation lives at `Foglet.Boards.boot_board_servers/0` and is what
  `FogletBbs.Application.start/2` actually calls.
- Files: `lib/foglet_bbs/boards/supervisor.ex:41-46` vs.
  `lib/foglet_bbs/boards.ex:39-46`.
- Impact: Confusing for new contributors — the stub looks callable but isn't
  invoked. Easy to mistake for the source of truth and "fix" it in the wrong
  module.
- Fix approach: Delete the stub from the supervisor module; the application
  already calls the context function directly.

### Pre-existing Dialyzer warnings ignored, not fixed

- Issue: `.dialyzer_ignore.exs` carries 25+ entries that suppress warnings
  rather than fix them. Most are `:contract_supertype` style noise on screen
  modules (specs that are broader than success-typing), but several are real
  hints (`call_without_opaque` on `boards/server.ex`, intentional `:no_match`
  fallbacks on `account/prefs_form.ex` and `account/profile_form.ex`).
- Files: `.dialyzer_ignore.exs`.
- Impact: New regressions of the same shape would slip through. Phase 39 found
  three real warnings hiding under a compromised baseline (two have since been
  fixed in Phase 40; the third was naturally removed by Plan 39-07 deletion).
- Fix approach: Iteratively narrow specs to match success-typing, then drop
  the ignore entry. The Phase 40 `Carry-Forward Disposition Register`
  established the pattern for `board_list.ex:161` and `sysop.ex:823`.

## Known Bugs

No outstanding bugs are currently tracked. Phase 39 carry-forward register
(`.planning/phases/40-verification-documentation/40-SUMMARY.md`) marks every
known issue as `Fixed` or `Excluded` (intentional out-of-scope). Re-validate
this section as new phases land.

## Security Considerations

### SSH key correlation via ETS pubkey stash

- Risk: `Foglet.SSH.PubkeyStash` keys offered public keys by
  `{peer_ip, peer_port}` so the channel handler can recover them after
  `is_auth_key/3` returned. The daemon runs with `no_auth_needed: true`, so
  unmatched/unknown peers still establish a guest session.
- Files: `lib/foglet_bbs/ssh/key_cb.ex` (entire file),
  `lib/foglet_bbs/ssh/pubkey_stash.ex` (entire file),
  `lib/foglet_bbs/ssh/cli_handler.ex:79-145,338-355`.
- Current mitigation: `pop/1` deletes the entry on read; the moduledoc notes
  `:miss` is treated as "guest". The stash is bounded by the 500-connection
  ceiling. Pubkey-derived authentication is gated by SHA-256 fingerprint match
  against `Foglet.Accounts.SSHKey` rows (`accounts/auth.ex:46-78`,
  `accounts/ssh_key.ex:53-66`).
- Recommendations:
  1. Add a TTL/sweep for orphan stash entries (the moduledoc explicitly notes
     "no periodic sweep"). Even at 500 entries this is fine in practice, but a
     denial-of-service attacker who scans many ports could nudge the table
     upward; an LRU/TTL bound is cheap insurance.
  2. Audit-log every guest→user promotion (currently logs as info on the
     Session side via `Logger.info` in `Foglet.Sessions.Session.handle_cast/2`
     for `{:promote_to_user, user}`); consider a structured audit row tied to
     peer IP for forensics.

### `no_auth_needed: true` SSH daemon posture

- Risk: The SSH daemon accepts every connection by design — identity
  resolution happens inside the TUI. A malicious peer can spin up a TUI
  session as a guest at will, restricted only by per-IP rate limit (10 conns
  per 60s) and the global 500-connection ceiling.
- Files: `lib/foglet_bbs/ssh/key_cb.ex:32-40`,
  `lib/foglet_bbs/ssh/cli_handler.ex:58,82-145`,
  `lib/foglet_bbs/ssh/rate_limiter.ex:20-21`.
- Current mitigation: Hammer-backed per-IP rate limit + ETS atomic counter for
  global cap. Both fail-open on table errors (intentional availability
  trade-off, documented in module docs).
- Recommendations: Consider exposing the rate-limit thresholds as
  `Foglet.Config` keys so an operator can tighten under attack without a
  redeploy. Currently both `@max_connections` (500) and the rate-limit window
  (10/60s) are module attributes.

### Soft-deleted post bodies remain in database

- Risk: `Foglet.Posts.delete_post/2` only sets `deleted_at` and
  `deletion_reason`; the post `body` stays in the row. A naive query that
  forgets `where: is_nil(p.deleted_at)` would render deleted content.
- Files: `lib/foglet_bbs/posts.ex:148-161`,
  `lib/foglet_bbs/posts/post.ex:18,64`,
  `lib/foglet_bbs/query_helpers.ex:11-14`.
- Current mitigation: `Foglet.QueryHelpers.not_deleted/1` provides a shared
  filter; render code is expected to show a tombstone for `deleted_at != nil`.
  Message numbers are intentionally preserved (no gap filling), as documented
  in the Posts moduledoc.
- Recommendations: Audit every list/get path that returns `Post.t()` to ensure
  `not_deleted/1` is applied in the query (consumer responsibility, not
  schema-level). Consider a "purge" Mix task that hard-deletes old soft-deleted
  rows after a retention window for GDPR-style requests; currently
  `Foglet.Accounts.delete_user/1` rewrites authorship to a tombstone user but
  does not redact bodies.

### Plain `Repo.transaction` skips Repo.transact ergonomics in board server

- Risk: `Foglet.Boards.Server` uses `|> Repo.transaction()` directly with
  `Ecto.Multi`, while every other context (`Foglet.Accounts`,
  `Foglet.Posts`, `Foglet.Threads`, `Foglet.Oneliners`, `Foglet.Boards`)
  uses `Repo.transact/1`.
- Files: `lib/foglet_bbs/boards/server.ex:154,196`.
- Impact: Inconsistency, not a bug. `Multi` already gives atomicity; the
  concern is convention drift.
- Fix approach: Document why Server uses `Multi.run` (it returns the
  `{:error, _op, reason, _changes}` shape that the GenServer reply path
  expects) and leave it, OR convert to `Repo.transact/1` returning a single
  `{:error, _}` shape if the Multi step labels are not externally observed.

## Performance Bottlenecks

### Per-board single-writer GenServer for message-number allocation

- Problem: All post and thread inserts on a given board route through a
  single `GenServer.call/3` to `Foglet.Boards.Server`. Each call holds the
  process while running an `Ecto.Multi` (board counter bump + post insert +
  thread counter bump + user post-count bump). Under burst write load this
  serializes inside a single OS process.
- Files: `lib/foglet_bbs/boards/server.ex` (entire file),
  `lib/foglet_bbs/posts.ex:45-63`,
  `lib/foglet_bbs/threads.ex` (`create_thread`).
- Cause: This is a deliberate invariant (per-board contiguous, gap-free
  message numbers — see `AGENTS.md` "Core Invariants"). Database-level
  serialization (advisory locks or `SELECT ... FOR UPDATE`) was not chosen.
- Improvement path: Acceptable for current scale (small BBS). If a board
  ever sees write QPS that taps the GenServer, options are:
  1. Move allocation to a Postgres sequence per board with a careful
     compensating-write protocol on Multi failure.
  2. Pipeline via `GenServer.cast` + ack message, so the caller doesn't block
     the calling process while waiting for `Multi` to commit.
  3. Pre-allocate ranges and hand out from in-memory pool, draining lazily.
- Default call timeout: 5s. Long-running posts (e.g. heavy markdown) are not
  currently a concern but worth re-checking if body validation grows.

### `Foglet.Posts.list_posts/1` loads every post in a thread, no pagination

- Problem: `list_posts/1` returns every non-paginated post in a thread,
  ordered by `inserted_at` ascending, with `:user` preloaded. PostReader then
  reads the full list into local state.
- Files: `lib/foglet_bbs/posts.ex:84-92`,
  `lib/foglet_bbs/tui/screens/post_reader.ex:94-119`.
- Cause: PostReader's UX is "read whole thread, paginate by post". A 1000-post
  thread loads 1000 rows and 1000 unique-user preload rows.
- Improvement path: Add a paginated variant (`list_posts_after/3` cursor by
  message_number) and let PostReader request batches as the user navigates.

### PostReader render cache keyed by `{post_id, terminal_width}`

- Problem: `PostReader.State.render_cache` memoizes parsed Markdown tuples
  per `{post_id, width}`. On `terminal_size` change (resize) every cached
  entry under the old width becomes dead memory until the screen exits.
- Files: `lib/foglet_bbs/tui/screens/post_reader.ex:38,48,336,619-731`,
  `lib/foglet_bbs/tui/screens/post_reader/state.ex:27,42,62`,
  `lib/foglet_bbs/tui/widgets/post/post_card.ex:36`.
- Cause: Cache is dropped on `Q` (screen exit) and rebuilt on re-entry. No
  width-LRU eviction is implemented.
- Improvement path: Drop entries for stale widths on `:resize` events, or key
  the cache solely on `post_id` and re-flow on width change inside the render
  function. Likely not needed at current scale; revisit if memory growth
  during long PostReader sessions becomes observable.

## Fragile Areas

### Session replacement race window (`replace_then_promote`)

- Files: `lib/foglet_bbs/sessions/supervisor.ex:124-181`,
  `lib/foglet_bbs/sessions/session.ex:165-188`.
- Why fragile: Two-step protocol — send `:replaced_by_new_session`, monitor,
  wait up to 2s for `:DOWN`, fall through to `DynamicSupervisor.terminate_child`
  / `Process.exit(_, :kill)`. The fall-through to `Process.exit/2` is a real
  code path (not just defensive), kept for cases where `old_pid` is not a
  supervised child (test setup or partial crash). After the timeout, a fresh
  promote is cast even if termination was forced; the new session may briefly
  observe a Registry race.
- Safe modification: Any change to one-session-per-user must preserve the
  protocol that `promote_to_user/2` is only cast once the Registry slot is
  free. The Session module `handle_cast({:promote_to_user, user}, ...)`
  explicitly logs an `error` if registration finds the slot held — this
  invariant guard is load-bearing.
- Test coverage: Direct tests of replacement timing are present but the
  forced-termination (2s timeout) branch is rarely exercised under realistic
  load.

### `Foglet.SSH.CLIHandler` global connection counter

- Files: `lib/foglet_bbs/ssh/cli_handler.ex:467-501`.
- Why fragile: Connection count lives in a `:public` ETS named-table counter.
  The handler increments atomically inside `check_connection_limit/0` (then
  potentially decrements on rate-limit reject). Every termination path —
  `{:closed}`, `{:EXIT, lifecycle, _}`, `terminate/2` — must decrement
  exactly once, gated on `over_limit`. Missed decrements drift the count
  upward over time and silently throttle the server.
- Safe modification: Audit any new termination path for the same
  `unless state.over_limit do decrement_connection_count() end` pattern.
- Test coverage: Counter invariant under crash-during-init is not exercised
  in tests (the increment happens before the handler returns success). A
  defensive improvement would be to clamp the counter at 0 on every
  decrement (already done via the `{2, -1, 0, 0}` atomic op).

### Alt-screen escape sequences scattered across CLIHandler termination paths

- Files: `lib/foglet_bbs/ssh/cli_handler.ex:148-269,281-306`.
- Why fragile: Three different SSH lifecycle messages (`{:EXIT, lifecycle, _}`,
  `{:eof, _}`, `{:closed, _}`) each call `send_alt_screen_leave/1` to restore
  the client's primary buffer. The implementation is "belt and suspenders" by
  design (terminal restoration is best-effort over a closing channel), but
  any new termination path must remember to emit the escape.
- Safe modification: Extract a single `terminate_channel(state, reason)`
  helper that owns alt-screen leave + lifecycle stop + session stop +
  counter decrement. Currently each branch open-codes the sequence.

### Phoenix surface area is minimal but easy to drift

- Files: `lib/foglet_bbs_web/router.ex` (entire file),
  `lib/foglet_bbs_web/endpoint.ex`.
- Why fragile: The router serves only `/`, `/up` (health), and dev-only
  LiveDashboard. There is no `/api` content. CSP is very tight (`default-src
  'self'`, no inline scripts). Adding any user-facing browser feature would
  require explicit architecture intent per `AGENTS.md` ("Phoenix is
  infrastructure ... do not add end-user browser workflows unless the
  architecture docs are updated").
- Safe modification: Treat `lib/foglet_bbs_web/` as locked unless the
  milestone explicitly opens it. New SSH-only features stay in `Foglet.*`.

### Render-path purity invariant on PostReader is enforced by convention only

- Files: `lib/foglet_bbs/tui/screens/post_reader.ex:33-39,619-731`.
- Why fragile: The moduledoc states "No `defp render_*` helper may perform
  state writes" and warming functions are confined to `load_posts/2`,
  `advance_post/2`, `scroll_post/2`, `warm_cache/4`, `warm_viewport/4`.
  Nothing tests this invariant; a future helper named `render_thing/2` that
  silently calls `put_in/2` would compile, run, and pass tests by surfacing
  via the next reducer call.
- Safe modification: Consider a Credo custom check or a static-analysis
  helper that scans `defp render_*` for forbidden calls (`put_in`, `Map.put`,
  `%{state | ...}`).

## Scaling Limits

### SSH connections: 500 hard cap, ETS counter

- Current capacity: 500 concurrent SSH channels (module attribute
  `@max_connections` in `lib/foglet_bbs/ssh/cli_handler.ex:58`).
- Limit: Beyond 500, connections are rejected with a banner and channel close.
- Scaling path: Bump `@max_connections`. Real ceilings are Erlang
  `:ssh` daemon throughput, the BEAM scheduler under N TUI processes, and
  Postgres connection-pool size — not the counter itself. Surface as
  `Foglet.Config.max_ssh_connections` if dynamic tuning becomes useful.

### Per-IP rate limit: 10 conns per 60s

- Current capacity: 10 connection attempts per IP per 60s window
  (`@rate_limit_max`, `@rate_limit_window_ms` in
  `lib/foglet_bbs/ssh/rate_limiter.ex:20-21`).
- Limit: Hammer ETS backend, fail-open on table errors.
- Scaling path: Move thresholds into `Foglet.Config` typed accessors so
  operators can tune under attack.

### Per-board write throughput: single GenServer

- Current capacity: One process serializes all post inserts per board.
- Limit: ~Postgres commit latency × Multi step count per insert.
- Scaling path: See "Performance Bottlenecks" above.

## Dependencies at Risk

### Raxol vendor copy

- Risk: Raxol lives under `vendor/raxol/` (referenced via path or git pin in
  `mix.exs`) and is the rendering engine for the entire SSH product surface.
  CLIHandler reaches into private internals like `Raxol.Core.Runtime.Lifecycle`
  state via `GenServer.call(lifecycle_pid, :get_full_state)` to fish out the
  dispatcher pid (`lib/foglet_bbs/ssh/cli_handler.ex:433-438`), and the
  app dispatches both `:resize` and `:window` events because the upstream
  dispatcher does not propagate `:resize` to `App.update/2`
  (`cli_handler.ex:218-235`).
- Impact: Any Raxol upstream change to the lifecycle or dispatcher API would
  silently break SSH input/resize forwarding. Compile-time warnings already
  show pre-existing `raxol` dependency churn (`Raxol.Adaptive.NxModel`,
  `Mogrify`, `Benchee.Formatter` in
  `.planning/phases/40-verification-documentation/40-SUMMARY.md` Render Smoke
  notes).
- Migration plan: Replace the `:get_full_state` peek with a stable supported
  API once Raxol publishes one. Until then, treat the dispatcher-pid lookup
  as a known coupling and add a regression test that fails loudly if the
  shape of `%{dispatcher_pid: pid}` changes.

## Missing Critical Features

No critical product gaps for v2.0 milestone close. The active requirement is
purely placeholder cleanup:

- `FUTURE-01..FUTURE-03` — Traceability placeholders left in `PROJECT.md`;
  resolve or remove if/when they become real requirements.

`SEED-001` (email notifications) and `SEED-002` (webhook notifications) are
intentionally dormant per the v2.0 milestone scope; they are NOT bugs.

## Test Coverage Gaps

### App-shell modal-submit handoff is tested through reducer paths only

- What's not tested: Direct property tests around the
  `Process.put({Foglet.TUI.App, :pending_screen_modal_submit}, _)` →
  `take_screen_modal_submit/0` round-trip. Coverage is implicit through
  screen-level submit tests.
- Files: `lib/foglet_bbs/tui/app.ex:795-799,891-897`,
  `test/foglet_bbs/tui/app_test.exs`.
- Risk: A regression that drops the stash key (e.g. via a future helper that
  uses a different module key) would surface as a silent submit no-op rather
  than a crash. Phase 40 explicitly retained this seam (BL-01 fix verified
  the submit-failure recovery path, not the success path).
- Priority: Medium. Worth covering when the modal-submit refactor (see Tech
  Debt above) lands.

### `replace_then_promote/3` 2s-timeout fallback path

- What's not tested: The `Process.exit(old_pid, :kill)` branch inside the
  timeout, which fires only when `DynamicSupervisor.terminate_child/2`
  returns `{:error, _reason}` because `old_pid` is not a supervised child.
- Files: `lib/foglet_bbs/sessions/supervisor.ex:124-153`.
- Risk: Path is exercised in the wild when an old session crashed mid-replace
  but the Registry slot lingers. Loud-logged but otherwise silent on the
  outside.
- Priority: Low. Defensive code; exercising it requires careful test setup
  with hand-managed pids.

### Soft-delete-aware list paths

- What's not tested: A blanket assertion that every `Foglet.Posts.*` query
  applies `Foglet.QueryHelpers.not_deleted/1` (or filters `deleted_at`).
  Currently each query is responsible.
- Files: `lib/foglet_bbs/posts.ex:84-92`,
  `lib/foglet_bbs/threads.ex` (`list_*`),
  `lib/foglet_bbs/query_helpers.ex:11-14`.
- Risk: Future query that forgets the filter renders deleted post bodies in a
  list. Tombstone-rendering tests catch the most-trafficked paths but not
  every consumer.
- Priority: Medium.

### Phoenix endpoint surface

- What's not tested: There are no controller tests beyond what
  `FogletBbsWeb.HealthController` may carry. The endpoint is intentionally
  minimal.
- Files: `lib/foglet_bbs_web/controllers/health_controller.ex`,
  `lib/foglet_bbs_web/controllers/page_controller.ex`,
  `test/foglet_bbs_web/`.
- Risk: Any drift toward end-user browser features should re-add coverage;
  current CSP is restrictive, but a regression that loosens
  `frame-ancestors 'none'` or `script-src 'self'` would not be caught by an
  automated test today.
- Priority: Low while SSH-first stance holds (see `AGENTS.md`).

### Render-path purity for screens beyond PostReader

- What's not tested: The "render helpers must not mutate state" invariant is
  documented per-module (PostReader, others by analogy) but not enforced by
  a static check or test.
- Files: `lib/foglet_bbs/tui/screens/*.ex`,
  `.credo.exs`.
- Risk: A new contributor adds a `defp render_x` that calls `put_in/2` and
  it ships. The next refactor that flips to a memoized render path would
  produce subtle render artifacts.
- Priority: Low; consider a Credo custom check.

---

*Concerns audit: 2026-04-29*
