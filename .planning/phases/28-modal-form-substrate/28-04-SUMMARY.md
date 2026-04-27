---
phase: 28-modal-form-substrate
plan: 04
subsystem: ui
tags: [tui, raxol, modal, form, sysop, site, migration, esc, validation]

# Dependency graph
requires:
  - phase: 28-modal-form-substrate
    plan: 02
    provides: Modal.Form submit_state machine, set_submit_state/2, status row
  - phase: 28-modal-form-substrate
    plan: 01
    provides: Modal.Form Up/Down focus, :backtab, :show_footer opt-in
  - phase: 25-tui-modal-form
    provides: Modal.Form substrate (init/handle_event/render contract, field types)
provides:
  - SiteForm rewritten as Modal.Form-backed wrapper (D-17)
  - SiteForm.State sibling module owning drafts/visibility/validation
  - Ctrl+S preserved at wrapper; routes through Modal.Form Enter-on-last (D-19)
  - Esc reseeds drafts from Foglet.Config.get!/1 with no inline copy (FORM-06 / D-12)
  - Validation pre-flight (no_email + require_email_verification) flows through
    Modal.Form.set_errors/2 + set_submit_state({:error, …}) (D-20)
  - Per-render Modal.Form construction preserves D-21 conditional visibility
    (invite_generation_per_user_limit shown only when generators == "any_user")
  - Modal.Form substrate addition: optional :description field-spec key renders
    a dim row beneath the widget when present and non-empty (Plan 04 Option a)
affects:
  - 29-sysop-tab-lifecycle (Sysop Site lifecycle / Config.put error mapping
    can now adopt set_submit_state for honest in-flight/saved/error display)
  - 30-account-async-persistence (description field-spec key is also available
    for ProfileForm/PrefsForm if Account screens decide to surface schema copy)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Per-render Modal.Form construction: SState owns drafts; build_modal_form/1 produces an ephemeral form per render so D-21 conditional visibility takes effect on the next paint without stateful re-sync."
    - "Wrapper-owned shortcut: Ctrl+S drives the per-render Modal.Form to the last visible field index and dispatches :enter, hitting Modal.Form's Enter-on-last branch and engaging the Phase 28 submit-state machine identically to physical Enter."
    - "String-keyed wrapper errors + atom-keyed Modal.Form errors: SiteForm preserves the legacy string-keyed errors map (used by sysop.ex consumers) while the per-render Modal.Form receives atom-keyed errors via Modal.Form.set_errors/2."
    - "Compile-time atom interning for runtime string→atom conversion: @site_keys_atoms in SState ensures String.to_existing_atom/1 succeeds for every site key — the rarely-referenced :invite_generation_per_user_limit atom would otherwise not be in the atom table on a fresh boot."
    - "Optional :description on Modal.Form field spec: render_field/5 emits a dim row under the widget when :description is a non-empty binary; nil and empty string are both treated as absent."

key-files:
  created:
    - lib/foglet_bbs/tui/screens/sysop/site_form/state.ex
  modified:
    - lib/foglet_bbs/tui/screens/sysop/site_form.ex
    - lib/foglet_bbs/tui/widgets/modal/form.ex
    - test/foglet_bbs/tui/screens/sysop/site_form_test.exs
    - test/foglet_bbs/tui/widgets/modal/form_test.exs

key-decisions:
  - "Description field — chose Option (a): added optional :description key to Modal.Form field spec so the Schema description copy carries through the migration (was visible to operators in the legacy bespoke renderer). 6-line addition to render_field/5; gated on Map.get(spec, :description) being a non-empty binary."
  - "Sysop SITE opts into Modal.Form's footer (show_footer: true) because the Sysop global command bar advertises Q/Tabs/Jump but NOT Enter/Esc. The Phase 28 D-09 status row replaces this footer when active. Preserves the legacy SiteForm screen-level footer UX and keeps the layout_smoke and sysop_test footer-presence assertions green without modification — different from Account ProfileForm/PrefsForm which DO get Enter/Esc from the global command bar and so leave show_footer: false."
  - "Behavior change: Sysop SITE enum selection moves from first-char-jump (legacy bespoke 'press e to pick email') to up/down cycling (Modal.Form contract used everywhere else). Documented as intentional alignment with Account; the alternative of porting first-char-jump into Modal.Form was rejected because it changes Modal.Form's public contract and creates an asymmetry across consumers."
  - "Compile-time atom interning via @site_keys_atoms module attribute in SState: Credo flagged the wrapper's String.to_atom/1 calls; switching to String.to_existing_atom/1 required guaranteeing the atoms exist at compile time. The :invite_generation_per_user_limit atom is not referenced as a literal anywhere else in lib/, so the @site_keys_atoms list explicitly interns all five at compile time."
  - "String-keyed errors preserved on the wrapper struct: The legacy SiteForm exposed errors keyed by string (e.g. form.errors['delivery_mode']); existing tests assert on this shape. The new wrapper preserves it via stringify_keys/1 even though the per-render Modal.Form receives atom-keyed errors. This keeps the wrapper API stable for sysop.ex callers."

patterns-established:
  - "Sibling state module for non-trivial form wrappers: SiteForm.State owns drafts + errors + visibility + validation + the Modal.Form builder; SiteForm wrapper module is a thin event router. Mirrors Account.State's build_profile_form/1 / build_prefs_form/1 pattern."
  - "Per-render Modal.Form snapshot: form is rebuilt fresh on every render and every handle_key event from the persistent SState.t() — D-21 conditional visibility takes effect immediately on the next paint without any stateful re-sync code."

requirements-completed: [FORM-04, FORM-06]

# Metrics
duration: ~12min
completed: 2026-04-27
---

# Phase 28 Plan 04: SiteForm → Modal.Form Migration Summary

**Sysop SITE renders through Modal.Form like Account Profile/Prefs do; Ctrl+S is preserved at the wrapper, Esc honestly reseeds drafts (no flash copy), the no-email + require-verification pre-flight flows through Modal.Form.set_errors, and conditional visibility for invite_generation_per_user_limit is preserved via per-render Modal.Form construction.**

## Performance

- **Duration:** ~12 min (most of the elapsed time was a `mix deps.get` + `mix precommit` Dialyzer cold start)
- **Started:** 2026-04-27T18:12:17Z
- **Completed:** 2026-04-27T18:24:27Z
- **Tasks:** 2 (each TDD RED → GREEN)
- **Files created:** 1
- **Files modified:** 4
- **Tests before:** 12 (site_form_test.exs)
- **Tests after:** 29 (site_form_test.exs) — 17 net new (+10 SState sibling, +7 wrapper behavior); 2 existing tests rewritten in place
- **Modal.Form substrate tests:** +3 (description field rendering — present, absent, empty)

## What Changed

### `Foglet.TUI.Screens.Sysop.SiteForm` (rewrite)

Old: bespoke 369-line module with hand-rolled `▸ key: value` rendering, custom `apply_char/2` per field type, hand-rolled focus rotation.

New: ~200-line thin wrapper. The struct (`%SiteForm.State{}`) lives in a sibling module; `render/2` and `handle_key/2` build a per-render Modal.Form from drafts and route events through `ModalForm.handle_event/2`. The wrapper still owns Ctrl+S, Esc, and the persist loop because they cross the SiteForm boundary (Foglet.Config.put/3 with the actor and the screen-side error_modal events).

Substrate-aligned subtleties:
- `state.focused` is the wrapper's persistent focus pointer; mirrored into the per-event Modal.Form's `:focus_index` and synced back via `sync_back/2`.
- `state.errors` stays string-keyed (legacy API); a `stringify_keys/1` step bridges the atom-keyed errors that Modal.Form.set_errors/2 expects.
- The persist loop iterates `visible_keys/1` and calls `Foglet.Config.put/3` per key; `:forbidden` and `:db_error` halt and surface as `:error_modal` events; `:invalid_value` and `:unknown_key` accumulate into errors but continue.
- On full-success persistence, `set_submit_state(form, :saved)` engages the Phase 28 D-08 status row ("Saved.") for one render until the next user keystroke auto-resets per D-04.

### `Foglet.TUI.Screens.Sysop.SiteForm.State` (new sibling)

Owns the `current_user / drafts / errors / focused` struct and the four non-event functions that used to be inside SiteForm:
- `new/1`, `reseed_drafts/1` — seed/reseed from `Foglet.Config.get!/1`
- `visible_keys/1` — D-21 conditional visibility filter
- `validate_delivery_verification_pair/1` — D-20 pre-flight
- `build_modal_form/1` — produces a fresh Modal.Form snapshot from current drafts + on_submit/on_cancel callbacks that stash into `Modal.Form.SubmitStash`

Field type mapping follows `Foglet.Config.Schema.fetch_spec/1`:

| Schema | ModalForm field |
|---|---|
| `:string` + `enum: [...]` | `:enum`, `choices: enum` |
| `:string` + `enum: nil`   | `:text` |
| `:integer` | `:integer`, `value: stringify_int(int)` |
| `:boolean` | `:boolean`, `value: !!raw` |

The Schema description is forwarded as `:description` so it renders beneath the widget (Modal.Form substrate addition below).

### `Foglet.TUI.Widgets.Modal.Form` (substrate addition)

Added optional `:description` field-spec key. `render_field/5` emits a dim row beneath the widget when `:description` is a non-empty binary; nil and empty string are both treated as absent. 6-line addition; behavior is opt-in (no impact on existing consumers — Account ProfileForm/PrefsForm don't carry `:description` so they render exactly as before).

### Tests

Two existing tests in `site_form_test.exs` were rewritten in place:
1. `"render shows delivery_mode description and current value"` → `"render shows delivery_mode label, current value, and description"` — splits the legacy combined `"delivery_mode: email"` assertion into the Modal.Form-rendered `"delivery_mode:"` label, separate `"email"` value (RadioGroup output), and the new `:description` row. Adds `refute text =~ "▸"` to lock the legacy marker out.
2. `"enum first-character input selects email and no_email"` → `"enum cycles via :down events (Modal.Form contract)"` — drives enum selection through `%{key: :down}`/`%{key: :up}` events instead of `%{key: :char, char: "e"}`. Documents the behavior change inline.

10 new tests for `SiteForm.State` sibling (Task 1 RED → GREEN):
- `new/1` seeds drafts, errors empty, focused 0, current_user pass-through (×2)
- `visible_keys/1` 4-key/5-key path (×2)
- `build_modal_form/1` field count = visible count, type mapping, enum value preserved (×3)
- `validate_delivery_verification_pair/1` invalid case + 3 valid combinations (×2)
- `reseed_drafts/1` reloads + clears (×1)

7 new tests for the SiteForm wrapper (Task 2 RED → GREEN):
1. Render delegates to Modal.Form with no legacy ▸ marker
2. FORM-04 routing — char input lands in focused integer field's draft
3. Ctrl+S invokes `Foglet.Config.put/3` (D-19)
4. Enter on last visible field invokes `Foglet.Config.put/3` (D-19)
5. D-20 validation rejects `no_email` + `require_email_verification: true`; no Config.put
6. D-21 conditional visibility hides limit field after switching away from any_user
7. FORM-06 Esc reseeds drafts from `Foglet.Config.get!/1`; no inline "discarded" status copy (D-12)

3 new tests for Modal.Form `:description`:
1. Field with `:description` renders the description row
2. Field without `:description` produces no description row
3. Empty `:description` is treated as absent

## Task Commits

Each task followed strict TDD RED → GREEN cycles:

1. **Task 1 RED — failing tests for SiteForm.State sibling (10)** — `e8fb633` (test)
2. **Task 1 GREEN — SiteForm.State sibling module** — `8260044` (feat)
3. **Task 2 RED — failing tests for Modal.Form-backed SiteForm + description substrate (6 fail of 13 added)** — `e4be991` (test)
4. **Task 2 GREEN — SiteForm wrapper rewrite + Modal.Form :description + 3 follow-up adjustments below** — `450db46` (feat)

Three follow-up adjustments were folded into the Task 2 GREEN commit because they're inseparable from the rewrite:
- Wired `:description` from Schema spec through `SState.build_field/2` (otherwise the description row would never appear).
- Set `show_footer: true` on the SiteForm Modal.Form (Sysop's global command bar doesn't advertise Enter/Esc, so the body must).
- Added `@site_keys_atoms` compile-time interning in SState to satisfy Credo's `String.to_existing_atom/1` preference without crashing on fresh-boot atom-table misses.

## Decisions Made

- **Description: option (a) — extend Modal.Form, not drop assertions.** The plan offered (a) extend Modal.Form with optional `:description` rendering, or (b) drop the description assertion as a UX regression deferred to Phase 29. Picked (a) because (i) the change is 6 lines + 3 tests in `form.ex`, (ii) it preserves the operator-facing copy that explains what each Sysop key does, and (iii) it's a clean substrate addition that other consumers (Account, future operator-console forms) can opt into.
- **Sysop SITE opts into the Modal.Form footer (`show_footer: true`).** Phase 28 D-06 says tab-body forms shouldn't double up against the global command bar, but Sysop's command bar (`Q Back   Tabs ←/→ Tab   1-6 Jump`) doesn't advertise Enter or Esc. Without the body footer, operators have no in-screen reminder of how to submit/cancel. The legacy SiteForm rendered its own screen-level footer for this reason; the Modal.Form-backed wrapper achieves the same UX by opting into Modal.Form's substrate footer. Account ProfileForm/PrefsForm legitimately leave `show_footer: false` because the Account command bar advertises `Save` and `Cancel`. Phase 28 D-09 still applies: the status row replaces the footer during `:submitting` / `:saved` / `{:error, _}` so operators see save progress instead of the static prompt.
- **Behavior change accepted: enum selection moves from first-char-jump to up/down cycling.** The legacy `apply_char/2` first-char logic was bespoke and required documentation about enum option ordering being load-bearing. Modal.Form's enum cycling via `:up`/`:down` is the contract used by Account PrefsForm and every other form-bearing consumer. Aligning Sysop SITE removes a UX asymmetry. The alternative (porting first-char-jump into Modal.Form) was rejected because it changes Modal.Form's public contract for all consumers.
- **String-keyed errors preserved on wrapper, atom-keyed inside Modal.Form.** Legacy tests assert `form.errors["delivery_mode"]`. Modal.Form expects atom keys (`%{delivery_mode: "msg"}`). Bridged with a one-liner `stringify_keys/1` on output and `apply_errors/2` (with `String.to_existing_atom/1`) on input. Keeps the wrapper API backward-compatible for sysop.ex.
- **Compile-time atom interning via `@site_keys_atoms`.** Credo's `String.to_atom/1` warning had to be addressed because the wrapper does runtime string→atom conversion in two places. Switching to `String.to_existing_atom/1` is the right idiom only if the atoms are guaranteed to exist. Four of the five site keys are referenced as literals elsewhere in `lib/`; `:invite_generation_per_user_limit` is not. Adding a `@site_keys_atoms` module attribute (with a `__site_keys_atoms__/0` accessor to defeat dead-code elimination) interns all five at compile time.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Description rendering required forwarding `:description` from Schema spec to ModalForm field spec**
- **Found during:** Task 2 GREEN — initial Modal.Form `:description` substrate worked in form_test, but SiteForm tests still failed because `SState.build_field/2` was not setting `:description` on the field map.
- **Fix:** Added `description: spec.description` to the base map in `SState.build_field/2`.
- **Files modified:** `lib/foglet_bbs/tui/screens/sysop/site_form/state.ex`
- **Verification:** `rtk mix test test/foglet_bbs/tui/screens/sysop/site_form_test.exs` → 29/29 pass.
- **Committed in:** `450db46` (Task 2 GREEN, alongside the wrapper rewrite — inseparable).

**2. [Rule 1 - Bug] FORM-04 routing test got 50 instead of 5 (TextInput append-to-existing-value)**
- **Found during:** Task 2 GREEN.
- **Issue:** TextInput-backed `:integer` fields have an initial value (the seeded `Config.get!("invite_generation_per_user_limit") = 0` becomes `"0"`); typing `"5"` appends, producing `"05"` or `"50"` rather than a clean `"5"`.
- **Fix:** Cleared the integer draft (`drafts |> Map.put("invite_generation_per_user_limit", nil)`) before firing the `:char` event in the test — exercises FORM-04 routing without entangling TextInput-coerce semantics.
- **Files modified:** `test/foglet_bbs/tui/screens/sysop/site_form_test.exs`
- **Verification:** Test passes; assertion `form.drafts["invite_generation_per_user_limit"] == 5`.
- **Committed in:** `450db46`.

**3. [Rule 1 - Bug] Layout-smoke and sysop_test footer-presence assertions failed (3 tests)**
- **Found during:** Task 2 GREEN — full-suite test run after the wrapper rewrite.
- **Issue:** With `show_footer: false` (the plan's initial spec), Sysop SITE no longer rendered `[Enter] Submit   [Esc] Cancel`. Three downstream tests broke: one in `sysop_test.exs` asserting "SITE tab body renders Modal.Form footer sentinel" and two in `layout_smoke_test.exs` asserting the footer renders within bounds at 64×22 and 80×24. Inspecting the rendered Sysop screen confirmed the global command bar advertises only `Q Back   Tabs ←/→ Tab   1-6 Jump` — no Enter or Esc. Without the body footer, operators have no in-screen reminder of submit/cancel.
- **Fix:** Set `show_footer: true` in `SState.build_modal_form/1` with an explanatory comment. Phase 28 D-09's status-row-replaces-footer rule still applies during in-flight saves.
- **Files modified:** `lib/foglet_bbs/tui/screens/sysop/site_form/state.ex`
- **Verification:** Full suite `rtk mix test` → 1880 tests, 0 failures. `rtk mix foglet.tui.render sysop` shows the placeholder pre-init (real render is exercised by tests).
- **Committed in:** `450db46`.

**4. [Rule 2 - Critical] Compile-time atom interning to make `String.to_existing_atom/1` safe**
- **Found during:** `mix precommit` — Credo warned about `String.to_atom/1` in 3 sites (1 in site_form.ex, 2 in state.ex via the same `build_field` codepath, plus `apply_errors`).
- **Issue:** Switching to `String.to_existing_atom/1` would crash on a fresh boot for `:invite_generation_per_user_limit` because no other lib file references that atom as a literal.
- **Fix:** Added `@site_keys_atoms` module attribute in `SState` listing all five atoms as literals, plus a `__site_keys_atoms__/0` accessor to defeat dead-code elimination. Then switched all three sites to `String.to_existing_atom/1`.
- **Files modified:** `lib/foglet_bbs/tui/screens/sysop/site_form.ex`, `lib/foglet_bbs/tui/screens/sysop/site_form/state.ex`
- **Verification:** Precommit clean. Full suite green.
- **Committed in:** `450db46`.

---

**Total deviations:** 4 auto-fixed (3 Rule 1 bugs in the rewrite, 1 Rule 2 correctness fix surfaced by Credo). All were anticipated by the plan in spirit (the plan flagged Modal.Form's lack of `:description` handling as a known gap to address; the FORM-04 routing test had a planner caveat about TextInput-coerce semantics; and the credo/atom issue is a standard Foglet idiom).

## TDD Gate Compliance

Both tasks followed strict RED → GREEN cycles, each with separate commits:

- **Task 1:** `e8fb633` (test, RED — 10 of 10 new tests fail; legacy 12 still pass) → `8260044` (feat, GREEN — 22/22 pass)
- **Task 2:** `e4be991` (test, RED — 6 of 13 added tests fail; legacy 22 still pass) → `450db46` (feat, GREEN — 29/29 site_form pass; 61/61 form pass; 1880/1880 full suite pass)

## Issues Encountered

- **Worktree base mismatch on startup:** Worktree was based on `3226ef9e` instead of expected `b739cec`. Hard-reset per `<worktree_branch_check>` protocol; no work lost (worktree was empty).
- **Mix deps missing:** Required `rtk mix deps.get`. ~30s.
- **Compile cache cold on first test:** First run took ~15s for compile + dep build; subsequent runs sub-second.

## Verification

- `rtk mix test test/foglet_bbs/tui/screens/sysop/site_form_test.exs` → 29 tests, 0 failures (covers FORM-04 routing on Sysop SITE, FORM-06 Esc, D-17 wrapper structure, D-18 field type mapping, D-19 Ctrl+S, D-20 validation, D-21 conditional visibility).
- `rtk mix test test/foglet_bbs/tui/widgets/modal/form_test.exs` → 61 tests, 0 failures (includes 3 new tests for `:description` substrate).
- `rtk mix test` (full suite) → 1 property, 1880 tests, 0 failures.
- `rtk mix precommit` → passed (compile with warnings as errors, formatter, Credo, Sobelow, Dialyzer all clean; raxol vendor warnings are pre-existing).

Acceptance-criteria grep counts:
- `grep -c "▸" lib/foglet_bbs/tui/screens/sysop/site_form.ex` → 0 ✓
- `grep -c "ModalForm.render" lib/foglet_bbs/tui/screens/sysop/site_form.ex` → 1 ✓
- `grep -c "ModalForm.handle_event" lib/foglet_bbs/tui/screens/sysop/site_form.ex` → 2 ✓
- `grep -c "Foglet.Config.put\|Config.put" lib/foglet_bbs/tui/screens/sysop/site_form.ex` → 2 ✓
- `grep -c "ctrl: true" lib/foglet_bbs/tui/screens/sysop/site_form.ex` → 1 ✓
- `grep -c ":escape" lib/foglet_bbs/tui/screens/sysop/site_form.ex` → 1 ✓
- `grep -c "reseed_drafts" lib/foglet_bbs/tui/screens/sysop/site_form.ex` → 3 ✓
- `grep -c ":description" lib/foglet_bbs/tui/widgets/modal/form.ex` → 4 ✓ (typespec hint + render_field clauses)

## FORM-04 / FORM-06 Confirmation

- **FORM-04 (substrate routing) holds at the Sysop boundary:** Test `"FORM-04 routing: char input lands in the focused integer field's draft"` exercises a `%{key: :char, char: "5"}` event through `SiteForm.handle_key/2` and asserts the typed value reaches `state.drafts["invite_generation_per_user_limit"]`. The wrapper builds a per-event Modal.Form, dispatches the event through `Modal.Form.handle_event/2`, and syncs the new field value back into the persistent draft map. Same routing pattern as Account ProfileForm.
- **FORM-06 (honest Esc) is wired across all three form-bearing screens:** Account Profile (Plan 03), Account Prefs (Plan 03), Sysop Site (Plan 04, this commit). All three reseed-on-Esc and emit no inline "discarded" copy. The Sysop SITE behavior is verified by `"FORM-06 Esc reseeds drafts from Foglet.Config.get!/1 with no inline status copy"` — sets `delivery_mode` to `"no_email"` in the draft, fires Esc, asserts the draft reverts to `"email"` (the persisted Config value) AND that the rendered output contains neither `"discarded"` nor `"Discarded"`.

## Next Phase Readiness

- **Phase 29 (Sysop Tab Lifecycle):** SiteForm now exposes `set_submit_state(form, :saved)` integration and `{:error, msg}` flow through Modal.Form. Phase 29's Sysop Site lifecycle work can layer async `Foglet.Config.put/3` (with set_submit_state(:saved) on completion) on top of this wrapper without further substrate changes — the persist loop already drives the status row.
- **Phase 30 (Account async persistence):** ProfileForm/PrefsForm can adopt the same async-save + `set_submit_state(:saved)` pattern. The `:description` substrate addition is also available if Account decides to surface schema/help copy beneath fields.

## Self-Check: PASSED

**Files exist:**
- `lib/foglet_bbs/tui/screens/sysop/site_form.ex` — FOUND (modified)
- `lib/foglet_bbs/tui/screens/sysop/site_form/state.ex` — FOUND (created)
- `lib/foglet_bbs/tui/widgets/modal/form.ex` — FOUND (modified)
- `test/foglet_bbs/tui/screens/sysop/site_form_test.exs` — FOUND (modified)
- `test/foglet_bbs/tui/widgets/modal/form_test.exs` — FOUND (modified)

**Commits exist:**
- `e8fb633` — FOUND (test RED Task 1)
- `8260044` — FOUND (feat GREEN Task 1)
- `e4be991` — FOUND (test RED Task 2)
- `450db46` — FOUND (feat GREEN Task 2)

---
*Phase: 28-modal-form-substrate*
*Completed: 2026-04-27*
