# Phase 39 — Deferred Items

Out-of-scope discoveries logged during plan execution. These are NOT to be fixed
as part of Phase 39 unless a later plan explicitly takes ownership.

## Pre-existing test failures (discovered during 39-01)

Two tests in `test/foglet_bbs/tui/screens/account_test.exs` fail on `main` HEAD
prior to any Phase 39 work, confirmed by stashing 39-01 changes and re-running
the file in isolation.

| File | Line | Test | Status |
|------|------|------|--------|
| test/foglet_bbs/tui/screens/account_test.exs | 1242 | "doomed oneliner submit leaves form in {:error, _} (not :submitting)" | pre-existing failure |
| test/foglet_bbs/tui/screens/account_test.exs | 1271 | "doomed hide-oneliner submit leaves form in {:error, _} (not :submitting)" | pre-existing failure |

These appear to predate Phase 39 (likely tied to error-routing in MainMenu /
Account form-submit modal after Phase 38). They do not block this plan because:

1. They are not in any file 39-01 modifies.
2. `rtk mix precommit` does not run `mix test` — so the precommit gate is
   unaffected.
3. Stash-baseline confirms they fail without 39-01 changes.

If a later Phase 39 plan touches the same code paths, fix as Rule 1 in that
plan's deviation log. Otherwise leave for Phase 40 cleanup or open as an
independent bug.

## Pre-existing Dialyzer warnings (discovered during 39-01)

`rtk mix precommit` does not exit 0 on `main` HEAD prior to Phase 39 because
Dialyzer emits three `done (warnings were emitted) → Halting VM with exit
status 2` items. Verified by stashing 39-01 changes and running
`rtk mix dialyzer` cleanly.

| Location | Warning | Disposition |
|----------|---------|-------------|
| `lib/foglet_bbs/tui/app.ex:63:38` | `unknown_type: ThreadEntry.t/0` (stale `@type t` reference) | Will be deleted by Plan 39-07 (legacy struct field removal redefines `@type t`). |
| `lib/foglet_bbs/tui/screens/board_list.ex:161:9` | `pattern_match_cov` — unreachable `_other` clause | Out of scope for 39-01; defer. May be incidentally fixed during BoardList subscription work in Plan 39-04 / 39-05. |
| `lib/foglet_bbs/tui/screens/sysop.ex:810:8` | `pattern_match` — `{_ss, _effects}` pattern can't match Sysop reducer return type | Out of scope; not touched by Phase 39. Suggest Phase 40 cleanup. |

Implication for the plan's success criterion "rtk mix precommit exits 0":
this criterion was authored against an assumed-clean baseline; on actual
`main` HEAD, dialyzer fails before any Phase 39 work begins. 39-01 does NOT
introduce additional dialyzer warnings — the failure delta is zero.

## Pre-existing Credo readability issues (fixed inline as Rule 3)

`rtk mix credo --strict` reported 3 alphabetical-alias-ordering issues on
`main` HEAD before 39-01. Fixed inline (trivial, behavior-preserving) so the
Credo step in `mix precommit` is unblocked:

| File | Fix |
|------|-----|
| `test/foglet_bbs/tui/screens/post_reader_test.exs:4-6` | Reordered `{Context, Effect}` ahead of nested `Screens.PostReader` aliases. |
| `test/foglet_bbs/tui/screens/post_composer_test.exs:4-7` | Reordered `Context` ahead of nested `Screens.PostComposer` aliases. |
| `lib/foglet_bbs/tui/screens/new_thread/state.ex:12-14` | Reordered `Context` ahead of `Widgets.Input.TextInput`. |

These are Rule 3 deviations: blocked the precommit gate; fixes are
mechanical and confined to alias-ordering.

