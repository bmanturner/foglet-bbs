---
phase: 05-terminal-size-gate
fixed_at: 2026-04-20T00:00:00Z
review_path: .planning/workstreams/phase-03-polish/phases/05-terminal-size-gate/05-REVIEW.md
iteration: 1
findings_in_scope: 3
fixed: 3
skipped: 0
status: all_fixed
---

# Phase 05: Code Review Fix Report

**Fixed at:** 2026-04-20
**Source review:** .planning/workstreams/phase-03-polish/phases/05-terminal-size-gate/05-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 3
- Fixed: 3
- Skipped: 0

## Fixed Issues

### WR-01: `SizeGate.render/1` crashes if `terminal_size` is set to a non-tuple

**Files modified:** `lib/foglet_bbs/tui/size_gate.ex`
**Commit:** c9a440a
**Applied fix:** Replaced the bare pattern match `{cols, rows} = Map.get(state, :terminal_size) || {0, 0}` on line 73 with a `case` expression that guards both elements with `is_integer/1`. Any non-2-tuple value (atom, integer, 3-tuple, etc.) now safely falls back to `{0, 0}` instead of raising a `MatchError`, bringing `render/1` in line with the defensive handling already present in `too_small?/1`.

### WR-02: Broken test chain — key press during gate is not in the state lineage

**Files modified:** `test/foglet_bbs/tui/app_test.exs`
**Commit:** 15b5201
**Applied fix:** In the `"read_position survives resize gate cycle"` test, bound the key-press result to `after_keys` instead of discarding it with `{_, _}`, and threaded `after_keys` into the subsequent `App.update({:window_change, 100, 30}, ...)` call. The `released` state now descends from the post-key-press state, so the test actually exercises the full resize-down → key-swallow → resize-up causal chain as described.

### IN-01: Conditional assertion in theme fallback test can pass vacuously

**Files modified:** `test/foglet_bbs/tui/size_gate_test.exs`
**Commit:** 8771793
**Applied fix:** Removed the `if default_fg do ... end` guard in the `"falls back to Theme.default() when session_context is empty"` test. Added a hard prerequisite `assert default_fg != nil, "..."` so that a missing `dim.fg` in `Theme.default/0` is a test failure rather than a silent skip. The subsequent `assert serialized =~ default_fg` is now unconditional, eliminating the zero-assertion pass path.

---

_Fixed: 2026-04-20_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
