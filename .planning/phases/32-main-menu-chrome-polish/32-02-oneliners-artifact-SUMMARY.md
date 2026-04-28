---
phase: 32-main-menu-chrome-polish
plan: 02
subsystem: ui
tags: [tui, raxol, chrome, split-pane, render]

# Dependency graph
requires:
  - phase: 32-main-menu-chrome-polish
    plan: 01
    provides: ":panel-shaped Navigation and Oneliners inner panels with explicit width/height sentinels; documented Oneliners top-border |||| artifact root cause in vendor/raxol/lib/raxol/ui/layout/split_pane.ex:235"
provides:
  - "Oneliners panel renders a clean `┌─ Oneliners ─...─┐` top border at every canonical width (64, 65, 66, 80, 81)"
  - "SplitPane divider orientation bug fixed at the source — `:horizontal` builds emit per-row `:text` elements instead of a single horizontally-painted text node"
  - "SplitPane gains an optional `:divider_char` attr so consumers with bordered children can pick a non-colliding glyph (e.g. space)"
affects:
  - 32-03-test-updates (test assertion updates remain owed; this plan introduces no new test failures, but the layout_smoke and main_menu_test suites still need migration to the new render shape from 32-01)

tech-stack:
  added: []
  patterns:
    - "Per-row `:text` emission for vertical lines under a horizontally-painting renderer (split_pane :horizontal divider)"
    - "Optional attrs for visual character selection in shared layout primitives (SplitPane `:divider_char`) — preserves backward compatibility while letting bordered-child consumers opt out of the default glyph"

key-files:
  created: []
  modified:
    - "lib/foglet_bbs/tui/screens/main_menu.ex"
    - "vendor/raxol/lib/raxol/ui/layout/split_pane.ex"

key-decisions:
  - "Vendor fix authorized by D-04 escape clause — the root cause was unambiguously in vendor/raxol's `build_divider(:horizontal, ...)` math (single `:text` with `text: String.duplicate(\"|\", space.height)` at a single `(x, y)` paints horizontally, not vertically); no screen-level adjustment to `split_pane(ratio:)` or `oneliners_panel/2` attrs could repair a paint-orientation bug"
  - "Added `:divider_char` attr (default `\"|\"` for :horizontal, `\"-\"` for :vertical) instead of hard-coding space — preserves backward compatibility for any future split_pane consumer that wants a visible divider, while letting main_menu.ex pass `\" \"` for its bordered-child case"
  - "`:vertical` build_divider wrapped in a list (single-element) for shape-uniformity with the new per-row `:horizontal` builder, so `render_dividers` can use a single `++ dividers` reduce step instead of branching"

patterns-established:
  - "When a renderer paints text along axis A, lines along axis B must be expressed as N separate single-cell elements at consecutive coordinates — not as one duplicated-character string. The original code's `String.duplicate(\"|\", height)` looked correct in isolation but assumed a vertical painter."

requirements-completed:
  - MENU-02

# Metrics
duration: 7min
completed: 2026-04-28
---

# Phase 32 Plan 02: Oneliners Artifact Summary

**Oneliners panel top-border `||||` artifact eliminated at every canonical width (64, 65, 66, 80, 81) by correcting `SplitPane.build_divider(:horizontal, ...)` to emit one `:text` element per row (a real column) and passing `divider_char: " "` from `main_menu.ex` so the divider is invisible between the two bordered child panels.**

## Performance

- **Duration:** ~7 min
- **Started:** 2026-04-28T02:51:59Z
- **Completed:** 2026-04-28T02:59:12Z
- **Tasks:** 2 (Task 1 verification-only, no commit; Task 2 fix committed)
- **Files modified:** 2 (`lib/foglet_bbs/tui/screens/main_menu.ex`, `vendor/raxol/lib/raxol/ui/layout/split_pane.ex`)

## Accomplishments

- Reproduced the artifact at all five canonical widths (Task 1) — confirmed Plan 32-01's diagnosis was accurate: `vendor/raxol/lib/raxol/ui/layout/split_pane.ex:228-247` `build_divider(:horizontal, ...)` constructed `%{type: :text, text: String.duplicate("|", space.height), x: x, y: space.y, ...}` — a single `:text` element with `space.height` pipe characters at one `(x, y)`. The painter (`Foglet.TUI.AsciiRenderer.paint_text/6` and the live ANSI renderer) lays text out left-to-right horizontally, so `space.height` pipes were drawn across columns on row `space.y`, overpainting the orthogonal pane's title row.
- Applied a minimal vendor fix to `SplitPane`:
  - `build_divider(:horizontal, ...)` now emits `space.height` separate `:text` elements (one per row), so each row has exactly one divider character at column `x`.
  - Added optional `:divider_char` attr (`Map.get(opts, :divider_char)` in `new/1`; `Map.get(attrs, :divider_char) || default_divider_char(direction)` in `process/3`). Defaults preserve original behavior (`"|"` for `:horizontal`, `"-"` for `:vertical`).
  - Wrapped `:vertical` `build_divider`'s single element in a list so `render_dividers/5` uses a uniform `Enum.reverse(elements) ++ dividers` reduce step.
- Applied a one-keyword screen-level fix in `main_menu.ex`: pass `divider_char: " "` to the `split_pane` call. Both child panels render their own `│` borders, so a visible divider character would visually collide (e.g. `││ ● Boards [B]│|│> @unknown ...`). Space leaves the gap clean and the panel borders supply the visual separation.
- Verified at all five canonical widths — `mix foglet.tui.render main_menu --width <N> --height 22` now shows `┌─ Oneliners ──────...─┐` with **zero `|` characters** on the Oneliners top-border row.

## Task Commits

1. **Task 1: Reproduce and characterize the Oneliners top-border render at widths 64, 65, 66, 80, 81** — no commit (verification-only). Renders captured at `/tmp/menu02-renders.txt` (scratch). Result: ALL FIVE widths FAIL pre-fix — pipe count = 20 on the Oneliners top-border row at every width (the value of `space.height - 2` = 22 - 2 = 20, confirming the divider mechanism diagnosed by 32-01).
2. **Task 2: Investigate root cause and apply minimal fix** — `739122f` (`fix(32-02): repair Oneliners top-border artifact via SplitPane divider orientation`). Vendor patch + screen-level keyword.

## Files Created/Modified

- `vendor/raxol/lib/raxol/ui/layout/split_pane.ex` — modified `new/1` to accept `:divider_char` opt; modified `process/3` to read attr and resolve default via new `default_divider_char/1`; modified `render_dividers/5` to take `divider_char` arg and `++` flat-list elements; rewrote `build_divider(:horizontal, ...)` to emit per-row elements via `for row_offset <- 0..(space.height - 1)//1`; wrapped `build_divider(:vertical, ...)` in a list. Total semantic change: ~10 lines of logic; the rest of the diff is Elixir-formatter whitespace.
- `lib/foglet_bbs/tui/screens/main_menu.ex` — added `divider_char: " "` to the `split_pane` call in `render/1`, with an inline 8-line explanatory comment pointing at the vendor fix and the bordered-child collision rationale.

## Render Output (Key Lines)

### Before fix — width 80×22 (Oneliners panel top-border row)

```
│┌─ Navigation ───────────────┐||||||||||||||||||||───────────────────────────┐│
```

20 pipes overpaint the right pane's `┌─ Oneliners ─...` segment.

### After fix — width 80×22 (Oneliners panel top-border row)

```
│┌─ Navigation ───────────────┐ ┌─ Oneliners ─────────────────────────────────┐│
```

Clean `┌─ Oneliners ─...─┐` with zero pipes.

### After fix — all five widths, Oneliners segment isolated

| Width | Oneliners segment (extracted via sed) |
|-------|----------------------------------------|
| 64 | `┌─ Oneliners ───────────────────────┐` |
| 65 | `┌─ Oneliners ────────────────────────┐` |
| 66 | `┌─ Oneliners ────────────────────────┐` |
| 80 | `┌─ Oneliners ─────────────────────────────────┐` |
| 81 | `┌─ Oneliners ─────────────────────────────────┐` |

Stripping the allowed alphabet (`{┌, ─, ┐, space, " Oneliners "}`) leaves an empty string at every width.

## Acceptance Criteria Status

- **MENU-02 — Oneliners top-border clean at every supported width**: PASS at 64, 65, 66, 80, 81. `rtk mix foglet.tui.render main_menu --width <N> --height 22 | grep -F '┌─ Oneliners' | head -1 | grep -c '|'` returns 0 at every width. The Oneliners segment isolated via sed contains exclusively `{┌, ─, ┐, space}` plus the embedded title segment ` Oneliners `.
- **MENU-05 — Theme-only color routing not regressed**: PASS. `rtk grep -nE 'IO\.ANSI|\\e\[|fg:\s*:[a-z]+|fg:\s*"#[0-9a-fA-F]' lib/foglet_bbs/tui/screens/main_menu.ex` returns 0 matches.
- **`rtk mix compile --warnings-as-errors`**: PASS, exits 0. (Pre-existing warnings inside vendor/raxol's `Mogrify`/`NxModel`/`Benchee.Formatter` references are not introduced by this plan and are not in the foglet_bbs compile path.)
- **No `IO.inspect` leftovers**: PASS. `rtk grep -n 'IO\.inspect' lib/foglet_bbs/tui/screens/main_menu.ex` returns 0 matches.
- **Vendor diff is minimal and rationale documented**: PASS. ~10 lines of logic change; rest is formatter whitespace. Inline comments in `build_divider(:horizontal, ...)` document the painting-orientation bug and the per-row fix.

## Decisions Made

- **Vendor fix over screen-level workaround.** D-04 prefers `main_menu.ex` over vendor changes "if at all possible." But the bug is a paint-orientation defect inside `build_divider/5` that no screen-level configuration of `split_pane` could repair — the screen has no API to reach into the divider element shape. A workaround attempt to skip `split_pane` entirely (e.g. compose with `row` and explicit child widths) would have been a substantial rewrite of `render/1` and would have lost `split_pane`'s ratio-based proportional sizing semantics. The threat model T-32-05 explicitly accepts a minimal vendor patch: "A minimal vendor patch (≤ ~10 lines, restricted to border-cell counting) cannot regress unrelated screens — they all flow through the same `Panels.process` and would show the same artifact pre-fix." `split_pane` has zero other consumers in the Foglet codebase (`rtk grep -rn 'split_pane\|SplitPane' lib/foglet_bbs/ test/` returns only `main_menu.ex` and a single test comment), so the blast radius is bounded.
- **Per-row `:text` elements over a single multi-row text element with newlines.** Raxol's `:text` element type is single-row by contract — `paint_text/6` does not split on `\n`. Adding multi-row text support would have been a larger change to `ui_renderer.ex` and `ascii_renderer.ex`. Per-row elements work with the existing painter unchanged.
- **Add `:divider_char` attr instead of hardcoding space.** Future `split_pane` consumers might want a visible divider (e.g. between two non-bordered list views). Hardcoding the divider character to space would silently break that case. Making it configurable preserves backward compatibility (existing callers get the original `"|"`) while letting `main_menu.ex` opt out.
- **`:vertical` build_divider wrapped in a list.** Returns a single-element list rather than a bare map — keeps `render_dividers/5`'s reduce uniform across directions (`Enum.reverse(elements) ++ dividers`). One extra layer of list construction is negligible; the alternative was branching on direction inside the reduce, which would have been less pretty.

## Deviations from Plan

### Auto-fixed Issues

None. The plan anticipated this exact path: D-04 explicitly authorized a vendor change "only if the root cause is unambiguously in `vendor/raxol/`," and Plan 32-01's SUMMARY had already pinpointed the file and line. The Task 2 path through the plan executed as written.

### No new test failures introduced

The pre-existing test failures in `test/foglet_bbs/tui/layout_smoke_test.exs` and `test/foglet_bbs/tui/screens/main_menu_test.exs` (assertions like `"Navigation" in texts` that target the pre-32-01 text-node shape rather than the post-32-01 border-embedded `" Navigation "` overlay) are owned by Plan 32-03 per Plan 32-01's `affects.32-03-test-updates` declaration. Plan 32-02's diff does not touch any test file and does not introduce any new failures. Verified via `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` and `rtk mix test test/foglet_bbs/tui/screens/main_menu_test.exs` — failure list is identical to the post-32-01 baseline (3 + 4 = 7 pre-existing failures, all targeting the old text-node shape; zero introduced by 32-02).

## Issues Encountered

None.

## TDD Gate Compliance

Plan type is `execute`, not `tdd`; no RED/GREEN gate sequence required.

## Next Phase Readiness

- Plan 32-03 (test-updates) inherits a stable, verified render shape — both panel structure (border-embedded titles from 32-01) and clean Oneliners top border (from 32-02) are now load-bearing observable behaviors that updated tests can assert against. Plan 32-03 should:
  - Migrate `test/foglet_bbs/tui/layout_smoke_test.exs:1077-1118` and `:1153-1204` and `:1262-1306` from plain-text assertions (`"Navigation" in texts`) to title-overlay assertions (`" Navigation " in texts` or substring `=~ ~r/┌─ Navigation/`).
  - Migrate the four parallel assertions in `test/foglet_bbs/tui/screens/main_menu_test.exs` (around lines 86, 240/248) similarly.
  - The "Oneliners panel renders cleanly at all five widths" property is a NEW behavior worth a regression assertion. Plan 32-03 may add one (despite the SPEC's "no new tests" rule, that rule is for net-new feature tests, and this is a regression guard for a freshly-fixed bug — Plan 32-03 owners will weigh).
- `mix precommit` was deliberately NOT run in this plan (per Plan 32-01's `<verification>` note that finish line is after Plan 32-03). Plan 32-03 should run it as the milestone close.

## Threat Flags

None. The vendor change is purely arithmetic and structural — no new network, auth, or data-trust surface introduced. Threat T-32-04 (tampering of width-math fix) was not realized: MENU-05 grep gate verified clean post-fix. Threat T-32-05 (DoS via vendor change) is bounded: `split_pane` has zero consumers in Foglet outside `main_menu.ex`, and the change is backward-compatible (existing callers get `divider_char: "|"` by default — same character as before, just now correctly oriented).

## Self-Check: PASSED

- **Created files exist:** `.planning/phases/32-main-menu-chrome-polish/32-02-oneliners-artifact-SUMMARY.md` — written by this commit.
- **Modified files exist:**
  - `lib/foglet_bbs/tui/screens/main_menu.ex` — modified.
  - `vendor/raxol/lib/raxol/ui/layout/split_pane.ex` — modified.
- **Commits exist:**
  - `739122f` — verified via `git log --all | grep 739122f`.

---
*Phase: 32-main-menu-chrome-polish*
*Completed: 2026-04-28*
