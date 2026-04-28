---
phase: 33-composer-wrap-boards-interaction
reviewed: 2026-04-28T14:29:22Z
depth: standard
files_reviewed: 8
files_reviewed_list:
  - lib/foglet_bbs/tui/screens/board_list.ex
  - lib/foglet_bbs/tui/screens/new_thread.ex
  - lib/foglet_bbs/tui/screens/post_composer.ex
  - lib/foglet_bbs/tui/widgets/compose.ex
  - test/foglet_bbs/tui/screens/board_list_test.exs
  - test/foglet_bbs/tui/screens/new_thread_test.exs
  - test/foglet_bbs/tui/screens/post_composer_test.exs
  - test/foglet_bbs/tui/widgets/compose_test.exs
findings:
  critical: 0
  warning: 1
  info: 0
  total: 1
status: issues_found
---

# Phase 33: Code Review Report

**Reviewed:** 2026-04-28T14:29:22Z
**Depth:** standard
**Files Reviewed:** 8
**Status:** issues_found

## Summary

Reviewed the scoped TUI board-list, new-thread, post-composer, shared compose widget, and their tests after commit `fix(33): keep composer cursor positions grapheme-based`. The previous CJK/full-width cursor placement bug is fixed: `render_logical_line/4` now uses `String.split_at/2` with the grapheme-based `MultiLineInput.cursor_pos`, and the focused regression test covers `"漢字"` with cursor position `{0, 1}` rendering as `漢█字`.

One related Unicode input defect remains in the same shared composer path: typed multi-codepoint graphemes are truncated before they reach `MultiLineInput`.

## Warnings

### WR-01: Multi-Codepoint Graphemes Are Truncated On Input

**File:** `lib/foglet_bbs/tui/widgets/compose.ex:88`

**Issue:** `translate_key/1` documents that typed `%{key: :char, char: grapheme_string}` events support emoji/unicode graphemes, but it converts the binary to a charlist and returns only `[cp | _]`. That preserves single-codepoint CJK like `"漢"`, but drops trailing codepoints from valid graphemes such as decomposed accents (`"e\u0301"`), skin-tone emoji, or ZWJ sequences before either composer stores the draft. The test at `test/foglet_bbs/tui/widgets/compose_test.exs:92` currently codifies this truncation instead of protecting user input.

**Fix:** Preserve the full grapheme at the composer boundary. One low-risk path is to add a helper that applies all printable codepoints from the `char` binary to `MultiLineInput.update/2`, then replace the direct single-message update in both composer screens with that helper.

```elixir
def apply_key(%MultiLineInput{} = input, %{key: :char, char: c}) when is_binary(c) do
  c
  |> String.to_charlist()
  |> Enum.reject(&(&1 < 32))
  |> Enum.reduce({:ok, input}, fn cp, {:ok, acc} ->
    case MultiLineInput.update({:input, cp}, acc) do
      {:noreply, next, _cmds} -> {:ok, next}
      next when is_struct(next, MultiLineInput) -> {:ok, next}
      _other -> {:error, acc}
    end
  end)
end
```

Then add a regression asserting a typed multi-codepoint grapheme round-trips through `PostComposer.handle_key/2` and `NewThread.handle_key/2` without dropping combining marks or joiner sequence codepoints.

---

_Reviewed: 2026-04-28T14:29:22Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
