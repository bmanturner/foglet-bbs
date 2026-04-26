# Quick Task 260426-jdz: Research

## Finding

The crash signature is specific to using Access syntax on an Ecto struct:

- `board[:name]` calls `Foglet.Boards.Board.fetch/2`.
- Ecto schema structs do not implement the Access behaviour.
- `Map.get(board, :name)` works for both plain maps and structs.

## Integration Points

- `BreadcrumbBar.board_name/1` derives board display names from `state.current_board` and from the new-thread compose state.
- TUI state can hold either fixture maps in tests or real Ecto structs in production.

## Pitfalls

- Do not convert structs with `Map.from_struct/1` in this rendering path; it would be broader than needed and may preserve unloaded association values.
- Prefer a tiny accessor helper for this widget so all board-name candidates are read consistently.

