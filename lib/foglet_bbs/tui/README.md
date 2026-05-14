# Foglet TUI

The Foglet TUI is the primary product surface. Phoenix, PubSub, telemetry, and
web endpoints support the SSH terminal experience; end-user workflows belong in
the TUI unless the architecture docs intentionally add another product surface.

This directory contains the Raxol app shell, screen reducers and renderers,
runtime effects, shared widgets, theme helpers, and manual/test rendering
support used by the SSH session.

## Where To Start

- [Screen contract](SCREEN_CONTRACT.md) defines the `Foglet.TUI.Screen`
  callbacks, state ownership, effect boundary, modal routing, subscriptions,
  cancel-key behavior, and render-purity rules.
- [Widget guide](widgets/README.md) catalogs reusable widgets and the authoring
  rules for stateless and stateful widgets.
- [Testing guide](../../../docs/TESTING.md) explains the ExUnit layout, TUI test
  helpers, layout smoke tests, and process-testing rules.
- [Raxol widget gallery](../../../docs/raxol/getting-started/WIDGET_GALLERY.md)
  shows the underlying view-tree primitives available to screens and widgets.
- [Agent TUI inspection notes](../../../AGENTS.md#inspecting-the-tui) document
  `rtk mix foglet.tui.render` for ad-hoc screen inspection.

## Boundaries

- `Foglet.TUI.App` is the runtime shell. It owns session identity, routing,
  modal overlay state, task execution, PubSub wiring, terminal size, and effect
  interpretation.
- Screen modules own screen-local state, reducer logic, focused subscriptions,
  and pure rendering from already-loaded state.
- `Foglet.TUI.Effect` is the public vocabulary screens use to ask App for
  runtime work such as navigation, tasks, PubSub publishing, modal control,
  terminal-size updates, session messages, and quit.
- Widgets are reusable view primitives. Render-only widgets accept data plus an
  explicit `theme:` option and return Raxol view trees; stateful widgets expose
  `init/1`, `handle_event/2`, and `render/2`.
- `Foglet.TUI.Theme` is the color/style boundary. Route colors through theme
  slots instead of hardcoding terminal colors in screens or widgets.
- Render and testing tools live near the product surface:
  `Foglet.TUI.AsciiRenderer` and `rtk mix foglet.tui.render` use the same Raxol
  layout path as production, while tests should assert behavior and stable
  rendered buffers.

## Rendering And Regression Checks

Use `rtk mix foglet.tui.render <screen>` when you need to see a screen quickly
without starting an SSH client. It is a manual inspection tool for layout,
chrome, and width-sensitive review.

Use reducer, widget, buffer, and layout smoke tests for regressions. Manual
render output is useful evidence while developing, but a checked-in behavior or
buffer test should carry any invariant that must keep passing.

## Layout Helpers

Use `Foglet.TUI.Layout` when a screen or widget needs deterministic cell math
that should be easy to test outside Raxol. It returns plain rect structs that
can drive style widths, heights, and assertions.

```elixir
alias Foglet.TUI.Layout

parent = %{x: 0, y: 0, width: terminal_width, height: body_height}

[header, body, footer] =
  Layout.vertical(parent, [
    {:length, 3},
    {:fill, 1},
    {:length, 1}
  ])
```

Prefer this helper for header/body/footer and sidebar/content splits. Keep
using Raxol `column`, `row`, `box`, and `spacer` directly when the built-in view
tree already expresses the layout clearly.

## Styled Text Helpers

Use `Foglet.TUI.Text` when a screen or widget needs to compose styled runs
before converting them to the current Raxol view tree. The helper is useful for
multi-run rows such as command hints, labels with badges, and small render
helpers that would otherwise pass repeated `fg: theme.slot.fg` options around.

```elixir
alias Foglet.TUI.Text

hint =
  Text.Line.new([
    Text.Span.new("[Enter]", fg: :accent) |> Text.Span.bold(),
    Text.Span.new(" Launch", fg: :primary)
  ])

Text.to_raxol(hint, theme)
```

Use direct Raxol `text/2` calls when rendering one simple node is clearer.
Prefer theme slot atoms with `Foglet.TUI.Text`; raw terminal color atoms are not
accepted, and raw color values should stay limited to widgets that already
document that contract.

## Key Bindings

Use `Foglet.TUI.KeyBinding` for common non-text-entry key predicates:
scrolling, paging, home/end, submit, cancel, and help. It wraps
`Foglet.TUI.ScrollKeys`, so the vertical movement convention remains
`↑`/`k` for previous and `↓`/`j` for next.

Do not use the `j`/`k` movement predicates while focus is inside text input,
composer body text, or search/filter fields. In those contexts, character keys
must remain typed input. Full-screen composers that follow the documented
cancel fallback can call `KeyBinding.cancel?(event, composer?: true)` to treat
`Ctrl+C` as the same reducer path as `Esc`; other surfaces should use plain
`Esc` cancellation only.
