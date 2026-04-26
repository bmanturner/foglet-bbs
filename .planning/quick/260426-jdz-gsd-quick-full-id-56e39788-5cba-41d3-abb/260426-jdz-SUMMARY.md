---
status: complete
quick_id: 260426-jdz
date: 2026-04-26
commit: c357fc6
---

# Quick Task 260426-jdz Summary

## Completed

- Fixed breadcrumb board-name derivation so `%Foglet.Boards.Board{}` structs use `Map.get/3` instead of Access syntax.
- Added a regression test covering `%Foglet.Boards.Board{name: "general"}` in `current_board`.

## Files Changed

- `lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex`
- `test/foglet_bbs/tui/widgets/chrome/breadcrumb_test.exs`

## Verification

- `rtk mix test test/foglet_bbs/tui/widgets/chrome/breadcrumb_test.exs`
- `rtk mix precommit`

Status: complete.
