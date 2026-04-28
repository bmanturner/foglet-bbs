---
phase: 32-main-menu-chrome-polish
plan: 03
type: execute
wave: 3
depends_on:
  - 32-01
  - 32-02
files_modified:
  - test/foglet_bbs/tui/layout_smoke_test.exs
  - test/foglet_bbs/tui/screens/main_menu_test.exs
autonomous: true
requirements:
  - MENU-01
  - MENU-03
  - MENU-04
  - MENU-05
tags:
  - tui
  - tests
  - raxol

must_haves:
  truths:
    - "Existing layout smoke test for main_menu (layout_smoke_test.exs:1077-1118) reflects the new render shape: border-embedded titles via :panel, bracketed [X] keys, one-column inner indent"
    - "Existing screen-level main_menu_test.exs assertions that depend on the bare-key/no-bracket/no-indent shape are updated to assert the new shape"
    - "rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs exits 0"
    - "rtk mix test test/foglet_bbs/tui/screens/main_menu_test.exs exits 0"
    - "rtk mix precommit exits 0 (compile-warnings-as-errors, format, Credo, Sobelow, Dialyzer all pass)"
    - "No NET-NEW test files are created — SPEC's 'no new tests' rule applies to net-new tests; D-13 only authorizes keeping existing tests in sync"
  artifacts:
    - path: "test/foglet_bbs/tui/layout_smoke_test.exs"
      provides: "Updated assertions for main_menu render shape — embedded titles, bracketed keys, indent"
    - path: "test/foglet_bbs/tui/screens/main_menu_test.exs"
      provides: "Updated screen-level assertions for the new nav row shape (e.g. ~r/●\\s+Boards.*\\[B\\]$/ instead of ~r/●\\s+Boards\\s+B$/)"
  key_links:
    - from: "layout_smoke_test.exs:1097-1101"
      to: "MENU-01 — embedded title assertion"
      via: "Assert top-border row contains '─ Navigation ─' and '─ Oneliners ─' substrings"
      pattern: "─ Navigation ─"
    - from: "layout_smoke_test.exs:1104-1108"
      to: "MENU-03 — bracketed key assertion"
      via: "Replace ~r/●.*Boards.*B$/ with a regex matching '[B]' at row end"
      pattern: "\\[B\\]"
    - from: "main_menu_test.exs:251,254,257,313 (and analogous lines)"
      to: "MENU-03 + MENU-04 — bracketed key + indent assertion"
      via: "Replace ~r/●\\s+Boards\\s+B$/ with ~r/●\\s+Boards.*\\[B\\]$/ (or equivalent that asserts the bracketed token at row end)"
      pattern: "\\[B\\]|\\[C\\]|\\[A\\]|\\[Q\\]"
---

<objective>
Update the two existing test files that assert main_menu's render shape so they pass against the new structure produced by Plans 32-01 and 32-02:

- `test/foglet_bbs/tui/layout_smoke_test.exs` — the `main_menu renders Navigation and Oneliners panels at distinct y positions` test at line 1077, which currently asserts `text == "Navigation"` (a body-row title) and `text =~ ~r/●.*Boards.*B$/` (a bare-key right-edge token).
- `test/foglet_bbs/tui/screens/main_menu_test.exs` — multiple assertions across the file that match the old `glyph + label + bare-key` row shape (e.g. lines 251, 254, 257, 313) and the body-row "Navigation"/"Oneliners" titles (lines 86, 93, 248).

Per D-13: SPEC's "no new tests" rule applies to NET-NEW test additions (no new files, no new test functions for new behaviors). Keeping EXISTING tests in sync is required — `mix precommit` would otherwise red-flag the diff. This plan adjusts assertions ONLY; it does not add new tests.

Output: Two updated test files; `rtk mix precommit` passes; the phase-level acceptance criteria from SPEC are confirmed via the existing test surface.
</objective>

<execution_context>
@/Users/brendan.turner/Dev/personal/foglet_bbs/.claude/get-shit-done/workflows/execute-plan.md
@/Users/brendan.turner/Dev/personal/foglet_bbs/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/phases/32-main-menu-chrome-polish/32-SPEC.md
@.planning/phases/32-main-menu-chrome-polish/32-CONTEXT.md
@.planning/phases/32-main-menu-chrome-polish/32-01-SUMMARY.md
@.planning/phases/32-main-menu-chrome-polish/32-02-SUMMARY.md
@AGENTS.md
@lib/foglet_bbs/tui/screens/main_menu.ex
@test/foglet_bbs/tui/layout_smoke_test.exs
@test/foglet_bbs/tui/screens/main_menu_test.exs
</context>

<tasks>

<task type="auto" tdd="false">
  <name>Task 1: Update layout_smoke_test.exs assertions for the new main_menu render shape</name>
  <files>test/foglet_bbs/tui/layout_smoke_test.exs</files>
  <read_first>
    - test/foglet_bbs/tui/layout_smoke_test.exs (entire `main_menu renders Navigation and Oneliners panels at distinct y positions` test, lines 1077-1118)
    - lib/foglet_bbs/tui/screens/main_menu.ex (post-32-01/32-02 shape — for ground-truth on what `text_elements/positioned` returns now)
    - .planning/phases/32-main-menu-chrome-polish/32-01-SUMMARY.md (notes on whether the title appears as a single positioned text element with `text == " Navigation "` or as part of the box-border cells)
  </read_first>
  <action>
    Update the test at `test/foglet_bbs/tui/layout_smoke_test.exs:1077-1118` so its assertions match the new render shape produced by Plan 32-01.

    The current assertions (lines 1097-1108):
    ```elixir
    # D-07: boxed Navigation + Oneliners panel headers.
    assert Enum.any?(texts, &(&1 == "Navigation")),
           "expected 'Navigation' panel header, got: #{inspect(texts)}"

    assert Enum.any?(texts, &(&1 == "Oneliners")),
           "expected 'Oneliners' panel header, got: #{inspect(texts)}"

    # D-08: glyph-shaped Navigation rows (not [B] bracket rows).
    assert Enum.any?(texts, &(&1 =~ ~r/●.*Boards.*B$/)),
           "expected '● Boards    B' row, got: #{inspect(texts)}"

    assert Enum.any?(texts, &(&1 =~ ~r/↯.*Logout.*Q$/)),
           "expected '↯ Logout    Q' row, got: #{inspect(texts)}"
    ```

    Replace with assertions that reflect the Phase 32 shape:

    ```elixir
    # Phase 32 / MENU-01: panel titles are embedded in the box top border via Raxol's
    # :panel element type. Panels.process emits the title as a positioned text element
    # with text " Navigation " (or " Oneliners "), x = panel.x + 2, y = panel.y.
    assert Enum.any?(texts, &(&1 == " Navigation ")),
           "expected embedded ' Navigation ' title (Panels.process overlay), got: #{inspect(texts)}"

    assert Enum.any?(texts, &(&1 == " Oneliners ")),
           "expected embedded ' Oneliners ' title (Panels.process overlay), got: #{inspect(texts)}"

    # Phase 32 / MENU-01: no bare 'Navigation'/'Oneliners' body-row title remains.
    refute Enum.any?(texts, &(&1 == "Navigation")),
           "Phase 32 MENU-01 removes the body-row 'Navigation' title; got: #{inspect(texts)}"

    refute Enum.any?(texts, &(&1 == "Oneliners")),
           "Phase 32 MENU-01 removes the body-row 'Oneliners' title; got: #{inspect(texts)}"

    # Phase 32 / MENU-03: nav rows compose multiple text nodes — primary-color
    # leading segment + accent-color "[X]" trailing segment. The leading segment
    # contains glyph + label + padding; the trailing segment is a bracketed key.
    assert Enum.any?(texts, &(&1 =~ ~r/●\s+Boards/)),
           "expected '● Boards ...' leading segment, got: #{inspect(texts)}"

    assert Enum.any?(texts, &(&1 == "[B]")),
           "expected '[B]' bracketed-key segment, got: #{inspect(texts)}"

    assert Enum.any?(texts, &(&1 =~ ~r/↯\s+Logout/)),
           "expected '↯ Logout ...' leading segment, got: #{inspect(texts)}"

    assert Enum.any?(texts, &(&1 == "[Q]")),
           "expected '[Q]' bracketed-key segment, got: #{inspect(texts)}"
    ```

    The existing `texts` (line 1090) is `Enum.map(elements, & &1.text)` over `text_elements(positioned)`, which returns the FLAT positioned text elements from the layout engine — Panels.process emits the title overlay AS its own `:text` element with content `" Navigation "` (note the leading and trailing space, per `panels.ex:87` `text: " #{title_text} "`). The two text-node nav row composition emits each text node as its own positioned element, so `[B]` and `[Q]` appear as standalone strings in `texts`.

    Keep:
    - The setup block (lines 1078-1086) — unchanged.
    - The `# D-11: no Welcome line.` `refute` block (lines 1092-1094) — unchanged.
    - The `Enum.any?(texts, &String.contains?(&1, "@alice  hello"))` oneliner-row assertion (lines 1110-1112) — unchanged (this row format is out of scope per SPEC).
    - The y-positions assertion (lines 1114-1117) — unchanged, but bump the threshold from `>= 3` to whatever the new render produces. Inspect the actual `ys` count when you run the test; if the title overlay sits at the same y as the panel top border, you may still have ≥ 3 distinct y positions. If the new threshold is different, update `>= 3` accordingly with a comment explaining why.

    Update the test docstring/inline comment to reference Phase 32 instead of D-07/D-08.

    Run `rtk mix format test/foglet_bbs/tui/layout_smoke_test.exs` after editing.
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs:1077 --color 2>&1 | tail -30</automated>
  </verify>
  <acceptance_criteria>
    - `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs:1077` exits 0.
    - The updated test asserts both: (a) `" Navigation "` and `" Oneliners "` are present in `texts` (the embedded-title overlay), AND (b) `"[B]"` and `"[Q]"` are present in `texts` as standalone bracketed-key text nodes.
    - The updated test refutes both `"Navigation"` and `"Oneliners"` as standalone elements (no body-row title remains).
    - The unchanged `@alice  hello` oneliner assertion still passes.
    - `rtk mix format --check-formatted test/foglet_bbs/tui/layout_smoke_test.exs` exits 0.
  </acceptance_criteria>
  <done>
    The `main_menu renders Navigation and Oneliners panels at distinct y positions` test passes against the new render shape.
  </done>
</task>

<task type="auto" tdd="false">
  <name>Task 2: Update main_menu_test.exs assertions for the new render shape</name>
  <files>test/foglet_bbs/tui/screens/main_menu_test.exs</files>
  <read_first>
    - test/foglet_bbs/tui/screens/main_menu_test.exs (focus on lines 78-100, 240-260, 307-340, and 437-465 — these are the assertion sites that match old shape)
    - lib/foglet_bbs/tui/screens/main_menu.ex (post-32-01 shape — the `collect_text_values/1` helper used by the test flattens text nodes; the new nav rows produce two separate text values per row instead of one)
  </read_first>
  <action>
    Update assertions in `test/foglet_bbs/tui/screens/main_menu_test.exs` that depend on the old render shape. Specifically:

    **Group A — `Oneliners` body-row title assertions (lines 86, 93):**

    Current (line 86 and 93 — same shape):
    ```elixir
    assert "Oneliners" in texts
    ```

    These run inside `describe "oneliners strip"` tests that confirm the panel renders. After Phase 32 the title is overlaid as `" Oneliners "` (with surrounding spaces, per `Panels.process.create_title_element` at `panels.ex:87`).

    Update to:
    ```elixir
    # Phase 32 / MENU-01: title is embedded in the box top border as " Oneliners "
    # (with surrounding spaces from Panels.process.create_title_element).
    assert " Oneliners " in texts
    ```

    Apply the same change at line 93.

    **Group B — `Navigation` body-row title assertion (line 248):**

    Current:
    ```elixir
    # D-07: boxed Navigation panel header replaces it.
    assert "Navigation" in texts
    ```

    Update to:
    ```elixir
    # Phase 32 / MENU-01: title is embedded in the box top border as " Navigation ".
    assert " Navigation " in texts
    ```

    **Group C — bare-key nav row regex assertions (lines 251, 254, 257, 313):**

    Current shape (line 251 example):
    ```elixir
    assert Enum.any?(texts, &(&1 =~ ~r/●\s+Boards\s+B$/)),
           "expected '● Boards    B' shaped row; got: #{inspect(texts)}"
    ```

    Phase 32 splits each nav row into two text nodes: a leading segment (`" ● Boards     "`) and a trailing bracketed-key segment (`"[B]"`). The single-text-node `~r/●\s+Boards\s+B$/` regex no longer matches anything in `texts`.

    Update each (lines 251, 254, 257, 313) to assert BOTH halves exist. Example for line 251:
    ```elixir
    # Phase 32 / MENU-03: nav row composed of leading segment + bracketed-key segment.
    # MENU-04: leading segment begins with one-column indent (single space).
    assert Enum.any?(texts, &(&1 =~ ~r/^\s+●\s+Boards/)),
           "expected ' ● Boards ...' leading segment; got: #{inspect(texts)}"

    assert "[B]" in texts,
           "expected '[B]' bracketed-key segment; got: #{inspect(texts)}"
    ```

    Apply analogous updates at:
    - Line 254 (Compose / `[C]`).
    - Line 257 (Logout / `[Q]`).
    - Line 313 (Account / `[A]`).
    - Any other line in the file that uses a `~r/<glyph>\s+<label>\s+<bareKey>$/` regex — search with `rtk grep -nE 'glyph.*label.*[A-Z]\$' test/foglet_bbs/tui/screens/main_menu_test.exs`.

    **Group D — `Phase 19 body visual` width-budget test (lines 437-465):**

    The test at line 437 asserts `Foglet.TUI.TextWidth.display_width(row) <= inner_width` for every row containing a glyph. After Phase 32, `texts` returns each row as TWO entries (leading + bracketed key), so `nav_rows` (filtered to rows containing a glyph) only captures the leading segment. The display_width of the leading segment alone is well under `inner_width`. The assertion still holds, BUT the test no longer covers the right-edge fit of the bracketed key.

    Update the test to ALSO confirm the bracketed-key node fits:
    ```elixir
    # Phase 32 / MENU-03: each nav row now has two text nodes.
    # The leading segment is rendered first (starts with " " indent + glyph + ...),
    # and the bracketed-key segment ([B], [C], etc.) follows.
    # Both must fit within inner_width when their display_widths are summed.
    nav_leading_rows =
      texts
      |> Enum.filter(fn row ->
        Enum.any?(["●", "✎", "◇", "⚑", "▣", "↯"], &String.contains?(row, &1))
      end)

    bracketed_keys = Enum.filter(texts, &(&1 =~ ~r/^\[[A-Z]\]$/))

    assert nav_leading_rows != [],
           "expected at least one nav leading segment for role=#{role} at #{inspect({width, height})}; got: #{inspect(texts)}"

    assert bracketed_keys != [],
           "expected at least one bracketed-key segment for role=#{role} at #{inspect({width, height})}; got: #{inspect(texts)}"

    inner_width = MainMenu.__nav_panel_inner_width__(state)

    for row <- nav_leading_rows do
      # Leading segment + a 3-cell "[X]" bracketed key + ≥1 cell of separating padding
      # must fit within inner_width.
      assert Foglet.TUI.TextWidth.display_width(row) + 3 + 1 <= inner_width,
             "nav row '#{row}' + bracketed-key budget exceeds inner_width=#{inner_width} for role=#{role} at #{inspect({width, height})}"
    end
    ```

    Keep the `for {width, height} <- ...` and `for role <- ...` outer loops unchanged.

    **Group E — any test depending on the bare-key shape that this audit missed:**

    Run `rtk mix test test/foglet_bbs/tui/screens/main_menu_test.exs --color` and triage failures. Fix each by aligning the assertion with Phase 32's two-text-node-per-row + embedded-title shape. DO NOT add new test functions — D-13 only authorizes updating existing assertions.

    Run `rtk mix format test/foglet_bbs/tui/screens/main_menu_test.exs` after editing.
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/screens/main_menu_test.exs --color 2>&1 | tail -20</automated>
  </verify>
  <acceptance_criteria>
    - `rtk mix test test/foglet_bbs/tui/screens/main_menu_test.exs` exits 0.
    - `rtk grep -nE '~r/●.*Boards.*B\$/' test/foglet_bbs/tui/screens/main_menu_test.exs` returns 0 matches (old bare-key regex gone).
    - `rtk grep -nE '~r/✎.*Compose.*C\$/' test/foglet_bbs/tui/screens/main_menu_test.exs` returns 0 matches.
    - `rtk grep -nE '~r/↯.*Logout.*Q\$/' test/foglet_bbs/tui/screens/main_menu_test.exs` returns 0 matches.
    - `rtk grep -nE '~r/◇.*Account.*A\$/' test/foglet_bbs/tui/screens/main_menu_test.exs` returns 0 matches.
    - `rtk grep -nF '"[B]" in texts' test/foglet_bbs/tui/screens/main_menu_test.exs` returns at least 1 match (new bracketed-key assertion present).
    - `rtk grep -nF '" Navigation "' test/foglet_bbs/tui/screens/main_menu_test.exs` returns at least 1 match (embedded title with surrounding spaces).
    - `rtk grep -nF '" Oneliners "' test/foglet_bbs/tui/screens/main_menu_test.exs` returns at least 2 matches.
    - No NEW `test "..." do` blocks were added — verify by counting before and after: the file's `test "` count should be unchanged. Capture before by `git show HEAD:test/foglet_bbs/tui/screens/main_menu_test.exs | grep -c '^  test '` and compare to `grep -c '^  test ' test/foglet_bbs/tui/screens/main_menu_test.exs` after the edit; counts must be equal.
    - `rtk mix format --check-formatted test/foglet_bbs/tui/screens/main_menu_test.exs` exits 0.
  </acceptance_criteria>
  <done>
    All existing assertions in `main_menu_test.exs` align with the new Phase 32 render shape; no net-new tests were added; the file passes.
  </done>
</task>

<task type="auto" tdd="false">
  <name>Task 3: Run full mix precommit and lock the phase</name>
  <files>(verification only — no file edits expected unless precommit surfaces a regression)</files>
  <read_first>
    - lib/foglet_bbs/tui/screens/main_menu.ex (final state)
    - test/foglet_bbs/tui/layout_smoke_test.exs (final state)
    - test/foglet_bbs/tui/screens/main_menu_test.exs (final state)
  </read_first>
  <action>
    Run the project's finish-line gate:

    ```
    rtk mix precommit
    ```

    Per AGENTS.md, this runs: compile-with-warnings-as-errors, format check, Credo, Sobelow, Dialyzer.

    If any check fails, triage and fix:
    - **Compile warnings:** likely unused `inner_width` argument or a stale alias if Plan 32-01's nav_row signature changed. Fix in `main_menu.ex`.
    - **Format check:** run `rtk mix format` on the offending file.
    - **Credo:** address style issues; if a Credo finding requires a structural change, document the fix in the SUMMARY.
    - **Sobelow:** unlikely to flag this work (no new IO/network surfaces); if it does, address per Sobelow guidance.
    - **Dialyzer:** if a spec mismatch surfaces (e.g. `nav_panel/3` returning a map instead of the previous box element type), update the relevant `@spec` to match the new return shape (`map()` is the safest, but match the existing screen-module conventions for other render helpers if they exist).

    Re-run `rtk mix precommit` after fixes until it exits 0.

    Confirm the phase-level acceptance criteria from SPEC by running this final battery:

    ```
    # MENU-01: embedded titles
    rtk mix foglet.tui.render main_menu --width 80 --height 24 | grep -F '─ Navigation ─'
    rtk mix foglet.tui.render main_menu --width 80 --height 24 | grep -F '─ Oneliners ─'

    # MENU-02: clean Oneliners top border at all five widths
    for w in 64 65 66 80 81; do
      PIPE_COUNT=$(rtk mix foglet.tui.render main_menu --width $w --height 22 | grep -F '┌─ Oneliners' | head -1 | grep -c '|')
      echo "W=$w pipes=$PIPE_COUNT"
    done

    # MENU-03: bracketed accent keys
    for k in B C A Q; do
      rtk mix foglet.tui.render main_menu --width 80 --height 24 | grep -F "[$k]" >/dev/null && echo "[$k] OK" || echo "[$k] MISSING"
    done

    # MENU-04: one-column inner indent
    rtk mix foglet.tui.render main_menu --width 80 --height 24 | grep -E '│ ● Boards' >/dev/null && echo "INDENT OK" || echo "INDENT MISSING"

    # MENU-05: zero color literals
    rtk grep -nE 'IO\.ANSI|\\\\e\[|fg:\s*:[a-z]+|fg:\s*"#[0-9a-fA-F]' lib/foglet_bbs/tui/screens/main_menu.ex | grep -v '^#' | wc -l
    ```

    Each check must produce the expected output (substrings present, `pipes=0` everywhere, `OK` for every key, `INDENT OK`, color-literal count `0`).
  </action>
  <verify>
    <automated>rtk mix precommit 2>&1 | tail -20</automated>
  </verify>
  <acceptance_criteria>
    - `rtk mix precommit` exits 0 (compile-warnings-as-errors, format, Credo, Sobelow, Dialyzer all pass).
    - `rtk mix foglet.tui.render main_menu --width 80 --height 24 | grep -F '─ Navigation ─'` exits 0.
    - `rtk mix foglet.tui.render main_menu --width 80 --height 24 | grep -F '─ Oneliners ─'` exits 0.
    - For each width in {64, 65, 66, 80, 81}: the Oneliners top border row contains zero `|` characters.
    - For each of {`[B]`, `[C]`, `[A]`, `[Q]`}: present in the 80×24 render.
    - `rtk mix foglet.tui.render main_menu --width 80 --height 24 | grep -E '│ ● Boards'` exit 0 (one-column indent).
    - `rtk grep -nE 'IO\.ANSI|\\\\e\[|fg:\s*:[a-z]+|fg:\s*"#[0-9a-fA-F]' lib/foglet_bbs/tui/screens/main_menu.ex | grep -v '^#' | wc -l` returns 0.
    - The `# Per D-08: per-glyph slot routing ... DEFERRED` comment block at `lib/foglet_bbs/tui/screens/main_menu.ex:55-62` is unchanged (verify: `rtk grep -n 'per-glyph slot routing' lib/foglet_bbs/tui/screens/main_menu.ex` still returns a match).
  </acceptance_criteria>
  <done>
    `rtk mix precommit` exits 0 and every SPEC-level acceptance criterion is verified passing.
  </done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Test assertions → CI | Test file changes flow through `mix precommit` (Credo, Sobelow, Dialyzer). No external trust boundaries are crossed by test edits. |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-32-06 | Tampering | Test assertions silently weakened | mitigate | Acceptance criteria require explicit grep matches confirming both the old assertions are gone (`~r/●.*Boards.*B$/` removed) AND the new assertions are present (`"[B]" in texts`, `" Navigation "` etc.). Net-new test count is verified unchanged via `git show HEAD` diff. |
| T-32-07 | Spoofing | A passing test that doesn't actually exercise the new shape | mitigate | The verify command runs the actual test (not just compile), and the SPEC-level render-output checks (Task 3) independently confirm the rendered output matches the new shape — providing two independent signals (test pass + render grep). |
</threat_model>

<verification>
- `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` exits 0.
- `rtk mix test test/foglet_bbs/tui/screens/main_menu_test.exs` exits 0.
- `rtk mix precommit` exits 0.
- All SPEC-level render-output assertions (MENU-01..MENU-05) verified via the final battery in Task 3.
- Net-new test count unchanged (D-13 compliance).
</verification>

<success_criteria>
- Phase 32 acceptance criteria from SPEC are all satisfied and demonstrably passing.
- The repo is in a clean precommit state and ready to ship.
- The D-08 deferral comment block in `main_menu.ex` is preserved.
</success_criteria>

<output>
After completion, create `.planning/phases/32-main-menu-chrome-polish/32-03-SUMMARY.md` documenting:
- The two test files updated and the assertion-by-assertion mapping (old → new).
- Confirmation that no net-new test functions were added (D-13).
- The full `rtk mix precommit` exit status.
- The full SPEC acceptance-criteria battery output (each MENU-XX check, pass/fail).
</output>
