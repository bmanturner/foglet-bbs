# Quick Research: TextInput backspace prefix deletion

**Researched:** 2026-04-26
**Scope:** isolate and fix a single-character deletion edge case in `RaxolTextInput`.

## Key Finding

Elixir `String.slice/2` with an inverse range such as `0..-1` does not produce an empty prefix and is effectively an unsupported reverse-range case, which causes `String.slice("a", 0..-1)` to return `"a"`.

In the text-input backspace handler, deleting with cursor position `1` used:

```elixir
before_part = String.slice(current_value, 0..(current_pos - 2))
```

When `current_pos == 1`, this becomes `0..-1` and leaves the first character in `before_part` instead of removing it.

## Chosen Approach

Use length-based slicing for the prefix:

```elixir
before_part = String.slice(current_value, 0, current_pos - 1)
```

This returns an empty prefix at `current_pos == 1`, which makes backspace correctly remove the first character.
