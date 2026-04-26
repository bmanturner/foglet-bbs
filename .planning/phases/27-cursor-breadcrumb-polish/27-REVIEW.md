---
phase: 27-cursor-breadcrumb-polish
reviewed: 2026-04-26T00:00:00Z
depth: standard
files_reviewed: 6
files_reviewed_list:
  - lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex
  - lib/foglet_bbs/tui/widgets/input/text_input.ex
  - test/foglet_bbs/tui/layout_smoke_test.exs
  - test/foglet_bbs/tui/screens/login_test.exs
  - test/foglet_bbs/tui/widgets/chrome/breadcrumb_test.exs
  - test/foglet_bbs/tui/widgets/input/text_input_test.exs
findings:
  critical: 1
  warning: 5
  info: 4
  total: 10
status: issues_found
---

# Phase 27: Code Review Report

**Reviewed:** 2026-04-26T00:00:00Z
**Depth:** standard
**Files Reviewed:** 6
**Status:** issues_found

## Summary

Phase 27 adds a block-cursor marker to `TextInput` and wires up auth-screen
breadcrumbs. The new `TextInput` render path is sound for the common case, but
one external-library call is completely unguarded (crash risk on bad init). The
`BreadcrumbBar` has a fragile slot-selection guard that can silently fall back
to the wrong style at runtime. The smoke-test suite contains several tautological
or duplicate assertions that deliver zero incremental coverage.

---

## Critical Issues

### CR-01: Unguarded pattern match on `RaxolTextInput.init/1` return value

**File:** `lib/foglet_bbs/tui/widgets/input/text_input.ex:72`

**Issue:** The call to `RaxolTextInput.init(raxol_props)` is matched directly
against `{:ok, raxol_state}` with no error clause. If the upstream Raxol
component ever returns `{:error, reason}` (e.g., on invalid `max_length` type,
future API change, or a bad `:mask_char` value), the process will crash with a
`MatchError` rather than surfacing a clear message. Every `TextInput.init/1`
call in screen init paths runs in the SSH channel process — a crash here takes
the user's session down without a recoverable error.

**Fix:**
```elixir
raxol_state =
  case RaxolTextInput.init(raxol_props) do
    {:ok, rs} -> rs
    {:error, reason} -> raise "TextInput: RaxolTextInput.init failed: #{inspect(reason)}"
  end
```
Or, if defensive degradation is preferred over a loud crash, default to an
empty map and log a warning. Either way, the silent `MatchError` path must be
replaced with an intentional, diagnosable failure.

---

## Warnings

### WR-01: `breadcrumb_slot/1` uses fragile empty-map equality guard

**File:** `lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex:176-181`

**Issue:** The fallback logic `empty when empty == %{}` will only match when
`theme.title` is literally `%{}`. If the field is `nil`, a partially-populated
map, or any non-map value, the guard falls through to the `title -> title`
branch, returning whatever is in `theme.title` — including a map that may be
missing `:fg`/`:bg` keys, causing `Map.get/2` to silently return `nil` and
produce an unstyled breadcrumb without any error. This will be invisible in
passing tests but wrong at runtime under any theme where `title` is unset as
`nil` rather than `%{}`.

```elixir
# Current — silent misfire if theme.title is nil
defp breadcrumb_slot(theme) do
  case theme.title do
    empty when empty == %{} -> theme.status_bar
    title -> title
  end
end

# Fix — explicitly handle nil and empty
defp breadcrumb_slot(theme) do
  case theme.title do
    slot when slot in [nil, %{}] -> theme.status_bar
    slot -> slot
  end
end
```

### WR-02: Raxol component commands silently discarded in `handle_event/2`

**File:** `lib/foglet_bbs/tui/widgets/input/text_input.ex:86`

**Issue:** `{new_rs, _cmds} = RaxolTextInput.handle_event(...)` discards the
command list returned by the underlying Raxol component. The `TextInput` module
documents a clean `{state, action}` contract, but if Raxol starts returning
side-effecting commands (async validation, clipboard, IME) in a future version,
they will be silently dropped. This is currently benign but represents a silent
contract violation with the underlying library.

**Fix:** At minimum document this explicitly:
```elixir
# Commands from Raxol are intentionally dropped; TextInput's contract exposes
# only the semantic action. Revisit if Raxol gains side-effecting commands.
{new_rs, _raxol_cmds} = RaxolTextInput.handle_event(raxol_event, rs, %{})
```
If Raxol commands carry anything observable, propagate them upward or assert
they are always empty.

### WR-03: `board_name/1` always probes `:new_thread` screen state regardless of current screen

**File:** `lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex:114-127`

**Issue:** `board_name/1` is called from `parts_for_screen/2` for `:thread_list`,
`:post_reader`, `:new_thread`, and `:post_composer`. In all cases it probes
`screen_state_for(state, :new_thread)` as a fallback. For a user on
`:post_reader`, if `:new_thread` screen state happens to contain a stale board
from a previous navigation, the breadcrumb silently shows that stale board name
instead of `"Boards"`. The intent is to support compose flows where
`current_board` is absent, but the fallback is not scoped to compose screens.

**Fix:** Scope the `:new_thread` fallback only to the screens that need it:
```elixir
defp board_name(state) do
  state_board = state |> Map.get(:current_board) |> map_or_empty()

  if Map.get(state_board, :name) do
    board_label(state_board)
  else
    compose_board =
      state |> screen_state_for(:new_thread) |> Map.get(:board) |> map_or_empty()
    board_label(compose_board) || "Boards"
  end
end
```
Or pass the current screen to `board_name/2` so the fallback is only reached
for compose screens.

### WR-04: Tautological overlap filter in board_list smoke test

**File:** `test/foglet_bbs/tui/layout_smoke_test.exs:554-564`

**Issue:** The overlap check at the end of the board_list size-contract test
filters elements with:
```elixir
String.contains?(flat, row_text)
```
where `flat` is the concatenation of **all** element texts. Since `row_text` is
always a substring of `flat` (it came from the same elements), this condition
is always `true` — the filter never excludes any element. The `assert_board_list_no_row_overlap!/3`
call therefore runs against the full element set, not the intended board-related
subset, making the scoping comment misleading and providing false confidence.

**Fix:** Filter by a meaningful predicate, e.g., match elements whose `y`
coordinate falls on a known board row, or drop the filter and assert overlap
across all non-chrome elements (which is what happens anyway).

### WR-05: `width_before_cursor/1` returns `nil` on missing cursor; test assertion gives unhelpful failure message

**File:** `test/foglet_bbs/tui/widgets/input/text_input_test.exs:16-21` and `:138`

**Issue:** If `flatten_text(rendered)` does not contain `"▌"`, `width_before_cursor/1`
returns `nil`. The assertion `assert width_before_cursor(result) == TextWidth.display_width("abc")`
then fails as `assert nil == 3`, giving no indication that the cursor was absent
entirely vs. positioned at the wrong column. This masks test failures as cursor
positioning bugs.

**Fix:**
```elixir
defp width_before_cursor!(rendered) do
  flat = flatten_text(rendered)
  case String.split(flat, "▌", parts: 2) do
    [before, _after] -> TextWidth.display_width(before)
    [_no_cursor] -> flunk("expected cursor marker ▌ in rendered output, got: #{inspect(flat)}")
  end
end
```
Use `width_before_cursor!/1` in the cursor-position assertion tests.

---

## Info

### IN-01: Duplicate assertions in login menu smoke test

**File:** `test/foglet_bbs/tui/layout_smoke_test.exs:1020-1035`

**Issue:** Six assertions appear in three identical pairs. Lines 1020 and 1023
both assert `Enum.any?(rendered_rows, &String.contains?(&1, "L Login"))` with
only the failure message differing ("key" vs "label"). Same duplication for
"R Register" and "Q Quit". These provide zero additional test coverage and add
noise.

**Fix:** Remove the three duplicate assertions (lines 1023, 1029, 1035).

### IN-02: `apply/1` shadows Kernel built-in in layout smoke test

**File:** `test/foglet_bbs/tui/layout_smoke_test.exs:94`

**Issue:** `defp apply(tree)` shadows `Kernel.apply/2` and `Kernel.apply/3`
within this module. While no test in this file calls `Kernel.apply`, the shadow
is a latent confusion risk — any future contributor who writes `apply(mod, fun, args)`
in this file will get a clause error rather than the expected MFA dispatch.

**Fix:** Rename to `defp layout(tree)` or `defp apply_default(tree)`.

### IN-03: Obfuscated forbidden-URL strings in login_test

**File:** `test/foglet_bbs/tui/screens/login_test.exs:91-93`

**Issue:** `forbidden_reset_route/0`, `forbidden_http_prefix/0`, and
`forbidden_https_prefix/0` build their return values via string concatenation
(`"/" <> "users" <> "/" <> "reset_password"`, etc.) as if to avoid triggering
a scanner. The concatenation is evaluated at compile time and offers no actual
obfuscation in the compiled beam. This is dead complexity.

**Fix:** Use plain string literals. If the intent was to appease a secret scanner,
add an inline `# scanner-safe` comment explaining the split, or configure the
scanner to ignore test files.

### IN-04: `active_tab_index/1` calls `Map.get` twice for the same key

**File:** `lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex:163-174`

**Issue:** The `cond` in `active_tab_index/1` calls `Map.get(screen_state, :active_tab)`
once to check `is_integer/1` and again to return the value. Same pattern for
`:active_tab_index`. Minor but avoidable.

**Fix:**
```elixir
defp active_tab_index(screen_state) do
  cond do
    is_integer(val = Map.get(screen_state, :active_tab)) -> val
    is_integer(val = Map.get(screen_state, :active_tab_index)) -> val
    true -> nil
  end
end
```

---

_Reviewed: 2026-04-26T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
