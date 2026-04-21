# Phase 4: Composer & thread creation end-to-end — Research

**Researched:** 2026-04-20
**Confidence:** HIGH
**Scope:** Technical verification of the decisions locked in `04-CONTEXT.md`. Reconfirms function signatures, establishes the exact call sites to modify, and validates the execute-order dependency on Phase 2's `Foglet.TUI.Widgets.Post.MarkdownBody`.

---

## 1. Executive Summary

Phase 4 is a **wiring + DRY + one new config key** phase — zero new dependencies, zero new domain code. Every callee already exists: `Foglet.Threads.create_thread/3`, `Foglet.Posts.create_reply/4`, `Foglet.Config.get!/1`, `Foglet.TUI.Widgets.Post.MarkdownBody.render/3`, `Foglet.TUI.Screens.PostComposer.init_screen_state/1`, `Foglet.TUI.Screens.NewThread.init_screen_state/1`. The phase connects them correctly, deletes the broken `thread_list.ex:80-82` branch, introduces a small `Foglet.TUI.Widgets.Compose` helper to collapse ~80 LOC of duplicated plumbing, and seeds one config key (`max_thread_title_length`, default 60).

The dominant risk is the **hard ordering dependency on Phase 2**: `Foglet.TUI.Widgets.Post.MarkdownBody.render/3` must exist before D-11 (composer preview calls it directly). Phase 2 execution has completed on this branch (see `.planning/workstreams/phase-03-polish/STATE.md` "completed_phases: 2"), so this ordering is already satisfied. No spike required.

Three risk areas that need planning attention (not new decisions — planning guardrails):

1. **Reply-jump race (D-05 + Claude's Discretion).** After `do_submit/3` success in `PostComposer`, the caller dispatches `{:load_posts, thread.id}` which is handled **asynchronously** in `app.ex:413-415` (it spawns a `Command.task/1`). The composer cannot set `selected_post_index` inline because the posts list hasn't loaded yet. The correct fix is to either (a) extend the command with a `jump_last: true` hint and handle it in `{:posts_loaded, posts}` at `app.ex:415-417`, or (b) add a new `{:load_posts_jump_last, thread_id}` command variant. Planner must pick one and make sure the post-reload completes before the index is set — **see Plan 04-04 for the chosen approach**.
2. **Origin stash must survive the screen transition.** Origin lives inside `screen_state[:new_thread]` or `screen_state[:post_composer]`. `do_submit/3` in `PostComposer` currently calls `Map.delete(state.screen_state, :post_composer)` on success (line 369) — this is correct and matches "origin only matters during the composer lifecycle". `cancel/1` must read `ss.origin` BEFORE deleting the composer screen_state.
3. **MainMenu's `[C]` still needs the board picker path.** D-01/D-03 leave the MainMenu `[C]` path (`main_menu.ex:40-47`) intact — it still dispatches `{:load_boards_for_new_thread}` and lands on `step: :board`. Only the ThreadList `[C]` skips the picker. The planner must NOT remove the `load_boards_for_new_thread` command handler at `app.ex:361-381` — it's still used.

---

## 2. Signature Verification (all confirmed)

| Call | Source | Signature | Used by |
|------|--------|-----------|---------|
| `Foglet.Threads.create_thread/3` | `lib/foglet_bbs/threads.ex:28` | `(board_id, user_id, %{title:, body:}) :: {:ok, %{thread: Thread.t(), post: Post.t()}} \| {:error, any()}` | `NewThread.do_submit/2` |
| `Foglet.Posts.create_reply/4` | `lib/foglet_bbs/posts.ex:28` | `(thread_id, board_id, user_id, attrs) :: {:ok, Post.t()} \| {:error, Changeset.t()}` | `PostComposer.do_submit/3` |
| `Foglet.Posts.list_posts/1` | `lib/foglet_bbs/posts.ex:43` | `(thread_id) :: [Post.t()]` | app.ex `{:load_posts, thread_id}` |
| `Foglet.Threads.list_threads/1` | `lib/foglet_bbs/threads.ex:43` | `(board_id) :: [Thread.t()]` | app.ex `{:load_threads, board_id}` |
| `Foglet.Config.get!/1` | `lib/foglet_bbs/config.ex:45` | `(key :: String.t()) :: term() \| raise` | `NewThread.handle_compose_key` title cap |
| `Foglet.TUI.Widgets.Post.MarkdownBody.render/3` | `lib/foglet_bbs/tui/widgets/post/markdown_body.ex` | `(body :: String.t(), width :: pos_integer(), theme :: Theme.t()) :: view_ast` | preview mode in both composers |
| `Raxol.UI.Components.Input.MultiLineInput.update/2` | Raxol 2.4.0 vendored | `(msg, state) :: {:noreply, state, cmds} \| state` | shared `translate_key` translator |
| `Foglet.TUI.Screens.PostComposer.init_screen_state/1` | `lib/foglet_bbs/tui/screens/post_composer.ex:122` | `(opts :: keyword()) :: map()` — keys: `mode`, `reply_to`, `error`, `input_state` | `PostReader` `[R]` handler |
| `Foglet.TUI.Screens.NewThread.init_screen_state/1` | `lib/foglet_bbs/tui/screens/new_thread.ex:32` | `(opts :: keyword()) :: map()` — keys: `step`, `boards`, `selected_board_index`, `board`, `title_input`, `body_input_state`, `focused`, `mode`, `error` | `MainMenu` `[C]` handler |

All signatures are load-bearing — do NOT change them in Phase 4; only add optional keys (`origin:`, `boards:`, `board:`, `step:`) via the existing `opts \\ []`.

---

## 3. Call-Site Map (exact file + line)

### 3.1 ThreadList `[C]` — delete broken branch, reinit for new-thread (D-01, D-02)

`lib/foglet_bbs/tui/screens/thread_list.ex:80-83` currently:

```elixir
def handle_key(%{key: :char, char: c}, state) when c in ["c", "C"] do
  {:update, %{state | current_screen: :post_composer, composer_draft: "", current_thread: nil},
   []}
end
```

**Replace with:** init `:new_thread` screen_state with `step: :compose, board: state.current_board, boards: nil, origin: :thread_list`, set `current_screen: :new_thread`. Do NOT dispatch `{:load_boards_for_new_thread}` — the board is already known.

### 3.2 MainMenu `[C]` — add origin stash (D-06)

`lib/foglet_bbs/tui/screens/main_menu.ex:40-47` — already initialises `:new_thread` screen_state and dispatches `{:load_boards_for_new_thread}`. Add `origin: :main_menu` to the initial screen_state. No other change.

### 3.3 PostReader `[R]` — add origin stash (D-06)

`lib/foglet_bbs/tui/screens/post_reader.ex:92-109` — already initialises `:post_composer` screen_state via `PostComposer.init_screen_state/1`. Add `origin: :post_reader` to the initial screen_state. No other change.

### 3.4 PostComposer cancel — origin-aware (D-07)

`lib/foglet_bbs/tui/screens/post_composer.ex:383-392` currently hard-codes `current_screen: :thread_list`. Change to read `ss.origin` (default `:main_menu` if missing) and navigate there.

### 3.5 PostComposer submit — reply-jump (D-05)

`lib/foglet_bbs/tui/screens/post_composer.ex:354-377` — `do_submit/3` must dispatch `{:load_posts, thread.id}` AND signal the post_reader to pick the last post on the next reload. See §4 for implementation.

### 3.6 NewThread cancel — origin-aware (D-07)

`lib/foglet_bbs/tui/screens/new_thread.ex:290-296` currently hard-codes `current_screen: :main_menu` for both Ctrl+C and Esc. The **board step** (handle_board_key Esc at line 237-239) keeps `:main_menu` — unchanged. The **compose step** (Ctrl+C / Esc at lines 290-296) reads `ss.origin` (default `:main_menu`).

### 3.7 NewThread submit — success nav → thread_list (D-04)

`lib/foglet_bbs/tui/screens/new_thread.ex:374-422` — `do_submit/2` success branch (lines 391-405) currently navigates to `:post_reader`. Change to:
- `current_screen: :thread_list`
- `current_board: board` (preserved; already set)
- `screen_state: Map.merge(state.screen_state, %{new_thread: nil, thread_list: %{selected_index: 0}})`
- Dispatch `{:load_threads, board.id}` instead of `{:load_posts, thread.id}`

Also remove the dead "Phase 2 not yet wired" fallback at lines 411-420 — `function_exported?(threads_mod, :create_thread, 3)` is always `true` now; keep the guard only if the user is nil.

### 3.8 NewThread title length cap (D-13, D-14)

`lib/foglet_bbs/tui/screens/new_thread.ex:327-329` — the `%{key: :char, char: c}` handler for `focused: :title` concatenates unconditionally. Add a length guard using `Foglet.Config.get!("max_thread_title_length")` (with safe fallback to 60 on any error). Reject the keystroke if appending `c` would exceed the cap.

Also add a counter display in `render_compose_step/2` (line 112-117 — the title line): `"Title: <text>█  N / 60 chars"` showing current / cap. Use the same theme pattern as PostComposer's body counter (`post_composer.ex:61`).

### 3.9 Shared module `Foglet.TUI.Widgets.Compose` (D-09, D-10)

New file `lib/foglet_bbs/tui/widgets/compose.ex`. Exports:

- `translate_key/1` — lifted verbatim from `post_composer.ex:180-201` (identical to `new_thread.ex:428-450`)
- `render_input/3` (name chosen to avoid collision with PostComposer's existing `render_input/3`) — lifted verbatim from `post_composer.ex:246-272` (same as `new_thread.ex:164-192` except `NewThread` uses `" "` for empty lines whereas `PostComposer` uses empty string; the helper takes a `placeholder_for_empty:` option to preserve both behaviors)

After extraction:
- `post_composer.ex` deletes its private `translate_key/1` (lines 180-201) and `render_input_as_text/3` (lines 246-272); delegates to the widget module via `alias Foglet.TUI.Widgets.Compose`.
- `new_thread.ex` deletes its private `translate_key/1` (lines 428-450) and `render_body/3` (lines 164-192); delegates likewise.

### 3.10 Shared markdown preview — remove duplicated `render_markdown_tuples/2` (D-11)

- `post_composer.ex:291-302` — `defp render_markdown_tuples(tuples, theme)` — remove.
- `new_thread.ex:208-219` — `defp render_markdown_tuples(tuples, theme)` — remove.
- `post_composer.ex:52` (preview branch) — change `render_markdown_tuples(render_preview(state, draft), theme)` → call `Foglet.TUI.Widgets.Post.MarkdownBody.render(draft, width, theme)` directly. `render_preview/2` is also removable (it only adds the `Foglet.Markdown.render/1` fallback which MarkdownBody already does internally).
- `new_thread.ex:158` (preview branch) — change `render_markdown_tuples(render_preview_text(state, ss.body_input_state.value), theme)` → call `Foglet.TUI.Widgets.Post.MarkdownBody.render(ss.body_input_state.value, width, theme)`. `render_preview_text/2` removable.

**Width resolution:** Both composers have access to `state.terminal_size` — use `{w, _h} = state.terminal_size || {80, 24}` and pass `max(w - 4, 20)` to match ScreenFrame's padding (same pattern as `new_thread.ex:254`).

---

## 4. Reply-Jump Implementation (resolution of Claude's Discretion)

**Chosen approach:** Extend the `{:load_posts, thread_id}` contract with an optional third element carrying options — `{:load_posts, thread_id, opts}` where `opts` is a keyword list. Handle `jump_last: true` in the `{:posts_loaded, posts}` sink.

**Why this over the flag-on-state-field alternative:** State-field flags (e.g., `state.jump_to_last`) leak temporal coupling across unrelated code paths. A command-option keyword keeps the signal scoped to the command lifecycle — the flag only exists between command dispatch and its paired `:posts_loaded` handler.

**Why not a new command name (`{:load_posts_jump_last, thread_id}`):** It duplicates the command-handler boilerplate in `app.ex` (load, spawn task, handle reply). The opts approach keeps the load path DRY.

**Implementation skeleton:**

```elixir
# In app.ex — replace the 2-arity tuple with a 3-arity pattern match:
defp do_update({:load_posts, thread_id, opts}, state) do
  ctx = Map.get(state, :session_context) || %{}
  posts_mod = get_in(ctx, [:domain, :posts]) || Foglet.Posts

  task =
    Command.task(fn ->
      {:posts_loaded, posts_mod.list_posts(thread_id), opts}
    end)

  {state, [task]}
end

# Backward-compat: 2-arity calls still work
defp do_update({:load_posts, thread_id}, state),
  do: do_update({:load_posts, thread_id, []}, state)

# Sink handles the opts
defp do_update({:posts_loaded, posts, opts}, state) do
  ss = get_in(state.screen_state, [:post_reader]) || %{selected_post_index: 0}

  new_idx =
    if Keyword.get(opts, :jump_last, false) and posts != [] do
      length(posts) - 1
    else
      ss.selected_post_index
    end

  new_ss = Map.put(ss, :selected_post_index, new_idx)
  new_screen_state = Map.put(state.screen_state, :post_reader, new_ss)
  {%{state | posts: posts, screen_state: new_screen_state}, []}
end

# Backward-compat for the 2-arity :posts_loaded emitted elsewhere:
defp do_update({:posts_loaded, posts}, state),
  do: do_update({:posts_loaded, posts, []}, state)
```

`PostComposer.do_submit/3` then dispatches `{:load_posts, thread.id, jump_last: true}` on success. All other callers of `{:load_posts, thread_id}` continue to work unchanged.

---

## 5. Config Seed (D-13)

`priv/repo/seeds.exs:48` already has the `max_post_length` seed tuple. Append one for `max_thread_title_length`:

```elixir
default_config = [
  {"registration_mode", "open", "..."},
  {"invite_code_generators", "sysop_only", "..."},
  {"max_post_length", 8192, "Maximum post body length in characters (D-31)"},
  {"max_thread_title_length", 60,
   "Maximum thread title length in characters (D-13, phase-03-polish Phase 4)"}
]
```

Runtime access: `Foglet.Config.get!("max_thread_title_length")` — returns `60` from seeded DB + ETS cache. On fresh test DBs without seeding, wrap in a safe getter (mirroring `PostComposer.safe_config_get/2` at lines 410-417) that falls back to `60` if `Ecto.NoResultsError` is raised.

`Foglet.Threads.Thread.creation_changeset/2` (line 24 of `thread.ex`): `validate_length(:title, min: 1, max: 300)` **stays unchanged** (D-15). The 300 is a schema backstop — the TUI cap can be raised up to 300 via `mix foglet.config.set max_thread_title_length N` without a migration.

---

## 6. Validation Architecture

Per Nyquist validation (workflow step 5.5), this phase's validation strategy is:

### 6.1 Unit tests (required per plan)

- **Plan 04-01 (shared widget):** `translate_key/1` mapping for every key (`:backspace`, `:enter`, arrows, PgUp/PgDn, printable char, unprintable/control char returns nil). `render_input/3` with focused/unfocused, cursor positions at start/mid/end of line, multi-line, empty body.
- **Plan 04-02 (routing + origin + cancel):** ThreadList `[C]` sets `current_screen: :new_thread` with `step: :compose, board: current_board, origin: :thread_list`. Old broken branch absent (grep-verified). MainMenu `[C]` stashes `origin: :main_menu`. PostReader `[R]` stashes `origin: :post_reader`. Cancel from each of the three origins routes back correctly.
- **Plan 04-03 (submit flows + config):** `NewThread.do_submit/2` success → `:thread_list` + `{:load_threads, board_id}` + `selected_index: 0`. `PostComposer.do_submit/3` success → `:post_reader` + `{:load_posts, thread_id, jump_last: true}`. App handler sets `selected_post_index` to last post in `:posts_loaded`. Title length cap: inserting 61 chars with cap=60 stops at 60. Config seed inserts the key.
- **Plan 04-04 (preview integration + dead code removal):** Preview mode in both composers calls `Foglet.TUI.Widgets.Post.MarkdownBody.render/3`. `render_markdown_tuples/2` absent from both composers. "coming soon" fallback absent from NewThread.

### 6.2 Integration check (manual UAT, gate for Phase 4 completion)

The three Phase 4 success criteria from ROADMAP.md:

1. `[C]` from thread list opens a new-thread composer with title+body; submit returns to thread list with new thread on top.
2. `[R]` from post reader opens a reply composer; submit returns to the thread with the new post visible (and selected).
3. No key press from thread list causes a crash or leads to an empty composer (no title field).

Ship as a short SSH session walkthrough in the phase summary.

### 6.3 Regression surface

Run `mix test` — the full suite must pass. Key files to watch:

- `test/foglet_bbs/tui/screens/post_composer_test.exs` (exists)
- `test/foglet_bbs/tui/screens/new_thread_test.exs` (exists)
- `test/foglet_bbs/tui/screens/thread_list_test.exs` (exists)
- `test/foglet_bbs/tui/screens/post_reader_test.exs` (exists)
- `test/foglet_bbs/tui/screens/main_menu_test.exs` (exists)

Tests that assert the OLD broken ThreadList `[C]` behavior (if any) must be updated, not worked around.

---

## 7. Scope Fences

**IN scope:**
- Files listed in §3 above, tests covering them, the new widget module, the new seed entry.

**OUT of scope (explicit from CONTEXT.md):**
- Full `PostComposer` + `NewThread` merge (D-12, deferred).
- Draft persistence, sysop in-TUI toggle for title cap, quote-preview UX, markdown rendering changes, any Phase 2 work.
- `Foglet.Threads.Thread.creation_changeset/2` changes (D-15).
- `state.composer_draft` field cleanup — leave as-is unless removing is a one-line diff in the files already being touched.

---

## 8. Plan Breakdown (recommended for planner)

Four plans, two waves — all autonomous:

| Plan | Wave | Depends on | Files | Purpose |
|------|------|------------|-------|---------|
| 04-01 | 1 | — | `lib/foglet_bbs/tui/widgets/compose.ex`, `test/foglet_bbs/tui/widgets/compose_test.exs` | Create shared `Foglet.TUI.Widgets.Compose` helper module + tests |
| 04-02 | 1 | — | `priv/repo/seeds.exs`, `test/foglet_bbs/config/config_seed_test.exs` (or inline in existing seed test) | Seed `max_thread_title_length` config key |
| 04-03 | 2 | 04-01, 04-02 | `lib/foglet_bbs/tui/screens/thread_list.ex`, `main_menu.ex`, `post_reader.ex`, `post_composer.ex`, `new_thread.ex`, `app.ex`, + test files for each | Wire routing, origin stash, cancel, submit navigation, title cap, reply-jump command option; delete broken branches and dead code; delegate to shared widget |
| 04-04 | 2 | 04-01, 04-03 | same composer files + preview test coverage | Swap composer preview to `Foglet.TUI.Widgets.Post.MarkdownBody.render/3`; remove local `render_markdown_tuples/2` duplicates |

Plan 04-03 is the heaviest — it spans 7 files and ~8 behavior changes. Planner may split further if per-file plans read cleaner, but the cross-file tests (e.g., "submit from NewThread lands on ThreadList with new_index: 0") naturally bind them.

## RESEARCH COMPLETE
