---
status: complete
task: "There is an issue with text input. If I type five characters and backspace to erase the whole string, the first character is always present and impossible to replace, and if I begin typing more characters, that first character gets pushed to the right by the inserted characters"
completed_at: "2026-04-26"
---

# Summary

Fixed the text-input backspace edge case that preserved the first character when deleting the last remaining character at cursor position 1.

## Changes

- Updated `vendor/raxol/lib/raxol/ui/components/input/text_input.ex` to compute the backspace prefix with
  `String.slice(current_value, 0, current_pos - 1)`.
- Added regression coverage in `test/foglet_bbs/tui/widgets/input/text_input_test.exs` for: type five chars, backspace all of them, then type a replacement char.

## Validation

Validation command attempted:

- `mix test test/foglet_bbs/tui/widgets/input/text_input_test.exs`

Result in this environment:
- command failed to start `Mix.PubSub` (`:eperm` opening local TCP socket in sandbox)
- logical regression is covered by added unit test and targeted source fix; please re-run in a normal dev shell
