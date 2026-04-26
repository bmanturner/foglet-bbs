# Phase 23: Composer Facelift - Specification

**Created:** 2026-04-25
**Ambiguity score:** 0.13 (gate: <= 0.20)
**Requirements:** 7 locked

## Goal

`NewThread` and `PostComposer` change from plain-line composition screens into a shared Classic Modern BBS editor experience with a visible focused editor shell, explicit Edit/Preview mode control, state-colored character counters, compact composition context, and preserved keyboard-first composer behavior.

## Background

Phase 23 is part of the v1.3 SSH-first TUI facelift. `SCREENS.md` defines the target composer shape: `Composer.EditorFrame` wraps the existing `MultiLineInput`, Edit/Preview is visible as a tab or segmented control, character budgets use normal/warning/error treatment, reply mode shows compact quoted context, and new-thread mode shows board/title context.

Current `Foglet.TUI.Screens.PostComposer` already stores `%PostComposer.State{}` in `state.screen_state[:post_composer]`, uses `Raxol.UI.Components.Input.MultiLineInput`, toggles `:edit` and `:preview` with Tab, renders markdown preview through `Post.MarkdownBody`, enforces `max_post_length`, preserves structured domain errors, and returns to `PostReader` after successful reply submission. Current `Foglet.TUI.Screens.NewThread` already has a board-selection step, `%NewThread.State{}` for title/body composition, `TextInput` title editing, `MultiLineInput` body editing, Tab focus/mode behavior, markdown preview, origin-aware cancel, and thread creation validation.

The visible gap is that both composer screens still feel like loose text rows. `PostComposer` shows reply context, raw editor rows, error text, and a plain `N / max chars` footer; `NewThread` shows a plain title row, plain body label, raw editor rows, and a plain title counter. There is no `Composer.EditorFrame`, no visible mode tab/segmented control beyond key hints, no shared composer shell, and no state-colored character counter contract across title and body.

## Requirements

1. **Shared editor shell**: Both new-thread and reply composition render inside a shared Classic Modern BBS composer shell.
   - Current: `NewThread` and `PostComposer` independently assemble loose title/context/body/counter rows around `Compose.render_input/4`.
   - Target: Both screens expose the same visible composer shell shape, with optional title or reply context slots and a focused editor area for the body.
   - Acceptance: Render tests for `NewThread` compose mode and `PostComposer` edit mode find a common shell marker or shared `Composer.EditorFrame` output, and source inspection shows both screens delegate body editor framing through a shared composer widget boundary.

2. **Visible editor frame**: The body editor has an explicit boundary and focused/unfocused styling.
   - Current: `Compose.render_input/4` renders `MultiLineInput` lines as plain themed text with an injected cursor block and no surrounding editor boundary.
   - Target: The editor body is wrapped by `Composer.EditorFrame` or an equivalent composer widget that shows an editor boundary, uses focused styling when editing, and uses unfocused styling when previewing or when the title field owns focus.
   - Acceptance: Focused and unfocused render tests find distinct theme-routed frame treatment, and no hardcoded terminal color atoms are introduced in the composer widget or composer screens.

3. **Visible Edit/Preview control**: Edit and preview mode are visible in the composer body, not only in command hints.
   - Current: Both screens toggle preview with Tab, but the active mode is primarily inferred from the key bar and changed content.
   - Target: Both screens render an Edit/Preview tab or segmented control showing the active mode in the composer shell.
   - Acceptance: Render tests for both screens in `:edit` and `:preview` modes find visible `Edit` and `Preview` labels and can distinguish the active mode from rendered text or style data.

4. **Character budget counters**: Title and body budgets show text counters with normal, warning, and over-limit states where a budget exists.
   - Current: `NewThread` shows a dim title `N / cap chars` counter; `PostComposer` shows a dim body `N / max chars` counter; body over-limit is enforced in `PostComposer`; budget styling is not shared.
   - Target: New-thread title and body, and reply body, show compact text counters routed through shared composer budget treatment. Counters use normal, warning, and error styling. A progress bar is optional and not required for Phase 23.
   - Acceptance: Tests cover below-warning, warning-threshold, and over-limit states for budget counters and verify the expected theme slots are used. Tests also verify title max-length behavior and post body max-length behavior remain intact.

5. **Mode-specific context**: New-thread and reply composition show the right compact context, and nonessential context collapses first at 64x22.
   - Current: `PostComposer` shows `Replying to @handle` plus up to five quoted body lines before the editor; `NewThread` shows a title line and body label, while board context is mostly in chrome/current state.
   - Target: Reply composition shows compact quoted context in the composer shell. New-thread composition shows board context plus title context. At 64x22, mode, editor, and compact counter remain visible while quote, board, or other nonessential context collapses before the writing surface becomes unusable.
   - Acceptance: Minimum-size render tests at 64x22 find visible mode control, editor body, and compact budget text for both screens; reply quote or board context may be shortened, but it must not overlap or push the editor off screen.

6. **Preview stays in the same shell**: Preview mode reuses the composer shell and existing markdown rendering.
   - Current: Preview replaces the raw body editor with `MarkdownBody.render/3`, but mode/context shell treatment is not explicit or shared.
   - Target: Preview mode remains inside the same composer shell, preserves the relevant title or reply context, and uses the existing markdown rendering path rather than a new post-rendering pipeline.
   - Acceptance: Preview render tests for both screens find the shared shell, visible active Preview mode, existing markdown-rendered body content, and relevant title or reply context.

7. **Behavior preservation**: The facelift does not change composer input, navigation, validation, domain, or resize behavior.
   - Current: Tests cover `TextInput` title editing, `MultiLineInput` body editing, Tab focus/mode rules, Ctrl+S submit, Ctrl+C/Esc cancel, policy/locked errors, max-length handling, reply transition back to `PostReader`, new-thread transition back to `ThreadList`, and composer draft preservation across resize gate cycles.
   - Target: All existing behavior remains intact after the visual facelift; Phase 23 changes presentation and shared composer widgets only.
   - Acceptance: Existing `post_composer_test.exs`, `new_thread_test.exs`, `app_test.exs` resize-gate composer tests, and composer layout smoke tests continue to pass after the facelift.

## Boundaries

**In scope:**
- `Composer.EditorFrame` or equivalent shared composer widget for visible editor boundaries, mode marker, focused/unfocused styling, and budget counter placement.
- Applying the shared composer shell to both `Foglet.TUI.Screens.NewThread` compose mode and `Foglet.TUI.Screens.PostComposer`.
- Visible Edit/Preview tab or segmented control for both composer screens.
- State-colored text counters for new-thread title, new-thread body, and reply body budgets where the existing limits apply.
- Compact reply quote context and new-thread board/title context, with 64x22-safe collapse behavior.
- Preservation tests and layout-smoke coverage at 64x22, 80x24, and at least one wide/tall terminal size.

**Out of scope:**
- Changing thread creation, reply creation, message-number allocation, posting policy, or authorization behavior - Phase 23 is a TUI presentation facelift.
- Replacing `TextInput` or `MultiLineInput` editing semantics - existing input components remain the editing engines.
- Building a full final-post mock preview using `PostCard` - preview uses existing markdown body rendering inside the composer shell.
- Adding autosave, draft persistence, attachments, polls, mentions, rich text editing, or live collaboration - these are new product workflows, not this facelift.
- Reworking board selection in the `NewThread` board step - Phase 23 targets the composition surface, not board browsing.
- Browser workflows - Foglet remains SSH-first for this milestone.
- Mandatory progress bars for character budgets - state-colored text counters are required; progress is optional.

## Constraints

- The hard minimum terminal size is 64x22; 80x24 is the compact design target; wider terminals may progressively show richer context.
- Mode, editor, and compact budget text remain visible at 64x22 for both composer screens.
- Colors and styles route through `Foglet.TUI.Theme` and `Foglet.TUI.Presentation.theme_mappings().editor`; no new hardcoded terminal color atoms in facelifted composer code.
- `TextInput` and `MultiLineInput` remain the editing engines, and `Compose.render_input/4` or its successor remains width-aware for cursor insertion.
- Character limits remain character-count policy limits, not display-width limits.
- Render helpers stay pure over already-loaded screen state; domain side effects remain in `Foglet.Threads` and `Foglet.Posts`.

## Acceptance Criteria

- [ ] Both `NewThread` compose mode and `PostComposer` render through a shared composer shell or `Composer.EditorFrame` boundary.
- [ ] Body editor rendering shows a visible frame/boundary with distinguishable focused and unfocused states using theme-routed styles.
- [ ] Both screens show visible `Edit` and `Preview` controls, and the active mode is distinguishable in render output.
- [ ] New-thread title, new-thread body, and reply body counters show compact text budgets with normal, warning, and error states where limits apply.
- [ ] At 64x22, both composer screens keep mode control, editor body, and compact budget text visible without text overlap or out-of-bounds positioned elements.
- [ ] Reply composition shows compact quoted context; new-thread composition shows board and title context, with context collapsing before the editor at minimum size.
- [ ] Preview mode stays inside the composer shell and uses existing markdown rendering for body content.
- [ ] Existing title/body editing, Tab rules, submit/cancel transitions, validation errors, domain errors, and resize-gate draft preservation remain covered and passing.
- [ ] Phase 23 visual contracts are covered at 64x22, 80x24, and at least one wide/tall terminal size.
- [ ] `rtk mix precommit` passes after implementation.

## Ambiguity Report

| Dimension           | Score | Min   | Status | Notes |
|---------------------|-------|-------|--------|-------|
| Goal Clarity        | 0.93  | 0.75  | met    | Full composer shell on both composer screens is locked. |
| Boundary Clarity    | 0.86  | 0.70  | met    | Domain changes, new workflows, board-step redesign, browser UI, and mandatory progress bars are excluded. |
| Constraint Clarity  | 0.80  | 0.65  | met    | 64x22, 80x24, theme routing, character-count policy, and input component preservation are locked. |
| Acceptance Criteria | 0.86  | 0.70  | met    | Pass/fail checks cover shared shell, visible modes, counters, context, preview, behavior preservation, and size contracts. |
| **Ambiguity**       | 0.13  | <=0.20| met    | Ready for discuss-phase. |

Status: met = dimension meets minimum; below minimum = planner treats as assumption.

## Interview Log

| Round | Perspective | Question summary | Decision locked |
|-------|-------------|------------------|-----------------|
| 1 | Researcher | Which visible composer change matters most? | All major visible pieces matter: shared focused shell, editor frame, visible mode control, counters, and context. |
| 1 | Researcher | What remains visible at 64x22? | Mode, editor, and compact counter remain visible; quote/board context collapses first. |
| 1 | Researcher | What does preview mode guarantee? | Preview stays inside the same composer shell and uses existing markdown rendering with relevant context preserved. |
| 2 | Researcher + Simplifier | How strict are character budgets? | Text counters must show normal, warning, and error states; progress bars are optional. |
| 2 | Researcher + Simplifier | What is the irreducible floor? | Both new-thread and reply screens must receive the full composer shell; no partial-screen shipping. |
| 2 | Researcher + Simplifier | Which behavior is non-negotiable? | Preserve all composer behavior: input, Tab rules, preview, submit/cancel, validation, draft/resize preservation, and domain errors. |

---

*Phase: 23-composer-facelift*
*Spec created: 2026-04-25*
*Next step: $gsd-discuss-phase 23 - implementation decisions (how to build what's specified above)*
