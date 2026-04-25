---
phase: 16-unicode-width-foundation
plan: 04
status: complete
created: 2026-04-25
---

# Phase 16 Width Scan

This scan records the Phase 16 layout-sensitive migration state after plans
16-01 through 16-04. The boundary is terminal display width for TUI layout
versus product character-count validation for content policy.

## Scan Command

```bash
rtk rg -n "String\.(length|slice|split_at|pad_leading|pad_trailing)|String\.graphemes" lib/foglet_bbs/tui/widgets/list/list_row.ex lib/foglet_bbs/tui/widgets/chrome/key_bar.ex lib/foglet_bbs/tui/widgets/modal.ex lib/foglet_bbs/tui/widgets/compose.ex lib/foglet_bbs/tui/screens/main_menu.ex lib/foglet_bbs/tui/screens/post_composer.ex lib/foglet_bbs/tui/screens/new_thread.ex
```

## Scan Results

```text
lib/foglet_bbs/tui/screens/new_thread.ex:94:    title_len = String.length(title_value)
lib/foglet_bbs/tui/screens/post_composer.ex:73:          text("#{String.length(draft)} / #{max_len(state)} chars", fg: theme.dim.fg)
lib/foglet_bbs/tui/screens/post_composer.ex:171:    if String.length(input_st.value) > max do
lib/foglet_bbs/tui/screens/post_composer.ex:175:      truncated = String.slice(input_st.value, 0, max)
lib/foglet_bbs/tui/screens/post_composer.ex:248:      String.length(draft) > max ->
```

## Migrated Layout Paths

The inspected layout-sensitive paths are migrated to `Foglet.TUI.TextWidth` or
are clean of direct string-width operations:

| Path | Status |
|------|--------|
| `lib/foglet_bbs/tui/widgets/list/list_row.ex` | Uses `Foglet.TUI.TextWidth` for row marker, title, metadata, truncation, and padding layout. |
| `lib/foglet_bbs/tui/widgets/chrome/key_bar.ex` | Uses `Foglet.TUI.TextWidth` for keybar hint measurement and truncation. |
| `lib/foglet_bbs/tui/widgets/modal.ex` | Uses `Foglet.TUI.TextWidth` for modal word-wrap line-fit checks. |
| `lib/foglet_bbs/tui/widgets/compose.ex` | Uses `Foglet.TUI.TextWidth.split_at/2` for visible cursor insertion. |
| `lib/foglet_bbs/tui/screens/main_menu.ex` | Uses `Foglet.TUI.TextWidth.slice_to_width/2` for oneliner handle/body clipping. |

## Intentional Character-Count Boundaries

The remaining direct string operations are not terminal layout width. They are
product policy counters and limits preserved by D-07/D-08:

- `lib/foglet_bbs/tui/screens/post_composer.ex`
  - `String.length(draft)` in the footer renders the post body length as
    `N / max chars`.
  - `String.length(input_st.value) > max` enforces `max_post_length`.
  - `String.slice(input_st.value, 0, max)` truncates the stored draft to the
    configured post body length.
  - `String.length(draft) > max` protects submit from over-limit post bodies.
  - These are post body length rules and must remain character-count policy,
    not display-width policy.
- `lib/foglet_bbs/tui/screens/new_thread.ex`
  - `String.length(title_value)` renders the thread title counter.
  - Thread title length remains a character-count policy backed by the
    `max_thread_title_length` configuration and `TextInput` max-length
    behavior, not terminal display width.

Verification-code length is also a preserved character-count policy per D-07,
but this focused scan did not inspect verification modules because Phase 16 did
not change domain/schema/auth or verification-code handling.

## Verification

Focused Phase 16 verification command:

```bash
rtk mix test test/foglet_bbs/tui/text_width_test.exs test/foglet_bbs/tui/widgets/list/list_row_test.exs test/foglet_bbs/tui/widgets/chrome/key_bar_test.exs test/foglet_bbs/tui/widgets/modal_test.exs test/foglet_bbs/tui/widgets/compose_test.exs test/foglet_bbs/tui/layout_smoke_test.exs
```

The source scan confirms the migrated layout-sensitive paths do not rely on
direct `String.length/1`, `String.slice/3`, `String.split_at/2`,
`String.pad_leading/2`, `String.pad_trailing/2`, or `String.graphemes/1` for
terminal display width.
