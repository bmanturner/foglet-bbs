---
phase: 01-login
verified: 2026-04-21T18:00:00Z
status: gaps_found
score: 4/5 must-haves verified
overrides_applied: 0
gaps:
  - truth: "Invalid credentials show inline error and clear password field"
    status: partial
    reason: "Password field is cleared but re-initialized without mask_char: \"*\" (line 270: TextInput.init([])), so the next password attempt is typed in plaintext. SC-1 requires password masking; LOGIN-01 requires the field to be configured with mask. The error recovery branch violates this."
    artifacts:
      - path: "lib/foglet_bbs/tui/screens/login.ex"
        issue: "Line 270: new_password_input = TextInput.init([]) — missing mask_char: \"*\". Compare with enter_login_form/1 line 223 which correctly passes mask_char."
    missing:
      - "Change TextInput.init([]) to TextInput.init(mask_char: \"*\") on line 270 of login.ex"
      - "Add/update a test asserting that after a failed login, the password field retains its mask (i.e., subsequent typed characters are masked)"
deferred:
  - truth: "Top-level state.register_wizard field usage in maybe_register/1"
    addressed_in: "Phase 2"
    evidence: "Phase 2 success criteria 3: 'state.register_wizard removed from the top-level App struct; state.screen_state[:register] is the canonical store'. Plan explicitly says keep start_verify_flow/2 and handle_active_user/2 unchanged."
  - truth: "Top-level state.verify_state field usage in start_verify_flow/2"
    addressed_in: "Phase 3"
    evidence: "Phase 3 success criteria 4: 'state.verify_state removed from the top-level App struct; state.screen_state[:verify] is the canonical store'. Login plan explicitly says keep start_verify_flow/2 unchanged."
human_verification:
  - test: "Visual parity — inline label + TextInput layout"
    expected: "Handle and password fields render as 'Handle:   value' and 'Password: ****' inline with focus-aware label highlighting (accent color + bold when focused, primary color otherwise)"
    why_human: "TUI rendering is visual; automated tests verify behavior but not exact column alignment or visual appearance of TextInput cursor in the SSH terminal"
---

# Phase 01: Login — Verification Report

**Phase Goal:** A user logging in sees two themed input fields — handle and password — with working focus toggle, password masking, and authentication that preserves today's happy/error branches bit-for-bit; the screen drops from 347 LoC to ~150.
**Verified:** 2026-04-21T18:00:00Z
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| #  | Truth                                                                        | Status          | Evidence                                                                                     |
|----|------------------------------------------------------------------------------|-----------------|----------------------------------------------------------------------------------------------|
| 1  | User sees two themed input fields (handle + password) with inline label layout | VERIFIED        | login.ex lines 200-215: row/text+TextInput.render with focus-aware fg/style; ScreenFrame wraps |
| 2  | Tab cycles focus between handle and password fields                          | VERIFIED        | login.ex lines 94-99: handle_form_key(:tab) toggles focused_field; test "tab cycles focus" passes |
| 3  | Enter on handle advances to password; Enter on password submits               | VERIFIED        | login.ex lines 102-111: handle_form_key(:enter) dispatches on focused_field; tests pass       |
| 4  | Escape returns to menu and clears form                                       | VERIFIED        | login.ex lines 114-117: puts %{sub: :menu}; test "escape from login form" passes             |
| 5  | Valid credentials emit {:promote_session, user} command                      | VERIFIED        | login.ex lines 299-301: handle_auth_success/3 returns [{:promote_session, user}]; test passes |
| 6  | Invalid credentials show inline error and clear password field               | PARTIAL (FAILED) | login.ex line 270: TextInput.init([]) missing mask_char: "*" — password unmasked after error  |
| 7  | Pending/suspended users see appropriate modals with screen_state cleared     | VERIFIED        | login.ex lines 280-292: :pending and :suspended branches set modal + screen_state: %{}; tests pass |

**Score:** 4/5 truths verified (truth 6 partially fails on masking)

### Deferred Items

Items not yet met but explicitly addressed in later milestone phases.

| # | Item | Addressed In | Evidence |
|---|------|-------------|----------|
| 1 | maybe_register/1 writes to state.register_wizard (top-level field) | Phase 2 | Phase 2 SC-3: "state.register_wizard removed from top-level App struct". Login plan explicitly says keep unchanged. |
| 2 | start_verify_flow/2 writes to state.verify_state (top-level field) | Phase 3 | Phase 3 SC-4: "state.verify_state removed from top-level App struct; state.screen_state[:verify] is canonical store". Login plan task 2 says "keep start_verify_flow/2 unchanged". |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/foglet_bbs/tui/screens/login.ex` | TextInput adoption, flat state, init_screen_state/1, with-chain auth | VERIFIED (with gap) | 340 lines (down from 347); all 6 deleted functions confirmed absent; init_screen_state/1 present; with chain at line 264; mask gap at line 270 |
| `test/foglet_bbs/tui/screens/login_test.exs` | Test coverage for TextInput state shape and with-chain branches | VERIFIED | 30 tests, all passing; TextInput.init/handle_event used; init_screen_state/1 describe block present; WR-01 mask gap not covered |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| login.ex | Foglet.TUI.Widgets.Input.TextInput | alias + TextInput.init/handle_event/render | WIRED | Lines 37, 121, 205, 211, 222-223, 270; all three API calls present |
| login.ex | Foglet.Accounts.authenticate_by_password/2 | with chain line 264 | WIRED | `with {:ok, user} <- Accounts.authenticate_by_password(handle_value, password_value)` |
| login.ex | Foglet.TUI.Theme.from_state/1 | Theme.from_state(state) line 53 | WIRED | Phase 0 helper correctly used; gate #8 returns zero |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|--------------|--------|--------------------|--------|
| login.ex render_login_form/2 | login_ss.handle_input / password_input | get_login_ss/1 → screen_state[:login] | Yes — TextInput structs set in enter_login_form/1, updated on each event | FLOWING |
| login.ex submit_login/1 | handle_value, password_value | login_ss.handle_input.raxol_state.value, login_ss.password_input.raxol_state.value | Yes — extracted from live TextInput struct state | FLOWING |

### Behavioral Spot-Checks

Behavioral spot-checks not applicable — this is a TUI screen, no runnable API endpoints or CLI entry points.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| LOGIN-01 | 01-01-PLAN.md | Hand-rolled inputs replaced with TextInput (mask: "*") | PARTIAL | TextInput adopted; mask_char: "*" absent in error branch (line 270) |
| LOGIN-02 | 01-01-PLAN.md | 6 hand-rolled functions deleted | SATISFIED | grep returns zero for all 6 function names |
| LOGIN-03 | 01-01-PLAN.md | Focused-field state in screen_state[:login]; init_screen_state/1 present | SATISFIED | init_screen_state/1 at line 47; screen_state[:login] used throughout |
| LOGIN-04 | 01-01-PLAN.md | nested case rewritten as with chain | SATISFIED | with chain at line 264; no case.*authenticate_by_password |
| LOGIN-05 | 01-01-PLAN.md | Config.get safety confirmed and documented | SATISFIED | Moduledoc lines 22-26 document ETS read-through caching |
| LOGIN-06 | 01-01-PLAN.md | AUDIT-05..22 pass; mix precommit green | PARTIAL | AUDIT-05 grep gates: all zero; AUDIT-15 (precommit): claimed green, 30 tests pass; AUDIT-18: section order deviation undocumented (see Anti-Patterns); AUDIT-16: 347→340 lines, strictly lower |
| AUDIT-05 | Inherited rubric | All 9 grep gates return zero | SATISFIED | All 9 patterns return zero on login.ex |
| AUDIT-06 | Inherited rubric | Behavioral invariants: handle_key clause order, render purity, no state.modal inspection in handle_key | SATISFIED | Single handle_key/2 clause routes to sub-state; no modal inspection; modal writes paired with screen_state: %{} reset |
| AUDIT-07 | Inherited rubric | Widget invocations pass theme: theme explicitly | SATISFIED | Both TextInput.render calls: (bordered: false, theme: theme) |
| AUDIT-08 | Inherited rubric | ScreenFrame wraps content; modal shape correct | SATISFIED | ScreenFrame.render/4 at line 65; modal shape %{type:, message:} at lines 281, 290 |
| AUDIT-09 | Inherited rubric | with chain replaces nested case | SATISFIED | Done in submit_login/1 |
| AUDIT-13 | Inherited rubric | Scope fence — only login.ex + login_test.exs touched | SATISFIED | Commits 105f724 (login.ex only) and fe6e733 (login_test.exs only) confirmed |
| AUDIT-14 | Inherited rubric | No new shared modules | SATISFIED | No new modules beyond login.ex private helpers |
| AUDIT-15 | Inherited rubric | mix precommit green | SATISFIED (claimed) | SUMMARY: "PASSED (0 issues, dialyzer 74 skips all pre-existing)"; 30 tests pass |
| AUDIT-16 | Inherited rubric | Line count and visible row count strictly lower | SATISFIED | 347→340 lines; plan's 120-180 aspirational target not met but REQUIREMENTS.md criterion ("strictly lower than pre-Phase-1") is met |
| AUDIT-17 | Inherited rubric | No protected region fills (below error line for login) | SATISFIED | Only handle/password fields + error line rendered; no additions below error |
| AUDIT-18 | Inherited rubric | Canonical 10-section order; deviations documented in moduledoc | PARTIAL (WARNING) | Sections 1-5 correct (aliases, attrs, init_screen_state, render, handle_key). §9 state helpers (focused_input, update_focused_input, input_key, lines 125-140) appear before §8 render helpers (render_menu, render_login_form, lines 172-215). Deviation undocumented in moduledoc. |
| AUDIT-19 | Inherited rubric | init_screen_state/1 present | SATISFIED | Line 46-47: @spec + def init_screen_state(_opts), do: %{sub: :menu} |
| AUDIT-21 | Inherited rubric | No prohibited widget usage | SATISFIED | No Display.Table, Input.Tabs, Input.Button, etc. |
| AUDIT-22 | Inherited rubric | No ASCII banners or decorative elements | SATISFIED | No banners/dividers/sidebars present |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| login.ex | 270 | `TextInput.init([])` missing `mask_char: "*"` on invalid_credentials error branch | Blocker | Password unmasked on the retry attempt after a failed login — user's next typed password appears in plaintext. Contradicts SC-1 and LOGIN-01 which require password masking. |
| login.ex | 125-170 | §9 state helpers precede §8 render helpers — AUDIT-18 section order deviation | Warning | Undocumented deviation from canonical layout. Requires a note in @moduledoc per AUDIT-18. Not a behavioral issue. |

### Human Verification Required

### 1. Inline label + TextInput visual layout

**Test:** SSH into the BBS, navigate to login screen, press L to enter login form. Observe the handle and password fields.
**Expected:** Each field renders as a single row: `"Handle:   value█"` and `"Password: ****█"`. The focused field label should appear in accent color (bold); the unfocused label in primary color. Pressing Tab should visually toggle which label is highlighted. After a failed login, the password field should show `*` characters for any subsequently typed password (not plaintext).
**Why human:** TUI rendering is visual; automated tests verify behavioral state but not column alignment, cursor rendering, or color display in the SSH terminal.

### Gaps Summary

**One behavioral gap blocks goal achievement:** The password mask is lost after a failed login attempt. `submit_login/1` re-initializes the password field with `TextInput.init([])` (line 270) instead of `TextInput.init(mask_char: "*")`. This means the user's next typed password appears in plaintext until they escape and re-enter the form. The ROADMAP success criteria SC-1 explicitly requires "mask the password with `*`" and LOGIN-01 requires the password field to be "configured with `mask: "*"`". The error recovery branch bypasses this configuration.

**One undocumented AUDIT-18 deviation:** The §9 state-plumbing helpers `focused_input/1`, `update_focused_input/2`, and `input_key/1` (lines 125-140) are placed immediately after the `handle_form_key/2` handlers they support, before the §8 render helpers (`render_menu/2`, `render_login_form/2`, lines 172-215). AUDIT-18 requires deviations to be documented in `@moduledoc` with rationale. The discussion log notes "AUDIT-18 section re-ordering details" is at Claude's discretion, but the final result has an unacknowledged deviation.

**Fix required:**
1. `lib/foglet_bbs/tui/screens/login.ex` line 270: Change `TextInput.init([])` to `TextInput.init(mask_char: "*")`
2. Add a test asserting the password field retains masking after a failed login
3. (Optional — warning only) Add a moduledoc note documenting the §9-before-§8 section ordering rationale

---

_Verified: 2026-04-21T18:00:00Z_
_Verifier: Claude (gsd-verifier)_
