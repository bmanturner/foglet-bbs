---
phase: 00-screen-shells-and-shared-surface-primitives
reviewed: 2026-04-23T00:00:00Z
depth: standard
files_reviewed: 19
files_reviewed_list:
  - lib/foglet_bbs/tui/app.ex
  - lib/foglet_bbs/tui/screens/account.ex
  - lib/foglet_bbs/tui/screens/account/state.ex
  - lib/foglet_bbs/tui/screens/main_menu.ex
  - lib/foglet_bbs/tui/screens/moderation.ex
  - lib/foglet_bbs/tui/screens/moderation/state.ex
  - lib/foglet_bbs/tui/screens/shared/invites_state.ex
  - lib/foglet_bbs/tui/screens/shared/invites_surface.ex
  - lib/foglet_bbs/tui/screens/shell_visibility.ex
  - lib/foglet_bbs/tui/screens/sysop.ex
  - lib/foglet_bbs/tui/screens/sysop/state.ex
  - test/foglet_bbs/tui/app_test.exs
  - test/foglet_bbs/tui/layout_smoke_test.exs
  - test/foglet_bbs/tui/screens/account_test.exs
  - test/foglet_bbs/tui/screens/main_menu_test.exs
  - test/foglet_bbs/tui/screens/moderation_test.exs
  - test/foglet_bbs/tui/screens/shared/invites_surface_test.exs
  - test/foglet_bbs/tui/screens/shell_visibility_test.exs
  - test/foglet_bbs/tui/screens/sysop_test.exs
  - .dialyzer_ignore.exs
findings:
  critical: 0
  warning: 3
  info: 6
  total: 9
status: issues_found
---

# Phase 0: Code Review Report

**Reviewed:** 2026-04-23
**Depth:** standard
**Files Reviewed:** 19
**Status:** issues_found

## Summary

Phase 0 delivers read-only shell screens (Account, Moderation, Sysop) and shared
surface primitives (InvitesSurface, ShellVisibility, InvitesState). The code is
well-structured, cleanly separated, and the Phase 0 scope boundary (no Repo/domain
I/O, no fake save/generate/revoke/ban affordances) is upheld — tests enforce this
via `refute` lists against forbidden strings and commands.

Key positives:

- **Role gating is centralized** in `ShellVisibility`, consumed by both MainMenu
  (entry) and Account/Moderation/Sysop (defensive re-checks). This mitigates
  Pitfall 3 drift cleanly.
- **No `String.to_atom/1` misuse** — user input is not coerced to atoms anywhere
  in the reviewed files. No atom-exhaustion vectors.
- **No `struct[:field]` Access-protocol misuse** on Elixir structs. User maps are
  pattern-matched (`%{role: :sysop}`) and struct access uses dot-notation.
- **No Repo / Ecto schema I/O** from shell modules (T-00-01 respected).
- **No hardcoded secrets / dangerous functions / debug artifacts** in the scope.

The findings below are primarily correctness nits and maintainability observations.
None are security-critical for Phase 0 given its explicitly read-only scope.

## Warnings

### WR-01: Moderation.handle_key drops tab-widget state when action is nil

**File:** `lib/foglet_bbs/tui/screens/moderation.ex:75-92`

**Issue:** When the Tabs widget consumes an event but the active index does
not change (e.g. pressing digit `"1"` while already on tab 0, or `:right` at
the last tab in a non-wrapping mode), `Tabs.handle_event/2` may return
`{new_tabs, nil}` where `new_tabs` differs from `ss.tabs` (e.g. `last_action`
bookkeeping). The Moderation handler returns `:no_match` in that case,
silently discarding `new_tabs`. Compare with the Account screen
(`lib/foglet_bbs/tui/screens/account.ex:86-92`), which guards with
`action == nil and new_tabs == ss.tabs` — only treating the event as
unhandled when the widget state is also unchanged.

This is not catastrophic: `Tabs.t()`'s `:last_action` field is only a
debugging convenience, so the drift is invisible today. But it introduces
an asymmetry with Account/Sysop that will bite if widget internals gain
other persisted state (focus history, animation counters, etc.). It also
means a test that inspects `ss.tabs.last_action` after a no-op digit press
would see stale data on Moderation but fresh data on Account.

**Fix:**

```elixir
def handle_key(event, state) do
  ss = get_screen_state(state)
  {new_tabs, action} = Tabs.handle_event(event, ss.tabs)

  cond do
    action == nil and new_tabs == ss.tabs ->
      :no_match

    true ->
      new_active =
        case action do
          {:tab_changed, idx} -> idx
          _ -> ss.active_tab
        end

      new_ss = %{ss | tabs: new_tabs, active_tab: new_active}
      new_screen_state = Map.put(Map.get(state, :screen_state) || %{}, :moderation, new_ss)
      {:update, %{state | screen_state: new_screen_state}, []}
  end
end
```

---

### WR-02: Moderation render bypasses Tabs.render/2 — the Tabs widget becomes decorative

**File:** `lib/foglet_bbs/tui/screens/moderation.ex:125-138`

**Issue:** `render_tabs_bar/2` re-implements the tab bar inline
(`Enum.map_join(" | ", …)`) instead of calling `Tabs.render/2`. The module
docstring (lines 120-124) acknowledges this is deliberate — to keep the
`collect_text_values/1` test helper happy — but the consequence is that
`ss.tabs` is held in state, mutated by `handle_event/2`, and never actually
rendered. All visual styling decisions (selected colors, indicators, border
theming) are now duplicated across Account (which uses `Tabs.render`) and
Moderation (which doesn't).

Downstream: if Theme changes the `selected` / `unselected` semantics or the
`active_indicator`, Account updates automatically and Moderation drifts.
The Sysop screen has the same issue but at least uses its own themed
helper function (`render_tab_bar/2`, lines 93-124).

The rendering pattern was chosen to satisfy a test traversal order
(ascending-position assertions in `moderation_test.exs:77-93`). That test
convenience is now structurally embedded in production rendering code.

**Fix:** Prefer fixing the test — update `collect_text_values/1` to preserve
traversal order (reverse at the end, or use `:lists.reverse(acc)` on return)
so render code doesn't have to accommodate prepend-accumulation ordering.
Then replace both Moderation's `render_tabs_bar/2` and Sysop's
`render_tab_bar/2` with calls to `Tabs.render(ss.tabs, theme: theme)`.

```elixir
# Test helper (three places: account_test, moderation_test, sysop_test,
# main_menu_test, invites_surface_test) should end with:
defp collect_text_values(nodes, acc) when is_list(nodes) do
  Enum.reduce(nodes, acc, fn node, text_acc ->
    collect_text_values(node, text_acc)
  end)
  |> :lists.reverse()     # <-- restore DFS order
end

# Then in Moderation.render_content/2:
defp render_content(ss, theme) do
  column style: %{gap: 0} do
    [Tabs.render(ss.tabs, theme: theme), render_tab_body(ss.active_tab, theme)]
  end
end
```

If preserving the reverse-accumulation helper is intentional, at minimum
leave a `# TEST-HELPER-HACK` comment on the render functions and bind the
reversed-label list to a named constant so the "why" is discoverable
without reading the module docstring.

---

### WR-03: Sysop.handle_key classifies wrap-around as :no_match — relies on undocumented Tabs behavior

**File:** `lib/foglet_bbs/tui/screens/sysop.ex:153-188`

**Issue:** `no_match?/5` infers that a "wrap-around" happened by observing
that `before_idx == tab_count - 1` and `after_idx == 0` for `:right`, or
the inverse for `:left`. This relies on the Tabs widget choosing to wrap
(a behavior your `Tabs` wrapper doesn't document — `Tabs.handle_event/2`
just forwards to `RaxolTabs.handle_event/3` and derives `:tab_changed`
purely from an index change). If Raxol's underlying tabs widget ever
switches to clamping (no wrap) or wraps at a different boundary, this
heuristic will either:

1. Silently drop a legitimate tab change as `:no_match` (false negative), or
2. Misclassify a 0→4 jump (e.g. from a digit key "5") as wrap-around when
   the user was actually at tab 0.

Scenario 2 is partially guarded by the `is_arrow` check (`event[:key] in
[:left, :right]`), but the behavior is still surprising. The test at
`sysop_test.exs:113-148` only exercises clamp-at-the-end — it does not
verify the wrap path or the no_match path for arrow keys at boundaries.

Additionally, `Map.get(ss.tabs.raxol_state, :active_index, ...)` reaches
into a field of the Raxol-owned state struct. That's an abstraction leak:
if Raxol renames `:active_index` or changes the struct shape, this breaks
silently (returns the fallback) rather than surfacing a compile error.

**Fix:** Expose a proper `Tabs.active_index/1` accessor and a `:no_op`
action returned when the widget is at a boundary so screens don't have to
infer it. Short term — since Account's approach (check `action == nil and
new_tabs == ss.tabs`) is both simpler and widget-internals-agnostic —
refactor Sysop to match Account:

```elixir
def handle_key(event, state) do
  ss = get_screen_state(state)
  {new_tabs, action} = Tabs.handle_event(event, ss.tabs)

  new_active =
    case action do
      {:tab_changed, idx} -> idx
      _ -> ss.active_tab
    end

  if action == nil and new_tabs == ss.tabs do
    :no_match
  else
    new_ss = %{ss | tabs: new_tabs, active_tab: new_active}
    new_screen_state = Map.put(state.screen_state, :sysop, new_ss)
    {:update, %{state | screen_state: new_screen_state}, []}
  end
end
```

This removes `no_match?/5`, `extract_active/2`, and the
`raxol_state.active_index` probe entirely. The trade-off: arrow-at-boundary
events become `{:update, state, []}` (idempotent mutation, identical state
returned) instead of `:no_match`. That's usually fine — `App.update/2`
would accept either, and idempotent updates are easier to reason about than
"widget consumed the key but we're lying about it."

If the wrap detection is load-bearing for some MainMenu-level behavior,
document that requirement in the Sysop moduledoc with an ADR reference.

## Info

### IN-01: Account.render/1 double-computes invites visibility

**File:** `lib/foglet_bbs/tui/screens/account.ex:49-53, 97-102, 104-112`

**Issue:** `render/1` calls `ShellVisibility.invites_visible?/2` directly,
and `get_screen_state/1` → `init_opts_from_state/1` calls it a second time
to seed `init_screen_state`. On first render both are called; on subsequent
renders `get_screen_state/1` short-circuits to the cached state but the
outer `invites?` call keeps firing every paint. Not performance-relevant
(the predicate is pattern-match-only and never hits I/O per
`ShellVisibility.resolve_policy/1`'s rescue/catch), but it's a clarity nit
— two sources of truth for the same UI decision within one render pass.

**Fix:** Compute once and thread through:

```elixir
def render(state) do
  ss = get_screen_state(state)
  theme = Theme.from_state(state)
  # Read from ss.tabs.tabs count or State.tab_labels count — a single
  # source of truth established at init_screen_state time.
  labels = ss.tabs |> ...tab_labels(...)   # whichever accessor exists
  ...
end
```

Or keep the current structure and add a comment noting the `init_opts_from_state`
branch only fires on the first render (when `get_in(state.screen_state,
[:account])` is nil), so the duplicate call is bounded.

### IN-02: Account.init_screen_state stores invites_visible? at construction time — stale if role changes

**File:** `lib/foglet_bbs/tui/screens/account/state.ex:39-48` and
`lib/foglet_bbs/tui/screens/account.ex:104-112`

**Issue:** The INVITES tab's presence is decided once when
`init_screen_state` is called (via the `invites_visible?` option) and baked
into the `Tabs` widget's tab list. If the user's role or the invite policy
changes while the Account screen is open (e.g. sysop applies a policy
change that affects this session), the tab set stays frozen until
`init_screen_state` is re-called.

Phase 0 does not mutate role or policy mid-session — but the pattern is
brittle. Note that `render/1` correctly recomputes `invites?` and
`active_label` each frame, so the *body* would render the new INVITES
content if the tab were present. It just wouldn't appear in the tab bar.

**Fix:** Either document the design invariant ("role/policy are considered
immutable for the lifetime of a screen_state") or rebuild the Tabs widget
from `tab_labels(invites?)` each render when the visibility changes. The
first option is simpler for Phase 0.

### IN-03: ShellVisibility.resolve_policy/1 silently swallows config errors

**File:** `lib/foglet_bbs/tui/screens/shell_visibility.ex:86-92`

**Issue:** `config_policy_or_nil/0` rescues all exceptions and catches all
exits from `Foglet.Config.invite_code_generators/0`. On failure the policy
becomes `nil` — which hides the invite tab from non-sysops (the safe
default). But no logging, no telemetry, no breadcrumb. If the ETS cache is
cold because of a deployment ordering bug, users silently lose the INVITES
tab with zero operator signal.

**Fix:** Log a warning (once per process, to avoid flood) when the config
read fails:

```elixir
defp config_policy_or_nil do
  Foglet.Config.invite_code_generators()
rescue
  e ->
    require Logger
    Logger.warning(
      "[ShellVisibility] invite_code_generators config read failed: " <>
        Exception.message(e) <> " — defaulting policy to nil"
    )
    nil
catch
  :exit, reason ->
    require Logger
    Logger.warning("[ShellVisibility] invite_code_generators exited: #{inspect(reason)}")
    nil
end
```

### IN-04: InvitesSurface.render/2 reads system time on every render — non-deterministic tests

**File:** `lib/foglet_bbs/tui/screens/shared/invites_surface.ex:49-50`

**Issue:** `render_loading/1` computes
`System.monotonic_time(:millisecond) |> abs() |> div(Spinner.frame_duration_ms())`
each call. This is correct for spinner animation but makes the render
function non-referentially-transparent. Tests that compare two render
outputs may flake depending on timing. Today the test at
`invites_surface_test.exs:112-118` only checks for the string "Loading",
so it's safe — but future snapshot tests would trip.

**Fix:** Accept an explicit frame counter via the state so the caller owns
time:

```elixir
def render(%{items: nil, frame: frame}, %Theme{} = theme), do: render_loading(frame, theme)
def render(%{items: nil}, %Theme{} = theme), do: render_loading(0, theme)

defp render_loading(frame, theme) do
  spinner_el = Spinner.render(frame, style: :line, theme: theme)
  ...
end
```

Subsequent phases that animate the spinner can tick `frame` via a
`subscribe_interval` message.

### IN-05: InvitesState @type declares items as list or nil, but validate_items!/1 accepts anything list-shaped

**File:** `lib/foglet_bbs/tui/screens/shared/invites_state.ex:18-34`

**Issue:** `@type t :: %__MODULE__{items: list() | nil}`. The validator
rejects non-list non-nil inputs, but it doesn't assert the list element
shape. Phase 0 never looks inside items, but once Phase 4 activates
persistence this will silently accept a list of arbitrary garbage. Not a
Phase 0 bug — just a structural hand-off note for Phase 4.

**Fix:** Add a TODO marker at the typespec:

```elixir
# TODO(phase-4): tighten :items to [%Foglet.Invites.Invite{}] and add
# per-element validation in validate_items!/1.
@type t :: %__MODULE__{items: list() | nil}
```

### IN-06: Multiple test files duplicate the collect_text_values/2 helper

**Files:**
- `test/foglet_bbs/tui/screens/account_test.exs:22-47`
- `test/foglet_bbs/tui/screens/main_menu_test.exs:20-45`
- `test/foglet_bbs/tui/screens/moderation_test.exs:21-46`
- `test/foglet_bbs/tui/screens/sysop_test.exs:21-46`
- `test/foglet_bbs/tui/screens/shared/invites_surface_test.exs:11-36`

**Issue:** The same ~25-line `collect_text_values/1` helper is copy-pasted
across five test modules. When a refactor is needed (see WR-02 where
fixing the test helper would unblock Moderation/Sysop from using
`Tabs.render/2`), five files have to change in lockstep.

**Fix:** Extract to `test/support/tui_render_helpers.ex` (or wherever
Foglet keeps its test support modules) and `import` into each test. Also
take the opportunity to change it to preserve DFS order (`:lists.reverse`
on return) so production rendering code no longer has to list children in
reverse to satisfy the traversal order.

---

_Reviewed: 2026-04-23_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
