---
phase: 32-main-menu-chrome-polish
plan: 03
subsystem: ui
tags: [tui, raxol, tests]

# Dependency graph
requires:
  - phase: 32-main-menu-chrome-polish
    plan: 01
    provides: ":panel-shaped Navigation / Oneliners panels with embedded titles; multi-text-node nav rows (leading + accent bracketed key); one-column inner indent"
  - phase: 32-main-menu-chrome-polish
    plan: 02
    provides: "Clean Oneliners top-border at every canonical width via SplitPane divider orientation fix; main_menu.ex passes divider_char: \" \" through split_pane"
provides:
  - "layout_smoke_test.exs:1077-1118 asserts the Phase 32 render shape (embedded titles, two-node rows)"
  - "layout_smoke_test.exs:1173-1280 anchors right-panel containment on `oneliners_header.x - 1` to account for title-overlay column offset"
  - "layout_smoke_test.exs:1282-1346 (CJK) anchors right-panel containment on the same offset"
  - "main_menu_test.exs assertions (lines 86, 93, 248, 251, 254, 257, 313, 437) align with the post-32-01 two-text-node row shape"
  - "Phase 19 body visual width-budget test enforces `display_width(leading) + 3 <= inner_width` to preserve the right-edge fit invariant for `[X]`"
affects: []

tech-stack:
  added: []
  patterns:
    - "Test assertion against multi-text-node render shapes — leading segment matched by glyph-anchored regex, bracketed-key segment matched by exact `\"[X]\"` membership"
    - "Anchor panel content-area left edge as `header.x - 1` when the panel uses border-embedded title overlay (`:panel` + Panels.process)"

key-files:
  created:
    - ".planning/phases/32-main-menu-chrome-polish/32-03-test-updates-SUMMARY.md"
  modified:
    - "test/foglet_bbs/tui/layout_smoke_test.exs"
    - "test/foglet_bbs/tui/screens/main_menu_test.exs"

key-decisions:
  - "Replace `assert \"Navigation\" in texts` and `assert \"Oneliners\" in texts` in main_menu_test.exs with refute assertions, because collect_text_values/1 walks `:text` children only and never surfaces the panel's `attrs.title` border-embedded overlay (the layout_smoke test asserts the embedded title at the positioned-render layer, providing the existing-test coverage MENU-01 needs)"
  - "Anchor right-panel containment on `oneliners_header.x - 1` (not `oneliners_header.x`): the title overlay is offset one column right of the panel's content-area left edge per Panels.process.create_title_element"
  - "Phase 19 body visual width-budget test: assert `display_width(leading) + 3 <= inner_width` to preserve the right-edge fit invariant for the bracketed `[X]` segment that is now its own text node (and therefore not captured by the leading-segment filter alone)"

requirements-completed:
  - MENU-01
  - MENU-03
  - MENU-04
  - MENU-05

# Metrics
duration: 6m 25s
completed: 2026-04-28
---

# Phase 32 Plan 03: Test Updates Summary

**Updated existing assertions in `layout_smoke_test.exs` and `main_menu_test.exs` to match the Phase 32 render shape — embedded `:panel` title overlays, two-text-node nav rows (leading + accent bracketed key), and the one-column title-column offset on right-panel containment — without adding any net-new test functions (D-13 compliance).**

## Performance

- **Duration:** ~6.5 min
- **Started:** 2026-04-28T03:05:31Z
- **Completed:** 2026-04-28T03:11:56Z
- **Tasks:** 3 (Task 3 verification-only, no commit)
- **Files modified:** 2 (`test/foglet_bbs/tui/layout_smoke_test.exs`, `test/foglet_bbs/tui/screens/main_menu_test.exs`)

## Accomplishments

- Migrated the layout-smoke main_menu tests at lines 1077, 1173, and 1282 from the pre-32-01 text-node shape (`assert &1 == "Navigation"`, `~r/●.*Boards.*B$/`) to the Phase 32 shape (`" Navigation "` / `" Oneliners "` embedded title overlays + standalone `"[B]"`/`"[Q]"` bracketed-key text nodes + glyph-anchored leading-segment regex).
- Re-anchored the right-panel containment assertions in `layout_smoke_test.exs` (lines 1267 and 1334) on `oneliners_header.x - 1` to account for the title-overlay's one-column offset from the content-area left edge — without this, content-row containment would falsely trip because the title overlay sits one column inset from the panel's content area.
- Migrated the screen-level main_menu tests at lines 86, 93, 248, 251, 254, 257, 313, and 437 from the pre-32-01 shape to the Phase 32 shape — splitting each `~r/<glyph>\s+<label>\s+<key>$/` assertion into a `~r/^\s+<glyph>\s+<label>/` leading-segment regex + `"[X]" in texts` bracketed-key membership pair.
- Updated the Phase 19 body visual width-budget test (line 437) to assert `display_width(leading) + 3 <= inner_width` so the right-edge fit invariant for the bracketed `[X]` segment is still enforced even though `[X]` is now its own text node and therefore not captured by the glyph-filter.
- Refuted the body-row `"Navigation"` / `"Oneliners"` titles in main_menu_test.exs (lines 86, 93, 248) — confirming Phase 32 / MENU-01 actually removed the body-row title rather than just adding the border-embedded overlay alongside it. The layout_smoke test asserts the positive presence of the embedded titles at the positioned-render layer.
- D-13 compliance verified: no net-new top-level `test "..."` functions added (`grep -c '^  test ' = 8 == 8`); total `test "` count unchanged (`grep -cE '^[ ]+test "' = 43 == 43`).
- `rtk mix precommit` exits 0 (compile-warnings-as-errors, format, Credo, Sobelow, Dialyzer all pass).

## Task Commits

1. **Task 1: Update layout_smoke_test.exs assertions for the new main_menu render shape** — `ef3e8e2` (test)
2. **Task 2: Update main_menu_test.exs assertions for the new render shape** — `c246d41` (test)
3. **Task 3: Run full mix precommit and lock the phase** — no commit (verification-only; precommit clean)

## Files Created/Modified

- `test/foglet_bbs/tui/layout_smoke_test.exs` — three assertion sites migrated. The 1077-test now asserts `" Navigation "` / `" Oneliners "` overlays + leading-segment regex + `"[B]"` / `"[Q]"` standalone text nodes, and refutes body-row titles. The 1173 and 1282 tests find headers via `" Navigation "` / `" Oneliners "` and use `header.x - 1` as the right-panel content-area left bound.
- `test/foglet_bbs/tui/screens/main_menu_test.exs` — eight assertion sites migrated. Group A (oneliners-strip lines 86, 93) and Group B (line 248) replace bare-title `assert ... in texts` with `refute ... in texts`. Group C (lines 251, 254, 257, 313) splits each bare-key regex into a leading-segment regex + bracketed-key membership pair. Group D (Phase 19 body visual line 437) preserves the right-edge fit invariant by asserting `display_width(leading) + 3 <= inner_width` and additionally proving the bracketed-key text-nodes are present.
- `.planning/phases/32-main-menu-chrome-polish/32-03-test-updates-SUMMARY.md` — this file.

## Acceptance Criteria Status

### Plan-level (per `<verification>`)

- **`rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` exits 0**: PASS (87 tests, 0 failures).
- **`rtk mix test test/foglet_bbs/tui/screens/main_menu_test.exs` exits 0**: PASS (43 tests, 0 failures).
- **`rtk mix precommit` exits 0**: PASS (compile-warnings-as-errors, format, Credo, Sobelow, Dialyzer all pass).
- **All SPEC-level render-output assertions verified via Task 3 final battery**: PASS — see SPEC battery below.
- **Net-new test count unchanged (D-13 compliance)**: PASS — verified `grep -c '^  test '` = 8 == 8; total `test "` = 43 == 43.

### SPEC-level acceptance battery (Task 3)

| Check | Result | Output |
|-------|--------|--------|
| MENU-01: `─ Navigation ─` substring at 80×24 | PASS | `│┌─ Navigation ───────────────┐ ┌─ Oneliners ─────────...─┐│` |
| MENU-01: `─ Oneliners ─` substring at 80×24 | PASS | (same line) |
| MENU-02: Oneliners top-border pipe count W=64 | PASS | `pipes=0` |
| MENU-02: pipe count W=65 | PASS | `pipes=0` |
| MENU-02: pipe count W=66 | PASS | `pipes=0` |
| MENU-02: pipe count W=80 | PASS | `pipes=0` |
| MENU-02: pipe count W=81 | PASS | `pipes=0` |
| MENU-03: `[B]` present at 80×24 | PASS | `[B] OK` |
| MENU-03: `[C]` present at 80×24 | PASS | `[C] OK` |
| MENU-03: `[A]` present at 80×24 | PASS | `[A] OK` |
| MENU-03: `[Q]` present at 80×24 | PASS | `[Q] OK` |
| MENU-04: `│ ● Boards` (one-column indent) at 80×24 | PASS | `INDENT OK` |
| MENU-05: zero color literals in main_menu.ex | PASS | `0` matches |
| D-08 deferral comment preserved | PASS | `lib/foglet_bbs/tui/screens/main_menu.ex:56` still references `per-glyph slot routing` |

### Audit greps (Task 2 acceptance)

| Check | Expected | Actual |
|-------|----------|--------|
| `~r/●.*Boards.*B$/` matches in main_menu_test.exs | 0 | 0 |
| `~r/✎.*Compose.*C$/` matches | 0 | 0 |
| `~r/↯.*Logout.*Q$/` matches | 0 | 0 |
| `~r/◇.*Account.*A$/` matches | 0 | 0 |
| `"[B]" in texts` literal matches in main_menu_test.exs | ≥ 1 | 1 |

## Decisions Made

- **Refute bare titles instead of asserting embedded titles in `main_menu_test.exs`.** The plan instructed `assert " Navigation " in texts` against `collect_text_values/1` output. But `collect_text_values` walks `:text` children only — it never sees the panel's `attrs.title` overlay (the title is rendered by `Panels.process.create_title_element` at the layout stage, not as a tree-level `:text` node). Asserting `" Navigation " in texts` on collect_text_values output would always fail. The right test-update is to `refute "Navigation" in texts` — confirming Phase 32 / MENU-01 actually removed the body-row title — and rely on `layout_smoke_test.exs:1077-1118` (which asserts on `text_elements(positioned)` AFTER layout) to verify the embedded title's positive presence. This decision is a Rule 1 deviation from the plan's literal instruction; the spirit of the plan (test the new shape) is preserved.
- **Anchor right-panel containment on `oneliners_header.x - 1`.** The plan's existing `assert row.x >= oneliners_header.x` containment check (lines 1268, 1335) breaks because the embedded title overlay sits one column right of the content-area left edge — `panel_content_x = panel.x + 1`, but `title_overlay_x = panel.x + 2` per `panels.ex create_title_element`. Without the offset, oneliner rows at `panel_content_x` (correctly inside the panel) would falsely trip the containment assertion. We define `right_panel_content_left = oneliners_header.x - 1` and assert `row.x >= right_panel_content_left`. Inline comments at both sites document the offset rationale.
- **Width-budget assertion update.** The pre-32 shape produced one text node per nav row, so `display_width(row) <= inner_width` was the natural fit invariant. Post-32 the row splits into a leading text node + a bracketed-key text node, and only the leading carries the glyph filter. The leading segment alone trivially fits (it's much narrower than `inner_width`), so the test would pass even if the bracketed key were positioned wrong. Update to `display_width(leading) + 3 <= inner_width` (3 = `display_width("[X]")` for any single-letter `X`) preserves the right-edge fit invariant for the bracketed key.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Bug] Plan's title-assertion shape doesn't match `collect_text_values/1` semantics**
- **Found during:** Task 2
- **Issue:** The plan instructed (Group A line 191, Group B line 209) to replace `assert "Oneliners" in texts` with `assert " Oneliners " in texts`. But `texts` in `main_menu_test.exs` comes from `collect_text_values/1` (defined at `test/support/foglet/tui/render_helpers.ex:29`), which walks the render tree's `:text` children only and does not visit `:panel` `attrs.title`. The `:panel` element type's title is stored in `attrs.title` (a string) and overlaid by `Panels.process.create_title_element` at the LAYOUT stage — it never appears as a tree-level `:text` node. So `assert " Oneliners " in texts` would have failed (verified empirically — pre-edit `texts` output contained `["No oneliners yet.", "└ ", "Actions", ...]` with no embedded title).
- **Fix:** Replace `assert "Oneliners" in texts` with `refute "Oneliners" in texts` (and analogously for `"Navigation"`). The refute confirms MENU-01 actually removed the body-row title; the embedded title's positive presence is asserted at the layout-smoke level (`layout_smoke_test.exs:1100-1101`, where `texts` comes from `text_elements(positioned)` AFTER layout, so Panels.process has materialized the title overlay as a positioned `:text` element).
- **Files modified:** `test/foglet_bbs/tui/screens/main_menu_test.exs` (lines 86, 93, 248).
- **Verification:** `rtk mix test test/foglet_bbs/tui/screens/main_menu_test.exs` — 43 tests, 0 failures.
- **Committed in:** `c246d41` (Task 2 commit).

**2. [Rule 1 — Bug] Plan understated the layout_smoke_test.exs migration scope**
- **Found during:** Task 1 verification (`rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` — 2 additional failures at lines 1173 and 1282).
- **Issue:** The plan's Task 1 only enumerated lines 1077-1118. But `layout_smoke_test.exs` has TWO additional sites that find Navigation/Oneliners headers via `element.text == "Navigation"` / `"Oneliners"` (lines 1218-1228 in the side-by-side test, and 1322-1327 in the CJK test). After 32-01, these elements no longer exist with bare-title text content; the post-layout positioned text is `" Navigation "` / `" Oneliners "` (with surrounding spaces). Plan 32-02's SUMMARY explicitly noted these sites at line 145 ("Migrate `layout_smoke_test.exs:1077-1118` and `:1153-1204` and `:1262-1306`"), so the omission was a Plan 32-03 oversight, not a new discovery.
- **Fix:** Update both sites to find headers via `" Navigation "` / `" Oneliners "`, and update the right-panel containment assertions (lines 1267, 1334) to anchor on `oneliners_header.x - 1` (the content-area left edge sits one column LEFT of the title overlay).
- **Files modified:** `test/foglet_bbs/tui/layout_smoke_test.exs` (3 sites total — 1097-1108 was the Task 1 primary, 1218-1232 and 1267-1278 in test 1173, 1322-1344 in test 1282).
- **Verification:** `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` — 87 tests, 0 failures.
- **Committed in:** `ef3e8e2` (Task 1 commit).

---

**Total deviations:** 2 (both Rule 1 — bug in plan instructions; both auto-fixed inline)
**Impact on plan:** Both deviations preserved the plan's spirit (test the new render shape) while correcting an instruction that didn't match the actual `collect_text_values/1` semantics (deviation 1) and expanding scope to cover sites the plan author had documented elsewhere but omitted from this plan's task list (deviation 2). All Task 3 SPEC acceptance battery checks pass; all D-13 compliance checks pass; precommit exits 0.

## Issues Encountered

None beyond the deviations above.

## TDD Gate Compliance

Plan type is `execute` (not `tdd`); no RED/GREEN gate sequence required. The pre-existing tests already covered the behavior; this plan only updated their assertions to match the new render shape produced by Plans 32-01 and 32-02.

## Next Phase Readiness

- Phase 32 is complete. All 5 requirements (MENU-01..MENU-05) PASS at every canonical width.
- `rtk mix precommit` exits 0; the repo is in a clean state ready to ship.
- The D-08 deferral comment block in `lib/foglet_bbs/tui/screens/main_menu.ex:55-62` is preserved for future per-glyph slot routing work.
- No follow-up plans or hand-offs are needed within this phase.

## Threat Flags

None. The two test files modified flow through the standard `mix precommit` gate (Credo, Sobelow, Dialyzer) — no new external trust boundaries introduced.

## Self-Check: PASSED

- **Created files exist:**
  - `.planning/phases/32-main-menu-chrome-polish/32-03-test-updates-SUMMARY.md` — written by this commit.
- **Modified files exist:**
  - `test/foglet_bbs/tui/layout_smoke_test.exs` — modified in `ef3e8e2`.
  - `test/foglet_bbs/tui/screens/main_menu_test.exs` — modified in `c246d41`.
- **Commits exist:**
  - `ef3e8e2` — verified via `git log --all | grep ef3e8e2`.
  - `c246d41` — verified via `git log --all | grep c246d41`.

---
*Phase: 32-main-menu-chrome-polish*
*Completed: 2026-04-28*
