# Phase 16 Deferred Items

## 16-03 Precommit Blockers Outside Plan Scope

- `lib/foglet_bbs/tui/widgets/list/list_row.ex` has a pre-existing Credo alias-order finding from the list-row width work.
- `test/foglet_bbs/tui/widgets/list/list_row_test.exs` has a pre-existing Credo alias-order finding from the list-row width work.
- `lib/foglet_bbs/tui/text_width.ex` has a pre-existing Credo refactor suggestion for `split_at_grapheme_boundary/3`.

These were discovered while running `rtk mix precommit` for plan 16-03. They are not part of plan 16-03's keybar, modal, or main-menu migration scope.
