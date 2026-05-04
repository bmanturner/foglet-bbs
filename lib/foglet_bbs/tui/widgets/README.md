# Foglet.TUI.Widgets — Widget Catalog Index

Every widget in this directory routes colors/styles through
`Foglet.TUI.Theme` (D-07, D-09) and accepts the theme as an explicit
`theme:` keyword argument (D-13). Stateful widgets expose the
`init/1` + `handle_event/2` + `render/2` triplet (D-14); stateless
widgets expose `render/*` only (D-16).

New widgets should:

- Live under `lib/foglet_bbs/tui/widgets/<bucket>/<name>.ex` (D-10).
- Cite the decision IDs they honour in the `@moduledoc` (`D-07`, `D-09`, `D-13`, `D-14` or `D-16`).
- Route colors through `Foglet.TUI.Theme` slots — never hardcoded
  `:red`/`:green`/`:cyan`/`:yellow`/`:blue`/`:magenta`/`:white`/`:black` atoms (D-07, D-09).
- Declare module-constant defaults as `@default_*` / `@on_marker` / etc. at the
  top of the file (D-08).
- Ship with a D-18 test (theme hygiene + smoke render) in `test/foglet_bbs/tui/widgets/<bucket>/`.

## Chrome (Phase 1, unchanged)

| Module | File | Description |
|---|---|---|
| `Chrome.ScreenFrame` | [`chrome/screen_frame.ex`](chrome/screen_frame.ex) | Outer frame wrapping every screen (FRAME-01) |
| `Chrome.StatusBar`   | [`chrome/status_bar.ex`](chrome/status_bar.ex)   | Top-of-screen title + handle bar (FRAME-02) |
| `Chrome.CommandBar`  | [`chrome/command_bar.ex`](chrome/command_bar.ex) | Bottom-of-screen V2 grouped command bar |

`Chrome.CommandBar` treats command priority as retention priority: lower
numbers stay visible longer under tight width. Use `0` for system escape
hatches, `5` for the active screen's primary action, `10` for routine
navigation, and larger numbers for secondary hints that may drop first.

## Compose / Modal (Phase 4 / 7, flat — unchanged per D-11)

| Module | File | Description |
|---|---|---|
| `Compose` | [`compose.ex`](compose.ex) | Shared plumbing for post/thread composers (COMPOSE-01/02) |
| `Modal`   | [`modal.ex`](modal.ex)     | Modal body (info/error/warning/confirm) — thin adapter (D-20, Phase 7) |
| `Modal.Form` | [`modal/form.ex`](modal/form.ex) | Stateful body-only modal form with refreshed heading, labels, required markers, inline/base errors, compact submit/cancel footer, typed fields, focus movement, and app-owned overlay chrome (D-14, Phase 24) |

## Composer

| Module | File | Description |
|---|---|---|
| `Composer.EditorFrame` | [`composer/editor_frame.ex`](composer/editor_frame.ex) | Stateless shared composer shell for Edit/Preview, counters, and context; honors D-01, D-04, D-06, D-13, and D-16 |

## Post (Phase 1–3, unchanged)

| Module | File | Description |
|---|---|---|
| `Post.MarkdownBody` | [`post/markdown_body.ex`](post/markdown_body.ex) | Themed markdown renderer (RENDER-01, RENDER-02) |
| `Post.PostCard`     | [`post/post_card.ex`](post/post_card.ex)         | Per-post card (header + body) |

## List

| Module | File | Description |
|---|---|---|
| `List.SelectionList` | [`list/selection_list.ex`](list/selection_list.ex) | Stateless selection list — caller owns `selected_index` (D-03) |
| `List.ListRow`       | [`list/list_row.ex`](list/list_row.ex)             | Single list row with optional metadata (LIST-03) |
| `List.SmartList`     | [`list/smart_list.ex`](list/smart_list.ex)         | Stateful — search + pagination + multi-select (D-02, Phase 8) |

## Input (Phase 8)

| Module | File | Description |
|---|---|---|
| `Input.Button`     | [`input/button.ex`](input/button.ex)             | Themed button with `:role` (primary/secondary/danger/success) |
| `Input.Checkbox`   | [`input/checkbox.ex`](input/checkbox.ex)         | Toggle with `checked?` + `disabled` |
| `Input.RadioGroup` | [`input/radio_group.ex`](input/radio_group.ex)   | Single-choice selector (DSL-composed from `text/2`) |
| `Input.TextInput`  | [`input/text_input.ex`](input/text_input.ex)     | Single-line input with validator/mask/max_length |

## Auth (FOG-612)

| Module | File | Description |
|---|---|---|
| `Auth.AuthForm` | [`auth/auth_form.ex`](auth/auth_form.ex) | Stateless compact card shell for logged-out/login-adjacent forms; honors D-07/D-09/D-13/D-16 |
| `Input.Tabs`       | [`input/tabs.ex`](input/tabs.ex)                 | Tab bar with Left/Right/1–9 nav |
| `Input.Menu`       | [`input/menu.ex`](input/menu.ex)                 | Nested dropdown / context menu |

## Display (Phase 8)

| Module | File | Description |
|---|---|---|
| `Display.Table`        | [`display/table.ex`](display/table.ex)                 | Sortable / filterable / selectable table |
| `Display.Badge`        | [`display/badge.ex`](display/badge.ex)                 | Compact semantic state badge for operator-console rows and summaries |
| `Display.KvGrid`       | [`display/kv_grid.ex`](display/kv_grid.ex)             | Width-safe caller-provided key/value grid with optional badge metadata |
| `Display.ConsoleTable` | [`display/console_table.ex`](display/console_table.ex) | Dense operator-console facade over `Display.Table` with compact defaults and empty-state handling |
| `Display.Tree`         | [`display/tree.ex`](display/tree.ex)                   | Hierarchical tree with expand/collapse |
| `Display.Progress`     | [`display/progress.ex`](display/progress.ex)           | Animated progress bar (stateless) |
| `Display.ScrambleText` | [`display/scramble_text.ex`](display/scramble_text.ex) | Deterministic frame-index-driven scramble-text reveal |

## Workspace (Phase 24)

| Module | File | Description |
|---|---|---|
| `Workspace.Inspector` | [`workspace/inspector.ex`](workspace/inspector.ex) | Optional wide-terminal selected-row detail and action descriptor panel for future operator-console screens |

## Progress (Phase 8)

| Module | File | Description |
|---|---|---|
| `Progress.Spinner` | [`progress/spinner.ex`](progress/spinner.ex) | Indeterminate spinner (stateless, frame-index-driven) |

## Further reading

- **Research:** [`.planning/workstreams/phase-03-polish/phases/08-build-local-widget-library-from-raxol-primitives/08-RESEARCH.md`](../../../../.planning/workstreams/phase-03-polish/phases/08-build-local-widget-library-from-raxol-primitives/08-RESEARCH.md) — Pattern 1 / Pattern 2 / Pattern 3 templates, pitfalls, architecture map.
- **Screen Contract:** [`../SCREEN_CONTRACT.md`](../SCREEN_CONTRACT.md) — how screens own state, emit `Foglet.TUI.Effect` values, consume `Foglet.TUI.Context`, route task results, request modals, and render through the App shell.
- **Raxol docs:** [`docs/raxol/getting-started/WIDGET_GALLERY.md`](../../../../docs/raxol/getting-started/WIDGET_GALLERY.md) — source gallery; every Phase 8 widget maps to a section here.
- **Theming contract:** [`docs/raxol/cookbook/THEMING.md`](../../../../docs/raxol/cookbook/THEMING.md).
