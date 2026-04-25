# Phase 16: Unicode Width Foundation - Research

**Researched:** 2026-04-25  
**Domain:** Terminal Unicode display-width helpers and TUI layout hardening  
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

## Implementation Decisions

### Text Width API
- **D-01:** Add `Foglet.TUI.TextWidth` under the TUI namespace as the shared Foglet API for terminal display-width behavior.
- **D-02:** Delegate measurement and display-width splitting to `Raxol.UI.TextMeasure`; do not invent an independent width policy unless tests prove Raxol cannot satisfy the locked Phase 16 cases.
- **D-03:** Add Foglet convenience functions for display width, ellipsis truncation, left/right padding, and display-width splitting or slicing so local TUI code does not call Raxol primitives directly in every widget.

### Migration Scope
- **D-04:** Must migrate `ListRow.render_with_metadata/6`, existing `Chrome.KeyBar`, `Modal.word_wrap/2`, reusable clipping/truncation helpers such as main-menu clipping, and composer cursor insertion in `Compose.render_input/4`.
- **D-05:** Keep the phase focused on current foundation paths. Broader Account, Sysop, Moderation, and other screen string operations should only migrate where cheap through the new helper or be documented as character-count/non-layout-sensitive paths.
- **D-06:** Do not start Chrome V2, theme/mode contracts, rich row redesign, board/post/composer facelifts, browser UI, or domain behavior changes in this phase.

### Character Count Boundaries
- **D-07:** Post body length, thread title length, verification-code length, and similar product validation rules remain character-count policies, not terminal display-width limits.
- **D-08:** Existing `String.length/1` and `String.slice/3` usage may remain in character-count enforcement paths when documented and tested as intentionally separate from terminal layout width.

### Test Strategy
- **D-09:** Add helper-level tests covering ASCII, accented Latin, combining marks, CJK, and the milestone glyph set `●`, `◆`, `▸`, `▾`, `✓`, `×`.
- **D-10:** Convert or add focused widget tests that measure flattened rendered output by `Foglet.TUI.TextWidth.display_width/1`, while preserving existing ASCII layout assertions where practical.
- **D-11:** Add representative size-contract coverage for 64x22, 80x24, and at least one wide/tall terminal across row, chrome/footer, modal, and composer paths.
- **D-12:** Lock Phase 16 behavior to Raxol's current width model for the milestone glyph set; do not expand scope into terminal/font compatibility research.

### Claude's Discretion
- Exact helper function names, arities, and internal implementation details are planner discretion as long as the shared API clearly covers measurement, truncation, padding, and display-width splitting/slicing.
- Exact structure of the source-level scan or equivalent focused test is planner discretion, but it must prove migrated layout-sensitive paths no longer use direct grapheme-count string operations for terminal layout width.

### Folded Todos
None.

### Deferred Ideas (OUT OF SCOPE)

## Deferred Ideas

None — analysis stayed within phase scope.

### Reviewed Todos (not folded)
None.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| WIDTH-01 | TUI widgets can measure, truncate, pad, and slice terminal text by display width through one shared helper. | Use `Foglet.TUI.TextWidth` wrapping `Raxol.UI.TextMeasure` plus local convenience functions. [VERIFIED: .planning/REQUIREMENTS.md] [VERIFIED: vendor/raxol/lib/raxol/ui/text_measure.ex] |
| WIDTH-02 | Layout-sensitive row, chrome, clipping, and composer cursor paths use the shared display-width helper instead of direct length/slice assumptions. | The scan found direct grapheme-count width logic in `ListRow`, `Modal`, `Compose`, and `MainMenu.clip/2`. [VERIFIED: rg codebase scan] |
| WIDTH-03 | Width tests cover ASCII, accented Latin, combining marks, CJK text, and the milestone glyph set from `SCREENS.md`. | `SCREENS.md` names the glyph set and Raxol exposes display-width functions to assert current model behavior. [VERIFIED: SCREENS.md] [CITED: https://hexdocs.pm/raxol/Raxol.UI.TextMeasure.html] |
| WIDTH-04 | Existing ASCII-heavy screens keep their current layout behavior after width hardening. | Existing `ListRow`, modal, compose, and layout smoke tests provide ASCII baselines to preserve while adding width-aware assertions. [VERIFIED: test/foglet_bbs/tui] |
| WIDTH-05 | Facelifted widgets and screens have size-contract coverage for 64x22, 80x24, and at least one wide/tall terminal layout. | Existing layout smoke tests already drive screen render trees through `Raxol.UI.Layout.Engine.apply_layout/2`; extend that pattern to multiple dimensions. [VERIFIED: test/foglet_bbs/tui/layout_smoke_test.exs] |
</phase_requirements>

## Summary

Phase 16 should standardize display-width behavior in one Foglet-owned helper and migrate only the current layout-sensitive string operations that affect aligned terminal output. [VERIFIED: .planning/phases/16-unicode-width-foundation/16-CONTEXT.md] The established pattern in Raxol is a framework-level text-measurement facade used by layout, rendering, wrapping, tables, buttons, and text components instead of `String.length/1` for terminal-cell calculations. [VERIFIED: rg codebase scan] [CITED: https://hexdocs.pm/raxol/Raxol.UI.TextMeasure.html]

The correct implementation is not a new Unicode library search. [VERIFIED: .planning/phases/16-unicode-width-foundation/16-CONTEXT.md] Foglet should wrap `Raxol.UI.TextMeasure.display_width/1` and `split_at_display_width/2`, then add local helpers for ellipsis truncation, padding, and fit/slice operations so Foglet widgets do not duplicate layout math. [VERIFIED: vendor/raxol/lib/raxol/ui/text_measure.ex] Keep product validation paths on character/grapheme semantics where the context says length limits are not terminal display-width limits. [VERIFIED: .planning/phases/16-unicode-width-foundation/16-CONTEXT.md]

**Primary recommendation:** Implement `Foglet.TUI.TextWidth` first, test it against the locked glyph/model cases, then migrate `ListRow`, `KeyBar`, `Modal`, `Compose`, and `MainMenu` to consume it. [VERIFIED: .planning/phases/16-unicode-width-foundation/16-CONTEXT.md] [VERIFIED: rg codebase scan]

## Project Constraints (from CLAUDE.md)

- Foglet is SSH-first and the terminal UI is the primary product surface; do not add end-user browser workflows for this phase. [VERIFIED: CLAUDE.md]
- Use `rtk` as the shell command prefix in this repository. [VERIFIED: CLAUDE.md]
- Before TUI/Raxol work, read `docs/raxol/getting-started/WIDGET_GALLERY.md` and `lib/foglet_bbs/tui/widgets/README.md`. [VERIFIED: CLAUDE.md]
- Keep UI behavior in `Foglet.TUI.App` and screens; keep reusable display in widgets and helpers. [VERIFIED: CLAUDE.md]
- Widgets route colors through `Foglet.TUI.Theme`, pass theme explicitly, and keep render functions pure over already-loaded state. [VERIFIED: CLAUDE.md]
- For TUI flows, keep global navigation in `Foglet.TUI.App`, screen-local state in screens or sibling state modules, data/mutations in domain contexts, off-process work in `Foglet.TUI.Command`/Raxol commands, and reusable display in widgets. [VERIFIED: CLAUDE.md]
- Use focused tests under mirrored `test/foglet_bbs/...` paths. [VERIFIED: CLAUDE.md]
- Use `start_supervised!/1` for processes in tests; avoid `Process.sleep/1` and `Process.alive?/1`. [VERIFIED: CLAUDE.md]
- Run `mix precommit` when code changes are complete. [VERIFIED: CLAUDE.md]

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|--------------|----------------|-----------|
| Terminal display-width measurement | TUI helper layer | Raxol framework | Foglet owns its local API, while Raxol owns the measured Unicode model. [VERIFIED: 16-CONTEXT.md] [VERIFIED: vendor/raxol/lib/raxol/ui/text_measure.ex] |
| Row/chrome/modal/composer alignment | TUI widgets/screens | Raxol layout engine | Foglet widgets compose strings and rows before Raxol layout positions view trees. [VERIFIED: lib/foglet_bbs/tui/widgets] [VERIFIED: docs/raxol/core/ARCHITECTURE.md] |
| Product length validation | Domain/screen validation paths | TUI display layer | Phase context explicitly keeps product length limits as character-count policies, separate from terminal layout width. [VERIFIED: 16-CONTEXT.md] |
| Multi-size layout verification | Test suite | Raxol layout engine | Existing smoke tests apply `Raxol.UI.Layout.Engine.apply_layout/2` to rendered TUI trees. [VERIFIED: test/foglet_bbs/tui/layout_smoke_test.exs] |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Elixir `String` | 1.19.5 local runtime | Grapheme-aware product string operations and non-layout character policies. | Official `String` functions operate on Unicode graphemes, and this remains correct for product length/count behavior. [VERIFIED: elixir --version] [CITED: https://hexdocs.pm/elixir/String.html] |
| Raxol | path dependency, Hex releases include 2.4.0 | Terminal UI framework and `Raxol.UI.TextMeasure` facade. | Existing project dependency and Raxol docs identify `TextMeasure` as the single source of truth for display-width-sensitive layout. [VERIFIED: mix.exs] [VERIFIED: rtk mix hex.info raxol] [CITED: https://hexdocs.pm/raxol/Raxol.UI.TextMeasure.html] |
| raxol_terminal | locked 2.4.0 | Underlying terminal character handling for Raxol display widths. | `Raxol.UI.TextMeasure` delegates to `Raxol.Terminal.CharacterHandling` when available, and this dependency is locked in `mix.lock`. [VERIFIED: mix.lock] [VERIFIED: vendor/raxol/lib/raxol/ui/text_measure.ex] [CITED: https://hexdocs.pm/raxol_terminal/Raxol.Terminal.CharacterHandling.html] |
| ExUnit | bundled with Elixir 1.19.5 | Helper, widget, and layout smoke tests. | Existing TUI tests use `ExUnit.Case` and mirror `lib/` paths under `test/foglet_bbs`. [VERIFIED: test/foglet_bbs/tui] |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Raxol layout engine | path dependency via Raxol | Render-tree positioning and layout smoke verification. | Use `Raxol.UI.Layout.Engine.apply_layout/2` for multi-size contract tests, matching existing layout smoke patterns. [VERIFIED: test/foglet_bbs/tui/layout_smoke_test.exs] |
| `String.graphemes/1` | Elixir 1.19.5 | Safe iteration over user-perceived characters for helper fallback logic. | Use only where a helper must iterate text; do not treat grapheme count as terminal display width. [CITED: https://hexdocs.pm/elixir/String.html] [CITED: https://www.unicode.org/reports/tr29/] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `Raxol.UI.TextMeasure` | New Unicode width/wcwidth library | Do not add it in Phase 16 because locked decisions require Raxol first and the current project already ships Raxol width APIs. [VERIFIED: 16-CONTEXT.md] |
| `Foglet.TUI.TextWidth` wrapper | Direct Raxol calls in every widget | Direct calls would scatter truncation/padding policy across widgets, contradicting the requirement for one shared helper. [VERIFIED: .planning/REQUIREMENTS.md] |
| Display-width limits for titles/bodies | Existing character-count limits | Product validation semantics are intentionally out of scope for display-width migration. [VERIFIED: 16-CONTEXT.md] |

**Installation:**

```bash
# No new dependency for Phase 16.
# Existing stack is provided by mix.exs and mix.lock.
rtk mix deps.get
```

**Version verification:** `rtk mix hex.info raxol` reported Raxol releases through `2.4.0`; `rtk mix hex.info raxol_terminal` reported locked `2.4.0`; local runtime is Elixir `1.19.5` with Erlang/OTP `28`. [VERIFIED: rtk mix hex.info raxol] [VERIFIED: rtk mix hex.info raxol_terminal] [VERIFIED: elixir --version]

## Architecture Patterns

### System Architecture Diagram

```text
Raxol key/input state + Foglet screen data
        |
        v
Foglet screen/widget render functions
        |
        +--> layout-sensitive text operation?
                 |
                 +-- yes --> Foglet.TUI.TextWidth
                 |              |
                 |              v
                 |       Raxol.UI.TextMeasure
                 |              |
                 |              v
                 |       Raxol.Terminal.CharacterHandling
                 |
                 +-- no --> character-count/product validation path
        |
        v
Raxol view tree
        |
        v
Raxol prepare/layout/render pipeline
        |
        v
SSH terminal output
```

This diagram follows the existing Raxol architecture: application view functions return pure view trees, Raxol prepares and measures text, lays out elements, composes cells, and renders to SSH/terminal backends. [VERIFIED: docs/raxol/core/ARCHITECTURE.md]

### Recommended Project Structure

```text
lib/foglet_bbs/tui/
├── text_width.ex                         # Foglet-owned display-width contract
├── widgets/
│   ├── list/list_row.ex                  # shared helper for metadata rows
│   ├── chrome/key_bar.ex                 # shared helper for command footer text
│   ├── modal.ex                          # shared helper for word wrapping
│   └── compose.ex                        # shared helper for cursor insertion
└── screens/main_menu.ex                  # shared helper for oneliner clipping

test/foglet_bbs/tui/
├── text_width_test.exs                   # helper model tests
├── widgets/list/list_row_test.exs        # width-aware row assertions
├── widgets/chrome/key_bar_test.exs       # command-footer width assertions
├── widgets/modal_test.exs                # display-width wrapping assertions
├── widgets/compose_test.exs              # cursor insertion assertions
└── layout_smoke_test.exs                 # 64x22, 80x24, wide/tall contracts
```

This structure matches existing TUI helper and widget placement conventions. [VERIFIED: CLAUDE.md] [VERIFIED: lib/foglet_bbs/tui/widgets/README.md]

### Pattern 1: Thin Foglet Facade Over Raxol

**What:** `Foglet.TUI.TextWidth` should delegate primitive width and split behavior to `Raxol.UI.TextMeasure`, then expose Foglet convenience functions for common widget needs. [VERIFIED: 16-CONTEXT.md] [VERIFIED: vendor/raxol/lib/raxol/ui/text_measure.ex]

**When to use:** Use this helper for alignment, padding, truncation, wrapping, clipping, and visible cursor placement in terminal cells. [VERIFIED: .planning/REQUIREMENTS.md]

**Example:**

```elixir
defmodule Foglet.TUI.TextWidth do
  @ellipsis "…"

  def display_width(text), do: Raxol.UI.TextMeasure.display_width(to_string(text))

  def split_at(text, width) when width <= 0, do: {"", to_string(text)}
  def split_at(text, width), do: Raxol.UI.TextMeasure.split_at_display_width(to_string(text), width)

  def truncate(text, max_width, opts \\ []) do
    ellipsis = Keyword.get(opts, :ellipsis, @ellipsis)
    text = to_string(text)

    cond do
      max_width <= 0 -> ""
      display_width(text) <= max_width -> text
      display_width(ellipsis) >= max_width -> elem(split_at(ellipsis, max_width), 0)
      true ->
        {prefix, _rest} = split_at(text, max_width - display_width(ellipsis))
        prefix <> ellipsis
    end
  end

  def pad_trailing(text, width) do
    text = to_string(text)
    text <> String.duplicate(" ", max(width - display_width(text), 0))
  end
end
```

Source: Raxol exposes `display_width/1` and `split_at_display_width/2`; Elixir `String` handles graphemes but not terminal cell width. [CITED: https://hexdocs.pm/raxol/Raxol.UI.TextMeasure.html] [CITED: https://hexdocs.pm/elixir/String.html]

### Pattern 2: Keep Layout Tests On Flattened Rendered Text But Measure Display Width

**What:** Existing widget tests flatten Raxol view trees into strings; keep that test style, but assert `TextWidth.display_width(flat) == expected_width` for layout-sensitive rows. [VERIFIED: test/foglet_bbs/tui/widgets/list/list_row_test.exs]

**When to use:** Use for `ListRow`, `KeyBar`, modal wrapping, and screen snippets where x-position/layout matters. [VERIFIED: 16-CONTEXT.md]

**Example:**

```elixir
flat = flatten_text(ListRow.render_with_metadata("漢字 cafe\u0301", "@alice · 2h", false, false, theme(), width: 40))

assert Foglet.TUI.TextWidth.display_width(flat) == 40
assert String.ends_with?(flat, "@alice · 2h")
```

Source: Existing `ListRowTest` flattens text and currently asserts `String.length/1`; Phase 16 should swap the layout-width assertion to the shared helper. [VERIFIED: test/foglet_bbs/tui/widgets/list/list_row_test.exs]

### Pattern 3: Separate Display Width From Character Policies

**What:** `String.length/1`, `String.slice/3`, and `String.split_at/2` may remain where code is editing/counting graphemes for product validation, but not where code computes terminal columns. [VERIFIED: 16-CONTEXT.md] [CITED: https://hexdocs.pm/elixir/String.html]

**When to use:** Keep character-count semantics for post body length, thread title length, verification codes, and form max lengths. [VERIFIED: 16-CONTEXT.md]

**Example:**

```elixir
# Character-count policy: acceptable outside terminal-cell layout.
if String.length(title) > max_title_length do
  {:error, :too_long}
end

# Terminal layout policy: must use TextWidth.
visible_title = Foglet.TUI.TextWidth.truncate(title, available_columns)
```

Source: Phase context explicitly preserves product character-count policies. [VERIFIED: 16-CONTEXT.md]

### Anti-Patterns to Avoid

- **Using `String.length/1` for terminal column math:** `String.length/1` is grapheme-aware, not display-cell-aware, so CJK and some glyphs break alignment. [CITED: https://hexdocs.pm/elixir/String.html] [CITED: https://hexdocs.pm/raxol/Raxol.UI.TextMeasure.html]
- **Calling Raxol width APIs directly across many Foglet widgets:** This scatters Foglet truncation and padding policy and violates the one-helper requirement. [VERIFIED: .planning/REQUIREMENTS.md]
- **Expanding into terminal/font compatibility guarantees:** Unicode East Asian Width itself warns that terminal emulators need tailoring and the property is not an off-the-shelf solution for every modern terminal case, so Phase 16 should test Foglet’s locked glyph set against Raxol’s model. [CITED: https://www.unicode.org/reports/tr11/] [VERIFIED: 16-CONTEXT.md]
- **Migrating product validation limits to display width:** That would change user-facing validation semantics outside the phase boundary. [VERIFIED: 16-CONTEXT.md]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Unicode display-width primitive | Custom East Asian Width or wcwidth tables in Foglet | `Raxol.UI.TextMeasure` via `Foglet.TUI.TextWidth` | Raxol already centralizes display width and the phase locks to that model. [VERIFIED: vendor/raxol/lib/raxol/ui/text_measure.ex] [VERIFIED: 16-CONTEXT.md] |
| Grapheme segmentation | Byte/codepoint slicing by hand | Elixir `String` grapheme functions and Raxol display-width split | Unicode text segmentation has a standard algorithm; Elixir documents `String.graphemes/1` as Extended Grapheme Cluster based. [CITED: https://www.unicode.org/reports/tr29/] [CITED: https://hexdocs.pm/elixir/String.html] |
| Ellipsis truncation per widget | One-off `String.slice(... ) <> "…"` logic | `Foglet.TUI.TextWidth.truncate/2` or `/3` | Widget-local slicing repeats edge cases for ellipsis width, zero/one-column limits, CJK boundaries, and combining marks. [VERIFIED: rg codebase scan] |
| Padding and alignment | `String.pad_leading/2`, `String.pad_trailing/2` for display columns | `Foglet.TUI.TextWidth.pad_leading/2` and `pad_trailing/2` | Built-in string padding uses string length semantics, while display columns require measured cell width. [CITED: https://hexdocs.pm/elixir/String.html] [CITED: https://hexdocs.pm/raxol/Raxol.UI.TextMeasure.html] |
| Terminal compatibility matrix | Per-terminal/font behavior detection | Locked Raxol model tests for required glyphs | Unicode documents terminal width tailoring complexity; phase context defers terminal/font compatibility research. [CITED: https://www.unicode.org/reports/tr11/] [VERIFIED: 16-CONTEXT.md] |

**Key insight:** Foglet needs a stable local contract over Raxol’s current width model, not a universal Unicode terminal-width implementation. [VERIFIED: 16-CONTEXT.md] [CITED: https://www.unicode.org/reports/tr11/]

## Runtime State Inventory

| Category | Items Found | Action Required |
|----------|-------------|-----------------|
| Stored data | None; this phase changes TUI rendering helpers and tests, not schemas or persisted values. [VERIFIED: 16-CONTEXT.md] | None. |
| Live service config | None; no external service configuration participates in text-width rendering. [VERIFIED: 16-CONTEXT.md] | None. |
| OS-registered state | None; SSH service registration and OS launch state are not changed by helper refactoring. [VERIFIED: 16-CONTEXT.md] | None. |
| Secrets/env vars | None; text-width behavior does not read or rename secret/env keys. [VERIFIED: 16-CONTEXT.md] | None. |
| Build artifacts | No persistent artifact migration required; normal Elixir compilation will rebuild changed modules. [ASSUMED] | Run normal test/precommit commands after implementation. |

## Common Pitfalls

### Pitfall 1: Grapheme Count Looks Unicode-Safe But Is Not Display Width

**What goes wrong:** Accented Latin and combining marks may look correct, while CJK or planned glyph rows still drift because code counts graphemes rather than terminal cells. [CITED: https://hexdocs.pm/elixir/String.html] [CITED: https://hexdocs.pm/raxol/Raxol.UI.TextMeasure.html]

**Why it happens:** Elixir `String.length/1` and `String.slice/3` work on graphemes; terminal layout needs display-cell width. [CITED: https://hexdocs.pm/elixir/String.html]

**How to avoid:** All alignment, truncation, clipping, wrapping, and padding paths must call `Foglet.TUI.TextWidth`. [VERIFIED: .planning/REQUIREMENTS.md]

**Warning signs:** Tests assert `String.length(flat) == width` for a row that is supposed to occupy terminal columns. [VERIFIED: test/foglet_bbs/tui/widgets/list/list_row_test.exs]

### Pitfall 2: Ellipsis Pushes Rows Over Width

**What goes wrong:** Truncation splits to `max_width` and then appends `…`, producing a string wider than the target. [VERIFIED: lib/foglet_bbs/tui/widgets/list/list_row.ex]

**Why it happens:** Widget code subtracts grapheme counts instead of subtracting display width of the ellipsis before splitting. [VERIFIED: lib/foglet_bbs/tui/widgets/list/list_row.ex]

**How to avoid:** Helper truncation must reserve `display_width(ellipsis)` before calling `split_at_display_width/2`. [CITED: https://hexdocs.pm/raxol/Raxol.UI.TextMeasure.html]

**Warning signs:** Width tests pass for ASCII and fail for CJK near the boundary. [ASSUMED]

### Pitfall 3: Combining Mark Split Creates Bad Cursor Placement

**What goes wrong:** Cursor insertion can split a displayed grapheme or place the cursor at a grapheme index that does not match the visible column. [VERIFIED: lib/foglet_bbs/tui/widgets/compose.ex] [CITED: https://www.unicode.org/reports/tr29/]

**Why it happens:** `Compose.render_input/4` currently uses `String.split_at(line, cursor_col)`, and `cursor_col` comes from `MultiLineInput` as a character/grapheme column, not a display-column policy. [VERIFIED: lib/foglet_bbs/tui/widgets/compose.ex]

**How to avoid:** Use the shared helper for cursor display splitting where Phase 16 needs visual correctness, and test with accented/composed, combining, and CJK input. [VERIFIED: 16-CONTEXT.md]

**Warning signs:** A body line such as `"漢e\u0301x"` renders the cursor one cell off from expected visual position. [ASSUMED]

### Pitfall 4: Raxol Model Is Treated As Universal Terminal Truth

**What goes wrong:** Tests make broad claims about all terminals, emoji, ambiguous-width glyphs, or fonts. [CITED: https://www.unicode.org/reports/tr11/]

**Why it happens:** Unicode East Asian Width is tempting to use as a complete terminal rule, but Unicode warns that terminal emulators require tailoring. [CITED: https://www.unicode.org/reports/tr11/]

**How to avoid:** Assert Foglet’s locked glyph set and required text categories against Raxol’s current model only. [VERIFIED: 16-CONTEXT.md]

**Warning signs:** Phase 16 starts adding terminal capability detection or font-dependent behavior. [VERIFIED: 16-CONTEXT.md]

### Pitfall 5: Source Scan Flags Valid Character Policies

**What goes wrong:** A blanket ban on `String.length/1` causes churn in validation, form editing, and counters where grapheme count is intentional. [VERIFIED: 16-CONTEXT.md]

**Why it happens:** Layout-width and product-length concerns share similar function names but have different semantics. [VERIFIED: 16-CONTEXT.md]

**How to avoid:** Scan only layout-sensitive paths, and document retained character-count sites as intentional where touched. [VERIFIED: 16-CONTEXT.md]

**Warning signs:** Planner tasks include Account/Sysop/Moderation form max-length rewrites beyond cheap helper adoption. [VERIFIED: 16-CONTEXT.md]

## Code Examples

Verified patterns from official and local sources:

### Display-Width-Based Row Padding

```elixir
metadata_width = TextWidth.display_width(metadata)
title_width = max(width - marker_width - min_gap - metadata_width, 0)
title_body = TextWidth.truncate(title, title_width)
title_part = marker <> title_body
padding = String.duplicate(" ", max(width - TextWidth.display_width(title_part) - metadata_width, 0))
```

Source: Existing `ListRow.compute_parts/4` should keep the same contract but swap grapheme counts for display-width helper calls. [VERIFIED: lib/foglet_bbs/tui/widgets/list/list_row.ex]

### Word Wrap By Display Width

```elixir
defp fits_with_space?(current, word, max_width) do
  TextWidth.display_width(current) + 1 + TextWidth.display_width(word) <= max_width
end
```

Source: Existing modal `word_wrap/2` wraps on whitespace but currently tests and computes with grapheme length. [VERIFIED: lib/foglet_bbs/tui/widgets/modal.ex] [VERIFIED: test/foglet_bbs/tui/widgets/modal_test.exs]

### Multi-Size Layout Smoke Pattern

```elixir
for dimensions <- [%{width: 64, height: 22}, %{width: 80, height: 24}, %{width: 132, height: 50}] do
  positioned = Raxol.UI.Layout.Engine.apply_layout(tree, dimensions)
  assert positioned != []
end
```

Source: Existing layout smoke tests use `Raxol.UI.Layout.Engine.apply_layout/2` with an 80x24 dimension map. [VERIFIED: test/foglet_bbs/tui/layout_smoke_test.exs]

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `String.length/1` for row width | `Raxol.UI.TextMeasure.display_width/1` through `Foglet.TUI.TextWidth` | Phase 16 | CJK, combining marks, and required glyphs are tested as terminal-cell layout inputs. [VERIFIED: 16-CONTEXT.md] |
| Per-widget truncation | Shared helper truncation/padding/splitting | Phase 16 | Future Chrome V2 and RichRow phases inherit one policy. [VERIFIED: .planning/REQUIREMENTS.md] |
| ASCII-only layout assertions | Preserve ASCII assertions plus display-width regression cases | Phase 16 | Existing behavior stays stable while Unicode-sensitive paths become covered. [VERIFIED: .planning/REQUIREMENTS.md] |
| Treat East Asian Width as complete terminal answer | Lock to framework model and explicit glyph fixtures | Unicode 17 docs current in 2025 | Avoids overpromising around ambiguous terminal/font behavior. [CITED: https://www.unicode.org/reports/tr11/] |

**Deprecated/outdated:**
- Direct `String.length/1`/`String.slice/3` for terminal layout width is outdated for this milestone because planned UI glyphs and CJK cases require display-cell measurement. [VERIFIED: SCREENS.md] [CITED: https://hexdocs.pm/raxol/Raxol.UI.TextMeasure.html]
- Broad terminal-width claims beyond Raxol’s model are out of scope because Unicode documents terminal tailoring requirements and Phase 16 explicitly avoids terminal/font compatibility research. [CITED: https://www.unicode.org/reports/tr11/] [VERIFIED: 16-CONTEXT.md]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Normal Elixir compilation will rebuild changed text-width modules; no persistent build artifact migration is required. | Runtime State Inventory | Low; planner may add an unnecessary clean build step. |
| A2 | CJK or combining cursor examples can expose visual cursor placement drift in `Compose.render_input/4`. | Common Pitfalls | Medium; if Raxol `MultiLineInput.cursor_pos` is strictly grapheme-indexed, implementation may need a narrow adapter rather than display-column cursor state. |

## Open Questions

1. **Should `TextWidth.truncate/2` use Unicode ellipsis `…` or ASCII `...` as default?**
   - What we know: Existing `ListRow` uses `…`, and Phase glyph work is Unicode-friendly. [VERIFIED: lib/foglet_bbs/tui/widgets/list/list_row.ex] [VERIFIED: SCREENS.md]
   - What's unclear: Whether any current SSH terminal compatibility fallback should force ASCII. [ASSUMED]
   - Recommendation: Use `…` by default with an `ellipsis:` option so Chrome V2 can later choose ASCII fallback deliberately. [VERIFIED: 16-CONTEXT.md]

2. **How far should composer cursor migration go if Raxol `MultiLineInput` stores grapheme columns?**
   - What we know: `Compose.render_input/4` currently inserts cursor via `String.split_at(line, cursor_col)`. [VERIFIED: lib/foglet_bbs/tui/widgets/compose.ex]
   - What's unclear: Whether Phase 16 should adapt only render splitting or also upstream cursor movement in Raxol `MultiLineInput`. [ASSUMED]
   - Recommendation: Keep Phase 16 to Foglet render insertion unless tests prove a locked success criterion cannot pass. [VERIFIED: 16-CONTEXT.md]

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| `rtk` | Required project command prefix | yes | `/opt/homebrew/bin/rtk` | None needed. [VERIFIED: command -v rtk] |
| Erlang/OTP | Elixir runtime | yes | 28 / ERTS 16.3.1 | None needed. [VERIFIED: elixir --version] |
| Elixir | Mix, ExUnit, compilation | yes | 1.19.5 | None needed. [VERIFIED: elixir --version] |
| Mix | Test and precommit commands | yes | 1.19.5 | None needed. [VERIFIED: mix --version] |
| Raxol | TUI framework and `TextMeasure` | yes | path dependency; Hex release 2.4.0 | None; locked decision says use Raxol. [VERIFIED: mix.exs] [VERIFIED: rtk mix hex.info raxol] |
| raxol_terminal | Terminal character handling | yes | 2.4.0 locked | Raxol `TextMeasure` falls back to `String.length/1` if unavailable, but that fallback is insufficient for Phase 16 success criteria. [VERIFIED: mix.lock] [VERIFIED: vendor/raxol/lib/raxol/ui/text_measure.ex] |

**Missing dependencies with no fallback:** None. [VERIFIED: environment audit]

**Missing dependencies with fallback:** None. [VERIFIED: environment audit]

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | ExUnit via Elixir 1.19.5. [VERIFIED: elixir --version] |
| Config file | `test/test_helper.exs` assumed from Phoenix/ExUnit project convention; existing tests under `test/foglet_bbs/...` verify framework use. [VERIFIED: test/foglet_bbs] |
| Quick run command | `rtk mix test test/foglet_bbs/tui/text_width_test.exs test/foglet_bbs/tui/widgets/list/list_row_test.exs test/foglet_bbs/tui/widgets/modal_test.exs test/foglet_bbs/tui/widgets/compose_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` [VERIFIED: CLAUDE.md] |
| Full suite command | `rtk mix test` during implementation; `rtk mix precommit` before completion. [VERIFIED: CLAUDE.md] |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| WIDTH-01 | Shared helper measures, truncates, pads, and splits by display width. | unit | `rtk mix test test/foglet_bbs/tui/text_width_test.exs` | No, Wave 0. [VERIFIED: rg --files] |
| WIDTH-02 | Locked layout-sensitive paths consume helper. | unit/static scan | `rtk mix test test/foglet_bbs/tui/widgets/list/list_row_test.exs test/foglet_bbs/tui/widgets/modal_test.exs test/foglet_bbs/tui/widgets/compose_test.exs` | Partial; KeyBar lacks a dedicated test in scan results. [VERIFIED: test/foglet_bbs/tui] |
| WIDTH-03 | ASCII, accented Latin, combining marks, CJK, and `● ◆ ▸ ▾ ✓ ×` have helper tests. | unit | `rtk mix test test/foglet_bbs/tui/text_width_test.exs` | No, Wave 0. [VERIFIED: rg --files] |
| WIDTH-04 | ASCII-heavy screens keep current layout behavior. | regression/smoke | `rtk mix test test/foglet_bbs/tui/widgets/list/list_row_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` | Yes, but assertions need width-aware additions. [VERIFIED: test/foglet_bbs/tui/widgets/list/list_row_test.exs] [VERIFIED: test/foglet_bbs/tui/layout_smoke_test.exs] |
| WIDTH-05 | Size contracts cover 64x22, 80x24, and wide/tall. | smoke | `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` | Yes, but currently uses a single 80x24 dimension constant. [VERIFIED: test/foglet_bbs/tui/layout_smoke_test.exs] |

### Sampling Rate

- **Per task commit:** Run the focused test file for the touched helper/widget. [VERIFIED: existing test layout]
- **Per wave merge:** Run the quick run command above. [VERIFIED: existing test layout]
- **Phase gate:** Run `rtk mix precommit` before `/gsd-verify-work`. [VERIFIED: CLAUDE.md]

### Wave 0 Gaps

- [ ] `test/foglet_bbs/tui/text_width_test.exs` covers WIDTH-01 and WIDTH-03. [VERIFIED: rg --files]
- [ ] `test/foglet_bbs/tui/widgets/chrome/key_bar_test.exs` covers command-footer display-width behavior. [VERIFIED: rg codebase scan]
- [ ] Existing `layout_smoke_test.exs` needs dimension parameterization for 64x22, 80x24, and wide/tall. [VERIFIED: test/foglet_bbs/tui/layout_smoke_test.exs]
- [ ] Existing row/modal/compose tests need display-width assertions for Unicode cases. [VERIFIED: test/foglet_bbs/tui/widgets]

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V2 Authentication | no | Phase does not alter authentication behavior. [VERIFIED: 16-CONTEXT.md] |
| V3 Session Management | no | Phase does not alter session lifecycle. [VERIFIED: 16-CONTEXT.md] |
| V4 Access Control | no | Phase does not alter domain mutations or authorization. [VERIFIED: 16-CONTEXT.md] |
| V5 Input Validation | yes | Preserve existing character-count validation semantics; use display-width only for layout. [VERIFIED: 16-CONTEXT.md] |
| V6 Cryptography | no | Phase does not touch secrets, tokens, hashing, or crypto. [VERIFIED: 16-CONTEXT.md] |

### Known Threat Patterns for TUI Width Handling

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Visual spoofing through unexpected wide/combining text that shifts aligned metadata | Spoofing | Shared display-width truncation/padding and tests for combining/CJK/glyph cases. [CITED: https://hexdocs.pm/raxol/Raxol.UI.TextMeasure.html] |
| Layout denial through long unbroken strings in modal/list rows | Denial of Service | Shared truncation/wrapping by display width and size-contract tests at 64x22. [VERIFIED: .planning/REQUIREMENTS.md] |
| Validation bypass by confusing character count with display width | Tampering | Keep validation paths character-count based and layout paths display-width based. [VERIFIED: 16-CONTEXT.md] |

## Sources

### Primary (HIGH confidence)

- `CLAUDE.md` - project TUI, testing, and workflow constraints. [VERIFIED: file read]
- `.planning/REQUIREMENTS.md` - Phase 16 requirement IDs WIDTH-01 through WIDTH-05. [VERIFIED: file read]
- `.planning/phases/16-unicode-width-foundation/16-CONTEXT.md` - locked decisions and migration scope. [VERIFIED: file read]
- `.planning/STATE.md` - current milestone focus and prior decisions. [VERIFIED: file read]
- `SCREENS.md` - glyph set and width-hardening rationale. [VERIFIED: file read]
- `vendor/raxol/lib/raxol/ui/text_measure.ex` - local Raxol width facade. [VERIFIED: file read]
- `deps/raxol_terminal/lib/raxol/terminal/character_handling.ex` - local Raxol terminal width implementation. [VERIFIED: file read]
- `docs/raxol/core/ARCHITECTURE.md` - Raxol prepare/layout/render architecture. [VERIFIED: file read]
- `lib/foglet_bbs/tui/widgets/README.md` - widget placement and style conventions. [VERIFIED: file read]
- `test/foglet_bbs/tui/...` - existing widget and layout test patterns. [VERIFIED: file read]
- HexDocs `Raxol.UI.TextMeasure` - display-width API and current docs. [CITED: https://hexdocs.pm/raxol/Raxol.UI.TextMeasure.html]
- HexDocs `Raxol.Terminal.CharacterHandling` - terminal character handling API. [CITED: https://hexdocs.pm/raxol_terminal/Raxol.Terminal.CharacterHandling.html]
- HexDocs Elixir `String` - grapheme and slice semantics. [CITED: https://hexdocs.pm/elixir/String.html]
- Unicode UAX #11 - East Asian Width and terminal tailoring caution. [CITED: https://www.unicode.org/reports/tr11/]
- Unicode UAX #29 - grapheme cluster/text segmentation basis. [CITED: https://www.unicode.org/reports/tr29/]

### Secondary (MEDIUM confidence)

- `rtk mix hex.info raxol` and `rtk mix hex.info raxol_terminal` - package version/release checks. [VERIFIED: command output]

### Tertiary (LOW confidence)

- None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Locked context, local dependencies, HexDocs, and `mix.lock` agree that Raxol 2.4.0 APIs are present. [VERIFIED: 16-CONTEXT.md] [VERIFIED: mix.lock] [CITED: https://hexdocs.pm/raxol/Raxol.UI.TextMeasure.html]
- Architecture: HIGH - Existing Raxol docs and local widget code define a clear helper/wrapper path. [VERIFIED: docs/raxol/core/ARCHITECTURE.md] [VERIFIED: lib/foglet_bbs/tui/widgets]
- Pitfalls: MEDIUM - Core risks are verified by source scans and official docs, while exact cursor behavior needs implementation-time tests. [VERIFIED: rg codebase scan] [ASSUMED]

**Research date:** 2026-04-25  
**Valid until:** 2026-05-25 for local project architecture; re-check HexDocs/package versions if dependencies change.
