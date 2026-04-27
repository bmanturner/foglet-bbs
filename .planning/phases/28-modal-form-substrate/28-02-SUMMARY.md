---
phase: 28-modal-form-substrate
plan: 02
subsystem: ui
tags: [tui, raxol, modal, form, submit-state, lock, status-row]

# Dependency graph
requires:
  - phase: 28-modal-form-substrate
    plan: 01
    provides: Modal.Form Up/Down focus, :backtab clause, :show_footer opt-in, dispatch_event_to_field/2 helper
  - phase: 25-tui-modal-form
    provides: Modal.Form substrate (init/handle_event/render contract, field types, focus_index)
provides:
  - Modal.Form `submit_state` first-class struct field (default `:idle`) (FORM-05)
  - Lock guard: every event swallowed while `submit_state == :submitting` (FORM-05 D-02)
  - Auto-reset preamble: `:saved` / `{:error, _}` collapse to `:idle` on next non-locked event (FORM-05 D-04)
  - Public `set_submit_state/2` setter accepting `:idle | :saved | {:error, term}`; raises `ArgumentError` on `:submitting` (FORM-05 D-03)
  - Internal `:idle → :submitting` transition on Enter-on-last-field, single `on_submit` invocation (FORM-05 D-05)
  - Status row in `render/2`: `Saving…` / `Saved.` / `Error: <msg>` (FORM-05 D-08)
  - Status row replaces footer when both would render (FORM-05 D-09)
affects:
  - 28-03-honest-esc (cancel-path semantics layer cleanly on top — no overlap)
  - 28-04-siteform-migration (SiteForm can opt into set_submit_state/2 wiring)
  - 29-sysop-tab-lifecycle (Sysop Site lifecycle / Config.put error mapping uses :saved / {:error, _})
  - 30-account-async-persistence (Account ProfileForm/PrefsForm async save + flash builds on lock)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Public/private handle_event split: public entry runs lock guard + auto-reset preamble; private do_handle_event/2 holds the original dispatch clauses in identical order"
    - "Lock-then-preamble ordering: the lock guard short-circuits BEFORE auto-reset, so :submitting never triggers a state mutation"
    - "Reserved-transition setter: the public setter raises on caller-supplied :submitting; the :idle → :submitting edge is internal-only"
    - "Status-row replaces footer convention: when both would render, the status row wins (idle = no status, footer follows :show_footer)"
    - "Theme-slot defensive fallback: status_saved_fg/1 prefers theme.success.fg, falls back to theme.accent.fg if a future theme leaves :success blank"

key-files:
  created: []
  modified:
    - lib/foglet_bbs/tui/widgets/modal/form.ex
    - test/foglet_bbs/tui/widgets/modal/form_test.exs

key-decisions:
  - "Restructured handle_event/2 into a public entry + private do_handle_event/2 to give the lock guard and auto-reset preamble exactly one place to live, rather than duplicating either across every clause."
  - "Used theme.success.fg directly for the :saved status row (the Theme struct already exposes it; see lib/foglet_bbs/tui/theme.ex:59) but kept the planner-suggested status_saved_fg/1 fallback to theme.accent.fg for forward-compatibility with future themes that might leave :success blank."
  - "Unicode ellipsis (U+2026) for 'Saving…' per CONTEXT D-08 — single character, not three ASCII dots."
  - "set_submit_state/2 raises ArgumentError on :submitting per the existing fail-fast convention in this codebase (planner explicitly picked raise over {:error, :reserved})."
  - "Test-side construction of :submitting state for the lock test: forced the form into :submitting via the legitimate Enter-on-last path (one no-op on_submit), then swapped in raising callbacks immediately to catch any leak. Avoids reaching for a private API or constructing the state directly with raising callbacks (which would crash the legitimate Enter)."

requirements-completed: [FORM-05]

# Metrics
duration: ~12min
completed: 2026-04-27
---

# Phase 28 Plan 02: Submit-State Machine Summary

**Modal.Form gains a first-class `submit_state` machine, an input-lock guard, an auto-reset preamble, the public `set_submit_state/2` setter, the in-flight/saved/error status row, and 14 new tests covering FORM-05 in full.**

## Performance

- **Duration:** ~12 min (most of the elapsed time was the cold `mix deps.get` and `mix precommit` Dialyzer warmup; test cycles were sub-second)
- **Started:** 2026-04-27T17:51:45Z
- **Completed:** 2026-04-27T18:03:30Z (approximate)
- **Tasks:** 2 (each TDD RED → GREEN)
- **Files created:** 0
- **Files modified:** 2
- **New test cases added:** 14 (8 in Task 1, 6 in Task 2)
- **Existing tests updated:** 0 (Plan 01 already inverted the Account footer assertions; nothing else needed touching)

## Submit-State Machine

```
                    Enter on last field          set_submit_state(:saved)
                    (internal only)              ┌──────────────────┐
       ┌─────────┐  ──────────────────►   ┌──────┴───┐              │
       │  :idle  │                        │:submitting│              ▼
       └─────────┘                        └──────┬───┘        ┌──────────┐
            ▲                                    │            │ :saved   │
            │                                    │            └──────────┘
            │ next non-locked event              │                  │
            │ (D-04 auto-reset)                  │ set_submit_state │
            │                                    │ ({:error, msg})  │
            │                                    ▼                  ▼
            │                            ┌──────────────┐  ┌──────────────┐
            └────────────────────────────┤{:error, msg}│   │              │
                                         └──────────────┘   └──────────────┘
```

**Invariants:**

1. **Single internal transition into `:submitting`:** Only the Enter-on-last-field clause inside `do_handle_event/2` writes `submit_state: :submitting`. Callers cannot fake this transition — `set_submit_state(form, :submitting)` raises `ArgumentError`.
2. **Total input lock while `:submitting`:** The Clause 0 lock guard (`handle_event(_event, %{submit_state: :submitting} = state)`) returns `{state, nil}` for every event with no exceptions. `field_states`, `focus_index`, and `errors` are all preserved byte-for-byte.
3. **Auto-reset on next non-locked event:** When a form is in `:saved` or `{:error, _}`, the public `handle_event/2` collapses `submit_state` back to `:idle` BEFORE running the rest of the dispatch. This means even consumers that haven't adopted `set_submit_state/2` yet (Plan 03's adoption) keep working — the form returns to editable on the next keystroke.
4. **Lock-before-preamble ordering:** The lock guard short-circuits at the public entry, so the auto-reset preamble never fires from a `:submitting` event. This ordering is deliberate — without it, a stray `set_submit_state(:saved)` followed by a key press could race with an in-flight save.

## Public Setter Contract

`Modal.Form.set_submit_state/2`:

| Argument             | Behavior                                                                          |
| -------------------- | --------------------------------------------------------------------------------- |
| `:idle`              | Sets `submit_state: :idle`. Useful for resetting the form externally.             |
| `:saved`             | Sets `submit_state: :saved`. Status row shows `Saved.` until next event.          |
| `{:error, term()}`   | Sets `submit_state: {:error, term}`. Status row shows `Error: <term>`.            |
| `:submitting`        | **Raises `ArgumentError`** — reserved for the internal Enter-on-last clause.      |

Consuming screens (Account ProfileForm/PrefsForm in Plan 03/Phase 30; Sysop SiteForm in Plan 04/Phase 29) drive the transition out of `:submitting` after async work completes:

```elixir
case Foglet.Config.put(...) do
  :ok                  -> Modal.Form.set_submit_state(form, :saved)
  {:error, %Ecto.Changeset{} = cs} ->
    msg = format_error(cs)
    Modal.Form.set_submit_state(form, {:error, msg})
end
```

## Render/2 Status Row

| `submit_state`        | Row text          | Color (theme slot)                         | Footer rendered? |
| --------------------- | ----------------- | ------------------------------------------ | ---------------- |
| `:idle`               | (none)            | —                                          | per `:show_footer` (D-06) |
| `:submitting`         | `Saving…`         | `theme.dim.fg`                             | NO (D-09)        |
| `:saved`              | `Saved.`          | `theme.success.fg` (fallback `theme.accent.fg`) | NO (D-09)   |
| `{:error, msg}`       | `Error: <msg>`    | `theme.error.fg`                           | NO (D-09)        |

The Unicode ellipsis (U+2026, `…`) is intentional per CONTEXT D-08 — one column wide, no string-length surprises versus three ASCII dots. The `theme.success.fg` slot is currently populated for all built-in themes (gray, green, amber, blue — see `lib/foglet_bbs/tui/theme.ex:108–142`); the `theme.accent.fg` fallback inside `status_saved_fg/1` is forward-compatibility insurance only.

## Task Commits

Each task was committed via TDD RED → GREEN cycles:

1. **Task 1 RED — failing FORM-05 submit-state tests (8)** — `a77708f` (test)
2. **Task 1 GREEN — submit_state field, lock guard, auto-reset, set_submit_state/2** — `6b14efd` (feat)
3. **Task 2 RED — failing render/2 status-row tests (6)** — `844accc` (test)
4. **Task 2 GREEN — render_status_row/2 + footer-replacement cond** — `f56c33f` (feat)

## Files Modified

- `lib/foglet_bbs/tui/widgets/modal/form.ex` — Added `submit_state` to defstruct + typespec, `@type submit_state`, lock-guard public clause, auto-reset preamble, restructured private `do_handle_event/2` clauses (identical bodies, identical order), `submit_state: :submitting` transition in the Enter-on-last branch, public `set_submit_state/2` (3 clauses), `render_status_row/2` (4 clauses), `status_saved_fg/1` helper, `cond` in `render/2` so status row replaces footer.
- `test/foglet_bbs/tui/widgets/modal/form_test.exs` — Appended two new `describe` blocks: `"FORM-05 submit-state machine + lock guard (Phase 28 D-01..D-05)"` (8 tests) and `"FORM-05 render/2 status row (Phase 28 D-08, D-09)"` (6 tests). Added private `single_field_form/1`, `two_field_form/1`, `status_form/1` helpers inside the describe blocks for FORM-05.

## Decisions Made

- **Public/private handle_event split:** The plan suggested two clean options for the auto-reset preamble: either inline a `state |> maybe_auto_reset_submit_state() |> then_dispatch` pipe at the head of every clause, or hoist dispatch behind a private helper. I chose the helper split because it gives the lock guard exactly one place to live (Clause 0 of the public function) and the auto-reset preamble exactly one place to live (the second clause of the public function), with `do_handle_event/2` holding the unchanged original dispatch order. This is what the plan recommended; it's also what `dialyzer` and code review will appreciate later.
- **Theme.success.fg vs accent fallback:** The plan flagged uncertainty about whether `theme.success.fg` exists. I checked `lib/foglet_bbs/tui/theme.ex` — it does, with valid fg colors in all four built-in palettes (gray, green, amber, blue). I still kept the `status_saved_fg/1` fallback to `theme.accent.fg` because it's free insurance and matches the planner's intent (keeping Modal.Form theme-agnostic).
- **Test 4 lock construction technique:** Constructing a `:submitting` state for the "every event swallowed" test is constrained: `set_submit_state/2` rejects `:submitting`, and the public Enter-on-last path requires a callable `on_submit`. The cleanest approach was to swap in a no-op `on_submit` for the single legitimate Enter, capture the resulting locked state, then immediately overwrite the callbacks with `flunk`-on-call versions before the lock test runs. This keeps the test honest (the locked state is reached via the real internal transition) without adding test-only public API on Modal.Form.
- **Pin to `submit_state` only on the public Enter clause:** I considered also pinning the Enter clause to `state.submit_state == :idle` inside the `if focus_index == last_idx` block. I left it implicit: by the time `do_handle_event/2` runs, the lock guard has rejected `:submitting` and the auto-reset preamble has collapsed `:saved` and `{:error, _}` to `:idle`. The current code is correct as-is and the `cond` triple-arm in the planner's spec was simplified to an `if/else` because the third arm is unreachable post-preamble.
- **No new test helper file:** The 14 new tests live alongside the existing 44 in `form_test.exs`. The new helpers (`single_field_form/1`, `two_field_form/1`, `status_form/1`) are private and scoped per describe block. No need to extract a shared helper module.

## Deviations from Plan

None functional. Three planner-anticipated micro-choices, documented above:

1. **`render/2` cond simplified:** The planner suggested a triple-arm `cond` for the Enter clause; the implementation uses `if/else` because the third arm is unreachable post-preamble. Same observable behavior, simpler code.
2. **`do_handle_event` argument order swap:** The planner's example showed `do_handle_event(state, event)` with state-first; the existing private clauses for `dispatch_event_to_field` use `(event, state)`. I went with `do_handle_event(state, event)` (state-first, matching the planner's convention) to keep pattern matching on the struct literal at the head, which is the dominant idiom in the rest of the file.
3. **`status_saved_fg/1` kept as defensive fallback:** Theme already exposes `success.fg`, so the fallback is technically unreachable for built-in themes. Kept it because it's free, theme-agnostic, and signals intent.

**No auto-fixes (Rule 1/2/3) were required:** All existing tests passed without modification. The plan correctly anticipated that ProfileForm/PrefsForm/SiteForm would continue working because:
  - their forms remain in `:idle` until they adopt `set_submit_state/2` in Plan 03,
  - the auto-reset preamble means even without that adoption, a stray `set_submit_state(:saved)` would self-clear on the next keystroke,
  - the synchronous `on_submit` invocation pattern (`SubmitStash` popped by the screen handler immediately after `:submitted`) is preserved byte-for-byte.

## TDD Gate Compliance

Both tasks followed strict RED → GREEN cycles, each with separate commits:

- **Task 1:** `a77708f` (test, RED — 8 of 8 new tests fail) → `6b14efd` (feat, GREEN — all 8 pass; 52 of 52 form tests green; 1854 of 1854 full-suite pass)
- **Task 2:** `844accc` (test, RED — 4 of 6 substantive new tests fail; 2 :idle pass-throughs already pass because no status row exists for :idle) → `f56c33f` (feat, GREEN — all 6 pass; 58 of 58 form tests green; 1860 of 1860 full-suite pass)

## Issues Encountered

- **Worktree base mismatch on startup:** The worktree was initially based on `3226ef9e` (older `main`) instead of the expected `e4e65f4` (Phase 28 Plan 01 merged). Hard-reset to the correct base per the `<worktree_branch_check>` protocol; no work was lost (worktree was empty).
- **Mix deps missing in worktree:** Required `rtk mix deps.get` before tests could run. ~30 s.

## Verification

- `rtk mix test test/foglet_bbs/tui/widgets/modal/form_test.exs` → 58 tests, 0 failures (covers FORM-01..FORM-05 in full).
- `rtk mix test` (full suite) → 1 property, 1860 tests, 0 failures.
- `rtk mix precommit` → passed (compile with warnings as errors, formatter, Credo, Sobelow, Dialyzer all clean; ~2 min cold).
- `grep -c "submit_state: :idle" lib/foglet_bbs/tui/widgets/modal/form.ex` → 3 (defstruct default + 2 auto-reset clauses).
- `grep -c "submit_state: :submitting" lib/foglet_bbs/tui/widgets/modal/form.ex` → 2 (lock clause head + Enter transition).
- `grep -c "def set_submit_state" lib/foglet_bbs/tui/widgets/modal/form.ex` → 3 (raise clause + idle/saved clause + error tuple clause).
- `grep -c "ArgumentError" lib/foglet_bbs/tui/widgets/modal/form.ex` → 2 (raise + moduledoc reference).
- `grep -c "render_status_row" lib/foglet_bbs/tui/widgets/modal/form.ex` → 5 (1 call site + 4 clauses).

## Next Phase Readiness

- **Plan 03 (honest Esc):** Cancel-path semantics and the existing Esc clause are unchanged; the lock guard short-circuits Esc while `:submitting`, which is the desired behavior per CONTEXT (no cancel mid-save). Plan 03 can layer the no-flash Esc behavior on top without conflict.
- **Plan 04 (SiteForm migration):** SiteForm's "re-init on change" pattern continues to work — re-init seeds `submit_state: :idle`, so a fresh form is always editable. SiteForm can adopt `set_submit_state/2` in its async save handler in Plan 04 without further substrate changes.
- **Phase 29 (Sysop Site lifecycle):** The `set_submit_state(form, {:error, msg})` API is the contract Phase 29's `Foglet.Config.put` error-mapping needs; ready to consume.
- **Phase 30 (Account async persistence + flash):** ProfileForm/PrefsForm can adopt `set_submit_state(form, :saved)` after the async-write handler returns `:ok`, getting the flash-row "Saved." for free; on `{:error, _}`, the form unlocks on the next keystroke (D-04) without needing screen-side reset logic.

## Self-Check: PASSED

**Files exist:**
- `lib/foglet_bbs/tui/widgets/modal/form.ex` — FOUND (modified)
- `test/foglet_bbs/tui/widgets/modal/form_test.exs` — FOUND (modified)

**Commits exist:**
- `a77708f` — FOUND (test RED Task 1)
- `6b14efd` — FOUND (feat GREEN Task 1)
- `844accc` — FOUND (test RED Task 2)
- `f56c33f` — FOUND (feat GREEN Task 2)

---
*Phase: 28-modal-form-substrate*
*Completed: 2026-04-27*
