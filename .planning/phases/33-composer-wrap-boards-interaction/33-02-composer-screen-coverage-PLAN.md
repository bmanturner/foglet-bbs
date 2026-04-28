---
phase: 33-composer-wrap-boards-interaction
plan: 02
type: execute
wave: 2
depends_on:
  - 33-01-composer-shared-wrap
files_modified:
  - lib/foglet_bbs/tui/screens/post_composer.ex
  - lib/foglet_bbs/tui/screens/new_thread.ex
  - test/foglet_bbs/tui/screens/post_composer_test.exs
  - test/foglet_bbs/tui/screens/new_thread_test.exs
autonomous: true
requirements:
  - POST-02
tags:
  - tui
  - composer
  - post-composer
  - new-thread

must_haves:
  truths:
    - "D-01: reply and new-thread body edit mode both consume shared Compose.render_input/4 wrapping"
    - "D-04: wrapping width is derived from the current terminal width at render time"
    - "D-05: cursor/key handling stays in MultiLineInput.update/2; no replacement editor state model is introduced"
    - "D-09: tests cover shared composer wrap behavior through reply composer and new-thread compose body"
    - "D-10: tests prove 80x24 and 64x22 renders reflow without inserting newline characters into the logical buffer"
  artifacts:
    - path: "lib/foglet_bbs/tui/screens/post_composer.ex"
      provides: "Reply composer passes current body width to Compose.render_input/4"
      contains: "width:"
    - path: "lib/foglet_bbs/tui/screens/new_thread.ex"
      provides: "New-thread composer passes current body width to Compose.render_input/4"
      contains: "empty_line_placeholder: \" \""
---

<objective>
Wire the shared visual-wrap renderer into reply and new-thread composer screens using the current terminal width, then add screen-level tests proving compact wrapping, resize reflow, and logical submitted-body preservation.
</objective>

<execution_context>
@/Users/brendan.turner/Dev/personal/foglet_bbs/.codex/get-shit-done/workflows/execute-plan.md
@/Users/brendan.turner/Dev/personal/foglet_bbs/.codex/get-shit-done/templates/summary.md
</execution_context>

<context>
@AGENTS.md
@docs/raxol/getting-started/WIDGET_GALLERY.md
@lib/foglet_bbs/tui/widgets/README.md
@.planning/phases/33-composer-wrap-boards-interaction/33-CONTEXT.md
@.planning/phases/33-composer-wrap-boards-interaction/33-RESEARCH.md
@lib/foglet_bbs/tui/screens/post_composer.ex
@lib/foglet_bbs/tui/screens/new_thread.ex
@lib/foglet_bbs/tui/widgets/compose.ex
@test/foglet_bbs/tui/screens/post_composer_test.exs
@test/foglet_bbs/tui/screens/new_thread_test.exs
</context>

<threat_model>
T-33-01: Screen callers could accidentally submit visually wrapped rows instead of logical text. Mitigation: keep submit paths unchanged and add tests that submit a long one-line value and assert the fake domain receives the same one-line body.
</threat_model>

<tasks>

<task type="auto" tdd="false">
  <name>Task 1: Pass current editor body width from PostComposer and NewThread into Compose.render_input/4</name>
  <files>lib/foglet_bbs/tui/screens/post_composer.ex, lib/foglet_bbs/tui/screens/new_thread.ex</files>
  <read_first>
    - lib/foglet_bbs/tui/screens/post_composer.ex
    - lib/foglet_bbs/tui/screens/new_thread.ex
    - lib/foglet_bbs/tui/widgets/compose.ex
    - lib/foglet_bbs/tui/widgets/composer/editor_frame.ex
  </read_first>
  <action>
    Update reply composer:
    - Change private `render_input/3` to accept a fourth `width` argument, or replace it with direct body-width calculation in `composer_body/6`.
    - Use `body_width = max(width - 4, 20)` from the current terminal width passed into `composer_body(:edit, input_st, _draft, state, theme, width)`.
    - Call `Compose.render_input(input_st, focused?, theme, width: body_width)`.

    Update new-thread composer:
    - In `render_body_section/3`, derive `{w, _h} = state.terminal_size || @default_terminal_size`.
    - Use `body_width = max(w - 4, 20)`.
    - Change the edit-mode call to `Compose.render_input(ss.body_input_state, body_focused, theme, width: body_width, empty_line_placeholder: " ")`.

    Do not change `submit/1`, `do_submit`, or any code path that reads `input_state.value`.
  </action>
  <verify>
    <automated>rtk mix format lib/foglet_bbs/tui/screens/post_composer.ex lib/foglet_bbs/tui/screens/new_thread.ex</automated>
  </verify>
  <acceptance_criteria>
    - `rtk rg -n "Compose\\.render_input\\([^\\n]+width:" lib/foglet_bbs/tui/screens/post_composer.ex lib/foglet_bbs/tui/screens/new_thread.ex` prints matches in both files.
    - `rtk rg -n "create_reply|create_thread" lib/foglet_bbs/tui/screens/post_composer.ex lib/foglet_bbs/tui/screens/new_thread.ex` still shows submit paths reading state values rather than rendered rows.
    - `rtk mix format lib/foglet_bbs/tui/screens/post_composer.ex lib/foglet_bbs/tui/screens/new_thread.ex` exits 0.
  </acceptance_criteria>
</task>

<task type="auto" tdd="false">
  <name>Task 2: Add reply composer compact-wrap, resize, and submit preservation tests</name>
  <files>test/foglet_bbs/tui/screens/post_composer_test.exs</files>
  <read_first>
    - test/foglet_bbs/tui/screens/post_composer_test.exs
    - lib/foglet_bbs/tui/screens/post_composer.ex
    - lib/foglet_bbs/tui/widgets/compose.ex
  </read_first>
  <action>
    Extend `PostComposerTest` with tests that seed the reply composer body with one long logical line such as:

    ```elixir
    long_body = "alpha beta gamma delta epsilon zeta eta theta"
    ```

    Required assertions:
    - At `terminal_size: {64, 22}`, `PostComposer.render/1 |> flatten_text()` contains multiple wrapped chunks from the same logical line, including `"alpha beta"` and `"gamma delta"` or another deterministic split produced by `TextWidth.wrap/2`.
    - The stored value at `state.screen_state.post_composer.input_state.value` equals `long_body` after render.
    - Rendering the same state at `{80, 24}` and `{64, 22}` does not change the stored value and the compact flattened output differs from the wide output in a way that proves reflow.
    - Submitting with Ctrl+S routes through `FakePosts.create_reply/4` with the exact one-line body. If necessary, add a `FakePosts` clause that returns the received body in the created post and assert no `"\n"` was inserted.
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/screens/post_composer_test.exs</automated>
  </verify>
  <acceptance_criteria>
    - `test/foglet_bbs/tui/screens/post_composer_test.exs` contains `terminal_size: {64, 22}`.
    - `test/foglet_bbs/tui/screens/post_composer_test.exs` contains `terminal_size: {80, 24}`.
    - `test/foglet_bbs/tui/screens/post_composer_test.exs` contains `refute input_value` or an equivalent assertion proving no inserted newline.
    - `rtk mix test test/foglet_bbs/tui/screens/post_composer_test.exs` exits 0.
  </acceptance_criteria>
</task>

<task type="auto" tdd="false">
  <name>Task 3: Add new-thread compact-wrap, resize, and submit preservation tests</name>
  <files>test/foglet_bbs/tui/screens/new_thread_test.exs</files>
  <read_first>
    - test/foglet_bbs/tui/screens/new_thread_test.exs
    - lib/foglet_bbs/tui/screens/new_thread.ex
    - lib/foglet_bbs/tui/widgets/compose.ex
  </read_first>
  <action>
    Extend `NewThreadTest` with tests that seed `body_input_state` with the same long one-line body while `step: :compose`, `focused: :body`, and `mode: :edit`.

    Required assertions:
    - At `terminal_size: {64, 22}`, render output contains multiple visual chunks from the one logical body line.
    - The title input rendering and title value assertions from existing tests remain unchanged.
    - Rendering at `{80, 24}` and `{64, 22}` does not alter `get_ss(state).body_input_state.value`; the compact render proves reflow.
    - Ctrl+S with a valid title and long one-line body still navigates to `:thread_list` and leaves the body submitted through `FakeThreadsOk.create_thread/3` without inserted newlines. Adjust the fake module only if needed to expose submitted attrs for assertions.
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/screens/new_thread_test.exs</automated>
  </verify>
  <acceptance_criteria>
    - `test/foglet_bbs/tui/screens/new_thread_test.exs` contains `terminal_size: {64, 22}`.
    - `test/foglet_bbs/tui/screens/new_thread_test.exs` contains `body_input_state.value`.
    - `test/foglet_bbs/tui/screens/new_thread_test.exs` contains an assertion that the long body does not contain inserted `\\n`.
    - `rtk mix test test/foglet_bbs/tui/screens/new_thread_test.exs` exits 0.
  </acceptance_criteria>
</task>

</tasks>

<verification>
Run:

```bash
rtk mix test test/foglet_bbs/tui/widgets/compose_test.exs test/foglet_bbs/tui/screens/post_composer_test.exs test/foglet_bbs/tui/screens/new_thread_test.exs
rtk mix foglet.tui.render post_composer --width 64 --height 22
```
</verification>

<success_criteria>
- Reply composer body edit mode visually wraps long logical lines.
- New-thread body edit mode visually wraps long logical lines.
- Resizing between 80x24 and 64x22 changes only rendered visual rows.
- Submitted body text remains logical one-line text unless the user typed real newlines.
</success_criteria>
