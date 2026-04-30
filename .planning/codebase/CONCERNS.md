# Codebase Concerns

**Analysis Date:** 2026-04-29

This document inventories tech debt, fragile areas, security considerations, and
under-tested zones for Foglet BBS as of v2.0 close (Phase 40 complete). The
post-Phase-40 codebase passes `rtk mix precommit` and the full `rtk mix test`
suite (1 property + 2161 tests, 0 failures), so most concerns below are latent
risks, bounded compatibility shims, or ergonomic debt — not active failures.

**v2.1 close pass (2026-04-29):** Phase 46 added an inline `**Disposition:**`
line to every `### ` heading in this file, classifying each concern as `Fixed
in Phase NN` (with a SUMMARY anchor or file pointer), `Intentionally retained`
(with rationale and, where applicable, a `ROADMAP.md` backlog pointer), or
`Covered by ...` (with the test or doc artifact named). The original v2.0
concern text is preserved verbatim; this pass adds annotations only.

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
- **Disposition:** Fixed in Phase 41 — canonical `update/3` + `render/2` screen contract finalized and compat callbacks retired across production screens; see `41-01-SUMMARY.md` and `41-02-SUMMARY.md`.

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
- **Disposition:** Fixed in Phase 41 — first-class modal-submit effect introduced and `SubmitStash` removed; see `41-03-SUMMARY.md` and `41-04-SUMMARY.md`.

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
- **Disposition:** Fixed in Phase 42 — `App.Routing`, `App.Modal`, `App.Effects`, `App.Subscriptions`, and helper extractions landed across plans 42-01 through 42-05; see `42-01-SUMMARY.md` through `42-05-SUMMARY.md`.

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
- **Disposition:** Fixed in Phase 43 — PostReader, MainMenu, Sysop, Login, NewThread, and Account screens decomposed into sibling `state.ex` / `render.ex` modules; see `43-01-SUMMARY.md` through `43-06-SUMMARY.md`.

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
- **Disposition:** Fixed in Phase 46 — `lib/foglet_bbs/boards/supervisor.ex` stub removed (DOM-01); see `46-01-SUMMARY.md`.

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
- **Disposition:** Fixed in Phase 46 — `.dialyzer_ignore.exs` baseline reduced from 54 lines / 28 entries to 46 lines / 22 entries, `:call_without_opaque` eliminated, every kept entry annotated under bucket headers (QUAL-01); see `46-03-SUMMARY.md`.

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
- **Disposition:** Fixed in Phase 45 — `Foglet.SSH.PubkeyStash` gained a TTL + periodic sweep (`lib/foglet_bbs/ssh/pubkey_stash.ex`) and structured promotion-audit metadata (`ssh_peer` carried into the session context) was added; see `45-01-SUMMARY.md` and `45-02-SUMMARY.md`.

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
- **Disposition:** Fixed in Phase 46 — documented as intentional, locked deviation from `Repo.transact/1` (DOM-02); see `lib/foglet_bbs/boards/server.ex` `## Transaction strategy` moduledoc and `46-02-SUMMARY.md`.

## Performance Bottlenecks

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
- **Disposition:** Intentionally retained — partially addressed by Phase 44 PostReader bounded reader-window/render-cache hardening (`44-01-SUMMARY.md`, `44-02-SUMMARY.md`); full cursor-pagination of `list_posts/1` deferred at v2.1 kickoff. See `ROADMAP.md` backlog.

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
- **Disposition:** Fixed in Phase 44 — reducer-side resize cache eviction landed (stale widths drop on `:resize`); see `44-03-SUMMARY.md`. Width-LRU eviction during steady-state intentionally retained as out-of-scope at current scale; see `ROADMAP.md` backlog.

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
- **Disposition:** Covered by `45-03-SUMMARY.md` — unified SSH cleanup helper plus connection-counter lifecycle proof tests exercise the termination paths that the replacement-race protocol relies on for clean Registry-slot release.

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
- **Disposition:** Fixed in Phase 45 — idempotent cleanup via `cleanup_done?` + `counter_counted?` state flags ensures exactly-once decrement across normal close, EOF-to-close, lifecycle EXIT, over-limit reject, rate-limit reject, and crash-during-init paths; see `45-03-SUMMARY.md`.

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
- **Disposition:** Fixed in Phase 45 — single `cleanup/2` helper now owns alt-screen leave, lifecycle stop, session stop, optional channel close, and counter decrement; every termination-sensitive callback delegates to it; see `45-03-SUMMARY.md`.

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
- **Disposition:** Covered by `44-03-SUMMARY.md` (render-purity guard hardening — render module scanned for forbidden state writes during tests) and `43-04-SUMMARY.md` (PostReader decomposition into render/state modules).


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
- **Disposition:** Covered by `41-03-SUMMARY.md` and `41-04-SUMMARY.md` — first-class modal-submit effect replaces the process-dictionary stash; the seam this gap describes no longer exists, and the new effect path is exercised end-to-end through reducer + consumer migration tests.

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
- **Disposition:** Intentionally retained — defensive low-priority branch in `Foglet.Sessions.Supervisor.replace_then_promote/3` requires hand-managed pid setup to exercise; Phase 45 hardened the SSH-side cleanup paths but did not add coverage for this Sessions-side fallback. See `ROADMAP.md` backlog.

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
- **Disposition:** Covered by `44-04-SUMMARY.md` — soft-delete reader/list query policy coverage added across `Foglet.Posts` and `Foglet.Threads` list paths.

---

*Concerns audit: 2026-04-29*
