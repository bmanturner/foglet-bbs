---
phase: 02-register
plan: 01
subsystem: tui-screens
tags: [tdd, wave-0, register, screen_state, TextInput, test-rewrite]
wave: 0

dependency_graph:
  requires:
    - 01-login/01-01-PLAN (Phase 1 login test patterns as fixture template)
  provides:
    - register_test.exs rewritten against post-Phase-2 API (failing by design)
    - login_test.exs purged of register_wizard assertion
  affects:
    - 02-02-PLAN (Wave 1 makes these tests green by implementing the new register.ex)

tech_stack:
  added: []
  patterns:
    - ExUnit.Case async: true (pure TUI unit tests — no DataCase needed)
    - base_state/1 + combined_state/3 + invite_state/1 fixture helpers mirroring login_test.exs
    - text_input_at_end/1 Phase 1 verbatim pattern for cursor positioning
    - Access.key(:raxol_state) for reaching into TextInput struct values in assertions
    - get_in/2 with atom key path for screen_state[:register] access

key_files:
  created: []
  modified:
    - test/foglet_bbs/tui/screens/register_test.exs
    - test/foglet_bbs/tui/screens/login_test.exs

decisions:
  - "Used ExUnit.Case async: true (not FogletBbs.DataCase) — Wave 0 tests are pure TUI state; no DB required"
  - "Kept :register_wizard command tuple references in tests — {register_wizard, {:submit_step, ...}} is the App dispatch command (new API), not the old struct field"
  - "Acceptance criteria pattern 'state.register_wizard|register_wizard:' correctly excludes the :register_wizard command atom"

metrics:
  duration: "~20 minutes"
  completed: "2026-04-21"
  tasks_completed: 2
  tasks_total: 2
  files_modified: 2
---

# Phase 02 Plan 01: Register Wave 0 Test Rewrite Summary

Wave 0 test foundation for the Phase 2 register screen refactor — rewrites `register_test.exs` against the post-Phase-2 API and patches `login_test.exs` to drop a stale assertion. Tests fail against current `register.ex` by design; Wave 1 (02-02-PLAN) makes them green.

## What Was Built

### Task 1: Full rewrite of register_test.exs (commit 56ed42c)

Replaced all 293 lines of the old test file (which tested `state.register_wizard` and the sequential step wizard) with a new 294-line file structured around the post-Phase-2 `screen_state[:register]` flat-map shape.

**New fixture helpers:**
- `text_input_at_end/1` — positions cursor at end of TextInput value (Phase 1 verbatim)
- `base_state/1` — empty `screen_state: %{}` state; register.ex self-initializes on first access
- `combined_state/3` — pre-seeds `screen_state[:register]` with four TextInput structs for :combined step tests
- `invite_state/1` — pre-seeds `screen_state[:register]` for :invite_code step tests

**Describe blocks (all required blocks present):**
1. `init_screen_state/1 (AUDIT-19)` — 2 tests (mode stub, opts passthrough)
2. `render/1` — 2 tests (open mode, invite_only mode)
3. `handle_key/2 — :escape` — 2 tests (combined step, invite_code step)
4. `handle_key/2 — :tab cycling on :combined step (D-02)` — 4 tests (handle→email→password→confirm→wrap)
5. `handle_key/2 — :enter on :combined step (D-02, D-03)` — 4 tests (advance + matching-password submit)
6. `handle_key/2 — :enter on :confirm_password with mismatched passwords (D-03, Pitfall 3)` — 1 test
7. `handle_key/2 — character input delegation (D-06)` — 4 tests (char + backspace per field)
8. `handle_key/2 — character input on :invite_code step` — 2 tests (char + enter emits command)
9. `handle_wizard_event/2 — {:cancel}` — 1 test
10. `handle_wizard_event/2 — {:submit_step, :invite_code, value}` — 3 tests (valid, too-short, empty)
11. `handle_wizard_event/2 — {:submit_step, :combined, _}` — 1 test (no-op passthrough)
12. `mode selection (D-04, D-06)` — 3 tests (open self-init, invite_only self-init, sysop_approved self-init)

### Task 2: Patch login_test.exs (commit f8769bf)

Removed `assert new_state.register_wizard.mode == "open"` from the `'R' transitions to :register` test. Replaced with a comment explaining that post-Phase-2 the screen transition is the only thing `login.ex:maybe_register/1` guarantees; `register.ex` self-initializes wizard state on first access (D-06).

Login test suite: 30 tests, 0 failures (verified).

## Verification Results

| Check | Result |
|-------|--------|
| `state.register_wizard\|register_wizard:` refs in register_test.exs | 0 |
| `screen_state: %{register:` refs in register_test.exs | 25 |
| `init_screen_state/1 (AUDIT-19)` describe present | 1 |
| `handle_wizard_event/2 — {:cancel}` describe present | 1 |
| `handle_wizard_event/2 — {:submit_step, :invite_code, value}` describe present | 1 |
| `handle_key/2 — :tab cycling on :combined step` describe present | 1 |
| `handle_key/2 — :enter on :confirm_password with mismatched passwords` describe present | 1 |
| `"Passwords do not match."` in register_test.exs | 2 |
| `TextInput.init(mask_char: "*")` seeding | 2 |
| `Map.from_struct()` in fixture helpers | 3 |
| `mix compile --warnings-as-errors` exit code | 0 |
| `register_wizard` refs in login_test.exs | 0 |
| `assert new_state.current_screen == :register` preserved | 1 |
| `'R' transitions to :register` test name preserved | 1 |
| Login test suite | 30/30 pass |
| Register test suite | Fails by design (Wave 0 state) |

## Deviations from Plan

None — plan executed exactly as written.

The two occurrences of `register_wizard` in register_test.exs (lines 288, 294) are `:register_wizard` as an App dispatch command atom `{:register_wizard, {:submit_step, :invite_code, "ABC123"}}` — this is the correct new API (the command emitted to `app.ex` for round-trip processing per D-08 / Pitfall 4), not the old struct field. The acceptance criteria pattern `state\.register_wizard\|register_wizard:` correctly excludes these.

## Wave 0 State

The register test suite is expected to fail against current `register.ex` — this is by design. The tests describe the target API that Wave 1 (02-02-PLAN) will implement:

- `Register.init_screen_state/1` — does not yet exist
- `Register.handle_key/2` routing by `screen_state[:register]` — not yet migrated
- `Register.handle_wizard_event/2` reading/writing `screen_state[:register]` — not yet migrated

## Known Stubs

None — this plan is test-only scope with no production code stubs.

## Threat Flags

None — Wave 0 is test-only scope with no network endpoints, auth paths, or DB changes.

## Self-Check

**Created files:**
- N/A (test rewrites only)

**Modified files exist:**
- `/Users/brendan.turner/Dev/personal/foglet_bbs/.claude/worktrees/agent-a01f9082/test/foglet_bbs/tui/screens/register_test.exs` — FOUND
- `/Users/brendan.turner/Dev/personal/foglet_bbs/.claude/worktrees/agent-a01f9082/test/foglet_bbs/tui/screens/login_test.exs` — FOUND

**Commits exist:**
- `56ed42c` test(02-01): rewrite register_test.exs against post-Phase-2 API — FOUND
- `f8769bf` test(02-01): patch login_test.exs to drop stale register_wizard assertion — FOUND

## Self-Check: PASSED
