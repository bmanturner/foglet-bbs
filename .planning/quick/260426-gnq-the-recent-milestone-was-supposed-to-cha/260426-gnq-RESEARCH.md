# Quick Task 260426-gnq: Screen Border Chrome Placement - Research

## Findings

- `SCREENS.md` is referenced by the Phase 18 spec and project state, but no file named `SCREENS.md` exists in the workspace.
- Phase 18's implementation currently composes `ScreenFrame` as a Raxol `box` with `border: :single` and `padding: 1`.
- Raxol box borders are rendered by the layout/element renderer around the child space. Child text cannot occupy the generated top or bottom border row through the normal `box` child layout.
- The observed defect follows directly from that structure:
  - `StatusBar.render/3` is the first child inside the bordered/padded box, so it appears below the top border.
  - `CommandBar.render/3` is the last child inside the box, so it appears above the bottom border.

## Recommended Approach

- Replace the outer bordered box in `ScreenFrame` with explicit text rows for the top and bottom borders.
- Use `BreadcrumbBar.format/2`, `StatusBar.status_atoms/1`, and `CommandBar` normalized text so existing Chrome V2 data ownership remains intact.
- Preserve width safety with `Foglet.TUI.TextWidth`.
- Update positioned layout tests to assert top chrome is at `y == 0` and command chrome is at `height - 1`.

## Risks

- Rendering command keys as one border-row string changes positioned text granularity. Existing tests that expected each key/label as separate nodes need to assert the border-row command content instead.
- The explicit border rows satisfy the top/bottom placement contract, but this quick task does not add vertical side border glyphs for every content row.
