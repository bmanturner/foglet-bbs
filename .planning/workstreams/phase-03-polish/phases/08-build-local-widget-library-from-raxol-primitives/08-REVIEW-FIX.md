---
phase: "08"
fixed_at: "2026-04-21T12:48:23Z"
review_path: .planning/workstreams/phase-03-polish/phases/08-build-local-widget-library-from-raxol-primitives/08-REVIEW.md
iteration: 1
findings_in_scope: 14
fixed: 13
skipped: 1
status: partial
---

# Phase 8: Code Review Fix Report

**Fixed at:** 2026-04-21T12:48:23Z
**Source review:** `.planning/workstreams/phase-03-polish/phases/08-build-local-widget-library-from-raxol-primitives/08-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 14 (0 Critical + 6 Warning + 8 Info)
- Fixed: 13
- Skipped: 1 (IN-08 — reviewer explicitly deferred to Phase 9)

All 785 tests pass after the fixes. `mix precommit` returns a non-zero exit from pre-existing Credo issues in files outside the Phase 8 diff (`thread_list_test.exs`, `new_thread_test.exs`, `post_composer.ex`, `login.ex`); none of those are caused by the fix run.

## Fixed Issues

### WR-01: `Display.Progress.render/2` crashes on integer progress

**Files modified:** `lib/foglet_bbs/tui/widgets/display/progress.ex`, `test/foglet_bbs/tui/widgets/display/progress_test.exs`
**Commits:** `df383fc`, follow-up `7c5e9de`
**Applied fix:** Relaxed the render/2 guard from `is_float/1` to `is_number/1`, coerced integers to floats via a private `to_float/1` helper, and kept the existing `clamp/3`. Added tests for integer 0/1 input and for out-of-range values (1.5, -0.5). Follow-up: dropped the NaN-sanitize branch because BEAM never yields NaN floats — Credo flagged `n != n` as always-false dead code (`:math.sqrt(-1.0)` raises `:badarith`). Integer-input crash fix remains intact.

### WR-02: `Input.RadioGroup.render/3` silently swallows out-of-range `selected_index`

**Files modified:** `lib/foglet_bbs/tui/widgets/input/radio_group.ex`, `test/foglet_bbs/tui/widgets/input/radio_group_test.exs`
**Commit:** `cc47977`
**Applied fix:** Added a private `clamp_index/2` that maps negative indices to 0 and indices ≥ length to length-1. Empty options lists yield -1 (nothing highlighted). Tightened the `@spec` from `non_neg_integer()` to `integer()` since negatives are now valid input. Added three contract tests covering stale-high, negative, and empty-options cases.

### WR-03: `Input.Menu` auto-generated IDs are non-deterministic and unroutable

**Files modified:** `lib/foglet_bbs/tui/widgets/input/menu.ex`, `test/foglet_bbs/tui/widgets/input/menu_test.exs`
**Commits:** `d7bd907`, follow-up `842a307`
**Applied fix:** Replaced the `:erlang.unique_integer([:positive])` fallback with a deterministic derivation from the label path. Initial commit used a `{:auto, [labels...]}` tuple but that regressed Menu.render/2 — Raxol's component interpolates `item.id` into a string (`"#{state.id}-item-#{item.id}"`). Follow-up switched to a stringifiable form `"auto:<label>/<child>/..."` that preserves determinism AND round-trips through Raxol's string interpolation. Items missing BOTH `:id` and `:label` now raise `ArgumentError` — a label-less item has no derivable key. Added five contract tests (determinism, distinctness, nesting, explicit-id-wins, raise-on-missing).

### WR-04: `Input.Tabs.normalize_tab/1` raises `FunctionClauseError` on bad input

**Files modified:** `lib/foglet_bbs/tui/widgets/input/tabs.ex`, `test/foglet_bbs/tui/widgets/input/tabs_test.exs`
**Commit:** `ebbc7ee`
**Applied fix:** Added an atom clause that coerces via `Atom.to_string/1`, and a catch-all clause that raises `ArgumentError` with a widget-named, value-showing message. Updated the moduledoc options doc to reflect accepted shapes. Added five contract tests (atom coercion, map passthrough, nil-raises, tuple-raises, map-without-:label-raises).

### WR-05: `Display.Table` initial `:selected_row = 0` synthesizes a "selection" on empty tables

**Files modified:** `lib/foglet_bbs/tui/widgets/display/table.ex`, `test/foglet_bbs/tui/widgets/display/table_test.exs`
**Commit:** `41c173f`
**Applied fix:** `init/1` now sets `selected_row` to nil when `rows == []` (matching Raxol's own default). `handle_event/2` short-circuits navigation keys on empty tables because Raxol's table component does `min(state.selected_row + 1, ...)` which would crash on `nil + 1`. Added three empty-table contract tests.

### WR-06: `Display.Tree.derive_action` may misclassify `:enter` on parents

**Files modified:** `lib/foglet_bbs/tui/widgets/display/tree.ex`, `test/foglet_bbs/tui/widgets/display/tree_test.exs`
**Commit:** `7b32cec`
**Applied fix:** Added a `leaf_under_cursor?/1` helper (with a recursive `find_node/2`) and gated the `:node_activated` branch on it. `:enter` on a parent now returns nil instead of spuriously claiming activation. Contract now matches the documented `"Enter on a leaf node"`. Added a regression test that pins the parent-enter-is-not-activated contract.

### IN-01: `SizeGate.render/1` defends against unreachable `terminal_size` shapes

**Files modified:** `lib/foglet_bbs/tui/size_gate.ex`
**Commit:** `45fbe25`
**Applied fix:** Documented the defensive fallback via a comment explaining (a) `App.view/1` only calls `render/1` after `too_small?/1`, (b) the `_ -> {0, 0}` branch exists so unit tests can invoke `render/1` with a bare `%{}` state. Kept the fallback rather than deleting it (deletion would break the direct-invocation test path).

### IN-02: 11 test files duplicate `flatten_text`/`collect_text` helpers verbatim

**Files modified:** `test/support/foglet/tui/widget_helpers.ex` (new), 11 Phase 8 widget test files
**Commit:** `16961b8`
**Applied fix:** Created `Foglet.TUI.WidgetHelpers` under `test/support/foglet/tui/` (already wired via `elixirc_paths(:test)`). Replaced every copy with `import Foglet.TUI.WidgetHelpers, only: [flatten_text: 1]`. Out-of-scope files (`list_row_test.exs`, screens tests, `markdown_body_test.exs`) retain their local copies because they are outside the Phase 8 diff. Net reduction: -142 lines of duplicated helper code.

### IN-03: D-18 hygiene tests use substring scan that would match legitimate hex codes

**Files modified:** `test/support/foglet/tui/widget_helpers.ex`, 13 Phase 8 widget test files
**Commit:** `cbe958c`
**Applied fix:** Added `color_atom_leaked?/2` to `WidgetHelpers` with a word-boundary regex `/(?<![\w-]):<color>(?![\w-])/` and a `color_names/0` accessor for the canonical eight-color list. Rewrote every Phase 8 hygiene block (Display.Table/Tree/Progress, Input.Button/Checkbox/Menu/RadioGroup/Tabs/TextInput, List.SmartList, Post.PostCard, Progress.Spinner, catalog_smoke_test) to iterate `color_names()` and delegate to the helper. Catches legitimate substring values like `:hovered_red` without false-positive failures.

### IN-04: `Input.Button` lacks contract test for unknown `:role`

**Files modified:** `lib/foglet_bbs/tui/widgets/input/button.ex`, `test/foglet_bbs/tui/widgets/input/button_test.exs`
**Commit:** `ea36590`
**Applied fix:** Documented the fallback explicitly in the moduledoc: unknown roles silently route through the `:secondary` clause by design (keeps a typo renderable rather than crashing mid-view). Added a contract test pinning the bogus-role-equivalent-to-:secondary behavior so a future switch to strict role validation is intentional. Chose documentation over a guard because adding `role in [...]` could break callers using undocumented roles.

### IN-05: `to_string(t.<slot>.fg)` is a no-op in test assertions

**Files modified:** 6 Phase 8 widget test files
**Commit:** `8cf3fcb`
**Applied fix:** Dropped the redundant `to_string/1` wrapping across `button_test.exs`, `checkbox_test.exs`, `radio_group_test.exs`, `spinner_test.exs`, `tree_test.exs`, `table_test.exs`. Theme slot values are already strings; wrapping misleadingly suggests they might not be.

### IN-06: `SmartList.handle_event` translated/untranslated event mismatch

**Files modified:** `lib/foglet_bbs/tui/widgets/list/smart_list.ex`
**Commit:** `6e9ed66`
**Applied fix:** Added an inline NOTE comment at the `derive_action/4` call site explaining that the original (pre-translation) `event` — NOT `raxol_data` — is what the downstream `%{key: :char}` pattern depends on. Future refactors that hoist the translation up or reuse `raxol_data` for derivation will now have a clear invariant to respect.

### IN-07: `Display.Tree.render` drops `theme.selected.bg` when nil

**Files modified:** `lib/foglet_bbs/tui/widgets/display/tree.ex`, `test/foglet_bbs/tui/widgets/display/tree_test.exs`
**Commits:** `da4459a`, style follow-up `f8108d8`
**Applied fix:** Extracted a `selected_attrs/1` helper that only prepends `{:bg, bg}` when the theme slot defines one. Added a test that exercises a bg-less theme; during test authoring I confirmed Raxol's `Text.new/2` still materializes `:bg` on its output struct (defaults to nil), so the primary value of this change is in the widget-layer contract rather than the rendered element. The test now pins "does not crash with a bg-less theme." Follow-up commit converts the struct-update syntax to the type-checker-approved `%Theme{} = base = theme()` pattern.

## Skipped Issues

### IN-08: `chrome/screen_frame.ex` and `chrome/status_bar.ex` chained `Map.get` idiom duplication

**Files:** `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex:34`, `lib/foglet_bbs/tui/widgets/chrome/status_bar.ex:37`, `lib/foglet_bbs/tui/size_gate.ex:67-70`
**Reason:** The reviewer explicitly wrote: *"Not in scope for Phase 8 if it touches files outside the diff, but worth filing as Phase 9 cleanup."* Implementing `Theme.from_state/1` requires editing `lib/foglet_bbs/tui/theme.ex`, which is outside the Phase 8 diff. Per the explicit guidance in the review, this is deferred.
**Original issue:** All three call sites duplicate `theme = (Map.get(state, :session_context) || %{}) |> Map.get(:theme) || Theme.default()`. The natural home is `Theme.from_state/1`; the refactor is small but the reviewer judged it out of scope for this phase.
**Follow-up recommendation:** Log a Phase 9 ticket to add `Theme.from_state/1` in `theme.ex` and replace the three call sites.

---

_Fixed: 2026-04-21T12:48:23Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
