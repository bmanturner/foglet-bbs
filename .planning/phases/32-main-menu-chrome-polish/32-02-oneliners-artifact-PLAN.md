---
phase: 32-main-menu-chrome-polish
plan: 02
type: execute
wave: 2
depends_on:
  - 32-01
files_modified:
  - lib/foglet_bbs/tui/screens/main_menu.ex
autonomous: true
requirements:
  - MENU-02
tags:
  - tui
  - raxol
  - chrome
  - width-math

must_haves:
  truths:
    - "Oneliners panel top border row at widths 64, 65, 66, 80, and 81 contains zero '|' characters"
    - "Oneliners panel top border row at every tested width contains only characters drawn from {┌, ─, ┐, space, embedded-title chars}"
    - "If the artifact persisted after Plan 32-01, the root cause is documented (split_pane rounding vs. Panels.process border math vs. screen-level child widths) and the minimal fix is applied — preferring main_menu.ex over vendor/raxol changes"
  artifacts:
    - path: "lib/foglet_bbs/tui/screens/main_menu.ex"
      provides: "Oneliners panel that renders a clean top border at every supported width — either organically (if 32-01's :panel switch resolved it) or via a minimal width-math fix in this plan"
  key_links:
    - from: "Oneliners top border row"
      to: "Raxol Panels.process border math"
      via: "%{type: :panel} routing in oneliners_panel/2"
      pattern: "%\\{type: :panel"
---

<objective>
Verify the Oneliners panel's top border is a clean horizontal rule at all five canonical widths (64, 65, 66, 80, 81) after Plan 32-01 lands the `:panel` element switch — and, if any artifact persists, investigate root cause and apply the minimal fix in `lib/foglet_bbs/tui/screens/main_menu.ex` (D-03/D-04).

Per D-03: do NOT pre-commit to a fix location. There is no current evidence that `split_pane(ratio: {2,3})` is the root cause; the `||||` artifact may resolve organically once the first-body-row title node is gone and panel borders flow through `Panels.process` instead of the previous `box do…end`-with-prepended-title shape.

Per D-04: if the artifact persists, investigate before fixing. Reproduce at the affected widths, identify whether the cause is screen-level explicit child widths, `Panels.process` border math, or `split_pane` rounding, and apply the minimal fix. Vendor changes only if the root cause is unambiguously in `vendor/raxol/`.

Output: Updated `lib/foglet_bbs/tui/screens/main_menu.ex` (if a fix is needed); otherwise a documented verification result confirming MENU-02 is satisfied organically by 32-01.
</objective>

<execution_context>
@/Users/brendan.turner/Dev/personal/foglet_bbs/.claude/get-shit-done/workflows/execute-plan.md
@/Users/brendan.turner/Dev/personal/foglet_bbs/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/phases/32-main-menu-chrome-polish/32-SPEC.md
@.planning/phases/32-main-menu-chrome-polish/32-CONTEXT.md
@.planning/phases/32-main-menu-chrome-polish/32-01-SUMMARY.md
@lib/foglet_bbs/tui/screens/main_menu.ex
@vendor/raxol/lib/raxol/ui/layout/panels.ex
@vendor/raxol/lib/raxol/ui/layout/engine.ex
@vendor/raxol/lib/raxol/ui/ui_renderer.ex
</context>

<tasks>

<task type="auto" tdd="false">
  <name>Task 1: Reproduce and characterize the Oneliners top-border render at widths 64, 65, 66, 80, 81</name>
  <files>lib/foglet_bbs/tui/screens/main_menu.ex</files>
  <read_first>
    - lib/foglet_bbs/tui/screens/main_menu.ex (post-32-01 shape — `oneliners_panel/2` should now be a `%{type: :panel}` element, no body-row title node)
    - .planning/phases/32-main-menu-chrome-polish/32-01-SUMMARY.md (notes from Plan 32-01 about whether the artifact was observed during 32-01 verification)
  </read_first>
  <action>
    Run the following five commands and capture the Oneliners panel's top border row from each:

    ```
    rtk mix foglet.tui.render main_menu --width 64 --height 22
    rtk mix foglet.tui.render main_menu --width 65 --height 22
    rtk mix foglet.tui.render main_menu --width 66 --height 22
    rtk mix foglet.tui.render main_menu --width 80 --height 22
    rtk mix foglet.tui.render main_menu --width 81 --height 22
    ```

    The Oneliners panel sits on the right side of the `split_pane(ratio: {2,3})`. Its top border row is the first row of that panel — identifiable as the row containing `┌─ Oneliners ─`.

    For EACH width, extract the Oneliners top-border row and check:
    1. Does the row contain ANY `|` character (vertical bar, ASCII 0x7C)?
    2. Does the row contain any non-{`┌`, `─`, `┐`, space} characters OTHER than the embedded title segment ` Oneliners `?
    3. Does the row appear "clean" — i.e. is it `┌─ Oneliners ─...─┐` followed by spaces if the row is wider than the panel?

    Record the result per width as PASS (clean) or FAIL (artifact detected, with the offending characters/positions noted).

    If ALL FIVE widths PASS: the artifact resolved organically with the `:panel` switch in 32-01. MENU-02 is satisfied; proceed to Task 3 (no-op summary).

    If ANY width FAILS: proceed to Task 2 to investigate root cause and apply a minimal fix.

    Save the captured rows to a temporary scratch file (e.g. `/tmp/menu02-renders.txt`) for reference during root-cause analysis.
  </action>
  <verify>
    <automated>for w in 64 65 66 80 81; do rtk mix foglet.tui.render main_menu --width $w --height 22 2>&1 | grep -F '┌─ Oneliners' | head -1 | tee -a /tmp/menu02-renders.txt; done; echo "---"; grep -c '|' /tmp/menu02-renders.txt</automated>
  </verify>
  <acceptance_criteria>
    - Five render commands executed, each producing an Oneliners top-border row in `/tmp/menu02-renders.txt` (verify: `wc -l /tmp/menu02-renders.txt` ≥ 5).
    - For EACH of widths 64, 65, 66, 80, 81: `rtk mix foglet.tui.render main_menu --width <N> --height 22 | grep -F '┌─ Oneliners' | head -1 | grep -c '|'` returns 0 (no pipe characters in the Oneliners top border row).
    - If any width returns a non-zero `|` count, the per-width pass/fail status is recorded explicitly and Task 2 proceeds; otherwise Task 2 is a documented no-op.
  </acceptance_criteria>
  <done>
    Per-width pass/fail status determined for all five widths; renders captured for reference.
  </done>
</task>

<task type="auto" tdd="false">
  <name>Task 2: If artifact persists, investigate root cause and apply minimal fix in main_menu.ex</name>
  <files>lib/foglet_bbs/tui/screens/main_menu.ex</files>
  <read_first>
    - /tmp/menu02-renders.txt (captured rows from Task 1)
    - lib/foglet_bbs/tui/screens/main_menu.ex (focus on `render/1` lines 77-97 — the `split_pane(ratio: {2,3}, ...)` composition is the candidate site for screen-level child width adjustment)
    - vendor/raxol/lib/raxol/ui/layout/panels.ex (Panels.process/3 border math at line 36; `measure_panel`, `create_panel_box`, `calculate_inner_space`)
    - vendor/raxol/lib/raxol/ui/layout/engine.ex (process_element :split_pane and :panel routing)
    - vendor/raxol/lib/raxol/ui/ui_renderer.ex (cell merge order for :panel and :box, line 140 onward)
  </read_first>
  <action>
    SKIP THIS TASK if Task 1 confirmed all five widths PASS. Record in summary as "no-op — organically resolved by 32-01 panel switch."

    Otherwise, investigate root cause:

    1. **Hypothesis A — split_pane rounding:** `split_pane(ratio: {2,3}, ...)` may round the right child's width to a value that, combined with `Panels.process` border math (`@border_thickness = 1`, `@title_x_offset = 2`, `@double_border = 2`), produces a top-border row that overflows or underfills the available width. Test: at the affected width, what width does `Panels.process` see for the Oneliners panel? (Add a `IO.inspect` temporarily in `oneliners_panel/2` or instrument the render — REMOVE BEFORE COMMIT.)

    2. **Hypothesis B — `Panels.process` `measure_panel` math:** The panel border is rendered as part of the `:box` element via `create_panel_box`. If the `:box` border-character generation has an off-by-one at certain widths, the artifact is in vendor/raxol.

    3. **Hypothesis C — Cell-merge order in `ui_renderer.ex`:** The title overlay `" Oneliners "` is positioned at `(space.x + 2, space.y)` and overlays whichever cells the underlying `:box` painted. If the box's top border cells are themselves correct but the title overlay collides with a `│` at certain widths, the artifact would manifest as `┌─ Oneliners ─┐` followed by `│` instead of `─`.

    4. **Apply the minimal fix.** Preferred fix locations in order:
       a. **`main_menu.ex`** — adjust `render/1`'s `split_pane` call (e.g. add `min_size:` adjustments, change ratio, set explicit child widths) OR pass a width-aware `attrs` to `oneliners_panel/2`. This is the preferred fix surface per D-04.
       b. **vendor/raxol** — only if the root cause is unambiguously a vendor bug (e.g. `Panels.process` math mis-counts border cells). If a vendor fix is needed, document the rationale clearly in the SUMMARY and keep the diff minimal.

    Do NOT change `nav_panel/3`, `nav_row/3`, or any of the Plan 32-01 work. Do NOT introduce a new widget module (D-12).

    After applying the fix, RE-RUN the five render commands from Task 1 and re-verify all five widths PASS.

    Run `rtk mix format` after editing.
  </action>
  <verify>
    <automated>for w in 64 65 66 80 81; do PIPE_COUNT=$(rtk mix foglet.tui.render main_menu --width $w --height 22 2>&1 | grep -F '┌─ Oneliners' | head -1 | grep -c '|'); echo "W=$w pipes=$PIPE_COUNT"; done</automated>
  </verify>
  <acceptance_criteria>
    - For EACH of widths 64, 65, 66, 80, 81: the Oneliners top-border row contains zero `|` characters (verified via the verify command — every line of output reads `pipes=0`).
    - For EACH of those widths: `rtk mix foglet.tui.render main_menu --width <N> --height 22 | grep -F '┌─ Oneliners' | head -1 | tr -d ' Oneliners─┌┐'` returns an empty string (no characters remain after stripping the allowed alphabet). Run as: `for w in 64 65 66 80 81; do REMAINING=$(rtk mix foglet.tui.render main_menu --width $w --height 22 | grep -F '┌─ Oneliners' | head -1 | tr -d ' Oneliners─┌┐'); echo "W=$w remaining='$REMAINING'"; done` — every line should show `remaining=''`.
    - If a vendor change was needed, the diff in `vendor/raxol/` is minimal (≤ ~10 lines) and documented in the SUMMARY with the reproduction case.
    - `rtk grep -nE 'IO\.ANSI|\\\\e\[|fg:\s*:[a-z]+|fg:\s*"#[0-9a-fA-F]' lib/foglet_bbs/tui/screens/main_menu.ex | grep -v '^#'` still returns 0 matches (MENU-05 grep gate not regressed).
    - `rtk mix compile --warnings-as-errors` exits 0.
    - No temporary `IO.inspect` calls left in committed code (verify: `rtk grep -n 'IO\.inspect' lib/foglet_bbs/tui/screens/main_menu.ex` returns 0 matches).
  </acceptance_criteria>
  <done>
    Either (a) Task 1 verified all five widths PASS organically and this task is a documented no-op, or (b) the root cause was identified, the minimal fix was applied (preferentially in `main_menu.ex`), and all five widths now PASS.
  </done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| TUI render → terminal | Same as Plan 32-01 — no untrusted input enters this width-math fix. |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-32-04 | Tampering | width-math fix in main_menu.ex (if applied) | mitigate | Any fix preserves the MENU-05 grep gate (acceptance criterion verifies it). The fix is purely arithmetic/positional — no new color or text input surfaces. |
| T-32-05 | Denial of service | vendor/raxol Panels.process math (if changed) | accept | A minimal vendor patch (≤ ~10 lines, restricted to border-cell counting) cannot regress unrelated screens — they all flow through the same `Panels.process` and would show the same artifact pre-fix. Documented reproduction case in the SUMMARY makes the change reviewable. |
</threat_model>

<verification>
- All five widths (64, 65, 66, 80, 81) produce an Oneliners top border with zero `|` characters and only allowed alphabet characters.
- `rtk mix compile --warnings-as-errors` exits 0.
- MENU-05 grep gate (zero color literals in `main_menu.ex`) is not regressed.
- If a vendor diff was applied, the change is minimal and the rationale is documented in the SUMMARY.
</verification>

<success_criteria>
- MENU-02 acceptance criteria satisfied: Oneliners top border contains exclusively `{┌, ─, ┐, space}` plus the embedded title segment at all five canonical widths.
- Either organic resolution from 32-01 is confirmed (preferred) or a minimal targeted fix lands.
- Plan 32-01 work is preserved (no regressions to MENU-01, MENU-03, MENU-04, MENU-05).
</success_criteria>

<output>
After completion, create `.planning/phases/32-main-menu-chrome-polish/32-02-SUMMARY.md` documenting:
- Per-width pass/fail status (64, 65, 66, 80, 81) BEFORE any fix.
- Whether the artifact resolved organically with 32-01's `:panel` switch.
- If a fix was needed: the root cause hypothesis confirmed, the fix location chosen, and the diff applied.
- Per-width pass/fail status AFTER the fix (must be all PASS).
- Confirmation that MENU-05 grep gate remains clean.
</output>
