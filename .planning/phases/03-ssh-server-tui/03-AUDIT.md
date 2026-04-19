# Phase 03 Audit — Raxol Integration Gaps

**Audited:** 2026-04-18
**Auditor:** Claude (Opus 4.7)
**Trigger:** User observed "Phase 03 has massive gaps in its implementation and I feel it's because the raxol documentation was not referenced properly during planning and plan execution."
**Scope:** Compare current implementation (lib/foglet_bbs/tui, lib/foglet_bbs/ssh, lib/foglet_bbs/sessions) against Raxol v2.4.0 documentation now available at `docs/raxol/` and the decisions locked in `03-CONTEXT.md`.

---

## Executive Summary

Phase 03 shipped as "complete" (see commit a289342 `docs(state): mark Phase 03 complete`) but the BBS is **not usable end-to-end**. The unit tests pass because they test the dispatch plumbing (`App.update/2` returns a 2-tuple, `:navigate` changes `current_screen`, etc.) — not the actual user experience.

**Root cause pattern:**
1. Planning referenced Raxol only by GitHub URL (`03-CONTEXT.md` §canonical_refs) without pulling the actual API surface into the plans.
2. Executors wrote code that *looks like* Raxol based on pattern-matching against Elixir/Phoenix idioms — but used invalid options (`color:` instead of `fg:`), invented missing integration layers (`ConnectionCounter` name-squatting `Raxol.SSH.Server`), and skipped mandated widgets (hand-rolled text input instead of `textarea`, despite D-26).
3. D-21 scoped testing to unit tests of `update/2` and `view/1` — so no one ran `ssh localhost -p 2222` and saw the empty login form.

**Consequence:** The login form has no functioning text input. The registration wizard cannot advance past step 1. The verify screen hand-rolls what the `text_input` widget does. Colors are silently dropped throughout. The SSH session never spawns a `Foglet.Sessions.Session`, so the one-session-per-user decision (D-25), heartbeats, and session-replacement messaging are all dead code.

**Bottom line:** A real user who SSH'd into this BBS today would see a colorless login screen, type their handle, watch nothing happen, press Enter, and submit an empty credential.

---

## How to read this document

Each item has:
- **Severity** — Critical / Major / Minor
- **Files** — concrete paths and line numbers
- **What's broken** — the observed defect
- **Evidence** — quoted code + relevant Raxol docs pointer
- **Fix direction** — not a finished plan, but which way to go

Items are grouped by theme, not by fix order. Task numbers (`#1` – `#18`) correspond to the TaskCreate IDs from the audit session on 2026-04-18, preserved for traceability.

---

# A. Framework API misuse (silent failures)

## #1 — `color:` is not a valid Raxol text option

**Severity:** Critical
**Files:** all 8 screens under `lib/foglet_bbs/tui/screens/` + all 3 widgets under `lib/foglet_bbs/tui/widgets/`

**What's broken:** Every `text("...", color: :green)` call in the TUI silently drops the color.

**Evidence:**
- `deps/raxol/lib/raxol/core/renderer/view/components/text.ex:22-33` — `Text.new/2` reads only `:fg`, `:bg`, `:style`, `:align`, `:wrap`. A stray `:color` key is ignored.
- `docs/raxol/getting-started/WIDGET_GALLERY.md:126` — documented form: `text(content: "Custom", fg: :cyan, bg: :blue)` or `text("x", style: %{fg: :red, bold: true})`.
- Grep `color:` in `lib/foglet_bbs/tui/` for the full list — every screen and widget is affected.

**Fix direction:** Replace `color:` → `fg:` globally. Map `:bright_black` / `:bright_green` to their valid forms (Raxol color atoms are `:black | :red | :green | :yellow | :blue | :magenta | :cyan | :white`, plus RGB tuples and hex strings — WIDGET_GALLERY.md:131). Decide whether `:bright_*` maps to `style: [:bold]` + fg or to an RGB tuple.

---

## #17 — Legacy function API instead of documented block-macro DSL

**Severity:** Minor (currently) / Major (going forward)
**Files:** all 8 screens, all 3 widgets

**What's broken:** Screens use `import Raxol.Core.Renderer.View` and call `panel(title: ..., children: [...])` / `box(children: [...])` / `column(opts)`. The currently-installed Raxol (2.4.0) still supports both this legacy function API and the block-macro API — both exist in `deps/raxol/lib/raxol/core/renderer/view.ex` (e.g., `def box/1` at line 66 and `defmacro box/2` at line 71). But:

- `docs/raxol/getting-started/QUICKSTART.md` / `WIDGET_GALLERY.md` / `BUILDING_APPS.md` show **only** the block form: `box style: %{border: :single, padding: 1} do ... end`.
- Block form carries a `style:` map with `gap`, `padding`, `align_items`, `flex` — none of which our code sets, so the UI has no spacing, no alignment, and will look cramped.
- Future Raxol releases, examples, and community patterns target the block form.

**Evidence:**
- Current code: `lib/foglet_bbs/tui/screens/login.ex:27-38` — `panel(title: ..., children: [...])`.
- Documented form: `docs/raxol/cookbook/BUILDING_APPS.md:319-328` — `box style: %{border: :single, flex: 1, padding: 0} do ... end`.

**Fix direction:** Pick a target (stay-legacy or migrate-to-blocks) and apply consistently. If migrating, also add `style: %{...}` maps with reasonable gap/padding/alignment so the rendered UI isn't a wall of flush-left text.

---

# B. Input widgets never wired — screens cannot take keyboard input

## #2 — Login form has no functioning text input

**Severity:** Critical (blocks every other login-requiring path)
**File:** `lib/foglet_bbs/tui/screens/login.ex`

**What's broken:** `render_login_form/1` at lines 97-121 emits:
```elixir
text("Handle:   #{form.handle}", color: :green),
text("Password: #{String.duplicate("*", String.length(form.password))}", color: :green)
```
`form.handle` starts as `""`. `handle_key/2` matches only `"l"`, `"r"`, `"q"`, `"enter"` (lines 41-50). Typing any other character falls to `:no_match`. User presses Enter, `submit_login/1` calls `Accounts.authenticate_by_password("", "")` — always fails.

**Evidence:** `docs/raxol/getting-started/WIDGET_GALLERY.md:299-307` — `text_input(value: model.name, placeholder: "Enter name...")` plus `Input.TextInput` component module with `mask_char` (for passwords), `max_length`, `validator`.

**Fix direction:** Either (a) DSL form: `text_input(value: form.handle, on_change: {:login_field, :handle, &1})` and track focus/active-field in state, or (b) component form: `Input.TextInput.init/handle_event/render` for real focus/cursor management. Option (b) is what WIDGET_GALLERY calls out for "full control — handling events, managing component state."

---

## #3 — Register wizard is non-functional past Escape

**Severity:** Critical (breaks SSH-04 D-22..D-24 entirely)
**File:** `lib/foglet_bbs/tui/screens/register.ex`

**What's broken:** `handle_key/2` at lines 54-58 matches only `%{key: "escape"}`. All wizard progression lives in `handle_wizard_event({:submit_step, step, value}, state)` at line 73 — but **nothing in the codebase dispatches `{:register_wizard, {:submit_step, ...}}`**. A user sees "Choose a handle (2-20 chars):" prompt, types, nothing appears, Enter does nothing.

**Evidence:** The only path into `handle_wizard_event` is `App.update({:register_wizard, event}, state)` at `app.ex:168-171`. Nothing produces that message.

**Fix direction:** Add a `text_input` widget per step, have Enter dispatch `{:register_wizard, {:submit_step, current_step, current_value}}`. Requires holding wizard input state somewhere (most likely `state.register_wizard.data[current_step]`) and routing keystrokes into it.

---

## #4 — Verify screen hand-rolls char accumulation

**Severity:** Major
**File:** `lib/foglet_bbs/tui/screens/verify.ex`

**What's broken:** Lines 59-90 manually handle:
- Backspace: `String.slice(buffer, 0, len-1)`
- Single chars: regex-guard `[A-Z0-9]`, uppercase, append if under length 6
- No cursor, no selection

**Evidence:** `docs/raxol/getting-started/WIDGET_GALLERY.md:304-307` — `Input.TextInput` supports `max_length`, `validator` (function), `on_submit`. A 6-char alphanumeric code input is a one-liner with the right widget.

**Fix direction:** `text_input(value: vs.buffer, max_length: 6, validator: &match?({:ok, _}, Regex.run(~r/\A[A-Z0-9]*\z/, &1)), on_submit: :verify_submit)`.

---

## #5 — Post composer ignores D-26 (mandated `textarea`)

**Severity:** Critical (D-26 explicitly mandates the built-in widget)
**File:** `lib/foglet_bbs/tui/screens/post_composer.ex:73-87`

**What's broken:** The composer hand-rolls text input:
```elixir
def handle_key(%{key: "backspace"}, state) do
  draft = state.composer_draft || ""
  new_draft = String.slice(draft, 0, max(String.length(draft) - 1, 0))
  {:update, %{state | composer_draft: new_draft}, []}
end
def handle_key(%{key: "enter"}, state) do
  draft = state.composer_draft || ""
  {:update, %{state | composer_draft: draft <> "\n"}, []}
end
def handle_key(%{key: key}, state) when is_binary(key) and byte_size(key) == 1 do
  draft = state.composer_draft || ""
  {:update, %{state | composer_draft: draft <> key}, []}
end
```
No cursor, no line wrap, no scrolling, no selection, no undo/redo. And `byte_size(key) == 1` rejects all multibyte unicode (see #13).

**Evidence:**
- `03-CONTEXT.md:120-121` (D-26): *"Composer uses Raxol's built-in multi-line scrollable text input widget. No external editor spawning, no line-by-line BBS-style entry."*
- `docs/raxol/getting-started/WIDGET_GALLERY.md:309-321` — `textarea(value:, placeholder:, rows:)` for simple use, `Input.MultiLineInput` component for the full editor (cursor, shift-select, undo/redo, word wrap).

**Fix direction:** Replace the custom keystroke handlers with `Input.MultiLineInput` (the fuller widget — the composer wants word wrap and multi-line editing). Preserve Tab-toggles-preview (D-28), Ctrl+S submit (D-29), Ctrl+C cancel (D-30) as App-level key handlers that run *before* the widget's own handler sees them.

---

## #6 — Modal is stacked as sibling, not overlaid

**Severity:** Major
**File:** `lib/foglet_bbs/tui/app.ex:113-122`

**What's broken:**
```elixir
def view(state) do
  screen_view = render_screen(state)
  if state.modal do
    box(children: [screen_view, Widgets.Modal.render(state.modal)])
  else
    screen_view
  end
end
```
This puts the modal as a sibling child of a box — it renders below the screen, stacked vertically. Not an overlay. Additionally, nothing dismisses the modal: `global_key_handler/2` at lines 211-215 only handles `"q"` on `:login`, and no screen dispatches `:dismiss_modal` on Enter/Y/N.

**Evidence:** `docs/raxol/getting-started/WIDGET_GALLERY.md:438-479` — `modal(visible: bool, title:, content:)` DSL, or `Raxol.UI.Components.Modal` component module with types `:alert` / `:prompt` / `:form`, button lists, and built-in dismissal.

**Fix direction:** Use `modal/1` DSL or the `Modal` component module. Wire an App-level key handler that, when `state.modal` is set, routes Enter/Y/N/Esc to appropriate dispatch messages (dismiss, confirm, cancel).

---

## #13 — Composer `byte_size(key) == 1` breaks multibyte input

**Severity:** Minor (moot once #5 is fixed)
**File:** `lib/foglet_bbs/tui/screens/post_composer.ex:84`

**What's broken:** `when is_binary(key) and byte_size(key) == 1` rejects "é" (2 bytes), "漢" (3 bytes), "🐸" (4 bytes). Users can't type non-ASCII.

**Fix direction:** `String.length(key) == 1` counts graphemes. Subsumed by #5 if the composer switches to `MultiLineInput`.

---

## #16 — Key normalization drops modifier info and misclassifies spacebar

**Severity:** Major
**File:** `lib/foglet_bbs/tui/app.ex:95-111`

**What's broken:** Normalization collapses every Raxol `%Event{}` into a flat `%{key: "string"}`:
```elixir
defp normalize_key(%{key: :char, char: " "}), do: %{key: "space"}
```
Problem: in the composer, a real spacebar press now comes in as `%{key: "space"}`. The catch-all single-char handler (`byte_size(key) == 1`) rejects `"space"` (5 bytes) — so **pressing spacebar in the composer does nothing**. Additionally:
- Shift modifier is dropped.
- Alt modifier is dropped.
- Function keys fall through as strings but no screen matches them.
- Multibyte chars pass as multibyte strings — see #13.

**Evidence:** `docs/raxol/cookbook/BUILDING_APPS.md:41-47` — documented pattern matches directly on `%Event{type: :key, data: %{key: :char, char: c}}`. The canonical Raxol shape carries all modifiers; flattening loses information.

**Fix direction:** Either align on Raxol's native `%Event{}` (simplest — copy the docs' pattern style in every `update/2` / `handle_key/2`) or pick a richer canonical representation (struct/map with key + char + ctrl/alt/shift) and document it. The current flat-string shape is strictly worse than either alternative.

---

# C. SSH ↔ Session ↔ TUI integration broken

## #7 — session_context / user / terminal_size never reach the App

**Severity:** Critical (breaks D-16 end-to-end)
**Files:**
- `deps/raxol/lib/raxol/ssh/session.ex:30-62` (Raxol's Session — starts Lifecycle)
- `deps/raxol/lib/raxol/ssh/cli_handler.ex:61-77` (spawns Session with hardcoded opts)
- `lib/foglet_bbs/tui/app.ex:70-86` (tries to read context that's never passed)

**What's broken:** `Raxol.SSH.Session.init/1` calls:
```elixir
Raxol.Core.Runtime.Lifecycle.start_link(app_module,
  environment: :ssh,
  io_writer: io_writer,
  width: width,
  height: height,
  name: :"ssh_session_#{inspect(self())}"
)
```
There's no hook to pass a `session_context` or a `user`. Our `Foglet.TUI.App.init/1` tries `Map.get(context, :session_context, %{})` and `Map.get(context, :terminal_size, {80, 24})` — both always default, because Raxol never populates them.

**Evidence:** `03-CONTEXT.md:70-80` (D-16): *"SSH daemon authenticates, starts or adopts a `Session` process, which starts the Raxol app via `Raxol.Core.RuntimeApplication` passing initial context. `init/1` populates the model from this context."* — this flow is unimplemented.

**Consequence:** `current_user` is always nil. Terminal size is always `{80, 24}` regardless of the client's actual window (so window resize events also don't match the initial state). Any test passing `session_context: %{user: ...}` (e.g., `test/foglet_bbs/tui/app_test.exs:14-19`) is testing a code path that is unreachable in production.

**Fix direction — two options:**

**(a) Foglet-owned CLIHandler** — Write `Foglet.SSH.CLIHandler` as a real `:ssh_server_channel` (not a wrapper around Raxol's) that:
  1. Authenticates via pwdfun/key_cb OR deliberately leaves identity to the TUI.
  2. Spawns `Foglet.Sessions.Session` with the authenticated user_id.
  3. Starts Raxol Lifecycle with `context: %{session_context: %{user: u, user_id: u.id, pid: session_pid, registration_mode: Config.get!("registration_mode"), ...}, terminal_size: {w, h}}`.

**(b) Guest-first, TUI-is-auth-boundary** — Accept that `App.init/1` always starts with `current_user: nil, current_screen: :login`. On successful login *inside* the TUI, call `Foglet.Sessions.Supervisor.start_session/1` and store the pid in model state. This matches RESEARCH Open Question 1 resolution (see Task #8). Terminal size still has to be plumbed from `Raxol.SSH.Session` → Lifecycle → App init — may require patching Raxol or reading it off the Lifecycle after startup.

Either way, it's a concrete architectural decision Phase 03 deferred.

---

## #8 — Authentication architecture is incoherent

**Severity:** Major (design inconsistency, not a runtime bug yet)
**File:** `lib/foglet_bbs/ssh/supervisor.ex:52-95`

**What's broken:** `daemon_opts/1` sets both:
```elixir
no_auth_needed: true,          # accept all connections
pwdfun: &__MODULE__.pwdfun/4,  # but also validate passwords?
key_cb: {Foglet.SSH.KeyCB, ...}
```
With `no_auth_needed: true`, Erlang's `:ssh` daemon accepts every connection without calling pwdfun or key_cb. The `pwdfun/4` function at lines 85-94 (and its `:pubkey` sibling at 73-83) is **dead code**, tested in isolation but never invoked at runtime.

**Evidence:**
- `03-RESEARCH.md` Open Question 1 resolution (referenced in `03-CONTEXT.md` §canonical_refs): *"the TUI is the authentication boundary; daemon accepts any connection so the guest login-or-register menu can gate identity."*
- `lib/foglet_bbs/ssh/supervisor.ex:10-13` comment confirms: *"no_auth_needed: true — per RESEARCH Open Question 1 resolution (the TUI is the authentication boundary)."*

So the intent is (b) — TUI-owned auth — but the code also sets pwdfun/key_cb as if SSH-layer auth were active.

**Fix direction:** Pick one:
- **(b) TUI-owned:** Remove `pwdfun` and `key_cb` from daemon opts. Delete `Foglet.SSH.Supervisor.pwdfun/4` and associated tests. `Foglet.SSH.KeyCB` stays only if we want pubkey *identity* (not auth) for post-login ssh-key management.
- **(a) SSH-level:** Remove `no_auth_needed: true`, keep pwdfun/key_cb, and wire them to actually load the user into SSH channel state so CLIHandler can hand it to the Session.

Coupled tightly with #7 — the auth choice determines the context-plumbing shape.

---

## #10 — Heartbeat / Session ↔ TUI back-channel never fires

**Severity:** Major
**File:** `lib/foglet_bbs/sessions/session.ex` (entire module is dead code at runtime)

**What's broken:** `Foglet.Sessions.Session` defines `heartbeat/1`, `set_terminal_size/2`, `set_tui_pid/2`, and handles `:replaced_by_new_session` by messaging `state.tui_pid` (lines 110-119). But because no SSH connection ever spawns a `Foglet.Sessions.Session` (see #7), none of this runs. Consequences:
- `last_seen_at` never updates (affects Phase 4 Presence / online list)
- `tui_pid` stays nil, so replacement notifications have nowhere to go
- D-25 one-session-per-user enforcement exists only in `Sessions.Supervisor` tests — in production, two SSH connections from the same user produce two independent, unrelated Raxol apps

**Fix direction (sequenced after #7):**
1. On successful login: `{:ok, sess} = Sessions.Supervisor.start_session([user_id: u.id, handle: u.handle, role: u.role, terminal_size: state.terminal_size])`; store `sess` in model; call `Session.set_tui_pid(sess, self())`.
2. In `App.subscribe/1`: add `subscribe_interval(10_000, :heartbeat_tick)` (or similar).
3. Handle `:heartbeat_tick` by calling `Session.heartbeat(sess)`.
4. Handle `{:session_replaced, _user_id}` → modal + `Command.quit()`.
5. On `{:window_change, w, h}`: also call `Session.set_terminal_size(sess, {w, h})`.
6. On logout or session exit: let the Session terminate naturally.

---

## #14 — `Foglet.SSH.Supervisor` starts daemon in init/1 but supervises nothing

**Severity:** Minor (won't cause bugs unless the daemon crashes)
**File:** `lib/foglet_bbs/ssh/supervisor.ex:30-45`

**What's broken:**
```elixir
def init(_opts) do
  # ...
  {:ok, _daemon_ref} = :ssh.daemon(port, daemon_opts)
  # ...
  Supervisor.init([], strategy: :one_for_one)  # empty children!
end
```
The daemon is owned by OTP's `:ssh` application, not this Supervisor. If the daemon crashes, this Supervisor doesn't know and doesn't restart it. The Supervisor is a facade — the name is misleading.

**Fix direction:**
- **(a)** Convert to a `GenServer` or `Task` that owns `daemon_ref` and exits on daemon DOWN, so the parent supervisor restarts it.
- **(b)** Drop the wrapper entirely — start the daemon in `FogletBbs.Application.start/2` directly.
- Also: `:ssh` needs to be in `mix.exs` `extra_applications` (check — may already be implicit via OTP release).

---

## #15 — `ConnectionCounter` impersonates `Raxol.SSH.Server`

**Severity:** Minor (latent risk)
**File:** `lib/foglet_bbs/ssh/connection_counter.ex:12-13`

**What's broken:**
```elixir
def start_link(_opts) do
  GenServer.start_link(__MODULE__, %{connections: 0}, name: Raxol.SSH.Server)
end
```
Registers itself under the name `Raxol.SSH.Server` so Raxol's `CLIHandler.register_connection/unregister_connection/connection_count` calls route here instead of to a real `Raxol.SSH.Server` (which we don't start because it would spawn its own daemon).

This "works" because Raxol 2.4.0 calls exactly three functions on that name. Any future Raxol release adding an API call to `Raxol.SSH.Server` will hit `function_clause` at runtime.

**Evidence:** `deps/raxol/lib/raxol/ssh/cli_handler.ex:23` — `Raxol.SSH.Server.register_connection()` (no GenServer server arg; uses the default name). `deps/raxol/lib/raxol/ssh/server.ex:56-71` — public API surface.

**Fix direction:**
- **(a)** Pin Raxol tightly and test against upgrades.
- **(b)** Mirror the full public API of `Raxol.SSH.Server` (delegate/stub every function).
- **(c)** Replace with Foglet-owned CLIHandler (see #7 option (a)) — removes the need for Raxol.SSH.Server entirely.

---

# D. Functional gaps

## #9 — "Compose New Thread" from main menu has no thread-creation path

**Severity:** Major
**Files:** `lib/foglet_bbs/tui/screens/main_menu.ex:40-43` + `lib/foglet_bbs/tui/screens/post_composer.ex:152-190`

**What's broken:** `MainMenu.handle_key("c" | "C", state)` jumps to `:post_composer` with `current_thread: nil, composer_draft: ""`, but:
- `current_board` is also nil (user hasn't selected a board)
- No UI prompts for board choice or thread title
- `post_composer.do_submit/3` at line 156 checks `function_exported?(posts_mod, :create_reply, 3) && state.current_thread` — with `current_thread: nil` the guard fails, so submission falls into the dev-stub modal at lines 177-189 and returns to thread_list

Effectively: the user selects "Compose New Thread" from the main menu, gets a composer, types a post, hits Ctrl+S, and sees "Submitted (dev-mode; Phase 2 not fully wired)." — even though Phase 2 *is* wired for `Posts.create_post/N` (just not `create_reply/3` in the absence of a thread).

**Fix direction:** Add a dedicated new-thread flow: board selector → title prompt → body composer → `Foglet.Threads.create_thread/N` + first post. Or extend the composer with a thread-creation mode (header fields visible above the body). The former is cleaner.

---

## #11 — Command dispatch wraps plain tuples in no-op `Command.task`

**Severity:** Minor
**File:** `lib/foglet_bbs/tui/app.ex:220-223`

**What's broken:**
```elixir
defp wrap_command({:terminate, _reason}), do: Command.quit()
defp wrap_command(msg) when is_tuple(msg), do: Command.task(fn -> msg end)
defp wrap_command(cmd), do: cmd
```
For tuples like `{:load_boards}`, `wrap_command` spawns a task whose entire body is `fn -> {:load_boards} end`. The task does no work — it just returns the tuple so the dispatcher round-trips it back to `update/2`, where the DB query actually runs synchronously inside `update/2`.

**Consequence:** I/O runs on the Lifecycle process (slow DB query = frozen UI) instead of off-process where `Command.task` is meant for. And a useless Task process is spawned per dispatch.

**Fix direction — two options:**
- **(a)** Do the work inside the task: `Command.task(fn -> boards = Boards.list_subscribed_boards(user); {:boards_loaded, boards} end)` — handle `{:boards_loaded, boards}` in `update/2` by assigning.
- **(b)** Send the tuple as a direct message back to the Lifecycle (Raxol has primitives for this) rather than wrapping in a Command.

Option (a) is the Raxol-idiomatic one — `Command.task` is designed specifically for off-process work that returns a message.

---

## #12 — `subscribe/1` is empty; no PubSub wiring

**Severity:** Major
**File:** `lib/foglet_bbs/tui/app.ex:124-128`

**What's broken:**
```elixir
def subscribe(_state) do
  # Plan 04 will add PubSub topic subscriptions (board activity, notifications).
  []
end
```
Plan 04 (`03-04-PLAN.md`) has already been executed and marked complete (commit 0cf235e), but `subscribe/1` is still empty. D-16 mandates: *"System events (board activity, notifications) arrive via PubSub subscriptions held by the Raxol app."*

**Consequence:** Board-activity broadcasts from Phase 2 (Foglet.Boards broadcasts after `Posts.create_post`) don't reach any screen. Real-time unread count updates, new post notifications, etc. don't happen.

**Fix direction:** `subscribe/1` should return subscriptions based on current screen:
- Always: user-level topic (`"user:#{user_id}"`) for DMs / notifications once user is logged in.
- On `:board_list`: `"boards"` for the activity feed.
- On `:thread_list`: `"board:#{board_id}"`.
- On `:post_reader`: `"thread:#{thread_id}"`.

Raxol's `subscribe_interval/2` is for timers; for PubSub, we need a subscription function that connects a PubSub topic to the message stream. Check Raxol 2.4.0 for the right primitive — if it's absent, `Phoenix.PubSub.subscribe/2` in `init/1` with a process-level receive is the fallback.

---

# E. Process gap

## #18 — End-to-end manual smoke test — no one has SSH'd into this BBS

**Severity:** Critical (process issue that produced all the above)

**What's broken:** Everything in this document was inferred from reading code. D-21 scoped Phase 03 testing to unit tests of `update/2` and `view/1`. There is no evidence in the repo — no UAT note, no log, no screenshot — that a human has actually run `iex -S mix phx.server` and `ssh localhost -p 2222`. Many of the defects above (empty forms, invisible colors, unresponsive input, modal stacked below screen) would surface within the first 30 seconds of a real session.

**Fix direction:** Once blockers #1, #2, #3, #5, #7 are resolved, capture a full manual walkthrough:
1. Start: `iex -S mix phx.server`
2. Connect: `ssh localhost -p 2222` from a separate terminal
3. Walk: register → verify → login → board list → thread list → post reader → compose reply → logout
4. Capture what renders vs what's expected at each step
5. Save to `03-SMOKE-TEST.md` (or amend `03-UAT.md`) as the definitive Phase 03 sign-off gate

This is the single biggest quality gate missing from Phase 03, and the process change that should carry into Phase 04+: UAT for any SSH/TUI work must include a real connection.

---

# Fix Sequencing Recommendation

Not all 18 items are equal; a reasonable order:

1. **#1** (color fix) — trivial, unblocks visible feedback during testing.
2. **#7 + #8** (auth architecture + context plumbing) — pick option (a) or (b); everything downstream depends on this.
3. **#2, #3, #5** (login, register, composer input widgets) — the TUI becomes usable.
4. **#6** (modal overlay) — error/confirmation UX actually works.
5. **#16** (key normalization) — fixes spacebar-in-composer and multibyte.
6. **#10** (heartbeat/session wiring) — once #7 landed.
7. **#9** (new thread flow).
8. **#12** (PubSub).
9. **#11, #14, #15, #17** — cleanup / polish.
10. **#4, #13** — subsumed by #5/#3 fixes.
11. **#18** — runs continuously throughout; formal walkthrough at the end.

---

# Related Artifacts

- `03-CONTEXT.md` — original decisions (D-01..D-31)
- `03-RESEARCH.md` — Open Question 1 resolution for TUI-owned auth
- `03-0{1-4}-PLAN.md` — the plans that produced the current code
- `03-UAT.md` — current UAT list (notably does NOT include a real SSH connection test)
- `docs/raxol/` — Raxol 2.4.0 documentation now available locally
- `deps/raxol/` — installed source for direct API reference

---

*Audit generated 2026-04-18. Tasks #1–#18 correspond to TaskCreate IDs in that session.*
