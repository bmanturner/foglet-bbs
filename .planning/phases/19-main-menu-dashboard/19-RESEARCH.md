# Phase 19: Main Menu Dashboard - Research

**Researched:** 2026-04-25
**Domain:** Elixir/Raxol TUI — screen refactor (body layout + command-bar dedup)
**Confidence:** HIGH (all key claims verified from repo source files in this session)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01**: One canonical "visible destinations" list + one canonical "visible actions" list inside `MainMenu`. Body renders destinations; command bar renders actions. Single source of truth; dedup is structural, not post-hoc subtraction.
- **D-02**: `Chrome.CommandBar`, `Chrome.Normalizer`, `Chrome.ScreenFrame` stay passive. Phase 18 invariants must hold.
- **D-03**: Body Navigation panel destinations (role-gated via `ShellVisibility`): B Boards (always), C Compose (always), A Account (`account_visible?`), M Moderation (`moderation_visible?`), S Sysop (`sysop_visible?`), Q Logout (always).
- **D-04**: Command bar ACTIONS only: O Post Oneliner (user non-nil), H Hide oneliner (hideable focused AND mod/sysop), ↑/↓ Select (oneliners non-empty).
- **D-05**: H via `Bodyguard.permit?(Authorization, :hide_oneliner, user, :site)`. Tests must lock negative path for regular users AND positive path for mod/sysop.
- **D-06**: Empty command bar is acceptable — no fallback affordance invented.
- **D-07**: Body has boxed `┌ Navigation ┐` left + boxed `┌ Oneliners ┐` right. Activity panel explicitly OUT.
- **D-08**: Navigation rows shaped as `glyph + label + right-aligned key`. Suggested glyphs: ● Boards, ✎ Compose, ◇ Account, ⚑ Moderation, ▣ Sysop, ↯ Logout. Theme slots only; right-aligned key via `Foglet.TUI.TextWidth`.
- **D-09**: Phase 19 adopts SCREENS.md visual shape only — no selection-list cursor, no Enter-to-open.
- **D-10**: If glyph cell-width breaks alignment at 64x22, fall back to ASCII-only rows `[K] Label  →`.
- **D-11**: Replace `Welcome back, handle.` line with boxed Navigation panel header.
- **D-12**: Continue using `split_pane(direction: :horizontal, ...)`. No manual TextWidth column math. `min_size` tunable.
- **D-13**: Prove 64x22 / 80x24 / 132x50 via positioned-render tests extending `layout_smoke_test.exs:119-183`.
- **D-14**: Oneliner clipping via `TextWidth.slice_to_width/2`. Constants `@oneliner_handle_limit`, `@oneliner_body_limit`, `@oneliner_display_limit` tunable.
- **D-15**: Test additions extend `test/foglet_bbs/tui/screens/main_menu_test.exs`. No new files.
- **D-16**: Size-contract coverage extends `test/foglet_bbs/tui/layout_smoke_test.exs`. No new files.
- **D-17**: Do NOT create `main_menu_layout_test.exs` or any other new test file.

### Claude's Discretion

- Exact module/struct names for the destinations-vs-actions split (D-01, D-04).
- Exact glyph atoms within the SCREENS.md suggested set (D-08); ASCII fallback gate point.
- Exact label text on command-bar action atoms.
- Exact `split_pane` ratio and `min_size` values (D-12) as long as 64x22 tests pass.
- Whether Navigation panel uses `box do ... end` with `border: :single`, `column` with `border:` style, or a thin panel helper — acceptance criterion is visual match to SCREENS.md sketch.

### Deferred Ideas (OUT OF SCOPE)

- Activity panel (unread counts, pinned threads, active sessions, moderation queue).
- Destination cursor, selected_index, or Enter-to-open destination behavior.
- Operator console primitives (Display.Badge, Display.KvGrid) — Phase 24 territory.
- Larger-terminal inspector panes for Home.
- Theme palette retuning for glyph contrast.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| HOME-01 | User can navigate main-menu destinations with selection keys while existing direct hotkeys continue to work. | D-01 through D-05 fully covered; handle_key/2 clauses need no structural change, only `visible_menu_items` → destinations list split. |
| HOME-02 | Home shows useful session/BBS activity context such as oneliners when available. | Existing `oneliner_rows/2` path retained; D-07 adds boxed panel header; D-14 clips to budget. |
| HOME-03 | Home remains navigable at 64x22, reaches compact dashboard rhythm at 80x24, side-by-side only when width permits. | D-12 splits via `split_pane`; D-13 locks sizes via `layout_smoke_test.exs`; existing `apply_at_size/2` harness already proven on Chrome V2 at `[{64,22},{80,24},{132,50}]`. |
</phase_requirements>

---

## Summary

Phase 19 is a focused refactor of `Foglet.TUI.Screens.MainMenu` — ~320 lines today. The major deltas are: (1) split the monolithic `visible_menu_items/1` and `visible_menu_keys/1` into a single `visible_destinations/1` that the body renders and a separate `visible_actions/1` that the command bar renders; (2) wrap each pane in a `box do ... end` with `border: :single` to produce the boxed panel visual; (3) build `glyph + label + right-aligned key` rows using `TextWidth.pad_trailing/2` / `TextWidth.display_width/1`; and (4) extend tests in two existing files.

No new library dependencies, no new screen-state fields, no new data queries. Every primitive needed already exists in `lib/foglet_bbs/tui/`. The only conceptual risk is the right-aligned key column inside a box whose inner width is determined by `split_pane` allocation — the plan must compute glyph+label+key budget against the panel width, not the full terminal width.

**Primary recommendation:** Use `box style: %{border: :single, border_fg: theme.border.fg}` wrapping a `column` of `text/2` rows for both Navigation and Oneliners panels. Drive both panels from a single `destinations` list computed once at the top of `render/1`. Pass that same list through to a separate `actions` derivation for the command bar. This is three function-level changes to the existing 320-line module.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Destination visibility (B/C/A/M/S/Q) | Screen (`MainMenu.render/1`) | `ShellVisibility` predicates | Screen computes once, passes to both body and command bar |
| Action visibility (O/H/↑↓) | Screen (`MainMenu.render/1`) | `Bodyguard.permit?` for H | Actions are ephemeral UI state, not stored |
| Panel border + layout | Raxol DSL (`box`, `split_pane`) | — | No custom layout primitive needed |
| Glyph + right-aligned key row | Screen private helper | `TextWidth.pad_trailing/display_width` | Row formatting stays in MainMenu; TextWidth owns measurement |
| Oneliner clipping | Existing `clip/2` (wraps `TextWidth.slice_to_width/2`) | — | Already wired at `main_menu.ex:318-320` |
| Role-gating (render) | `ShellVisibility` predicates | — | Centralized in `shell_visibility.ex` |
| Authorization (H action) | `Bodyguard.permit?/4` | `Foglet.Authorization` | `:hide_oneliner` in `@mod_site_actions` at `authorization.ex:58` |
| Chrome framing | `ScreenFrame.render/4` | — | Unchanged; Phase 18 invariant |
| Size contracts | `layout_smoke_test.exs` `apply_at_size/2` | `Engine.apply_layout/2` | Pre-existing harness; Phase 19 extends existing block |

---

## Standard Stack

### Core (all already in repo — no new dependencies)

| Module | File | Purpose | Why Use |
|--------|------|---------|---------|
| `Raxol.Core.Renderer.View` (DSL) | `import` in screen | `box`, `column`, `row`, `text`, `split_pane`, `divider` | Only layout DSL in repo; all screens use it |
| `Foglet.TUI.TextWidth` | `lib/foglet_bbs/tui/text_width.ex` | `display_width/1`, `slice_to_width/2`, `pad_trailing/2`, `truncate/3` | Unicode-safe column math; already used by MainMenu at line 319 |
| `Foglet.TUI.Theme` | `lib/foglet_bbs/tui/theme.ex` | Theme slot access (`theme.border.fg`, `theme.primary.fg`, `theme.accent`, etc.) | Mandatory; no hardcoded color atoms per D-07/D-09 |
| `Foglet.TUI.Screens.ShellVisibility` | `lib/foglet_bbs/tui/screens/shell_visibility.ex` | `account_visible?/1`, `moderation_visible?/1`, `sysop_visible?/1` | Single source of truth for role gating |
| `Foglet.TUI.Widgets.Chrome.ScreenFrame` | `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex` | `render/4` — outer chrome, CommandBar, StatusBar | Unchanged entry point |
| `Foglet.Authorization` | `lib/foglet_bbs/authorization.ex` | `Bodyguard.permit?` for `:hide_oneliner` gate | `:hide_oneliner` confirmed in `@mod_site_actions` (line 58) |

### Raxol DSL Primitives in Play

| DSL Function | What It Does | Relevant Options |
|---|---|---|
| `box do ... end` | Container with border, padding | `border: :single`, `border_fg: theme.border.fg` |
| `column do ... end` | Vertical stack | `gap: 0` |
| `split_pane/1` | Two-pane horizontal split | `direction: :horizontal`, `ratio: {N, M}`, `min_size: N` |
| `text/2` | Styled text | `fg:`, `style:` |
| `divider/1` | Horizontal rule | `char:`, `style:` |

**[VERIFIED: `docs/raxol/getting-started/WIDGET_GALLERY.md`]** — `box`, `column`, `split_pane`, `text`, `divider` are all Layout DSL functions; `box` border styles include `:single`.

**[VERIFIED: `lib/foglet_bbs/tui/screens/main_menu.ex:70-76`]** — `split_pane(direction: :horizontal, ratio: {2, 3}, min_size: 24, children: [menu_panel, oneliners_panel])` is the only horizontal split callsite in the TUI; Phase 19 must tune this, not replace it.

---

## Architecture Patterns

### System Architecture Diagram

```
state (current_user, recent_oneliners, selected_oneliner_index, terminal_size)
  │
  └── MainMenu.render/1
        │
        ├── destinations = visible_destinations(user)       ← single computation
        │     │  ShellVisibility predicates
        │     └── [{key, glyph, label}, ...]
        │
        ├── actions = visible_actions(state, destinations)  ← derived from state
        │     │  Bodyguard.permit? for H
        │     └── grouped command list
        │
        ├── nav_panel =
        │     box(border: :single) do
        │       column do [text("Navigation"), ...nav_rows(destinations, theme)] end
        │     end
        │
        ├── oneliners_panel =
        │     box(border: :single) do
        │       column do [text("Oneliners"), ...oneliner_rows(state, theme)] end
        │     end
        │
        ├── content =
        │     split_pane(direction: :horizontal, ratio: {2,3}, min_size: N,
        │                children: [nav_panel, oneliners_panel])
        │
        └── ScreenFrame.render(state, "Main Menu", content, actions)
              │
              ├── StatusBar (breadcrumb + status atoms)
              ├── content (split pane)
              └── CommandBar (actions groups — no destinations)
```

### Recommended Module Structure

The module stays in one file. No sibling `state.ex` is needed (screen remains stateless for destinations per D-02). Internal structure:

```
lib/foglet_bbs/tui/screens/main_menu.ex
  # Module constants (existing + tuned)
  @base_destinations, @logout_destination  # replaces @base_items / @logout_item
  @oneliner_display_limit, @oneliner_handle_limit, @oneliner_body_limit

  # Public API (Foglet.TUI.Screen behaviour — unchanged)
  render/1
  handle_key/2   # 11 clauses — unchanged structurally

  # Private: destination/action computation
  visible_destinations/1        # replaces visible_menu_items/1
  visible_actions/1             # replaces visible_menu_keys/1
  command_group/3               # existing helper — keep
  command_priority/2            # existing helper — keep

  # Private: panel builders
  nav_panel/3   (destinations, theme, panel_width)  # NEW
  nav_row/3     (destination, theme, panel_width)   # NEW
  oneliners_panel/3 (state, theme, panel_width)     # refactored from existing column

  # Private: oneliner helpers (existing — keep)
  oneliner_rows/2, oneliner_row/1, update_selected_oneliner/2,
  selected_hideable_oneliner/1, hideable_oneliner?/2,
  visible_oneliners/1, selected_oneliner_index/2, normalize_index/1,
  clamp/3, user_handle/1, single_line/1, clip/2
```

### Pattern 1: Destinations-vs-Actions Split (D-01 / D-04)

**What:** Compute the destinations list once; derive the actions list from the same state. The body and command bar cannot drift because they read from the same single computation.

**When to use:** Entry point of `render/1`; nowhere else.

**Example (adapted from existing code at `main_menu.ex:52-77`):**

```elixir
# Source: lib/foglet_bbs/tui/screens/main_menu.ex (to be refactored)
def render(state) do
  user = state.current_user
  theme = Theme.from_state(state)

  # D-01: single computation — both panels derive from this
  destinations = visible_destinations(user)
  actions = visible_actions(state)

  nav_panel = nav_panel(destinations, theme)
  oneliners_panel = oneliners_panel(state, theme)

  content =
    split_pane(
      direction: :horizontal,
      ratio: {2, 3},
      min_size: 24,      # planner tunes for 64x22 fit
      children: [nav_panel, oneliners_panel]
    )

  ScreenFrame.render(state, "Main Menu", content, actions)
end
```

### Pattern 2: Boxed Panel with Right-Aligned Key Column (D-07 / D-08 / D-12)

**What:** Each Navigation row is `glyph + space + label + right-padding + key`, where padding is computed via `TextWidth.pad_trailing/2` to flush the key character to the panel's right margin. The panel_width must be derived from the split_pane allocation, not the terminal width.

**Key insight:** `split_pane` with `ratio: {2, 3}` and terminal width `W` gives the left panel roughly `(W - 4 - 1) * 2 / 5` inner columns (subtract ScreenFrame outer border of 2, split_pane separator of 1, then apply ratio). The `box` border itself takes 2 more columns. So for 64-wide: `(64 - 5) * 2 / 5 = 23` columns; the left panel inner width is ~21. This tight budget likely means the right-aligned key column must fall back to ASCII `[K]` rows to stay flush — see **Pitfall 1**.

**Example (pattern for a nav row):**

```elixir
# Source: pattern from lib/foglet_bbs/tui/widgets/list/list_row.ex:97-113
# (render_with_metadata uses the same pad_trailing → right-align technique)
defp nav_row({key, glyph, label}, theme, panel_width) do
  prefix = "#{glyph} #{label}"
  prefix_width = TextWidth.display_width(prefix)
  key_width = TextWidth.display_width(key)
  # right-align: pad so key lands at column panel_width
  padding = TextWidth.pad_trailing("", max(panel_width - prefix_width - key_width, 1))
  text(prefix <> padding <> key, fg: theme.primary.fg)
end
```

### Pattern 3: Boxed Panel DSL (D-07 / D-12 Claude's Discretion)

**What:** Use `box do ... end` with `border: :single` and `border_fg: theme.border.fg` to produce the boxed visual. Raxol `box` handles the border rendering; no custom border widget needed.

**When to use:** Wrap both Navigation and Oneliners columns.

**Example:**

```elixir
# Source: lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex:37
# (ScreenFrame uses box with border: :single already — identical DSL call)
box style: %{border: :single, border_fg: theme.border.fg} do
  column style: %{gap: 0} do
    [text("Navigation", fg: theme.title.fg) | nav_rows]
  end
end
```

**[VERIFIED: `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex:37`]** — `box style: %{border: :single, padding: 1, border_fg: theme.border.fg}` is the exact call used by ScreenFrame. Navigation and Oneliners panels use the same idiom without the `padding: 1`.

### Pattern 4: Command Group Construction (existing — unchanged)

**What:** The existing `command_group/3` and `command_priority/2` helpers in `main_menu.ex:194-207` already produce the correct `%{label, commands: [%{key, label, priority}]}` shape that `CommandBar.normalize_groups/1` expects. Phase 19 reuses them for the actions list.

**[VERIFIED: `lib/foglet_bbs/tui/screens/main_menu.ex:188-207`]** — `visible_menu_keys/1` already calls `command_group/3`. Phase 19 just narrows its input from destinations+actions to actions-only.

### Anti-Patterns to Avoid

- **Parallel visibility computation:** Don't compute destination visibility separately in `visible_destinations/1` and again in `visible_actions/1`. Compute once at the top of `render/1` or pass the destinations list into `visible_actions/1` as context.
- **String.length for column math:** All alignment math must use `TextWidth.display_width/1` because glyphs like `●` and `✎` may measure wider than one byte suggests.
- **Hardcoded color atoms:** No `:green`, `:cyan`, etc. in text calls. Route through `theme.primary.fg`, `theme.border.fg`, `theme.title.fg`, etc.
- **Touching `visible_menu_items`/`visible_menu_keys` name-first:** The functions can be renamed, but `handle_key/2` must stay structurally identical — do not add or remove clauses. Role gates in `handle_key/2` already test `ShellVisibility` before acting.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | File |
|---------|-------------|-------------|------|
| Unicode-safe column width | Custom String.length math | `TextWidth.display_width/1` + `TextWidth.pad_trailing/2` | `lib/foglet_bbs/tui/text_width.ex` |
| Right-align key within a width budget | Manual space padding | `TextWidth.pad_trailing("", max(budget - used, 1))` | `lib/foglet_bbs/tui/text_width.ex:89-107` |
| Oneliner text clipping | Custom truncation | `TextWidth.slice_to_width/2` (already in `clip/2` at `main_menu.ex:318`) | `lib/foglet_bbs/tui/text_width.ex:44-48` |
| Panel border box | Custom border drawing | `box style: %{border: :single, border_fg: ...}` DSL | Raxol DSL, pattern in `chrome/screen_frame.ex:37` |
| Two-pane horizontal layout | Manual column math | `split_pane(direction: :horizontal, ...)` | `lib/foglet_bbs/tui/screens/main_menu.ex:70` |
| Command bar rendering | Custom footer widget | `Chrome.CommandBar.render/3` via `ScreenFrame.render/4` | `lib/foglet_bbs/tui/widgets/chrome/command_bar.ex` |
| Role visibility logic | Inline role checks | `ShellVisibility.account_visible?/1` etc. | `lib/foglet_bbs/tui/screens/shell_visibility.ex` |
| H authorization | Custom role check | `Bodyguard.permit?(Authorization, :hide_oneliner, user, :site)` | `lib/foglet_bbs/authorization.ex:58` |
| Render tree text collection in tests | Bespoke walker | `collect_text_values/1` from `import Foglet.TUI.RenderHelpers` | `test/support/foglet/tui/render_helpers.ex:28` |
| Positioned-render at specific sizes | Custom layout harness | `apply_at_size(tree, {w, h})` helper in `layout_smoke_test.exs:72` | `test/foglet_bbs/tui/layout_smoke_test.exs:72` |

**Key insight:** The codebase has a complete tool for every sub-problem in Phase 19. There is no gap that requires a new library or a new shared widget. The risk is not "missing primitive" — it is "wrong width budget for the right-align math" (see Pitfall 1).

---

## Common Pitfalls

### Pitfall 1: Panel Inner Width Miscalculation for Right-Aligned Key Column

**What goes wrong:** Right-aligned key characters land outside the box border or overlap the split pane separator. The `nav_row` helper computes `panel_width` incorrectly by using `state.terminal_size` directly instead of the post-split-pane panel allocation.

**Why it happens:** `split_pane` allocates width at layout time; the screen module only knows the raw terminal width. The math is approximately `(terminal_width - chrome_overhead) * ratio_numerator / ratio_sum - border_overhead`. At 64 wide with `ratio: {2, 3}` and ScreenFrame border: roughly `(64 - 4) * 2 / 5 - 2 = 22` inner columns for the Navigation panel. Glyphs consume 2 cells each; a row like `● Boards     B` must fit in 22 columns.

**How to avoid:** Either (a) hardcode a conservative `@nav_panel_budget` that is proven against the 64x22 positioned-render test, or (b) accept the ASCII fallback (D-10) at 64x22 and confirm it via the smoke test. Option (a) is simpler for Phase 19. A safe budget for the 64-wide case is 20 inner columns (leaves headroom for `border: :single` consuming 2 columns).

**Warning signs:** Positioned-render test at `{64, 22}` shows two text elements sharing the same `{x, y}` — the key character has wrapped onto the previous row's coordinate.

### Pitfall 2: Destination Keys Appearing in Command Bar (Dedup Failure)

**What goes wrong:** `B`, `C`, `A`, `M`, `S`, or `Q` appear in a command bar group, violating D-01/D-04.

**Why it happens:** The old `visible_menu_keys/1` put ALL visible keys into the command bar. If the refactor copies the old shape instead of replacing it, destinations leak back in.

**How to avoid:** D-01 mandates a single source of truth. The canonical test is: assert that `collect_text_values(MainMenu.render(state))` contains `"B"` in the body AND does NOT contain `"Boards"` (or any other destination label) in any text node that also contains a command-bar group label like `"Actions"` or `"Navigate"`. The existing test at line 376 (`"  [#{key}] #{menu_label}" in texts`) must be updated because row format changes, but the invariant does not.

**Warning signs:** `mix precommit` passes but the test `"none of B/C/A/M/S appear in any command-bar group"` (D-15) fails.

### Pitfall 3: `Welcome back, alice.` Assertion in Existing Tests (D-11)

**What goes wrong:** The existing test at `main_menu_test.exs:231` asserts `"Welcome back, alice." in texts`. Phase 19 removes this line (D-11). The test must be updated to assert the new Navigation panel header instead.

**Why it happens:** Tests were written against current behavior; a direct refactor without updating the test will produce a failing assertion after the body change.

**How to avoid:** The plan must include an explicit task to update the `"render includes main menu owned text rows"` test block at line 230–237 to assert `"Navigation"` (panel header) and the new row format, and to remove the `"Welcome back, alice."` assertion.

**Warning signs:** `mix test test/foglet_bbs/tui/screens/main_menu_test.exs` fails on line 231 after the body refactor.

### Pitfall 4: `layout_smoke_test.exs` Main Menu Block Expects Old Text (Pitfall 3 extension)

**What goes wrong:** The existing `layout_smoke_test.exs:332` asserts `Enum.any?(texts, &String.contains?(&1, "Welcome"))`. Phase 19 removes the welcome line.

**Why it happens:** Same root cause as Pitfall 3 — the existing smoke test for Main Menu was written against current body text.

**How to avoid:** The plan must include updating the Main Menu block at `layout_smoke_test.exs:318-351` to assert `"Navigation"` panel presence instead of `"Welcome"`, and extending it with the `[{64,22},{80,24},{132,50}]` three-size block per D-16.

**Warning signs:** `mix test test/foglet_bbs/tui/layout_smoke_test.exs` fails on line 332 after body refactor.

### Pitfall 5: Glyph Cell-Width Breaks Row Alignment on Real SSH Terminals

**What goes wrong:** Glyphs like `●` (U+25CF) render as 1 cell in most terminals but as 2 cells on some East Asian font configurations. The positioned-render test passes (layout engine measures 1 cell) but the terminal shows misalignment.

**Why it happens:** `Raxol.UI.TextMeasure` uses Unicode East Asian Width tables; `●` is classified as Neutral (1 cell) by EAW but some terminal emulators treat it as ambiguous-width. This is the same dynamic Phase 18 resolved with ASCII fallback for breadcrumbs (D-04 of Phase 18 context).

**How to avoid:** D-10 already provides the fallback gate: if positioned-render tests fail at 64x22 with glyphs, fall back to ASCII rows. The plan should implement the glyph path first, run the positioned-render test, and switch to ASCII only if the test shows overlap.

**Warning signs:** `layout_smoke_test.exs` passes for ASCII but the `{64, 22}` assertion triggers text-overlap failure when glyphs are present.

---

## Code Examples

### Example 1: Existing `split_pane` call to tune (current shape)

```elixir
# Source: lib/foglet_bbs/tui/screens/main_menu.ex:69-75
content =
  split_pane(
    direction: :horizontal,
    ratio: {2, 3},
    min_size: 24,
    children: [menu_panel, oneliners_panel]
  )
```

Phase 19 keeps this call; the planner tunes `ratio` and `min_size` to fit both boxed panels at 64x22.

### Example 2: `box` with `border: :single` — existing idiom from ScreenFrame

```elixir
# Source: lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex:37
box style: %{border: :single, padding: 1, border_fg: theme.border.fg} do
  column style: %{gap: 0, justify_content: :space_between} do
    [...]
  end
end
```

Navigation and Oneliners panels use the same `box` primitive without `padding: 1`.

### Example 3: Right-align metadata — existing pattern in `ListRow`

```elixir
# Source: lib/foglet_bbs/tui/widgets/list/list_row.ex:121-142
defp compute_parts(marker, title, metadata, width) do
  marker_width = TextWidth.display_width(marker)
  metadata_width = TextWidth.display_width(metadata)
  min_gap = 2

  max_title_body = max(width - marker_width - min_gap - metadata_width, 0)
  title_body = truncate_title(title, max_title_body)

  title_part = marker <> title_body
  title_part_width = marker_width + TextWidth.display_width(title_body)

  padding_width =
    (width - title_part_width - metadata_width)
    |> max(0)
    |> min(width)

  padding_part = TextWidth.pad_trailing("", padding_width)
  {title_part, padding_part, metadata}
end
```

The `nav_row` helper uses the same left-part + padding + right-part pattern. `title` = `glyph + " " + label`; `metadata` = key character.

### Example 4: Positioned-render harness at multiple sizes — existing pattern

```elixir
# Source: test/foglet_bbs/tui/layout_smoke_test.exs:130-182
# (Chrome V2 size contracts block — Phase 19 extends layout_smoke_test.exs with same shape)
for {width, height} <- [{64, 22}, {80, 24}, {132, 50}] do
  state = %{ ... terminal_size: {width, height} }

  positioned =
    SomeScreen.render(state)
    |> apply_at_size({width, height})

  elements = text_elements(positioned)

  for element <- elements do
    text = Map.fetch!(element, :text)
    assert element.x >= 0
    assert element.y >= 0
    assert element.x + TextWidth.display_width(text) <= width
  end

  # Phase 19 addition: assert both panels present, no {x,y} overlap
end
```

### Example 5: Existing command-group construction (keep, narrow input)

```elixir
# Source: lib/foglet_bbs/tui/screens/main_menu.ex:188-207
defp visible_menu_keys(state) do
  user = state.current_user
  oneliner = if user, do: [@oneliner_key], else: []
  hide_oneliner = if selected_hideable_oneliner(state), do: [{"H", "Hide oneliner"}], else: []

  [
    command_group("Navigate", @base_keys, 0),          # ← Phase 19 REMOVES: B/C go to body
    command_group("Actions", account ++ ... ++ hide_oneliner ++ oneliner, 10),  # ← only O/H remain
    command_group("System", [@logout_key], 0)           # ← Phase 19 REMOVES: Q goes to body
  ]
  |> Enum.reject(&(&1.commands == []))
end
```

Phase 19 replaces `visible_menu_keys/1` with `visible_actions/1`. The new function passes only `oneliner` + `hide_oneliner` + optional `↑/↓ Select` to command groups; `@base_keys`, account/mod/sysop, and `@logout_key` are removed from the command bar entirely.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | ExUnit (Elixir built-in) |
| Config file | `mix.exs` — no separate test config |
| Quick run command | `rtk mix test test/foglet_bbs/tui/screens/main_menu_test.exs` |
| Full suite command | `rtk mix precommit` (compile + format + Credo + Sobelow + Dialyzer + test) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| HOME-01 | Role-visible destination rows in body | unit | `rtk mix test test/foglet_bbs/tui/screens/main_menu_test.exs` | ✅ extends existing |
| HOME-01 | Direct hotkeys B/C/A/M/S/Q preserve behavior | unit | same | ✅ extends existing |
| HOME-01 | Enter returns `:no_match` for destinations | unit | same | ✅ extends existing (line 215) |
| HOME-01 | O/H/↑↓ in command bar only; B/C/A/M/S/Q absent | unit | same | ❌ Wave 0 gap |
| HOME-01 | H absent for regular user even with hideable oneliner selected | unit | same | ✅ extends existing (line 175) |
| HOME-01 | H present for mod/sysop with hideable focused | unit | same | ✅ extends existing (line 188) |
| HOME-02 | Nil/empty oneliners render panel header + empty state | unit | same | ✅ extends existing (line 73) |
| HOME-02 | More than display_limit rows capped | unit | same | ✅ extends existing (line 101) |
| HOME-02 | Long Unicode oneliner clipped without multiline overflow | unit | same | ✅ extends existing (line 118) |
| HOME-03 | 64x22 / 80x24 / 132x50 both panels side-by-side, no overlap | smoke | `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` | ❌ Wave 0 gap |
| HOME-03 | Oneliner rows clipped to panel inner width | smoke | same | ❌ Wave 0 gap |

### Wave 0 Gaps

- [ ] `test/foglet_bbs/tui/screens/main_menu_test.exs` — add `"command bar non-duplication"` test block: assert none of `B/C/A/M/S/Q` appear in command-bar group text nodes.
- [ ] `test/foglet_bbs/tui/screens/main_menu_test.exs` — update `"render includes main menu owned text rows"` (line 230-237): remove `"Welcome back, alice."` assertion; add `"Navigation"` panel header assertion; update row format assertions to match `glyph + label + key` shape.
- [ ] `test/foglet_bbs/tui/layout_smoke_test.exs` — update existing Main Menu block (line 318-351): remove `"Welcome"` assertion; add `"Navigation"` assertion; extend to `[{64,22},{80,24},{132,50}]` three-size block per D-16 with both-panels-visible and no-overlap assertions.

### Sampling Rate

- **Per task commit:** `rtk mix test test/foglet_bbs/tui/screens/main_menu_test.exs test/foglet_bbs/tui/layout_smoke_test.exs`
- **Per wave merge:** `rtk mix test test/foglet_bbs/tui/`
- **Phase gate:** `rtk mix precommit` full green before `/gsd-verify-work`

---

## Open Questions

1. **Split pane ratio and min_size for 64x22**
   - What we know: Current ratio is `{2, 3}`, `min_size: 24`. ScreenFrame outer border consumes 4 columns. At 64 wide, left panel gets roughly `(64-4)*2/5 = 24` columns minus the box border = ~22 inner. That fits a `glyph + label + key` row like `● Boards       B` (14 cells) with headroom.
   - What's unclear: Whether the `min_size: 24` value causes the right panel to steal space from the left at 64-wide, leaving the left panel too narrow for boxed glyphs.
   - Recommendation: Planner should drop `min_size` to `16` or `18` and run the positioned-render test. If glyph rows overflow at `min_size: 24`, reduce it. The test is cheap.

2. **`↑/↓ Select` command bar hint key literal**
   - What we know: D-04 says show `↑/↓ Select` when `recent_oneliners` is non-empty. The existing `Normalizer` classifies `"↑/↓"` as a navigate command (line 102: `key in ["j/k", "↑/↓", "up/down", "enter", "return"]`).
   - What's unclear: Whether the planner wants the hint in a "Navigate" group (Normalizer default) or an explicit "Actions" group to keep it with O and H.
   - Recommendation: Use an explicit `command_group("Select", [{"↑/↓", "Select", 20}], 20)` to keep the three actions grouped logically. Low priority — the planner can decide.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `box style: %{border: :single}` produces a single-line box border in Raxol's layout engine (not just a style hint) | Standard Stack | Low — ScreenFrame already uses it and the positioned-render harness confirms box borders appear. |
| A2 | `split_pane` with `min_size` below the natural half of 64-4=60 will reduce left panel width proportionally rather than collapsing it | Common Pitfalls | Medium — if engine enforces min_size as a floor for the smaller pane, ratio math changes. Positioned-render test will catch this. |

**All other claims are VERIFIED from repo source files read in this session.**

---

## Sources

### Primary (HIGH confidence — verified from repo files this session)

- `lib/foglet_bbs/tui/screens/main_menu.ex` — complete current implementation read
- `lib/foglet_bbs/tui/screens/shell_visibility.ex` — API surface confirmed
- `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex` — `render/4` signature and `box` usage confirmed
- `lib/foglet_bbs/tui/widgets/chrome/command_bar.ex` — grouped command contract confirmed; `normalize_groups/1` and empty-group rejection confirmed
- `lib/foglet_bbs/tui/widgets/chrome/normalizer.ex` — `↑/↓` navigation classification confirmed
- `lib/foglet_bbs/tui/theme.ex` — all slot keys confirmed; `from_state/1` confirmed
- `lib/foglet_bbs/tui/text_width.ex` — `display_width/1`, `slice_to_width/2`, `pad_trailing/2`, `truncate/3` confirmed
- `lib/foglet_bbs/tui/widgets/list/list_row.ex` — right-align pattern confirmed at lines 121-142
- `test/foglet_bbs/tui/screens/main_menu_test.exs` — full test surface read; stale assertions identified
- `test/foglet_bbs/tui/layout_smoke_test.exs` — full test read; `apply_at_size/2` helper at line 72 confirmed; existing Main Menu block at lines 318-351 confirmed
- `test/support/foglet/tui/render_helpers.ex` — `collect_text_values/1` confirmed
- `docs/raxol/getting-started/WIDGET_GALLERY.md` — `box`, `split_pane`, `column`, `text`, `divider` DSL confirmed
- `.planning/phases/19-main-menu-dashboard/19-CONTEXT.md` — all locked decisions read
- `SCREENS.md lines 255-304` — visual target confirmed; Activity panel confirmed OUT

---

## Metadata

**Confidence breakdown:**

| Area | Level | Reason |
|------|-------|--------|
| Standard Stack | HIGH | Every module read directly from source |
| Architecture | HIGH | Current MainMenu anatomy fully known; delta is small |
| Dedup pattern | HIGH | `visible_menu_items/visible_menu_keys` split point clearly identified |
| Panel border | HIGH | ScreenFrame uses identical `box` DSL; WIDGET_GALLERY confirms options |
| Right-align math | HIGH | `ListRow.compute_parts` is proven pattern; same technique |
| Pitfalls | HIGH | Stale test assertions verified at specific line numbers |
| Width budget at 64x22 | MEDIUM | Width math is approximate — split_pane allocation is runtime; positioned-render test will confirm |

**Research date:** 2026-04-25
**Valid until:** 2026-05-25 (stable codebase; no fast-moving dependencies)

---

## What the Planner Now Knows That They Didn't Before

1. **Exact stale assertions to fix:** Lines 231 and 332 in the two test files will fail immediately after the body refactor; the plan must include updating them as part of Wave 0 or the first implementation task.

2. **`visible_menu_items` and `visible_menu_keys` are not structurally separate today** — they share no common data structure. Phase 19's primary implementation move is to extract a `visible_destinations/1` that returns `[{key, glyph, label}]` triples, then feed that to the body AND derive the actions list separately. This is a ~40-line refactor of two private functions.

3. **The panel border pattern already exists in ScreenFrame** (`box style: %{border: :single, border_fg: theme.border.fg}`). No new widget or helper is needed.

4. **Right-aligned key column math** is proven in `ListRow.compute_parts/4` (lines 121-142) and reusable via `TextWidth.pad_trailing/2`. The nav_row helper is ~5 lines.

5. **Width budget at 64x22** is tight (~22 inner columns for the Navigation panel with current ratio). A row like `● Browse Boards    B` won't fit; rows like `● Boards    B` or `[B] Boards    →` will. The planner should plan for the short-label glyph path first, with ASCII fallback if the positioned-render test fails.

6. **`split_pane` is the only horizontal layout primitive in the TUI** (confirmed by grep across all screen files) — it must not be replaced.

7. **`↑/↓ Select` command group placement** is an open question; planner can decide whether it lives in "Navigate" (Normalizer default) or "Select" (explicit group with O and H).
