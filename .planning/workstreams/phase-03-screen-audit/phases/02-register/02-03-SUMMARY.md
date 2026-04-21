---
phase: 02-register
plan: 03
subsystem: tui-screens
tags: [audit, rubric-sweep, register, dialyzer, precommit]
dependency_graph:
  requires: ["02-02"]
  provides: ["REGISTER-05 rubric gate — AUDIT-05..22 all pass on register.ex"]
  affects:
    - lib/foglet_bbs/tui/screens/register.ex
    - test/foglet_bbs/tui/screens/register_test.exs
tech_stack:
  added: []
  patterns:
    - "AUDIT-05..22 rubric sweep (grep gates, behavioral invariants, widget contract, mix precommit)"
    - "Dialyzer extra_range fix — remove :no_match from handle_key/2 spec when all clauses return {:update,...}"
key_files:
  created:
    - .planning/workstreams/phase-03-screen-audit/phases/02-register/02-03-SUMMARY.md
  modified:
    - lib/foglet_bbs/tui/screens/register.ex
    - test/foglet_bbs/tui/screens/register_test.exs
decisions:
  - "Removed :no_match from @spec handle_key/2 — register.ex has a catch-all clause that delegates to handle_invite_key/handle_combined_key, both of which always return {:update,...}; spec was overly broad and triggered Dialyzer extra_range"
  - "AUDIT-16 LoC increase (448 vs 294) accepted — documented deviation from 02-02-SUMMARY.md; four TextInput fields + confirm validation + AUDIT-18 canonical sections justify the increase"
  - "3 pre-existing LayoutSmokeTest failures (login form old form: shape) are out of scope — documented in 02-02-SUMMARY.md as deferred"
metrics:
  duration: "12m"
  completed: "2026-04-21"
  tasks_completed: 1
  files_changed: 2
---

# Phase 02 Plan 03: Register AUDIT Rubric Sweep Summary

AUDIT-05..22 grep gates all pass on the post-plan-02 `register.ex`; Dialyzer `extra_range` on `handle_key/2` spec fixed; `mix precommit` exits 0; register test suite green (29 tests).

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | AUDIT rubric sweep — all grep gates pass, fix Dialyzer extra_range, mix precommit green | a25175b | register.ex, register_test.exs |

## Task 2 Status

**PENDING HUMAN VERIFICATION** — SSH smoke test (6 scenarios). See Checkpoint Details section.

## AUDIT-05..22 Sweep Results

### AUDIT-05: Grep Gates (all 9 pass)

| Gate | Pattern | Result |
|------|---------|--------|
| 1 | Named color atoms (`:red`, `:green`, etc.) | PASS (0 matches) |
| 2 | Hex literals `"#[0-9a-fA-F]{6}"` | PASS (0 matches) |
| 3 | Raw ANSI escapes `\e[` / `\x1b` | PASS (0 matches) |
| 4 | Theme struct mutation `%{.*theme.*\|` | PASS (0 matches) |
| 5 | `box style.*border` nested border | PASS (0 matches) |
| 6 | `IO.(write\|puts\|inspect)` direct writes | PASS (0 matches) |
| 7 | `{80, 24}` inlined terminal size | PASS (0 matches — N/A for register) |
| 8 | Inlined theme extraction pattern | PASS (0 matches — uses Theme.from_state/1) |
| 9 | Inlined domain lookup `get_in(ctx, [:domain` | PASS (0 matches — N/A for register) |

### AUDIT-06: Behavioral Invariants

- `handle_key/2` clause order: `:escape` head (line 77) before catch-all (line 81) — PASS
- `render/*` purity: no `%{state | ...}` writes inside any `defp render_*` — PASS
- `handle_key/2` never inspects `state.modal` — PASS (modal dispatch in app.ex)
- `%{state | modal: m}` paired with wizard clear in success paths — PASS

### AUDIT-07: Widget Contract

- `TextInput.render/2` called with `theme: theme` at both call sites (lines 233, 258) — PASS
- All 5 TextInput structs hoisted to `screen_state[:register]` per D-14 — PASS
- No stateless widgets in screen_state — PASS

### AUDIT-08: Chrome Contract

- `ScreenFrame.render/4` wraps all screen content (line 71) — PASS
- KeyBar hints provided for both steps via `keys_for/1` — PASS

### AUDIT-09: `with`-chain

- `submit/2` open/invite_only head uses `with` chain (line 355) covering all 4 branches — PASS

### AUDIT-10..12: N/A

- AUDIT-10: All ops synchronous; no spinner needed — PASS trivially
- AUDIT-11: No loading/empty-state text in register.ex — PASS trivially
- AUDIT-12: No `load_*` or `flush_*` public functions — PASS trivially

### AUDIT-13: Scope Fence

- Phase 2 files: register.ex, register_test.exs, app.ex (AUDIT-13(b) exception), login.ex (AUDIT-13(b) exception), layout_smoke_test.exs (fixture migration) — PASS

### AUDIT-14: No New Shared Modules

- All new helpers are file-scoped private functions in register.ex — PASS

### AUDIT-15: CI Gate

- `mix precommit` exits 0 — PASS
- `credo:disable-for-next-line` preserved verbatim at line 411 (REGISTER-04) — PASS (1 match, expected 1)
- No new Dialyzer/Credo/Sobelow suppressions added — PASS

### AUDIT-16: Size Delta

- Current: 448 LoC (was 294 pre-Phase-2)
- Increase is an accepted deviation (documented in 02-02-SUMMARY.md): 4 simultaneous TextInput fields + confirm_password validation + with-chain + AUDIT-18 canonical 10-section structure replace old 294-LoC sequential one-field-per-step wizard
- PASS with documented rationale

### AUDIT-17: Protected Layout Regions

- `:invite_code` step: 1 input row + optional error row — no content below error line — PASS
- `:combined` step: 4 field rows + optional error row — no content below error line — PASS

### AUDIT-18: Canonical Section Order

```
§2 Module attributes (30)
§3 init_screen_state/1 PUBLIC (39)
§4 render/1 PUBLIC (57)
§5 handle_key/2 PUBLIC (77)
§6 handle_wizard_event/2 PUBLIC domain hook (102)
§7 Private key handlers (136)
§8 Private render helpers (216)
§9 Private state plumbing (282)
§10 Private domain plumbing (317)
```

PASS — all 10 sections in canonical order. `handle_wizard_event/2` correctly placed at §6 (public domain-hook dispatched from `app.ex:352`).

### AUDIT-19: `init_screen_state/1`

- Public function with `@spec init_screen_state(keyword()) :: map()` at line 38-39 — PASS

### AUDIT-20..22: Anti-Affordances

- AUDIT-20: 0 `box style.*border` matches — PASS
- AUDIT-21: 0 prohibited widget usages (Display.Table, Input.Tabs, etc.) — PASS
- AUDIT-22: No ASCII banners, decorative dividers, or panels added — PASS

## Verification Results

- `mix compile --warnings-as-errors`: exit 0
- `mix test test/foglet_bbs/tui/screens/register_test.exs`: 29 tests, 0 failures
- `mix precommit`: exit 0 (69 Dialyzer errors, all 69 skipped, 0 unskipped, 0 unnecessary skips)
- Full suite: 812 tests, 3 failures (all 3 pre-existing LayoutSmokeTest login form failures — deferred, out of scope)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Dialyzer extra_range on handle_key/2 spec**
- **Found during:** Task 1 (mix precommit run)
- **Issue:** `@spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match` — the `:no_match` type was never actually returned. `register.ex` has a catch-all clause that delegates to `handle_invite_key/2` or `handle_combined_key/2`, both of which always return `{:update, state, commands}`. Dialyzer reported `extra_range` at line 76.
- **Fix:** Removed `:no_match` from spec: `@spec handle_key(map(), map()) :: {:update, map(), list()}`
- **Files modified:** `lib/foglet_bbs/tui/screens/register.ex`
- **Commit:** a25175b

**2. [Rule 1 - Formatting] mix format normalization on register.ex and register_test.exs**
- **Found during:** Task 1 pre-commit check
- **Issue:** Minor formatting whitespace differences (line break in `keys_for(:combined)` clause; whitespace in test helper call)
- **Fix:** Applied `mix format` (already in the working tree diff from prior work)
- **Files modified:** register.ex, register_test.exs
- **Commit:** a25175b (inline)

### Out-of-Scope Discoveries

3 pre-existing `LayoutSmokeTest` failures use old `form: %{...}` nested shape from before Phase 1's TextInput migration (noted in 02-02-SUMMARY.md). Not caused by this plan.

## Known Stubs

None — all fields are eagerly wired; submit pipeline calls real Accounts functions.

## Threat Flags

No new security surface introduced. This is a spec + formatting-only fix on top of the Phase 2 structural refactor.

## Checkpoint: Task 2 Pending (human-verify)

Task 2 requires a developer SSH smoke test of the full registration flow via the running BBS server. See the Checkpoint Details in the orchestrator message for the 6 verification scenarios.

## Self-Check: PASSED

Files verified:
- `lib/foglet_bbs/tui/screens/register.ex`: FOUND
- `test/foglet_bbs/tui/screens/register_test.exs`: FOUND
- `.planning/workstreams/phase-03-screen-audit/phases/02-register/02-03-SUMMARY.md`: FOUND

Commits verified:
- a25175b: FOUND (fix(02-03): AUDIT rubric sweep — fix Dialyzer extra_range on handle_key/2 spec)
