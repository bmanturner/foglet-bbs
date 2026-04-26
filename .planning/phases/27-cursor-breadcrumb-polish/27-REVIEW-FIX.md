---
phase: 27-cursor-breadcrumb-polish
fixed_at: 2026-04-26T00:00:00Z
review_path: .planning/phases/27-cursor-breadcrumb-polish/27-REVIEW.md
iteration: 1
findings_in_scope: 10
fixed: 10
skipped: 0
status: all_fixed
---

# Phase 27: Code Review Fix Report

**Fixed at:** 2026-04-26T00:00:00Z
**Source review:** .planning/phases/27-cursor-breadcrumb-polish/27-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 10
- Fixed: 10
- Skipped: 0

## Fixed Issues

### CR-01: Unguarded pattern match on `RaxolTextInput.init/1` return value

**Files modified:** `lib/foglet_bbs/tui/widgets/input/text_input.ex`
**Commit:** 8dd021b
**Applied fix:** Replaced bare `{:ok, raxol_state} = RaxolTextInput.init(raxol_props)` with a `case` expression that matches `{:ok, rs}` and raises a descriptive error on `{:error, reason}`.

### WR-01: `breadcrumb_slot/1` uses fragile empty-map equality guard

**Files modified:** `lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex`
**Commit:** 0d29ad2
**Applied fix:** Changed `empty when empty == %{}` to `slot when slot in [nil, %{}]` so both `nil` and `%{}` fall back to `theme.status_bar`.

### WR-02: Raxol component commands silently discarded in `handle_event/2`

**Files modified:** `lib/foglet_bbs/tui/widgets/input/text_input.ex`
**Commit:** 602eb67
**Applied fix:** Added a two-line comment above the `{new_rs, _raxol_cmds}` binding documenting that Raxol commands are intentionally dropped and the revisit condition. Renamed `_cmds` to `_raxol_cmds` for clarity.

### WR-03: `board_name/1` always probes `:new_thread` screen state regardless of current screen

**Files modified:** `lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex`
**Commit:** 0994c69
**Applied fix:** Restructured `board_name/1` to only probe `:new_thread` screen state when `current_board` has no `:name` — the compose-screen fallback is now reached only when the primary board is absent, preventing stale board names from leaking into `:post_reader` breadcrumbs. This is logically equivalent to the reviewer's suggested fix (requires human verification for edge cases).

### WR-04: Tautological overlap filter in board_list smoke test

**Files modified:** `test/foglet_bbs/tui/layout_smoke_test.exs`
**Commit:** 6e13896
**Applied fix:** Removed the always-true `String.contains?(flat, row_text)` condition from the `Enum.filter/2` predicate, leaving only the meaningful board-row content check.

### WR-05: `width_before_cursor/1` returns `nil` on missing cursor; unhelpful failure message

**Files modified:** `test/foglet_bbs/tui/widgets/input/text_input_test.exs`
**Commit:** ca8de1c
**Applied fix:** Added `width_before_cursor!/1` bang variant that calls `flunk/1` with the full rendered text when the cursor marker is absent. Updated both cursor-position assertion call sites (lines 138 and 149) to use the bang form.

### IN-01: Duplicate assertions in login menu smoke test

**Files modified:** `test/foglet_bbs/tui/layout_smoke_test.exs`
**Commit:** 31aeeca
**Applied fix:** Removed the three duplicate assertions for "L Login", "R Register", and "Q Quit" (the second assert of each pair that differed only in its failure message label).

### IN-02: `apply/1` shadows Kernel built-in in layout smoke test

**Files modified:** `test/foglet_bbs/tui/layout_smoke_test.exs`
**Commit:** 065b394
**Applied fix:** Renamed `defp apply(tree)` to `defp layout(tree)` and updated all 24 call sites (`= apply(tree)` -> `= layout(tree)`) via replace_all.

### IN-03: Obfuscated forbidden-URL strings in login_test

**Files modified:** `test/foglet_bbs/tui/screens/login_test.exs`
**Commit:** e047493
**Applied fix:** Replaced the string-concatenation constructions in `forbidden_reset_route/0`, `forbidden_http_prefix/0`, and `forbidden_https_prefix/0` with plain string literals.

### IN-04: `active_tab_index/1` calls `Map.get` twice for the same key

**Files modified:** `lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex`
**Commit:** cfe90ff
**Applied fix:** Collapsed each two-line `cond` branch into a single line using inline assignment (`val = Map.get(...)`), eliminating the redundant double lookup.

---

_Fixed: 2026-04-26T00:00:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
