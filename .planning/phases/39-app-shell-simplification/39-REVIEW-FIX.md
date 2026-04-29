---
phase: 39-app-shell-simplification
fixed_at: 2026-04-29T08:40:00Z
review_path: .planning/phases/39-app-shell-simplification/39-REVIEW.md
iteration: 1
findings_in_scope: 14
fixed: 9
skipped: 5
status: partial
---

# Phase 39: Code Review Fix Report

**Fixed at:** 2026-04-29
**Source review:** `.planning/phases/39-app-shell-simplification/39-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 14 (1 critical + 8 warnings + 5 info)
- Fixed: 9
- Skipped: 5

All fixes were verified by recompiling (`rtk mix compile`) and running the
relevant test suites. The 14-finding queue was triaged into per-finding
atomic commits. Five findings were skipped — three for scope (sweeping
multi-file refactors that the review itself flagged as follow-up work),
two because they are static-lint guards whose only behavioural equivalent
would be a custom Credo check.

The two pre-existing test failures in `test/foglet_bbs/tui/screens/account_test.exs`
(BL-01 form modal lock release tests) were verified to fail on baseline
before any fix was applied — they are not regressions from this fix pass.

## Fixed Issues

### CR-01: Initial mount via `App.init/1` skips `:on_route_enter`

**Files modified:** `lib/foglet_bbs/tui/initial_route_enter_forwarder.ex` (new),
`lib/foglet_bbs/tui/app.ex`, `test/foglet_bbs/tui/app_test.exs`

**Commit:** `71ce228`

**Applied fix:** Created a new one-shot Raxol custom subscription module
(`Foglet.TUI.InitialRouteEnterForwarder`) that fires once after the
Dispatcher starts, sending `{:subscription, :initial_route_enter}` to the
Dispatcher pid. Added a `do_update(:initial_route_enter, state)` clause
that routes the message through `route_screen_update/3` as
`:on_route_enter` — identical to what `apply_effect(navigate, ...)` does.
Wired the forwarder into `subscribe/1`'s return value so it is always
present (since `setup_subscriptions/1` runs once per Dispatcher init, the
forwarder fires exactly once per session).

The original review fix sketch suggested calling
`maybe_dispatch_route_entry/3` directly from `init/1`, but that loses the
emitted commands (Raxol's `init/1` contract is `{:ok, model}`, no
commands accepted). The subscription approach preserves the load-task
fire-and-forget semantics that screens like MainMenu rely on.

`app_test.exs:113`'s `refute_received {:list_recent_visible, 5}` was
codifying the broken behaviour. The test now demonstrates the fixed
behaviour by also calling `App.update(:initial_route_enter, state)` and
asserting `oneliner_status: :loading`, that the load command is emitted,
and that the task closure invokes `FakeOneliners.list_recent_visible/1`.
Three subscription tests were updated to account for the always-present
forwarder.

**Status:** fixed: requires human verification

The Raxol Dispatcher integration is mediated by Raxol's
`Subscription.start/2` lifecycle, which the unit tests do not exercise
directly. Confirming the forwarder actually fires `:initial_route_enter`
end-to-end requires a manual SSH session test (or an integration test
that spins up the full Raxol Lifecycle/Dispatcher pair). The
`do_update(:initial_route_enter, ...)` reducer clause IS unit-tested.

### WR-01: `PostComposer.State.from_context/1` and `NewThread.State.from_context/1` ignore terminal width

**Files modified:** `lib/foglet_bbs/tui/screens/post_composer/state.ex`,
`lib/foglet_bbs/tui/screens/new_thread/state.ex`

**Commit:** `0cb0fb9`

**Applied fix:** Both `from_context/1` functions now extract
`{w, _h} = context.terminal_size || {80, 24}` and pass `width:` to
`new/1`. PostComposer applies `max(w - 4, 20)` directly to leave room
for chrome; NewThread.State.new/1 already does that math internally so
the raw width is forwarded unchanged.

### WR-02: `screen_module_for/1` raises FunctionClauseError on unknown screen

**Files modified:** `lib/foglet_bbs/tui/app.ex`

**Commit:** `bf40026`

**Applied fix:** Added a fallback clause `defp screen_module_for(other)`
that logs the error via `Logger.error/1` and returns `Screens.MainMenu`
as a degraded-but-functional fallback. The runtime no longer crashes
when an unknown screen atom reaches the legacy `:erlang.apply/3`
fallback path in `render_screen/1`.

### WR-03: `Moderation.update/3` and `Sysop.update/3` Q-key clauses drop context

**Files modified:** `lib/foglet_bbs/tui/screens/moderation.ex`,
`lib/foglet_bbs/tui/screens/sysop.ex`

**Commit:** `9d710f2`

**Applied fix:** Both Q-key (quit-to-main-menu) clauses now use
`normalize_state(local_state, context)` (the 2-arg form) instead of the
1-arg form, ensuring tab-label refresh via `ShellVisibility.invites_visible?/2`
runs and any %State{} hydrated by `init/1` is preserved. The 1-arg
`normalize_state/1` clauses are now dead and were removed (they would
have produced a "function unused" warning that mix precommit treats as
an error).

### WR-04: `PostReader.legacy_state/1` shim still present

**Files modified:** `lib/foglet_bbs/tui/screens/post_reader.ex`

**Commit:** `3207071`

**Applied fix:** Replaced every `legacy_state(state)` call (9 sites)
with `get_screen_state(state)` and deleted the redundant
`legacy_state/1` definition. The two helpers were structurally
identical — `get_screen_state/1` already does what `legacy_state/1`
did, so consolidation is a no-op behaviourally. Also updated a stale
moduledoc reference from `legacy_state/1` to `get_screen_state/1`.

### WR-07: Five tests assert presence of substrings in source files

**Files modified:** `test/foglet_bbs/tui/screens/moderation_test.exs`,
`test/foglet_bbs/tui/screens/post_composer_test.exs`,
`test/foglet_bbs/tui/screens/post_reader_test.exs`

**Commit:** `484d4bd`

**Applied fix:** Replaced four source-grep tests with behavioural
assertions against the rendered tree:

- `moderation_test.exs:160` — removed redundant source-grep (the line
  above already asserts `Presentation.mode_for!(:moderation) == :operator`
  at runtime, which is the actual contract).
- `post_composer_test.exs:144` — now renders a reply composer and
  refutes the legacy "Reply to:" prefix.
- `post_composer_test.exs:262` — now renders the composer, asserts the
  EditorFrame contract (Edit/Preview tabs, body counter regex), and
  refutes the PostCard reader-style "Post N of M" header.
- `post_reader_test.exs:363` — now loads posts, renders, and refutes
  the legacy "Thread:" prefix.
- `post_reader_test.exs:462` — now renders a thread with one post and
  asserts the "Post N of M" reader-card header is present.

The remaining source-grep tests in `sysop_test.exs` (5 sites listed in
WR-07) are documented as skipped below — they are architectural lint
guards whose behavioural equivalents would require either a custom
Credo check or rendering across an exhaustive fixture set.

### IN-01: `:on_confirm` / `:on_cancel` callback contract undocumented

**Files modified:** `lib/foglet_bbs/tui/modal.ex`

**Commit:** `4906701`

**Applied fix:** Added a callback-contract section to the Modal
moduledoc explaining the three accepted callback shapes
(nil / :dismiss_modal / function) and the two routing modes for
function returns (`{%App{}, [commands]}` vs message). Added a typedoc
on the @type callback that points to the moduledoc. Stricter runtime
validation (raising on unknown shapes) was considered but deferred —
several existing callers return tuples like `{:navigate, :main_menu}`
that are intentionally routed through the message path, so a strict
guard would require a wider audit.

### IN-02: `RenderFixtures.populate/3` writes raw maps into `screen_state`

**Files modified:** `lib/foglet_bbs/tui/render_fixtures.ex`

**Commit:** `1e62414`

**Applied fix:** Routed every populate clause through
`App.put_screen_state/3`. Where clauses also rewrite `route_params`,
that map-update is done in a separate step and piped into
`put_screen_state/3` so the public boundary helper is the single
write to `screen_state`.

### IN-03: `:session_replaced` modal+quit doesn't wait for user dismiss

**Files modified:** `lib/foglet_bbs/tui/app.ex`,
`test/foglet_bbs/tui/app_test.exs`

**Commit:** `109d2fe`

**Applied fix:** The `:session_replaced` handler now mirrors
`:terminate_after_modal`: it sets a warning modal with on_confirm /
on_cancel callbacks that issue `Command.quit()` and returns an empty
command list. The user sees the modal until they dismiss it (Enter or
Esc), at which point the session quits cleanly. The corresponding
`app_test.exs` case was updated to assert the new contract: no
immediate quit command, both dismiss callbacks issue Command.quit().

### IN-05: `domain_from_session_context/1` discards non-map domain silently

**Files modified:** `lib/foglet_bbs/tui/app.ex`

**Commit:** `41ad6f5`

**Applied fix:** Split the case clause: nil still coerces silently to
`%{}` (the not-set case), but non-nil/non-map values now emit a
`Logger.warning/1` with the offending term inspected. Production stays
unchanged when `:domain` is properly shaped or simply absent;
misconfigured test fixtures now leave a breadcrumb in the log.

## Skipped Issues

### WR-05: Legacy `handle_key/2` dispatch path still resolves screen modules

**File:** `lib/foglet_bbs/tui/app.ex:508-544`

**Reason:** scope: explicitly deferred to follow-up cleanup phase

**Original issue:** The `do_update({:key, ...})` clause has a `true ->`
fallback branch that dispatches to legacy `handle_key/2` callbacks via
`:erlang.apply/3`. The branch is dead in production today (every
post-39 screen implements `update/3`) but is kept alive for legacy
test harnesses. The review explicitly says "Keep this narrow review's
scope, but the cleanup is begging to be done" — deletion would also
cascade into removing `process_screen_commands/2`, `wrap_commands/1`,
the `handle_key/2` callbacks across screen modules, and a chunk of
legacy `render/1` paths. That is a multi-file follow-up phase, not a
single-finding fix.

### WR-06: `PostComposer.legacy_thread_for_submit/2` reads PostReader's screen-state slot

**File:** `lib/foglet_bbs/tui/screens/post_composer.ex:446-475`

**Reason:** scope: bound to WR-05 deletion

**Original issue:** The cross-screen state read in
`legacy_thread_for_submit/2` violates the screen-ownership boundary.
It exists ONLY in the legacy submit path (the new `update/3` contract
correctly uses the composer's own State). The review explicitly says
"Per WR-05, deleting the legacy path also deletes this hazard. Until
then, document loudly that this is a hack and not a pattern to copy."
Since WR-05 is deferred, this fix is too. Documenting it as a hack
without fixing the root cause is a half-measure of negative value.

### WR-08: 332 `=~` text-presence assertions across the test suite

**Files:** All 16 test files in scope

**Reason:** scope: too broad to safely auto-fix in one pass

**Original issue:** 332 `=~` substring assertions across the test
suite, of which a meaningful fraction test layout details rather than
component contracts. The review itself notes "Triage scope: WR-07's
source-file reads first; the layout-pinning ones second (the
highest-density culprits are `layout_smoke_test.exs` with 70 matches
and `new_thread_test.exs` with 41)." A safe audit requires a per-test
judgment call ("does this fail if a layout-only refactor changes the
rendered text but preserves the contract?") that cannot be automated
reliably. WR-07 (5 specific source-file reads) was tractable in this
fix pass; WR-08's broader cleanup is left as a follow-up.

### IN-04: `MainMenu.app_state_from_local/2` reconstructs an App-shape map

**File:** `lib/foglet_bbs/tui/screens/main_menu.ex:457-470`

**Reason:** scope: explicitly deferred to follow-up phase

**Original issue:** Five separate construction sites
(`MainMenu.app_state_from_local/2`, `PostReader.frame_state/2`,
`PostComposer.frame_state/2`, `NewThread.frame_state/2`,
`ThreadList.frame_state/2`) build a 9-key App-shape map for legacy
ScreenFrame consumption. The review's fix says "Phase 39 is 'App-shell
simplification' — a follow-up phase should push App-shape map
construction OUT of screens, replacing it with explicit calls passing
`Theme.from_state(theme_input)` where `theme_input` is the
`session_context` directly."

This is a multi-file refactor that touches the ScreenFrame contract
and every consumer. It is explicitly flagged as out-of-phase work.

### Remaining WR-07 source-string-grep tests in sysop_test.exs

**Files:** `test/foglet_bbs/tui/screens/sysop_test.exs` (5 sites:
lines 282-298, 1290-1305, 1869-1878, 2108-2116, 2358-2371) and
`test/foglet_bbs/tui/screens/post_reader_test.exs` (1 site: lines
578-627)

**Reason:** static lint guards; behavioural equivalent requires custom Credo check or exhaustive fixture rendering

**Original issue:** These tests use `File.read!/1` + substring/regex
matching to enforce architectural / lint-style guarantees:

- `sysop_test.exs:282` — no "Press any key" literal in sysop.ex
- `sysop_test.exs:287` — no `Raxol.Core.Runtime.Command.task` literal
  under Sysop.* (D-04 boundary)
- `sysop_test.exs:1290` — no double-quoted string literal contains
  "invalid_transition" in users_view.ex (D-16 render guard)
- `sysop_test.exs:1869` — sysop.ex delegates invite lifecycle through
  shared modules only
- `sysop_test.exs:2108` — exactly one `def revoke_selected` definition
  in invites_actions.ex (D-25 boundary lock)
- `sysop_test.exs:2358` — no screen module references
  `Workspace.Inspector` (D-20)
- `post_reader_test.exs:578` — no `defp render_*` block contains
  forbidden state-write patterns (D-07/D-08 render purity guard)

These are all architectural / contract guards rather than tests of
observable behaviour. The behavioural equivalents would require
either (a) a custom Credo check (the right home for cross-module
architectural lints) or (b) rendering across an exhaustive fixture
set and asserting absence of the forbidden pattern in every variant
— which still wouldn't catch dead-code paths the test runner doesn't
exercise.

These tests violate the letter of AGENTS.md's "no text-presence tests"
rule but they enforce real architectural constraints. The recommended
fix is migration to custom Credo checks, which is a separate piece of
infrastructure work outside the scope of this review-fix pass.

---

_Fixed: 2026-04-29_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_

## Operational note

This fixer ran in the main worktree because the orchestrator did not
spawn it inside an isolated worktree (the `git worktree add` step
failed because `main` was already checked out at the project root).
The pre-existing uncommitted modifications to `AGENTS.md` (adding the
"DO NOT WRITE BULLSHIT TESTS" line) and the untracked `LOGIN.md` /
`.claude/worktrees/` paths were left untouched — every commit
explicitly listed only the files it modified, so those uncommitted
changes did not get folded into any fix commit.
