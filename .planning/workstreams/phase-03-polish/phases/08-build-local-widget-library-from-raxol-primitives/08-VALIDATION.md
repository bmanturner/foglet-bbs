---
phase: 8
slug: build-local-widget-library-from-raxol-primitives
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-20
---

# Phase 8 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit (stdlib, Elixir 1.19.2) |
| **Config file** | `test/test_helper.exs` (already present) |
| **Quick run command** | `mix test test/foglet_bbs/tui/widgets/` |
| **Full suite command** | `mix precommit` (compile --warnings-as-errors, format, credo --strict, sobelow, dialyzer, mix test) |
| **Estimated runtime** | ~30s (widget subtree); ~2–3 min (precommit) |

---

## Sampling Rate

- **After every task commit:** Run `mix test test/foglet_bbs/tui/widgets/<bucket>/` — fast feedback on the affected bucket (≈5–10s)
- **After every plan wave:** Run `mix test test/foglet_bbs/tui/widgets/` — full widget layer (≈30s)
- **Before `/gsd-verify-work`:** `mix precommit` must be green
- **Max feedback latency:** 30 seconds (per-bucket test)

---

## Per-Task Verification Map

> Task IDs and file paths are the planner's discretion per CONTEXT D-02 + D-14. The planner assigns each D-02 widget to a plan/task and fills in Task ID + Plan + Wave when writing PLAN.md. Use the REQ-W-* grouping below as the stable contract.

| Requirement | Widget / Artifact | Test Type | Automated Command | File Exists | Status |
|-------------|-------------------|-----------|-------------------|-------------|--------|
| REQ-W-01 | `Foglet.TUI.Widgets.List.SmartList` | unit | `mix test test/foglet_bbs/tui/widgets/list/smart_list_test.exs` | ❌ W0 | ⬜ pending |
| REQ-W-02 | `Foglet.TUI.Widgets.Display.Table` | unit | `mix test test/foglet_bbs/tui/widgets/display/table_test.exs` | ❌ W0 | ⬜ pending |
| REQ-W-03 | `Foglet.TUI.Widgets.Display.Tree` | unit | `mix test test/foglet_bbs/tui/widgets/display/tree_test.exs` | ❌ W0 | ⬜ pending |
| REQ-W-04 | `Foglet.TUI.Widgets.Display.Progress` | unit | `mix test test/foglet_bbs/tui/widgets/display/progress_test.exs` | ❌ W0 | ⬜ pending |
| REQ-W-05 | `Foglet.TUI.Widgets.Progress.Spinner` | unit | `mix test test/foglet_bbs/tui/widgets/progress/spinner_test.exs` | ❌ W0 | ⬜ pending |
| REQ-W-06 | `Foglet.TUI.Widgets.Input.TextInput` | unit | `mix test test/foglet_bbs/tui/widgets/input/text_input_test.exs` | ❌ W0 | ⬜ pending |
| REQ-W-07 | `Foglet.TUI.Widgets.Input.Button` | unit | `mix test test/foglet_bbs/tui/widgets/input/button_test.exs` | ❌ W0 | ⬜ pending |
| REQ-W-08 | `Foglet.TUI.Widgets.Input.Checkbox` | unit | `mix test test/foglet_bbs/tui/widgets/input/checkbox_test.exs` | ❌ W0 | ⬜ pending |
| REQ-W-09 | `Foglet.TUI.Widgets.Input.RadioGroup` | unit | `mix test test/foglet_bbs/tui/widgets/input/radio_group_test.exs` | ❌ W0 | ⬜ pending |
| REQ-W-10 | `Foglet.TUI.Widgets.Input.Tabs` | unit | `mix test test/foglet_bbs/tui/widgets/input/tabs_test.exs` | ❌ W0 | ⬜ pending |
| REQ-W-11 | `Foglet.TUI.Widgets.Input.Menu` | unit | `mix test test/foglet_bbs/tui/widgets/input/menu_test.exs` | ❌ W0 | ⬜ pending |
| REQ-W-12 | `lib/foglet_bbs/tui/widgets/README.md` index | integration | `test -f lib/foglet_bbs/tui/widgets/README.md && grep -c "SmartList\|Table\|Tree\|Progress\|Spinner\|TextInput\|Button\|Checkbox\|RadioGroup\|Tabs\|Menu" lib/foglet_bbs/tui/widgets/README.md` (≥ 11) | ❌ W0 | ⬜ pending |
| REQ-W-13 | Umbrella: whole phase passes precommit | suite | `mix precommit` | Existing | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

### Per-widget test bar (D-18 — applies to REQ-W-01 through REQ-W-11)

Each widget test file MUST cover:

1. **Smoke render** (`WidgetMod.render/2` returns non-nil element with the expected top-level `:type` key, e.g., `:box`, `:column`).
2. **Theme hygiene** (no hardcoded color atom — `:red`, `:green`, `:cyan`, `:yellow`, `:blue`, `:magenta`, `:white`, `:black` — appears in the serialized tree; rendering with two distinct `Foglet.TUI.Theme` fixtures produces different output).
3. **Defaults from module constants** (assert `@default_*` values apply when the caller omits the option — for per-widget defaults per D-08).
4. **(Stateful widgets only)** `init/1` returns the defstruct shape; `handle_event/2` is pure (same input → same output, no process spawn, no `send/2`).
5. **(Stateful widgets only)** Action atoms returned match the per-widget convention (e.g., `:item_selected`, `:submitted`, `:cancelled`, `:tab_changed`, `:node_expanded`/`:node_collapsed`/`:node_activated`, `:menu_action`, `:toggled`).

---

## Wave 0 Requirements

Wave 0 creates the test files that verify each widget's D-18 bar. Implementation lands in Wave 1+ per planner's plan breakdown.

- [ ] `test/foglet_bbs/tui/widgets/list/smart_list_test.exs` — REQ-W-01
- [ ] `test/foglet_bbs/tui/widgets/display/table_test.exs` — REQ-W-02
- [ ] `test/foglet_bbs/tui/widgets/display/tree_test.exs` — REQ-W-03
- [ ] `test/foglet_bbs/tui/widgets/display/progress_test.exs` — REQ-W-04
- [ ] `test/foglet_bbs/tui/widgets/progress/spinner_test.exs` — REQ-W-05
- [ ] `test/foglet_bbs/tui/widgets/input/text_input_test.exs` — REQ-W-06
- [ ] `test/foglet_bbs/tui/widgets/input/button_test.exs` — REQ-W-07
- [ ] `test/foglet_bbs/tui/widgets/input/checkbox_test.exs` — REQ-W-08
- [ ] `test/foglet_bbs/tui/widgets/input/radio_group_test.exs` — REQ-W-09
- [ ] `test/foglet_bbs/tui/widgets/input/tabs_test.exs` — REQ-W-10
- [ ] `test/foglet_bbs/tui/widgets/input/menu_test.exs` — REQ-W-11
- [ ] `lib/foglet_bbs/tui/widgets/README.md` — REQ-W-12 (index file; new)

**Framework install:** none needed — ExUnit is stdlib; Raxol is vendored; `Foglet.TUI.Theme` already ships with session-resolved snapshot.

**Helper reuse:** `test/foglet_bbs/tui/widgets/list/list_row_test.exs` already defines `flatten_text/1` and `collect_text/2` helpers; extract to a shared `test/support/raxol_element_helpers.ex` (or per-test-file copy) so theme-hygiene assertions read uniformly across the new test files.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Visual parity with Phase 1 chrome (border style, padding density) when widgets are rendered through `ScreenFrame` | D-08 (per-widget defaults look good next to existing chrome) | No visual-snapshot infrastructure for TUI in this repo; judging aesthetic coherence across themes is a human-eye task | Render a throwaway screen that stacks one widget from each bucket (SmartList, Table, Tabs, Button, Checkbox, TextInput) inside `ScreenFrame`. SSH in with the active theme (`Foglet.TUI.Theme.default/0`) and visually confirm border style / spacing / selected-row contrast read as a coherent family. |

All other phase behaviors have automated verification via the per-widget test bar (D-18).

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s per-bucket; < 3 min precommit
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
