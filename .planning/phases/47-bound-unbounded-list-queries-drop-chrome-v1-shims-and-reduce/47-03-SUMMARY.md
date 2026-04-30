---
phase: 47-bound-unbounded-list-queries-drop-chrome-v1-shims-and-reduce
plan: 03
subsystem: tui-chrome
tags: [chrome, refactor, deletion, R5]
requirements: [R5]
dependency_graph:
  requires:
    - "Foglet.TUI.Widgets.Chrome.CommandBar.normalize_groups/1 (V2 grouped contract)"
    - "Foglet.TUI.Widgets.Chrome.ScreenFrame.render/4 (chrome composition site)"
  provides:
    - "V2-only Chrome surface (no Normalizer, no KeyBar, no legacy_title)"
    - "Single normalize_chrome map clause in ScreenFrame"
  affects:
    - "All TUI screens that emit a command bar through ScreenFrame.render/4"
tech-stack:
  added: []
  patterns:
    - "V2 grouped command bar emission with explicit priority tiers (System=0, Tabs/Navigate/Field=10, Actions=30)"
key-files:
  created: []
  modified:
    - lib/foglet_bbs/tui/screens/board_list.ex
    - lib/foglet_bbs/tui/screens/thread_list.ex
    - lib/foglet_bbs/tui/screens/moderation.ex
    - lib/foglet_bbs/tui/screens/account/render.ex
    - lib/foglet_bbs/tui/screens/post_reader/render.ex
    - lib/foglet_bbs/tui/screens/post_composer.ex
    - lib/foglet_bbs/tui/screens/register.ex
    - lib/foglet_bbs/tui/screens/verify.ex
    - lib/foglet_bbs/tui/screens/new_thread/render.ex
    - lib/foglet_bbs/tui/screens/login/render.ex
    - lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex
    - lib/foglet_bbs/tui/widgets/chrome/status_bar.ex
    - lib/foglet_bbs/tui/widgets/README.md
    - .dialyzer_ignore.exs
    - test/foglet_bbs/tui/layout_smoke_test.exs
    - test/foglet_bbs/tui/widgets/chrome/breadcrumb_migration_test.exs
    - test/foglet_bbs/tui/widgets/chrome/screen_frame_test.exs
    - test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs
  deleted:
    - lib/foglet_bbs/tui/widgets/chrome/key_bar.ex
    - lib/foglet_bbs/tui/widgets/chrome/normalizer.ex
    - test/foglet_bbs/tui/widgets/chrome/key_bar_test.exs
    - test/foglet_bbs/tui/widgets/chrome/normalizer_test.exs
decisions:
  - "Migrated 5 additional V1 call sites beyond the plan's listed five (post_composer, register, verify, new_thread x2, login) — necessary to keep compile green after the V1 fallback removal in Task 2."
  - "Tightened ScreenFrame.render/4 @spec to [map()] for commands and added the file to the C2 contract_supertype ignore bucket (matches surrounding widget render-spec pattern)."
  - "Deleted V1 fixture tests (KeyBarTest, NormalizerTest, StatusBar.render/2 describe block) per D-25; migrated incidental V1 assertions in ScreenFrame/breadcrumb-migration/layout-smoke tests onto the V2 grouped shape."
metrics:
  duration_minutes: 30
  completed: 2026-04-30
---

# Phase 47 Plan 03: Drop Chrome V1 Shims Summary

**One-liner:** Migrated all surviving V1 chrome call sites to V2 grouped command bars (Navigate/Tabs/Field/Actions/System priority tiers) and deleted the Normalizer and KeyBar compatibility modules along with their fixture tests.

## Tasks Executed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Migrate V1 screen call sites to V2 grouped command bars | `3047c255` | 10 screen modules |
| 2 | Strip V1 paths from chrome widgets and delete KeyBar + Normalizer | `3ba4c45e` | screen_frame.ex, status_bar.ex, README.md, .dialyzer_ignore.exs, 4 test files; deleted 4 files |

## What Changed

### Screen call sites (Task 1)

The plan listed 5 V1 sites; the SPEC R5 grep gate after migration revealed 5 more V1 emissions (`post_composer.ex`, `register.ex`, `verify.ex`, `new_thread/render.ex` × 2 sites, `login/render.ex`'s `keys_for/2` clauses). Per the plan's own escape hatch ("If any V1 chrome shape appears that wasn't surveyed in PATTERNS.md, migrate it"), all ten were migrated to the V2 grouped shape using the priority vocabulary from `sysop/render.ex`:

- **System** group (Q/Esc/Cancel/Back) — priority `0`
- **Navigate** / **Tabs** / **Field** groups — priority `10`
- **Actions** group — priority `30`

### Chrome widget cleanup (Task 2)

- `lib/foglet_bbs/tui/widgets/chrome/normalizer.ex` — **deleted** (141 lines)
- `lib/foglet_bbs/tui/widgets/chrome/key_bar.ex` — **deleted** (26 lines, was a `Normalizer → CommandBar` shim)
- `screen_frame.ex` — removed `Normalizer` alias, deleted the V1 `command_groups/1` fallback branch, deleted the `defp normalize_chrome(_legacy_title, state)` clause; `command_groups/1` now reduces to a single `CommandBar.normalize_groups/1` call.
- `status_bar.ex` — removed `def render(state, title), do: render(state, title, [])` 2-arity dispatch, removed `legacy_title/1` clause, simplified `left_text/2` to require V2 breadcrumb parts or chrome map.
- `widgets/README.md` — replaced the `Chrome.KeyBar` row with a `Chrome.CommandBar` row.

### Test cleanup (D-25)

Per D-25 (V1 fixture tests are deleted, not skipped):

- `test/foglet_bbs/tui/widgets/chrome/key_bar_test.exs` — **deleted** (75 lines)
- `test/foglet_bbs/tui/widgets/chrome/normalizer_test.exs` — **deleted** (107 lines)
- `status_bar_test.exs` — deleted the `describe "StatusBar.render/2"` block (4 tests asserting V1 string title contract); kept `status_atoms/1` and `render/3` describe blocks.
- `layout_smoke_test.exs` — removed the `KeyBar.render/3` block from the Phase 16 size-contracts test; migrated the Chrome V2 size-contracts ScreenFrame call from a string title + V1 tuples to a chrome map + V2 grouped commands.
- `screen_frame_test.exs` and `breadcrumb_migration_test.exs` — migrated incidental `[{"Q", "Back"}]` assertions to the V2 grouped equivalent.

## Verification

- `rtk mix precommit` — green (compile-with-warnings-as-errors, formatter, Credo, Sobelow, Dialyzer all clean)
- `rtk mix test` — 1 property, 2221 tests, 0 failures
- SPEC R5 grep gates:
  - `lib/foglet_bbs/tui/widgets/chrome/normalizer.ex` does not exist ✓
  - `lib/foglet_bbs/tui/widgets/chrome/key_bar.ex` does not exist ✓
  - `Chrome.Normalizer` / `Widgets.Chrome.Normalizer` references in lib/test: 0 ✓
  - `Chrome.KeyBar` / `Widgets.Chrome.KeyBar` references in lib/test: 0 ✓
  - `legacy_title` references in `lib/foglet_bbs/tui/widgets/chrome/`: 0 ✓
  - `defp normalize_chrome` clauses in `screen_frame.ex`: exactly 1 (V2 map clause) ✓

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking] Migrated 5 additional V1 call sites not surveyed in PATTERNS.md**

- **Found during:** Task 1 SPEC R5 grep gate (D-12)
- **Issue:** PATTERNS.md listed only 5 chrome call sites needing migration. The grep gate after migrating those five revealed 5 more V1 tuple emissions still flowing through `ScreenFrame.render/4`: `post_composer.ex:141-145`, `register.ex:272-275` (`keys_for/1`), `verify.ex:62-67`, `new_thread/render.ex:54-58` and `:85-89`, `login/render.ex:61-76` (`keys_for/2` for `:login_form`, `:reset_request`, `:reset_consume`). Leaving them V1 would have crashed at runtime once Task 2 removed the `Normalizer.commands/1` fallback in `screen_frame.ex:198-204`.
- **Fix:** Migrated all 5 to the V2 grouped shape using the same Navigate/Tabs/Field/Actions/System vocabulary as the plan-listed sites.
- **Files modified:** `post_composer.ex`, `register.ex`, `verify.ex`, `new_thread/render.ex`, `login/render.ex`
- **Commit:** `3047c255` (folded into Task 1)
- **Plan basis:** Plan explicitly authorizes this — *"If any V1 chrome shape appears that wasn't surveyed in PATTERNS.md ('file not on the migration list but still emits keybar tuples'), migrate it using the same Navigate/Actions/System group vocabulary."*

**2. [Rule 3 — Blocking] Tightened ScreenFrame.render/4 @spec and added dialyzer ignore**

- **Found during:** Task 2 `mix precommit`
- **Issue:** With the V1 fallback gone, dialyzer's success typing for `ScreenFrame.render/4` narrowed to `[map()]` for `commands`; the existing `@spec render(map(), String.t() | map(), any(), list()) :: any()` was now flagged `:contract_supertype`. Narrowing the return type emits a fresh `:contract_supertype` on the same line because the body returns a Raxol element struct (Phase 46 Pitfall 1).
- **Fix:** Tightened the spec to `@spec render(map(), map(), any(), [map()]) :: any()` and added `screen_frame.ex` to `.dialyzer_ignore.exs` Bucket C2 (the same bucket used for every other widget/screen render function with the same Raxol-element-return pattern).
- **Files modified:** `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex`, `.dialyzer_ignore.exs`
- **Commit:** `3ba4c45e` (folded into Task 2)

**3. [Rule 3 — Blocking] Migrated incidental V1 assertions in 3 test files**

- **Found during:** Task 2 `mix test` — 4 failures with `FunctionClauseError` from `CommandBar.to_map/1` and `ScreenFrame.normalize_chrome/2`.
- **Issue:** `screen_frame_test.exs`, `breadcrumb_migration_test.exs`, and `layout_smoke_test.exs` (Chrome V2 size contracts test) all incidentally passed `[{"Q", "Back"}]` V1 tuples and (in one layout-smoke case) a string title. These tests primarily exercise V2 chrome composition (breadcrumb / layout / status atoms / chrome model fallback); the V1 input was incidental.
- **Fix:** Migrated the V1 inputs to V2 grouped form. Per the plan: *"if the test exercises broader render behavior and incidentally asserts the V1 shape, migrate the assertion to the V2 grouped shape."*
- **Files modified:** `test/foglet_bbs/tui/widgets/chrome/screen_frame_test.exs`, `test/foglet_bbs/tui/widgets/chrome/breadcrumb_migration_test.exs`, `test/foglet_bbs/tui/layout_smoke_test.exs`
- **Commit:** `3ba4c45e` (folded into Task 2)

### Plan reference inaccuracies (minor, no action needed)

- D-11 / acceptance criteria mention `lib/foglet_bbs/tui/screens/invites_surface.ex` and `lib/foglet_bbs/tui/screens/account/ssh_keys_surface.ex`. The first file does not exist in the repo (only `ssh_keys_surface.ex` exists). The `@key_hints` constraint applied trivially: nothing in `invites_surface.ex` to leave alone, and `ssh_keys_surface.ex` was untouched.

### Authentication gates

None.

## Self-Check: PASSED

- `lib/foglet_bbs/tui/widgets/chrome/normalizer.ex` — MISSING (intentional deletion) ✓
- `lib/foglet_bbs/tui/widgets/chrome/key_bar.ex` — MISSING (intentional deletion) ✓
- `test/foglet_bbs/tui/widgets/chrome/key_bar_test.exs` — MISSING (intentional deletion) ✓
- `test/foglet_bbs/tui/widgets/chrome/normalizer_test.exs` — MISSING (intentional deletion) ✓
- Commit `3047c255` — FOUND ✓
- Commit `3ba4c45e` — FOUND ✓
- All modified files exist ✓
- `mix precommit` green ✓
- Test suite green (2221/2221) ✓
