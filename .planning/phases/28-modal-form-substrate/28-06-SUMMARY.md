---
phase: 28-modal-form-substrate
plan: 06
subsystem: tui
tags: [modal-form, sysop, site-form, form-05, form-state, bl-02, gap-closure]

# Dependency graph
requires:
  - phase: 28-modal-form-substrate
    provides: "Modal.Form submit_state machine + lock guard + auto-reset preamble (form.ex), Sysop SiteForm Modal.Form-backed wrapper (28-04 SUMMARY)"
provides:
  - "SiteForm.State.submit_state field that persists FORM-05 lifecycle across the per-render Modal.Form rebuild"
  - "Render-time + dispatch-time seeding of state.submit_state onto the freshly-built Modal.Form via Map.put/3"
  - "sync_back/2 carries form.submit_state back onto SState (the missing half of the FORM-05 contract on this consumer)"
  - "D-08/D-09 status row (\"Saved.\" / \"Error: validation\") finally renders on Sysop SITE"
  - "FORM-05 lock guard semantics extended to the SiteForm consumer (D-02 protective intent restored)"
  - "reseed_drafts/1 collapses submit_state → :idle along with drafts (D-12 honest-Esc)"
affects: [28-modal-form-substrate verification re-run, 28-WR-02 follow-up (non-transactional Config.put cascade — not addressed here)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Per-render widget rebuild + lifecycle persistence on the wrapper struct: the Modal.Form is rebuilt per-render so D-21 conditional visibility takes effect immediately, but FORM-05 lifecycle state must round-trip wrapper → form (seed) → wrapper (sync_back) so the lock + status-row contract holds across the rebuild."

key-files:
  created: []
  modified:
    - "lib/foglet_bbs/tui/screens/sysop/site_form/state.ex"
    - "lib/foglet_bbs/tui/screens/sysop/site_form.ex"
    - "test/foglet_bbs/tui/screens/sysop/site_form_test.exs"

key-decisions:
  - "Direct Map.put(:submit_state, state.submit_state) on the rebuilt form rather than ModalForm.set_submit_state/2: the setter raises ArgumentError on :submitting (D-03 reservation), but the wrapper must be able to faithfully replay any persisted lifecycle value, including :submitting between an internal :idle → :submitting transition and the consuming screen's set_submit_state call."
  - "Persist submit_state on SState rather than caching the entire Modal.Form struct: minimal additive defstruct change (option 2 from 28-REVIEW.md BL-02 §Fix) — keeps build_modal_form/1's per-render rebuild semantics intact for D-21 conditional visibility."
  - "reseed_drafts/1 (Esc) drops submit_state → :idle along with drafts: D-12 honest-Esc semantics — no stale \"Saved.\" or \"Error: …\" pinned across a discard."
  - "Auto-reset preamble (form.ex:178-184) interaction: on the next non-locked event the rebuilt form auto-resets :saved / {:error, _} → :idle, dispatch runs, sync_back persists :idle back onto SState. The lifecycle-persistence patch does NOT defeat auto-reset; it just lets the terminal state survive long enough to render."

patterns-established:
  - "Wrapper-struct-as-source-of-truth for per-keystroke widget rebuilds: when a tab body opts to rebuild its Modal.Form per render (e.g. for conditional visibility), the wrapper struct MUST hold any FORM-05 lifecycle so the lock guard + D-08/D-09 status row hold across the rebuild. SiteForm is now the reference consumer for this pattern; ProfileForm and PrefsForm preserve the form between renders and so do not require this round-trip."
  - "Direct Map.put on a public widget field is acceptable when the public setter cannot reach the desired transition: ModalForm.set_submit_state/2 reserves :submitting per D-03, but a wrapper that owns lifecycle persistence must be able to seed all four states. This is documented inline at site_form.ex render/2."

requirements-completed: [FORM-05]

# Metrics
duration: ~25min
completed: 2026-04-27
---

# Phase 28 Plan 06: BL-02 Gap Closure — SiteForm submit_state Persistence Summary

**Persist `Modal.Form.submit_state` on `Foglet.TUI.Screens.Sysop.SiteForm.State` so the FORM-05 lock guard and the D-08/D-09 status-row contract survive the per-render Modal.Form rebuild — closing BL-02 from 28-VERIFICATION.md.**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-04-27T19:25:00Z
- **Completed:** 2026-04-27T19:50:00Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments

- **BL-02 closed.** SiteForm now persists `submit_state` on `SiteForm.State` across the rebuild driven by `SState.build_modal_form/1`. Four wrapper sites (`render/2`, catch-all `handle_key/2`, `submit/1`, and `sync_back/2`) all participate in the round-trip: render and dispatch sites seed the freshly-built form via `Map.put(:submit_state, state.submit_state)`; `sync_back/2` writes the post-event `form.submit_state` back onto SState.
- **D-08/D-09 status-row contract restored on Sysop SITE.** A successful Ctrl+S now renders the literal "Saved." row; a `validate_delivery_verification_pair/1` rejection (delivery_mode=no_email + require_email_verification=true) renders "Error: validation".
- **FORM-05 D-02 lock-guard intent restored on this consumer.** When a future async-Config.put path leaves the form in `:submitting`, subsequent events on SiteForm now see the persisted `:submitting` on the rebuilt form and are correctly lock-swallowed.
- **Auto-reset (D-04) preserved.** The preamble at form.ex:178-184 still collapses `:saved` / `{:error, _}` → `:idle` on the next non-locked event; sync_back persists the now-`:idle` value back to SState. A regression test (the fourth new test) exercises this directly.
- **D-12 honest-Esc preserved.** `reseed_drafts/1` drops `submit_state` to `:idle` along with drafts — Esc cannot leave a stale "Saved." / "Error: …" pinned across a discard.

## Task Commits

Each task was committed atomically:

1. **Task 1: RED — failing tests for FORM-05 lock + status row on SiteForm** — `a41f038` (test)
2. **Task 2: GREEN — persist submit_state on SState; re-apply across rebuild** — `8d2ff50` (feat)
3. **Task 3: Sanity sweep + precommit checks** — _no commit_ (sysop suite, modal widget tests, layout smoke, compile-warnings-as-errors, format all clean — no follow-up edit required)

## Files Created/Modified

- `lib/foglet_bbs/tui/screens/sysop/site_form/state.ex` — Added `submit_state: ModalForm.submit_state()` to `@type t` and the defstruct (default `:idle`); `reseed_drafts/1` now also resets `submit_state: :idle` per D-12.
- `lib/foglet_bbs/tui/screens/sysop/site_form.ex` — `render/2`, the catch-all `handle_key/2` clause, and `submit/1` each thread `state.submit_state` into the freshly-built Modal.Form via `Map.put(:submit_state, state.submit_state)` BEFORE `apply_errors`/dispatch; `sync_back/2` persists `form.submit_state` back onto SState.
- `test/foglet_bbs/tui/screens/sysop/site_form_test.exs` — Added `describe "BL-02: FORM-05 lock + status row persistence on SiteForm"` block with four new tests:
  - `double Ctrl+S preserves submit_state across the per-render rebuild` (asserts `state.submit_state == :saved` after one and two Ctrl+S events — the persistence assertion)
  - `successful Ctrl+S renders "Saved." status row (D-08/D-09)` (asserts the rendered tree contains the literal `"Saved."`)
  - `validation-failure Ctrl+S renders "Error: validation" status row` (asserts the rendered tree contains the literal `"Error: validation"`)
  - `auto-reset still collapses :saved to :idle on the next non-locked event` (regression guard for D-04 — drives Tab after a save and asserts both `state.submit_state == :idle` and that "Saved." is absent from the next render)

## Decisions Made

- **Map.put on `:submit_state` rather than `ModalForm.set_submit_state/2`.** The setter raises on `:submitting` per D-03 (the `:idle → :submitting` transition is reserved for the internal Enter-on-last-field clause). The wrapper must replay the full persisted lifecycle including `:submitting`, so direct field assignment is the correct seam. Documented inline at `render/2`.
- **Persist `submit_state` on the wrapper struct rather than caching the whole form.** The plan's option-2 minimal patch keeps `build_modal_form/1`'s per-render rebuild intact, which is required for D-21 conditional visibility. No structural change to the rebuild model.
- **`reseed_drafts/1` includes `submit_state: :idle`.** D-12 honest-Esc semantics: the visible reversion of fields IS the cancel signal, so a stale terminal status row would be misleading after Esc.

## Deviations from Plan

None - plan executed exactly as written.

The plan's Task 1 acceptance text described two equivalent strategies for proving "double-Enter single-fire" (Config.put count vs. submit_state lock assertion). The implementation chose the persistence-on-state assertion (`state.submit_state == :saved` after each call) because it's deterministic, requires no `:meck`, and directly tests the BL-02 root cause (sync_back drops submit_state). This matches the plan's "Acceptable alternative implementation" guidance and is documented in the test docstrings.

## Issues Encountered

- Worktree was initialized at `3226ef9e` (older `main` snapshot) rather than the documented base `d72becd2`. Hard-reset to `d72becd2` per the `<worktree_branch_check>` protocol; no user changes lost (fresh worktree). One-time deps fetch (`mix deps.get`) was required before tests could run.

## TDD Gate Compliance

- **RED gate:** `a41f038 test(28-06): RED for BL-02 SiteForm submit_state persistence` — all four new tests failed with `KeyError: :submit_state` (struct lacks the field) and missing `"Saved."` / `"Error: validation"` substrings.
- **GREEN gate:** `8d2ff50 feat(28-06): persist Modal.Form submit_state on SiteForm.State (BL-02)` — all four new tests pass; the 29 pre-existing `site_form_test.exs` tests continue to pass; broader `test/foglet_bbs/tui/screens/sysop/` (40/40), `test/foglet_bbs/tui/widgets/modal/` (67/67), and `test/foglet_bbs/tui/layout_smoke_test.exs` (68/68) all pass.
- **REFACTOR gate:** Not needed — minimal additive change, no follow-up cleanup required.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- **BL-02 ready for verification re-run.** The 28-VERIFICATION.md gap entry should now mark "FORM-05 lock + status row" verified for the Sysop SITE consumer. The two truths previously failing on this gap (`Two back-to-back Enter events ... invoke on_submit exactly once` and `submit_state ≠ :idle ⇒ visible status row`) should now pass.
- **Out of scope (flagged for follow-up):** WR-02 — non-transactional Config.put cascade in `persist_payload/3`. A partial cascade still leaves Config rows for already-written keys mutated even when a later key fails with `:forbidden` / `:db_error`. Per the plan's `<success_criteria>` this is explicitly deferred and not addressed here.

## Threat Flags

No new auth/data surfaces introduced. The threat register entries (T-28-06-01 mitigate / T-28-06-02 accept / T-28-06-03 accept) from the plan all hold:
- **T-28-06-01 (DoS — Config.put cascade) — mitigated:** persisting `submit_state` engages the FORM-05 lock as designed; the consumer no longer silently nullifies the D-02 protective intent.
- **T-28-06-02 (Tampering — submit_state) — accepted:** `submit_state` is UI-only state; no policy decision keys off it.
- **T-28-06-03 (Information Disclosure — "Error: validation" literal) — accepted:** static literal; per-field error payloads continue to flow through the Modal.Form errors map and render inline.

## Self-Check: PASSED

- File `lib/foglet_bbs/tui/screens/sysop/site_form/state.ex` exists with `submit_state: :idle` defstruct field and `submit_state: ModalForm.submit_state()` in `@type t` — verified.
- File `lib/foglet_bbs/tui/screens/sysop/site_form.ex` exists with three `Map.put(:submit_state, state.submit_state)` call sites (`render/2`, catch-all `handle_key/2`, `submit/1`) and `submit_state: ss` written by `sync_back/2` — verified.
- File `test/foglet_bbs/tui/screens/sysop/site_form_test.exs` exists with the BL-02 describe block and the four new tests; substrings `"Saved."`, `"Error: validation"`, and "double Ctrl+S" present — verified.
- Commit `a41f038 test(28-06): RED for BL-02 SiteForm submit_state persistence` exists in `git log` — verified.
- Commit `8d2ff50 feat(28-06): persist Modal.Form submit_state on SiteForm.State (BL-02)` exists in `git log` — verified.
- `rtk mix test test/foglet_bbs/tui/screens/sysop/site_form_test.exs` → 33/33 passing.
- `rtk mix test test/foglet_bbs/tui/screens/sysop/` → 40/40 passing.
- `rtk mix test test/foglet_bbs/tui/widgets/modal/` → 67/67 passing.
- `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` → 68/68 passing.
- `rtk mix compile --warnings-as-errors` → no foglet_bbs warnings (only pre-existing unrelated raxol warnings about `Mogrify`/`Nx`/`Benchee.Formatter` — out of scope per Plan 28-06 boundary, untouched by this patch).
- `rtk mix format --check-formatted` on the three modified files → ok.

---
*Phase: 28-modal-form-substrate*
*Plan: 06*
*Completed: 2026-04-27*
