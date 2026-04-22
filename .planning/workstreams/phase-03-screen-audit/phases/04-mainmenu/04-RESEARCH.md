# Phase 4: MainMenu — Research

**Researched:** 2026-04-21
**Domain:** Elixir TUI screen audit — stateless screen discipline, sparseness preservation, helper/rubric compliance
**Confidence:** HIGH (grounded in direct reads of `main_menu.ex`, its tests, workstream roadmap/requirements/context, and Phase 0 helper outcomes)

## Summary

Phase 4 is a narrow screen-audit phase, not a redesign. `lib/foglet_bbs/tui/screens/main_menu.ex` is already close to the target shape: it uses `Theme.from_state/1`, renders through `ScreenFrame.render/4`, stays stateless, and keeps the visible content minimal. The remaining work is mostly **making the current intent explicit and rubric-compliant**.

Three concrete gaps remain:

1. The screen still hardcodes `{80, 24}` in the `[C]` path, which fails inherited grep gate `AUDIT-05` item 7. This phase should replace that inline tuple with a module-level `@default_terminal_size` attribute.
2. The KeyBar metadata is still an inline literal passed directly to `ScreenFrame.render/4`. Phase requirements `MENU-02` and `MENU-03` want the render rows and KeyBar rows treated as two intentionally separate, load-bearing shapes. That means introducing a dedicated `@menu_keys` attribute and documenting why it duplicates `@menu_items`.
3. The moduledoc does not yet document the intentional-stateless deviation required by `MENU-05` / `AUDIT-19`, nor the sparseness reservation for future milestones.

The screen has **no domain lookup call sites**, so `MENU-01` is satisfied by verifying that no `Screens.Domain.get/2` integration is needed here. The correct outcome is not to invent one.

## What Must Stay True

### User-visible behavior

- Content remains: one welcome line, one blank spacer, and three plain-text menu rows.
- KeyBar hints remain exactly `B / C / Q`.
- `[B]` still routes to `:board_list` with `{:load_boards}`.
- `[C]` still seeds `screen_state[:new_thread]` via `Foglet.TUI.Screens.NewThread.init_screen_state/1`, sets `origin: :main_menu`, and dispatches `{:load_boards_for_new_thread}`.
- `[Q]` still emits `{:terminate, :logout}`.

### Scope and sparseness

- No banner, divider, date/time line, status panel, session info, or notification badge is added.
- The blank spacer line stays. Per phase context D-01, the roadmap’s “4 content lines” wording means 4 non-empty content lines, not “remove the spacer.”
- No `screen_state[:main_menu]` entry is introduced.
- No widget swap to `SelectionList`, `Button`, `Tabs`, or anything interactive beyond current plain `text/2` rows.

## Current Code Read

### `lib/foglet_bbs/tui/screens/main_menu.ex`

- Already uses `Theme.from_state(state)` in `render/1`.
- Already uses `ScreenFrame.render(state, "Main Menu", content, key_list)`.
- Already returns `:no_match` for unrelated keys.
- Already seeds `screen_state[:new_thread]` through `NewThread.init_screen_state/1`.
- Still uses `state.terminal_size || {80, 24}` inline inside the `[C]` handler.
- Uses only `@menu_items`; the KeyBar tuples are still an inline literal instead of a parallel load-bearing attribute.
- Moduledoc is too thin for `MENU-05` and does not explain the stateless deviation.

### `test/foglet_bbs/tui/screens/main_menu_test.exs`

- Covers the three key routes and a crash-free render.
- Also contains render-tree assertions about `justify_content: :space_between` and a divider after the status bar. Those are chrome-level expectations inherited from `ScreenFrame`, not MainMenu-specific behavior, and they do not express Phase 4’s real acceptance bar.
- The plan should keep route coverage and add screen-specific assertions that reinforce sparseness and statelessness rather than layout internals owned elsewhere.

## Recommended Structural Shape

### Module layout

MainMenu is intentionally stateless, so its `AUDIT-18` ordering is a documented deviation:

1. Aliases + imports
2. Module attributes
3. `render/1`
4. `handle_key/2`
5. Private helpers, if any

There should be **no** `init_screen_state/1`. The moduledoc must say this explicitly.

### Module attributes to keep/add

Recommended target:

```elixir
@default_terminal_size {80, 24}

@menu_items [
  {"B", "Browse Boards"},
  {"C", "Compose New Thread"},
  {"Q", "Logout"}
]

@menu_keys [
  {"B", "Boards"},
  {"C", "Compose"},
  {"Q", "Logout"}
]
```

Why this matters:

- `@default_terminal_size` clears inherited grep gate #7 without introducing a shared helper (consistent with the workstream’s per-screen terminal-size policy).
- `@menu_items` and `@menu_keys` should stay separate because the render rows and KeyBar rows are different UI contracts. A single shared source would push the screen toward “DRY for its own sake,” which the phase context explicitly rejects.

## Validation Architecture

### Automated checks

- Focused screen suite: `mix test test/foglet_bbs/tui/screens/main_menu_test.exs`
- Full audit gate: `mix precommit`
- Grep checks:
  - `rg -n '\{80, 24\}' lib/foglet_bbs/tui/screens/main_menu.ex`
  - `rg -n 'get_in\((ctx|sc), \[:domain,' lib/foglet_bbs/tui/screens/main_menu.ex`
  - `rg -n '\(Map\.get\(state, :session_context\) \|\| %\{\}\) \|> Map\.get\(:theme\)' lib/foglet_bbs/tui/screens/main_menu.ex`

### What to assert in tests

- Render tree still contains the welcome text and the three menu rows.
- Key routing semantics for `B`, `C`, `Q`, and unknown keys remain intact.
- `[C]` still sets `origin: :main_menu` and leaves `step: :board`.
- No test should assert the existence of a synthetic `screen_state[:main_menu]` default.

### What to verify by grep / file read rather than tests

- Moduledoc explicitly says MainMenu is intentionally stateless and warns against adding `screen_state[:main_menu]`.
- `@menu_keys` and `@menu_items` both exist.
- `{80, 24}` is gone from the file.

## Implementation Guidance

### Planner should treat MENU-01 carefully

`MENU-01` says “Theme extraction + domain-module lookup use the Phase 0 helpers.” For MainMenu:

- Theme helper is already in use and should remain untouched.
- Domain helper is **not applicable** because the screen has no domain lookup call site. The correct implementation is verification plus documentation, not adding dead code.

### Test strategy

One plan is likely enough for this phase. The work is small and coupled:

- `main_menu.ex` changes are mostly attribute/moduledoc/helper-cleanup.
- `main_menu_test.exs` should be updated in the same plan so the test suite locks the intended sparseness behavior.

Splitting this into multiple plans would create overhead without reducing risk.

## Risks and Landmines

- Do not “improve” the screen by adding anything to the reserved whitespace.
- Do not introduce `init_screen_state/1` just to satisfy a generic rubric; this phase’s requirement is the documented deviation.
- Do not convert the inline rows to a richer widget. Plain `text/2` is the correct primitive here.
- Do not change the compose-entry semantics while replacing the terminal-size fallback.
- Do not overfit tests to `ScreenFrame` internals; keep MainMenu tests about MainMenu behavior.

## Recommended Plan Shape

Single execute plan:

- Modify `lib/foglet_bbs/tui/screens/main_menu.ex`
- Modify `test/foglet_bbs/tui/screens/main_menu_test.exs`
- Verify grep gates, focused test file, and `mix precommit`

This is sufficient to cover `MENU-01..05` plus inherited `AUDIT-05..22` for this screen.
