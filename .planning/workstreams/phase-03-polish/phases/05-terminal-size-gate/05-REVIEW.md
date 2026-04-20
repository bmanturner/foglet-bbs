---
phase: 05-terminal-size-gate
reviewed: 2026-04-20T00:00:00Z
depth: standard
files_reviewed: 4
files_reviewed_list:
  - lib/foglet_bbs/tui/size_gate.ex
  - test/foglet_bbs/tui/size_gate_test.exs
  - lib/foglet_bbs/tui/app.ex
  - test/foglet_bbs/tui/app_test.exs
findings:
  critical: 0
  warning: 2
  info: 1
  total: 3
status: issues_found
---

# Phase 05: Code Review Report

**Reviewed:** 2026-04-20
**Depth:** standard
**Files Reviewed:** 4
**Status:** issues_found

## Summary

Reviewed the terminal size gate implementation across `SizeGate`, `App`, and their test suites. The core logic is solid: the `too_small?/1` guard, the render-time branch in `view/1`, and the key-swallow in `do_update({:key, _})` are all correctly implemented and well-tested. The same-size short-circuit (D-09), the render-only gate contract (D-04), and the state-preservation invariants are all upheld.

Two warnings were found: a potential crash in `SizeGate.render/1` if `terminal_size` is set to a non-tuple value, and a broken test chain in `app_test.exs` that means a key-press-during-gate scenario is not actually exercised. One info item notes a conditional assertion that can pass vacuously.

No critical security or data-loss issues were found.

## Warnings

### WR-01: `SizeGate.render/1` crashes if `terminal_size` is set to a non-tuple

**File:** `lib/foglet_bbs/tui/size_gate.ex:73`

**Issue:** The pattern match `{cols, rows} = Map.get(state, :terminal_size) || {0, 0}` will raise a `MatchError` at runtime if `state.terminal_size` is present but is not a 2-tuple — for example `nil` passes the `|| {0, 0}` fallback correctly, but an atom, integer, or 3-tuple stored in `:terminal_size` would crash the match. By contrast, `too_small?/1` handles all bad shapes safely via its fallback clause and never crashes. The inconsistency means the render path has a narrower safe zone than the gate predicate.

In practice, the only writers of `terminal_size` are `init/1` (always `{w, h}`) and `do_update({:window_change, cols, rows}, ...)` (guarded by `is_integer/1`), so corruption from internal code is unlikely. However, direct test construction or a future refactor could expose this.

**Fix:**
```elixir
# Replace the bare pattern match with a safe extraction:
terminal_size = Map.get(state, :terminal_size)
{cols, rows} =
  case terminal_size do
    {c, r} when is_integer(c) and is_integer(r) -> {c, r}
    _ -> {0, 0}
  end
```

---

### WR-02: Broken test chain — key press during gate is not in the state lineage

**File:** `test/foglet_bbs/tui/app_test.exs:465-467`

**Issue:** In the `"read_position survives resize gate cycle"` test, the result of the key press on line 466 is discarded and `gated` (not the post-key-press state) is used to compute `released` on line 467. This means the test does not actually verify that the key press during the gated state leaves `read_position` and `screen_state` intact — it tests resize-down followed immediately by resize-up, skipping the key press in the causal chain entirely. The test description says "key presses" are part of the scenario, making this a silent coverage gap.

```elixir
# Current (broken chain — key press result discarded):
{gated, _} = App.update({:window_change, 50, 15}, state_reading)
{_, _} = App.update({:key, %{key: :char, char: "j"}}, gated)      # result ignored
{released, _} = App.update({:window_change, 100, 30}, gated)       # uses gated, not after_keys
```

**Fix:**
```elixir
# Corrected chain — thread the state through each step:
{gated, _} = App.update({:window_change, 50, 15}, state_reading)
{after_keys, _} = App.update({:key, %{key: :char, char: "j"}}, gated)
{released, _} = App.update({:window_change, 100, 30}, after_keys)   # use after_keys

assert released.read_position == state_reading.read_position
assert released.screen_state.post_reader.selected_post_index == 5
assert released.current_screen == :post_reader
```

---

## Info

### IN-01: Conditional assertion in theme fallback test can pass vacuously

**File:** `test/foglet_bbs/tui/size_gate_test.exs:88-97`

**Issue:** The `"falls back to Theme.default() when session_context is empty"` test wraps its assertion in `if default_fg do ... end`. If `Theme.default()` returns a theme where `dim.fg` is `nil` or absent, the test body is skipped entirely and the test passes without asserting anything. A test that can pass with zero assertions is a silent blind spot.

**Fix:** Either assert unconditionally that the element is non-nil and contains some expected string from the default theme (without depending on `dim.fg` being non-nil), or assert that `default_fg` is non-nil as a prerequisite:

```elixir
test "falls back to Theme.default() when session_context is empty" do
  default = Theme.default()
  default_fg = Map.get(default.dim, :fg)
  # Ensure the default theme actually has a dim.fg — if this fails,
  # Theme.default/0 needs to be updated to provide one.
  assert default_fg != nil, "Theme.default() must provide a dim.fg for SizeGate rendering"

  element = SizeGate.render(%{terminal_size: {40, 10}, session_context: %{}})
  serialized = inspect(element, limit: :infinity)
  assert serialized =~ default_fg
end
```

---

_Reviewed: 2026-04-20_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
