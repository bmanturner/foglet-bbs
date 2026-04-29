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

## Pre-existing Dialyzer warnings (discovered during 39-01; partial resolution in 39-07)

`rtk mix precommit` does not exit 0 on `main` HEAD prior to Phase 39 because
Dialyzer emits warnings (`done (warnings were emitted) → Halting VM with exit
status 2`).

Plan 39-07 RESOLVED `lib/foglet_bbs/tui/app.ex:63:38` by deleting the legacy
`current_thread: ThreadEntry.t() | nil` field from `@type t`. The remaining two
warnings predate Phase 39 and persist:

| Location | Warning | Disposition |
|----------|---------|-------------|
| ~~`lib/foglet_bbs/tui/app.ex:63:38`~~ | ~~`unknown_type: ThreadEntry.t/0`~~ | RESOLVED by Plan 39-07 (legacy `@type t` field deleted). |
| `lib/foglet_bbs/tui/screens/board_list.ex:161:9` | `pattern_match_cov` — unreachable `_other` clause | Out of scope for Phase 39; defer to Phase 40. |
| `lib/foglet_bbs/tui/screens/sysop.ex:823:8` | `pattern_match` — `{_ss, _effects}` pattern can't match Sysop reducer return type | Out of scope; not touched by Phase 39. Suggest Phase 40 cleanup. |

Implication for the plan's success criterion "rtk mix precommit exits 0":
this criterion was authored against an assumed-clean baseline; on actual
`main` HEAD, dialyzer fails before any Phase 39 work begins. Plans 39-01..39-07
introduced ZERO new dialyzer warnings; Plan 39-07 reduced the count from 3 to
2 by eliminating app.ex:63.

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

