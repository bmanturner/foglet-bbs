---
quick_id: 260426-gnq
status: planned
must_haves:
  truths:
    - "Breadcrumb/status text renders on the top border row."
    - "Command hints render on the bottom border row."
    - "ScreenFrame.render/4 remains the shared screen-facing API."
  artifacts:
    - "lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex"
    - "lib/foglet_bbs/tui/widgets/chrome/command_bar.ex"
    - "test/foglet_bbs/tui/widgets/chrome/screen_frame_test.exs"
    - "test/foglet_bbs/tui/layout_smoke_test.exs"
  key_links:
    - "ScreenFrame -> BreadcrumbBar.format/2"
    - "ScreenFrame -> StatusBar.status_atoms/1"
    - "ScreenFrame -> CommandBar.render_text/2"
---

# Quick Task 260426-gnq Plan

## Task 1: Make ScreenFrame Border Rows Explicit

**files:** `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex`, `lib/foglet_bbs/tui/widgets/chrome/command_bar.ex`

**action:** Replace the outer Raxol bordered box with explicit top and bottom border text rows. Add a `CommandBar.render_text/2` helper so the bottom border can use existing command normalization and truncation.

**verify:** `rtk mix test test/foglet_bbs/tui/widgets/chrome`

**done:** Top and bottom chrome text is embedded in the border-row strings while keeping the `ScreenFrame.render/4` caller contract.

## Task 2: Lock Border Placement With Tests

**files:** `test/foglet_bbs/tui/widgets/chrome/screen_frame_test.exs`, `test/foglet_bbs/tui/layout_smoke_test.exs`

**action:** Assert rendered top text starts with the top-left glyph and includes breadcrumb/status. Assert rendered bottom text starts with the bottom-left glyph and includes command hints. Update positioned smoke coverage to prove top border is `y == 0` and bottom command border is `height - 1`.

**verify:** `rtk mix test test/foglet_bbs/tui/widgets/chrome/screen_frame_test.exs test/foglet_bbs/tui/layout_smoke_test.exs`

**done:** Tests fail if breadcrumbs or commands drift back off the border rows.
