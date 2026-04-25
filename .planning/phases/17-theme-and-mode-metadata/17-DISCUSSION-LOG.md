# Phase 17: theme-and-mode-metadata - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md - this log preserves the analysis.

**Date:** 2026-04-25T13:30:44Z
**Phase:** 17-theme-and-mode-metadata
**Mode:** assumptions
**Areas analyzed:** Mode Contract Location, Screen Mapping Scope, Theme Slot Extension, Mapping Contract Form, Theme Independence

## Assumptions Presented

### Mode Contract Location
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Implement the presentation-mode contract as a shared TUI-level module or API keyed by existing screen ids, rather than deriving mode inside individual render functions. | Confident | `lib/foglet_bbs/tui/app.ex`, `lib/foglet_bbs/tui/screen.ex`, `.planning/phases/17-theme-and-mode-metadata/17-SPEC.md` |

### Screen Mapping Scope
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Only the named Phase 17 screens should receive locked mode declarations: `:login`, `:main_menu`, `:board_list`, `:thread_list`, `:post_reader`, `:new_thread`, `:post_composer`, `:account`, `:moderation`, and `:sysop`. | Confident | `.planning/phases/17-theme-and-mode-metadata/17-SPEC.md`, `.planning/ROADMAP.md`, `.planning/REQUIREMENTS.md`, `SCREENS.md`, `lib/foglet_bbs/tui/app.ex` |

### Theme Slot Extension
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Add `success`, `info`, and `badge` as first-class fields in `%Foglet.TUI.Theme{}`, `@type t`, `@slot_keys`, and every palette map. | Confident | `lib/foglet_bbs/tui/theme.ex`, `.planning/phases/17-theme-and-mode-metadata/17-SPEC.md`, `SCREENS.md` |

### Mapping Contract Form
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Capture tab, row, badge, command hint, and editor-state mappings as a project-local data contract with tests that validate referenced slot names against `Foglet.TUI.Theme`, not by introducing new visible widgets. | Confident | `.planning/phases/17-theme-and-mode-metadata/17-SPEC.md`, `lib/foglet_bbs/tui/widgets/input/tabs.ex`, `lib/foglet_bbs/tui/widgets/list/list_row.ex`, `lib/foglet_bbs/tui/widgets/chrome/key_bar.ex`, `lib/foglet_bbs/tui/widgets/compose.ex` |

### Theme Independence
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Mode resolution must ignore `state.session_context.theme`, `theme_id`, and Account preview state, using only screen identity or screen metadata. | Confident | `lib/foglet_bbs/tui/theme.ex`, `lib/foglet_bbs/tui/screens/account.ex`, `.planning/phases/17-theme-and-mode-metadata/17-SPEC.md`, `SCREENS.md` |

## Corrections Made

### Screen Mapping Scope
- **Original assumption:** Only the SPEC/SCREENS-named screens should receive locked mode declarations.
- **User correction:** Lock all current TUI screens, even those not mentioned by `SCREENS.md`.
- **Reason:** The phase mode contract should cover every current app-routed screen id so downstream code does not inherit holes for `:register` or `:verify`.
- **Applied decision:** `:register` and `:verify` are included and classified as `:bbs`.

## External Research

None.
