---
phase: 04-mainmenu
verified: 2026-04-21T21:05:05Z
status: human_needed
score: 10/10 must-haves verified
overrides_applied: 0
human_verification:
  - test: "Render MainMenu in a real SSH TUI session and confirm content density"
    expected: "Exactly one welcome line, one spacer, and three menu rows; no extra banner/divider/panel/date line"
    why_human: "Visual row-density and reserved-whitespace checks are presentation-level behavior"
  - test: "Manual keyflow check from MainMenu using B/b, C/c, Q/q"
    expected: "B/b opens boards, C/c opens composer, Q/q logs out, and unknown keys are ignored"
    why_human: "End-to-end user flow in live TUI cannot be fully verified by static inspection alone"
---

# Phase 4: MainMenu Verification Report

**Phase Goal:** A user on MainMenu sees the same sparse 4-line content and key behavior as before, with explicit statelessness documentation and audit-compliant structure.
**Verified:** 2026-04-21T21:05:05Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
| --- | --- | --- | --- |
| 1 | MainMenu remains intentionally stateless (no `init_screen_state/1`, no `screen_state[:main_menu]` state writes) | ✓ VERIFIED | Moduledoc states intentional statelessness and no `screen_state[:main_menu]` in [`lib/foglet_bbs/tui/screens/main_menu.ex:4`](/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/main_menu.ex:4), [`lib/foglet_bbs/tui/screens/main_menu.ex:5`](/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/main_menu.ex:5); no `def init_screen_state` in file; test asserts no public export in [`test/foglet_bbs/tui/screens/main_menu_test.exs:50`](/Users/brendan.turner/Dev/personal/foglet_bbs/test/foglet_bbs/tui/screens/main_menu_test.exs:50). |
| 2 | `render/1` shows welcome line + spacer + exactly three plain-text menu rows | ✓ VERIFIED | `content` is built from welcome `text/2`, spacer `text("")`, and `Enum.map(@menu_items)` with `text/2` rows at [`lib/foglet_bbs/tui/screens/main_menu.ex:38`](/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/main_menu.ex:38), [`lib/foglet_bbs/tui/screens/main_menu.ex:39`](/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/main_menu.ex:39), [`lib/foglet_bbs/tui/screens/main_menu.ex:40`](/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/main_menu.ex:40); render-text assertions in tests at [`test/foglet_bbs/tui/screens/main_menu_test.exs:54`](/Users/brendan.turner/Dev/personal/foglet_bbs/test/foglet_bbs/tui/screens/main_menu_test.exs:54). |
| 3 | `@menu_items` and `@menu_keys` both exist and remain separate, with documented rationale | ✓ VERIFIED | Attributes exist at [`lib/foglet_bbs/tui/screens/main_menu.ex:19`](/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/main_menu.ex:19) and [`lib/foglet_bbs/tui/screens/main_menu.ex:25`](/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/main_menu.ex:25); duplication rationale documented at [`lib/foglet_bbs/tui/screens/main_menu.ex:6`](/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/main_menu.ex:6). |
| 4 | Moduledoc documents statelessness, duplication, and reserved whitespace | ✓ VERIFIED | Required statements present in [`lib/foglet_bbs/tui/screens/main_menu.ex:4`](/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/main_menu.ex:4) through [`lib/foglet_bbs/tui/screens/main_menu.ex:9`](/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/main_menu.ex:9). |
| 5 | Inline `{80, 24}` fallback is replaced with `@default_terminal_size` | ✓ VERIFIED | Single `{80, 24}` occurrence is module attribute at [`lib/foglet_bbs/tui/screens/main_menu.ex:17`](/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/main_menu.ex:17); compose handler uses `@default_terminal_size` at [`lib/foglet_bbs/tui/screens/main_menu.ex:53`](/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/main_menu.ex:53). |
| 6 | `Theme.from_state(state)` remains the only theme extraction in `render/1` | ✓ VERIFIED | Theme extraction in `render/1` at [`lib/foglet_bbs/tui/screens/main_menu.ex:34`](/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/main_menu.ex:34); inlined old pattern absent via grep gate. |
| 7 | No `Screens.Domain.get/2` is added in MainMenu | ✓ VERIFIED | No domain helper call or `get_in(...[:domain...])` pattern in `main_menu.ex` (grep gate clear). |
| 8 | `B/b`, `C/c`, `Q/q`, and unknown-key behavior remain unchanged | ✓ VERIFIED | `handle_key/2` clauses preserved at [`lib/foglet_bbs/tui/screens/main_menu.ex:48`](/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/main_menu.ex:48), [`lib/foglet_bbs/tui/screens/main_menu.ex:52`](/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/main_menu.ex:52), [`lib/foglet_bbs/tui/screens/main_menu.ex:65`](/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/main_menu.ex:65), [`lib/foglet_bbs/tui/screens/main_menu.ex:69`](/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/main_menu.ex:69); route tests in [`test/foglet_bbs/tui/screens/main_menu_test.exs:63`](/Users/brendan.turner/Dev/personal/foglet_bbs/test/foglet_bbs/tui/screens/main_menu_test.exs:63), [`test/foglet_bbs/tui/screens/main_menu_test.exs:73`](/Users/brendan.turner/Dev/personal/foglet_bbs/test/foglet_bbs/tui/screens/main_menu_test.exs:73), [`test/foglet_bbs/tui/screens/main_menu_test.exs:87`](/Users/brendan.turner/Dev/personal/foglet_bbs/test/foglet_bbs/tui/screens/main_menu_test.exs:87), [`test/foglet_bbs/tui/screens/main_menu_test.exs:95`](/Users/brendan.turner/Dev/personal/foglet_bbs/test/foglet_bbs/tui/screens/main_menu_test.exs:95). |
| 9 | Focused MainMenu test suite is green | ✓ VERIFIED | `mix test test/foglet_bbs/tui/screens/main_menu_test.exs` passed: 7 tests, 0 failures. |
| 10 | `mix precommit` and screen grep gates are green for this phase | ✓ VERIFIED | `mix precommit` passed (compile, format, credo, sobelow, dialyzer); AUDIT grep gates for `main_menu.ex` showed only the allowed `{80, 24}` module attribute. |

**Score:** 10/10 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
| --- | --- | --- | --- |
| `lib/foglet_bbs/tui/screens/main_menu.ex` | Stateless MainMenu with explicit sparseness/docs and audit-compliant literals | ✓ VERIFIED | Exists, substantive (70 LOC), wired via app screen dispatch at [`lib/foglet_bbs/tui/app.ex:741`](/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/app.ex:741). |
| `test/foglet_bbs/tui/screens/main_menu_test.exs` | Route/render tests for MainMenu-owned behavior | ✓ VERIFIED | Exists, substantive (98 LOC), executed and passing in focused test run. |

### Key Link Verification

| From | To | Via | Status | Details |
| --- | --- | --- | --- | --- |
| `main_menu.ex` | `Foglet.TUI.Theme.from_state/1` | `render/1` | ✓ WIRED | Direct call in render at [`lib/foglet_bbs/tui/screens/main_menu.ex:34`](/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/main_menu.ex:34). |
| `main_menu.ex` | `Foglet.TUI.Screens.NewThread.init_screen_state/1` | C/c compose shortcut | ✓ WIRED | Compose handler seeds new-thread screen state at [`lib/foglet_bbs/tui/screens/main_menu.ex:56`](/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/main_menu.ex:56). |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
| --- | --- | --- | --- | --- |
| `main_menu.ex` | `handle` for welcome text | `state.current_user.handle` from app session state | Yes | ✓ FLOWING |
| `main_menu.ex` | `theme` | `Theme.from_state(state)` helper | Yes | ✓ FLOWING |
| `main_menu.ex` | compose screen seed (`ss`) | `NewThread.init_screen_state(width: w)` | Yes | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| --- | --- | --- | --- |
| MainMenu test contract passes | `mix test test/foglet_bbs/tui/screens/main_menu_test.exs` | `7 tests, 0 failures` | ✓ PASS |
| Full CI gate for phase passes | `mix precommit` | Completed successfully (compile/format/credo/sobelow/dialyzer) | ✓ PASS |
| Terminal-size default gate | `rg -n '\{80, 24\}' lib/foglet_bbs/tui/screens/main_menu.ex` | One match at module attribute only | ✓ PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| --- | --- | --- | --- | --- |
| MENU-01 | 04-01-PLAN.md | Theme extraction uses Phase 0 helper; no domain helper added in MainMenu | ✓ SATISFIED | `Theme.from_state(state)` at [`main_menu.ex:34`](/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/main_menu.ex:34); no `Screens.Domain.get/2`/domain pattern in file. |
| MENU-02 | 04-01-PLAN.md | Keep `@menu_keys` + `@menu_items` duplication and document why | ✓ SATISFIED | Attributes present at [`main_menu.ex:19`](/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/main_menu.ex:19), [`main_menu.ex:25`](/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/main_menu.ex:25); rationale in moduledoc [`main_menu.ex:6`](/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/main_menu.ex:6). |
| MENU-03 | 04-01-PLAN.md | Keep plain `text/2` menu rows (no SelectionList/Button) | ✓ SATISFIED | Menu rows rendered with `text/2` at [`main_menu.ex:40`](/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/main_menu.ex:40); no `SelectionList`/`Button` tokens in file. |
| MENU-04 | 04-01-PLAN.md | AUDIT rubric gates, focused tests, and precommit pass; maintain sparseness | ✓ SATISFIED | Focused test pass (`7/7`) and `mix precommit` pass; grep gates clean; `main_menu.ex` capped at 70 lines. |
| MENU-05 | 04-01-PLAN.md | Moduledoc documents intentional statelessness and no `screen_state[:main_menu]`/`init_screen_state/1` | ✓ SATISFIED | Explicit text in moduledoc at [`main_menu.ex:4`](/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/main_menu.ex:4), [`main_menu.ex:5`](/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/main_menu.ex:5). |

Orphaned requirements for Phase 4 in workstream REQUIREMENTS mapping: none (`MENU-01..MENU-05` are all declared in plan frontmatter).

### Anti-Patterns Found

No blocker/warning anti-patterns found in phase-modified files (`main_menu.ex`, `main_menu_test.exs`): no TODO/FIXME placeholders, no stub returns, no hardcoded empty render props, no console-log placeholder handlers.

### Human Verification Required

### 1. MainMenu Visual Sparseness In SSH

**Test:** Open a real SSH TUI session and navigate to MainMenu.
**Expected:** Exactly the same sparse content contract (welcome + spacer + 3 menu rows) with no extra decorative or informational rows.
**Why human:** Row density and reserved whitespace are visual UX constraints.

### 2. Live Keyflow Transition Check

**Test:** Trigger `B/b`, `C/c`, `Q/q`, and one unknown key from MainMenu in live session.
**Expected:** Transitions/commands match current contract with no perceived regression.
**Why human:** End-to-end behavior across dispatcher/render loop is best validated interactively.

---

_Verified: 2026-04-21T21:05:05Z_  
_Verifier: Claude (gsd-verifier)_
