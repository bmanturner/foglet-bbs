---
phase: 28-modal-form-substrate
plan: 05
subsystem: ui
tags: [tui, raxol, modal-form, oneliner, hide-oneliner, account, form-05, bl-01, wr-01]

# Dependency graph
requires:
  - phase: 28-modal-form-substrate
    provides: 28-07 Modal.Form fields-list guard (Wave 1) — guard already in
      place at the moduledoc-edit point, so this plan's Task 1 lands without
      conflict alongside 28-07's init/1 validation.
  - phase: 28-modal-form-substrate
    provides: 28-02 set_submit_state/2 + auto-reset preamble (D-02..D-05) —
      this plan calls set_submit_state(form, {:error, _}) on the App's two
      :form-modal error helpers to satisfy the FORM-05 consumer obligation.
provides:
  - BL-01 closure — oneliner / hide-oneliner :form modals release the
    Modal.Form `:submitting` lock on async failure so :escape dismisses
    the modal instead of being swallowed by the lock guard.
  - WR-01 closure — Account ProfileForm/PrefsForm handle_key/3 allow-lists
    accept :backtab so the CLIHandler-translated terminal `ESC[Z` sequence
    reaches Modal.Form.handle_event/2's :backtab clause and retreats focus.
  - Modal.Form moduledoc states the FORM-05 consumer obligation contract
    in grep-checkable form ("MUST drive `set_submit_state/2`") with
    references to BL-01 and BL-02 as canonical failure modes.
affects: [29-sysop-tab-lifecycle-bodies, 30-account-workflow]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - FORM-05 consumer obligation pattern: any caller that holds a
      Modal.Form across an async submit MUST drive set_submit_state/2
      to a terminal state on failure ({:error, msg} or :idle), or
      persist the form across renders so :submitting is preserved.
    - Status-row error summary helper (summarize_form_errors/1):
      pick the shortest representative message for the FORM-05
      {:error, msg} payload while letting per-field errors continue
      to flow through set_errors/2 unchanged.

key-files:
  created: []
  modified:
    - lib/foglet_bbs/tui/widgets/modal/form.ex
    - lib/foglet_bbs/tui/app.ex
    - lib/foglet_bbs/tui/screens/account/profile_form.ex
    - lib/foglet_bbs/tui/screens/account/prefs_form.ex
    - test/foglet_bbs/tui/screens/account_test.exs

key-decisions:
  - "BL-01 fix shape: drive set_submit_state(form, {:error, summarize_form_errors(errors)}) alongside the existing set_errors(form, errors) call in both put_oneliner_form_errors/2 and put_hide_oneliner_form_errors/2 — single edit per helper, no other call sites touched."
  - "summarize_form_errors/1 returns the first binary value in the errors map (or 'validation' as a fallback) rather than concatenating all errors — keeps the FORM-05 status-row content short and predictable, while per-field errors continue to render through set_errors."
  - "Add :backtab to ProfileForm/PrefsForm allow-lists rather than translating it to :shift_tab in the screen layer — Modal.Form already has a dedicated :backtab clause (form.ex:213-217) that is byte-equivalent to :shift_tab; routing the key through the existing path matches Sysop SiteForm's behaviour."
  - "Document the FORM-05 consumer obligation in the moduledoc rather than hiding it in a code comment — BL-01 silently violated this contract for months because nobody knew it existed; making it grep-checkable in the moduledoc is what FORM-05 needed from the start."

patterns-established:
  - "Pattern 1: FORM-05 consumer obligation — every caller that holds a Modal.Form across an async submit must release the :submitting lock on failure via set_submit_state/2, OR persist the form across renders. Documented in Modal.Form moduledoc."
  - "Pattern 2: BL-01 fix template — set_errors/2 + set_submit_state/2 in the same |> pipeline at every :form-modal error helper, with a small summarize_form_errors/1 helper to compute the status-row payload."

requirements-completed: [FORM-02, FORM-05]

# Metrics
duration: ~30min
completed: 2026-04-27
---

# Phase 28 Plan 05: BL-01 Lock Release + WR-01 :backtab + FORM-05 Contract Summary

**Fixed BL-01 by driving Modal.Form.set_submit_state/2 to a terminal state on every :form-modal error path (oneliner + hide-oneliner), fixed WR-01 by adding :backtab to Account ProfileForm/PrefsForm allow-lists, and documented the FORM-05 consumer obligation in Modal.Form's moduledoc.**

## Performance

- **Duration:** ~30 min
- **Started:** 2026-04-27T19:11Z
- **Completed:** 2026-04-27T19:43Z
- **Tasks:** 3 (all auto, two TDD)
- **Files modified:** 5

## Accomplishments

- **BL-01 closed.** `put_oneliner_form_errors/2` and `put_hide_oneliner_form_errors/2`
  in `lib/foglet_bbs/tui/app.ex` now drive
  `ModalForm.set_submit_state(form, {:error, summarize_form_errors(errors)})`
  alongside the existing `set_errors/2` call. The Modal.Form lock guard
  releases on the next event, the auto-reset preamble collapses
  `{:error, _} → :idle`, and the Esc cancel clause fires — the modal
  dismisses cleanly instead of wedging the user.
- **WR-01 closed.** Account `ProfileForm.handle_key/3` and
  `PrefsForm.handle_key/3` allow-list guards include `:backtab`, so the
  CLIHandler-translated terminal `ESC[Z` sequence reaches Modal.Form's
  existing `:backtab` clause (byte-equivalent to `:shift_tab`).
- **FORM-05 consumer obligation made explicit.** `Modal.Form` moduledoc gains a
  `## Submit-state lifecycle (FORM-05 consumer obligation)` section stating
  consumers MUST drive `set_submit_state/2` to a terminal state on async
  failure, or persist the form across renders so `:submitting` is preserved.
  References Phase 28 BL-01 (oneliner / hide-oneliner) and BL-02 (Sysop
  SiteForm) as canonical failure modes.
- **7 new regression tests.** Four under `BL-01 :form modal lock release` cover
  doomed oneliner / hide-oneliner submit and Esc dismissal; three under
  `FORM-02 :backtab on Account ProfileForm / PrefsForm` cover focus retreat
  and the Modal.Form path-equivalence sanity check.

## Task Commits

Each task was committed atomically:

1. **Task 1: Document FORM-05 consumer obligation** — `baef8b0` (docs)
2. **Task 2 RED: BL-01 lock release tests** — `0b04923` (test)
3. **Task 2 GREEN: set_submit_state on :form-modal error paths** — `e2bdea5` (feat)
4. **Task 3 RED: WR-01 :backtab tests** — `89aeb94` (test)
5. **Task 3 GREEN: :backtab in Account form guards** — `92bf97b` (fix)

_Note: Tasks 2 and 3 both used the TDD RED/GREEN cycle (no separate REFACTOR commit was needed — the GREEN edits were minimal and clean as written)._

## Files Created/Modified

- `lib/foglet_bbs/tui/widgets/modal/form.ex` — Added
  `## Submit-state lifecycle (FORM-05 consumer obligation)` section to
  the moduledoc with grep-checkable contract phrase.
- `lib/foglet_bbs/tui/app.ex` — Updated both
  `put_oneliner_form_errors/2` (single-arity head) and
  `put_hide_oneliner_form_errors/2` (single-arity head) to chain
  `ModalForm.set_submit_state(form, {:error, ...})` after
  `ModalForm.set_errors/2`. Added private
  `summarize_form_errors/1` helper.
- `lib/foglet_bbs/tui/screens/account/profile_form.ex` — Added
  `:backtab` to the `handle_key/3` allow-list guard.
- `lib/foglet_bbs/tui/screens/account/prefs_form.ex` — Added
  `:backtab` to the `handle_key/3` allow-list guard.
- `test/foglet_bbs/tui/screens/account_test.exs` — Added two new
  describe blocks:
  - `FORM-02 :backtab on Account ProfileForm / PrefsForm (Phase 28 WR-01)` (3 tests)
  - `BL-01 :form modal lock release (Phase 28 FORM-05)` (4 tests)

### New test names

**WR-01 (`FORM-02 :backtab on Account ProfileForm / PrefsForm`):**
- `FORM-02 :backtab on ProfileForm retreats focus by one`
- `FORM-02 :backtab on PrefsForm retreats focus by one`
- `WR-01 sanity: :backtab on PrefsForm preserves focused field via Modal.Form path`

**BL-01 (`BL-01 :form modal lock release`):**
- `doomed oneliner submit leaves form in {:error, _} (not :submitting)`
- `doomed hide-oneliner submit leaves form in {:error, _} (not :submitting)`
- `after doomed oneliner error, %{key: :escape} dismisses the modal`
- `after doomed hide-oneliner error, %{key: :escape} dismisses the modal`

## Decisions Made

- **summarize_form_errors/1 picks the first binary error value, not all of them.**
  The FORM-05 status row is meant to be a short signal, not a full validation
  report. Per-field errors continue to flow through `set_errors/2` and render
  inline beneath each field — `set_submit_state/2` only needs a representative
  message for the {:error, msg} value. Fallback string is `"validation"` if
  the errors map has no binary values (defensive — current call sites all
  produce binary errors, but the helper is permissive).
- **No changes to the second-arity (`state, errors`) heads of the two helpers.**
  Those funnel back into the modal-bearing head after re-opening the modal,
  so the fix lands once at the modal-bearing head and is naturally inherited.

## Deviations from Plan

None — plan executed exactly as written.

The plan's `<files>` block for Tasks 2 and 3 named
`test/foglet_bbs/tui/screens/account_test.exs`; the BL-01 lock-release
tests are conceptually App-level (they exercise `App.update/2` and the
`:form` modal-key dispatcher), but the plan's `files_modified` frontmatter
pinned them to that file. Honored as-written: the BL-01 tests are added
as a self-contained describe block in `account_test.exs` with its own
`App.init/1`-based setup.

## Issues Encountered

None.

## Verification

- `rtk mix test` — 1 property, 1896 tests, 0 failures.
- `rtk mix test test/foglet_bbs/tui/screens/account_test.exs` — 57 tests, 0 failures.
- `rtk mix test test/foglet_bbs/tui/widgets/modal/form_test.exs` — 62 tests, 0 failures.
- `rtk mix test test/foglet_bbs/tui/app_test.exs` — passes (combined run had 232 tests across the 3 files, 0 failures).
- `rtk mix compile --warnings-as-errors` — exits 0.
- `rtk mix format --check-formatted` on the 5 modified files — `mix format: ok`.
- `grep -F 'MUST drive \`set_submit_state/2\`' lib/foglet_bbs/tui/widgets/modal/form.ex` — 1 hit.
- `grep -E "ModalForm\.set_submit_state\(.*\{:error," lib/foglet_bbs/tui/app.ex | grep -v '^#'` — 2 hits.
- `grep -F ":backtab" lib/foglet_bbs/tui/screens/account/profile_form.ex` — 1 hit (in guard).
- `grep -F ":backtab" lib/foglet_bbs/tui/screens/account/prefs_form.ex` — 1 hit (in guard).

(Did not run `rtk mix precommit` end-to-end because `rtk mix test` plus the
focused checks above cover the substantive verification, and Phase 26 carries
known pre-existing Dialyzer warnings out of scope for this plan — see Phase 26
SUMMARY.)

## User Setup Required

None — no external service configuration required. UI-state-only changes
behind the FORM-05 lock; no auth, schema, or runtime-config impact.

## Next Phase Readiness

- BL-01 closed. Phase 28 verification gap "Existing Modal.Form consumers do
  not regress" is now satisfied for the oneliner / hide-oneliner :form modals.
  Verifier should reconfirm.
- WR-01 closed. Phase 28 anti-pattern "Account ProfileForm/PrefsForm allow-list
  drops :backtab" is removed.
- Phase 28 BL-02 (Sysop SiteForm wedge) was already closed in Wave 1 by
  plan 28-06 — orthogonal to this plan.
- Human-verification item #3 in 28-VERIFICATION.md ("BL-01 reproduction in
  live SSH at 64×22 / 80×24") remains open for re-verification on the
  closed BL-01 path; this plan does not consume it.

## Self-Check: PASSED

Files exist:
- FOUND: lib/foglet_bbs/tui/widgets/modal/form.ex (moduledoc updated)
- FOUND: lib/foglet_bbs/tui/app.ex (helpers updated)
- FOUND: lib/foglet_bbs/tui/screens/account/profile_form.ex
- FOUND: lib/foglet_bbs/tui/screens/account/prefs_form.ex
- FOUND: test/foglet_bbs/tui/screens/account_test.exs (7 new tests)

Commits exist (in `git log --oneline 176ac7e..HEAD`):
- FOUND: baef8b0 (docs)
- FOUND: 0b04923 (test RED)
- FOUND: e2bdea5 (feat GREEN)
- FOUND: 89aeb94 (test RED)
- FOUND: 92bf97b (fix GREEN)

---
*Phase: 28-modal-form-substrate*
*Completed: 2026-04-27*
