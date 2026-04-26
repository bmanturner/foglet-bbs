---
phase: 25
plan: 06
type: execute
wave: 3
depends_on: [04]
files_modified:
  - test/support/foglet/tui/layout_smoke/sysop_helper.ex
autonomous: true
requirements:
  - SYSOP-01
user_setup: []
tags:
  - tui
  - operator-console
  - sysop
  - elixir
  - gap-closure

must_haves:
  truths:
    - "register_sysop_size_contracts/0 contains exactly five describe blocks: 'sysop site tab — size contract', 'sysop limits tab — size contract', 'sysop boards tab — size contract', 'sysop users tab — size contract', 'sysop system tab — size contract'."
    - "Each describe block iterates [{64,22},{80,24}] with bounds and primitive-sentinel assertions."
    - "SITE and LIMITS blocks assert '[Enter] Submit' sentinel (Modal.Form footer)."
    - "USERS block asserts 'Handle' sentinel (ConsoleTable column header)."
    - "SYSTEM block asserts 'Sessions:' or 'Version:' sentinel (KvGrid key label)."
    - "BOARDS block retains the existing bounds assertion from the Plan 01 sentinel."
    - "mix precommit passes."
  artifacts:
    - path: "test/support/foglet/tui/layout_smoke/sysop_helper.ex"
      provides: "Full five-tab size-contract registry for register_sysop_size_contracts/0."
      contains: "sysop site tab — size contract"
  key_links:
    - from: "test/support/foglet/tui/layout_smoke/sysop_helper.ex"
      to: "lib/foglet_bbs/tui/screens/sysop.ex"
      via: "Sysop.render/1 called for each tab to assert primitive sentinels within bounds"
      pattern: "set_active_tab"
---

<objective>
Close the single Phase 25 verification gap: complete `register_sysop_size_contracts/0` in
`test/support/foglet/tui/layout_smoke/sysop_helper.ex` with the five per-tab size-contract
blocks required by Plan 04 Task 3 (D-09, D-10).

The file currently contains only the Plan 01 sentinel BOARDS block. This plan adds the
four missing blocks (SITE, LIMITS, USERS, SYSTEM) and replaces the sentinel BOARDS comment
with the canonical block keeping the same assertion logic.

Verification requirement: `mix test test/foglet_bbs/tui/layout_smoke_test.exs` green and
`grep -r "sysop site tab" test/` returns a result.
</objective>

<execution_context>
@/Users/brendan.turner/Dev/personal/foglet_bbs/.claude/get-shit-done/workflows/execute-plan.md
@/Users/brendan.turner/Dev/personal/foglet_bbs/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/phases/25-operator-console-conversion/25-CONTEXT.md
@.planning/phases/25-operator-console-conversion/25-VERIFICATION.md
@AGENTS.md
@test/support/foglet/tui/layout_smoke/account_helper.ex
@test/support/foglet/tui/layout_smoke/sysop_helper.ex
@lib/foglet_bbs/tui/screens/sysop.ex
@lib/foglet_bbs/tui/screens/sysop/state.ex
</context>

<tasks>

## Task 1 — Complete sysop_helper.ex with all five per-tab size-contract blocks

<read_first>
- test/support/foglet/tui/layout_smoke/sysop_helper.ex (file to modify — read current state)
- test/support/foglet/tui/layout_smoke/account_helper.ex (pattern to follow)
- lib/foglet_bbs/tui/screens/sysop.ex (Sysop.init_screen_state/0 and render/1 signatures)
- lib/foglet_bbs/tui/screens/sysop/state.ex (tab order: ["SITE","BOARDS","LIMITS","SYSTEM","USERS"])
- lib/foglet_bbs/tui/screens/sysop/site_form.ex (sentinel: "[Enter] Submit" footer)
- lib/foglet_bbs/tui/screens/sysop/limits_form.ex (sentinel: "[Enter] Submit" footer)
- lib/foglet_bbs/tui/screens/sysop/users_view.ex (sentinel: "Handle" column header)
- lib/foglet_bbs/tui/screens/sysop/system_snapshot.ex (sentinel: "Sessions:" or "Version:" KvGrid key)
</read_first>

<action>
Replace the entire body of `register_sysop_size_contracts/0` in
`test/support/foglet/tui/layout_smoke/sysop_helper.ex` with five describe blocks.
Keep the module `@moduledoc` unchanged; update only the macro body.

The macro `quote do` block must contain these five describe blocks in this order:
1. `"sysop site tab — size contract"` — set_active_tab("SITE"), assert "[Enter] Submit"
2. `"sysop limits tab — size contract"` — set_active_tab("LIMITS"), assert "[Enter] Submit"
3. `"sysop boards tab — size contract"` — set_active_tab("BOARDS"), bounds assertion (same as existing sentinel, remove the "sentinel" label from the describe string to make it canonical)
4. `"sysop users tab — size contract"` — set_active_tab("USERS"), assert "Handle" header sentinel
5. `"sysop system tab — size contract"` — set_active_tab("SYSTEM"), assert "Sessions:" KvGrid sentinel

Each block follows this structure (copy from the existing sentinel block, adapt tab and assertion):

```elixir
describe "sysop <tab> tab — size contract" do
  for {width, height} <- [{64, 22}, {80, 24}] do
    @width width
    @height height
    @tag :"sysop <tab> size contract"
    test "at #{width}x#{height} <primitive> sentinel renders within bounds" do
      width = @width
      height = @height

      ss =
        Sysop.init_screen_state()
        |> set_active_tab("<TAB_LABEL>")

      state =
        %Foglet.TUI.App{
          current_screen: :sysop,
          current_user: %{
            id: "u1",
            handle: "sysop",
            role: :sysop,
            status: :active
          },
          session_context: %{},
          terminal_size: {width, height},
          screen_state: %{sysop: ss}
        }
        |> Map.from_struct()

      tree = Sysop.render(state)
      positioned = apply_at_size(tree, {width, height})
      elements = text_elements(positioned)

      for el <- elements do
        assert el.x + TextWidth.display_width(el.text) <= width,
               "element #{inspect(el.text)} at x=#{el.x} exceeds width #{width}"
      end

      texts = Enum.map(elements, & &1.text)

      assert Enum.any?(texts, &String.contains?(&1, "<SENTINEL>")),
             "expected '<SENTINEL>' at #{width}x#{height}"
    end
  end
end
```

Sentinels per tab:
- SITE: `"[Enter] Submit"` — Modal.Form action footer
- LIMITS: `"[Enter] Submit"` — Modal.Form action footer
- BOARDS: keep existing bounds-only assertion; no extra sentinel assert needed (bounds check is sufficient for the canonical boards block)
- USERS: `"Handle"` — ConsoleTable column header
- SYSTEM: `"Sessions:"` — KvGrid key label

For the BOARDS block, keep the existing full assertion body from the sentinel block unchanged. Just rename
the describe string from `"sysop boards tab — size contract (Phase 25 helper sentinel)"` to
`"sysop boards tab — size contract"` and remove the sentinel-specific comment.

The `import` and `alias` declarations at the top of the `quote do` block should be:
```elixir
import Foglet.TUI.LayoutSmokeHelpers, only: [set_active_tab: 2]

alias Foglet.TUI.Screens.Sysop
alias Foglet.TUI.TextWidth
```
</action>

<acceptance_criteria>
- `grep -r "sysop site tab — size contract" test/` returns a result in sysop_helper.ex
- `grep -r "sysop limits tab — size contract" test/` returns a result in sysop_helper.ex
- `grep -r "sysop boards tab — size contract" test/` returns a result in sysop_helper.ex (without the word "sentinel")
- `grep -r "sysop users tab — size contract" test/` returns a result in sysop_helper.ex
- `grep -r "sysop system tab — size contract" test/` returns a result in sysop_helper.ex
- `grep -c "describe \"sysop" test/support/foglet/tui/layout_smoke/sysop_helper.ex` returns `5`
- `mix test test/foglet_bbs/tui/layout_smoke_test.exs` exits 0
</acceptance_criteria>

</tasks>

<verification>
Run after implementation:

```bash
# Sentinel presence
grep -r "sysop site tab — size contract" test/
grep -r "sysop limits tab — size contract" test/
grep -r "sysop users tab — size contract" test/
grep -r "sysop system tab — size contract" test/
grep -c "describe \"sysop" test/support/foglet/tui/layout_smoke/sysop_helper.ex

# Tests pass
mix test test/foglet_bbs/tui/layout_smoke_test.exs

# Precommit
mix precommit
```

All commands must exit 0. `grep -c` must return `5`.
</verification>
