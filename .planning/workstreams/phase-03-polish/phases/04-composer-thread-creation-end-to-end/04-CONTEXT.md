# Phase 4: Composer & thread creation end-to-end — Context

**Gathered:** 2026-04-20
**Status:** Ready for planning
**Workstream:** phase-03-polish (v1.0.1)

<domain>
## Phase Boundary

Fix the three composer entry points so they route to the right screen, land the user on the right screen after submit or cancel, and kill the broken `current_thread: nil → :post_composer` branch in `thread_list.ex`. Also de-duplicate ~80 LOC of identical plumbing (`translate_key/1`, MultiLineInput body rendering) between `PostComposer` and `NewThread` by extracting a shared `Foglet.TUI.Widgets.Compose` helper module.

**In scope:**
- `[C]` from `ThreadList` → routes correctly to new-thread flow (COMPOSE-01).
- `[R]` from `PostReader` → already wired to `PostComposer`; verify and harden navigation (COMPOSE-02).
- Broken `thread_list.ex:80-82` branch deleted (COMPOSE-03).
- Shared composer helper module (`Foglet.TUI.Widgets.Compose`) extracted; both screens import.
- Preview mode in both composers calls `Post.MarkdownBody.render/3` (from Phase 2).
- Origin-aware cancel targets.
- Thread title length cap (new config key, default 60).

**Explicitly NOT in scope:**
- Merging `PostComposer` and `NewThread` into one module (deferred).
- Draft persistence across sessions (deferred).
- Sysop in-TUI toggle for `max_thread_title_length` (edit via `mix foglet.config.set`).
- Quote-preview UX changes in reply flow (preserve current `> line` prefix).
- Any markdown rendering changes — rely on Phase 2's `Post.MarkdownBody` widget.

**Critical cross-phase dependency:** Phase 4 plans depend on Phase 2 execution completing. `Post.MarkdownBody.render/3` must exist before Phase 4 composer preview integration can land. Phase 2 plans committed as `5e8acbd` — execute Phase 2 before executing Phase 4.

</domain>

<decisions>
## Implementation Decisions

### [C]-from-ThreadList routing

- **D-01:** `ThreadList.handle_key(%{key: :char, char: c}, state) when c in ["c", "C"]` inits `:new_thread` screen_state with `step: :compose`, `board: state.current_board`, `boards: nil` (picker not shown), and navigates. No `{:load_boards_for_new_thread}` command is dispatched — the board is already known. Mirrors `MainMenu`'s [C] pattern minus the load_boards dispatch.
- **D-02:** The broken `thread_list.ex:80-82` branch that routes to `:post_composer` with `current_thread: nil` is deleted entirely. `:post_composer` is only reachable from `PostReader`'s `[R]` handler after Phase 4 lands. No other callers.
- **D-03:** `NewThread.handle_board_key(%{key: :enter}, ...)` path remains unchanged for the `MainMenu → NewThread` entry (board-picker step). The picker still works for cross-board thread creation from the main menu.

### Post-success navigation

- **D-04:** `NewThread.do_submit/2` on success navigates to `:thread_list` (not `:post_reader`). Dispatches `{:load_threads, board.id}` so the new thread reloads. Sets `screen_state[:thread_list][:selected_index] = 0` so the new thread is pre-selected (threads sort by `last_post_at` desc — new thread is at top). Clears `screen_state[:new_thread]`. Sets `current_board: board` so ThreadList has the board available on arrival.
- **D-05:** `PostComposer.do_submit/3` on success navigates to `:post_reader` (unchanged target) + reloads posts via `{:load_posts, thread.id}`. After the post reload, `selected_post_index` is set to the **last post** in the reloaded list (the user's new reply). This requires either computing the index in `PostReader.load_posts/2` when a flag is set, or handling it in the command return path. Planner's choice — see Claude's Discretion.

### Cancel navigation

- **D-06:** Cancel is origin-aware. On entry into either composer screen, the navigating screen stashes `origin: <screen_name>` in the composer's `screen_state` map:
  - `ThreadList`'s `[C]` handler sets `screen_state[:new_thread].origin = :thread_list`
  - `MainMenu`'s `[C]` handler sets `screen_state[:new_thread].origin = :main_menu`
  - `PostReader`'s `[R]` handler sets `screen_state[:post_composer].origin = :post_reader`
- **D-07:** `PostComposer.cancel/1` and `NewThread.handle_compose_key` (Ctrl+C / Esc) read `ss.origin` and navigate to that screen (default `:main_menu` if missing). Board-step cancel in `NewThread` still routes to `:main_menu` (unchanged — that step only reachable from MainMenu path).
- **D-08:** Silent discard on cancel. No modal confirm. Matches current behavior and classic BBS feel.

### Module consolidation

- **D-09:** New shared module `Foglet.TUI.Widgets.Compose` at `lib/foglet_bbs/tui/widgets/compose.ex`. Exposes:
  - `translate_key/1` — Raxol event map → `MultiLineInput.update/2` message (currently duplicated verbatim in both screens)
  - `render_input_as_text/3` or equivalent — MultiLineInput state → column of themed `text/2` elements with cursor `█` injection
- **D-10:** Both `PostComposer` and `NewThread` import/alias `Foglet.TUI.Widgets.Compose` and delegate. The private copies of `translate_key` and the body renderer in both screens are removed.
- **D-11:** Preview mode in both composers calls `Foglet.TUI.Widgets.Post.MarkdownBody.render/3` directly (from Phase 2). The private `render_markdown_tuples/2` copies in `post_composer.ex` and `new_thread.ex` are removed. This creates a hard execute-order dependency on Phase 2.
- **D-12:** Full merge of `PostComposer` + `NewThread` into a single mode-switched module is **deferred** — noted for a later cleanup milestone, not this phase.

### Title character limit

- **D-13:** New `Foglet.Config` key `max_thread_title_length`, default **60**. Seeded via `priv/repo/seeds.exs` using the same pattern as `max_post_length` (tuple `{"max_thread_title_length", 60, "Maximum thread title length in characters (D-13)"}`).
- **D-14:** `NewThread` title input handler enforces the config value: keystrokes that would push `title_input` past the cap are rejected at the key-handler level. The title line displays an `"N / {cap} chars"` counter on the compose step (paired with the existing body counter from `PostComposer`).
- **D-15:** `Foglet.Threads.Thread.changeset/2` keeps `validate_length(:title, min: 1, max: 300)` unchanged — acts as a hard schema backstop so sysops can raise the TUI config (up to 300) without a migration. Config 60 = soft TUI cap. Changeset 300 = hard DB cap.

### Claude's Discretion

- **Reply-jump implementation:** D-05 requires selecting the last post after reply submit. Options: (A) add a `jump_to_last: true` flag to the `{:load_posts, thread_id}` command variant that PostReader handles; (B) inspect `state.current_post_list` length after `load_posts` returns and set `selected_post_index` inline; (C) a new `{:load_posts_jump_last, thread_id}` command. Any of these is acceptable. Constraint: do not race the DB reload (must be index-after-reload, not assumed-count-before-submit).
- **Origin stash location:** D-06 places `origin` inside the composer's screen_state map (not on top-level `state`). Planner may choose to add a small helper on `Foglet.TUI.Widgets.Compose` like `with_origin(screen_state, origin)` to DRY the stash logic across the three call sites.
- **Legacy `state.composer_draft` field:** Not addressed in this phase. The field is set to `nil` on entry/exit and never read for draft text (comment in `post_composer.ex:12-14` confirms). Planner may leave it as-is or remove it in the same diff if it's trivial — do not let it block phase scope.
- **NewThread pre-filled-board entry point — code shape:** D-01 says init `ss.board = state.current_board`. Planner decides whether to add a `boards_source: :prefilled | :picker` flag on the screen_state, or infer it from `step == :compose && boards == nil`, or another mechanism. All are viable.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Workstream Requirements and Roadmap
- `.planning/workstreams/phase-03-polish/REQUIREMENTS.md` — COMPOSE-01, COMPOSE-02, COMPOSE-03 requirements; locked decisions (widget style, no new deps)
- `.planning/workstreams/phase-03-polish/ROADMAP.md` — Phase 4 success criteria; dependency on Phase 1

### Prior Phase Context
- `.planning/workstreams/phase-03-polish/phases/01-widget-foundation-theme-screen-chrome/01-CONTEXT.md` — Widget namespace (`Foglet.TUI.Widgets.*`), theme slots, `ScreenFrame` API, `Post.MarkdownBody` stub decision (D-10, D-11)
- `.planning/workstreams/phase-03-polish/phases/02-markdown-rendering-correctness/02-CONTEXT.md` — `Post.MarkdownBody` and `Post.PostCard` design, theme mapping for styles
- `.planning/workstreams/phase-03-polish/phases/02-markdown-rendering-correctness/02-01-PLAN.md` — `Post.MarkdownBody` implementation plan (consumed by D-11)
- `.planning/workstreams/phase-03-polish/phases/02-markdown-rendering-correctness/02-02-PLAN.md` — `Post.PostCard` implementation plan
- `.planning/workstreams/phase-03-polish/phases/02-markdown-rendering-correctness/02-03-PLAN.md` — PostReader integration (reference for how composer preview should call MarkdownBody)

### Raxol DSL Constraint
- `lib/foglet_bbs/tui/widgets/chrome/` — canonical examples of function-form widget DSL (`column/row/box do...end` block macros). Use these as reference instead of the phantom `memory/feedback_raxol_modern_dsl.md` flagged by Phase 2 planner.

### Existing Code to Modify
- `lib/foglet_bbs/tui/screens/thread_list.ex` — `handle_key` for `"c"/"C"` (D-01, D-02); origin stash
- `lib/foglet_bbs/tui/screens/post_reader.ex` — existing `[R]` handler at lines 60-75; add origin stash
- `lib/foglet_bbs/tui/screens/main_menu.ex` — existing `[C]` handler at lines 43-46; add origin stash (value `:main_menu`)
- `lib/foglet_bbs/tui/screens/post_composer.ex` — `cancel/1` origin-aware; `do_submit/3` last-post jump; remove private `translate_key` + `render_input_as_text` + `render_markdown_tuples`
- `lib/foglet_bbs/tui/screens/new_thread.ex` — `handle_compose_key` Ctrl+C/Esc origin-aware; `do_submit/2` success nav → thread_list; title-length cap in `handle_compose_key` (focused: :title) path; remove "coming soon" stub (Phase 2 complete); remove private `translate_key` + `render_body` + `render_markdown_tuples`; title counter line

### New Files to Create
- `lib/foglet_bbs/tui/widgets/compose.ex` — new `Foglet.TUI.Widgets.Compose` helper module (D-09, D-10)

### Domain and Config
- `lib/foglet_bbs/threads/thread.ex` — `changeset/2` validation (D-15, no change expected; verify 300 stays)
- `lib/foglet_bbs/threads.ex` — `create_thread/3` (consumed by NewThread — already exists)
- `lib/foglet_bbs/posts.ex` — `create_reply/4` (consumed by PostComposer — already exists)
- `lib/foglet_bbs/config.ex` — `get!/1` (consumed for new `max_thread_title_length` key)
- `priv/repo/seeds.exs` — add `{"max_thread_title_length", 60, "Maximum thread title length in characters (D-13)"}` to the config seed tuple list (see line 48 for the `max_post_length` precedent)

### App-Level State
- `lib/foglet_bbs/tui/app.ex` — `screen_module_for/1` already routes `:post_composer` and `:new_thread`; `{:load_posts, ...}` + `{:load_threads, ...}` command handlers; `{:load_boards_for_new_thread}` command handler at line 361

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Foglet.TUI.Screens.NewThread` (`lib/foglet_bbs/tui/screens/new_thread.ex`) — two-step wizard (`:board` → `:compose`); `init_screen_state/1` accepts `boards:` option. D-01 reuses this by passing `boards: nil` and immediately jumping to `:compose` via a new init path or screen_state override.
- `Foglet.TUI.Screens.PostComposer` (`lib/foglet_bbs/tui/screens/post_composer.ex`) — reply composer; `[R]` wiring already done in `PostReader.handle_key` at lines 60-75. Works today as a reply form; `title_for(nil, nil)` returns "New Thread" but is never reached with `current_thread: nil` after D-02.
- `MultiLineInput` body rendering pattern (lines 236-272 of `post_composer.ex`, lines 164-192 of `new_thread.ex`) — identical implementation in both screens. Extracts to `Foglet.TUI.Widgets.Compose` (D-09).
- `translate_key/1` (lines 180-201 of `post_composer.ex`, lines 428-450 of `new_thread.ex`) — identical in both screens. Extracts to `Foglet.TUI.Widgets.Compose` (D-09).
- `Foglet.Config` with `max_post_length` precedent — `priv/repo/seeds.exs:48` shows the config-seed pattern used for D-13.
- `Foglet.Threads.create_thread/3` and `Foglet.Posts.create_reply/4` — both exported; the `function_exported?` guard in `NewThread.do_submit` and its "coming soon" modal stub are now dead code (Phase 2 main-roadmap complete — see `.planning/STATE.md`).

### Established Patterns
- Screen state keyed by screen name: `state.screen_state[:post_composer]`, `state.screen_state[:new_thread]`. Origin field lives inside these maps (D-06), not on top-level state.
- Command dispatch via `{:update, state, commands}` return tuple. `{:load_posts, thread_id}` reloads posts; planner uses this or a variant for the reply-jump (see Claude's Discretion).
- Chrome via `ScreenFrame.render(state, title, content, key_list)` — both composer screens already use this correctly. No chrome changes in Phase 4.
- Theme lookup: `(Map.get(state, :session_context) || %{}) |> Map.get(:theme) || Theme.default()`. This pattern is itself a candidate for a helper but that's out of scope for Phase 4.

### Integration Points
- `thread_list.ex:80-82` — broken branch to delete (D-02)
- `thread_list.ex:31-34` — placeholder text `"No threads in this board yet. Press [C] to compose."` — verify it still works after D-01 routing change
- `post_reader.ex:60-75` — add origin stash (D-06); PostComposer init already correct
- `main_menu.ex:43-46` — add origin stash (D-06)
- `post_composer.ex:363-376` — `do_submit/3` success path: update `selected_post_index` for reply-jump (D-05 + Claude's Discretion)
- `post_composer.ex:383-392` — `cancel/1`: read `ss.origin` (D-07)
- `new_thread.ex:290-296` — Ctrl+C / Esc handlers: read `ss.origin` (D-07)
- `new_thread.ex:391-405` — `do_submit/2` success path: navigate to `:thread_list`, dispatch `{:load_threads, board.id}`, set `selected_index: 0` (D-04)
- `new_thread.ex:412-420` — "coming soon" fallback branch: remove (dead code per Phase 2 main-roadmap completion)
- `new_thread.ex:315-329` — `handle_compose_key` title-field branches: add length guard (D-14)
- `app.ex:361-381` — `{:load_boards_for_new_thread}` handler — no change needed; used only from MainMenu path

### Scope Fencing Notes
- Phase 2's plan 02-03 explicitly flags `post_composer.ex` / `new_thread.ex` duplicate `render_markdown_tuples/2` as out-of-scope for Phase 2. D-11 moves them in-scope for Phase 4.
- Phase 3's LIST-02 work adds `{:load_threads, ...}` dispatch from multiple sites — D-04's dispatch aligns with that pattern, not with it.
- `memory/feedback_raxol_modern_dsl.md` is a phantom file referenced by Phase 1 and Phase 2 CONTEXT files — do not rely on it. The DSL constraint is embodied by `lib/foglet_bbs/tui/widgets/chrome/` as the canonical example.

</code_context>

<specifics>
## Specific Ideas

- User preferred `max_thread_title_length` default of **60**, not 300 — tighter than the changeset's backstop because thread-list rows must fit title + metadata within 80-col terminals (Phase 3 D-03 truncation falls back to `…` but titles over 60 chars routinely trigger it).
- Silent cancel with no confirm modal (D-08) is a deliberate classic-BBS UX choice, matching the user's stated preference for fast, low-friction navigation.
- The new `Foglet.TUI.Widgets.Compose` helper module (D-09) is scoped narrowly to shared MultiLineInput plumbing — it is NOT a unified composer screen. A full merge of `PostComposer` and `NewThread` is explicitly deferred (D-12).
- Reply-success jumps to the new reply (last post after reload) — chosen over stay-in-place because the user wants visible confirmation that their reply landed (D-05).
- Thread-success jumps back to ThreadList with the new thread pre-selected (D-04) — chosen over opening the new thread because the user wants to see the new thread in context, and opening it is one Enter away.

</specifics>

<deferred>
## Deferred Ideas

- **Full `PostComposer` + `NewThread` module merge** — Collapse both screens into a single mode-switched composer module. Deferred; extract-shared-helpers approach (D-09) is sufficient for Phase 4.
- **Draft persistence across cancel/resume** — Auto-save drafts on cancel and restore on re-entry. Out of scope for v1.0.1.
- **Sysop in-TUI toggle for `max_thread_title_length`** — Belongs in Milestone 8 (`Sysop Administration In-TUI`). v1.0.1 sysop edits via `mix foglet.config.set max_thread_title_length N`.
- **Submit-error UX rework** — Inline error banner vs modal dialog for changeset errors. Out of scope; current modal approach is preserved.
- **Legacy `state.composer_draft` field cleanup** — May be removed opportunistically if trivial, otherwise deferred (see Claude's Discretion).
- **Quote-preview UX changes** (lines `> quoted` in reply composer) — Preserve current behavior.

</deferred>

---

*Phase: 04-composer-thread-creation-end-to-end*
*Context gathered: 2026-04-20*
