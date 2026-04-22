# Phase 7: NewThread — Research

**Researched:** 2026-04-22
**Domain:** Elixir TUI screen audit — `new_thread.ex` title-input migration with compose-path invariants
**Confidence:** HIGH (grounded in direct reads of `new_thread.ex`, `new_thread_test.exs`, Phase 7 context, roadmap, and requirements)

## Summary

Phase 7 is a constrained migration: move only the title line in `NewThread` from hand-rolled text/cursor handling to `Input.TextInput`, while keeping body compose behavior (`Compose` + `MultiLineInput`) unchanged.

Current screen state and handlers are already close to the target. The major risk is source-order-sensitive key handling in compose mode. The `handle_compose_key/3` ordering that intercepts Ctrl+S/Ctrl+C before body fallthrough is explicitly load-bearing and must stay intact.

The planning recommendation is one execute plan with two tasks:

1. update `lib/foglet_bbs/tui/screens/new_thread.ex` for title `Input.TextInput`, `@default_terminal_size`, and section-order/rubric compliance;
2. update `test/foglet_bbs/tui/screens/new_thread_test.exs` to lock title-input migration behavior and no-regression compose semantics.

## Current Code Read

### `lib/foglet_bbs/tui/screens/new_thread.ex`

- Already uses `Theme.from_state/1` and `Screens.Domain.get/2`.
- Still contains two inline `{80, 24}` fallbacks (`render_body_section/3`, board Enter path).
- Title input is hand-rolled in render (`Title: #{ss.title_input}█`) and handlers (`:backspace` + `:char` clauses on `title_input`).
- Body path is already delegated to `Compose.translate_key/1` + `MultiLineInput.update/2` with load-bearing ordering notes.
- Has `init_screen_state/1` and screen_state plumbing (`screen_state/1`, `put_ss/2`).

### `test/foglet_bbs/tui/screens/new_thread_test.exs`

- Covers board-step navigation, compose-step focus/mode switching, cancel/escape, title typing, and submit paths.
- Current tests lock user behavior, but do not yet assert `Input.TextInput`-specific state ownership/flow for title edits.

## Required Invariants

- `NEWTHREAD-01`: title line migrates to `Input.TextInput` (Phase 1 precedent).
- `NEWTHREAD-02`: body path remains `Compose` + `MultiLineInput` (no behavior refactor).
- `NEWTHREAD-03`: remove inline `{80,24}` and route via `@default_terminal_size`.
- `NEWTHREAD-04`: preserve the source-order warning comment and semantics in compose key handling.
- `NEWTHREAD-05`: pass inherited `AUDIT-05..22` gates and `mix precommit`.

## Validation Architecture

### Automated checks

- `mix test test/foglet_bbs/tui/screens/new_thread_test.exs`
- `mix precommit`
- `gsd-sdk query verify.plan-structure .planning/workstreams/phase-03-screen-audit/phases/07-newthread/07-01-PLAN.md`
- Grep gates on screen file:
  - `rg -n '\\{80, 24\\}' lib/foglet_bbs/tui/screens/new_thread.ex`
  - `rg -n 'Theme\\.from_state\\(state\\)' lib/foglet_bbs/tui/screens/new_thread.ex`
  - `rg -n 'get_in\\(ctx, \\[:domain' lib/foglet_bbs/tui/screens/new_thread.ex`
  - `rg -n 'source order matters for handle_key/2 clauses — do not reorder' lib/foglet_bbs/tui/screens/new_thread.ex`

### Regression focus

- Ctrl+S submit path unchanged on compose step.
- Ctrl+C/Esc origin-aware cancel unchanged.
- Tab behavior unchanged (`:title -> :body`; body tab toggles edit/preview).
- Body input still managed by `MultiLineInput` with Compose translation.

## Risks and Landmines

- Reordering compose `handle_key/2` clauses can silently break submit/cancel interception.
- Pulling title and body input under one shared handler risks behavior drift; keep title migration scoped.
- Introducing extra visual rows (banners/hints/panels) violates sparseness and reserved region rules.

## Recommended Plan Shape

One plan (`07-01-PLAN.md`) with two tasks:

- Task 1: screen migration and rubric compliance in `new_thread.ex`.
- Task 2: tests + quality gates in `new_thread_test.exs`.

This keeps file scope bounded, preserves audit restraint, and fully covers `NEWTHREAD-01..05`.
