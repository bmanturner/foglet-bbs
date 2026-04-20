# Phase 4: Composer & thread creation end-to-end — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in 04-CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-20
**Phase:** 04-composer-thread-creation-end-to-end
**Workstream:** phase-03-polish (v1.0.1)
**Areas discussed:** C-routing from ThreadList, Post-success navigation, Cancel navigation, Module consolidation, Title character limit

---

## A — [C] routing from ThreadList

### A1. How should [C] start the new-thread flow from inside a board?

| Option | Description | Selected |
|--------|-------------|----------|
| Skip picker, pre-fill board | Set ss.board = state.current_board, jump straight to :compose. No load_boards_for_new_thread dispatch. | ✓ |
| Show picker, current preselected | Dispatch load_boards, land on picker with current board highlighted. | |
| Always show picker fresh | Same as main_menu path with no preselection. | |

**User's choice:** Skip picker, pre-fill board
**Notes:** Fewest keystrokes; matches mental model (user is already inside General, doesn't need to pick).

### A2. Exact replacement for broken thread_list.ex:80-82 branch

| Option | Description | Selected |
|--------|-------------|----------|
| Delete + new-thread init | Remove current handler. New handler inits :new_thread with step: :compose, board: state.current_board. | ✓ |
| Keep branch, hard-fail safely | Keep :post_composer route but refuse to submit when current_thread is nil. | |
| Add a MainMenu bounce | Route [C] to :main_menu and re-dispatch. | |

**User's choice:** Delete + new-thread init
**Notes:** Mimics main_menu pattern minus the load_boards dispatch.

---

## B — Post-success navigation

### B1. After successful new-thread submit, where does the user land?

| Option | Description | Selected |
|--------|-------------|----------|
| Thread list (per REQ) | Back to :thread_list with current_board preserved, dispatch load_threads. | |
| Post reader (current code) | Open :post_reader showing new thread's opening post. | |
| Thread list, highlight new row | Back to :thread_list, set selected_index: 0 so new thread is pre-selected. | ✓ |

**User's choice:** Thread list, highlight new row
**Notes:** Matches REQ-01 while also giving the user the new thread as one-Enter-away.

### B2. After successful reply submit, which post is selected?

| Option | Description | Selected |
|--------|-------------|----------|
| Jump to the new reply | Set selected_post_index to the last post after reload. | ✓ |
| Stay on replied-to post | Keep selected_post_index unchanged. | |
| Jump to the original post | Reset to selected_post_index: 0. | |

**User's choice:** Jump to the new reply
**Notes:** Visible confirmation that the reply landed.

---

## C — Cancel navigation

### C1. How does cancel decide where to go?

| Option | Description | Selected |
|--------|-------------|----------|
| Origin-aware via screen_state | Stash origin in screen_state on entry; cancel reads it. | ✓ |
| Origin-aware via new state field | Add top-level state.composer_origin. | |
| Hardcoded per path | Each entry point sets its own cancel target field. | |

**User's choice:** Origin-aware via screen_state
**Notes:** Keeps origin scoped to the composer's state bag; cleanest fix.

### C2. Confirm modal on cancel when draft is non-empty?

| Option | Description | Selected |
|--------|-------------|----------|
| Silent discard | Ctrl+C / Esc always discards immediately. | ✓ |
| Confirm if non-empty | Modal asking 'Discard draft?' | |
| Auto-save draft | Stash in state, restore on re-entry. | |

**User's choice:** Silent discard
**Notes:** Matches current behavior; classic BBS feel; no modal friction.

---

## D — Module consolidation

### D1. Consolidation scope for Phase 4

| Option | Description | Selected |
|--------|-------------|----------|
| Extract shared helpers only | New Foglet.TUI.Widgets.Compose module with translate_key + MultiLineInput body renderer. | ✓ |
| Full merge into one screen | Collapse NewThread into PostComposer with mode: :reply | :new_thread. | |
| Defer — fix bugs only | Touch only what COMPOSE-01/02/03 require. | |
| Extract shared + Phase 2 bridge | Option 1 plus explicit Phase 2 preview dependency. | |

**User's choice:** Extract shared helpers only
**Notes:** Preview alignment follow-up captured in D2 below.

### D2. Composer preview alignment with Phase 2

| Option | Description | Selected |
|--------|-------------|----------|
| Call Post.MarkdownBody | Preview calls Post.MarkdownBody.render/3 directly. Requires Phase 2 first. | ✓ |
| Keep duplicated preview | Composers keep their own render_markdown_tuples. | |
| Extract to shared helper now | Move render_markdown_tuples into Widgets.Compose. | |

**User's choice:** Call Post.MarkdownBody
**Notes:** Single source of truth for terminal markdown; creates hard execute-order dependency on Phase 2 (acceptable — Phase 2 plans committed during this discussion).

---

## E — Title character limit (added follow-up after D)

### E1. Handling the 300-char changeset limit in NewThread title field

| Option | Description | Selected |
|--------|-------------|----------|
| TUI cap + counter | Enforce 300-char cap in TUI, show N/300 counter. | |
| Rely on changeset only | No TUI cap, show error modal on submit. | |
| New config key + cap | Add max_thread_title_length config, mirror max_post_length pattern. | ✓* |

**User's choice:** New config key + cap, BUT default to **60** (not 300)
**Notes:** User-specified default of 60 chars. Tighter than changeset backstop because thread rows must fit title + metadata on 80-col terminals. Seed via priv/repo/seeds.exs.

### E2. Should the Thread changeset's validate_length(:title, max: 300) change?

| Option | Description | Selected |
|--------|-------------|----------|
| Keep 300 as backstop | TUI enforces soft config cap, changeset keeps 300 as DB hard cap. | ✓ |
| Lower to match config | Change validate_length to max: 60. | |
| Read from config | Changeset calls Foglet.Config.get! at runtime. | |

**User's choice:** Keep 300 as backstop
**Notes:** Sysop can raise config up to 300 without schema migration.

---

## Claude's Discretion

- Reply-jump implementation (D-05) — command flag vs post-reload inline computation vs new command variant
- Origin stash helper shape — helper function on Widgets.Compose or inline in each screen
- Legacy state.composer_draft field — remove if trivial, else leave
- NewThread pre-filled-board code shape — new boards_source flag vs implicit inference

## Deferred Ideas

- Full PostComposer + NewThread module merge
- Draft persistence across cancel/resume
- Sysop in-TUI toggle for max_thread_title_length (belongs in Milestone 8)
- Submit-error UX rework (inline banner vs modal)
- Legacy state.composer_draft field cleanup
- Quote-preview UX changes in reply flow
