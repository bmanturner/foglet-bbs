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
