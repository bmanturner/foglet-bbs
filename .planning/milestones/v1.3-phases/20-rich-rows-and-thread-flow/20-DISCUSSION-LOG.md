# Phase 20: rich-rows-and-thread-flow - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the analysis.

**Date:** 2026-04-25
**Phase:** 20-rich-rows-and-thread-flow
**Mode:** assumptions
**Areas analyzed:** RichRow public API surface, Glyph choices and theme-slot mapping, Selection clarity (focus treatment), Test placement and fixture strategy

## Assumptions Presented

### RichRow public API surface
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| `RichRow.render/1` accepts a keyword list with `:title`, `:metadata`, `:state_cluster`, `:selected`, `:theme`; optional `:width`, `:focus_marker`, `:emphasis`. Replaces the boolean `unread?` arg. | Likely | SPEC requirement 6 demands generic state-cluster shape; sibling `SmartList`/`SelectionList` already use `Keyword.fetch!(opts, :theme)` (`smart_list.ex:81-106`, `selection_list.ex:46-89`). |
| `:state_cluster` is a list of state atoms (`[:unread, :sticky]`); `RichRow` owns the atom→glyph→theme-slot mapping. Cluster width is a fixed module attribute computed via `TextWidth.display_width/1`. | Likely | SPEC requirement 6 line 46-49: "list/struct of state atoms or glyph cells"; SPEC constraint line 79 mandates fixed cluster width; sibling pattern in `selection_list.ex:91-105`, `smart_list.ex:280-283`. |

### Glyph choices and theme-slot mapping (initial assumption)
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| `unread → ●`, `read → ◇` or whitespace, `sticky → ◆`, `locked → ⚿` or `⚑`. Theme slots: unread→`accent.fg`+`:bold`, read→`dim.fg`, sticky→`info.fg`/`badge.fg`, locked→`warning.fg`. | Likely | SCREENS.md lines 358-373 use `●`/`◆`/`◇`; Phase 18 layout_smoke_test.exs:198-247 confirms single-cell width across `[{64,22},{80,24},{132,50}]`; Phase 19 CONTEXT D-08 standardizes SCREENS.md glyphs. |

### Selection clarity (focus treatment)
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| `▌` (U+258C) leading marker + `theme.selected.fg`/`theme.selected.bg` + `:bold` style. Non-focused: two leading spaces + `theme.unselected.fg` (no bg). Replaces `> ` marker. | Likely | `▌` is canonical: `selection_list.ex:100`, `smart_list.ex:41`, `tabs.ex:43`, `modal.ex:82`. `selection_list.ex:19-20` moduledoc names it canonical. Every theme defines `selected.bg` (`theme.ex:113-241`), satisfying SPEC requirement 4. |

### Test placement and fixture strategy
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| NEW `rich_row_test.exs` for widget unit tests; EXTEND `thread_list_test.exs` (glyph presence, `[S]` absence in LIST-03 describe block ~line 221); EXTEND `layout_smoke_test.exs` with new ThreadList block at `[{64,22},{80,24},{132,50}]`. | Confident | Sibling list widgets each have dedicated test files (`list_row_test.exs`, `selection_list_test.exs`, `smart_list_test.exs`). Phase 18/19 layout_smoke_test.exs precedent. Phase 19 D-16/D-17 mandates extending size-contract file rather than creating new ones. |

## Corrections Made

### Glyph choices and theme-slot mapping
- **Original assumption:** `unread → ●`, `sticky → ◆` (per SCREENS.md mock)
- **User correction:** Swap them — `sticky → ●`, `unread → ◆`, `read → ◇` (matches the "I think `●` should be sticky, `◆` is unread, and `◇` is read" message)
- **Reason:** User's preferred semantic mapping; SPEC line 28 explicitly allows "or theme-routed equivalent" so glyph atoms are planner discretion. Theme-slot routing is unaffected by the swap — unread still routes to `accent` (warm/highlight), sticky still routes to `info`/`badge` (structural-affordance).

## External Research

None performed. Codebase-only evidence sufficient for all four assumption areas.
