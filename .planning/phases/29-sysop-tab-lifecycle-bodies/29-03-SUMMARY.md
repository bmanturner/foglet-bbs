---
phase: 29-sysop-tab-lifecycle-bodies
plan: 03
subsystem: ui
tags:
  - tui
  - sysop
  - site
  - config
  - copy
  - operator-facing

# Dependency graph
requires:
  - phase: 28-modal-form-substrate
    provides: SiteForm Modal.Form wrapper, Saved./Esc-reseed contract (D-08, D-12, D-17..D-21)
provides:
  - SYSOP-04 invariant — `@site_keys` descriptions free of planning-ID, phase, pitfall, deliverable tokens
  - Phase 29 regression suite locking D-18 (Enter→Foglet.Config.put/3), D-19 ("Saved." substring), D-20/D-21 (Esc reseed honoring Phase 28 D-12)
  - Schema regex test (`Foglet.Config.SchemaTest`) enforcing operator-facing copy hygiene as a permanent invariant
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Schema regex hygiene test: case-insensitive `(D-\\d+|REQ-[A-Z]+-\\d+|Phase \\d+|Pitfall \\d+|deliverable)/i` over a fixed key set, plus ends-with-period assertion"
    - "Audit-only Phase 29 plan: Phase 28 substrate already satisfied D-18..D-21; tests lock the contract without code changes"

key-files:
  created: []
  modified:
    - "lib/foglet_bbs/config/schema.ex"
    - "test/foglet_bbs/config/schema_test.exs"
    - "test/foglet_bbs/tui/screens/sysop/site_form_test.exs"

key-decisions:
  - "D-22/D-23: Five `@site_keys` descriptions rewritten verbatim per the locked literal table. No enum value lists inlined — operators discover legal values by Space-cycling per Modal.Form's enum field idiom."
  - "D-18 audit: Phase 28 already wires the on_submit cascade (validate_delivery_verification_pair pre-flight → Foglet.Config.put/3 per visible key → Modal.Form.set_submit_state(:saved) on success). NO code change in lib/foglet_bbs/tui/screens/sysop/site_form.ex."
  - "D-20 audit: Phase 28 already wires the on_cancel reseed (SState.reseed_drafts/1 reloads from Foglet.Config.get!/1, clears errors/focus, drives submit_state → :idle). NO `status_message` field added; Phase 28 D-12 honored verbatim."
  - "Existing schema_test.exs spec-equality assertions and existing site_form_test.exs render assertions referenced the OLD literal description substrings — updated in Task 1's commit (Rule 3 blocking auto-fix). Without the update the description rewrites would have broken 6 pre-existing tests."

patterns-established:
  - "Operator-facing copy regex test pattern: iterate the SiteForm's authoritative key list, fetch each spec, refute the forbidden token regex, assert the description ends with a period. Reusable for any future operator-visible key set."
  - "D-18/D-19 acceptance assertion shape: focus the SiteForm to its last visible field, dispatch `:enter`, then assert (a) `Config.get!/1` returns the mutated draft and (b) the rendered text contains the substring `\"Saved.\"`. Mirrored in the validation-failure negative."
  - "D-20/D-21 acceptance assertion shape: mutate a draft, dispatch `:escape`, then assert (a) `state.drafts[key] == Config.get!/1`, (b) saved value is rendered, (c) returned events list contains no `:navigate` or `:pop_screen` tuples, (d) the rendered text does NOT contain any of `draft discarded` / `Changes discarded` / `Discarded`."

requirements-completed:
  - SYSOP-03
  - SYSOP-04

# Metrics
duration: 30min
completed: 2026-04-27
---

# Phase 29 Plan 03: Sysop Site Editability + Site-Field Operator Copy Summary

**SYSOP-03 (Site editability) and SYSOP-04 (operator-facing copy) lock down on top of the Phase 28 Modal.Form substrate — five `@site_keys` description rewrites + a regex hygiene test eliminate planning IDs from operator copy permanently, and a Phase 29 regression suite locks D-18 (Enter→`Foglet.Config.put/3`), D-19 ("Saved." status row), and D-20/D-21 (Esc reseed honoring Phase 28 D-12) as invariants — no SiteForm code changes required.**

## Performance

- **Duration:** ~30 min
- **Started:** 2026-04-27 (afternoon)
- **Completed:** 2026-04-27
- **Tasks:** 2
- **Files modified:** 3 (0 created, 3 modified)
- **Commits:** 2 atomic

## Accomplishments

- **D-22/D-23 description rewrites (Task 1):** All five `@site_keys` descriptions in `lib/foglet_bbs/config/schema.ex` now read as short user-facing operator copy. `registration_mode` → `"How new accounts are created."`; `invite_code_generators` → `"Who can generate invite codes."`; `delivery_mode` → `"Whether outbound email is sent."`; `require_email_verification` → `"Require email verification before login."`; `invite_generation_per_user_limit` → `"Per-user invite cap (0 = unlimited)."` Every other field of every entry (`label`, `default`, `enum`, `min`, `max`, `type`, `key`) is untouched.
- **SYSOP-04 regex test (Task 1):** New describe block in `test/foglet_bbs/config/schema_test.exs` iterates the five `@site_keys`, fetches each spec via `Schema.fetch_spec/1`, and refutes the case-insensitive regex `(D-\d+|REQ-[A-Z]+-\d+|Phase \d+|Pitfall \d+|deliverable)/i`. A second test asserts every description is non-empty and ends with a period. The invariant is now permanent — any future regression breaks the test suite.
- **D-18 / D-19 audit (Task 2):** Phase 28's SiteForm already runs `validate_delivery_verification_pair/1` as the on_submit pre-flight (inside `SState.build_modal_form/1`'s `on_submit` closure → stash → wrapper finalize), iterates `Foglet.Config.put/3` over `visible_keys` in `persist_payload/3` (lib/foglet_bbs/tui/screens/sysop/site_form.ex:165–211), and calls `ModalForm.set_submit_state(new_form, :saved)` on the all-keys-success branch (line 206). NO code changes were necessary in `site_form.ex`.
- **D-20 / D-21 audit (Task 2):** Phase 28's `Esc` handler at `site_form.ex:80–83` calls `SState.reseed_drafts/1`, which reloads drafts from `Foglet.Config.get!/1`, resets errors and focus, and drives `submit_state` to `:idle` (state.ex:99–105). No `status_message` field exists on `SiteForm.State`. Phase 28 D-12 was already honored.
- **Phase 29 regression suite (Task 2):** Two new describe blocks in `test/foglet_bbs/tui/screens/sysop/site_form_test.exs`:
  - `"Sysop Site Enter persistence (D-18, D-19)"` — focuses the SiteForm to its last visible field, dispatches `:enter`, and asserts (a) `Config.get!/1` reflects the mutated draft and (b) the rendered text contains `"Saved."` (Phase 28 D-08). Negative case asserts a `delivery_mode=no_email + require_email_verification=true` payload is rejected without persistence and without a `"Saved."` row, with `submit_state` landing in `{:error, _}`.
  - `"Sysop Site Esc reseed (D-20, D-21)"` — four tests covering (a) drafts equal saved Config, (b) rendered values reflect saved Config, (c) no navigate/pop event in returned events list, and (d) no `"draft discarded"` / `"Changes discarded"` / `"Discarded"` copy in the rendered output.
- **All 39 SiteForm tests + 40 schema tests pass.** Compile clean with `--warnings-as-errors`.

## Task Commits

Each task was committed atomically:

1. **Task 1: Rewrite 5 `@site_keys` descriptions + SYSOP-04 regex test** — `e960232` (feat)
2. **Task 2: SiteForm Enter/Esc D-18/D-19/D-20/D-21 regression suite** — `24f0971` (test)

## Files Created/Modified

**Created:** none — Task 2's audit revealed Phase 28 already delivers everything D-18..D-21 require, so no new source files were needed.

**Modified:**
- `lib/foglet_bbs/config/schema.ex` — Five `description:` strings rewritten verbatim per D-23. No other field changed; entry order, key set, and all type/enum/min/max constraints are byte-identical to pre-edit.
- `test/foglet_bbs/config/schema_test.exs` — Five existing `Schema.fetch_spec/1` spec-equality assertions updated to match the new descriptions (Rule 3 blocking — old literal substrings would have broken otherwise). Appended a new `describe "@site_keys descriptions are user-facing operator copy (SYSOP-04)"` block with two tests: forbidden-token regex refute + ends-with-period assertion.
- `test/foglet_bbs/tui/screens/sysop/site_form_test.exs` — Two existing render assertions updated from `"Outbound transactional delivery mode"` / `"Account registration policy"` → the new descriptions (Rule 3 blocking — same root cause). Appended two new Phase 29 describe blocks: `"Sysop Site Enter persistence (D-18, D-19)"` (2 tests) and `"Sysop Site Esc reseed (D-20, D-21)"` (4 tests).

## Decisions Made

- **NO `lib/foglet_bbs/tui/screens/sysop/site_form.ex` edits.** Phase 28 already satisfies D-18 and D-20 verbatim — adding code would have introduced redundancy and risked re-shaping the BL-02 lock contract. This is the explicit "audit may show Phase 28 already delivers everything" outcome the plan flagged in `<action>` Step 1.
- **NO new `status_message` field on `SiteForm.State`.** D-20 / D-21 explicitly reject this. The visible signal of Esc is field-value reversion on the next render. Phase 28 D-12 contract preserved.
- **NO Sysop-specific `Saved.` copy.** D-19 reuses Phase 28 D-08's substring verbatim. Acceptance test asserts the exact substring `"Saved."`.
- **Existing-test breakage was a pre-existing lock.** Task 1's description rewrites broke 4 spec-equality tests in `schema_test.exs` and 2 render-assertion lines in `site_form_test.exs` that referenced old literals — Rule 3 blocking auto-fix in the same Task 1 commit avoided false-negative regressions.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Updated existing schema_test.exs spec-equality assertions to match new descriptions**
- **Found during:** Task 1 (after the `description:` rewrites)
- **Issue:** `test/foglet_bbs/config/schema_test.exs` had 5 `Schema.fetch_spec/1` tests that asserted the entire spec map equals a literal — including the old description strings on lines 50, 64, 108, 122, 152. Without updating these, Task 1's rewrites would break 5 pre-existing schema tests.
- **Fix:** Updated each spec-equality test to use the new D-23 description literal.
- **Files modified:** `test/foglet_bbs/config/schema_test.exs`
- **Verification:** All 40 schema tests pass, including the 5 updated spec-equality tests + the 2 new SYSOP-04 regex tests.
- **Committed in:** `e960232` (Task 1 commit)

**2. [Rule 3 - Blocking] Updated existing site_form_test.exs render assertions to match new descriptions**
- **Found during:** Task 1
- **Issue:** `test/foglet_bbs/tui/screens/sysop/site_form_test.exs` had 2 render-output assertions (lines 61 + 345-346) asserting the rendered SiteForm output contained the OLD description substrings (`"Outbound transactional delivery mode"`, `"Account registration policy"`). The Modal.Form `:description` row passes the schema description through verbatim, so rewriting the descriptions also breaks these renders.
- **Fix:** Updated both assertions to the new descriptions (`"Whether outbound email is sent."`, `"How new accounts are created."`).
- **Files modified:** `test/foglet_bbs/tui/screens/sysop/site_form_test.exs`
- **Verification:** All 33 pre-existing SiteForm tests still pass (and all 39 after Task 2's additions).
- **Committed in:** `e960232` (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (both Rule 3 blocking). Both were in-scope cleanups required for the plan's intended changes to land green. No scope creep.

**Plan deviation: NO `site_form.ex` code changes.** The plan's `<action>` Step 1 explicitly flagged this as a possible audit outcome ("If `persist_payload/3` already calls `set_submit_state(form, :saved)` on success, NO CODE CHANGE is needed"). The audit confirmed all Phase 28 wiring is in place; only the test suite was extended.

## Issues Encountered

- **Worktree base mismatch at startup.** `git merge-base HEAD a1f9dc6...` returned `3226ef9...` (one commit ahead of expected). Recovered with `git reset --hard a1f9dc6...` per the `<worktree_branch_check>` protocol. No work lost.
- **Worktree had no `deps/` or `_build/`.** Symlinked the parent repo's `deps/` and `_build/` into the worktree to enable `rtk mix compile` / `mix test`. Both directories are gitignored (untracked in `git status`).
- **Plan referred to `Schema.fetch_spec!/1` and `SiteForm.site_keys/0` returning atoms.** The actual canonical accessor is `Schema.fetch_spec/1 :: {:ok, spec} | :error` (binary key); `SiteForm.site_keys/0` and `SiteForm.State.site_keys/0` return string keys. The new SYSOP-04 regex test uses the actual API (a hardcoded `@site_keys` list of strings + `Schema.fetch_spec/1` `{:ok, spec}` destructuring). The plan's `<action>` block explicitly authorized this adaptation.

## User Setup Required

None — no external service configuration required.

## Threat Flags

No new security-relevant surface introduced. T-29-09 mitigation (operator-copy info-disclosure) is now permanently locked by the SYSOP-04 regex test. T-29-10 (double-submit) is unchanged from Phase 28 D-05's `submit_state` machine. T-29-11 (Esc mid-write) is documented per D-20/D-21 — operators expect field reversion as the visible signal. T-29-12 (`Saved.` row visibility to actor) is unchanged from Phase 28 D-08.

## Self-Check: PASSED

All claimed files exist and contain the documented edits; both task commits are present in `git log`.

```
FOUND: lib/foglet_bbs/config/schema.ex (5 description rewrites)
FOUND: test/foglet_bbs/config/schema_test.exs (5 spec-equality updates + new SYSOP-04 describe block)
FOUND: test/foglet_bbs/tui/screens/sysop/site_form_test.exs (2 render-assertion updates + 2 new Phase 29 describe blocks)
FOUND: e960232 — feat(29-03): rewrite @site_keys descriptions and add SYSOP-04 regex test
FOUND: 24f0971 — test(29-03): lock D-18/D-19/D-20/D-21 invariants in SiteForm regression suite
```

Acceptance criteria verification:

```
PASS: grep "How new accounts are created\." → 1 match (schema.ex:54)
PASS: grep "Who can generate invite codes\." → 1 match (schema.ex:63)
PASS: grep "Whether outbound email is sent\." → 1 match (schema.ex:90)
PASS: grep "Require email verification before login\." → 1 match (schema.ex:99)
PASS: grep "Per-user invite cap (0 = unlimited)\." → 1 match (schema.ex:118)
PASS: 0 lines match `(D-\d+|MAIL-|Phase \d+|INVT-)` on description: rows for the 5 @site_keys
PASS: rtk mix test test/foglet_bbs/config/schema_test.exs → 40 tests, 0 failures
PASS: rtk mix test test/foglet_bbs/tui/screens/sysop/site_form_test.exs → 39 tests, 0 failures
PASS: rtk mix compile --warnings-as-errors → exit 0
PASS: describe "Sysop Site Enter persistence (D-18, D-19)" present at line 618
PASS: describe "Sysop Site Esc reseed (D-20, D-21)" present at line 698
PASS: refute "Discarded" in site_form_test.exs at line 467 (and additional Phase 29 refutes)
PASS: set_submit_state(:saved) at site_form.ex:206
PASS: validate_delivery_verification_pair referenced in site_form.ex (D-20 pre-flight in build_modal_form)
PASS: 0 occurrences of status_message in site_form.ex
```

---
*Phase: 29-sysop-tab-lifecycle-bodies*
*Completed: 2026-04-27*
