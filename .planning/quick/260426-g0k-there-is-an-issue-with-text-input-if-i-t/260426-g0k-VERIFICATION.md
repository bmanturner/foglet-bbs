---
quick_id: 260426-g0k
phase: quick-260426-g0k
verified: 2026-04-26T00:00:00Z
status: human_needed
overrides_applied: 0
---

# Quick Task 260426-g0k Verification

## Goal

Ensure backspace deletes the first character when cursor position is 1 and that retyping after full erase inserts text from position 0.

## Verification status

Automated verification is not complete in this sandbox because `mix test` fails to start Mix.PubSub (`:eperm` opening a local TCP socket). The test was added, but execution is pending in a normal dev shell.

| # | Truth | Status |
|---|---|---|
| 1 | Backspace at start-position (`current_pos == 1`) no longer preserves the first char. | PENDING |
| 2 | After five backspaces from a five-character string, input value is empty and new typed input starts at the beginning without prepending the stale char. | PENDING |

## Method

- Regression test added in `test/foglet_bbs/tui/widgets/input/text_input_test.exs`.
- Test covers end-to-end event flow through Foglet text input wrapper using `TextInput.handle_event/2`.
