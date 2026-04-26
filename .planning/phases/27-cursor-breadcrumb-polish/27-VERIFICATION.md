---
phase: 27-cursor-breadcrumb-polish
verified: 2026-04-26T18:25:00Z
status: human_needed
score: 8/9 must-haves verified
overrides_applied: 0
human_verification:
  - test: "SSH into the BBS and navigate to the Login form. Type several characters, then backspace. Confirm the cursor marker moves with the insertion point rather than staying at the field start."
    expected: "The '▌' cursor marker sits immediately after the last typed character, retreats on backspace, and advances on new keystrokes."
    why_human: "Terminal cell rendering over a real SSH session cannot be confirmed by static render-tree inspection alone; focus/input routing requires a live session."
  - test: "Navigate from Login menu to Register, then back with Escape. Check the breadcrumb bar at each step."
    expected: "Register shows 'Foglet ▸ Login ▸ Register'. Escape returns to Login menu showing only 'Foglet ▸ Login'."
    why_human: "Live nav behavior and actual chrome rendering require a real SSH session to confirm."
---

# Phase 27: Cursor & Breadcrumb Polish Verification Report

**Phase Goal:** Implement TextInput insertion-point cursor (CURSOR-01) and BreadcrumbBar auth screen mapping (BREAD-01) as shared widget fixes.
**Verified:** 2026-04-26T18:25:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A focused single-line TextInput renders the cursor at the active insertion point, not before the field. | ✓ VERIFIED | `render_with_cursor_marker/3` in text_input.ex splits at `cursor_pos` and places `"▌"` between left/right spans. Test in `render/2 — insertion cursor (CURSOR-01)` describe block confirms behavior. |
| 2 | Typing five characters then backspacing twice leaves the visible cursor after the third displayed cell. | ✓ VERIFIED | Test "cursor_pos after typing 5 then backspace 2 is 3, width before cursor equals display_width('abc')" asserts `cursor_pos == 3` and `width_before_cursor == TextWidth.display_width("abc")`. |
| 3 | Blurred and disabled TextInput renders contain no cursor marker. | ✓ VERIFIED | Tests "focused: false renders no cursor marker" and "disabled: true renders no cursor marker" both refute `"▌"` in output. Implementation guards with `focused? and not disabled?`. |
| 4 | Masked TextInput rendering never exposes the raw password value while placing the cursor. | ✓ VERIFIED | Test "masked focused input renders masked chars and cursor but does not leak raw value" checks `inspect(result)` does not contain `"secret"` and the cursor marker IS present. |
| 5 | Register shows breadcrumb parts `Foglet`, `Login`, `Register`. | ✓ VERIFIED | `defp parts_for_screen(_state, :register), do: [@root, "Login", "Register"]` in breadcrumb_bar.ex. Layout smoke test line 2226+ verifies rendered output. |
| 6 | Forgot Password shows breadcrumb parts `Foglet`, `Login`, `Forgot Password`. | ✓ VERIFIED | `login_parts/1` maps `:reset_request -> [@root, "Login", "Forgot Password"]`. Layout smoke test line 2267 asserts this at 64x22 and 80x24. |
| 7 | Verify shows breadcrumb parts `Foglet`, `Login`, `Verify`. | ✓ VERIFIED | `defp parts_for_screen(_state, :verify), do: [@root, "Login", "Verify"]` in breadcrumb_bar.ex. Layout smoke test covers this. |
| 8 | `:reset_consume` shows breadcrumb parts `Foglet`, `Login`, `Forgot Password`, `Enter Token`. | ✓ VERIFIED | `login_parts/1` maps `:reset_consume -> [@root, "Login", "Forgot Password", "Enter Token"]`. Layout smoke test line 2325 asserts all four segments. |
| 9 | Returning to Login menu shows only `Foglet`, `Login`. | ✓ VERIFIED | `login_parts/1` default clause (`_ -> [@root, "Login"]`) handles `:menu` and unknown sub-states. Layout smoke test line 2360+ asserts absence of "Forgot Password", "Register", "Verify", "Enter Token". |

**Score:** 9/9 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/foglet_bbs/tui/widgets/input/text_input.ex` | Shared single-line TextInput cursor rendering; contains `render_with_cursor_marker` | ✓ VERIFIED | Function exists at line 119. Splits on `cursor_pos`, renders row with left/cursor/right. Uses `TextWidth` alias (line 35). |
| `test/foglet_bbs/tui/widgets/input/text_input_test.exs` | Cursor position, mask, blur, and disabled tests; contains `TextWidth.display_width` | ✓ VERIFIED | `describe "render/2 — insertion cursor (CURSOR-01)"` block with 5 tests. `width_before_cursor/1` helper uses `TextWidth.display_width`. |
| `lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex` | Central auth/Login breadcrumb mapping; contains `login_parts` | ✓ VERIFIED | `defp login_parts/1` at line 86 dispatches on sub-state. `:register` and `:verify` clauses present at lines 67-68. |
| `test/foglet_bbs/tui/widgets/chrome/breadcrumb_test.exs` | Direct breadcrumb part and formatting coverage; contains `"Enter Token"` | ✗ STUB | File is 90 lines with 7 tests. Does NOT contain "Enter Token", "Register" sub-paths, "Forgot Password", or `:reset_consume` assertions. Auth paths from PLAN 27-02 are absent from this file. |
| `test/foglet_bbs/tui/screens/login_test.exs` | Login sub-state back-to-menu breadcrumb behavior; contains `"reset_consume"` | ✗ STUB | No `BreadcrumbBar`, `parts_for`, or `:reset_consume` breadcrumb assertions in this file. `:reset_request` appears only in existing pre-phase tests for form navigation. |
| `test/foglet_bbs/tui/layout_smoke_test.exs` | 64x22 and 80x24 render-tree verification for cursor and breadcrumb polish; contains `"CURSOR-01"` | ✓ VERIFIED | `describe "Phase 27 cursor surfaces (CURSOR-01)"` (line 2061) and `describe "Phase 27 auth breadcrumbs (BREAD-01)"` (line 2226) both present. `reset_consume` covered at line 2325. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `text_input.ex` | `Foglet.TUI.TextWidth` | cell-width-aware display splitting | ✓ WIRED | `alias Foglet.TUI.TextWidth` at line 35; referenced in test via `width_before_cursor` helper. |
| `text_input.ex` | `Raxol.UI.Components.Input.TextInput` | `raxol_state.cursor_pos` | ✓ WIRED | `cursor_pos = Map.get(rs, :cursor_pos, 0)` used in `render_with_cursor_marker/3`. Unfocused path delegates to `RaxolTextInput.render/2`. |
| `screen_frame.ex` | `breadcrumb_bar.ex` | `BreadcrumbBar.parts_for` | ✓ WIRED | Pre-existing wiring; verified via smoke test rendering ScreenFrame output with correct breadcrumb text. |
| `breadcrumb_bar.ex` | Login screen_state | `screen_state[:login][:sub]` via `:reset_consume` | ✓ WIRED | `login_parts/1` reads `Map.get(:screen_state, %{}) |> Map.get(:login, %{}) |> Map.get(:sub)`. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|--------------|--------|--------------------|--------|
| `text_input.ex` `render_with_cursor_marker/3` | `cursor_pos`, `value` | `raxol_state` mutated by `handle_event/2` | Yes — driven by keystroke events through RaxolTextInput | ✓ FLOWING |
| `breadcrumb_bar.ex` `login_parts/1` | `sub` atom | `state.screen_state[:login][:sub]` | Yes — reads live App state passed at render time | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Phase 27 focused test suite | `mix test text_input_test.exs breadcrumb_test.exs login_test.exs layout_smoke_test.exs` | 137 tests, 0 failures | ✓ PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| CURSOR-01 | 27-01, 27-03 | TextInput cursor follows insertion point on all focused single-line inputs | ✓ SATISFIED | `render_with_cursor_marker/3` implements cursor at `cursor_pos`. Tests cover advance, retreat, blur, disabled, masked. Layout smoke at 64x22 and 80x24. |
| BREAD-01 | 27-02, 27-03 | Shared breadcrumb updates correctly for Register, Forgot Password, Verify, reset-consume sub-states | ✓ SATISFIED | All five state paths implemented in `breadcrumb_bar.ex`. All paths covered by layout smoke tests. Implementation is correct; unit-level artifact location deviated. |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `test/.../breadcrumb_test.exs` | — | PLAN 27-02 specified auth path tests here; file still has only pre-phase 7 tests; no "Enter Token" or sub-state assertions | ⚠️ Warning | Test artifact gap — behavior is covered in layout_smoke_test.exs instead, but the unit-level direct coverage in breadcrumb_test.exs was promised and absent. |
| `test/.../login_test.exs` | — | PLAN 27-02 specified breadcrumb sub-state assertions here; no `BreadcrumbBar`/`parts_for`/`:reset_consume` breadcrumb tests present | ⚠️ Warning | Same as above — coverage migrated to layout smoke rather than unit location. |

### Human Verification Required

#### 1. Live SSH cursor behavior

**Test:** SSH into the BBS and navigate to the Login form. Focus on the username or email field. Type "hello", then press Backspace twice. Observe the cursor position.
**Expected:** The `▌` marker sits after "hel" (three characters), not at the start of the field.
**Why human:** The render-tree smoke test confirms the marker exists, but the actual terminal cell rendering and SSH input routing require a live session to confirm the insertion-point behavior is visually correct.

#### 2. Live breadcrumb navigation

**Test:** SSH into the BBS. Navigate to Forgot Password (press `F` from Login menu). Confirm breadcrumb. Press Escape. Confirm breadcrumb returns to Login-only state.
**Expected:** Forgot Password state shows `Foglet ▸ Login ▸ Forgot Password`. After Escape: `Foglet ▸ Login`.
**Why human:** Escape-key navigation routing and actual breadcrumb update-on-screen-transition require a live session; the smoke tests verify render at static fixture states only.

### Gaps Summary

No behavioral gaps found — all 9 observable truths are VERIFIED and the implementation is substantively correct.

The two ⚠️ Warning artifacts (`breadcrumb_test.exs` missing "Enter Token" tests, `login_test.exs` missing `:reset_consume` breadcrumb assertions) represent a deviation from PLAN 27-02's artifact specification. The SUMMARY 27-02 claimed these tests were added, but they are absent. The equivalent coverage exists in `layout_smoke_test.exs` (Plan 27-03). This does not block the phase goal — BREAD-01 is implemented correctly and tested at the smoke layer — but the unit-level isolation promised by PLAN 27-02 was not delivered.

Status is `human_needed` because live SSH terminal verification is the last gate before these visual behaviors can be declared fully working.

---

_Verified: 2026-04-26T18:25:00Z_
_Verifier: Claude (gsd-verifier)_
