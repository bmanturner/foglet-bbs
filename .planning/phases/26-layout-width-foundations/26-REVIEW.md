---
phase: 26-layout-width-foundations
reviewed: 2026-04-26T22:34:58Z
depth: standard
files_reviewed: 22
files_reviewed_list:
  - lib/foglet_bbs/markdown.ex
  - lib/foglet_bbs/tui/text_width.ex
  - lib/foglet_bbs/tui/widgets/display/table.ex
  - lib/foglet_bbs/tui/widgets/display/console_table.ex
  - lib/foglet_bbs/tui/widgets/input/tabs.ex
  - lib/foglet_bbs/tui/screens/moderation.ex
  - lib/foglet_bbs/tui/screens/moderation/state.ex
  - lib/foglet_bbs/tui/screens/shared/invites_state.ex
  - lib/foglet_bbs/tui/screens/board_list.ex
  - lib/foglet_bbs/tui/widgets/list/board_tree.ex
  - lib/foglet_bbs/tui/widgets/post/markdown_body.ex
  - test/foglet_bbs/markdown_test.exs
  - test/foglet_bbs/tui/text_width_test.exs
  - test/foglet_bbs/tui/widgets/display/table_test.exs
  - test/foglet_bbs/tui/widgets/display/console_table_test.exs
  - test/foglet_bbs/tui/widgets/input/tabs_test.exs
  - test/foglet_bbs/tui/screens/moderation_test.exs
  - test/foglet_bbs/tui/screens/board_list_test.exs
  - test/foglet_bbs/tui/widgets/list/board_tree_test.exs
  - test/foglet_bbs/tui/widgets/post/markdown_body_test.exs
  - test/foglet_bbs/tui/widgets/post/post_card_test.exs
  - test/foglet_bbs/tui/screens/post_reader_test.exs
findings:
  critical: 1
  warning: 1
  info: 0
  total: 2
status: issues_found
---

# Phase 26: Code Review Report

**Reviewed:** 2026-04-26T22:34:58Z
**Depth:** standard
**Files Reviewed:** 22
**Status:** issues_found

## Summary

Reviewed the Phase 26 width/layout helper changes, compact operator table and tabs usage, Boards viewport windowing, markdown newline preservation, and the related focused tests. The main correctness problem is in the new `TextWidth.wrap/2` contract: it can still emit lines wider than the requested display width for wide graphemes, leaving a hole in the layout foundation. I also found a missing defensive default that stores `nil` for table `page_size` on common no-option moderation table builders.

## Critical Issues

### CR-01: BLOCKER - `TextWidth.wrap/2` Can Emit Oversized Lines For Wide Graphemes

**File:** `lib/foglet_bbs/tui/text_width.ex:195`

**Issue:** `split_token/3` accepts the `left` side returned by `split_at/2` without re-checking that it fits the requested width. For a single wide grapheme and a width smaller than that grapheme, `wrap/2` violates its own Phase 26 contract that every emitted nonblank line is `<= width`.

Reproduction:

```elixir
lines = Foglet.TUI.TextWidth.wrap("あ", 1)
# => ["あ"]
Foglet.TUI.TextWidth.display_width(hd(lines))
# => 2
```

This is the layout primitive downstream widgets are supposed to trust. If a caller wraps CJK or emoji content into a 1-column residual cell, the helper returns an over-budget line and can reintroduce frame overflow.

**Fix:**

Guard the split result and choose an explicit fallback for unsplittable wide graphemes. For strict width-bounded layout, emit a width-fitting placeholder/ellipsis for that grapheme rather than returning an oversized line.

```elixir
defp split_token(token, width, chunks) do
  cond do
    display_width(token) <= width ->
      Enum.reverse([token | chunks])

    true ->
      {left, right} = split_at(token, width)

      cond do
        left == "" ->
          Enum.reverse([slice_to_width(@default_ellipsis, width) | chunks])

        display_width(left) > width ->
          Enum.reverse([slice_to_width(@default_ellipsis, width) | chunks])

        true ->
          split_token(right, width, [left | chunks])
      end
  end
end
```

Also add a regression test such as:

```elixir
test "wrap never emits a line wider than width for wide graphemes" do
  lines = TextWidth.wrap("あ", 1)
  assert lines != []
  assert Enum.all?(lines, &(TextWidth.display_width(&1) <= 1))
end
```

## Warnings

### WR-01: WARNING - Moderation Table Builders Pass `page_size: nil`

**File:** `lib/foglet_bbs/tui/screens/moderation/state.ex:120`

**Issue:** `build_log_table/2`, `build_users_table/2`, and `build_boards_table/2` always include `page_size: Keyword.get(opts, :page_size)`. When callers use the default path, that inserts `page_size: nil`, which bypasses `ConsoleTable` and `Table` default page-size handling because `Keyword.get(opts, :page_size, default)` returns the present nil value. A direct check shows `State.build_log_table([]).table.raxol_state.options.page_size == nil`.

Pagination is currently disabled, so this is not crashing today, but it weakens the table state contract and can break if Raxol starts consulting `page_size` regardless of `paginate`, or if this table is later made pageable.

**Fix:** Only pass `:page_size` when it is present and non-nil, or default it at the state-builder boundary.

```elixir
table_opts =
  [
    columns: columns,
    rows: items,
    selectable: false,
    width: Keyword.get(opts, :width),
    empty_state: "No moderation events in scope."
  ]
  |> Keyword.merge(if Keyword.has_key?(opts, :page_size), do: [page_size: Keyword.fetch!(opts, :page_size)], else: [])

ConsoleTable.init(table_opts)
```

Add coverage asserting the default moderation tables keep the ConsoleTable default:

```elixir
assert State.build_log_table([]).table.raxol_state.options.page_size == 10
```

---

_Reviewed: 2026-04-26T22:34:58Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
