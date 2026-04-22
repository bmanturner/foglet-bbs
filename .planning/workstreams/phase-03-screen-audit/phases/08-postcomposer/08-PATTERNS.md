# Phase 8: PostComposer — Pattern Map

**Mapped:** 2026-04-22
**Files analyzed:** 2
**Analogs found:** 2 / 2

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `lib/foglet_bbs/tui/screens/post_composer.ex` | stateful compose screen | key-event input + submit pipeline | `lib/foglet_bbs/tui/screens/new_thread.ex` (source-order note), `lib/foglet_bbs/tui/screens/login.ex` (with-chain discipline) | high |
| `test/foglet_bbs/tui/screens/post_composer_test.exs` | screen behavior tests | command/assertion round-trip | existing `post_composer_test.exs` submit + cancel tests | high |

## Pattern Assignments

### `lib/foglet_bbs/tui/screens/post_composer.ex`

**Keep:**

- `Compose.translate_key/1` + `MultiLineInput.update/2` forwarding path;
- modal payload/message shapes already used by submit flow;
- success cleanup contract (`current_screen`, `composer_draft`, `screen_state` delete + load command).

**Migrate:**

- inline `{80, 24}` fallbacks to:

```elixir
@default_terminal_size {80, 24}
```

- nested submit `case` in `submit_reply/4` to a branch-equivalent `with` chain.
- add source-order warning comment above `handle_key/2` clauses.

### `test/foglet_bbs/tui/screens/post_composer_test.exs`

Preserve and tighten existing assertions for:

- Ctrl+S success and error branches;
- origin-aware cancel behavior;
- command dispatch shape (`{:load_posts, thread_id, jump_last: true}`) and screen cleanup;
- no behavior drift after submit `with` rewrite.

## Guardrails

- Scope fence: only `post_composer.ex` and `post_composer_test.exs`.
- No widget migration for body composition (`COMPOSER-04`).
- No new rows or decorative elements in protected layout regions.
