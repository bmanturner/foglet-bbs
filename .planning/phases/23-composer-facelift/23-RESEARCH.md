# Phase 23: Composer Facelift - Research

**Researched:** 2026-04-25  
**Domain:** SSH-served terminal composer UI, Raxol widgets, Foglet TUI screen composition  
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
Phase 23 refreshes `Foglet.TUI.Screens.NewThread` compose mode and `Foglet.TUI.Screens.PostComposer` into the Classic Modern BBS composer shape from `SCREENS.md`: both composer screens use a shared visible editor shell, explicit Edit/Preview control, theme-routed character budget counters, mode-specific context, and existing markdown preview behavior inside the same shell.

Phase 23 does NOT change thread/reply creation, board selection, message-number allocation, posting policy, authorization behavior, autosave/draft persistence, attachments, polls, mentions, rich text editing, browser workflows, or the `TextInput`/`MultiLineInput` editing engines. Existing keyboard-first behavior, validation, submit/cancel transitions, and resize-gate draft preservation remain intact.

### Shared Composer Shell

- **D-01:** Create `Foglet.TUI.Widgets.Composer.EditorFrame` or an equivalent module under a `widgets/composer/` bucket as the shared composer widget boundary. It should wrap the existing body editor/preview surface and be applied by both `NewThread` and `PostComposer`; the screens should not grow separate frame, tab, and counter formatting piles.
- **D-02:** Keep `Raxol.UI.Components.Input.MultiLineInput` as the body editing engine and keep `Foglet.TUI.Widgets.Compose.render_input/4` or a direct successor responsible for width-aware cursor rendering. `EditorFrame` frames and styles the editor; it does not replace the input component.
- **D-03:** Keep `Foglet.TUI.Widgets.Input.TextInput` as the new-thread title editing engine. The title field may be visually placed inside the shared shell, but title input handling and max-length behavior remain the current `TextInput` path.

### Mode Control

- **D-04:** Render Edit/Preview as a compact segmented row inside the composer shell rather than only as a command hint. It may be a stateless composer-specific renderer instead of the stateful `Input.Tabs` widget, because Tab behavior is already screen-owned and the mode set is exactly two values.
- **D-05:** Active mode must be visible in render output and theme-routed through the Phase 17 editor/tab mapping slots. Both `:edit` and `:preview` render the same surrounding composer shell so preview feels like a mode of the editor, not a separate loose screen body.

### Character Budgets

- **D-06:** Character budgets are text-first counters for Phase 23. New-thread title, new-thread body, and reply body all render compact `N / cap chars` treatment where a limit exists, with normal, warning, and over-limit states routed through `Foglet.TUI.Presentation.theme_mappings().editor` (`counter`, `counter_warning`, `counter_error`) and `Foglet.TUI.Theme`.
- **D-07:** `Foglet.TUI.Widgets.Display.Progress` may be used as optional polish when space permits, but a progress bar is not required and must collapse before the compact text counter. The durable contract is readable text budget state at 64x22.
- **D-08:** Character budgets remain character-count policy limits, not terminal display-width limits. This preserves Phase 16's boundary: display-width helpers protect layout and cursor placement; validation/counter counts use content characters.

### Context And Minimum Size

- **D-09:** At the 64x22 minimum, layout priority is: visible Edit/Preview mode control, usable body editor or preview content, and compact budget text. Quote, board, title, and other context are secondary and must shorten or collapse before those required controls disappear.
- **D-10:** Reply composition shows compact quoted context in the shell when space allows. Use a light quote/gutter treatment such as `┃` or `>` and cap quoted lines aggressively; do not let the quote block push the editor off screen.
- **D-11:** New-thread composition shows board context and title context in the shell when space allows. Board/title context may compress to a single line or omit nonessential labels at 64x22, but title editing itself remains available and clear.

### Preview Path

- **D-12:** Preview mode continues using `Foglet.TUI.Widgets.Post.MarkdownBody`; Phase 23 must not introduce a new post-rendering or `PostCard` preview pipeline. Preview content is rendered inside the same composer shell with the active Preview mode visible.

### Behavior Preservation

- **D-13:** Preserve existing key handling: Tab switches title/body focus or edit/preview exactly as current screen rules define; Ctrl+S submits; Ctrl+C/Esc cancels through current origins; fallback body keys route through `Compose.translate_key/1` and `MultiLineInput.update/2`.
- **D-14:** Preserve existing domain and validation behavior. `PostComposer` continues enforcing `max_post_length` and returning to `PostReader` after successful reply submission. `NewThread` continues using `Foglet.Threads.create_thread/3`, preserving policy/locked/changeset error handling and transition back to `ThreadList`.

### Test Placement

- **D-15:** Add widget tests under `test/foglet_bbs/tui/widgets/composer/editor_frame_test.exs` or the equivalent mirrored path if the final module name differs. Cover focused/unfocused frame treatment, Edit/Preview mode marker output, counter state styling, preview/editor children, and theme hygiene.
- **D-16:** Extend `test/foglet_bbs/tui/screens/post_composer_test.exs` and `test/foglet_bbs/tui/screens/new_thread_test.exs` for shell presence, visible Edit/Preview labels in both modes, compact context, budget states, preview staying in-shell, and preservation of existing behavior tests.
- **D-17:** Extend `test/foglet_bbs/tui/layout_smoke_test.exs` with Phase 23 composer size-contract coverage at `[{64, 22}, {80, 24}, {132, 50}]`. Assertions should cover visible mode control, editor/preview content, compact counter, no overlapping positioned text, and context collapse at 64x22.
- **D-18:** Keep existing `test/foglet_bbs/tui/widgets/compose_test.exs`, `test/foglet_bbs/tui/app_test.exs` resize-gate composer tests, and composer behavior tests passing. Add to them only where the shared input/cursor boundary changes.

### the agent's Discretion
- Exact `EditorFrame` public function shape and options, as long as both composer screens delegate through one shared composer widget boundary and the widget accepts `theme:` explicitly.
- Exact border glyphs and segmented-control styling, provided they are single-cell/width-safe, theme-routed, and readable at 64x22.
- Exact warning threshold for counters. Recommended default is warning at 80% of the limit and error when over limit, matching `Display.Progress` state conventions.
- Whether optional compact progress segments ship in Phase 23. Text counters are mandatory; progress segments are optional.
- Exact quote/context collapse algorithm, provided the 64x22 priority from D-09 is enforced and tested.

### Deferred Ideas (OUT OF SCOPE)
- Autosave or persisted drafts — future product workflow, not Phase 23.
- Attachments, polls, mentions, rich text editing, or collaborative editing — future composer capabilities, not this facelift.
- Reworking the `NewThread` board-selection step — out of scope; Phase 23 targets the compose surface.
- Building a full final-post preview via `PostCard` — explicitly out of scope; preview remains markdown body rendering inside the shell.
- Screenshot-based terminal fixtures — Phase 23 follows existing code/layout tests unless a later visual QA phase adds screenshots.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| COMPOSER-01 | `Composer.EditorFrame` wraps `MultiLineInput` for new-thread and reply composition with visible editor boundaries and focused/unfocused styling. | Use a new stateless `Foglet.TUI.Widgets.Composer.EditorFrame` that delegates body rendering to `Compose.render_input/4` and receives `theme:` explicitly. [VERIFIED: `.planning/REQUIREMENTS.md`, `23-CONTEXT.md`, `lib/foglet_bbs/tui/widgets/compose.ex`, `lib/foglet_bbs/tui/widgets/README.md`] |
| COMPOSER-02 | Edit and preview modes are visible as a tab or segmented control instead of only hidden in key hints. | Render a compact two-option segmented row in the editor shell; keep screen-owned mode state and Tab handling. [VERIFIED: `.planning/REQUIREMENTS.md`, `23-CONTEXT.md`, `lib/foglet_bbs/tui/screens/post_composer.ex`, `lib/foglet_bbs/tui/screens/new_thread.ex`] |
| COMPOSER-03 | Character budgets use shared progress/counter treatment with normal, warning, and over-limit states for title and body inputs where applicable. | Add a shared composer budget renderer using `Presentation.theme_mappings().editor` and optional `Display.Progress` only when space permits. [VERIFIED: `.planning/REQUIREMENTS.md`, `23-CONTEXT.md`, `lib/foglet_bbs/tui/presentation.ex`, `lib/foglet_bbs/tui/widgets/display/progress.ex`] |
| COMPOSER-04 | Reply composition shows compact quoted context while new-thread composition shows board and title context, with nonessential context collapsing first at 64x22. | Make context an explicit optional section of `EditorFrame`; quote/board labels collapse before mode control, body surface, and compact counter. [VERIFIED: `.planning/REQUIREMENTS.md`, `23-CONTEXT.md`, `SCREENS.md`] |
| COMPOSER-05 | Title `TextInput` and body `MultiLineInput` behavior remains width-aware and theme-routed after the editor-frame refresh. | Keep `TextInput` and `MultiLineInput` state in screen structs; do not replace editing engines or reimplement cursor/key behavior. [VERIFIED: `.planning/REQUIREMENTS.md`, `23-CONTEXT.md`, `lib/foglet_bbs/tui/widgets/input/text_input.ex`, `vendor/raxol/lib/raxol/ui/components/input/multi_line_input.ex`] |
</phase_requirements>

## Summary

Phase 23 should be implemented as a shared presentation wrapper around the existing composer engines, not as a new editor subsystem. [VERIFIED: `23-CONTEXT.md`, `lib/foglet_bbs/tui/widgets/compose.ex`] The established pattern in this codebase is screen-owned state and key routing, pure widget renderers, explicit `theme:` arguments, and layout verification through Raxol positioned output. [VERIFIED: `lib/foglet_bbs/tui/widgets/README.md`, `test/foglet_bbs/tui/layout_smoke_test.exs`]

The industry pattern supports this boundary: mature TUI editor widgets treat multiline editing, cursor movement, wrapping, undo/redo, and selection as specialized component concerns, while frames, validation displays, mode labels, and counters are composition around the editor. [CITED: https://textual.textualize.io/widgets/text_area/] [CITED: https://docs.rs/ratatui-textarea/latest/ratatui_textarea/] Foglet already has that split: Raxol `MultiLineInput` owns editor state, `Compose.render_input/4` owns Foglet cursor rendering, `TextInput` owns title input, and screens own submit/cancel/mode behavior. [VERIFIED: `vendor/raxol/lib/raxol/ui/components/input/multi_line_input.ex`, `lib/foglet_bbs/tui/widgets/compose.ex`, `lib/foglet_bbs/tui/widgets/input/text_input.ex`]

**Primary recommendation:** Build `Foglet.TUI.Widgets.Composer.EditorFrame` as a stateless shell with small helpers for mode segment, budget counter, optional compact progress, and context collapse; then migrate `PostComposer.render/1` and `NewThread.render_compose_step/2` to feed it already-rendered title/body/preview/context children. [VERIFIED: `23-CONTEXT.md`, `SCREENS.md`]

## Project Constraints (from AGENTS.md)

- Foglet BBS is SSH-first; do not add end-user browser workflows for this phase. [VERIFIED: `AGENTS.md`, `.planning/REQUIREMENTS.md`]
- Use `rtk` as the shell command prefix in this repo. [VERIFIED: `AGENTS.md`, `/Users/brendan.turner/.codex/RTK.md`]
- TUI behavior belongs in `Foglet.TUI.App`, screens, screen-local state modules, and reusable widgets; Phoenix namespaces are infrastructure. [VERIFIED: `AGENTS.md`]
- Route colors through `Foglet.TUI.Theme`; pass theme explicitly; keep render functions pure over already-loaded state. [VERIFIED: `AGENTS.md`, `lib/foglet_bbs/tui/widgets/README.md`]
- Widgets should expose `init/1`, `handle_event/2`, and `render/2` when stateful; stateless widgets expose render functions. [VERIFIED: `lib/foglet_bbs/tui/widgets/README.md`]
- Domain mutations must remain in contexts; this phase should preserve existing `Foglet.Threads.create_thread/3` and reply submission paths. [VERIFIED: `AGENTS.md`, `23-CONTEXT.md`, `lib/foglet_bbs/tui/screens/new_thread.ex`, `lib/foglet_bbs/tui/screens/post_composer.ex`]
- Use `start_supervised!/1` for process tests and avoid `Process.sleep/1`; this phase is primarily render/key tests and should not need new process tests. [VERIFIED: `AGENTS.md`]
- Run `mix precommit` when code changes are complete. [VERIFIED: `AGENTS.md`, `mix.exs`]

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Composer visual shell | SSH TUI / Widget | Screens | `EditorFrame` owns rendering, border styling, mode segment, context placement, and budget visuals; screens supply state-derived children. [VERIFIED: `23-CONTEXT.md`, `lib/foglet_bbs/tui/widgets/README.md`] |
| Body editing | Raxol component wrapped by Foglet widget | Screens | `MultiLineInput` owns text editing state and `Compose.render_input/4` owns width-aware cursor insertion. [VERIFIED: `vendor/raxol/lib/raxol/ui/components/input/multi_line_input.ex`, `lib/foglet_bbs/tui/widgets/compose.ex`] |
| Title editing | Foglet input widget | NewThread screen | `TextInput` already wraps Raxol single-line input and enforces max-length behavior. [VERIFIED: `lib/foglet_bbs/tui/widgets/input/text_input.ex`, `lib/foglet_bbs/tui/screens/new_thread.ex`] |
| Edit/Preview mode | Screens | Widget render helper | Current `PostComposer` and `NewThread` screen state stores `mode`; the widget should render the selected value without owning transitions. [VERIFIED: `lib/foglet_bbs/tui/screens/post_composer/state.ex`, `lib/foglet_bbs/tui/screens/new_thread/state.ex`] |
| Markdown preview | Existing post widget | Screens | Preview continues through `Post.MarkdownBody.render/3` and is placed inside the shell. [VERIFIED: `23-CONTEXT.md`, `lib/foglet_bbs/tui/widgets/post/markdown_body.ex`] |
| Submit/cancel/domain validation | Domain contexts via screens | Modal/error display | Submit and cancel behavior is screen-owned and must remain unchanged; the shell may display errors only. [VERIFIED: `23-CONTEXT.md`, `lib/foglet_bbs/tui/screens/post_composer.ex`, `lib/foglet_bbs/tui/screens/new_thread.ex`] |

## Standard Stack

### Core

| Library / Module | Version | Purpose | Why Standard |
|------------------|---------|---------|--------------|
| Elixir | 1.19.5 in local runtime; project constraint `~> 1.17` | Application/runtime language | Existing Phoenix/Raxol codebase and tests run on Elixir. [VERIFIED: `rtk mix run -e 'IO.puts(System.version())'`, `mix.exs`] |
| Raxol | 2.4.0, `vendor/raxol` path dependency | Terminal UI runtime, View DSL, layout engine, input components | Existing SSH TUI is built on Raxol and its `MultiLineInput` component. [VERIFIED: `rtk mix deps`, `mix.exs`, `vendor/raxol/lib/raxol/ui/components/input/multi_line_input.ex`] |
| `Foglet.TUI.Widgets.Compose` | Project module | Body key translation and width-aware body rendering | Already shared by `PostComposer` and `NewThread`; preserves `TextWidth.split_at/2` cursor placement. [VERIFIED: `lib/foglet_bbs/tui/widgets/compose.ex`, `test/foglet_bbs/tui/widgets/compose_test.exs`] |
| `Foglet.TUI.Widgets.Input.TextInput` | Project module | New-thread title input | Existing themed wrapper over Raxol `TextInput`; keeps title state and max length behavior. [VERIFIED: `lib/foglet_bbs/tui/widgets/input/text_input.ex`, `test/foglet_bbs/tui/widgets/input/text_input_test.exs`] |
| `Foglet.TUI.Widgets.Post.MarkdownBody` | Project module | Preview rendering | Existing markdown-to-terminal renderer used by current composer preview paths. [VERIFIED: `lib/foglet_bbs/tui/widgets/post/markdown_body.ex`, `lib/foglet_bbs/tui/screens/post_composer.ex`, `lib/foglet_bbs/tui/screens/new_thread.ex`] |
| `Foglet.TUI.Theme` and `Foglet.TUI.Presentation` | Project modules | Theme slots and semantic editor mapping | Phase 17 defines editor slots for focused/unfocused/input/counter states. [VERIFIED: `lib/foglet_bbs/tui/presentation.ex`, `test/foglet_bbs/tui/presentation_test.exs`] |

### Supporting

| Library / Module | Version | Purpose | When to Use |
|------------------|---------|---------|-------------|
| `Foglet.TUI.Widgets.Display.Progress` | Project module | Optional compact segmented budget visualization | Use only after compact text counter remains visible; collapse progress first at 64x22. [VERIFIED: `23-CONTEXT.md`, `lib/foglet_bbs/tui/widgets/display/progress.ex`] |
| `Raxol.UI.Layout.Engine` | Raxol 2.4.0 | Layout verification in tests | Use through existing layout smoke test harness for 64x22, 80x24, and 132x50 size contracts. [VERIFIED: `test/foglet_bbs/tui/layout_smoke_test.exs`, `rtk mix deps`] |
| `Foglet.TUI.TextWidth` | Project module | Display-width measurement and cursor-safe split | Use for truncation, row budget checks, and any glyph/context collapse math. [VERIFIED: `lib/foglet_bbs/tui/widgets/compose.ex`, `test/foglet_bbs/tui/text_width_test.exs`] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Composer-specific stateless segment renderer | `Foglet.TUI.Widgets.Input.Tabs` | `Tabs` is stateful and consumes navigation events; locked context says two-value composer mode is screen-owned and can be stateless. [VERIFIED: `23-CONTEXT.md`, `lib/foglet_bbs/tui/widgets/input/tabs.ex`] |
| Existing `MultiLineInput` plus shell | New custom multiline editor | Mature TUI editors include cursor movement, wrapping, selection, undo/redo, scrolling, and shortcut behavior; rebuilding that would expand Phase 23 far beyond facelift scope. [CITED: https://docs.rs/ratatui-textarea/latest/ratatui_textarea/] [VERIFIED: `vendor/raxol/lib/raxol/ui/components/input/multi_line_input.ex`] |
| `MarkdownBody` preview | `PostCard` preview pipeline | Locked context explicitly keeps preview lightweight inside composer shell and excludes final-post mockup work. [VERIFIED: `23-CONTEXT.md`, `lib/foglet_bbs/tui/widgets/post/markdown_body.ex`] |

**Installation:** No dependency installation is required for this phase. [VERIFIED: `mix.exs`, `rtk mix deps`] The project already depends on local `vendor/raxol` and the required Foglet widgets are in the repo. [VERIFIED: `mix.exs`, `lib/foglet_bbs/tui/widgets/README.md`]

**Version verification:** Versions were verified with `rtk mix deps`; Raxol is `2.4.0`, Phoenix is `1.8.5`, Ecto is `3.13.5`, and ExUnit is provided by Elixir/OTP. [VERIFIED: `rtk mix deps`, `mix.lock`] This phase does not need registry version changes. [VERIFIED: `23-CONTEXT.md`]

## Architecture Patterns

### System Architecture Diagram

```text
SSH key events / resize
        |
        v
Foglet.SSH.CLIHandler -> Raxol lifecycle -> Foglet.TUI.App
        |                                      |
        |                                      v
        |                         current_screen dispatch
        |                                      |
        |                       +--------------+--------------+
        |                       |                             |
        v                       v                             v
PostComposer screen      NewThread compose step        NewThread board step
 mode/input state         title/body/focus/mode         unchanged selection UI
        |                       |
        |                       v
        |             TextInput.render for title
        v                       |
Compose.translate_key    Compose.translate_key
MultiLineInput.update    MultiLineInput.update
        |                       |
        +-----------+-----------+
                    v
         Composer.EditorFrame.render
       mode segment -> context -> child editor/preview -> budget/error
                    |
                    v
          Chrome.ScreenFrame.render
                    |
                    v
           Raxol layout/rendering
```

This diagram reflects the existing event/render ownership: SSH events reach `App`, screens own key routing and state transitions, widgets render already-loaded state, and `ScreenFrame` remains the outer chrome boundary. [VERIFIED: `AGENTS.md`, `docs/raxol/core/ARCHITECTURE.md`, `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex`]

### Recommended Project Structure

```text
lib/foglet_bbs/tui/widgets/composer/
└── editor_frame.ex      # shared stateless composer shell, mode segment, counters, context collapse

test/foglet_bbs/tui/widgets/composer/
└── editor_frame_test.exs
```

The `widgets/<bucket>/<name>.ex` structure matches existing widget guidance. [VERIFIED: `lib/foglet_bbs/tui/widgets/README.md`]

### Pattern 1: Stateless Shell Around Stateful Inputs

**What:** `EditorFrame` should accept `mode`, `focused?`, optional `context`, optional `title`, `body_child`, optional `preview_child`, budget structs, errors, `width`, and `theme:`; it renders pure Raxol DSL output and does not call domain contexts or update input state. [VERIFIED: `23-CONTEXT.md`, `lib/foglet_bbs/tui/widgets/README.md`]

**When to use:** Use for both reply composition and new-thread compose step once each screen has computed the relevant child view elements. [VERIFIED: `lib/foglet_bbs/tui/screens/post_composer.ex`, `lib/foglet_bbs/tui/screens/new_thread.ex`]

**Example:**

```elixir
# Source: local Foglet widget contract and Raxol View DSL.
EditorFrame.render(
  mode: ss.mode,
  focused?: ss.mode == :edit and ss.focused == :body,
  context: reply_context(ss.reply_to, width),
  body: Compose.render_input(ss.input_state, ss.mode == :edit, theme),
  budget: %{label: "Body", count: String.length(draft), limit: max_len(state)},
  error: ss.error,
  width: width,
  theme: theme
)
```

This keeps editing state in the screen and uses the shell only for presentation. [VERIFIED: `23-CONTEXT.md`, `lib/foglet_bbs/tui/widgets/compose.ex`]

### Pattern 2: Text-First Budget Rendering

**What:** Budget rendering should always emit compact text such as `Body 181 / 8192 chars`; state selects `counter`, `counter_warning`, or `counter_error` from `Presentation.theme_mappings().editor`. [VERIFIED: `23-CONTEXT.md`, `lib/foglet_bbs/tui/presentation.ex`]

**When to use:** Use for new-thread title, new-thread body if a limit is available, and reply body. [VERIFIED: `.planning/REQUIREMENTS.md`, `23-CONTEXT.md`]

**Example:**

```elixir
# Source: Foglet editor theme mapping.
defp counter_slot(count, limit) when is_integer(limit) and limit > 0 do
  cond do
    count > limit -> :counter_error
    count / limit >= 0.8 -> :counter_warning
    true -> :counter
  end
end

defp counter_text(label, count, limit, theme) do
  slot = Presentation.theme_mappings().editor |> Map.fetch!(counter_slot(count, limit))
  color = Map.fetch!(theme, slot).fg
  text("#{label} #{count} / #{limit} chars", fg: color)
end
```

The 80% warning threshold matches the locked recommendation and the existing `Display.Progress` threshold. [VERIFIED: `23-CONTEXT.md`, `lib/foglet_bbs/tui/widgets/display/progress.ex`]

### Pattern 3: Progressive Context Collapse

**What:** Treat mode control, body surface, and compact counter as required rows; quote, board name, title metadata labels, and optional progress segments are progressive enhancements. [VERIFIED: `23-CONTEXT.md`, `SCREENS.md`]

**When to use:** At 64x22, cap reply quote lines aggressively and shorten context before removing required writing controls. [VERIFIED: `23-CONTEXT.md`, `.planning/REQUIREMENTS.md`]

**Example:**

```elixir
# Source: Phase 23 collapse priority.
defp quote_context(nil, _width, _height), do: []
defp quote_context(_post, _width, height) when height <= 22, do: []

defp quote_context(post, width, _height) do
  post.body
  |> String.split("\n")
  |> Enum.take(2)
  |> Enum.map(fn line -> "┃ " <> TextWidth.truncate(line, max(width - 4, 10)) end)
end
```

Use `TextWidth.truncate/2` or the existing display-width helper for context strings because Unicode glyphs are part of the milestone UI language. [VERIFIED: `SCREENS.md`, `lib/foglet_bbs/tui/widgets/compose.ex`, `test/foglet_bbs/tui/text_width_test.exs`]

### Anti-Patterns to Avoid

- **Replacing `MultiLineInput`:** Do not hand-roll cursor, wrapping, undo/redo, selection, and scrolling behavior during a facelift. [VERIFIED: `23-CONTEXT.md`, `vendor/raxol/lib/raxol/ui/components/input/multi_line_input.ex`] [CITED: https://docs.rs/ratatui-textarea/latest/ratatui_textarea/]
- **Putting mode state in `EditorFrame`:** Current screens own `mode` and key routing; the shell should render active mode only. [VERIFIED: `lib/foglet_bbs/tui/screens/post_composer.ex`, `lib/foglet_bbs/tui/screens/new_thread.ex`]
- **Using hidden key hints as the only mode indication:** COMPOSER-02 requires visible Edit/Preview state in the content area. [VERIFIED: `.planning/REQUIREMENTS.md`, `23-CONTEXT.md`]
- **Hardcoding color atoms:** Widget tests scan for leaked atoms such as `:red` and `:green`; route through `Theme` slots. [VERIFIED: `lib/foglet_bbs/tui/widgets/README.md`, `test/support/foglet/tui/widget_helpers.ex`]
- **Letting quote/title context consume the editor:** Minimum-size priority requires context to collapse before mode control, body surface, and compact counter. [VERIFIED: `23-CONTEXT.md`]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Multiline text editing | Custom buffer, cursor movement, undo/redo, word wrap, selection, scrolling | `Raxol.UI.Components.Input.MultiLineInput` plus `Compose.translate_key/1` and `Compose.render_input/4` | Mature TUI editor widgets include many edge cases; Foglet already has the component and tests. [VERIFIED: `vendor/raxol/lib/raxol/ui/components/input/multi_line_input.ex`, `test/foglet_bbs/tui/widgets/compose_test.exs`] [CITED: https://textual.textualize.io/widgets/text_area/] |
| Single-line title editing | Custom title input renderer/handler | `Foglet.TUI.Widgets.Input.TextInput` | Existing wrapper handles theme routing, max length, masking, and key translation. [VERIFIED: `lib/foglet_bbs/tui/widgets/input/text_input.ex`, `test/foglet_bbs/tui/widgets/input/text_input_test.exs`] |
| Markdown preview | New post preview/card renderer | `Foglet.TUI.Widgets.Post.MarkdownBody.render/3` | Locked context says preview stays markdown-body-only inside the shell. [VERIFIED: `23-CONTEXT.md`, `lib/foglet_bbs/tui/widgets/post/markdown_body.ex`] |
| Character progress polish | New progress bar primitive | `Foglet.TUI.Widgets.Display.Progress` only as optional compact polish | Existing progress widget already routes semantic states through theme slots and tests warning/error behavior. [VERIFIED: `lib/foglet_bbs/tui/widgets/display/progress.ex`, `test/foglet_bbs/tui/widgets/display/progress_test.exs`] |
| Width measurement/truncation | `String.length/1` or byte slicing for display layout | `Foglet.TUI.TextWidth` | Phase 16 established display-width helpers for Unicode layout and cursor placement. [VERIFIED: `.planning/REQUIREMENTS.md`, `lib/foglet_bbs/tui/widgets/compose.ex`, `test/foglet_bbs/tui/text_width_test.exs`] |
| Screen chrome | Bespoke composer chrome/footer | `Chrome.ScreenFrame` and existing command groups | `ScreenFrame` is the shared outer frame for current screens. [VERIFIED: `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex`] |

**Key insight:** The hard part is not drawing a border; it is preserving the existing editor, validation, and resize behavior while making mode/counter/context visible in one shared shell. [VERIFIED: `23-CONTEXT.md`, `test/foglet_bbs/tui/app_test.exs`, `test/foglet_bbs/tui/layout_smoke_test.exs`]

## Common Pitfalls

### Pitfall 1: Screen-Owned Key Routing Gets Broken

**What goes wrong:** Ctrl+S or Ctrl+C reaches `MultiLineInput` and inserts text instead of submitting/canceling. [VERIFIED: `lib/foglet_bbs/tui/screens/new_thread.ex`, `test/foglet_bbs/tui/widgets/compose_test.exs`]  
**Why it happens:** `Compose.translate_key/1` intentionally translates ctrl-modified printable chars unless the screen intercepts them first. [VERIFIED: `lib/foglet_bbs/tui/widgets/compose.ex`, `test/foglet_bbs/tui/widgets/compose_test.exs`]  
**How to avoid:** Keep Tab/Ctrl+S/Ctrl+C/Esc clauses above fallback input forwarding. [VERIFIED: `lib/foglet_bbs/tui/screens/post_composer.ex`, `lib/foglet_bbs/tui/screens/new_thread.ex`]  
**Warning signs:** Tests mention source order or key clauses; do not reorder them while moving render code. [VERIFIED: `lib/foglet_bbs/tui/screens/new_thread.ex`, `lib/foglet_bbs/tui/screens/post_composer.ex`]

### Pitfall 2: Character Limits Get Confused With Display Width

**What goes wrong:** Counters use terminal display width instead of content character count, causing CJK or combining text to report confusing budget values. [VERIFIED: `23-CONTEXT.md`]  
**Why it happens:** Phase 16 created display-width helpers, but Phase 23 budget policy is character-count based. [VERIFIED: `23-CONTEXT.md`, `.planning/REQUIREMENTS.md`]  
**How to avoid:** Use `String.length/1` for policy counters and `TextWidth` only for layout/truncation/cursor rendering. [VERIFIED: `23-CONTEXT.md`, `lib/foglet_bbs/tui/widgets/compose.ex`]  
**Warning signs:** Budget tests fail for Unicode or counter differs from current max-length enforcement. [VERIFIED: `test/foglet_bbs/tui/widgets/compose_test.exs`, `lib/foglet_bbs/tui/screens/post_composer.ex`]

### Pitfall 3: Optional Progress Crowds Out Mandatory Counter

**What goes wrong:** A progress bar consumes space at 64x22 while compact text budget disappears. [VERIFIED: `23-CONTEXT.md`]  
**Why it happens:** The SCREENS sketch shows progress polish, but locked context makes text counters the durable contract. [VERIFIED: `SCREENS.md`, `23-CONTEXT.md`]  
**How to avoid:** Render text counter unconditionally; render compact progress only when width/height budget permits. [VERIFIED: `23-CONTEXT.md`, `lib/foglet_bbs/tui/widgets/display/progress.ex`]  
**Warning signs:** `64x22` layout smoke lacks `N / cap chars` text. [VERIFIED: `test/foglet_bbs/tui/layout_smoke_test.exs`, `.planning/REQUIREMENTS.md`]

### Pitfall 4: Preview Looks Like a Different Screen

**What goes wrong:** Preview drops the editor boundary or active mode segment, so users lose orientation. [VERIFIED: `23-CONTEXT.md`]  
**Why it happens:** Current render functions branch into separate loose edit/preview body sections. [VERIFIED: `lib/foglet_bbs/tui/screens/post_composer.ex`, `lib/foglet_bbs/tui/screens/new_thread.ex`]  
**How to avoid:** Both edit and preview children pass through `EditorFrame` with the same shell. [VERIFIED: `23-CONTEXT.md`]  
**Warning signs:** Preview tests see markdown but no visible `Preview` segment or editor shell marker. [VERIFIED: `23-CONTEXT.md`, `test/foglet_bbs/tui/screens/post_composer_test.exs`]

### Pitfall 5: Context Collapse Uses String Slicing

**What goes wrong:** Quote or title context truncates through CJK/combining glyphs or overflows positioned rows. [VERIFIED: `SCREENS.md`, `test/foglet_bbs/tui/text_width_test.exs`]  
**Why it happens:** Terminal display width is not the same as byte length or grapheme count. [VERIFIED: `docs/raxol/core/ARCHITECTURE.md`, `test/foglet_bbs/tui/text_width_test.exs`]  
**How to avoid:** Use `TextWidth.truncate/2`/helpers for visible context strings and verify with layout smoke row bounds. [VERIFIED: `lib/foglet_bbs/tui/widgets/compose.ex`, `test/foglet_bbs/tui/layout_smoke_test.exs`]  
**Warning signs:** Positioned text has `x + display_width(text) > width` at 64 columns. [VERIFIED: `test/foglet_bbs/tui/layout_smoke_test.exs`]

### Pitfall 6: Theme Hygiene Regressions

**What goes wrong:** New widget code leaks literal color atoms or bypasses Phase 17 editor mappings. [VERIFIED: `lib/foglet_bbs/tui/widgets/README.md`, `test/support/foglet/tui/widget_helpers.ex`]  
**Why it happens:** Raxol DSL permits direct `fg: :cyan`, but Foglet widgets require theme-routed slots. [CITED: `docs/raxol/cookbook/THEMING.md`] [VERIFIED: `lib/foglet_bbs/tui/widgets/README.md`]  
**How to avoid:** Fetch semantic slots from `Presentation.theme_mappings().editor` and `Theme` instead of hardcoded atoms. [VERIFIED: `lib/foglet_bbs/tui/presentation.ex`]  
**Warning signs:** Widget hygiene tests using `color_atom_leaked?/2` fail. [VERIFIED: `test/support/foglet/tui/widget_helpers.ex`]

## Code Examples

Verified patterns from local sources:

### Render Body Edit Mode Without Replacing the Editor

```elixir
# Source: lib/foglet_bbs/tui/screens/post_composer.ex and widgets/compose.ex
defp render_input(input_st, state, theme) do
  ss = composer_screen_state(state)
  focused? = ss.mode == :edit
  Compose.render_input(input_st, focused?, theme)
end
```

This is the boundary to preserve: screens decide focus/mode, `Compose` renders the existing input state. [VERIFIED: `lib/foglet_bbs/tui/screens/post_composer.ex`, `lib/foglet_bbs/tui/widgets/compose.ex`]

### Keep Preview on Existing Markdown Renderer

```elixir
# Source: lib/foglet_bbs/tui/screens/new_thread.ex
case ss.mode do
  :edit ->
    Compose.render_input(ss.body_input_state, body_focused, theme,
      empty_line_placeholder: " "
    )

  :preview ->
    {w, _h} = state.terminal_size || @default_terminal_size
    body_width = max(w - 4, 20)
    MarkdownBody.render(ss.body_input_state.value, body_width, theme)
end
```

Phase 23 should move this child selection into inputs to `EditorFrame`, not replace `MarkdownBody`. [VERIFIED: `23-CONTEXT.md`, `lib/foglet_bbs/tui/screens/new_thread.ex`]

### Widget Theme Hygiene Test Shape

```elixir
# Source: test/foglet_bbs/tui/widgets/display/progress_test.exs
tree = Progress.render(0.5, theme: theme())
serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)

for color <- color_names() do
  refute color_atom_leaked?(serialized, color)
end
```

Add equivalent tests for `EditorFrame`. [VERIFIED: `test/foglet_bbs/tui/widgets/display/progress_test.exs`, `test/support/foglet/tui/widget_helpers.ex`]

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Composer as plain text rows with mode only in key hints | Framed editor shell with visible Edit/Preview segment and semantic counters | v1.3 facelift requirement, 2026-04-25 | Planner should add a shared composer primitive and screen render migrations. [VERIFIED: `.planning/REQUIREMENTS.md`, `SCREENS.md`, `23-CONTEXT.md`] |
| Handbuilt terminal text editing | Reuse specialized text area/multiline input components | Established in modern TUI libraries and Foglet's existing Raxol usage | Preserve `MultiLineInput` and test behavior instead of rebuilding editor mechanics. [CITED: https://textual.textualize.io/widgets/text_area/] [CITED: https://docs.rs/ratatui-textarea/latest/ratatui_textarea/] [VERIFIED: `vendor/raxol/lib/raxol/ui/components/input/multi_line_input.ex`] |
| Widget-local direct color choices | Semantic theme mappings and explicit `theme:` arguments | Phase 17 and widget catalog contract | `EditorFrame` must use `Presentation.theme_mappings().editor` and theme hygiene tests. [VERIFIED: `lib/foglet_bbs/tui/presentation.ex`, `lib/foglet_bbs/tui/widgets/README.md`] |
| Screenshot-only confidence | Positioned layout tests at canonical terminal sizes | Existing v1.3 layout smoke pattern | Add Phase 23 checks at 64x22, 80x24, and 132x50. [VERIFIED: `.planning/REQUIREMENTS.md`, `test/foglet_bbs/tui/layout_smoke_test.exs`] |

**Deprecated/outdated:**
- Hiding mode solely in the command bar is outdated for Phase 23 and directly fails COMPOSER-02. [VERIFIED: `.planning/REQUIREMENTS.md`, `23-CONTEXT.md`]
- Using `String.split_at/2` for visible cursor insertion was superseded locally by `TextWidth.split_at/2` in `Compose.render_input/4`. [VERIFIED: `SCREENS.md`, `lib/foglet_bbs/tui/widgets/compose.ex`]
- Adding browser composer workflows is out of scope and contradicts SSH-first project constraints. [VERIFIED: `AGENTS.md`, `.planning/REQUIREMENTS.md`]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | No registry/package upgrades are required for Phase 23. [ASSUMED] | Standard Stack | If the implementation reveals a missing Raxol primitive, planner may need a dependency or vendor patch task. |

## Open Questions

1. **Should reply quote be completely hidden at 64x22 or reduced to one line?**
   - What we know: context must collapse before mode control, editor body, and compact budget. [VERIFIED: `23-CONTEXT.md`]
   - What's unclear: exact one-line vs zero-line quote behavior is discretionary. [VERIFIED: `23-CONTEXT.md`]
   - Recommendation: plan for one-line quote only when it does not reduce editor/preview usability; tests should assert required controls survive at 64x22. [VERIFIED: `23-CONTEXT.md`, `test/foglet_bbs/tui/layout_smoke_test.exs`]

2. **Should body budget use the same configured limit in NewThread as replies?**
   - What we know: `PostComposer` enforces `max_post_length`; `NewThread` currently shows title cap and validates title/body emptiness through create-thread flow. [VERIFIED: `lib/foglet_bbs/tui/screens/post_composer.ex`, `lib/foglet_bbs/tui/screens/new_thread.ex`]
   - What's unclear: whether new-thread body has a direct local max-length limit or only context-level validation. [VERIFIED: `lib/foglet_bbs/tui/screens/new_thread.ex`]
   - Recommendation: use the same config lookup pattern only if existing domain policy already enforces a body limit; otherwise render body budget only where a limit exists and avoid inventing a new policy. [VERIFIED: `AGENTS.md`, `23-CONTEXT.md`]

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| Elixir | Compile/tests | yes | 1.19.5 | None needed. [VERIFIED: `rtk mix run -e 'IO.puts(System.version())'`] |
| Mix | Test and precommit workflow | yes | bundled with Elixir | None needed. [VERIFIED: `mix.exs`, `rtk mix deps`] |
| Raxol | TUI render/input stack | yes | 2.4.0 | None; project uses local `vendor/raxol`. [VERIFIED: `rtk mix deps`, `mix.exs`] |
| ExUnit/DataCase | Automated validation | yes | bundled/project test support | None needed. [VERIFIED: `test/foglet_bbs/tui/layout_smoke_test.exs`, `mix.exs`] |

**Missing dependencies with no fallback:** None found for this phase. [VERIFIED: `rtk mix deps`, `mix.exs`]

**Missing dependencies with fallback:** None found for this phase. [VERIFIED: `rtk mix deps`, `mix.exs`]

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | ExUnit via Mix; project test alias creates/migrates DB and seeds config. [VERIFIED: `mix.exs`] |
| Config file | `test/test_helper.exs` and `test/support`; phase-specific tests under `test/foglet_bbs/tui/...`. [VERIFIED: repo test structure] |
| Quick run command | `rtk mix test test/foglet_bbs/tui/widgets/composer/editor_frame_test.exs test/foglet_bbs/tui/screens/post_composer_test.exs test/foglet_bbs/tui/screens/new_thread_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` |
| Full suite command | `rtk mix precommit` |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| COMPOSER-01 | Shared `EditorFrame` wraps editor/preview with focused/unfocused border styling | Widget + screen render | `rtk mix test test/foglet_bbs/tui/widgets/composer/editor_frame_test.exs` | No, Wave 0. [VERIFIED: `23-CONTEXT.md`] |
| COMPOSER-02 | Edit/Preview visible in render output for both modes | Widget + screen render | `rtk mix test test/foglet_bbs/tui/screens/post_composer_test.exs test/foglet_bbs/tui/screens/new_thread_test.exs` | Yes, extend. [VERIFIED: existing test files] |
| COMPOSER-03 | Counter states normal/warning/error use editor theme mappings | Widget tests | `rtk mix test test/foglet_bbs/tui/widgets/composer/editor_frame_test.exs` | No, Wave 0. [VERIFIED: `23-CONTEXT.md`, `lib/foglet_bbs/tui/presentation.ex`] |
| COMPOSER-04 | Reply quote/new-thread context collapse before required controls at 64x22 | Layout smoke + screen render | `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` | Yes, extend. [VERIFIED: `test/foglet_bbs/tui/layout_smoke_test.exs`] |
| COMPOSER-05 | Title/body input behavior remains width-aware and theme-routed | Existing widget + screen behavior tests | `rtk mix test test/foglet_bbs/tui/widgets/compose_test.exs test/foglet_bbs/tui/widgets/input/text_input_test.exs` | Yes. [VERIFIED: existing test files] |

### Sampling Rate

- **Per task commit:** Run the focused test file(s) touched by that task. [VERIFIED: existing GSD test practice in context]
- **Per wave merge:** Run all Phase 23 quick-run files listed above. [VERIFIED: `23-CONTEXT.md`]
- **Phase gate:** Run `rtk mix precommit` before `$gsd-verify-work`. [VERIFIED: `AGENTS.md`, `mix.exs`]

### Wave 0 Gaps

- [ ] `test/foglet_bbs/tui/widgets/composer/editor_frame_test.exs` — covers COMPOSER-01, COMPOSER-02, COMPOSER-03 widget-level contracts. [VERIFIED: `23-CONTEXT.md`]
- [ ] Extend `test/foglet_bbs/tui/screens/post_composer_test.exs` — shell presence, visible modes, context, counter, preview-in-shell. [VERIFIED: `23-CONTEXT.md`]
- [ ] Extend `test/foglet_bbs/tui/screens/new_thread_test.exs` — title/body shell integration and behavior preservation. [VERIFIED: `23-CONTEXT.md`]
- [ ] Extend `test/foglet_bbs/tui/layout_smoke_test.exs` — canonical dimensions `64x22`, `80x24`, `132x50`. [VERIFIED: `.planning/REQUIREMENTS.md`, `test/foglet_bbs/tui/layout_smoke_test.exs`]

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V2 Authentication | no direct change | Existing authenticated SSH session state remains unchanged. [VERIFIED: `23-CONTEXT.md`, `AGENTS.md`] |
| V3 Session Management | no direct change | Existing `Foglet.Sessions.*` and app routing remain unchanged. [VERIFIED: `23-CONTEXT.md`, `AGENTS.md`] |
| V4 Access Control | no direct change | Existing submit functions continue using current domain context paths; no new mutation path. [VERIFIED: `23-CONTEXT.md`, `lib/foglet_bbs/tui/screens/post_composer.ex`, `lib/foglet_bbs/tui/screens/new_thread.ex`] |
| V5 Input Validation | yes | Preserve existing title/body emptiness, max title length, reply max post length, and changeset/domain errors; add visual budget states only. [VERIFIED: `23-CONTEXT.md`, `lib/foglet_bbs/tui/screens/post_composer.ex`, `lib/foglet_bbs/tui/screens/new_thread.ex`] |
| V6 Cryptography | no | No secrets, tokens, or cryptographic flows are touched. [VERIFIED: `23-CONTEXT.md`] |

### Known Threat Patterns for Foglet TUI Composer

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| UI-only validation mistaken for enforcement | Tampering | Keep domain validation and context submit paths unchanged; counters are advisory display. [VERIFIED: `AGENTS.md`, `23-CONTEXT.md`] |
| Hidden authorization bypass through new submit path | Elevation of Privilege | Do not create new mutation APIs; retain `Foglet.Threads.create_thread/3` and existing reply submission path. [VERIFIED: `AGENTS.md`, `lib/foglet_bbs/tui/screens/new_thread.ex`, `lib/foglet_bbs/tui/screens/post_composer.ex`] |
| Terminal control/input confusion | Tampering | Preserve `Compose.translate_key/1` control filtering and screen-level Ctrl+S/Ctrl+C interception. [VERIFIED: `lib/foglet_bbs/tui/widgets/compose.ex`, `test/foglet_bbs/tui/widgets/compose_test.exs`] |

## Sources

### Primary (HIGH confidence)

- `.planning/REQUIREMENTS.md` — Phase 23 COMPOSER requirements and SSH-first milestone scope.
- `.planning/phases/23-composer-facelift/23-CONTEXT.md` — locked decisions D-01 through D-18, boundaries, code touch points, test anchors.
- `AGENTS.md` and `/Users/brendan.turner/.codex/RTK.md` — project constraints and required command prefix.
- `SCREENS.md` — Classic Modern BBS composer target sketch and `Composer.EditorFrame` primitive gap.
- `lib/foglet_bbs/tui/widgets/README.md` — widget structure, theme, and testing conventions.
- `lib/foglet_bbs/tui/widgets/compose.ex` — current shared body input render/key boundary.
- `lib/foglet_bbs/tui/widgets/input/text_input.ex` — title input wrapper contract.
- `lib/foglet_bbs/tui/widgets/post/markdown_body.ex` — preview renderer contract.
- `lib/foglet_bbs/tui/widgets/display/progress.ex` — optional compact progress behavior.
- `lib/foglet_bbs/tui/presentation.ex` — editor semantic theme mappings.
- `lib/foglet_bbs/tui/screens/post_composer.ex` and `lib/foglet_bbs/tui/screens/new_thread.ex` — current composer behavior.
- `vendor/raxol/lib/raxol/ui/components/input/multi_line_input.ex` — Raxol multiline input component state and behavior.
- `docs/raxol/core/ARCHITECTURE.md` — Raxol TEA/render/layout model.
- `test/foglet_bbs/tui/layout_smoke_test.exs` and widget tests — validation patterns.

### Secondary (MEDIUM confidence)

- https://textual.textualize.io/widgets/text_area/ — Textual TextArea current widget feature set and focus/soft-wrap/keybinding model.
- https://textual.textualize.io/widgets/input/ — Textual Input max-length and validation-on-change/submission/blur model.
- https://docs.rs/ratatui-textarea/latest/ratatui_textarea/ — Ratatui textarea features showing the complexity of multiline terminal editors.

### Tertiary (LOW confidence)

- None used as implementation authority.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — verified from `mix.exs`, `mix.lock`, `rtk mix deps`, and local module source.
- Architecture: HIGH — phase context locks the ownership boundaries and current code matches them.
- Pitfalls: HIGH — derived from existing code comments, tests, and locked decisions.
- External ecosystem comparison: MEDIUM — checked current official docs for Textual and docs.rs for ratatui-textarea, but Foglet's implementation is locked to local Raxol/Foglet widgets.

**Research date:** 2026-04-25  
**Valid until:** 2026-05-25 for local architecture; re-check external TUI docs before using them to justify new dependencies.
