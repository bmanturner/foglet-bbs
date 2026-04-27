---
phase: 28-modal-form-substrate
plan: 01
subsystem: ui
tags: [tui, raxol, modal, form, focus, keyboard]

# Dependency graph
requires:
  - phase: 25-tui-modal-form
    provides: Foglet.TUI.Widgets.Modal.Form substrate (init/handle_event/render contract, field types, focus_index)
  - phase: 27-foglet-tui-render-task
    provides: mix foglet.tui.render task used to verify Account tabs no longer emit duplicate footers
provides:
  - Modal.Form Up/Down focus on text/integer/textarea fields with wrap (FORM-01)
  - Modal.Form :backtab clause equivalent to :shift_tab and %{key: :tab, shift: true} (FORM-02)
  - Modal.Form :show_footer init option (default false) — footer is opt-in (FORM-03)
  - Forward-locking grep test for single-source-of-truth focus on leaf widgets (FORM-04)
  - Documenting comment in Foglet.TUI.App.render_modal_overlay/2 for future :form-typed overlay callers
affects:
  - 28-02-submit-state-machine
  - 28-03-honest-esc
  - 28-04-siteform-migration
  - 29-sysop-tab-lifecycle (downstream consumer of Modal.Form contract)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Modal.Form keystroke contract: forward (Tab/Down) wraps last → 0; backward (Shift+Tab/:backtab/Up) wraps 0 → last"
    - "Footer opt-in convention: tab-body consumers leave default-off; overlay-style forms pass show_footer: true at init"
    - "Forward-locking grep tests for architectural invariants (e.g. no leaf-widget focus state)"

key-files:
  created:
    - test/foglet_bbs/tui/widgets/input_focus_state_test.exs
  modified:
    - lib/foglet_bbs/tui/widgets/modal/form.ex
    - lib/foglet_bbs/tui/app.ex
    - test/foglet_bbs/tui/widgets/modal/form_test.exs
    - test/foglet_bbs/tui/screens/account_test.exs
    - test/support/foglet/tui/layout_smoke/account_helper.ex

key-decisions:
  - "Updated 4 Account consumer assertions (account_test.exs ×2, account_helper.ex ×2) from `assert footer present` to `refute footer present` per Phase 28 D-06 (the global command bar is the single advertiser of Enter/Esc for tab-body consumers)."
  - "Updated existing 'D-19 refreshed body renders ... action footer' test in form_test.exs to opt in via show_footer: true; otherwise the footer assertions would fail with the new default-off behavior."
  - "Extracted `dispatch_event_to_field/2` private helper so Up/Down clauses can reuse the catch-all dispatch body without duplication."
  - "FORM-04 grep test passes on first run (no leaf widget changes required) per CONTEXT D-16 — committed as a single test rather than RED→GREEN cycle."

patterns-established:
  - "Up/Down focus pattern: type-branch on `Enum.at(state.fields, state.focus_index).type`; text-like types mutate focus_index, others fall through to dispatch_to_field/3 to preserve per-field semantics (e.g. enum cycling)."
  - "Footer opt-in: callers that own their own Enter/Esc advertising surface (global command bar, screen-emitted footer) leave `show_footer: false`; centered overlay forms opt in."

requirements-completed: [FORM-01, FORM-02, FORM-03, FORM-04]

# Metrics
duration: ~25min
completed: 2026-04-27
---

# Phase 28 Plan 01: Modal.Form Substrate Summary

**Modal.Form gains Up/Down focus on text-like fields, `:backtab` ≡ `:shift_tab` ≡ shift+tab key equivalence, and an opt-in `:show_footer` init option (default off), with a forward-locking grep test pinning single-source-of-truth focus on leaf input widgets.**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-04-27T17:22:00Z
- **Completed:** 2026-04-27T17:47:00Z
- **Tasks:** 3
- **Files created:** 1
- **Files modified:** 5
- **New test cases added:** 14 (9 in Task 1, 4 in Task 2, 1 in Task 3)
- **Existing tests updated:** 5 (1 in form_test.exs, 2 in account_test.exs, 2 in account_helper.ex)

## Accomplishments

- **FORM-01 (Up/Down focus):** Modal.Form now accepts `%{key: :up}` / `%{key: :down}` and branches on the focused field's type. On `:text`/`:integer`/`:textarea`, focus moves with wrap (last → 0 forward, 0 → last backward). On `:enum`, the existing field dispatcher handles value cycling with no change to `focus_index`.
- **FORM-02 (`:backtab` acceptance):** New `handle_event(%{key: :backtab}, ...)` clause sits adjacent to the existing `:shift_tab` clause with byte-identical body. `@moduledoc` documents key equivalence and wrap direction.
- **FORM-03 (footer opt-in):** Modal.Form gains a `:show_footer` boolean field (default `false`). `init/1` reads the option from opts. `render/2` appends the `[Enter] Submit   [Esc] Cancel` row only when `show_footer == true`. A documenting comment above `Foglet.TUI.App.render_modal_overlay/2` instructs future `:form`-typed overlay callers to pass `show_footer: true` at init.
- **FORM-04 (single-source-of-truth focus):** New test file `input_focus_state_test.exs` reads each leaf widget source and refutes any defstruct entry for `:focused` / `focused?` and any reference to `:focus_index`. Passes on first run; serves as a forward-locking guard.

## Task Commits

Each task was committed via TDD RED→GREEN cycles:

1. **Task 1 RED — failing tests for Up/Down focus and `:backtab`** — `0da9fc0` (test)
2. **Task 1 GREEN — Up/Down + `:backtab` clauses on Modal.Form** — `d2e97d9` (feat)
3. **Task 2 RED — failing tests for `:show_footer` opt-in** — `ade589d` (test)
4. **Task 2 GREEN — `:show_footer` init option + render/2 conditional + Account consumer-test fixes** — `833c69a` (feat)
5. **Task 3 — single-source-of-truth grep test (passes on first run per D-16)** — `691ac0c` (test)

## Files Created/Modified

### Created
- `test/foglet_bbs/tui/widgets/input_focus_state_test.exs` — Forward-locking grep test ensuring leaf input widgets carry no defstruct focus field.

### Modified
- `lib/foglet_bbs/tui/widgets/modal/form.ex` — Added `:backtab`, `:up`, `:down` clauses; extracted `dispatch_event_to_field/2` helper; added `show_footer: false` to defstruct + typespec; conditional footer in `render/2`; expanded `@moduledoc` with focus-navigation documentation.
- `lib/foglet_bbs/tui/app.ex` — Documenting comment above `render_modal_overlay/2` describing the `show_footer: true` requirement for future `:form`-typed overlay callers.
- `test/foglet_bbs/tui/widgets/modal/form_test.exs` — Added 13 new tests across three describe blocks (FORM-01 / FORM-02 / FORM-03 / FORM-04 routing); updated 1 existing test (`D-19 refreshed body…`) to opt in via `show_footer: true`.
- `test/foglet_bbs/tui/screens/account_test.exs` — Updated 2 PROFILE/PREFS primitive-presence tests to refute the footer (Phase 28 D-06).
- `test/support/foglet/tui/layout_smoke/account_helper.ex` — Updated 2 layout-smoke contracts (PROFILE/PREFS at 64×22 and 80×24) to refute the footer.

## Decisions Made

- **Account consumer-test rewrite:** The plan explicitly anticipated this in Task 2's verification block ("if any test asserts on the footer text on those screens, it must be updated in this plan"). Per Phase 28 D-06, Account tab-body forms (Profile/Prefs) MUST NOT show the Modal.Form footer because the global command bar already advertises `Enter Save` / `Esc Cancel` (visible in the failing-test output: `["└ ", "Esc", " Cancel", "  ", "Ctrl+Q", " Back", "   ", "Save", ...]`). Six failing assertions across two account test files were inverted from `assert footer present` to `refute footer present` with explanatory comments referencing Phase 28 D-06.
- **Existing `D-19 refreshed body…` test in form_test.exs:** The single in-form-test footer-presence assertion was updated to opt in via `show_footer: true`, preserving its original intent (verifying overlay-style footer rendering) under the new default.
- **Sysop screens unaffected:** `lib/foglet_bbs/tui/screens/sysop/site_form.ex` and `lib/foglet_bbs/tui/screens/sysop/limits_form.ex` emit their own `[Enter] Submit   [Esc] Cancel` row at the screen level (independent of Modal.Form's footer), so all sysop tests continued to pass without modification.
- **`dispatch_event_to_field/2` helper extraction:** Required because the new `:up` and `:down` clauses fall through to the catch-all dispatch body for `:enum` (and other non-text-like) types. Extracting the helper avoids triplicating the spec/field_state/replace pattern.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Updated Account consumer tests asserting on the now-absent footer**
- **Found during:** Task 2 (footer opt-in via `:show_footer`)
- **Issue:** After making the footer opt-in (default off), six existing assertions in `test/foglet_bbs/tui/screens/account_test.exs` (×2) and `test/support/foglet/tui/layout_smoke/account_helper.ex` (×4) failed because they expected the Modal.Form footer in Account tab-body renders. Per Phase 28 D-06, Account tab-body consumers MUST NOT show the footer (the global command bar advertises Enter/Esc).
- **Fix:** Inverted the six assertions from `assert "[Enter] Submit"` to `refute "[Enter] Submit"`, kept (or added) heading/field-label assertions to ensure the form is still rendered, and added comments referencing Phase 28 D-06.
- **Files modified:** `test/foglet_bbs/tui/screens/account_test.exs`, `test/support/foglet/tui/layout_smoke/account_helper.ex`
- **Verification:** `rtk mix test` green (1845 tests, 0 failures). `rtk mix foglet.tui.render account | grep -c "[Enter] Submit"` returns `0`.
- **Committed in:** `833c69a` (Task 2 GREEN commit, alongside the Modal.Form changes — these test edits are inseparable from the substrate change)

**2. [Rule 1 - Bug] Updated `D-19 refreshed body…` test in form_test.exs to opt-in via `show_footer: true`**
- **Found during:** Task 2 (footer opt-in via `:show_footer`)
- **Issue:** The existing test asserted on the footer text using the convenience `test_form/2` helper, which would now produce a footer-less form by default.
- **Fix:** Replaced the `test_form/2` call in that single test with an explicit `Form.init(...)` call passing `show_footer: true`, preserving the test's original intent (verifying that overlay-style forms still render the footer).
- **Files modified:** `test/foglet_bbs/tui/widgets/modal/form_test.exs`
- **Verification:** Test passes; remaining 43 form tests still pass.
- **Committed in:** `ade589d` (Task 2 RED commit)

---

**Total deviations:** 2 auto-fixed (Rule 1 bugs — pre-existing tests asserting on behavior the plan deliberately changed).

**Impact on plan:** Both deviations were anticipated by the plan ("if any test asserts on the footer text on those screens, it must be updated in this plan, with the diff and rationale called out in the SUMMARY"). No scope creep; both edits are direct consequences of the FORM-03 default-off change.

## TDD Gate Compliance

Task 1 and Task 2 followed strict RED → GREEN cycles, each with separate commits:

- **Task 1:** `0da9fc0` (test, RED — 8 of 9 tests fail) → `d2e97d9` (feat, GREEN — all pass)
- **Task 2:** `ade589d` (test, RED — 3 of 4 new tests fail) → `833c69a` (feat, GREEN — all pass; consumer tests updated)
- **Task 3:** `691ac0c` (test only — passes on first run per D-16, so no GREEN commit is required; this is a forward-locking guard, not RED→GREEN.)

## Issues Encountered

- **Worktree base mismatch on startup:** The worktree was initially based on `3226ef9e` (older `main`) instead of the expected `5f6cfb3` (Phase 28 plans). Hard-reset to the correct base per the `<worktree_branch_check>` protocol; no work was lost (worktree was empty).
- **Mix deps missing in worktree:** Required `rtk mix deps.get` before tests could run. No further issues.

## Verification

- `rtk mix test test/foglet_bbs/tui/widgets/modal/form_test.exs` → 44 tests, 0 failures (covers FORM-01, FORM-02, FORM-03, and FORM-04 routing).
- `rtk mix test test/foglet_bbs/tui/widgets/input_focus_state_test.exs` → 1 test, 0 failures (covers FORM-04 single-source-of-truth).
- `rtk mix test` (full suite) → 1 property, 1845 tests, 0 failures.
- `rtk mix precommit` → passed (compile, formatter, Credo, Sobelow, Dialyzer all clean).
- `rtk mix foglet.tui.render account | grep -c "[Enter] Submit"` → `0` (Modal.Form footer correctly suppressed in Account tab body).

## Next Phase Readiness

- **Plan 02 (submit-state machine):** Modal.Form's keystroke contract is now stable — Up/Down focus, `:backtab` acceptance, and `:show_footer` are locked. Plan 02 can add the `submit_state` field and the input-lock guard clause without conflict.
- **Plan 03 (honest Esc):** Cancel-path semantics and the existing Esc clause are unchanged; Plan 03 can layer the no-flash behavior on top.
- **Plan 04 (SiteForm migration):** SiteForm's "re-init on change" pattern works cleanly with the new substrate; Plan 04 can construct Modal.Form with `show_footer: false` at every render and rely on its own screen-level footer (existing pattern in `site_form.ex:330`).

## Self-Check: PASSED

**Files exist:**
- `lib/foglet_bbs/tui/widgets/modal/form.ex` — FOUND (modified)
- `lib/foglet_bbs/tui/app.ex` — FOUND (modified)
- `test/foglet_bbs/tui/widgets/modal/form_test.exs` — FOUND (modified)
- `test/foglet_bbs/tui/widgets/input_focus_state_test.exs` — FOUND (created)
- `test/foglet_bbs/tui/screens/account_test.exs` — FOUND (modified)
- `test/support/foglet/tui/layout_smoke/account_helper.ex` — FOUND (modified)

**Commits exist:**
- `0da9fc0` — FOUND (test RED Task 1)
- `d2e97d9` — FOUND (feat GREEN Task 1)
- `ade589d` — FOUND (test RED Task 2)
- `833c69a` — FOUND (feat GREEN Task 2)
- `691ac0c` — FOUND (test Task 3)

---
*Phase: 28-modal-form-substrate*
*Completed: 2026-04-27*
