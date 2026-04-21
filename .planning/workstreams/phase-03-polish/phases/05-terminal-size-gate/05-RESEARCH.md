# Phase 5: Terminal size gate — Research

**Researched:** 2026-04-20
**Confidence:** HIGH
**Scope:** Technical verification of the decisions locked in `05-CONTEXT.md`. Confirms exact call sites, Raxol DSL shape for the centered message, theme-slot plumbing, and regression-test approach for MultiLineInput preservation across resize. Phase 5 has no new dependencies — every callee exists.

---

## 1. Executive Summary

Phase 5 is a **three-touch render-time gate** phase:

1. A predicate + constants (`too_small?/1`, `@min_cols`, `@min_rows`) — new code.
2. A branch in `App.view/1` that short-circuits `render_screen/1` and `render_modal_overlay/2` when gated — one insert.
3. A same-size guard in `do_update({:window_change, ...})` — two-line edit at `app.ex:247-255`.
4. A key-swallow guard in `do_update({:key, ...})` — one insert at `app.ex:303`.

Zero new dependencies, zero schema changes, zero new subsystems. All of `state.terminal_size`, `state.session_context.theme`, the Raxol DSL (`column`, `row`, `text`), and the `Theme.dim` slot are live today.

The dominant risk per research Pitfall 4 is state loss: the gate must NEVER clear `screen_state`, `current_screen`, `composer_draft`, or `screen_state[:post_composer].input_state` / `screen_state[:new_thread].body_input_state`. The CONTEXT-locked approach (render-time branch, not a screen transition) structurally avoids this — the gate reads state but never writes it.

The secondary risk is key leakage during gated state. Without the `App.update/2` guard, a user hammering keys on the hidden `:post_reader` screen could scroll `selected_post_index` or change `read_position` silently. The guard blocks `{:key, _}` at the dispatcher entry; resize events (`{:window_change, ...}`) and runtime/domain messages (`{:posts_loaded, _}`, `:heartbeat_tick`, etc.) flow through unchanged.

### Architectural Responsibility Map

| Layer | Owns | Touches in Phase 5 |
|-------|------|-----|
| `Foglet.TUI.App` | Top-level model, view routing, update dispatch | `view/1` (add gate branch), `do_update({:window_change, ...})` (same-size guard), `do_update({:key, ...})` (swallow when gated) |
| `Foglet.TUI.SizeGate` (new module) | Gate predicate + render + constants | NEW: `@min_cols`, `@min_rows`, `too_small?/1`, `render/1` |
| `Foglet.TUI.Theme` | Theme slots (dim, border, etc.) | READ-ONLY: gate reads `theme.dim` |
| `Foglet.TUI.Widgets.Chrome.ScreenFrame` | Outer chrome | UNTOUCHED — gate bypasses |
| `Foglet.Sessions.Session` | Terminal size tracking | UNTOUCHED — set_terminal_size stays idempotent |
| `Foglet.SSH.CLIHandler` | Alt-screen takeover, SIGWINCH plumbing | UNTOUCHED |

The gate lives entirely in `App.view/1` + `App.update/2` + a new `SizeGate` module. No other file changes.

---

## 2. Signature Verification (all confirmed)

| Call / Field | Source | Shape | Used by Phase 5 |
|------|--------|-------|-----------------|
| `state.terminal_size` | `lib/foglet_bbs/tui/app.ex:42,61` | `{pos_integer(), pos_integer()}` — defaults `{80, 24}` | Gate predicate reads this |
| `state.session_context.theme` | `lib/foglet_bbs/tui/app.ex:40` (via `session_context` map) | `Foglet.TUI.Theme.t()` or nil | Gate reads `theme.dim.fg` for message color |
| `Foglet.TUI.Theme.default/0` | `lib/foglet_bbs/tui/theme.ex` | `() :: Foglet.TUI.Theme.t()` | Fallback when `session_context.theme` absent (same pattern as StatusBar/ScreenFrame) |
| `theme.dim` | `Foglet.TUI.Theme` struct, `dim: %{fg: ...}` slot | `%{fg: String.t()}` | Gate message color |
| `Raxol.Core.Renderer.View.column/2` | imported via `import Raxol.Core.Renderer.View` | `column(style_opts_keyword_list, do: children)` | Outer centering container |
| `Raxol.Core.Renderer.View.row/2` | same module | `row(style_opts, do: children)` | Horizontal centering row |
| `Raxol.Core.Renderer.View.text/2` | same module | `text(String.t(), keyword())` — accepts `fg:`, `bg:`, `style:` | Each message line |
| `App.do_update({:window_change, cols, rows}, state)` | `lib/foglet_bbs/tui/app.ex:247-255` | Already updates terminal_size + notifies Session | Add same-size short-circuit at top |
| `App.do_update({:key, key_event}, state)` | `lib/foglet_bbs/tui/app.ex:303-326` | Dispatches to screen or global_key_handler | Add gate check at entry; return `{state, []}` when gated |
| `App.view/1` | `lib/foglet_bbs/tui/app.ex:146-153` | Currently branches on `state.modal` | Add outer branch on `SizeGate.too_small?/1` |

**Nothing changes signature-wise.** All insertions are additive.

---

## 3. Call-Site Map (exact file + line)

### 3.1 `Foglet.TUI.SizeGate` (NEW module)

File: `lib/foglet_bbs/tui/size_gate.ex`

Contract:

```elixir
defmodule Foglet.TUI.SizeGate do
  @moduledoc "..."
  import Raxol.Core.Renderer.View
  alias Foglet.TUI.Theme

  @min_cols 64
  @min_rows 22
  @user_facing_min_cols 60
  @user_facing_min_rows 20

  @spec min_cols() :: pos_integer()
  def min_cols, do: @min_cols

  @spec min_rows() :: pos_integer()
  def min_rows, do: @min_rows

  @spec too_small?(map()) :: boolean()
  def too_small?(%{terminal_size: {cols, rows}}) when is_integer(cols) and is_integer(rows),
    do: cols < @min_cols or rows < @min_rows
  def too_small?(_state), do: false

  @spec render(map()) :: any()
  def render(state) do
    theme = (Map.get(state, :session_context) || %{}) |> Map.get(:theme) || Theme.default()
    fg = Map.get(theme.dim, :fg)
    {cols, rows} = Map.get(state, :terminal_size) || {0, 0}

    column style: %{justify_content: :center, align_items: :center} do
      [
        text("Terminal too small.", fg: fg),
        text("Foglet BBS requires at least #{@user_facing_min_cols}×#{@user_facing_min_rows}.", fg: fg),
        text("Your terminal is currently: #{cols}×#{rows}.", fg: fg),
        text("Please resize.", fg: fg)
      ]
    end
  end
end
```

**Constants — D-02, D-13:**
- `@min_cols 64` and `@min_rows 22` — code-level strict-inequality threshold.
- `@user_facing_min_cols 60` and `@user_facing_min_rows 20` — user-facing mental minimum shown in the message copy (D-07). Separate from `@min_cols`/`@min_rows` because chrome overhead accounts for the 4-col/2-row delta.

**Predicate — D-06:** Takes state (match on `%{terminal_size: {cols, rows}}` pattern). Falsy / missing → default to `false` (not gated) — safer failure mode if terminal_size goes nil for any reason.

**Renderer — D-04, D-07, D-08:** Four `text/2` calls inside a single `column` with `justify_content: :center` and `align_items: :center`. Raxol centers content in both axes when the parent occupies the full terminal. No outer border (matches D-04: "No outer border, no StatusBar, no KeyBar on the too-small screen").

**Theme fallback:** Uses the same pattern as `StatusBar.render/2` and `ScreenFrame.render/4` (`lib/foglet_bbs/tui/widgets/chrome/status_bar.ex:37` and `screen_frame.ex:34`): `(Map.get(state, :session_context) || %{}) |> Map.get(:theme) || Theme.default()`. Matches the established code style.

### 3.2 `App.view/1` — add gate branch (D-04, D-05)

File: `lib/foglet_bbs/tui/app.ex:146-153`

**Current:**
```elixir
@impl true
def view(state) do
  if state.modal do
    render_modal_overlay(state.modal, state.terminal_size)
  else
    render_screen(state)
  end
end
```

**Target:**
```elixir
@impl true
def view(state) do
  cond do
    SizeGate.too_small?(state) -> SizeGate.render(state)
    state.modal -> render_modal_overlay(state.modal, state.terminal_size)
    true -> render_screen(state)
  end
end
```

**Ordering justification:** The gate runs BEFORE the modal check. If the terminal shrinks while a modal is open, the user sees the too-small message (not a half-rendered modal); when they resize back, the modal re-appears because the gate never touched `state.modal`. This matches CONTEXT "gated state means no modal either — planner choice on exact ordering" (D-04 note).

Add `alias Foglet.TUI.SizeGate` near the existing aliases (line 20-24) — no other import changes.

### 3.3 `App.do_update({:window_change, ...})` — same-size guard (D-09)

File: `lib/foglet_bbs/tui/app.ex:247-255`

**Current:**
```elixir
defp do_update({:window_change, cols, rows}, state)
     when is_integer(cols) and is_integer(rows) and cols > 0 and rows > 0 do
  # SSH-06: terminal resize — also notify Session for presence/analytics.
  if is_pid(state.session_pid) do
    Foglet.Sessions.Session.set_terminal_size(state.session_pid, {cols, rows})
  end

  {%{state | terminal_size: {cols, rows}}, []}
end
```

**Target:**
```elixir
defp do_update({:window_change, cols, rows}, state)
     when is_integer(cols) and is_integer(rows) and cols > 0 and rows > 0 do
  # D-09: same-size guard — short-circuit bursty SIGWINCH events at the same
  # terminal size to avoid render storms during tmux/iTerm drags.
  if state.terminal_size == {cols, rows} do
    {state, []}
  else
    # SSH-06: terminal resize — also notify Session for presence/analytics.
    if is_pid(state.session_pid) do
      Foglet.Sessions.Session.set_terminal_size(state.session_pid, {cols, rows})
    end

    {%{state | terminal_size: {cols, rows}}, []}
  end
end
```

### 3.4 `App.do_update({:key, ...})` — swallow keys when gated (D-11, D-12)

File: `lib/foglet_bbs/tui/app.ex:303-326`

**Current head:**
```elixir
defp do_update({:key, key_event}, state) do
  if state.modal != nil do
    global_key_handler(key_event, state)
  else
    screen_module = screen_module_for(state.current_screen)
    ...
  end
end
```

**Target head:**
```elixir
defp do_update({:key, key_event}, state) do
  cond do
    SizeGate.too_small?(state) ->
      # D-11: swallow keys entirely when gated — screens behind the gate
      # must not mutate their own state silently. Ctrl+C / EOF reach
      # CLIHandler at the SSH channel layer independently (D-12).
      {state, []}

    state.modal != nil ->
      global_key_handler(key_event, state)

    true ->
      screen_module = screen_module_for(state.current_screen)
      case screen_module.handle_key(key_event, state) do
        ...
      end
  end
end
```

Order: gate → modal → screen dispatch. This matches `view/1`'s ordering and keeps the two dispatchers consistent.

**What flows through:** `{:window_change, _, _}`, `{:subscription, _}`, `:heartbeat_tick`, `{:posts_loaded, _}`, `{:boards_loaded, _}`, and every other non-`:key` message — these hit their own `do_update/2` clauses, not this one. The gate ONLY blocks keyboard input.

### 3.5 Reverse wiring sanity (no other changes needed)

| Concern | Status | Evidence |
|---|---|---|
| Alt-screen exit paths | Already hardened | `cli_handler.ex:196, 203` — do not touch (CONTEXT "Do NOT Touch") |
| Composer draft preservation across resize | Structurally preserved | Gate never writes state; `screen_state[:post_composer]` and `screen_state[:new_thread]` remain untouched through resize cycles |
| `MultiLineInput` rebuilt from width on resize | NOT triggered today | `composer_screen_state/1` at `post_composer.ex:166-180` only runs on screen entry (init); resize does not flow into it. Research Pitfall 4 confirms. Regression test added in Plan 02 to lock this in. |
| Session.set_terminal_size cast | Stays idempotent | Same-size guard short-circuits BEFORE the cast, reducing GenServer load |

---

## 4. Raxol DSL Validation: centered multi-line text

**The question (CONTEXT "Claude's Discretion"):** Does `text/2` support embedded newlines, or must each line be a separate `text/2` call?

**Finding (from Raxol 2.4.0 vendored `raxol/core/renderer/view.ex`):** `text/2` treats the input as a single-line string and does NOT split on `\n`. Embedded `\n` renders as a literal character (or is stripped). The correct shape is **one `text/2` per line inside a `column`**.

Precedent in this repo: `Foglet.TUI.Widgets.Modal` and the login screen both use multiple `text/2` children inside a `column` for multi-line content. Matches the CONTEXT "planner decides the exact Raxol element shape" guidance.

**Centering behavior:** A top-level `column` with `justify_content: :center` and `align_items: :center` centers its children both vertically (column's main axis) and horizontally (column's cross axis) within the container. Raxol fills the container to the full terminal by default when given no sizing constraints.

If centering misbehaves empirically at execution time (Raxol version quirks), the fallback is to wrap the children in a `row style: %{justify_content: :center}` for horizontal centering and use a top `column style: %{justify_content: :center}` for vertical — a double container. Plan 01 should write the single-`column` version first and fall back to the double-container form only if visual verification flags drift.

---

## 5. Test Strategy

### 5.1 Gate behavior tests (new file: `test/foglet_bbs/tui/size_gate_test.exs`)

Direct unit tests for the predicate and the renderer output structure:

```elixir
defmodule Foglet.TUI.SizeGateTest do
  use ExUnit.Case, async: true
  alias Foglet.TUI.SizeGate

  describe "too_small?/1" do
    test "returns true when cols < 64"
    test "returns true when rows < 22"
    test "returns true when both dims below"
    test "returns false at exactly 64×22"  # D-13 strict inequality
    test "returns false at 80×24 (common default)"
    test "returns false when terminal_size is missing"  # safety fallback
  end

  describe "render/1" do
    test "returns a column element with justify_content: :center"
    test "contains the required message lines"
    test "interpolates current dimensions from state.terminal_size"
    test "uses theme.dim.fg when session_context has a theme"
    test "falls back to Theme.default() when session_context is empty"
  end

  describe "min_cols/0 and min_rows/0" do
    test "are 64 and 22 respectively"
  end
end
```

### 5.2 Integration tests (add to `test/foglet_bbs/tui/app_test.exs`)

Extends the existing `describe "view/1 routing"` and `describe "update/2"` blocks:

```elixir
describe "view/1 size gate (FRAME-03)" do
  test "renders SizeGate output when cols < 64" do
    {:ok, state} = App.init(%{terminal_size: {40, 30}})
    element = App.view(state)
    # Assert element shape matches SizeGate.render output (column + text leaves)
  end

  test "renders SizeGate output when rows < 22" do
    {:ok, state} = App.init(%{terminal_size: {80, 10}})
    element = App.view(state)
    # Assert gate rendering, not normal screen
  end

  test "renders normal screen at exactly 64×22 (strict inequality)" do
    {:ok, state} = App.init(%{terminal_size: {64, 22}})
    element = App.view(state)
    # Assert element is not the gate output
  end

  test "gate takes precedence over modal" do
    {:ok, state} = App.init(%{terminal_size: {40, 10}})
    {with_modal, _} = App.update({:show_modal, %{type: :info, message: "hi"}}, state)
    element = App.view(with_modal)
    # Assert gate rendering, not modal overlay
  end
end

describe "update/2 {:window_change} same-size guard (D-09)" do
  test "short-circuits when cols/rows match state.terminal_size" do
    {:ok, state} = App.init(%{terminal_size: {100, 30}})
    {new_state, cmds} = App.update({:window_change, 100, 30}, state)
    assert new_state == state  # identity — no mutation
    assert cmds == []
  end

  test "updates terminal_size and notifies Session when size differs" do
    {:ok, state} = App.init(%{terminal_size: {80, 24}, session_context: %{session_pid: self()}})
    {new_state, cmds} = App.update({:window_change, 120, 40}, %{state | session_pid: self()})
    assert new_state.terminal_size == {120, 40}
  end
end

describe "update/2 {:key} gate swallow (D-11)" do
  test "swallows {:key, _} when too_small?" do
    {:ok, state} = App.init(%{terminal_size: {40, 10}})
    {new_state, cmds} = App.update({:key, %{key: :char, char: "q"}}, state)
    assert new_state == state  # state must not mutate
    assert cmds == []
  end

  test "still dispatches {:key, _} normally above threshold" do
    {:ok, state} = App.init(%{terminal_size: {80, 24}})
    # Q on login screen normally emits Command.quit
    {_new_state, cmds} = App.update({:key, %{key: :char, char: "Q"}}, state)
    assert [%Raxol.Core.Runtime.Command{type: :quit}] = cmds
  end

  test "{:window_change, _, _} reaches the normal handler when gated" do
    {:ok, state} = App.init(%{terminal_size: {40, 10}})
    # Resize OUT of the gate — this must still process
    {new_state, _} = App.update({:window_change, 100, 30}, state)
    assert new_state.terminal_size == {100, 30}
  end
end
```

### 5.3 Regression test for MultiLineInput preservation (CONTEXT "Claude's Discretion")

Add to `test/foglet_bbs/tui/app_test.exs` (or a new `post_composer_resize_test.exs` if more readable):

```elixir
describe "composer draft preservation across resize gate cycles (Pitfall 4)" do
  test "post_composer input_state.value survives resize down → up → down" do
    {:ok, state} = App.init(%{terminal_size: {100, 30}})
    # Simulate opening the post composer with a reply in progress
    state_with_composer = %{state |
      current_screen: :post_composer,
      screen_state: %{post_composer: %{
        mode: :compose,
        input_state: %{value: "draft-in-progress", cursor_pos: 17}
      }}
    }

    # Resize below threshold → gate engages → keys swallowed
    {gated, _} = App.update({:window_change, 40, 10}, state_with_composer)
    {key_noop, _} = App.update({:key, %{key: :char, char: "x"}}, gated)
    # Composer input is untouched — gate swallowed the key
    assert key_noop.screen_state.post_composer.input_state.value == "draft-in-progress"

    # Resize back up → gate releases, screen returns
    {released, _} = App.update({:window_change, 100, 30}, key_noop)
    assert released.current_screen == :post_composer
    assert released.screen_state.post_composer.input_state.value == "draft-in-progress"
  end

  test "new_thread body_input_state.value survives the same cycle" do
    # Mirror of above but for :new_thread screen_state[:new_thread].body_input_state
  end
end
```

This test is critical per CONTEXT's "Claude's Discretion" note: it locks in the state-preservation guarantee against any future regression that would re-initialize `MultiLineInput` from width.

---

## Validation Architecture

### Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit (Elixir stdlib) |
| **Config** | `test/test_helper.exs` (exists) |
| **Quick run** | `mix test test/foglet_bbs/tui/size_gate_test.exs test/foglet_bbs/tui/app_test.exs` |
| **Full suite** | `mix precommit` (alias — runs `mix test` + `mix format --check-formatted` + `mix credo` + `mix compile --warnings-as-errors`) |
| **Estimated runtime** | ~15s for targeted, ~60s for full |

### Per-Task Verification Map (preview)

| Task | Requirement | Test | Automated Command |
|------|-------------|------|-------------------|
| SizeGate module | FRAME-03 | `size_gate_test.exs` | `mix test test/foglet_bbs/tui/size_gate_test.exs` |
| View gate branch | FRAME-03 | `app_test.exs describe "view/1 size gate"` | `mix test test/foglet_bbs/tui/app_test.exs -k "size gate"` |
| Same-size guard | FRAME-03 | `app_test.exs describe "same-size guard"` | `mix test test/foglet_bbs/tui/app_test.exs -k "same-size"` |
| Key swallow | FRAME-03 | `app_test.exs describe "gate swallow"` | `mix test test/foglet_bbs/tui/app_test.exs -k "swallow"` |
| MultiLineInput preservation | FRAME-03 + Pitfall 4 | `app_test.exs describe "draft preservation"` | `mix test test/foglet_bbs/tui/app_test.exs -k "draft preservation"` |

### Manual Verification (cannot automate)

- SSH into the BBS, open an iTerm pane, drag to resize below 60 cols wide.
  - Expected: four-line centered "terminal too small" message with current dims.
  - No border, no status bar, no key bar.
  - No flicker during the drag.
- Start typing in the composer, drag to below threshold mid-keystroke, drag back.
  - Expected: draft intact.

---

## 6. Risk Areas and Planning Guardrails

### 6.1 Centering may not auto-fill on Raxol

Raxol's `column` with no explicit `width` / `height` may not expand to fill the terminal. If so, the gate message appears in the top-left rather than centered. **Mitigation:** if Plan 01 verification shows off-center output, change the wrapper to `column style: %{width: :fill, height: :fill, justify_content: :center, align_items: :center}`. The CONTEXT explicitly says "planner's choice of `column` + `row` with `justify_content: :center` or a simple centered `text/2`" — planner has discretion to choose the one that works empirically.

### 6.2 Theme snapshot may be missing in edge cases

In the `:login` screen before `session_context.theme` is set, `theme` can be nil. The research references `Theme.default()` as fallback — matches `StatusBar` and `ScreenFrame`. The plan MUST use this fallback pattern exactly; hard-coding a color breaks theme consistency.

### 6.3 `too_small?/1` is called on every render

It must be O(1). The implementation (pattern-match + two integer comparisons) is trivially O(1). No risk.

### 6.4 Raxol's `{:window_change, 0, 0}` pathological case

Never observed, but CLIHandler / PTY glitches could theoretically emit zero dims. The existing guard `cols > 0 and rows > 0` at `app.ex:248` already rejects these — the function head falls through to the catch-all `do_update(_other, state) -> {state, []}` at `app.ex:537`. No action needed in Phase 5.

### 6.5 Multiple message handlers competing with the key swallow

`do_update({:key, _}, state)` is ONE clause among 20+ `do_update` heads. Adding a gate branch inside this clause does NOT affect `{:subscription, _}`, `{:boards_loaded, _}`, `:heartbeat_tick`, `{:promote_session, _}`, etc. Those have their own clauses and fire independently. The plan must only touch the `{:key, _}` head.

---

## 7. Out-of-Scope Confirmations (from CONTEXT)

- Graceful compact layouts — **OUT**. One threshold, one message.
- Per-screen thresholds — **OUT**. Global.
- Time-based debounce — **OUT**. Same-size guard is sufficient; Raxol coalesces.
- Hysteresis — **OUT**. Same-size guard catches the common case.
- Alt-screen handling — **OUT**. Already hardened in `cli_handler.ex:196, 203`.
- Sysop-configurable min dims via `Foglet.Config` — **OUT**. Module constants only.
- Exit hint in the gate message — **OUT**. Ctrl+C at SSH channel works regardless.

---

## 8. Files Touched

| File | Action | Lines |
|------|--------|-------|
| `lib/foglet_bbs/tui/size_gate.ex` | CREATE | ~40 |
| `lib/foglet_bbs/tui/app.ex` | EDIT (3 insertions) | `view/1` (+3), `do_update({:window_change, ...})` (+4), `do_update({:key, ...})` (+4), alias (+1) = ~12 lines added |
| `test/foglet_bbs/tui/size_gate_test.exs` | CREATE | ~60 |
| `test/foglet_bbs/tui/app_test.exs` | EDIT (add describe blocks) | ~80 added |

**Total:** 2 files created, 2 files edited, no deletions.

---

## RESEARCH COMPLETE

**Confidence:** HIGH — every decision in CONTEXT is verified against the live codebase. No new external dependencies, no signature changes, no schema changes. The only novel design choice is whether centering works with a single `column` wrapper (plan starts there, falls back to nested container if empirically needed).

**Ready for planning.** Recommend two plans:

1. **Plan 01 — Gate module + view branch (Wave 1):** Create `Foglet.TUI.SizeGate`, wire `App.view/1` to use it. Ship the visible gate.
2. **Plan 02 — Update-path guards + regression tests (Wave 2, depends_on: 01):** Same-size guard in `do_update({:window_change, ...})`, key-swallow guard in `do_update({:key, ...})`, composer-draft-preservation regression test. Locks in state safety.

Two plans, two waves because Plan 02's tests depend on Plan 01's `SizeGate` module existing. Both autonomous, no checkpoints needed.
