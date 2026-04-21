# Architecture Research — Screen Audit Workstream

**Domain:** TUI screens over Raxol + SSH, 9 screens, 18 widgets, App dispatcher
**Researched:** 2026-04-21
**Confidence:** HIGH (every observation below cites a real file + line range)

---

## 1. Scope

This is a **retrospective** architecture pass. The system shape (App → Screens →
Widgets, Theme struct, ScreenFrame chrome, SSH → Session → TUI runtime) is
locked by `phase-03-polish` and MUST NOT be redesigned. The audit's job is
to pull the 9 screens up to the bar set by the widget library and theme
contract shipped in that workstream.

Two concerns per screen:
- **(a) Idiomatic Elixir correctness** — pattern-match hygiene, guard usage,
  dead code, drift between screens.
- **(b) Styling / primitive adoption** — replace inlined layout with the
  widgets we already have; enforce D-07/D-09/D-13 theme routing.

Bias: **sparseness**. Phases 4-9 of the main roadmap (Presence, Chat, DMs,
Search, Oneliners) will layer functionality on top of these screens. Every
audit phase must leave **more** empty real estate, not less.

---

## 2. Current Architecture (inherited, unchanged)

```
┌─────────────────────────────────────────────────────────────────┐
│                      Foglet.TUI.App                             │
│                                                                 │
│  State struct  ── update/2 ── view/1                            │
│       │             │             │                             │
│       │   size-gate + modal intercept (D-11/D-12)               │
│       │   key dispatch: modal? → screen.handle_key/2 → global   │
│       │   command processor: {:load_*}, {:flush_*},             │
│       │     {:promote_session}, {:register_wizard},             │
│       │     {:verify_event}, %Command.task{}                    │
│       └─> PubSub topics (board:/thread:/user:) built per screen │
└─────────────────────────────────────────────────────────────────┘
              │                    │                    │
              ▼                    ▼                    ▼
      ┌───────────────┐   ┌───────────────┐   ┌───────────────┐
      │ Screens.*     │   │ Widgets.*     │   │ SizeGate      │
      │ render/1      │   │ render/*      │   │ too_small?/1  │
      │ handle_key/2  │   │ init+handle_  │   │ render/1      │
      │ screen_state  │   │   event       │   │ (bypasses     │
      │ (per-key map) │   │ (D-14/D-16)   │   │  ScreenFrame) │
      └───────────────┘   └───────────────┘   └───────────────┘
              │                    │
              └────── Theme (D-07/D-09) explicit :theme kwarg ─────┘
```

Source anchors:

- Dispatch table: `lib/foglet_bbs/tui/app.ex:739-747` (`screen_module_for/1`)
- Key routing: `app.ex:319-352` (`do_update({:key, ...})`)
- Modal intercept: `app.ex:329-334` + `app.ex:687-726` (`global_key_handler` +
  `handle_modal_key`)
- Size gate: `app.ex:149-164` (`view/1` cond), `app.ex:321-327` (key swallow)
- ScreenFrame contract: `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex:32-52`
- Theme extraction pattern (the one inlined by every screen):
  `(Map.get(state, :session_context) || %{}) |> Map.get(:theme) || Theme.default()`

---

## 3. Target Screen-Internal Shape

### 3.1 Canonical layout (every screen SHOULD follow)

Every screen module should have these sections **in this order**, labelled
with section-comment dividers. We already have partial adoption — `NewThread`
and `PostComposer` use them; others don't.

```elixir
defmodule Foglet.TUI.Screens.X do
  @moduledoc "..."

  # 1. Aliases + imports (always: Theme, ScreenFrame, any widgets)
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  # ... domain aliases
  import Raxol.Core.Renderer.View

  # 2. Module attributes (@menu_keys, @max_attempts, etc.)

  # 3. Screen-state initialiser (public — called by navigators)
  @spec init_screen_state(keyword()) :: map()
  def init_screen_state(opts \\ []), do: ...

  # 4. Public render/1
  @spec render(map()) :: any()
  def render(state), do: ...

  # 5. Public handle_key/2
  @spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
  def handle_key(key, state), do: ...

  # 6. Public domain-hook callbacks (load_boards/1, load_posts/2, ...)
  #    ONLY if App.update/2 dispatches by name — most screens delegate via
  #    command tuples and don't need these anymore (see §5.3).

  # 7. Private — key handlers (handle_<step>_key/3, move_selection/2, ...)

  # 8. Private — render helpers (render_<section>/N)

  # 9. Private — state plumbing (get_ss/put_ss/default_ss)

  # 10. Private — domain plumbing (domain_module/2, format_error/1, ...)
end
```

### 3.2 Drift between screens today

| Screen | Has `init_screen_state/1`? | Has `get_ss/put_ss`? | Inlines theme extraction? | Returns `:no_match` cleanly? |
|---|---|---|---|---|
| `Login` | NO (state inlined in render path — `login.ex:154-161`) | yes (`get_login_ss`/`put_login_ss`) | YES (`login.ex:36`) | yes |
| `Register` | NO (uses top-level `state.register_wizard` field) | NO — wizard lives on `state` directly | YES (`register.ex:30`) | yes |
| `Verify` | NO (uses top-level `state.verify_state` field) | NO — verify state lives on `state` directly | YES (`verify.ex:41`) | yes |
| `MainMenu` | NO (stateless — no `screen_state[:main_menu]` key) | N/A | YES (`main_menu.ex:18`) | yes |
| `BoardList` | NO (just a literal default `%{selected_index: 0}` in `render/1` + `handle_key/2`) | NO — `get_in/Map.put` open-coded | YES (`board_list.ex:18`) | yes |
| `ThreadList` | NO (same pattern as BoardList) | NO — open-coded | YES (`thread_list.ex:20`) | yes |
| `PostReader` | NO (uses `default_screen_state/0` + `get_screen_state/1`) | YES (internally) | YES (`post_reader.ex:34`) | yes |
| `PostComposer` | **YES** (`post_composer.ex:127-143`) | YES (`composer_screen_state/1`, `put_input_state/3`) | YES (`post_composer.ex:38`) | yes |
| `NewThread` | **YES** (`new_thread.ex:33-63`) | YES (`screen_state/1`, `put_ss/2`) | YES (`new_thread.ex:80, 115`) | yes |

**Five drift points to normalise in the audit:**

1. **Theme extraction inlined 9 times.** Every `render/1` opens with the same
   four-chain expression. Extract to a single module attribute or a
   screen-helper: e.g. `Theme.from_state(state)` that does the whole chain.
   Kill the duplication across all 9 screens and both modal/size-gate sites
   in App (`app.ex:170`, `screen_frame.ex:34`, `app.ex:149` for SizeGate). This
   is a trivial audit win — MVP deliverable of the first phase.

2. **`init_screen_state/1` convention missing on 7/9 screens.**
   Only `PostComposer` and `NewThread` expose it; others either bake the
   default into `get_ss/1` (PostReader) or lean on a nil-fallback literal
   inside `handle_key/2` (BoardList/ThreadList). Normalise so every screen
   that has a non-empty `screen_state[:X]` key exposes `init_screen_state/1`.

3. **Wizard state stored on top-level struct fields** (`state.register_wizard`,
   `state.verify_state` — declared at `app.ex:53-56, 74-75`). These predate
   `screen_state` and are now an inconsistency. The audit could migrate them
   into `state.screen_state[:register]` / `state.screen_state[:verify]` —
   but doing so touches App's wizard-dispatch path (`app.ex:354-361`) and
   is non-trivial. **Recommendation: leave alone.** Document the exception;
   don't migrate in the audit.

4. **`MainMenu` has no `screen_state` entry at all.** It's pure stateless.
   That's fine — no change needed, but the audit should explicitly note
   "intentionally stateless" in the moduledoc so future contributors don't
   add a default hash reflexively.

5. **`handle_key/2` return-shape consistency.** Most screens return
   `{:update, state, cmds}` or `:no_match`. `PostReader` quietly returns
   `{:update, state, []}` from `advance_post`/`scroll_post` when
   `state.posts == []` to absorb keys during loading (`post_reader.ex:343-347,
   379-383`) — this is correct but undocumented. The audit phase should
   lift a comment explaining the pattern to the moduledoc.

### 3.3 Stateful widget contract (D-14) is NOT used by screens

D-14 says stateful widgets expose `init/1 + handle_event/2 + render/2`. Today,
**none of the screens use widgets that way** — the widgets are invoked as
plain `render/*` function calls and the screen owns any persistent state
(PostReader owns `viewport`; PostComposer owns `input_state`; NewThread owns
`body_input_state`). This is fine — the D-14 contract is for widgets that
bubble events upward via actions, not a forced pattern. The audit should NOT
try to retrofit `handle_event/2` calls into screens that don't need them.

---

## 4. Screens-to-Widgets Boundary Audit

Each observation below has **file + line range + what to swap for**.

### 4.1 Hand-rolled forms that duplicate `Input.TextInput`

**`Login` login form** — `login.ex:180-210`
- Renders `"Handle: {value}█"` / `"Password: {****}█"` as two text lines
  with manual cursor-block and manual `focus_style/1` branching.
- Delete `format_input_line/3`, `input_fg/2`, `focus_style/1`,
  `mask_password/1`, `drop_last_grapheme/1`, `append_to_focused/2`, and the
  entire `handle_form_key/2` family (`login.ex:76-124`).
- Replace with two `Widgets.Input.TextInput` instances (one masked via
  `mask_char: "*"`). Store both in `state.screen_state[:login]` as a
  `%{fields: %{handle: tinput_state, password: tinput_state}, focused: :handle}`.
- This is the single biggest styling win of the audit — Login is ~347 lines
  today and should drop to ~150.

**`Register` wizard input line** — `register.ex:43-48`
- Renders `"> {current_input}█"` manually, masks password by re-rendering the
  whole string as asterisks (`register.ex:133-134`).
- Replace with one `Widgets.Input.TextInput` whose `value` is `w.current_input`,
  swapping `mask_char` when `w.step == :password`. Keeps the wizard's
  "one input field at a time" shape; just upgrades the rendering.
- Drop `display_value/2` and the per-keystroke `handle_key` plumbing at
  `register.ex:60-82` — delegate to `TextInput.handle_event/2`.

**`Verify` code slot** — `verify.ex:55, 138-147`
- Renders `[█_____]` with a manual `pad_buffer_with_cursor/1` helper.
- This is a **single-purpose styled input** (uppercase-only, 6 chars, bracketed).
  The right move is to leave it alone; it's not generic, and a TextInput would
  not materially improve it. Flag the decision in the audit: "verify code slot
  is intentionally custom; do not widget-ise."

### 4.2 List rendering is already adopted (good)

`BoardList`, `ThreadList`, and `NewThread` (board step) all call
`SelectionList.render/3` + `ListRow.render/3` or `ListRow.render_with_metadata/6`.
These are the screens that went through phase-03-polish's primitive-adoption
pass and are the reference implementation.

**`MainMenu` is the outlier** — `main_menu.ex:19-27`
- Renders each menu entry as a manual `text("  [#{k}] #{label}", ...)` inside
  a `column do`. This is a selection list without a selector (no j/k, no
  selected state) — the user picks by letter shortcut.
- Two options:
  - **(a) Leave it alone** — a letter-shortcut menu is conceptually different
    from `SelectionList`, and MainMenu will acquire new entries in Phase 4
    (Presence) and Phase 9 (Oneliners) anyway.
  - **(b) Wrap in a minimal `Widgets.Nav.ShortcutMenu`** (doesn't exist yet) —
    overkill for 3-5 items. **Recommend (a).**
- Same verdict applies to `Login.render_menu/2` at `login.ex:169-178`.

### 4.3 Loading / empty-state messages

Every list-bearing screen has the same `"Loading..."` / `"No foo yet."`
text(...) pair:

| Screen | Loading line | Empty line |
|---|---|---|
| `BoardList` | `board_list.ex:39` | `board_list.ex:29-31` |
| `ThreadList` | `thread_list.ex:45` | `thread_list.ex:33-35` |
| `PostReader` | `post_reader.ex:92-94` | N/A (nil-guards) |
| `NewThread` | `new_thread.ex:84-87` | `new_thread.ex:89-97` |

**Opportunity:** extract a tiny `Widgets.Feedback.LoadingLine.render(theme)`
and `Widgets.Feedback.EmptyState.render(message, theme)`. Low value — three
lines of code each. **Recommend: skip.** Document the pattern in the screen
audit checklist so every screen uses the **same** phrasing ("Loading…" not
"Loading..."; "No boards subscribed." not "No boards.") instead of building
a widget.

### 4.4 Per-screen theme slot drift

All screens correctly go through theme slots (no hardcoded color atoms —
`phase-03-polish` Phase 6 enforced this), but **which** slots get used is
inconsistent:

| Intent | Login uses | Register uses | Verify uses | MainMenu uses | BoardList uses |
|---|---|---|---|---|---|
| Body text | `primary.fg` | `primary.fg` | `primary.fg` | `primary.fg` | (delegates) |
| Dimmed/hint | `dim.fg` | `dim.fg` | `dim.fg` | — | `dim.fg` |
| Error message | `error.fg + [:bold]` | `error.fg + [:bold]` | `error.fg + [:bold]` | — | — |
| Warning / empty | — | — | — | — | `warning.fg` |
| Focus / cursor | `accent.fg + [:bold]` | `accent.fg + [:bold]` | `accent.fg + [:bold]` | — | — |

Consistent. Good. Two minor drifts:

- `BoardList` uses `theme.warning.fg` for the "No boards subscribed" message
  (`board_list.ex:31`). `NewThread` uses `theme.warning.fg` for the same
  intent (`new_thread.ex:94`). `ThreadList` uses `theme.warning.fg` too
  (`thread_list.ex:35`). Consistent — good. But **`Verify.handle_key`
  rejects chars with `:no_match`** which means they fall through to the
  global handler, which returns `{state, []}` — silent swallow. No visual
  feedback to the user. The audit may want to surface a dim-colored
  "accepted chars: A-Z 0-9" hint on Verify — but this adds clutter. **Leave
  as-is; document.**

- `Login.render_login_form` uses both `theme.accent.fg` and `theme.error.fg`
  and manually reaches into `theme.primary.fg`. This is fine —
  the slots are correct, but the branching logic at `login.ex:213-222`
  (`focus_style/1` + `input_fg/2`) is logic that Input.TextInput already
  encapsulates (see §4.1).

### 4.5 Copy-pasted helpers across screens

Three functions appear nearly verbatim in multiple places:

**Theme extraction** (9 copies — see §3.2.1).

**Domain module resolution** — appears in `BoardList.domain_module/2`
(`board_list.ex:111-114`), `NewThread.threads_module/1`
(`new_thread.ex:410-413`), `PostComposer.submit_reply/4`
(`post_composer.ex:284-286` inline), `PostReader.load_posts/2`
(`post_reader.ex:160-161` inline), `PostReader.flush_read_pointers/2`
(`post_reader.ex:198-201` inline). All do the same thing:
```elixir
ctx = Map.get(state, :session_context) || %{}
get_in(ctx, [:domain, :<name>]) || Foglet.<Name>
```

**Extract to:** a lightweight helper module —
`Foglet.TUI.Screens.Domain.get/2` that takes `(state, :boards | :threads |
:posts | :markdown)` and returns the module, defaulting to the canonical
context. Small, one test, drops ~20 lines across the codebase.

**Config safe-getter** — `PostComposer.safe_config_get/2`
(`post_composer.ex:353-360`) vs `NewThread.max_thread_title_length/0`
(`new_thread.ex:427-434`) — same pattern, different cap. NewThread already
cites the "mirrors the PostComposer pattern" comment at line 425. Both are
small enough to leave; extraction is over-abstraction for two call sites.

### 4.6 Widgets that exist but are unused

The widget library has primitives that no screen uses yet. The audit must
**not** treat these as "unused, therefore adopt" — doing so violates the
sparseness rule. Leave unused until a real need surfaces.

| Widget | File | Status |
|---|---|---|
| `Input.Button` | `widgets/input/button.ex` | Unused by screens. Appropriate for Phase 4/5 confirm-modal actions, not this audit. |
| `Input.Checkbox` | `widgets/input/checkbox.ex` | Unused. Candidate for future Phase 8 sysop prefs — NOT for this audit. |
| `Input.Tabs` | `widgets/input/tabs.ex` | Unused. Candidate for Phase 5 chat split-pane — NOT for this audit. |
| `Input.Menu` | `widgets/input/menu.ex` | Unused. Candidate for future context menus. |
| `Display.Table` | `widgets/display/table.ex` | Unused. Overkill for current 9 screens. |
| `Display.Tree` | `widgets/display/tree.ex` | Unused. Candidate for reply-threading later. |
| `Display.Progress` | `widgets/display/progress.ex` | Unused. No long-running ops in TUI yet. |
| `Progress.Spinner` | `widgets/progress/spinner.ex` | Unused. Same — no long ops. |
| `List.SmartList` | `widgets/list/smart_list.ex` | Unused. Current boards/threads counts tiny; SelectionList is enough. |
| `Input.RadioGroup` | `widgets/input/radio_group.ex` | Unused. Candidate for theme picker (Phase 4) — NOT this audit. |
| `Input.TextInput` | `widgets/input/text_input.ex` | **Unused today — SHOULD be adopted by Login (and maybe Register), see §4.1.** |

**Principle for the audit:** "Widgets exist for a purpose. Adopting them as
ornament violates sparseness. The only widget this audit should newly adopt
is `Input.TextInput` in Login."

---

## 5. Screen ↔ App Boundary Audit

### 5.1 Modal intercept (clean — leave alone)

App owns the modal key dispatch entirely (`app.ex:329-334, 687-726`) and
never delegates to `screen.handle_key/2` while a modal is open. This is
correct and documented. **No audit action.**

### 5.2 Size-gate intercept (clean — leave alone)

`SizeGate.too_small?/1` in `view/1` short-circuits to `SizeGate.render/1`
without touching screen state (`app.ex:150-156`). Keys are swallowed during
the gate (`app.ex:321-327`). Well-factored; documented. **No audit action.**

### 5.3 Key dispatch (mostly clean, one wart)

Screen `handle_key/2` returns either `{:update, state, cmds}` or `:no_match`.
On `:no_match`, App falls through to `global_key_handler/2`
(`app.ex:336-350`). Today `global_key_handler/2` only handles:
- `q` on `:login` (quit) — `app.ex:693-695`
- No-op catch-all — `app.ex:697`

This is fine, but there's **one inconsistency**: App-level `:terminate`
tuples returned by screens bypass this layer entirely via
`process_screen_commands/2` → `Command.quit()` conversion
(`app.ex:659-678`). That's the right split.

**The wart:** `Login.handle_key` returns `{:terminate, :user_quit}` for Q
(`login.ex:60-61`), while `MainMenu.handle_key` returns `{:terminate, :logout}`
(`main_menu.ex:53-55`). The reason strings are different but both get
converted to `Command.quit()` identically. The audit could consolidate
these quit paths through an `App` helper that preserves reason semantics —
**but this is cosmetic; defer unless the reason propagates to telemetry.**

### 5.4 Domain I/O commands from screens (clean)

Screens emit `{:load_boards}`, `{:load_threads, board_id}`, `{:load_posts,
thread_id, opts}`, `{:flush_read_pointers, ctx}` as commands; App's
`do_update/2` clauses convert them to real off-process `Command.task`
closures (`app.ex:369-468`). This is the right architecture and explicitly
justified in `app.ex:653-658`. The domain call NEVER runs inline in the
Raxol dispatcher.

**Gotcha to preserve in the audit:** Lines 602-622 (`load_threads_for_user/3`)
and lines 626-646 (the `flush_read_pointers_task` helpers) exist in **App**
because the `Command.task` closure must not capture screen state. Any
refactor attempt to "put the domain call in ThreadList" will move it back
to the Raxol process unless done carefully. **The audit phase for
ThreadList must not rewrite this.**

**Minor dead code** — `ThreadList.load_threads/2` (`thread_list.ex:128-147`),
`BoardList.load_boards/1` (`board_list.ex:86-91`), `PostReader.load_posts/2`
(`post_reader.ex:158-181`), `PostReader.flush_read_pointers/2`
(`post_reader.ex:197-209`) appear to be public hooks for direct App
dispatch. Cross-reference: `app.ex:369-422, 430-468` implement their own
task closures and do NOT call these screen hooks. **Verify whether the
screen-side `load_*` functions are dead**; if so, delete. If they're used
by tests, leave + document. The audit phase for each screen should include
this verification as a checklist item.

### 5.5 Wizard + verify-event dispatch (odd but justified)

`Register.handle_key` returns `{:register_wizard, {:submit_step, step, value}}`
which App's `do_update/2` routes back into `Screens.Register.handle_wizard_event/2`
(`app.ex:354-356`, `register.ex:95-104`). Same for Verify. This is a
self-dispatch round-trip that lets the wizard logic be tested without a
real keystroke stream (explicit in `register.ex:86-90`).

It's awkward but it's a tested contract. **The audit must not try to
inline the call back into `handle_key/2`** — it would break the test
surface. Document the pattern in each screen's moduledoc.

---

## 6. Data Flow — Per Screen

Brief. One line each on domain calls, N+1 concerns, render-path calls.

| Screen | Domain modules touched | In render path? | N+1 risk |
|---|---|---|---|
| `Login` | `Accounts.authenticate_by_password/2`, `Accounts.post_login_screen/1`, `Accounts.build_verify_code/1`, `Config.get/2` | `Config.get` on every render via `registration_mode/1` (`login.ex:140-147`) — cached via session_context usually, but falls back to DB hit if nil. **Minor concern.** | None. |
| `Register` | `Accounts.register_user/1`, `Accounts.register_pending_user/1`, `Accounts.consume_invite_code/1`, `Accounts.build_verify_code/1`, `Accounts.post_login_screen/1`, `Config.get/2` | `Config.get` on every render path (same as Login). | None. |
| `Verify` | `Accounts.verify_email_code/2`, `Accounts.build_verify_code/1`, `Config.get/2` | `Config.get` on resend only — not in render. Good. | None. |
| `MainMenu` | None | None. | None. |
| `BoardList` | `Boards.list_subscribed_boards/1` via App-side command (off-process) | None — board list is pre-loaded into `state.board_list`. Good. | None — single query with preloads expected; verify on Boards side, not here. |
| `ThreadList` | `Threads.list_threads/1` or `/2` via App-side command | None — thread list is pre-loaded. Good. | **Thread.created_by.handle is accessed in render** (`thread_list.ex:70`). Requires `Threads.list_threads` to preload `:created_by`. Flag for verification. |
| `PostReader` | `Posts.list_posts/1`, `Boards.advance_board_read_pointer/3`, `Threads.advance_thread_read_pointer/3`, `Markdown.render/1` | `Markdown.render/1` IS called in render path via `parse_body/2` (`post_reader.ex:284-300`), mitigated by `render_cache` keyed on `{post_id, w}` (`post_reader.ex:66`). First render parses; cache hit thereafter. | Posts loaded all at once; pagination is client-side. For a 500-post thread this is a lot of memory + a lot of markdown parsing. Acceptable for now; flag as "likely needs a phase beyond the audit". |
| `PostComposer` | `Posts.create_reply/4`, `Config.get!/1` | `Config.get!` via `safe_config_get/2` on every render (`post_composer.ex:341-351`) — called when char-counter recomputes. Same as Login/Register. **Minor concern.** | None. |
| `NewThread` | `Threads.create_thread/3`, `Config.get!/1` | `Config.get!` on every render via `max_thread_title_length/0` (`new_thread.ex:119, 427-434`). Same concern. | None. |

**One cross-cutting finding:** `Config.get/2` and `Config.get!/1` are called
from render paths on 5 screens (Login, Register, Verify, PostComposer,
NewThread). Five screens × 1-2 calls per render × ~30 renders per session =
~200 DB hits unless the Config module caches. **Flag for audit: verify
Config caches.** If not, this is a real bug and belongs in its own
pre-audit gap closure, not a styling phase.

---

## 7. Per-Phase Checklist (drives all 9 phases)

Every screen audit phase should run through this checklist. If the
requirements doc adopts this verbatim, roadmapping for the 9 phases
becomes mechanical.

### Shape

- [ ] Moduledoc covers: purpose (SSH-0X refs), sub-state shape, cross-references
  (e.g. "Paired with NewThread on Ctrl+S path")
- [ ] Sections in canonical order (§3.1): aliases → attrs → init → render →
  handle_key → public hooks → private key handlers → private render helpers →
  private state plumbing → private domain plumbing
- [ ] `init_screen_state/1` exposed (unless intentionally stateless — comment
  in moduledoc if so)
- [ ] Screen state default merge goes through a single `get_ss/1` / `put_ss/2`
  pair (no `Map.put` / `get_in` scatter)
- [ ] `handle_key/2` returns `{:update, _, _}` or `:no_match` — no silent
  `{:update, state, []}` absorptions without a moduledoc comment
- [ ] No copy-pasted domain resolver; use the `Screens.Domain.get/2` helper
  (Phase 1 deliverable — see §8)

### Theme + widgets

- [ ] No inlined theme extraction — use `Theme.from_state/1`
  (Phase 1 deliverable — see §8)
- [ ] Every `text/2` / widget call routes colors via `theme.<slot>.fg` — no
  hardcoded color atoms
- [ ] Every widget call passes `theme:` explicitly (D-13)
- [ ] Any list rendering uses `SelectionList` + `ListRow` — no hand-rolled
  `Enum.map/2` over items into `text/2` when a list selector is in play
- [ ] `"Loading…"` uses `theme.dim.fg`; `"No foo yet."` uses `theme.warning.fg`
  (consistency rule from §4.3)

### Sparseness

- [ ] No decorative dividers, ASCII art, banners, or emoji added during the
  audit (see §9)
- [ ] No new vertical padding beyond what ScreenFrame provides
- [ ] No new horizontal padding beyond existing `column style: %{gap: 0}`
- [ ] Any `text("")` spacer is **kept as-is** if it already exists, but no
  new ones added

### Correctness (Elixir)

- [ ] `mix credo --strict` passes with zero new warnings on the screen
- [ ] `mix dialyzer` passes with zero new warnings on the screen
- [ ] Specs updated if the shape of `screen_state[:X]` changed
- [ ] Dead code audit: does any public `load_*`/`flush_*` function still
  get called by App? (see §5.4) — delete if not, or add a `@doc false`
  comment explaining the test surface
- [ ] No `Config.get/get!` in the render path (see §6 cross-cutting finding)

### Tests

- [ ] Existing tests still pass
- [ ] If widget adoption changed the DOM shape, snapshot/smoke tests updated
  in the same commit
- [ ] No new flaky tests (no `Process.sleep`, no `Process.alive?`)

### Documentation

- [ ] Moduledoc reflects the post-audit shape (not the pre-audit shape)
- [ ] If a decision was made to deviate from the pattern (e.g. "Verify code
  slot is intentionally custom"), it's in the moduledoc with a one-line
  rationale

---

## 8. Phase 1 (Prelude) — Before the 9 screens

Two extractions that every subsequent phase will use. Doing them first
saves 9× drudgery.

**Extraction 1: `Foglet.TUI.Theme.from_state/1`**
```elixir
# lib/foglet_bbs/tui/theme.ex
@spec from_state(map()) :: t()
def from_state(state) do
  (Map.get(state, :session_context) || %{}) |> Map.get(:theme) || default()
end
```
Used by 9 screens + ScreenFrame + SizeGate + App's modal overlay. One commit.

**Extraction 2: `Foglet.TUI.Screens.Domain.get/2`**
```elixir
# lib/foglet_bbs/tui/screens/domain.ex
@spec get(map(), atom()) :: module()
def get(state, key) when key in [:boards, :threads, :posts, :markdown] do
  ctx = Map.get(state, :session_context) || %{}
  get_in(ctx, [:domain, key]) || canonical(key)
end

defp canonical(:boards), do: Foglet.Boards
defp canonical(:threads), do: Foglet.Threads
defp canonical(:posts), do: Foglet.Posts
defp canonical(:markdown), do: Foglet.Markdown
```
Used by 5+ sites today.

**Recommendation:** treat this as **Phase 0** of the audit workstream, or
the opening half of Phase 1 (Login — the biggest beneficiary). It's not
a screen audit — it's a prerequisite that lets the checklist above have
a single canonical answer for "how do you get the theme?"

---

## 9. Ordering Recommendation (9 phases)

### Tier 1 — Start here (establish the pattern)

**Phase 1 — `Login`**
- **Why first:** biggest styling win (adopt `Input.TextInput`, delete ~40
  lines of form plumbing). Shape is representative of every subsequent
  form-bearing screen (Register, Verify, Composer). Whatever decisions are
  made here (init_screen_state shape, TextInput integration pattern,
  Theme.from_state/1, Domain.get/2) set the precedent.
- **Surfaces learnings about:** TextInput adoption, form-state shape,
  focus handling, `get_ss/put_ss` pattern.
- **Depends on:** Phase 0 prelude (Theme.from_state, Domain.get).
- **Parallel-safe:** No — the pattern it sets is reused by Phases 2, 3, 8, 9.

### Tier 2 — Apply the pattern to other forms

**Phase 2 — `Register`** (applies Login's TextInput pattern to wizard steps)
**Phase 3 — `Verify`** (intentionally doesn't adopt TextInput — documents why)

Both depend on Phase 1 to know what the TextInput integration looks like.

### Tier 3 — Stateless / simple

**Phase 4 — `MainMenu`**
- Smallest screen (58 lines). Pure stateless. Little more than a moduledoc
  update, sparseness audit, and a `Theme.from_state/1` swap.
- Good "easy win" to build momentum after the heavy Register/Verify phases.
- **Parallel-safe with Phases 5, 6.**

### Tier 4 — List screens (already well-adopted)

**Phase 5 — `BoardList`**
- Mostly already uses SelectionList/ListRow. Work is: extraction adoption,
  dead-code audit of `load_boards/1`, empty-state wording normalisation.
- **Parallel-safe with Phases 4, 6.**

**Phase 6 — `ThreadList`**
- Same pattern as BoardList. Additionally: verify `:created_by` preload
  expectation (§6 data flow) is real.
- **Parallel-safe with Phases 4, 5.**

### Tier 5 — Composer family

**Phase 7 — `NewThread`**
- Has the cleanest shape already (`init_screen_state/1`, `get_ss/put_ss`
  equivalents). Audit is: extraction adoption, checklist compliance,
  sparseness check on the title-input row.
- **Parallel-safe with Phase 8.**

**Phase 8 — `PostComposer`**
- Shape matches NewThread. Additionally: verify `max_post_length` config
  path (§6 cross-cutting concern).
- **Parallel-safe with Phase 7.**

### Tier 6 — Largest / most intertwined (last)

**Phase 9 — `PostReader`**
- 425 lines; most complex single screen. Owns: Viewport state, render_cache,
  read-pointer seeding + flushing, markdown parsing cache warming.
- Leave for last because: (a) the audit pattern will be most refined by
  then, (b) any learnings from Phases 1-8 apply here, (c) the refactor
  surface is large — catching mistakes benefits from practice on simpler
  screens first.
- **Parallel-safe with nothing in tier 6.**

### Parallelism map (if user later wants to parallelize)

| Tier | Phases | Parallel? |
|---|---|---|
| 1 | `Login` | No — sets precedent |
| 2 | `Register`, `Verify` | Yes — if Phase 1 done |
| 3-4 | `MainMenu`, `BoardList`, `ThreadList` | Yes with each other |
| 5 | `NewThread`, `PostComposer` | Yes with each other |
| 6 | `PostReader` | Must be last |

Critical path under parallelism: Phase 0 → Phase 1 → (2+3 parallel) → (4+5+6
parallel) → (7+8 parallel) → Phase 9. 5 serial blocks instead of 9.

---

## 10. Sparseness Risks (per-region protection)

The audit's stated bias is sparseness. The checklist prohibits decorative
additions, but specific layout regions in the current code will invite
creative fill. Flag these in the requirements explicitly.

### Region 1 — MainMenu between "Welcome" and the 3 menu items

`main_menu.ex:20-26`: the layout is:
```
Welcome back, @handle.
<blank>
  [B] Browse Boards
  [C] Compose New Thread
  [Q] Logout
```

The area between "Welcome back" and the menu items, and the area below the
menu items down to the KeyBar, is **empty**. This is where Phase 4 (Presence
"Who's online"), Phase 9 (Oneliners shoutbox), and Phase 6 (Notification
badge) will land. **The audit must NOT fill this space with ASCII art,
status text, date/time, or decorative dividers.** The requirements should
say explicitly: "MainMenu retains exactly 4 content lines. Any addition
triggers a roadmap discussion."

### Region 2 — BoardList left column (before board names) and right gutter

`board_list.ex:42-46`: each row is just the board name + optional `" (N
unread)"` suffix. The left gutter (beyond the `"> "` / `"  "` selection
marker) is empty, as is the right gutter. Phase 4 will want to show
online-count-per-board there. Phase 6 will want to show mention-count.
**Audit must not fill either gutter.**

### Region 3 — ThreadList row middle (between title and metadata)

`thread_list.ex:54-68`: ListRow.render_with_metadata already puts metadata
on the right (`"@handle · N posts · Xh ago"`). The padding area is whitespace.
**Audit must not** add sticky icons, read indicators (beyond the existing
`[S] ` sticky prefix), or color-coded tags. Phase 7 moderation will need
this space.

### Region 4 — PostReader header strip (Post X of N / author / divider)

`post_reader.ex:69-72`: three lines at the top of every post — post count,
author line, divider. This is as far as the header should go. **Audit must
not** add post timestamps, upvote counts (Phase 9), post type badges, or
read indicators. The divider line already serves as the visual boundary.

### Region 5 — PostReader footer between body and KeyBar

`post_reader.ex:84-86`: the body is the last element in the content column;
KeyBar follows directly. No footer exists. Phase 6 mentions + Phase 9
upvote counter will want to live here. **Audit must not** add a footer.

### Region 6 — Composer area below char counter

`post_composer.ex:64-67`: the char counter `"{N} / {max} chars"` is the
last content line before KeyBar. **Audit must not** add autosave
indicators, markdown hint line, "Tip: use **bold**" text, or similar.

### Region 7 — Login/Register/Verify below error line

All three screens render errors at the bottom of the content column with
an explicit `text("")` spacer above. The space below the error is free.
**Audit must not** fill it with "Forgot password?" links, "Need help?"
text, or anything adjacent — Phase 10 email notifications will handle
this space.

### Summary: the audit adds NO new lines of screen content

The only content-level changes the audit may make are:
- Replacing hand-rolled input rendering with `Input.TextInput` in Login
  (which will likely reduce line count, not increase).
- Normalising loading/empty-state phrasing (no line-count delta).
- Normalising theme slot names (no line-count delta).

Anything that **adds** a visible element to a screen is out of scope and
triggers a roadmap discussion.

---

## 11. Integration Points — Per Screen (adapted from template)

### Per-screen summary table

| Screen | File | Lines | Primary audit action | Sparseness-critical region |
|---|---|---|---|---|
| `Login` | `screens/login.ex` | 347 | Adopt `Input.TextInput` for handle+password (§4.1). | Below-error footer (R7) |
| `Register` | `screens/register.ex` | 294 | Adopt `Input.TextInput` for wizard input (§4.1). | Below-error footer (R7) |
| `Verify` | `screens/verify.ex` | 271 | Document why code slot stays custom (§4.1); extractions. | Below-error footer (R7) |
| `MainMenu` | `screens/main_menu.ex` | 58 | Moduledoc + extractions only. | Everything below line 4 (R1) |
| `BoardList` | `screens/board_list.ex` | 115 | Extractions + dead-code audit of `load_boards/1` (§5.4). | Row gutters (R2) |
| `ThreadList` | `screens/thread_list.ex` | 196 | Extractions + verify `:created_by` preload (§6). | Row padding (R3) |
| `PostReader` | `screens/post_reader.ex` | 425 | Extractions + dead-code audit (§5.4); LEAVE viewport alone. | Header (R4) + footer (R5) |
| `PostComposer` | `screens/post_composer.ex` | 361 | Extractions only; LEAVE MultiLineInput path alone. | Below char counter (R6) |
| `NewThread` | `screens/new_thread.ex` | 436 | Extractions only; LEAVE MultiLineInput path alone. | Below char counter (R6) |

### Screen → App boundary contracts (what must NOT change)

| Contract | Enforced by | Why |
|---|---|---|
| Screens return `{:update, state, cmds}` or `:no_match` | `app.ex:339-350` | App uses `:no_match` to fall through to global handler |
| I/O tuples get routed through `do_update/2` | `app.ex:659-678` (`process_screen_commands/2`) | Ensures `Command.task` closures run off-process |
| Domain calls go through `session_context.domain.*` overrides | All `load_*` paths in App | Test injection for fake Boards/Threads/Posts |
| Modal rendering goes through App, not screens | `app.ex:169-179` | One source of truth for modal layout |
| SizeGate bypasses ScreenFrame entirely | `app.ex:150-156` | Gate must not be inside any screen chrome |
| Wizard self-dispatch via `{:register_wizard, _}` + `{:verify_event, _}` | `app.ex:354-361` | Test surface for wizard logic without keystrokes |

**Any audit phase that modifies these contracts is out of scope. Raise to
the roadmap.**

---

## 12. Anti-Patterns (audit-specific)

### Anti-Pattern 1: "The screen looks bare — let me add something."

**What people do:** Look at MainMenu's three menu items surrounded by
empty space, conclude it's sparse because nobody got to it yet, add a
decorative banner / ASCII logo / `"Connected as @handle"` line.

**Why it's wrong:** The space is reserved for Phase 4 Presence, Phase 6
notifications, Phase 9 oneliners. Filling it now creates layout churn
later.

**Instead:** Leave space. If you feel like something is missing, add a
moduledoc comment noting what milestone will fill the region.

### Anti-Pattern 2: "There's a widget for that — let me use it."

**What people do:** See `Widgets.Input.Tabs` in the library. Decide
PostComposer's edit/preview toggle "should" be a Tabs widget instead of
`Tab` on the handle_key path.

**Why it's wrong:** The current `ss.mode` toggle is a 1-line state field
and a Tab keypress. Adopting Tabs adds ~20 lines of widget state plumbing
and gains nothing visually.

**Instead:** Adopt widgets only when the current code is **worse** for
being inlined — measured by line count saved or bugs fixed. Exactly one
audit in this workstream meets that bar: `Input.TextInput` in Login.

### Anti-Pattern 3: "Consistency means identity."

**What people do:** Notice `Login.render_menu` renders menu items as
`text("  [K] label")` while `BoardList` uses `SelectionList.render + ListRow.render`.
Conclude Login "should" use SelectionList too, for consistency.

**Why it's wrong:** A letter-shortcut menu is not a selection list — no
j/k navigation, no selected index, no hover. Forcing the primitive makes
the code worse.

**Instead:** Consistency applies to theme slots, widget adoption when
semantically appropriate, and shape (§3.1). It does NOT apply at the
"every screen uses the same widget" level.

### Anti-Pattern 4: "Extract it now."

**What people do:** During a screen audit phase, notice a helper pattern
and extract it into a new shared module.

**Why it's wrong:** Extractions done in the middle of a screen audit phase
change the surface area for every subsequent phase. The prelude (§8)
exists specifically to front-load known extractions.

**Instead:** If you find a new extraction opportunity mid-audit, file it
as a gap closure and pursue after the 9 phases complete.

---

## 13. Scaling / Future-Proofing Considerations

Not a scaling audit — at this tier (small BBS, low user count), none of
the screens have a scaling problem. Three flags for the roadmapper to
consider **outside** the audit:

1. **`Config.get/get!` in render paths** (§6 cross-cutting): at 100+ users
   this hits the DB. **Not an audit fix; belongs to a Config caching gap
   closure.**
2. **PostReader loads all posts up-front** (`post_reader.ex:159-162`): at
   500-post threads this is slow. **Not an audit fix; belongs to a
   pagination milestone.**
3. **Per-screen `render/1` re-parses markdown for non-cached posts**
   (`post_reader.ex:66`): the `render_cache` mitigates this for navigated
   posts, but a PubSub-triggered reload (`app.ex:510-520`) reparses
   everything. **Not an audit fix; belongs to a markdown-cache milestone.**

---

## 14. Sources

All observations anchored in the repository. No external sources —
this is a retrospective of already-shipped code.

- `.planning/PROJECT.md` — milestone scope + constraints
- `.planning/workstreams/phase-03-screen-audit/STATE.md` — workstream scope
- `lib/foglet_bbs/tui/app.ex` — App dispatcher, key routing, commands
- `lib/foglet_bbs/tui/screens/login.ex`
- `lib/foglet_bbs/tui/screens/register.ex`
- `lib/foglet_bbs/tui/screens/verify.ex`
- `lib/foglet_bbs/tui/screens/main_menu.ex`
- `lib/foglet_bbs/tui/screens/board_list.ex`
- `lib/foglet_bbs/tui/screens/thread_list.ex`
- `lib/foglet_bbs/tui/screens/post_reader.ex`
- `lib/foglet_bbs/tui/screens/post_composer.ex`
- `lib/foglet_bbs/tui/screens/new_thread.ex`
- `lib/foglet_bbs/tui/widgets/README.md` — widget catalog
- `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex`
- `lib/foglet_bbs/tui/widgets/list/selection_list.ex`
- `lib/foglet_bbs/tui/widgets/list/list_row.ex`
- `lib/foglet_bbs/tui/widgets/input/text_input.ex` — the one widget this
  audit should newly adopt
- `docs/ARCHITECTURE.md` — inherited system architecture

---

*Architecture research for: 9-screen audit of Foglet BBS TUI*
*Researched: 2026-04-21*
*Author: research subagent for `/gsd-new-milestone phase-03-screen-audit`*
