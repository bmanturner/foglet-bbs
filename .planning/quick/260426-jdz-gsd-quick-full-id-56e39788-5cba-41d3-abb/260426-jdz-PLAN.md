---
status: complete
must_haves:
  truths:
    - Breadcrumb rendering must not call Access on Foglet.Boards.Board structs.
    - Existing map-backed breadcrumb behavior must remain intact.
  artifacts:
    - lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex
    - test/foglet_bbs/tui/widgets/chrome/breadcrumb_test.exs
  key_links:
    - lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex
---

# Quick Task 260426-jdz: Fix Board Breadcrumb Struct Access

## Task 1

**Files:** `lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex`, `test/foglet_bbs/tui/widgets/chrome/breadcrumb_test.exs`

**Action:** Replace Access-style board name lookup with map/struct-safe field lookup and add a regression test that passes `%Foglet.Boards.Board{}` as `current_board`.

**Verify:** Run the breadcrumb widget test and full precommit.

**Done:** Complete. Breadcrumb paths render for both maps and Board structs without raising `Foglet.Boards.Board.fetch/2`.
