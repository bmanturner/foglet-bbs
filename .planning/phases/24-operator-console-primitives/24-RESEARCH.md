# Phase 24: Operator Console Primitives - Research

**Researched:** 2026-04-25
**Status:** Ready for planning

## Research Question

What does the planner need to know to create executable plans for Phase 24:
Operator Console Primitives?

## Summary

Phase 24 can be implemented as a focused widget-library expansion. The safest
path is to add three new stateless/pure primitives, add one stateful wrapper
around the existing table facade, refresh `Modal.Form.render/2` in place, and
prove everything with widget-level tests using realistic Account, Moderation,
Sysop, invite, and board-shaped fixture data.

The phase should not migrate Account, Moderation, or Sysop tab bodies. Existing
screen modules are source references for fixture shapes only. Phase 25 owns
adoption.

## Existing Architecture

### Widget Contracts

`lib/foglet_bbs/tui/widgets/README.md` establishes the local widget rules:

- New widgets live under `lib/foglet_bbs/tui/widgets/<bucket>/<name>.ex`.
- Stateless widgets expose render functions only.
- Stateful widgets expose `init/1`, `handle_event/2`, and `render/2`.
- `render` calls receive `theme:` explicitly.
- Colors route through `Foglet.TUI.Theme`; tests should refute leaked hardcoded
  terminal color atoms.
- Mirrored tests live under `test/foglet_bbs/tui/widgets/<bucket>/`.

This means:

- `Display.Badge` should be stateless.
- `Display.KvGrid` should be stateless.
- `Workspace.Inspector` should be stateless unless a concrete stateful need
  appears during implementation.
- The operator console table should be stateful because it composes the existing
  stateful `Display.Table`.

### Existing Table Foundation

`Foglet.TUI.Widgets.Display.Table` already wraps `Raxol.UI.Components.Table`.
It normalizes column specs, supports `sortable`, `filterable`, and row
selection, uses `selected_row = nil` for empty rows to avoid navigation crashes,
and maps table styles through `Foglet.TUI.Theme`.

The operator console table should not fork Raxol behavior. It should wrap
`Display.Table.init/1`, `Display.Table.handle_event/2`, and
`Display.Table.render/2`, adding console-specific defaults:

- compact column normalization,
- rows supplied as maps,
- `empty_state` copy,
- selectable default true for operator tables,
- sortable/filterable flags passed through,
- deterministic row-selected actions from `Display.Table.handle_event/2`,
- theme routing delegated to `Display.Table`.

### Existing Modal.Form Contract

`Foglet.TUI.Widgets.Modal.Form` already owns:

- `init/1`,
- `handle_event/2`,
- `render/2`,
- `set_errors/2`,
- typed coercion for text, integer, boolean, enum, and textarea fields,
- Tab and Shift-Tab focus movement,
- Enter submit behavior,
- Esc cancel behavior,
- textarea raw-value tracking,
- caller-provided submit/cancel callbacks,
- body-only rendering.

The implementation should change only the rendered body hierarchy. It must not
add `box`, borders, centering, or overlay chrome because
`Foglet.TUI.App.render_modal_overlay/2` owns modal chrome.

## Recommended Implementation Patterns

### Pattern 1: `Display.Badge`

Recommended module:

`lib/foglet_bbs/tui/widgets/display/badge.ex`

Recommended API:

- `render(state, opts)` where `state` is an atom or binary and `opts` includes
  `theme: %Theme{}`.
- Optional `:label`, `:compact`, and `:role` options.
- Built-in states at minimum:
  `:required`, `:subscribed`, `:locked`, `:sticky`, `:pending`, `:healthy`,
  `:error`, `:neutral`, and `:info`.

Map states to presentation badge roles first, then to theme slots:

- `:required` -> `:warning`
- `:subscribed` -> `:success`
- `:locked` -> `:warning`
- `:sticky` -> `:accent`
- `:pending` -> `:info`
- `:healthy` -> `:success`
- `:error` -> `:error`
- `:neutral` -> `:info`
- `:info` -> `:info`

The exact labels/glyphs are planner discretion, but flattened render output
must remain recognizable for tests. Good compact labels include `required`,
`subscribed`, `locked`, `sticky`, `pending`, `healthy`, `error`, and `info`.

Tests should assert:

- all required states appear in flattened output,
- `Presentation.theme_mappings().badges` is used or mirrored through a helper,
- rendered trees include relevant resolved theme values,
- no `:red`, `:green`, `:cyan`, `:yellow`, `:blue`, `:magenta`, `:white`, or
  `:black` atoms leak in serialized output,
- compact rendering remains small enough for 64-column contexts.

### Pattern 2: `Display.KvGrid`

Recommended module:

`lib/foglet_bbs/tui/widgets/display/kv_grid.ex`

Recommended API:

- `render(entries, opts)` where `entries` is a list of maps.
- Required entry keys: `:label`, `:value`.
- Optional entry keys: `:state`, `:badge`, `:value_style`, `:label_style`.
- Options: `theme:`, `width:`, `label_width:`, `gap:`.

Implementation should use `Foglet.TUI.TextWidth` for:

- display-width-safe label truncation,
- label padding,
- value truncation,
- row width assertions in tests.

Avoid raw `String.length/1` for layout-sensitive math. `String.length/1` is
acceptable only for non-layout validation; this widget's alignment is layout.

Fixture coverage should include:

- Account profile rows: `Location`, `Tagline`, `Real name`.
- Account prefs rows: `Timezone`, `Time format`, `Theme`.
- Sysop system rows: `Version`, `Uptime`, `Sessions`, `Active boards`,
  `OTP processes`, `DB pool size`.
- Site setting rows: `Registration`, `Invite policy`, `Board creation`.
- Runtime limit rows: `Title limit`, `Post limit`, `Upload limit`.
- Status summary rows with badges: `Health`, `Pending users`, `SSH daemon`.

### Pattern 3: `Display.ConsoleTable`

Recommended module:

`lib/foglet_bbs/tui/widgets/display/console_table.ex`

`ConsoleTable` should be an explicit operator-console table facade, not a
replacement for all table rendering. It should delegate to `Display.Table` for
state and rendering.

Recommended state:

- `table: Display.Table.t()`,
- `empty_state: binary`,
- `last_action: action`,
- `columns: list`.

Recommended API:

- `init(opts)` with `:columns`, `:rows`, optional `:empty_state`, `:sortable`,
  `:filterable`, `:selectable`, `:page_size`.
- `handle_event(event, state)` delegates to `Display.Table.handle_event/2`.
- `render(state, opts)` renders compact empty state when rows are empty and
  otherwise delegates to `Display.Table.render/2`.

Fixture coverage should cover:

- Moderation LOG: timestamp, moderator, target, reason.
- Moderation USERS: handle, role, status.
- Moderation BOARDS: name, slug, category, scope.
- Sysop USERS: status, handle, email.
- Sysop BOARDS: category, slug, name, postability/status.
- Account SSH keys: label, fingerprint, created, last used.
- Invites: code, status, issuer, inserted_at, lifecycle details.

No domain contexts should be called from this module or its tests. Use maps.

### Pattern 4: `Workspace.Inspector`

Recommended module:

`lib/foglet_bbs/tui/widgets/workspace/inspector.ex`

Recommended API:

- `render(selection, opts)` where `selection` is `nil` or a map.
- Options: `theme:`, `width:`, `min_width:`, `title:`, `details:`, `actions:`.
- Collapse by returning an intentionally empty render node/list when
  `width < min_width`.

The context recommends wide-only behavior aligned with the existing `132x50`
precedent. A default `min_width` around 100 columns is appropriate, but the
planner may choose the exact value.

Details and actions are caller-provided data:

- Details are label/value pairs rendered with `KvGrid`.
- Actions are descriptors like `%{key: "E", label: "Edit"}` or
  `%{key: "D", label: "Archive", role: :danger}`.

The inspector must not perform domain mutations, infer unavailable workflows,
or create fake actions. Tests should include selected board, user, invite, and
no-selection fixtures.

### Pattern 5: `Modal.Form` Body Refresh

Modify:

`lib/foglet_bbs/tui/widgets/modal/form.ex`

Extend:

`test/foglet_bbs/tui/widgets/modal/form_test.exs`

Keep all current behavior tests passing. Add render tests for:

- stronger heading/title visible,
- each label visible,
- required marker visible for `%{required: true}` fields,
- inline field errors visible,
- `:base` error visible,
- action footer visible with submit/cancel controls,
- serialized render does not contain `type: :box`, `border`, or equivalent
  outer modal chrome introduced by `Modal.Form`.

The action footer can be compact copy such as:

`[Enter] Submit   [Esc] Cancel`

The exact copy is discretionary, but tests should check stable substrings.

## File Map For Planning

### New Files

- `lib/foglet_bbs/tui/widgets/display/badge.ex`
- `lib/foglet_bbs/tui/widgets/display/kv_grid.ex`
- `lib/foglet_bbs/tui/widgets/display/console_table.ex`
- `lib/foglet_bbs/tui/widgets/workspace/inspector.ex`
- `test/foglet_bbs/tui/widgets/display/badge_test.exs`
- `test/foglet_bbs/tui/widgets/display/kv_grid_test.exs`
- `test/foglet_bbs/tui/widgets/display/console_table_test.exs`
- `test/foglet_bbs/tui/widgets/workspace/inspector_test.exs`

### Existing Files To Modify

- `lib/foglet_bbs/tui/widgets/modal/form.ex`
- `test/foglet_bbs/tui/widgets/modal/form_test.exs`
- `lib/foglet_bbs/tui/widgets/README.md`

### Source References Only

- `lib/foglet_bbs/tui/widgets/display/table.ex`
- `test/foglet_bbs/tui/widgets/display/table_test.exs`
- `lib/foglet_bbs/tui/presentation.ex`
- `lib/foglet_bbs/tui/theme.ex`
- `lib/foglet_bbs/tui/text_width.ex`
- `test/support/foglet/tui/widget_helpers.ex`
- `test/foglet_bbs/tui/layout_smoke_test.exs`
- `lib/foglet_bbs/tui/screens/account/ssh_keys_surface.ex`
- `lib/foglet_bbs/tui/screens/account/profile_form.ex`
- `lib/foglet_bbs/tui/screens/account/prefs_form.ex`
- `lib/foglet_bbs/tui/screens/moderation.ex`
- `lib/foglet_bbs/tui/screens/sysop/system_snapshot.ex`
- `lib/foglet_bbs/tui/screens/sysop/users_view.ex`
- `lib/foglet_bbs/tui/screens/sysop/boards_view.ex`
- `lib/foglet_bbs/tui/screens/shared/invites_surface.ex`

## Risks And Pitfalls

1. **Accidental screen migration.** Phase 24 should not convert Account,
   Moderation, or Sysop tab bodies. Keep source changes to primitives, tests,
   and widget README, except for narrowly required `Modal.Form` compatibility.

2. **Table fork drift.** Duplicating Raxol table behavior would create a second
   table stack. Wrap `Display.Table` unless a concrete implementation blocker
   appears.

3. **Width regressions.** `KvGrid` and badge/table labels must use
   `TextWidth` for layout-sensitive truncation/padding.

4. **Theme leaks.** Hardcoded terminal color atoms are easy to introduce in new
   widgets. Every new widget test needs serialized render hygiene checks.

5. **Fake operator workflows.** Inspector action descriptors are display data.
   They must not imply new moderation/sysop/account workflows that the domain
   does not support.

6. **Modal double chrome.** `Modal.Form.render/2` must not introduce an outer
   box, border, or centering container.

7. **Over-coupled fixtures.** Tests should use realistic maps copied from
   screen shapes, but they should not call domain contexts, Repo, or screen
   loaders.

## Validation Architecture

Phase 24 is highly testable with existing ExUnit widget infrastructure.

### Quick Feedback

Run the widget-focused tests after each related implementation task:

```bash
rtk mix test \
  test/foglet_bbs/tui/widgets/display/badge_test.exs \
  test/foglet_bbs/tui/widgets/display/kv_grid_test.exs \
  test/foglet_bbs/tui/widgets/display/console_table_test.exs \
  test/foglet_bbs/tui/widgets/workspace/inspector_test.exs \
  test/foglet_bbs/tui/widgets/modal/form_test.exs
```

### Broader TUI Regression

Run the existing related widget and layout tests after the primitive set lands:

```bash
rtk mix test \
  test/foglet_bbs/tui/widgets/display/table_test.exs \
  test/foglet_bbs/tui/widgets/catalog_smoke_test.exs \
  test/foglet_bbs/tui/layout_smoke_test.exs
```

### Final Verification

Run the project finish-line command:

```bash
rtk mix precommit
```

### Sampling Plan

- After Badge: run `badge_test.exs`.
- After KvGrid: run `kv_grid_test.exs`.
- After ConsoleTable: run `console_table_test.exs` plus `table_test.exs`.
- After Inspector: run `inspector_test.exs`.
- After Modal.Form: run `form_test.exs`.
- After README/catalog update: run `catalog_smoke_test.exs` if it still scans
  widget modules/catalog content.
- Before phase completion: run `rtk mix precommit`.

## Suggested Plan Breakdown

1. Badge primitive and tests.
2. KvGrid primitive and tests.
3. ConsoleTable wrapper and tests.
4. Workspace.Inspector primitive and tests.
5. Modal.Form refresh and tests.
6. Widget README/catalog update and focused regression pass.

This keeps each plan independently reviewable while preserving dependency order:
Inspector can reuse KvGrid, ConsoleTable can reuse Display.Table, and Modal.Form
can be updated independently after the new display primitives land.

## Research Complete

The implementation is well bounded and can proceed to planning.
