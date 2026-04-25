---
phase: 19-main-menu-dashboard
reviewed: 2026-04-25T00:00:00Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - lib/foglet_bbs/tui/screens/main_menu.ex
  - test/foglet_bbs/tui/layout_smoke_test.exs
  - test/foglet_bbs/tui/screens/main_menu_test.exs
findings:
  critical: 0
  warning: 3
  info: 5
  total: 8
status: issues_found
---

# Phase 19: Code Review Report

**Reviewed:** 2026-04-25
**Depth:** standard
**Files Reviewed:** 3
**Status:** issues_found

## Summary

Phase 19 (Plans 01-03) refactors `Foglet.TUI.Screens.MainMenu` around a single
canonical `@main_menu_commands` descriptor list, replaces the flat menu layout
with two boxed `Navigation` / `Oneliners` panels driven by a terminal-size-aware
inner-width budget, and adds size-contract tests at three canonical terminal
geometries with real CJK + combining-mark fixtures.

The implementation is well-structured, hews to project conventions (Bodyguard
advisory UI gating, theme slot routing, `TextWidth` for display-width math, no
screen-local state), and is exercised by a thorough test matrix. The changes
preserve the established `ShellVisibility` predicates as the single source of
truth for role gating, and the `:destination` vs `:action` `:kind` partition
gives a clean structural disjointness property that the test suite asserts as
a data property (not just a literal-keys sweep).

The findings below are mostly cleanup and one math/contract gap. None are
blocking and there are no security issues.

Specifically:

- One warning concerns a `Map.fetch!/2` coupling between `@main_menu_commands`
  and `@nav_glyphs` that crashes the entire screen render if the two lists
  drift — exactly the kind of drift the Phase 19 D-01 single-source-of-truth
  refactor was designed to prevent for the destination/action split.
- One warning concerns an inconsistency between the `@oneliner_body_limit`
  comment math and the actual right-panel inner width at 64×22: the comment
  asserts an "exact fit at the narrowest canonical terminal size", but the
  combined row width (37 cols) exceeds the right-panel inner width (~34 cols)
  derived from the same `nav_panel_inner_width/1` allocation; the row stays
  within the viewport only because the panel's right border sits at the
  viewport edge. The size-contract test at 64×22 only asserts viewport bounds
  and left-edge containment — it never asserts right-panel inner containment,
  so the gap between the comment and reality is invisible to CI.
- One warning concerns a magic-number duplication between
  `nav_panel_inner_width/1` and the test that asserts every nav row fits the
  budget: the `chrome_outer = 4` / ratio `{2, 3}` / `box_border = 2` /
  floor `20` math is rederived in both places, so a future change to either
  constant on one side will silently desync until the test fails.

## Warnings

### WR-01: `Map.fetch!/2` on `@nav_glyphs` panics the whole screen if a destination is added without a glyph

**File:** `lib/foglet_bbs/tui/screens/main_menu.ex:309-317`

**Issue:** `nav_row/3` looks up the per-row glyph via `Map.fetch!(@nav_glyphs, key)`.
`@nav_glyphs` is keyed by destination `key` and is defined separately from
`@main_menu_commands`. The two lists are coupled at compile time but not
co-located — a future contributor adding a new destination row to
`@main_menu_commands` (the canonical D-01 source of truth) without also adding
a glyph to `@nav_glyphs` will not get a compile error; the screen will instead
crash at render time with a `KeyError` the first time that role logs in.

This is exactly the kind of drift that Phase 19 D-01's single-source-of-truth
refactor was designed to eliminate for the destination/action split. The
`@nav_glyphs` map reintroduces the same drift hazard one level down.

**Fix:** Either fold the glyph into the `@main_menu_commands` descriptor map
so the two attributes cannot drift, or fail closed with a soft default and
log a warning rather than crashing the screen. Folding into the descriptor is
preferable because it keeps the canonical list complete:

```elixir
@main_menu_commands [
  %{key: "B", label: "Boards", glyph: "●", kind: :destination, visibility: :always},
  %{key: "C", label: "Compose", glyph: "✎", kind: :destination, visibility: :always},
  %{key: "A", label: "Account", glyph: "◇", kind: :destination, visibility: :account},
  %{key: "M", label: "Moderation", glyph: "⚑", kind: :destination, visibility: :moderation},
  %{key: "S", label: "Sysop", glyph: "▣", kind: :destination, visibility: :sysop},
  %{key: "Q", label: "Logout", glyph: "↯", kind: :destination, visibility: :always},
  %{key: "O", label: "Oneliner", kind: :action, visibility: :authenticated},
  # ... actions don't need glyphs
]
```

Then `visible_destinations/1` returns `{key, label, glyph}` triples (or the
descriptor map directly), and `nav_row/3` reads `entry.glyph` instead of
fetching from a parallel map. If the descriptor refactor is too invasive,
the minimal defensive change is `Map.get(@nav_glyphs, key, "·")` plus a
`Logger.warning` so the screen renders and the drift surfaces in logs rather
than as a render-time crash.

---

### WR-02: `@oneliner_body_limit` comment math is inconsistent with the right-panel inner width

**File:** `lib/foglet_bbs/tui/screens/main_menu.ex:34-39`

**Issue:** The comment claims `"> @" prefix + handle_limit + "  " separator + body_limit = 3+12+2+20=37`
"fits inside the right panel at 64-wide where the panel starts at ~x=27 (27 + 37 = 64 —
exact fit at the narrowest canonical terminal size)". But applying the same
allocation math `nav_panel_inner_width/1` uses for the LEFT panel gives a
right-panel allocation at 64-wide of `(60 * 3) / 5 = 36` outer columns and
inner width `36 - 2 = 34` (subtract the box border). A 37-column row sourced
from the body+handle limits therefore overruns the right-panel inner border by
~3 columns; it stays within the 64-column viewport only because the right
panel's right border coincides with the viewport edge.

The Phase 19 size-contract test at 64×22 only asserts:
1. `element.x + display_width(text) <= width` (viewport bound)
2. `row.x >= oneliners_header.x` (left-edge containment in the right panel)

It does not assert right-edge containment in the right panel. So if the
SplitPane allocator changes (or a future caller pads the panel), the comment's
"exact fit" claim will silently become a real overflow.

**Fix:** Either tighten the comment math to reflect the right-panel inner width
the layout actually produces (right-panel inner ≈ `floor(((w - 4) * 3) / 5) - 2`,
which is 34 at 64-wide, 26 at 80-wide… actually 32 at 80-wide; recompute), or
add a right-edge containment assertion to the size-contract test mirroring the
left-edge one already there:

```elixir
# In test/foglet_bbs/tui/layout_smoke_test.exs, alongside the existing
# `row.x >= oneliners_header.x` containment assertion.

# Compute the right panel's right inner edge from the same allocation math
# the production helper uses (mirror the math; or extract a shared helper).
chrome_outer = 4
left_alloc = div((width - chrome_outer) * 2, 5)
right_alloc = (width - chrome_outer) - left_alloc
right_panel_right_inner = chrome_outer / 2 + left_alloc + right_alloc - 1

for row <- oneliner_rows do
  row_right = row.x + TextWidth.display_width(row.text) - 1

  assert row_right <= right_panel_right_inner,
         "oneliner row overruns right panel inner border at #{inspect({width, height})}: " <>
           "row_right=#{row_right} > right_panel_right_inner=#{right_panel_right_inner}; row=#{inspect(row)}"
end
```

The fix may legitimately be to lower `@oneliner_body_limit` further (e.g. to
17) so a 34-column row fits the actual right-panel inner width at 64-wide.
That is the more conservative correctness fix; the test addition is the
contract that prevents this from regressing.

---

### WR-03: Inner-width allocation math is duplicated between production and tests

**File:** `lib/foglet_bbs/tui/screens/main_menu.ex:282-296` and `test/foglet_bbs/tui/screens/main_menu_test.exs:443-457`

**Issue:** `nav_panel_inner_width/1` computes the panel inner-width budget from
`chrome_outer = 4`, ratio `{2, 3}`, `box_border = 2`, and a floor of
`@nav_panel_min_inner_width = 20`. The "every Navigation row fits within the
computed panel inner width budget" test rederives all four constants inline
("Compute the same budget the production helper computes (mirror the math).").
A future change to either side — narrower outer chrome, different split ratio,
new floor — will silently desync until the test fails for a reason the
contributor will need to triangulate.

**Fix:** Either expose `nav_panel_inner_width/1` (or an internal helper) as a
test-visible function and have the test call it directly, or extract a shared
constants module. Option A is cheaper and idiomatic in Elixir:

```elixir
# main_menu.ex — promote the helper to public for tests; keep @doc false
# so it is not part of the documented API surface.

@doc false
@spec __nav_panel_inner_width__(map()) :: pos_integer()
def __nav_panel_inner_width__(state), do: nav_panel_inner_width(state)

# test — replace the inlined math
inner_width = MainMenu.__nav_panel_inner_width__(state)
```

A double-underscore name makes the testing-only intent clear; alternatively,
move the math to `Foglet.TUI.Screens.MainMenu.Layout` and call from both
sides. The point is to have one source of truth so the test cannot lie about
what the helper computes.

---

## Info

### IN-01: `command_priority/2` clauses for "A", "M", "S" are unreachable

**File:** `lib/foglet_bbs/tui/screens/main_menu.ex:277-280`

**Issue:** `command_priority/2` is only called from `command_group/3`, which
is only called from `visible_actions/1`. `visible_actions/1` filters the
descriptor list to `:action` entries before mapping to the priority builder.
Per `@main_menu_commands` (lines 73-83), the only `:action` entries are `"O"`,
`"H"`, and `"↑/↓"`. The clause `defp command_priority(key, _priority) when key in ["A", "M", "S"]`
can therefore never fire.

This appears to be a leftover from a pre-Phase-19-Plan-01 shape where
destinations and actions shared the command bar; the Phase 19 D-04 split
moved A/M/S out of the command bar entirely (the test
"command bar non-duplication" sweep at line 589 enforces this).

**Fix:** Remove the dead clause. Keep the `"H" -> -10`, `"O" -> 30`, and
catch-all clauses; the resulting function is two lines shorter and matches
the actions actually in `@main_menu_commands`.

---

### IN-02: `command_priority/2`'s `priority` parameter is effectively unused for "H" and "O"

**File:** `lib/foglet_bbs/tui/screens/main_menu.ex:267-280`

**Issue:** `command_group/3` accepts a `priority` argument (`10` for "Actions",
`20` for "Select") and threads it through `command_priority(key, priority)`,
but the per-key clauses for "H" and "O" hardcode their priorities and ignore
the argument. The argument is only consumed by the catch-all clause for
`"↑/↓"`, where the `20` baseline carries through.

The result is functionally correct but the function signature implies
configurability that does not exist for the special cases. A reader
reasonably expects `command_priority("O", 10)` and `command_priority("O", 30)`
to differ; they do not.

**Fix:** Either drop the `priority` parameter and define group priorities as
constants (since only `"↑/↓"` uses the threaded value, that constant is just
`20`), or honor the parameter for "H" and "O" with offsets. The constants
form is simpler:

```elixir
defp command_priority("H"), do: -10
defp command_priority("O"), do: 30
defp command_priority(_key), do: 20  # default for actions in any group
```

And drop the argument from the call site. This is a minor naming/clarity
improvement, not a correctness issue.

---

### IN-03: `visible_destinations/1` builds a state shim that is fragile against future visibility tags

**File:** `lib/foglet_bbs/tui/screens/main_menu.ex:210-219`

**Issue:** `visible_destinations/1` constructs `state = %{current_user: user, recent_oneliners: []}`
to satisfy `command_visible?/3`'s state-aware visibility tags
(`:hide_oneliner_policy`, `:oneliners_present`). Today no destination uses a
state-dependent visibility tag, so the shim is benign. But the shape silently
biases any future state-dependent destination toward the empty case (e.g. a
hypothetical `:has_unread_destinations` tag would always be hidden when
queried via `visible_destinations/1`).

The function comment notes "destination visibility never depends on oneliner
state, so the shim has no oneliners" but this invariant is not enforced —
adding a new state-dependent tag will not produce a compile-time or test-time
warning that `visible_destinations/1` cannot serve it.

**Fix:** Document the invariant more loudly (e.g. enumerate the valid
destination visibility tags in a `@destination_visibility_tags` module attr
and assert at compile time that destinations only use those tags), or split
`command_visible?/3` into `destination_visible?/2` (user-only) and
`action_visible?/3` (state-aware). Splitting the function makes the typing
of state-dependence explicit at the call site and removes the need for the
shim.

---

### IN-04: `clamp/3` shadows `Kernel.max/2` and `Kernel.min/2` via implicit imports

**File:** `lib/foglet_bbs/tui/screens/main_menu.ex:413-417`

**Issue:** `defp clamp(value, min, max)` names its parameters `min` and `max`
and then calls `value |> max(min) |> min(max)`. Inside the function body the
local bindings shadow the `Kernel.max/2` and `Kernel.min/2` functions for any
purposes other than this exact pipe — the pipe works because the first
argument disambiguates it as a function call, but the resulting code reads
ambiguously and is fragile under refactor (e.g. if a future edit adds a
non-pipe call to `max(a, b)`, the shadowing bites).

**Fix:** Either rename the parameters to `lower` and `upper`, or fully-qualify
the Kernel calls:

```elixir
defp clamp(value, lower, upper) do
  value
  |> Kernel.max(lower)
  |> Kernel.min(upper)
end
```

Cosmetic; pure correctness today.

---

### IN-05: `role_label_to_role/1` test helper masks the test's own intent

**File:** `test/foglet_bbs/tui/screens/main_menu_test.exs:426-427`

**Issue:** The "destinations and actions are disjoint" property test at line
608 uses `roles_and_users = [{:anonymous, nil}, ...]`, then calls
`build_state(role_label_to_role(role_label))` which silently maps `:anonymous`
to `:user`. The state is then immediately overwritten with the real user
(`Map.put(:current_user, user)` where `user` is `nil` for the anonymous case),
so the build_state's role choice is meaningless for that branch. The mapping
exists only because `build_state/1` constructs a `%Foglet.Accounts.User{}`
struct that requires a valid role atom even though the result is discarded.

The end-to-end behavior is correct, but a future reader hits the
`role_label_to_role` helper and assumes there is meaning in the `:anonymous` →
`:user` mapping where there is none.

**Fix:** Either inline the workaround with a comment ("build_state needs *some*
valid role to construct the User struct; the result is overwritten with nil
below"), or have `build_state/1` accept `nil` and short-circuit construction:

```elixir
defp build_state(nil) do
  %Foglet.TUI.App{
    current_screen: :main_menu,
    current_user: nil,
    session_context: %{},
    terminal_size: {80, 24}
  }
  |> Map.from_struct()
end

defp build_state(role) when is_atom(role) do
  # existing definition
end
```

Then drop `role_label_to_role/1` and pass `nil` directly in the tuple. Pure
test-readability; no functional change.

---

_Reviewed: 2026-04-25_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
