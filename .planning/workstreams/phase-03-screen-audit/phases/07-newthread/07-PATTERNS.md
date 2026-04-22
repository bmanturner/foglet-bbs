# Phase 7: NewThread — Pattern Map

**Mapped:** 2026-04-22
**Files analyzed:** 2
**Analogs found:** 2 / 2

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `lib/foglet_bbs/tui/screens/new_thread.ex` | stateful compose screen | key-event driven state transitions | `lib/foglet_bbs/tui/screens/post_composer.ex`, `lib/foglet_bbs/tui/screens/login.ex` (TextInput precedent) | high |
| `test/foglet_bbs/tui/screens/new_thread_test.exs` | screen behavior tests | command/assertion round-trip | existing `new_thread_test.exs` + `login_test.exs` input assertions | high |

## Pattern Assignments

### `lib/foglet_bbs/tui/screens/new_thread.ex`

**Keep:**

- public `init_screen_state/1` contract;
- compose body path (`Compose.render_input`, `Compose.translate_key`, `MultiLineInput.update`);
- source-order warning and clause ordering around Ctrl+S/Ctrl+C interception.

**Migrate:**

- hand-rolled title render/keypress logic to `Foglet.TUI.Widgets.Input.TextInput` with explicit `theme: theme`;
- inline `{80, 24}` fallbacks to module attribute:

```elixir
@default_terminal_size {80, 24}
```

### `test/foglet_bbs/tui/screens/new_thread_test.exs`

Preserve route/compose behavior tests and add title-input migration assertions:

- title input state mutates through TextInput event flow;
- title cap behavior remains enforced;
- submit/cancel/body behavior remains unchanged.

## Guardrails

- No scope drift outside `new_thread.ex` and `new_thread_test.exs`.
- No new shared modules.
- No nested border UI additions; no reserved-region content additions.
