# Pitfalls Research — Phase 03 Polish

**Domain:** SSH-delivered Raxol TUI BBS (Elixir/OTP)
**Milestone:** v1.0.1 polish / hardening pass
**Researched:** 2026-04-19
**Confidence:** HIGH (all pitfalls grounded in this repo's files or shipped commits; generic TUI advice filtered out)

## Orientation

Phase 03 shipped the SSH + Raxol TUI functional but rough. The git log since
`164417e docs(phase-03): evolve PROJECT.md after phase completion` is essentially
one long list of close calls — Gap 1..7 fixes, CR-01..03, WR-01/03, IN-01..03,
UAT diagnosis, alt-screen takeover, window_change type bug. Every numbered
pitfall below is either a *recurrence-shape* of one of those close calls or a
*new-trap* that the polish scope introduces.

Reading order for planner agents:
1. Critical pitfalls 1–5 gate the polish items that most often regress.
2. Unread-count and composer state-machine pitfalls map 1-to-1 to milestone
   scope items #4, #7, #11 and drive their acceptance criteria.
3. Resize / alt-screen pitfalls gate milestone scope item #9 (min size gating).

---

## Critical Pitfalls

### Pitfall 1: Raxol legacy DSL drift (silent empty render)

**What goes wrong:**
Use of the legacy function-form — `panel(...)`, `box(children: [...])`,
`column(children: [...])` — produces a view tree the modern runtime accepts
without error but silently fails to lay out. The screen renders blank or
partial; no exception is raised. The repo already hit this (see memory
`feedback_raxol_modern_dsl.md` and commits `8001bf5 migrate app.ex view/1 to
block DSL (#17)`, `7643a27 migrate widgets to block DSL`).

Adjacent shape mismatches that behave the same way:
- Calling `MultiLineInput.render/2` directly crashes
  `Flexbox.measure_flex_child/3` — commit `51acce7` was the fix. Any widget
  that returns tuple-shaped elements instead of `%View{}` structs will do the
  same.
- Returning a struct (not a plain map) to `MultiLineInput.init/1` — see the
  inline note in `post_composer.ex:227` ("a struct is not enumerable"). Same
  family of drift: API expects a plain enumerable, struct slips through type
  checks and crashes inside.
- Passing a plain list where a child-list is expected inside a block DSL (e.g.
  forgetting to wrap siblings in a `column do [...] end` so they become peer
  expressions in the `do` body).
- Returning `nil` from a conditional branch that was meant to render a child
  — the layout engine drops it but without a marker, so the neighbouring
  children shift and the screen looks "off by one row".

**Why it happens:**
The modern DSL's contract is: layout containers use `do ... end` blocks
whose body evaluates to a list (or single element); everything else is a
function call. Legacy APIs accepted children as keyword args or wrapped
tuples. Training data and cookbook/guide examples still mix the two because
archived plugin docs (`docs/raxol/plugins/_archive/*`) teach the old form.
Copy-paste from those archives produces silent breakage.

**How to avoid:**
- **Only use the block-macro DSL for `column`, `row`, `box`** — enforce by
  keeping the existing widget-layer (status_bar, key_bar, modal) as the
  reference template.
- **Render smoke tests (`mix test test/foglet_bbs/tui/app_test.exs` covers
  the view-compile path)** — when adding a new screen, add it to the smoke
  test screen list (see commit `86d82f1 IN-03 add :new_thread to view smoke
  test screen list`). An empty render manifests as a missing element
  assertion.
- **Assert on a visible string from the rendered tree**, not just that
  render/1 doesn't raise. Silent blank renders raise nothing.
- **When touching Raxol widgets, always import `Raxol.Core.Renderer.View`**
  and stay inside its `text/2`, `box do`, `column do`, `row do`, `divider()`,
  `spacer()` vocabulary. Do not reach into `Raxol.Core.Renderer.Layout` (that
  is the underlying engine; its API is not the app-level DSL).

**Warning signs:**
- A screen renders its border but the interior is blank.
- Partial content: title appears, KeyBar appears, middle is empty.
- `mix test` passes but UAT shows nothing.
- Layout children appear at y=0 all stacked (not in distinct rows) — this is
  what the smoke test in commit `92b907a` was written to catch.

**Phase to address:**
**Phase P1 — Widget Foundation.** Before any polish screen change, write the
"reusable widget layer" (milestone scope #8) on top of the block DSL as the
single source of truth, and delete any residual legacy shapes. Every
subsequent polish phase inherits the verified base.

---

### Pitfall 2: Stuck board unread count (BoardList "(6 unread)" never clears)

**What goes wrong:**
After reading every thread in General the board still shows `(6 unread)`
indefinitely. This is the one-line entry in milestone scope #4.

**Why it happens (root cause, grounded in this repo):**
The board read pointer is advanced via
`post_reader.ex:131 boards_mod.advance_board_read_pointer(user_id, board_id,
ctx[:last_read_message_number] || 0)`. But `ctx[:last_read_message_number]`
is the *highest post message_number in the thread the user just closed*, not
the *highest message_number in the board*. Threads in a board do not each
contain every message number — the board numbers are allocated across all
threads. So a user who opens thread A (msgs #1, #3) and closes it, then
opens thread B (msgs #2, #4, #5, #6) and closes it, advances the board
pointer in order: 3, then 6. Fine. But if the user opens the most recent
thread first (msg #6), the pointer jumps to 6; then opens an older thread
(msg #3), the code re-calls `advance_board_read_pointer(..., 3)` — the
`on_conflict: [set: [last_read_message_number: 3]]` on `boards.ex:195`
**moves the pointer backwards**, and the backlog reappears.

Second root cause in the same family: when `ctx[:last_read_message_number]
|| 0` falls back to 0 (which happens if the user opens a thread and quits
without scrolling — `state.read_position[thread_id]` is never populated
because `advance_post/2` is the only writer and is only called on n/p
navigation), the board pointer is overwritten *with 0*, and every post in
the board becomes "unread" again.

Third root cause possibility: `Foglet.Boards.unread_counts/1` uses
`p.message_number > coalesce(rp.last_read_message_number, 0)` — a strict
`>` is correct here, so off-by-one is not the issue. But the same query
depends on `ReadPointer` rows existing; `subscribe_to_defaults/1` does not
seed pointers, so first-time users see every existing post as unread. That
is correct behaviour but looks like a bug if seeded threads predate the
user account.

Fourth: the `{:load_boards}` path is only triggered on board_list screen
entry or a `:board_activity` PubSub event. The board pointer is advanced
after leaving a thread (`{:flush_read_pointers, ctx}`) — but the board
list is not refreshed on screen-return from the thread list. So even when
the pointer is correctly advanced, the cached `state.board_list` still
shows stale `unread_count`. User navigates back to Boards and sees the old
number.

**How to avoid:**
- Make `advance_board_read_pointer/3` monotonically non-decreasing. Change
  the `on_conflict` to
  `[set: [...], where: rp.last_read_message_number < ^message_number]` (or
  equivalent) so a smaller message_number never overwrites a larger one.
  Add a property test: any sequence of advances leaves the pointer at
  `max(seq)`.
- Do **not** pass `0` as the fallback. If the user closed a thread without
  advancing locally, compute the actual current max message_number in that
  thread from the loaded posts and use it (or skip the advance entirely).
  Make `last_read_message_number: 0` an invalid input, not a silent default.
- Reload `state.board_list` whenever the user returns to `:board_list`
  from any screen — either dispatch `{:load_boards}` on every
  `:navigate → :board_list` transition, or subscribe to a "pointer
  flushed" event and refresh from that. Stale caches are UI's #1 source of
  "ghost" unread counts.
- Decide upfront: when a seed thread has message_number #1..#6 and a user
  registers on day 7, should the user see `(6 unread)` or `(0 unread)`?
  The current behaviour is `(6 unread)`. If product answer is `(0 unread)`
  ("start from zero"), seed `ReadPointer` rows in
  `subscribe_to_defaults/1` with the board's current max message_number.

**Warning signs:**
- User reads every thread in a board and the count stays ≥ 1.
- Count *increases* when opening an older thread (reverse-flush — proof of
  monotonicity bug).
- Count resets to the full board count on app restart (proof the pointer
  was overwritten with 0 or never persisted).
- `Foglet.Boards.unread_count/2` returns the expected number in IEx but
  the TUI shows a different number (cache staleness, not DB).

**Phase to address:**
**Phase P3 — Read-pointer correctness.** This is the single most
UAT-visible polish item. Make monotonicity a DB-level invariant and add a
property test (StreamData). Refresh board_list on screen-return.

---

### Pitfall 3: `flush_read_pointers` fallback overwrites with zero

**What goes wrong:**
`app.ex:550-558` and `post_reader.ex:131-138` both call
`advance_board_read_pointer(user_id, board_id, ctx[:last_read_message_number]
|| 0)`. When `ctx[:last_read_message_number]` is `nil` (user quits without
scrolling, or the post lacks a `message_number`, or `state.read_position`
was cleared by a previous flush), this writes `0` to the DB as the "last
read". Every post with `message_number > 0` is then unread. This is not
hypothetical: the exact coercion appears twice in the code.

**Why it happens:**
`||` default in Elixir treats `nil` and `false` uniformly as "use default"
— and `0` is the wrong default for an advance-only integer pointer. The
correct behaviour is "do not write if unknown".

**How to avoid:**
- Change the fallback to skip the update: `if
  ctx[:last_read_message_number], do: advance_... end` (already done for
  the thread pointer at `app.ex:560-564` — apply symmetrically to the
  board pointer).
- Or, combine with Pitfall 2's monotonicity guard: if the DB-level
  monotonicity check is in place, writing `0` is a no-op (current value is
  ≥ 0), so the damage is contained. Belt-and-suspenders.

**Warning signs:**
- Unread count jumps from 0 to the full board count after viewing one
  thread and quitting immediately.
- Logs show a pointer value of 0 written when the user visited posts with
  message_number > 0.

**Phase to address:**
**Phase P3 — Read-pointer correctness.** Same phase as Pitfall 2. These
are two halves of the same bug.

---

### Pitfall 4: Resize-during-alt-screen flicker and state loss

**What goes wrong:**
The polish scope's "terminal too small" gate (milestone item #9) has to
coexist with:
- Alt-screen takeover (`cli_handler.ex:151 alternate_screen: true`, added
  in commit `7171160 fix(tui): take over SSH client terminal with
  alt-screen buffer`).
- `{:resize, ...}` event now routed through Dispatcher (commit `01a0d4a`).
- Window-change events arriving in bursts — tmux/iTerm fire many
  `SIGWINCH`s per drag. The dispatcher pushes each one to `update/2`.

Likely regressions if the gating screen is built naively:
- Gate UI flips "too small" → "ok" → "too small" at 60Hz during a drag,
  producing visible flicker on the alt buffer.
- `current_screen` is overwritten with `:too_small` and the user loses
  their position (selected_index, composer draft, scroll).
- Composer width is recomputed on every resize (`new_thread.ex:272 w =
  state.terminal_size`). Re-initialising `MultiLineInput` on every burst
  destroys the in-flight value. Already a shape this repo has because
  `post_composer.ex:166-180 composer_screen_state/1` rebuilds the
  MultiLineInput from `w` if the key `:input_state` is missing — a too-small
  gate that clears `screen_state[:post_composer]` is a silent draft-loser.
- On the SSH alt buffer, a partial re-render after a resize can paint
  stale cells in the border region; this repo already had the
  `83c6bf5 fix(vendor/raxol): SSH frame redraw` for it.

**Why it happens:**
Resize events are state-changing (terminal_size) and view-changing (layout
re-runs) simultaneously. Without a debounce or a "don't reshape below the
gate" rule, the whole render tree rebuilds and transient state is lost.
Alt-screen adds one more wrinkle: the client expects a full frame after a
mode switch.

**How to avoid:**
- Do **not** represent "too small" as a separate `current_screen`. Keep
  it a render-time branch: `view(state) = if too_small?(state), do:
  render_too_small(state), else: render_screen(state)`. The underlying
  `current_screen`, `screen_state`, drafts are preserved across resize.
- Never rebuild `MultiLineInput` state from the width on every resize.
  Initialise once; let the widget wrap internally. If width truly must be
  propagated, write a tiny `resize/2` path that preserves `value` and
  `cursor_pos`.
- Debounce nothing at the app level; Raxol coalesces renders. But add an
  `only if new size differs from old` guard on `do_update({:window_change,
  ...})` to avoid spurious re-renders when the size is unchanged.
- Always `alternate_screen: true` when on SSH (already done). Always emit
  `\e[?1049l` on exit and EOF (already done in `cli_handler.ex:196, 203`)
  so the client buffer is restored regardless of exit path. Add a regression
  test that `send_alt_screen_leave/1` is called in all three exit paths
  (graceful quit, EOF, closed-without-EOF).
- When the terminal is too small, suppress composer rendering explicitly
  (branch to render_too_small) but do not clear the composer state.

**Warning signs:**
- User resizes terminal and loses a 20-minute-old draft.
- Screen flickers during an iTerm drag.
- Residual border fragments in the corner of the alt buffer after a resize
  (the exact symptom commit `83c6bf5` fixed — regressions live here).
- Returning to normal size leaves the client on the primary buffer (LEAVE
  sent too early) or on the alt buffer with stale text (LEAVE never sent).

**Phase to address:**
**Phase P5 — Resize & gating.** Do this *after* the widget layer is
stable, because the gating UI is a widget that composes with every screen.

---

### Pitfall 5: Composer state-machine trap (new-thread vs reply)

**What goes wrong:**
Milestone scope #7 says "Composer has no title field, so starting a new
thread from the board page is impossible". The naive fix is to reuse
`PostComposer` with a conditional title field. That path creates a
four-state machine:

| Entry point        | reply_to | title field | current_thread | on submit             |
|--------------------|----------|-------------|----------------|-----------------------|
| thread_list → [C]  | nil      | required    | nil            | create_thread         |
| post_reader → [R]  | post     | forbidden   | present        | create_reply          |
| post_reader → [R]  | nil      | forbidden   | present        | create_reply to root  |
| board_list → [N]?  | nil      | required    | nil            | create_thread         |

The traps:
- `PostComposer.title_for/2` (`post_composer.ex:288-290`) already branches
  on `{reply_to, current_thread}` — adding a "new-thread from board" entry
  means a new case that doesn't match cleanly. Missing case falls through
  to the wrong submit path.
- `do_submit/3` at `post_composer.ex:377` calls
  `posts_mod.create_reply(thread.id, ...)` unconditionally — if
  `current_thread` is `nil`, this crashes with a MatchError on
  `thread.board_id`.
- `NewThread` already exists as a dedicated 2-step wizard
  (`new_thread.ex`). If the composer is extended to cover new-thread, you
  now have two independent code paths doing the same thing; they will
  diverge (one will pick up markdown preview, one won't; one will enforce
  title length, one won't).
- The "title field" drawn inside PostComposer breaks the existing
  MultiLineInput-as-text rendering: the title input uses a flat `text/2`
  with a `█` cursor overlay (`new_thread.ex:137`), which the composer
  hasn't done before — you'll end up with two different cursor styles on
  the same screen.

**Why it happens:**
The composer was designed as "reply editor", then retrofitted. The
existence of `NewThread` as a separate screen is actually correct — the
bug in scope #7 is just "no affordance routes there from board_list".

**How to avoid:**
- **Do not extend PostComposer.** Keep it strictly "reply-to-existing-thread".
  Add a [N]ew-thread keybinding on `board_list` that navigates to
  `:new_thread` (which already supports board-pick → compose).
- Add the same [N] affordance on `thread_list`, replacing the current [C]
  (which currently navigates to PostComposer with `current_thread: nil`
  — the hidden broken path). Delete the `{:update, ... current_screen:
  :post_composer, composer_draft: "", current_thread: nil}` branch at
  `thread_list.ex:96`.
- Route an existing "reply" directly from `post_reader`, unchanged.
- Add a guard at `post_composer.ex:377`: `if is_nil(thread), do: return
  {:error, "no thread context"}`. Defensive — makes the impossible state
  fail loudly if we ever regress.

**Warning signs:**
- Pressing [C] from thread_list navigates to PostComposer; user sees no
  title field and can't figure out how to set a thread subject.
- Pressing [C] from thread_list then Ctrl+S crashes with a MatchError (this
  is the current state).
- Markdown preview behaves differently in new-thread vs reply flows.

**Phase to address:**
**Phase P4 — Composer & thread creation.** Scope #7 and #11 ("Wire
thread creation + post reply end-to-end") are the same phase; do not split.

---

## Moderate Pitfalls

### Pitfall 6: Markdown → ANSI rendering traps

The current `Foglet.Markdown.render/1` (`markdown.ex`) goes HTML → marker
string → `[{text, style}]`, then is rendered to a `column` of `text/2`
elements. This creates a class of traps:

- **Code block overflow at narrow widths.** Code lines are emitted as
  single `text/2` elements with `:dim` style; Raxol will wrap or truncate
  depending on parent. Wrapping at whitespace inside a code block is wrong
  (breaks syntax); truncation loses content. The polish fix is to pick one
  explicit strategy (horizontal scroll is not available) and document it.
  Recommendation: **truncate with an ellipsis indicator** for wrapped
  content-aware display; allow the user to view raw with a keybinding.
- **Nested-list indent stripping.** `markdown.ex:118` replaces `<li>` with
  `"  • ...\n"` — a flat indent. Nested `<ul><li><ul><li>` loses its
  structure and produces a wrong bullet. MDEx's nested HTML is not
  walked recursively before the flat replace.
- **Tables are essentially unrenderable.** GFM produces `<table>` which
  the current pipeline strips via `String.replace(~r/<[^>]+>/, "")` — the
  cell text dumps out as a run-on paragraph. Either render tables with an
  ASCII-table helper or fall back to rendering the raw markdown
  (pre-MDEx) for any message containing a pipe-table.
- **ANSI SGR reset leak across lines.** Not applicable to the current
  code because styles are carried as atoms on each `text/2` element and
  Raxol emits the full SGR per-cell. BUT if the polish work introduces a
  "render a whole block with one SGR prefix" optimisation (to reduce bytes
  over SSH), this trap reappears — the next line starts mid-style.
- **Unicode width.** Raxol handles CJK and emoji per-cell (2-cell width
  for CJK, variable for emoji sequences). But `Foglet.Markdown`'s
  `String.length(current) + 1 + String.length(word) <= max_width` in
  `Modal.word_wrap/2` (`modal.ex:72-88`) uses `String.length/1` which
  counts graphemes, not display columns. Wrapping in the modal at width
  50 with a CJK string will overflow. Same class bug in `Modal`, likely to
  be cloned into other widgets.
- **Long URLs in inline links.** `markdown.ex:114` renders
  `[text](url)` as `text (url)` — a 100-char URL pushes body layout
  beyond any sane width. Consider truncating URLs to host-only in the
  body render and exposing the full URL in a footer / view-link screen.
  Do NOT use OSC 8 hyperlinks — `:ssh` clients are inconsistent and iTerm
  needs opt-in; safer to render inline text.
- **Raw markdown rendering in posts (milestone scope #1).** The current
  situation is that posts *do* render through MDEx — if UAT says posts
  "show raw markdown", the likely cause is either:
  1. A path where `render_markdown_tuples/1` is not called (e.g. quoted
     preview in composer at `post_composer.ex:318-325` uses plain
     `"> #{line}"` and never runs markdown). Expected for a quote, bug
     if the reader itself is skipping the call.
  2. Posts stored with escaped markdown (`\*` instead of `*`) — migration
     from old seed format.
  3. `function_exported?(markdown_mod, :render, 1)` returning `false`
     because the context injected a test double without `:render/1`.

**Warning signs:**
- `**bold**` visible as literal asterisks in rendered posts.
- Code fence "```" visible in output (dim styling missing).
- Long URL makes the border shift or disappears off-screen.
- Table renders as one unreadable paragraph.

**Prevention:**
- Write a golden-file test: for each of `bold`, `italic`, `code-block`,
  `nested-list`, `table`, `long-url`, `emoji`, feed the markdown in and
  assert on the `[{text, style}]` output and the final rendered lines.
- Document the "flat renderer" limitations in `Foglet.Markdown` docstring
  so the next person doesn't try to enable GFM tables expecting them to
  render.

**Phase to address:** **Phase P2 — Markdown rendering correctness.**

---

### Pitfall 7: Theme propagation gaps (border un-themed, text themed)

**What goes wrong:**
Milestone scope #6 — "border box and some text don't pick up theme". In
this repo the theme is effectively not wired: `StatusBar` hardcodes
`fg: :green`, `Modal` uses `color_for(:confirm) = :yellow`, everything in
`render_markdown_tuples` uses `fg: :green`. There is no app-level
ThemeManager integration (see cookbook THEMING.md §Theme System —
`Raxol.UI.Theming.ThemeManager.set_theme(:nord)`).

The trap during polish is partial theming:
- Border characters on a `box style: %{border: :single}` are rendered by
  Raxol's layout engine using terminal default fg (usually white/bright)
  while the inner `text/2` uses `fg: :green`. Result: green text in a
  white box. "Theme" looks applied but the frame is jarring.
- Per-widget hardcoded colors (`StatusBar.render/1`'s `fg: :green`) win
  over any theme pulled from `ThemeManager.current_theme()` — you can
  "switch themes" at runtime and see no change except for text that
  explicitly reads from the theme.
- Modal's `color_for/1` switches on `:warning` / `:error` / `:confirm`
  regardless of theme — themed dark-on-dark or light-on-light can render
  as unreadable.
- Foreground-only theming: background is never set, so on a terminal
  where the user has a green background (because their theme is Solarized
  Light), all the `fg: :green` text is invisible.

**Why it happens:**
Theming was stubbed in M4 (see PROJECT.md "user preferences (..., theme
stub)") and the widgets were written against atom colors as placeholders.
Polish scope is the right time to replace hardcoded atoms with a theme
lookup but only if done consistently.

**How to avoid:**
- Introduce one helper `theme_color(state, :accent | :muted | :warn |
  :error)` that all widgets use. Widgets accept `theme_color/2` as a
  function, not a hardcoded atom. Migration is mechanical: grep for
  `fg: :green` and replace.
- Never set `fg` without considering whether to set `bg` too — if the
  theme is background-significant, set both or set neither (let Raxol's
  adaptive color downsampling handle it).
- Border colors: Raxol's border renderer accepts a color in the `style`
  map — check `border_color` or similar in
  `vendor/raxol/lib/raxol/ui/layout/engine.ex` before assuming it's
  uncontrollable. Pass the theme accent for borders in the same call as
  the `:single`/`:double`/`:rounded` style.
- Accessibility: add a `text + color` combination for status indicators
  (`[OK]` green is a hint, not the only signal). See cookbook THEMING §
  Accessibility.

**Warning signs:**
- Changing the theme leaves most of the screen unchanged.
- Border is a different color than the adjacent text.
- UAT on iTerm with Solarized Light shows green-on-white (low contrast).

**Phase to address:** **Phase P1 — Widget Foundation.** Bake theme lookup
into the widget layer from day one; do not retrofit.

---

### Pitfall 8: StatusBar placement inconsistency and re-render storms

**What goes wrong:**
The current StatusBar is hand-placed in every screen's render function
(`board_list.ex:25`, `thread_list.ex:26`, `new_thread.ex:82`,
`post_reader.ex:28`, `post_composer.ex:71`, `verify.ex` doesn't have one
— inconsistency visible to the naked eye). Milestone scope #2 says
"StatusBar should be a reusable widget at the top with a divider beneath".

Traps when centralising:
- Rendering the StatusBar at the app level (in `app.ex view/1`) adds a row
  to every screen. Screens' min-size assumptions break (the 2-step wizard
  assumes ~10 rows for the body input; with +1 row for StatusBar + 1 for
  divider, usable height drops to 8). Composer truncates content without
  warning.
- StatusBar shows "current user connection count" or "live user list" →
  on every Presence diff broadcast, the app re-renders the entire view
  (because Raxol's diff algorithm re-walks the tree on state change). The
  `column` inside every screen rebuilds. Not a performance disaster, but
  if the StatusBar pulls from a GenServer, each render triggers a
  `GenServer.call` → serialises the whole view pipeline on that process.
- If the StatusBar is conditionally hidden (e.g. on `:login` and
  `:verify`), any global-key handler that depends on StatusBar being
  visible misfires. Consistency lapse: user sees it on 7/9 screens and
  the other 2 feel broken.
- A full-width status bar + a `box style: %{border: :single}` inside it
  produces a border-inside-bar visual that depends on the order of
  composition. The existing screens each render their own border *around*
  the status bar (`board_list.ex:18` outer box, StatusBar at
  `:25` inside). Moving StatusBar to `app.ex view/1` flips that order —
  the border is now inside the StatusBar, not around it. Borders will
  appear in a different place than UAT expected.

**Why it happens:**
The StatusBar was born as a widget but placed inside each screen. Moving
it up one layer changes composition rules silently.

**How to avoid:**
- Decide on **one** composition: either StatusBar inside each screen's
  top-level box (status quo, but consistent everywhere including Login
  and Verify) or at `app.ex` level above every screen (explicit, uniform,
  but requires screens to stop drawing their own borders at the outer
  level).
- If live user-count goes in StatusBar, pull it from PubSub only — the
  subscribe_interval / `subscribe` callback makes the refresh declarative
  and off-process. Do not make the StatusBar render function do I/O.
- Reserve rows: if StatusBar adds a row at app level, every screen's
  min-size calculation (`terminal_size[1] - 2 rows`) must account for it.
  Write a single `usable_height/1` helper and use it everywhere.
- Add a visual-regression test: render every screen at 80x24 and compare
  the top 3 rows to an expected snapshot.

**Warning signs:**
- Two screens show StatusBar in slightly different positions.
- Composer body visibly loses a line of content after the StatusBar
  addition.
- UAT reports "lag" when a user joins/leaves.

**Phase to address:** **Phase P1 — Widget Foundation.**

---

### Pitfall 9: Email verification toggle security holes

**What goes wrong:**
Milestone scope #10 says toggle verification per registration mode via
sysop config, and wire resend. The toggle introduces three security
pitfalls:

- **Retroactive bypass.** A user registered yesterday with
  `confirmed_at: nil`. Sysop flips
  `require_email_verification = false`. Next login: does that user
  become confirmed? Currently `login.ex:276` redirects *any* user with
  `confirmed_at: nil` to `:verify`. If the polish code changes this to
  `if require_email_verification? and confirmed_at == nil`, the existing
  unverified user silently gains access without ever verifying. May be
  fine; must be an explicit decision.
- **Mode-combination bypass.** `registration_mode: "open"` + `skip
  verification`= free-for-all spam registration. The sysop flip has to be
  accompanied by a warning modal listing the combined effect. Do not
  allow "open + skip_verify" without explicit `--force` intent.
- **Resend abuse.** `Verify.resend_code_raw/1` (verify.ex:206) does not
  check cooldown when called via `{:verify_event, {:resend}}` from
  `app.ex:333`. `resend_code/1` (line 193) does check cooldown, but the
  event path bypasses it. A programmatic client can loop
  `{:verify_event, {:resend}}` as fast as SSH allows and rebuild the
  verify code repeatedly. Accounts.build_verify_code/1 writes to the DB
  — sustained abuse = write amplification. Fix: add cooldown check
  inside `resend_code_raw/1` itself, not at the UI wrapper.
- **Code replay.** Is the code invalidated on a new build? Check
  `Accounts.build_verify_code/1` and whether old codes remain valid. If
  yes, a user who requested 100 codes has 100 valid codes simultaneously.
- **Config cache staleness.** `Foglet.Config` uses ETS
  (`config.ex:20`). `require_email_verification` is read on
  `login.ex` login and on `register.ex` submit via `safe_config_get/2`.
  If the sysop flips the toggle mid-session, ETS has the old value
  until `invalidate/1` is called. Every write via `put!/3` does
  invalidate, but a manual DB `UPDATE` (seeds, migrations) bypasses ETS.
  Document that `put!/3` is the only supported write path.

**Why it happens:**
Toggleable security checks interact with existing user state (`confirmed_at`)
and with config caching in non-obvious ways. Authentication gates are
high-stakes; a one-line fix is tempting but skips the edge cases.

**How to avoid:**
- Explicit decision per edge case, written into the phase plan:
  1. Toggle off → existing unverified users: keep pending OR confirm on
     next login OR batch-confirm via migration.
  2. Toggle off + open registration: require sysop confirm prompt (and
     log the combined state).
  3. Toggle on later: new users must verify; existing confirmed users are
     unaffected; existing pending users continue on the verify path.
- Add cooldown inside `resend_code_raw/1` to close the programmatic-abuse
  gap. Covered by commit `b8744c6 WR-03` partially — audit that path.
- Unit-test all four combinations of (registration_mode, require_email_verification).
- Make `Config.put!/3` the only documented write path.

**Warning signs:**
- User registered under mode X; sysop flipped to mode Y; user has
  different access than expected.
- Log shows > 1 successful `build_verify_code` per user per minute.
- Spam accounts pass through open+skip-verify combo.

**Phase to address:** **Phase P6 — Email verification polish.** Do last
— touches auth flow; requires all other screens to be stable so the user
can actually test.

---

### Pitfall 10: Thread list row info (creator + time-ago) looks easy, isn't

**What goes wrong:**
Milestone scope #5 — "Thread list rows need more info — creator handle,
last-activity time ago". Traps:

- **N+1 query.** Current `Foglet.Threads.list_threads/1` preloads
  `:created_by` (`threads.ex:48`) but NOT the last post or the user who
  made the last post. Adding "last-activity by @handle" means either a
  second preload (`join: p in Post, where: p.id == t.last_post_id`) or a
  per-row query that N+1s.
- **Time-ago stale.** "30s" displayed at t=0 becomes "30s" forever
  unless the view re-renders. Raxol only re-renders on state change.
  Solution: subscribe to a 30s tick in the `:thread_list` screen and let
  it force a re-render. But a 30s tick while the user is typing feels
  like lag — measure actual impact before enabling.
- **Time-ago rollover.** "59s" → "1m" and "59m" → "1h" should happen at
  exact boundaries; off-by-one on `DateTime.diff` unit conversion is
  common. Write a table-test (`{diff_seconds, expected_string}` pairs).
- **Width pressure.** On an 80-col terminal, `> [S] Thread title (47
  unread)` already eats 30 columns with a moderate title. Adding
  `@really_long_handle · 2w` pushes past 80 cols → wrap or truncate.
  Decide the layout budget upfront.

**Why it happens:**
"Just show the time ago" sounds trivial. The staleness and the preload
and the column budget are three separate problems.

**How to avoid:**
- Preload `:last_post` and `:last_post.user` in a single extended query.
  Measure the query plan at 100 threads / 1k threads.
- Either: accept visible staleness (don't tick) and refresh the whole
  list on PubSub `:board_activity` events; or: subscribe to a coarse
  60s tick that only re-renders if the screen is `:thread_list`.
- Truncate title with ellipsis to make room. Prefer "leave time-ago off
  if width < 80" over wrapping — wrap in a list row is UX death.
- Use relative-time helper with table-test coverage:
  - `< 60s` → `30s`
  - `< 60m` → `5m`
  - `< 24h` → `3h`
  - `< 7d` → `2d`
  - `else` → `2w` (or `3w` etc.), then `long ago`

**Warning signs:**
- `mix test` times out after adding preload (schema issue).
- Time-ago strings never update while the user is idle on the screen.
- Thread list becomes two lines per thread on narrow terminals.

**Phase to address:** **Phase P3 — Read-pointer correctness** or
**Phase P4 — Composer**. Group with scope #4 (unread) since both touch
the thread_list render.

---

## Minor Pitfalls

### Pitfall 11: Seeded-thread "don't render properly"

Milestone scope #3 says seeded threads in General don't render properly.
Two likely causes in this repo:

- Seed posts have `message_number = 0` or missing, and `post_reader.ex`
  silently handles it via `Map.get(post, :message_number, 0)`. No visible
  render bug but it poisons the read-pointer advance (Pitfalls 2, 3).
- Seed threads are inserted via `Repo.insert_all/3` bypassing
  `Foglet.Boards.Server.create_thread/3`, so they don't get a
  `last_post_at` / `last_post_id`. `threads.ex:48 order_by: [desc:
  t.sticky, desc: t.last_post_at]` with nil `last_post_at` sorts
  unstably. Fix in the seed (use Boards.Server) or make `list_threads`
  `order_by` resilient to nil.

Commit `9578faf add thread seed; fix threads not showing` suggests this
was already hit once.

**Phase to address:** **Phase P0 — Seeds & fixtures.** Quick win; do
before screen polish so UAT has real data.

---

### Pitfall 12: `:verify_event`, `:register_wizard`, `:command_result` dispatch chain

`app.ex:506-512 {:command_result, inner}` re-dispatches inner messages
through `do_update/2`. `{:verify_event, ...}` and
`{:register_wizard, ...}` each delegate into their screen modules. The
chain is: screen `handle_key` returns `{:update, state, [event_tuple]}`
→ `process_screen_commands/2` at `app.ex:577` detects it's an atom-tuple
→ recursively `do_update/2`.

Trap:
- If a screen returns a tuple the app doesn't know (e.g. adds a
  `{:refresh_unread}` command without wiring `do_update/2` for it), it
  falls through to `do_update(_other, state)` at `app.ex:537` which
  silently drops it. Logger.warning in `process_screen_commands/2` only
  fires for non-atom-tuples.
- The `{:terminate, _}` shortcut at `process_screen_commands/2:583` is
  not documented — screens that want to quit return `{:terminate, :ok}`.
  New screens may not know.

**Phase to address:** **Phase P1 — Widget Foundation.** Document the
dispatch contract in `app.ex` moduledoc so new commands don't vanish.

---

## Technical Debt Patterns

| Shortcut                                                             | Immediate Benefit                                    | Long-term Cost                                                                           | When Acceptable              |
|----------------------------------------------------------------------|------------------------------------------------------|------------------------------------------------------------------------------------------|------------------------------|
| Hardcode `fg: :green` everywhere                                     | Ships fast, looks consistent in dev                  | Theme switching does nothing; retrofitting theme lookup is a cross-cutting edit          | MVP only — fix in v1.0.1     |
| Keep legacy `Foglet.Markdown` flat-HTML-regex pipeline               | Already works for 80% of markdown                    | Tables, nested lists, long URLs fail; hard to extend                                     | Until user-visible breakage  |
| Rebuild MultiLineInput width from `terminal_size` on every resize    | Simple — no width-tracking state                     | Drafts lost on resize; impossible to restore after a too-small event                     | Never acceptable             |
| `|| 0` fallback on `last_read_message_number`                        | No `nil` check needed                                | Pitfall 3 — silently zeroes read pointers                                                | Never acceptable             |
| Write `:ssh_connection.send/3` directly for alt-screen escapes       | No library change needed                             | Ties SSH layer to terminal-control bytes; brittle to raxol upgrades                      | Until Raxol exposes API      |
| StatusBar hardcoded in each screen                                   | No plumbing change                                   | Inconsistent; every new screen must remember to add it                                   | Until widget layer lands     |
| Stubbed-out `function_exported?(...)` branches in screens            | Lets screens compile without Phase 2 ready           | Silent "coming soon" modals hide missing wiring; user confusion                          | Phase 2 complete — remove    |
| Dispatch `{:verify_event, ...}` via `do_update/2` tuple handlers     | Keeps screens pure                                   | New message types must be registered in two places; easy to forget                       | Until Commands DSL stabilises|

---

## Integration Gotchas

Common mistakes when connecting to Raxol, `:ssh`, and Phoenix PubSub.

| Integration                | Common Mistake                                                                                          | Correct Approach                                                                                                                            |
|----------------------------|---------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------|
| Raxol block DSL            | Mix `box(children: [...])` (legacy) with `box do ... end` (modern) in the same render tree              | Only the block form; reference `widgets/status_bar.ex`                                                                                      |
| Raxol Command.task         | Return a plain tuple thinking it'll reach `update/2`                                                    | Tuples from `Command.task` arrive wrapped as `{:command_result, inner}`; `app.ex:506` already unwraps — follow that pattern                 |
| Raxol MultiLineInput       | Call `MultiLineInput.render/2` in view                                                                  | Render its `value` as plain `text/2` lines (see `post_composer.ex:260-286`); known Flexbox crash                                            |
| Raxol Lifecycle            | Pass `context:` at the top level of `start_link/2` opts                                                 | Reaches `init/1` via `%{options: [context: ...]}`; `app.ex:110-126` extracts it                                                             |
| Raxol subscriptions        | Expect arbitrary Phoenix messages to reach `update/2`                                                    | Use `Subscription.custom(PubSubForwarder, %{topics: [...]})` — Raxol only routes `{:subscription, msg}` to `update/2`                       |
| Raxol window event         | Use `Event.window/3`                                                                                    | Use `Event.new(:resize, ...)` so Dispatcher routes through `handle_resize_event/2`; commit `01a0d4a` fixed this                             |
| `:ssh` alt-screen          | Assume Raxol takes over the terminal by default                                                         | Must pass `alternate_screen: true` to Lifecycle AND emit `\e[?1049l` on EOF/closed/graceful exit — see `cli_handler.ex:196, 203, 126`       |
| `:ssh` CRLF                | Pipe Raxol bytes straight to `:ssh_connection.send/3`                                                   | Wrap writer with LF→CRLF translation (`cli_handler.ex:241-252`) or cursor stair-steps                                                       |
| Phoenix.PubSub from TUI    | Subscribe in `init/1` and forget — messages arrive as raw term                                          | Use PubSubForwarder → `{:subscription, msg}` envelope (`app.ex:197-206`); subscriptions list is recomputed per state change                 |
| Ecto read-pointer advance  | Overwrite unconditionally on `on_conflict`                                                              | Guard with `where: ... <` in the conflict update to enforce monotonicity (Pitfall 2)                                                        |
| `Foglet.Config`            | Read directly from DB                                                                                   | Use `Config.get!/1` or `Config.get/2` — ETS cache; `put!/3` invalidates                                                                     |
| Swoosh (not yet enabled)   | Re-enable SMTP without staging                                                                          | v1.0.1 scope is toggle + resend wiring; actual SMTP is M10 (SEED-002) — resist scope creep                                                  |

---

## Performance Traps

| Trap                                                 | Symptoms                                         | Prevention                                                                   | When It Breaks                    |
|------------------------------------------------------|--------------------------------------------------|------------------------------------------------------------------------------|-----------------------------------|
| PubSubForwarder without debounce                     | Typing lag when many users active                | Debounce `:board_activity` at ~250ms; drop intermediate events               | 10+ concurrent users on one board |
| Re-render full tree on every heartbeat               | 10Hz CPU burn on idle session                    | Heartbeat updates session state only; view reads from state — if unchanged, Raxol diffs to zero bytes | 100+ concurrent sessions         |
| StatusBar does `GenServer.call` in render            | Serialised renders; one slow call blocks all    | Read from subscribed state only; never I/O in `view/1`                       | 10+ concurrent sessions           |
| `list_threads` without `:last_post` preload          | N+1 query when showing time-ago                  | Single query with preload; measure at 1k threads                             | Board with 100+ threads           |
| ETS config cache not invalidated after seed          | Polish feature "works in dev, not in prod"       | Always go through `Foglet.Config.put!/3`                                     | First deploy post-seed            |
| Markdown re-render on every keystroke in preview     | Composer feels laggy                             | Memoize `Markdown.render/1` output by draft string hash                      | Long drafts (> 1k chars)          |
| `advance_board_read_pointer/3` on every scroll      | DB write amplification                           | Batch via `{:flush_read_pointers, ctx}` on screen-exit (already the pattern) | Always (well-handled)             |

---

## Security Mistakes

Domain-specific issues beyond generic web security.

| Mistake                                                          | Risk                                                             | Prevention                                                                   |
|------------------------------------------------------------------|------------------------------------------------------------------|------------------------------------------------------------------------------|
| ANSI escape injection in user post bodies                        | Screen takeover, cursor-position attacks, fake UI                | `Foglet.Markdown.strip_ansi/1` already handles this — keep it; test with `\x1b[2J\x1b[1;1H` payloads |
| Resend-code programmatic abuse via `{:verify_event, {:resend}}` | DB write amplification, spam on shared email infra              | Move cooldown check into `resend_code_raw/1` itself (Pitfall 9)              |
| Email-verify toggle without retroactive policy                   | Existing unverified users gain access unintentionally            | Explicit migration / feature flag per decision (Pitfall 9)                   |
| One-session-per-user enforcement bypass via guest promotion      | Two active sessions for one user                                 | `Sessions.Supervisor.promote_guest_session/2` replaces old session (`app.ex:498`); audit that all login paths route through here |
| Stash pubkey in ETS keyed by `{ip, port}`                        | Another client on same NAT reusing the port gets wrong identity  | Expire stash after N seconds; log miss-then-hit patterns                     |
| Markdown link rendering fetching external data                   | Terminal-render server makes outbound request                    | Current code strips src on images and renders URL as text — do not add auto-fetch |
| SSH per-peer connection limit at 500 (`cli_handler.ex:55`)      | DoS via slow-loris connections                                   | Also add per-IP rate limit and per-user session cap                          |
| Modal text directly interpolating user input                     | Broken rendering on user-controlled content                      | `format_error(cs)` iterates changeset errors — safe; do not `inspect/1` user fields in modals (commit `e27b1c1 IN-02` was this bug) |

---

## UX Pitfalls

| Pitfall                                                          | User Impact                                                       | Better Approach                                                              |
|------------------------------------------------------------------|-------------------------------------------------------------------|------------------------------------------------------------------------------|
| "Terminal too small" replaces content                            | Resize to small → resize back → lost draft                        | Render-time branch, preserve state (Pitfall 4)                               |
| Composer crash on [C] from thread_list                           | Thread can't be created; no feedback                              | Route [C] to :new_thread (Pitfall 5)                                         |
| Stale unread count                                               | User doesn't trust the count; checks boards needlessly            | Monotonic pointer + refresh on navigate (Pitfall 2)                          |
| Theme switch does nothing visible                                | Feature appears broken                                            | Widget-level theme reads (Pitfall 7)                                         |
| Modal dismisses the underlying screen (pre-fix)                  | User has to re-navigate                                           | Current code (after commit `200f163`) dismisses modal only — keep this      |
| Markdown renders differently in preview vs posted                | "Why did my post look different?"                                 | Same renderer path — currently true; test to prevent divergence              |
| Time-ago doesn't update                                          | "Was this posted 2s ago or 2h ago?"                               | Low-frequency tick OR refresh-on-activity (Pitfall 10)                       |
| KeyBar and StatusBar misalign across screens                     | Each screen feels like a different app                            | Central widget + snapshot test (Pitfall 8)                                   |

---

## "Looks Done But Isn't" Checklist

- [ ] **Markdown rendering (scope #1):** verify posts render through
      `Foglet.Markdown.render/1` in ALL paths (post_reader, composer
      preview, new_thread preview, thread-list body snippet if added) —
      not just the most obvious one.
- [ ] **StatusBar (scope #2):** present on ALL 9 screens (including
      login, verify) or NONE — no silent exceptions. Measure y-position
      pixel-identical across screens.
- [ ] **Seeded threads (scope #3):** verify `message_number > 0` and
      `last_post_at != nil` via IEx; otherwise the ordering and
      unread-count math are silently wrong.
- [ ] **Unread count (scope #4):** UAT scenario "read every thread, go
      back to boards → 0 unread" — don't stop at "the query is right",
      verify the cache refreshes.
- [ ] **Thread list info (scope #5):** verify the query plan in EXPLAIN;
      N+1 only appears at scale.
- [ ] **Theme (scope #6):** switch theme → verify EVERY widget updates,
      including borders. "fg: :green" grep should return zero hits
      outside the theme helper.
- [ ] **New-thread from board page (scope #7 + #11):** UAT with [N] on
      board_list AND [N] on thread_list AND [R] on post_reader; all three
      exit-routes land on the correct screen.
- [ ] **Widget layer (scope #8):** every screen uses the widget helpers
      — no screen redefines its own header/footer inline.
- [ ] **Min terminal size (scope #9):** resize below threshold →
      content hidden, state preserved; resize back → content
      restored unchanged.
- [ ] **Email verify toggle (scope #10):** all four mode-combinations
      tested; resend cooldown on both `resend_code/1` AND
      `resend_code_raw/1`.
- [ ] **Alt-screen leave (SSH resilience):** verify `\e[?1049l` sent on
      graceful quit, EOF, closed-without-EOF, and Lifecycle crash.
- [ ] **Every screen smoke test (Pitfall 1):** add new screens to the
      view-compile test list (commit `86d82f1` is the canary).

---

## Recovery Strategies

| Pitfall                             | Recovery Cost | Recovery Steps                                                                                           |
|-------------------------------------|---------------|----------------------------------------------------------------------------------------------------------|
| Legacy-DSL silent empty render      | LOW           | Grep for `box(children:`, `panel(`, `column(children:`; convert to block form; add to smoke test        |
| Stuck unread count                  | MEDIUM        | Add monotonicity guard in `advance_board_read_pointer/3`; run one-off migration to `GREATEST` existing + current-max-per-board; refresh BoardList on navigate |
| Composer state-machine trap         | LOW           | Delete [C]→PostComposer branch in thread_list; add [N]→:new_thread; audit `title_for/2` cases          |
| Resize state loss                   | MEDIUM        | Move "too small" to render-branch; guard `do_update({:window_change, ...})` with size-changed check    |
| Theme partial application           | MEDIUM        | Introduce `theme_color/2`; grep-replace hardcoded atoms; widget-level test                              |
| Email-verify bypass                 | HIGH          | Policy decision doc; migration for existing users; unit-test all mode combos; audit log                 |
| Resend-code abuse                   | LOW           | Move cooldown into `resend_code_raw/1`                                                                   |
| Markdown table or long-URL break    | LOW           | Pre-process markdown: tables → "(table view not supported)"; long URLs → truncate at boundary           |
| Alt-screen residue on disconnect    | LOW           | Belt-and-suspenders `\e[?1049l` in all three exit paths; already present — add regression test         |

---

## Pitfall-to-Phase Mapping

Suggested phase order for the polish milestone. Each phase should leave the
app in a UAT-testable state.

| Phase | Name                          | Pitfalls Addressed    | Milestone Scope Items | Verification                                           |
|-------|-------------------------------|-----------------------|-----------------------|--------------------------------------------------------|
| P0    | Seeds & fixtures              | 11                    | #3                    | Seeded General shows 2+ threads with real posts        |
| P1    | Widget foundation (+ theme)   | 1, 7, 8, 12           | #2, #6, #8            | Every screen uses StatusBar widget; theme switch works |
| P2    | Markdown rendering            | 6                     | #1                    | Golden-file test for each markdown feature             |
| P3    | Read-pointer correctness      | 2, 3, 10              | #4, #5                | "Read all, return to boards, zero unread" UAT          |
| P4    | Composer & thread creation    | 5                     | #7, #11               | [N] on board_list creates thread; [R] on reader replies |
| P5    | Resize & min-size gating      | 4                     | #9                    | Resize below threshold → preserved state → restored    |
| P6    | Email verification            | 9                     | #10                   | All four toggle × registration_mode combos tested      |

**Phase ordering rationale:**
- P0 first — without valid seeds, later UAT is impossible.
- P1 second — every later phase touches widgets; establishing the
  foundation (theme, block DSL discipline, StatusBar) prevents
  cross-cutting rework.
- P2 before P3 — read-pointer UAT requires readable posts.
- P3 before P4 — composer's "thread created" navigation lands on
  post_reader, which pulls a read-pointer path; do not introduce a new
  writer while the reader math is wrong.
- P4 before P5 — resize gating wraps around all screens including the
  new thread-creation flow; need the flow stable first.
- P6 last — auth flow change; safest when every other screen is
  stable so regression surface is minimal.

---

## Sources

- This repo's git log (`git log --all --oneline`) — commits
  `01a0d4a`, `83c6bf5`, `7171160`, `5099a35`, `51acce7`, `86d82f1`,
  `8001bf5`, `7643a27`, `b8744c6`, `c53dac0`, `200f163`, `e27b1c1`,
  `bc2f17d`, `164417e`, `9578faf`, `e5b04cb`.
- `lib/foglet_bbs/tui/app.ex` — dispatch chain, command routing
- `lib/foglet_bbs/tui/screens/*.ex` — each screen's render + key handlers
- `lib/foglet_bbs/ssh/cli_handler.ex` — alt-screen, resize, CRLF, pubkey
- `lib/foglet_bbs/markdown.ex` — HTML-regex pipeline, sanitisation
- `lib/foglet_bbs/boards.ex`, `threads.ex` — read-pointer semantics
- `lib/foglet_bbs/config.ex` — ETS cache behaviour
- `docs/raxol/cookbook/{BUILDING_APPS,THEMING,SSH_DEPLOYMENT}.md`
- `docs/raxol/getting-started/WIDGET_GALLERY.md`
- `vendor/raxol/lib/raxol/ui/layout/engine.ex` — `justify_content`
  support confirmation
- Memory `feedback_raxol_modern_dsl.md` — legacy-DSL lesson
- `.planning/seeds/SEED-002-email-verification-ux.md`
- `.planning/workstreams/phase-03-polish/STATE.md` — milestone scope

---
*Pitfalls research for: Foglet BBS Phase 03 polish (v1.0.1)*
*Researched: 2026-04-19*
