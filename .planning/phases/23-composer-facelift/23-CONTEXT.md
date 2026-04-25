# Phase 23: composer-facelift - Context

**Gathered:** 2026-04-25 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 23 refreshes `Foglet.TUI.Screens.NewThread` compose mode and `Foglet.TUI.Screens.PostComposer` into the Classic Modern BBS composer shape from `SCREENS.md`: both composer screens use a shared visible editor shell, explicit Edit/Preview control, theme-routed character budget counters, mode-specific context, and existing markdown preview behavior inside the same shell.

Phase 23 does NOT change thread/reply creation, board selection, message-number allocation, posting policy, authorization behavior, autosave/draft persistence, attachments, polls, mentions, rich text editing, browser workflows, or the `TextInput`/`MultiLineInput` editing engines. Existing keyboard-first behavior, validation, submit/cancel transitions, and resize-gate draft preservation remain intact.

</domain>

<decisions>
## Implementation Decisions

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

### Folded Todos

None — `gsd-sdk query todo.match-phase 23` returned `todo_count: 0`.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Locked Phase Scope

- `.planning/phases/23-composer-facelift/23-SPEC.md` — Locked Phase 23 requirements, boundaries, constraints, acceptance criteria, ambiguity report, and interview decisions.
- `.planning/ROADMAP.md` §Phase 23 — Milestone position, dependency on Phase 22, requirements `COMPOSER-01` through `COMPOSER-05`, and success criteria.
- `.planning/REQUIREMENTS.md` §Composer — Requirement IDs `COMPOSER-01`, `COMPOSER-02`, `COMPOSER-03`, `COMPOSER-04`, `COMPOSER-05`.
- `SCREENS.md` §New Thread And Post Composer — Classic Modern BBS composer target sketch, Edit/Preview segment, counter/progress guidance, quote context, and primitive gap notes.
- `SCREENS.md` §Widget And Primitive Work — `Composer.EditorFrame` primitive description.
- `SCREENS.md` §Design Principles and §Chosen Direction — Terminal-native, keyboard-first, Unicode-capable Classic Modern BBS direction.

### Dependency Contracts

- `.planning/phases/16-unicode-width-foundation/16-CONTEXT.md` — `Foglet.TUI.TextWidth` width-helper contract and character-count vs display-width boundary.
- `.planning/phases/17-theme-and-mode-metadata/17-CONTEXT.md` — `:bbs` mode metadata and editor theme mapping contract.
- `.planning/phases/18-chrome-v2/18-CONTEXT.md` — `Chrome.ScreenFrame` composition boundary and composer breadcrumb migration precedent.
- `.planning/phases/20-rich-rows-and-thread-flow/20-CONTEXT.md` — Width-safe glyph/theme testing precedent and `layout_smoke_test.exs` size-contract pattern.
- `.planning/phases/22-post-reader-facelift/22-CONTEXT.md` — Latest post/preview boundary precedent: preserve markdown rendering, keep Phase 23 composer work separate from `PostCard` reader work.

### Existing Code Touch Points

- `lib/foglet_bbs/tui/screens/post_composer.ex` — Reply composer screen to facelift. Preserve `handle_key/2`, max-length enforcement, domain error modal behavior, reply quote data, markdown preview, and return-to-reader flow.
- `lib/foglet_bbs/tui/screens/post_composer/state.ex` — Existing `%PostComposer.State{}` with `mode`, `reply_to`, `error`, `input_state`, and `origin`.
- `lib/foglet_bbs/tui/screens/new_thread.ex` — New-thread wizard compose step to facelift. Preserve board step, title/body focus rules, body preview toggle, submit/cancel behavior, and domain error handling.
- `lib/foglet_bbs/tui/screens/new_thread/state.ex` — Existing `%NewThread.State{}` with board/title/body/focus/mode/error fields.
- `lib/foglet_bbs/tui/widgets/compose.ex` — Existing shared key translation and width-aware `MultiLineInput` rendering; likely reused or evolved under `EditorFrame`.
- `lib/foglet_bbs/tui/widgets/input/text_input.ex` — Existing title input wrapper and theme-routed single-line input.
- `lib/foglet_bbs/tui/widgets/post/markdown_body.ex` — Existing markdown preview renderer to keep inside the shell.
- `lib/foglet_bbs/tui/widgets/display/progress.ex` — Optional compact progress primitive; must remain secondary to text counters.
- `lib/foglet_bbs/tui/presentation.ex` — Editor theme-slot mapping (`focused`, `unfocused`, `input`, `counter`, `counter_warning`, `counter_error`).
- `lib/foglet_bbs/tui/theme.ex` — Theme slots used by composer widget rendering; no hardcoded color atoms.
- `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex` — Screen chrome boundary. Both composer screens continue rendering inside `ScreenFrame`.

### Test Anchors

- `test/foglet_bbs/tui/widgets/composer/editor_frame_test.exs` — New widget test file if `EditorFrame` lands under `widgets/composer/`.
- `test/foglet_bbs/tui/widgets/compose_test.exs` — Existing input translation and width-aware cursor tests; extend only if the shared render boundary moves.
- `test/foglet_bbs/tui/screens/post_composer_test.exs` — Existing reply composer behavior tests; extend for shell, mode control, counters, context, and preview.
- `test/foglet_bbs/tui/screens/new_thread_test.exs` — Existing new-thread behavior tests; extend for shell, title/body counters, mode control, context, and preview.
- `test/foglet_bbs/tui/layout_smoke_test.exs` — Existing positioned-render harness; add Phase 23 composer size-contract coverage.
- `test/foglet_bbs/tui/app_test.exs` — Existing resize-gate composer draft preservation coverage; keep passing.
- `test/foglet_bbs/tui/presentation_test.exs` — Reference for editor mapping assertions if a new composer widget consumes `Presentation.theme_mappings/0`.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- `Foglet.TUI.Widgets.Compose.translate_key/1` already centralizes body editor key translation for both composer screens.
- `Foglet.TUI.Widgets.Compose.render_input/4` already renders `MultiLineInput` state through Raxol DSL text rows and uses `Foglet.TUI.TextWidth.split_at/2` for Unicode-safe cursor insertion.
- `PostComposer.State.new/1` and `NewThread.State.new/1` already initialize `MultiLineInput` with width/height options and preserve screen-local state in `%State{}` structs.
- `NewThread` already uses the project-local `Foglet.TUI.Widgets.Input.TextInput` wrapper for title editing, including `max_length`.
- `Post.MarkdownBody.render/3` already handles composer preview rendering; both screens use it today.
- `Foglet.TUI.Presentation.theme_mappings().editor` already defines the slots Phase 23 needs: focused, unfocused, input, counter, counter_warning, and counter_error.
- `Foglet.TUI.Widgets.Display.Progress.render/2` already provides a theme-routed compact segmented progress option, but it is optional for this phase.

### Established Patterns

- TUI widgets live under `lib/foglet_bbs/tui/widgets/<bucket>/`, accept `theme:` explicitly, document decision IDs in moduledocs, and avoid hardcoded color atoms.
- Screen render functions stay pure over already-loaded state; domain mutations remain in `Foglet.Threads` and `Foglet.Posts` through existing screen submit functions.
- Input components remain stateful structs stored inside screen-local `%State{}` structs; screens own key routing and widget state updates.
- Width-sensitive layout uses `Foglet.TUI.TextWidth`, especially when rendering glyphs, truncation, or cursor placement.
- Size contracts for v1.3 facelift screens live in `test/foglet_bbs/tui/layout_smoke_test.exs` at `64x22`, `80x24`, and `132x50`.
- Existing behavior tests are extended in place rather than replaced by screenshots.

### Integration Points

- `PostComposer.render/1` should become mostly shell composition: collect reply context, body editor or markdown preview, errors, and counter data; pass them into `EditorFrame`; keep `ScreenFrame.render/4` and key hints.
- `NewThread.render_compose_step/2` should similarly collect board/title context, title input, body editor or markdown preview, errors, and counters; pass body/shell rendering through the same composer widget.
- `Compose.render_input/4` can remain as the low-level body line renderer that `EditorFrame` calls for edit mode, or its logic can move behind a successor while preserving tests and width-aware cursor behavior.
- `PostComposer.handle_key/2` and `NewThread.handle_key/2` should not be rewritten beyond what the visual shell requires; their clause order is load-bearing for Ctrl+S/Ctrl+C before `MultiLineInput` fallback.
- `App` routing and Chrome V2 breadcrumbs for `:new_thread` and `:post_composer` remain unchanged.

</code_context>

<specifics>
## Specific Ideas

- Follow the `SCREENS.md` composer sketch: a visible editor boundary, an in-shell Edit/Preview segment, compact budget text, optional `▰▱` progress only when space allows, and reply quote treatment such as `┃`.
- The 64x22 rule means context collapses before the controls needed to keep writing: mode control, editor/preview body, and compact counter stay visible first.
- Keep preview deliberately lightweight: existing markdown rendering inside the composer shell, not a final post-card mockup.
- Keep command behavior familiar: Tab, Ctrl+S, Ctrl+C, Esc, and current body/title input rules remain the user's muscle memory.

</specifics>

<deferred>
## Deferred Ideas

- Autosave or persisted drafts — future product workflow, not Phase 23.
- Attachments, polls, mentions, rich text editing, or collaborative editing — future composer capabilities, not this facelift.
- Reworking the `NewThread` board-selection step — out of scope; Phase 23 targets the compose surface.
- Building a full final-post preview via `PostCard` — explicitly out of scope; preview remains markdown body rendering inside the shell.
- Screenshot-based terminal fixtures — Phase 23 follows existing code/layout tests unless a later visual QA phase adds screenshots.

### Reviewed Todos (not folded)

None — no matching todos for this phase.

</deferred>

---

*Phase: 23-composer-facelift*
*Context gathered: 2026-04-25*
