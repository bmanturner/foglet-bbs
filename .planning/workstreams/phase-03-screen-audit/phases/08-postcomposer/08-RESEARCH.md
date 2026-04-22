# Phase 8: PostComposer — Research

**Researched:** 2026-04-22
**Domain:** Elixir TUI screen audit — `post_composer.ex` submit-path `with` refactor + source-order guard note
**Confidence:** HIGH (grounded in direct reads of `post_composer.ex`, `post_composer_test.exs`, Phase 8 context, roadmap, and requirements)

## Summary

Phase 8 is a constrained audit pass over `PostComposer`:

1. add `@default_terminal_size {80, 24}` and remove inline terminal fallback literals;
2. replace the nested submit `case` chain in `submit_reply/4` with a `with` chain while preserving all modal-error branches;
3. add the missing source-order warning comment above `handle_key/2` clauses (`:tab`, `Ctrl+S`, `Ctrl+C`, fallback);
4. keep `Compose` + `MultiLineInput` behavior unchanged.

The strongest risk is behavioral drift in submit/cancel flow. The plan should be a single execute plan with two tasks: one production-file refactor and one test/gate task.

## Current Code Read

### `lib/foglet_bbs/tui/screens/post_composer.ex`

- Uses `Theme.from_state/1` and `Domain.get/2` already.
- Still has inline terminal-size fallbacks (`state.terminal_size || {80, 24}` in preview render and state bootstrap).
- `handle_key/2` has source-order-sensitive clauses but no guard comment.
- Submit path currently is:
  - `submit/1` pre-checks (`empty`, `too long`) and modal branches.
  - `do_submit/3` enforces logged-in user and modal branch.
  - `submit_reply/4` dispatches to posts module with nested `case {:ok, _} | {:error, _}`.

### `test/foglet_bbs/tui/screens/post_composer_test.exs`

- Strong coverage already exists for mode toggles, input forwarding, max-length behavior, submit success/error branches, and origin-aware cancel.
- Tests assert current modal and navigation semantics; these are the lock points for the `with` rewrite.

## Required Invariants

- `COMPOSER-01`: terminal fallback literals move to `@default_terminal_size`; helper routing stays on `Theme.from_state/1` + `Domain.get/2`.
- `COMPOSER-02`: publish path is rewritten as `with` while preserving exact happy/error branches and modal payloads.
- `COMPOSER-03`: source-order warning comment is added above the `handle_key/2` clause block.
- `COMPOSER-04`: compose body remains `Compose` + `MultiLineInput`.
- `COMPOSER-05`: inherited `AUDIT-05..22` and `mix precommit` gates pass.

## Validation Architecture

### Automated checks

- `mix test test/foglet_bbs/tui/screens/post_composer_test.exs`
- `mix precommit`
- `gsd-sdk query verify.plan-structure .planning/workstreams/phase-03-screen-audit/phases/08-postcomposer/08-01-PLAN.md`
- Grep gates on screen file:
  - `rg -n '@default_terminal_size \\{80, 24\\}' lib/foglet_bbs/tui/screens/post_composer.ex`
  - `rg -n '\\{80, 24\\}' lib/foglet_bbs/tui/screens/post_composer.ex`
  - `rg -n 'source order matters for handle_key/2 clauses — do not reorder' lib/foglet_bbs/tui/screens/post_composer.ex`
  - `rg -n 'with .* <- .*create_reply|create_reply\\(' lib/foglet_bbs/tui/screens/post_composer.ex`

### Regression focus

- Modal messages for empty body, over-limit body, not logged-in, and create failure remain unchanged.
- Success still clears `:post_composer`, sets `current_screen: :post_reader`, and dispatches `{:load_posts, thread.id, jump_last: true}`.
- Compose key forwarding remains unchanged after the source-order comment insertion.

## Risks and Landmines

- Reordering or over-broad matching in `handle_key/2` can break Ctrl+S/Ctrl+C interception.
- Over-refactoring `submit/1` + `do_submit/3` alongside `submit_reply/4` can change branch behavior; keep scope minimal.
- Any extra rows below the char counter violates reserved-region constraints (`AUDIT-17`).

## Recommended Plan Shape

One plan (`08-01-PLAN.md`) with two tasks:

- Task 1: `post_composer.ex` refactor (`with` rewrite + source-order note + terminal-size attribute).
- Task 2: `post_composer_test.exs` regression hardening and full quality gates.
