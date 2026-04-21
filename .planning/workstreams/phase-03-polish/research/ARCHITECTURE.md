# Architecture Research — Phase 03 Polish

**Domain:** Elixir/Phoenix SSH BBS with Raxol TUI
**Researched:** 2026-04-19
**Confidence:** HIGH (codebase-grounded; Raxol behavior verified from vendored source at `vendor/raxol/lib/raxol/ui/components/`)

---

## 1. Current Architecture (Baseline)

```
┌─────────────────────────────────────────────────────────────────┐
│                     SSH Client (Raxol Terminal)                 │
└──────────────────────────────┬──────────────────────────────────┘
                               │ SSH + alt-screen (DECSET 1049)
┌──────────────────────────────▼──────────────────────────────────┐
│  Foglet.SSH.CLIHandler  (:ssh_server_channel — per-connection)  │
│  - owns channel lifecycle, PTY, window_change                   │
│  - builds session_context {user, registration_mode, max_post_   │
│    length} then starts Raxol Lifecycle with it                  │
└──────────┬─────────────────────────────────┬────────────────────┘
           │ starts (DynamicSupervisor)      │ spawns (Raxol)
┌──────────▼────────────────┐    ┌───────────▼────────────────────┐
│ Foglet.Sessions.Session   │    │ Raxol.Core.Runtime.Lifecycle   │
│ (GenServer per user,      │    │ ─► Dispatcher                  │
│  registered by user_id;   │    │ ─► Foglet.TUI.App (the "model")│
│  guests are unregistered) │    │    ├── %App{} model struct     │
│ heartbeat, terminal_size, │    │    ├── current_screen (atom)   │
│ replace-on-duplicate      │    │    ├── screen_state (per-screen│
│                           │    │    │   maps)                   │
└───────────────────────────┘    │    └── modal overlay           │
                                 └───────────┬────────────────────┘
                                             │ view/1
                     ┌───────────────────────┴────────────────────┐
                     │  Screens (pure render/handle_key modules)  │
                     │  Login · Register · Verify · MainMenu      │
                     │  BoardList · ThreadList · PostReader       │
                     │  PostComposer · NewThread                  │
                     └───────────────────────┬────────────────────┘
                                             │ composes
                     ┌───────────────────────▼────────────────────┐
                     │  Foglet.TUI.Widgets.*                      │
                     │  StatusBar · KeyBar · Modal                │
                     │  (thin wrappers over Raxol View DSL)       │
                     └───────────────────────┬────────────────────┘
                                             │ uses
                     ┌───────────────────────▼────────────────────┐
                     │  Raxol.Core.Renderer.View (block-macro DSL)│
                     │  box / column / row / text / divider       │
                     │  Raxol.UI.Components.Input.MultiLineInput  │
                     └────────────────────────────────────────────┘
```

### Key Invariants (what's already right)

| Invariant | Location | Why it matters for polish |
|---|---|---|
| One Session GenServer per user | `Sessions.Supervisor` | Don't introduce a second per-user process (StatusBar sibling idea is rejected below) |
| Raxol app is a single TEA loop — one `%App{}`, one `update/2`, one `view/1` | `tui/app.ex:18` | Theme must flow through model/context, not dispatched via messages |
| Screens are pure `{render/1, handle_key/2}` — no process | `tui/screens/*` | Widget API must be function-based, not component-stateful |
| Per-screen state lives in `state.screen_state[:<screen>]` | `app.ex:63`, screens | Widget-owned state (e.g., scroll offset in a List widget) MUST fit here, not in its own process |
| Tasks dispatch via `Command.task/1` returning `{:command_result, inner}` and re-dispatched through `do_update/2` | `app.ex:506-512` | Markdown pre-rendering (if done async) must follow this pattern |
| Modern block-macro DSL only (MEMORY) | everywhere | `Raxol.UI.Components.*` return `%{type: :column, children:...}` tuple-shaped elements that DON'T compose inside modern block-macro trees (see PostComposer Bug B comment at `post_composer.ex:259`) |

---

## 2. Integration Point Decisions

Each decision names its alternatives, picks one, and justifies the choice against codebase reality.

### 2.1 Widget Layer Design

**Question:** How do we organize wrappers/composites over Raxol without duplicating Raxol's own widgets?

**Alternatives considered:**

| Option | Description | Rejected because |
|---|---|---|
| **A. Widgets are Raxol Components** (`use Raxol.UI.Components.Base.Component`) | Full stateful components | Raxol components return `%{type: :column, children: [...]}` tuple-shape trees. Flexbox layout engine crashes on them when nested inside modern block-macro trees — already documented at `post_composer.ex:259-261` ("MultiLineInput.render/2, which returns tuple-shaped elements that crash Flexbox.measure_flex_child/3 (Bug B)"). |
| **B. Widgets are thin render functions** (current pattern: `Widgets.StatusBar.render/1`) | Pure `fn props -> view_ast end` | **CHOSEN.** Composes cleanly inside `column do ... end` blocks. Stateless — state stays in `state.screen_state`. Matches current StatusBar / KeyBar / Modal pattern. |
| **C. Re-export Raxol components directly** | `alias Raxol.UI.Components.Display.StatusBar` | Raxol's StatusBar takes `%{key:, label:}` items and renders bold key + value pairs — useful semantics but tuple-shape output again. Also, its rendering assumes component context and style inheritance we don't wire. |
| **D. Mixed — some function widgets, some component widgets** | Let each widget pick | Inconsistency cost > savings. DSL mismatch surfaces as silent layout failures (MEMORY: "the modern runtime silently fails to lay out"). |

**Decision: B. Function-form widgets.**

**Namespace:** `Foglet.TUI.Widgets.*` (already established). Subdivide by role:

```
Foglet.TUI.Widgets/
├── chrome/          # screen chrome — applied by every screen
│   ├── status_bar.ex    # existing — top bar
│   ├── key_bar.ex       # existing — bottom bar
│   └── screen_frame.ex  # NEW — wraps box+column+status_bar+key_bar (see 2.2)
├── list/            # selection lists (board_list, thread_list, new_thread board picker)
│   ├── selection_list.ex  # NEW — unified j/k-nav list with row renderer callback
│   └── list_row.ex        # NEW — consistent row rendering (marker, columns, dim/bold)
├── post/            # post rendering
│   ├── markdown_body.ex   # NEW — wraps Foglet.Markdown.render/1 → column of text nodes
│   └── post_card.ex       # NEW — "by @handle · 3m ago · #42" header + body
├── input/           # form inputs beyond MultiLineInput
│   ├── text_field.ex      # NEW — single-line masked/plain field for login/register/title
│   └── field_group.ex     # NEW — label + field + error row
├── modal.ex         # existing — dialog body renderer
└── time_ago.ex      # NEW — pure helper `DateTime → "5m"` (not a widget strictly; co-located)
```

**What a widget file contains (contract):**
- Exactly one `@spec render(props :: map()) :: view_ast()` function.
- `render/1` accepts a plain map of props. No structs to keep widgets cheap to call.
- No process state. No GenServer. No `use Component`. Pure function.
- Uses `import Raxol.Core.Renderer.View`.
- May call other Foglet widgets (composition via function call).

**What a widget file does NOT do:**
- Read `Foglet.Config` or `Foglet.Accounts` directly — screens pass props.
- Manage focus, selection, or scroll state itself — screens pass current values.
- Emit commands — screens own key handling and return `{:update, state, cmds}`.

**Justification:** This matches what works (StatusBar/KeyBar) and avoids the tuple-shape tree interop issue. Screens stay the orchestrators; widgets are just view fragments. The "ten items" in the milestone touch 7 of 9 screens — a shared vocabulary reduces churn across all of them at once.

**Minimum viable surface for v1.0.1:**
1. `Chrome.ScreenFrame` (2.2)
2. `List.SelectionList` + `List.ListRow` (unifies BoardList/ThreadList/NewThread)
3. `Post.MarkdownBody` (fixes scope item #1)
4. `Post.PostCard` (fixes scope item #5 — creator handle + time ago)
5. `TimeAgo` helper (fixes scope item #5)

Leave `Input.TextField` / `Input.FieldGroup` for a later polish iteration — login/register forms already work.

---

### 2.2 StatusBar Integration

**Question:** Should StatusBar live inside each screen, a shared layout wrapper, or a sibling process?

**Alternatives considered:**

| Option | Description | Trade-off |
|---|---|---|
| **A. Each screen renders its own StatusBar** (status quo) | Every screen calls `StatusBar.render(%{handle:, location:})` | Duplication. Easy to miss updates when polishing. Already shows inconsistency (scope item #2). |
| **B. Shared layout wrapper at App.view/1** | `App.view/1` wraps every screen's render in status+divider+screen+keybar | Requires every screen to return an inner-content view AND a spec for title/keys. Larger screen-API change. |
| **C. `Chrome.ScreenFrame` helper called by each screen** | `ScreenFrame.render(title: ..., handle: ..., keys: ..., do: screen_content)` | Same output as A structurally, but only one place to change chrome style. Minimal screen-API change (replace existing `box/column` chrome with one call). **CHOSEN.** |
| **D. Sibling process / separate overlay** | StatusBar as its own GenServer or Raxol subscription | Over-engineered. No need for independent ticking — status content is derived from App state at render time. Violates the single-TEA-loop invariant. |

**Decision: C. `Chrome.ScreenFrame` widget.**

**API sketch:**
```elixir
ScreenFrame.render(%{
  handle: state.current_user && state.current_user.handle,
  location: "Boards",          # breadcrumb string
  title: " Boards ",            # inside the border frame
  keys: [{"j/k", "Select"}, {"Enter", "Open"}, {"Q", "Back"}],
  content: (fn -> board_rows end)  # lazy so we don't evaluate when unused
})
```

The `content:` is passed as a zero-arity function so the frame can interleave `content.()` between status and keybar inside the flex container. Equivalent (and currently acceptable): pass the already-built view tree directly as `content:`.

**Terminal-too-small overlay lives here, not per-screen.** `ScreenFrame.render/1` reads `terminal_size` via `state` or a prop, checks against thresholds, and substitutes a "Terminal too small (need ≥ 60×20)" view when below the floor. This fixes scope item #9 once, globally, without tearing down screen state (the check happens at render time only).

**What the StatusBar needs from screens:**
- `handle` (or nil for guest) — sourced from `state.current_user.handle`.
- `location` — a breadcrumb-like string. Screens compute this from their own state: BoardList passes `"Boards"`; ThreadList passes `"Boards → #{board.name}"`; PostReader passes `"Boards → #{board.name} → #{thread.title}"`. Keep it string-valued, not a list-of-segments, for v1.0.1.

**Future extension:** if we later want clock, unread total, or presence count in the bar, extend `ScreenFrame`'s props — not a sibling process.

---

### 2.3 Theme Propagation

**Question:** Single source of truth for theme. How does it reach nested widgets?

**Alternatives considered:**

| Option | Description | Trade-off |
|---|---|---|
| **A. Raxol ThemeManager** (`Raxol.UI.Theming.ThemeManager.set_theme/1`) | Use Raxol's runtime-switchable theme system; components read via `Theme.component_style/2` | Raxol's ThemeManager is process-backed state. It would require adopting Raxol components (2.1.A) to get the benefit — which we've rejected. Orthogonal to our architecture. |
| **B. Per-session theme in `%App{}`** | Add `theme: Foglet.TUI.Theme.t()` to the App struct; pass into every widget render call as a prop | Explicit but verbose — every `render/1` call grows a `theme:` key. |
| **C. Theme in `session_context` map** | Put theme in the context extracted at `init/1`, read via `state.session_context[:theme]` | Session-scoped naturally. Widgets receive theme in their props (like `handle`, `location`), keeping them pure. **CHOSEN.** |
| **D. Application-level config (compile-time)** | Fixed global palette, no per-user override | Rejected by scope item #6 wording — theme should be consistent, and User schema has `theme: :string, default: "default"` (user.ex:41), implying per-user preference is a design goal. |

**Decision: C. Theme in `session_context`, resolved to a `Foglet.TUI.Theme` struct at session start.**

**Shape:**
```elixir
# lib/foglet_bbs/tui/theme.ex  (NEW)
defmodule Foglet.TUI.Theme do
  @enforce_keys [:fg_primary, :fg_dim, :fg_accent, :fg_error, :fg_warning, :border]
  defstruct [:fg_primary, :fg_dim, :fg_accent, :fg_error, :fg_warning, :border]

  def default, do: %__MODULE__{
    fg_primary: :green, fg_dim: :white, fg_accent: :cyan,
    fg_error: :red, fg_warning: :yellow, border: :single
  }

  def nord, do: %__MODULE__{...}
  def get(name), do: ...   # "default" | "nord" | ...
end
```

Resolved once per session in `Foglet.SSH.CLIHandler.build_context/3`:
```elixir
theme = Foglet.TUI.Theme.get(user && user.theme || "default")
%{session_context: %{..., theme: theme}, ...}
```

**Propagation:** widgets receive `theme:` as a prop alongside other data. `ScreenFrame` reads it from state and threads it down — this is cheap because screens don't have deep nesting (2-3 levels typical).

**What this fixes (scope item #6):** The inconsistency comes from every screen hardcoding `fg: :green` / `style: [:bold]` / `border: :single`. With the Theme struct, widgets read those from theme, border picks up theme, text picks up theme. The `box style: %{border: :single, padding: 1}` pattern repeated across all 9 screens becomes `box style: %{border: theme.border, padding: 1}` inside `ScreenFrame`.

**Justification over A:** Raxol's ThemeManager is a nice system, but it's coupled to Raxol components we've rejected. A plain struct in session_context gives us the 80% benefit (consistent palette, per-user default) without the coupling.

**Rejected sub-alternatives:**
- ETS-cached theme: no — session startup already resolves it; no re-read cost.
- Process dictionary / global: no — violates "everything goes through state/context" invariant.

---

### 2.4 Markdown Rendering Pipeline

**Question:** Where does `markdown body → terminal-ready tuples` run? Storage-time, fetch-time, or render-time?

**Current state (confirmed from code):**
- `posts.body_rendered` column exists (`post.ex:18`) but is "stays NULL in Phase 2; computed on demand via Foglet.Markdown.render/1 (D-03)".
- `PostReader.render_post_items/4` calls `Foglet.Markdown.render(body)` → `render_markdown_tuples/1` → a `column` of `text/2` nodes (`post_reader.ex:186-215`).

**Why is markdown appearing as raw (scope item #1)?**
After tracing the code, the markdown pipeline LOOKS correct (Foglet.Markdown → list of {text, style} → render_markdown_tuples → `column` of `text` nodes). **Hypothesis (confidence MEDIUM, needs runtime verification in Feasibility research):**
1. `Foglet.Markdown.render/1` inserts literal `"\n"` tuples as separators (`markdown.ex:252`). The `text/2` node rendered as `text("\n", fg: :green)` may collapse or render as visible `\n` inside the flex row measurement — there's no hard evidence either way from code alone.
2. `render_markdown_tuples/1` wraps in `column style: %{gap: 0}`. If the outer flex context sets `flex-direction: row` (unlikely here) the newlines would flatten. But the containing `column` should be fine.
3. **More likely root cause:** post bodies in the DB (the seeded thread) contain literal markdown characters, and `MDEx.to_html!/1` output is being walked correctly, but the final `clean_tuples → deduplicate_newlines` produces output where `{"\n", :plain}` tuples appear AS LITERAL `\n` text in the rendered terminal because `text/2` preserves the content as-is.

Read the test expectations to confirm: `[{"hello", :bold}]` for `"**hello**"` (markdown.ex:47-48) — works. But `[{"click (https://example.com)", :plain}, {"\n", :plain}]` for a link — here the `{"\n", :plain}` gets rendered as literal newline character in `text(...)` which, inside a `column` with flex layout, is emitted as a visible `\n` (or simply ignored — the terminal doesn't advance a row from text content; it advances from column-child separation).

**That's the bug.** Newline separation between markdown elements must come from being separate `text/2` siblings inside a `column`, not from `\n` characters inside a single `text/2`. `Foglet.Markdown.render/1` emits a flat list; `render_markdown_tuples/1` maps 1:1 → each tuple becomes one `text/2` → the `{"\n", :plain}` tuples become bogus "\n" text children in the column.

**Fix:** `render_markdown_tuples/1` should split the tuple list on `{"\n", :plain}` into groups, emit one `text/2` per group by concatenating content (joining styled runs within a line), and let the `column do` siblings provide line separation. Better: introduce `Foglet.Markdown.render_to_view/2` (width-aware) that emits a view tree directly, bypassing the intermediate tuple list for the common case.

**Alternatives for WHERE rendering happens:**

| Option | Description | Trade-off |
|---|---|---|
| **A. At post-save time, store in `body_rendered`** | Pre-render markdown to a terminal AST on insert | Terminal width varies per session (session's terminal_size). Pre-rendered output pinned to one width is wrong for every other width. Also, stored AST format becomes a schema concern; future renderer changes require backfill. |
| **B. At fetch time, in `Foglet.Posts.list_posts/1`** | Context adds a `rendered:` virtual field | Still width-naive unless caller passes width. And it runs on the DB-fetch task, so if many posts load, we pay the parse cost serially inside one task. |
| **C. At render time, inside `PostReader`/`PostComposer` preview** | Call `Foglet.Markdown.render/1` from the screen render function (status quo) | Happens 60fps-ish during scrolling; MDEx is fast but not free. Width can be read from state.terminal_size. **Cache by `{post.id, width}` in screen_state** to avoid re-parse on every keystroke. |
| **D. Hybrid: render-time + per-post memoization in screen state** | (C) plus caching | **CHOSEN.** Best of both: width-aware (input to the cache key), cheap after first render, no DB schema churn. |

**Decision: D. Render-time with per-screen memoization.**

**Implementation shape:**
```elixir
# In PostReader screen_state:
%{
  selected_post_index: 0,
  markdown_cache: %{post_id => {width, rendered_view_tree}}
}
```
On `:load_posts` completion, or on first render for a post, compute and cache. On window resize (`{:window_change, ...}`), invalidate the cache (clear the screen_state key).

This **fixes scope item #1** by also correcting `render_markdown_tuples/1` to properly group tuples into per-line text siblings.

**Edit history implications:** Edits produce a new `posts.last_edited_at`; the cache key is `post.id` — stale cache after edit. Add `post.last_edited_at` to the cache key (`{post.id, width, post.last_edited_at}`) so edits invalidate naturally.

**`body_rendered` column:** leave NULL. Reserve for a future optimization (e.g., store width-independent HTML or a pre-normalized AST) that can be decided after Phase 04. Don't populate in v1.0.1.

---

### 2.5 Unread-Count Invalidation (Root-Cause Analysis)

**Question:** Why does BoardList show stuck `(6 unread)` next to General?

**Data path (traced from code):**
1. `BoardList.render/1` reads `state.board_list` — set by `{:load_boards}` command (`app.ex:343-355`).
2. `{:load_boards}` calls `Foglet.Boards.list_subscribed_boards(user)` (`boards.ex:162-176`) which computes fresh `unread_counts(user_id)` (`boards.ex:236-252`) via a LEFT JOIN on `board_read_pointers` and `posts` where `message_number > coalesce(last_read_message_number, 0)`. **Query is correct.**
3. Read pointers flush on `PostReader` quit via `{:flush_read_pointers, ctx}` (`post_reader.ex:86`, `app.ex:416-425`) with `last_read_message_number: pos[:last_read_message_number]` — populated inside `PostReader.advance_post/2` (`post_reader.ex:163-171`).

**Root-cause hypotheses, ranked by likelihood:**

**H1 (HIGH confidence): `last_read_message_number` is the LAST POST's message number, not the HIGHEST post the user has seen in that board.**
- `advance_post/2` writes `state.read_position[thread.id] = %{last_read_message_number: post.message_number}` for the *current post being viewed*.
- If the user views thread A first (messages #1, #2, #3) then thread B (messages #4, #5, #6), the flush context for leaving thread B carries `last_read_message_number: 6` — correct.
- BUT if the user views thread B first (reads #4, #5, #6) then thread A (#1, #2, #3), the flush for leaving thread A carries `last_read_message_number: 3` — which OVERWRITES the pointer (`on_conflict: [set: [last_read_message_number: ^3]]`, `boards.ex:195`). The board now thinks user has only read through #3, and #4, #5, #6 become unread again.
- **This is the bug for scope item #4.** The fix: `advance_board_read_pointer/3` should use `GREATEST(last_read_message_number, $new)` in the `on_conflict` clause — monotonic maximum, not replace.

**H2 (MEDIUM confidence): BoardList doesn't refetch on navigation-return.**
- When the user goes `BoardList → ThreadList → PostReader → (reads, advances pointer) → Q (flushes) → back to ThreadList → Q → BoardList`, the transition to `:board_list` is a plain `%{state | current_screen: :board_list}` at `thread_list.ex:101` — **no `{:load_boards}` command** to refresh the count.
- State still shows the stale list from the initial load. Unread count will only drop after a PubSub `:board_activity` message triggers `{:load_boards}` (`app.ex:441-447`) — but read-pointer advances do NOT emit that PubSub message (only new posts would).
- **Additional bug:** ThreadList's `Q` handler should append `[{:load_boards}]` on return, so BoardList sees fresh counts. Similarly, PostReader's `Q` returns to ThreadList without refreshing thread list — so unread counts per thread there are also stale. (This is a parallel bug to scope item #4 but for thread-level counts.)

**H3 (LOW confidence, unlikely given code): ETS cache staleness in Foglet.Config.**
- `Config.get!/1` reads from ETS (`config.ex:44-58`); reads are through-cached. But `unread_count`/`unread_counts` don't touch `Foglet.Config`. This is not the cause.

**Combined fix for scope item #4:**
1. Change `Boards.advance_board_read_pointer/3` to monotonic max on upsert (H1 — the correctness fix).
2. Have ThreadList's `Q` handler and app's post-flush path trigger `{:load_boards}` on return (H2 — the freshness fix).

**Precondition:** the polish phase should include a small test reproducing the thread-order-dependent pointer regression (H1) — otherwise this will bite again.

---

### 2.6 Compose-Title for New Threads

**Question:** New-thread title field — architecture options.

**Current state:** `Foglet.TUI.Screens.NewThread` (`new_thread.ex`) ALREADY EXISTS and handles the full flow: board-pick step → compose step with title + body (MultiLineInput) → submit via `Foglet.Threads.create_thread/3`. The `c: Compose` key from MainMenu (`main_menu.ex:44`) already routes here. The `C: Compose` key on ThreadList (`thread_list.ex:95`) routes to `:post_composer` without title (a reply-style composer missing title).

**So scope item #7 is slightly mis-stated.** The BBS DOES have a NewThread composer with title. What's missing is:
- From **ThreadList**, pressing `C` goes to `:post_composer` instead of `:new_thread`. The composer has no title field, so thread creation from the board page is "impossible" — as written in the scope.

**Alternatives:**

| Option | Description | Trade-off |
|---|---|---|
| **A. Mode flag on PostComposer** | `%{composer_mode: :reply | :new_thread}` — conditional title field | Bloats `PostComposer`. Two screens doing double duty. Reply code path branches everywhere. |
| **B. Route ThreadList's `C` to `:new_thread`** | Re-use existing NewThread screen; pre-populate `ss.board` with the current board and skip the board-pick step | Zero new code. Leverages what already works. **CHOSEN.** |
| **C. Third dedicated screen** | NewThreadFromBoard as a variant | Duplication. |

**Decision: B.** Change `ThreadList.handle_key` `"c"/"C"` clause to navigate to `:new_thread` with pre-filled `ss.board = state.current_board` and `ss.step = :compose` (skip the board-pick step because the board is already known). Minimum diff.

**Rejected alternative rationale:** A mode flag on PostComposer couples reply logic (quote preview from `reply_to`) with thread-creation logic (title validation, first-post allocation via `Foglet.Threads.create_thread/3` not `Foglet.Posts.create_reply/4`). They are different domain paths.

---

### 2.7 Terminal Size Gating

**Question:** Where does the min-size check run?

**Current state:**
- `state.terminal_size` is set at init from context (`app.ex:102`) and updated on `{:window_change, ...}` (`app.ex:247-255`).
- No min-size check exists. Screens render whatever they render regardless of size.

**Alternatives:**

| Option | Description | Trade-off |
|---|---|---|
| **A. Check at mount only** | App.init/1 rejects; session exits if too small | User can't resize up to recover — terrible UX. |
| **B. Check on every window-change event, show "too small" screen** | Toggle a flag; `view/1` renders overlay when true | Requires a new state field + branch in `App.view/1`. Overlays modal-style but doesn't use modal (which has its own semantics). |
| **C. Check at render time in ScreenFrame** | Frame reads `state.terminal_size`, chooses content-or-too-small view | No state field needed. Window resize above threshold auto-restores the screen (no flag to un-set). Screen state preserved beneath. **CHOSEN.** |
| **D. Dedicated process** | GenServer watches size | Way over-engineered for a render-time decision. |

**Decision: C. `ScreenFrame.render/1` gates on `terminal_size`.**

**Threshold:** 60 columns × 20 rows (baseline). Below either, show:
```
┌─ Terminal too small ──────────┐
│ Current: 58×18                │
│ Required: 60×20               │
│ Resize your terminal window.  │
└───────────────────────────────┘
```

**Why it doesn't tear down state:** `view/1` is pure. Choosing a different view on too-small doesn't touch `state.screen_state`. As soon as size crosses threshold, next render is the full screen again with state intact.

**Fixes scope item #9.**

---

### 2.8 Email Verification Toggle

**Question:** Which code paths read `require_email_verification`? Where does the sysop-facing toggle live?

**Current state:**
- `Foglet.Config` is ETS-cached runtime config read from the `configuration` table (`config.ex`).
- `Login.submit_login/1` currently **always** routes users with `confirmed_at: nil` to the verify screen (`login.ex:276-289`) — no toggle.
- `Register.submit/2` for "open"/"invite_only" modes always builds a verify code + goes to verify screen (`register.ex:247-250`).

**Code paths to modify:**

| Path | File | What changes |
|---|---|---|
| Registration success | `register.ex:245-260` (open/invite_only branch) | If `require_email_verification` = false, skip verify step; set `confirmed_at` via `Accounts.confirm_user/1`; navigate straight to `:main_menu` |
| Login with `confirmed_at: nil` | `login.ex:276-289` | If `require_email_verification` = false AND user is active, treat as confirmed — go straight to main_menu |
| Resend affordance | `verify.ex:193-217` (already exists) | No change — resend stays always-on when on the verify screen |
| `session_context` build | `ssh/cli_handler.ex:314-350` | Read `require_email_verification` once at session start, stash in session_context alongside `registration_mode` |

**Where should the sysop-facing toggle live?**

| Option | Description | Trade-off |
|---|---|---|
| **A. Env var only** | `FOGLET_REQUIRE_EMAIL_VERIFICATION=true` read in `config/runtime.exs` | Forces restart to change. Doesn't fit the existing ETS-cached runtime-config pattern used for `registration_mode` (same class of knob). |
| **B. `Foglet.Config` key only** | Seed `require_email_verification = true` by default in seeds; sysop can flip via `Config.put!/3` | Runtime-editable, no restart. Matches `registration_mode` pattern. **CHOSEN.** |
| **C. Both** | Env var seeds the config row on first boot; config row is the source of truth after | Over-engineered until sysop admin TUI (Milestone 8) needs a UI to flip it. |

**Decision: B. `Foglet.Config` key.** Add to `priv/repo/seeds.exs` (or equivalent): `Foglet.Config.put!("require_email_verification", true, nil)`.

Sysop changes it today via Mix task (or direct Config call) — `Foglet.Config.put!("require_email_verification", false, sysop_user.id)`. Milestone 8 adds an in-TUI toggle screen.

**Fixes scope item #10.**

---

### 2.9 Raxol Components — What We Reject and Why

Quick explicit record of which pre-built Raxol widgets we do NOT adopt, and why. This is important because the scope says "don't reinvent" — but some of Raxol's widgets are incompatible with the modern block-macro DSL per MEMORY and per `post_composer.ex:259` comment.

| Raxol widget | Status | Reason |
|---|---|---|
| `Raxol.UI.Components.Input.MultiLineInput` (state struct) | **Adopted** (already in use) — but NEVER via its `render/2`; we read `input_state.value` and re-render with our own `text/2` nodes | Its `render/2` returns tuple-shape that crashes Flexbox. The state machine is excellent — cursor, wrap, etc. |
| `Raxol.UI.Components.Display.StatusBar` | **Rejected** — keep `Foglet.TUI.Widgets.Chrome.StatusBar` | Component output doesn't compose cleanly; Foglet's needs (handle + location) are a 20-line function. |
| `Raxol.UI.Components.MarkdownRenderer` | **Rejected** — keep `Foglet.Markdown.render/1` + Foglet's own renderer | Uses EarmarkParser fallback; we use MDEx (CommonMark + GFM). Our renderer is ANSI-injection-safe (strips raw ESC). Component also returns tuple-shape. |
| `Raxol.UI.Components.Modal.*` | **Rejected** — keep `Foglet.TUI.Widgets.Modal` | Current Modal works; rewrite not worth it for v1.0.1. |
| `Raxol.UI.Components.Input.SelectList` | **Consider for Phase 04** | Could replace our list-row logic. For v1.0.1, build `Widgets.List.SelectionList` as a function — one step at a time. |
| `Raxol.UI.Components.HintDisplay` | **Consider for Phase 04** | Alternative to KeyBar. Current KeyBar works; no urgency. |
| `Raxol.UI.Components.Table` | **Not needed in v1.0.1** | No screens use tabular data yet. |

**Principle:** we use Raxol's **state machinery** (MultiLineInput state struct) and Raxol's **view DSL** (`box/column/row/text/divider`). We avoid Raxol's **stateful component render pipelines** because they're tuple-tree-based and don't compose into block-macro trees.

---

### 2.10 Thread-List Row Upgrade

**Question (scope item #5):** Thread list rows need creator handle, "time ago", post count.

**Architecture impact:**
- `Foglet.Threads.list_threads/1` already preloads `:created_by` (`threads.ex:49`) — no query change needed.
- `thread.last_post_at` already exists on the schema (`thread.ex:11`) — data is there.
- Renderer-side only: `thread_list.ex` → use `Widgets.Post.ThreadListRow` (or extended `List.ListRow`) reading thread.created_by.handle, thread.last_post_at via `TimeAgo.format/1`.

**No new architecture needed.** Purely a widget + renderer change. Flagged here so phase planners route it through the widget layer dependency.

---

## 3. Build Order — Dependency DAG

Goal: order that minimizes churn. Each polish item's dependencies must land first.

```
                      ┌──────────────────────────┐
                      │  Foglet.TUI.Theme struct │  (§2.3)
                      │    (standalone module)   │
                      └────────────┬─────────────┘
                                   │
                                   ▼
                      ┌──────────────────────────┐
                      │  session_context carries  │
                      │  theme at session start   │  (CLIHandler)
                      └────────────┬─────────────┘
                                   │
        ┌──────────────────────────┼──────────────────────────────┐
        ▼                          ▼                              ▼
┌──────────────────┐   ┌────────────────────────┐   ┌──────────────────────┐
│ Widgets.Chrome.  │   │ Widgets.List.          │   │ Widgets.Post.        │
│ ScreenFrame      │   │ SelectionList +        │   │ MarkdownBody +       │
│ (§2.2, §2.7)     │   │ ListRow                │   │ fix render_markdown  │
│                  │   │ (§2.1 list/)           │   │ _tuples (§2.4)       │
│ Theme consumer;  │   │                        │   │                      │
│ status+divider+  │   │ Unifies BoardList /    │   │ Consumes theme;      │
│ content+keybar;  │   │ ThreadList /           │   │ per-post cache in    │
│ size gate        │   │ NewThread board-pick   │   │ screen_state         │
└────────┬─────────┘   └──────────┬─────────────┘   └──────────┬───────────┘
         │                         │                            │
         │   ┌─────────────────────┴────────────────────────────┘
         │   │
         ▼   ▼
┌─────────────────────────────────────────────────────────────────┐
│  Migrate all 9 screens to ScreenFrame + SelectionList +         │
│  MarkdownBody where applicable.                                 │
│  Fixes scope items #1, #2, #6, #9 in one sweep.                 │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
        ┌────────────────────┴────────────────────────┐
        ▼                                              ▼
┌────────────────────────────┐       ┌────────────────────────────┐
│ Widgets.TimeAgo + refactor │       │ Fix Boards.advance_board_  │
│ ThreadList rows (§2.10)    │       │ read_pointer to monotonic  │
│ (adds creator, "5m ago",   │       │ max; ThreadList.Q triggers │
│ post count)                │       │ {:load_boards} (§2.5)      │
│ Fixes scope item #5        │       │ Fixes scope item #4        │
└────────────────────────────┘       └────────────────────────────┘

                  ┌──────────────────────────────┐
                  │ Route ThreadList `C` to      │
                  │ :new_thread with pre-filled  │
                  │ board (§2.6)                 │
                  │ Fixes scope item #7          │
                  └──────────────────────────────┘

                  ┌──────────────────────────────┐
                  │ require_email_verification   │
                  │ config key + seed + login /  │
                  │ register branches (§2.8)     │
                  │ Fixes scope item #10         │
                  └──────────────────────────────┘

                  ┌──────────────────────────────┐
                  │ Audit seed thread content &  │
                  │ verify markdown renders end- │
                  │ to-end (scope item #3)       │
                  │ Likely resolves via §2.4 fix │
                  └──────────────────────────────┘
```

### Recommended Phase Sequence

| Phase | Items | Rationale |
|---|---|---|
| **P1: Foundations** | Theme struct + session_context wiring; `Chrome.ScreenFrame` (size-gate built in); `List.SelectionList`+`ListRow`; `Post.MarkdownBody` + `Foglet.Markdown` tuple-grouping fix; `TimeAgo` | All downstream screen migrations depend on these. No user-visible change until screens migrate — so small P1, big P2. |
| **P2: Screen migration** | Migrate all 9 screens to ScreenFrame + SelectionList + MarkdownBody; thread-list row upgrade | Resolves scope items #1, #2, #3, #5, #6, #9 in one sweep. Biggest visible change. |
| **P3: Unread-count correctness** | Boards.advance_board_read_pointer monotonic max; ThreadList.Q triggers load_boards; PostReader.Q triggers load_threads | Data-layer fix independent of widget work. Can land in parallel with P2 if worked by different person/session, but safer after P1+P2 have landed to avoid test churn. Scope item #4. |
| **P4: New-thread-from-board flow** | ThreadList `C` routes to `:new_thread` with pre-filled board | One-screen change. Independent of P1–P3. Scope item #7. |
| **P5: Email-verification toggle** | Config key + seed + login/register branches; CLIHandler context read | One-feature addition. Independent of widget work. Scope item #10. |
| **P6: End-to-end verification** | `mix precommit`; manual SSH test across all screens and thresholds | Gate before milestone ships. Scope item #11 ("wire thread creation + post reply end-to-end") — largely already working (NewThread → create_thread → PostReader; PostComposer → create_reply) but verify with seeded data and fresh user. |

**P1 → P2 is the only strict sequential constraint.** P3, P4, P5 are independent and can land in any order after P1.

---

## 4. Patterns to Follow

### Pattern 1: Screen = ScreenFrame + Content

Every screen's `render/1`:
```elixir
def render(state) do
  content = render_content(state)          # the screen's unique part
  keys = key_bindings_for(state)

  Widgets.Chrome.ScreenFrame.render(%{
    theme: state.session_context[:theme] || Theme.default(),
    terminal_size: state.terminal_size,
    handle: state.current_user && state.current_user.handle,
    location: breadcrumb(state),
    title: screen_title(state),
    keys: keys,
    content: content
  })
end
```
Frame owns chrome; screen owns content + keys.

### Pattern 2: Widget Composition via Function Call

```elixir
# inside a screen's render_content:
column style: %{gap: 0} do
  [
    Widgets.List.SelectionList.render(%{
      items: state.board_list,
      selected_index: ss.selected_index,
      row_renderer: &render_board_row/1,
      theme: theme
    })
  ]
end
```
Widgets return view-AST; screens embed via list construction inside `column do`.

### Pattern 3: Width-Aware Render-Time Caching

```elixir
# in PostReader on {:posts_loaded, posts}:
{w, _h} = state.terminal_size
cache = Enum.into(posts, %{}, fn p ->
  {p.id, {w, Widgets.Post.MarkdownBody.prerender(p.body, w)}}
end)
# store cache in screen_state[:post_reader][:markdown_cache]
```

Renderer checks cache; misses or width-mismatches re-compute.

### Pattern 4: Theme Propagation via Props, Not Globals

Always pass `theme:` down. Never read theme inside a widget from a process or ETS. Exactly one place resolves theme: `CLIHandler.build_context/3`.

---

## 5. Anti-Patterns (Specific to This Codebase)

### Anti-Pattern: Putting StatusBar as a Sibling Process

**What people do:** Spawn a `StatusBar` GenServer that gets subscribed-to by each screen via PubSub, pushing status updates.

**Why it's wrong:**
- Raxol's single-TEA-loop is our source of truth for UI state. A sibling process introduces a second state owner.
- Status content is derived from `state.current_user`, `state.current_screen`, `state.current_board` etc. — it is a pure function of existing state. No new process warranted.

**Do this instead:** Status bar is a render-time widget inside `ScreenFrame`. Reads state; returns view. Done.

### Anti-Pattern: Using Raxol's Stateful Components Directly Inside Block-Macro Trees

**What people do:** `alias Raxol.UI.Components.Display.StatusBar` and drop it into a `column do` tree.

**Why it's wrong:** Raxol component `render/2` returns `%{type: :row, children: [...]}` tuple-shape trees. The modern block-macro runtime silently fails to lay out these tuple-trees when they are children of `column/row/box` blocks. See `post_composer.ex:259-261` comment explaining why `MultiLineInput.render/2` crashes Flexbox.

**Do this instead:** Use Raxol component **state** (like MultiLineInput's cursor/value machinery) but render with your own `text/2` siblings inside a block-macro tree. Or reimplement the 20-line render as a function widget.

### Anti-Pattern: Pre-rendering Markdown at Post Save

**What people do:** Populate `posts.body_rendered` on insert to "cache" the rendered output.

**Why it's wrong:** Terminal width varies per session. Pre-rendered output pinned to one width is wrong everywhere else. Schema becomes coupled to renderer; backfills required when renderer changes.

**Do this instead:** Render at view time; cache in screen_state keyed by `{post.id, terminal_width, post.last_edited_at}`.

### Anti-Pattern: Read-Pointer as Replace-Upsert

**What people do:** `on_conflict: [set: [last_read_message_number: $new]]` — overwrites unconditionally.

**Why it's wrong:** Non-monotonic. Reading an older thread *after* a newer one decreases the pointer, marking already-read posts as unread. This IS the root cause of scope item #4.

**Do this instead:** `on_conflict: [set: [...]] + conflict_target: [...] + where: last_read_message_number < $new`. Or use a fragment: `set: [last_read_message_number: fragment("GREATEST(..., ?)", $new)]`. Same pattern for thread_read_pointers (though there the "last_read_post_id" is opaque — use `last_read_at` monotonic max as the gate and keep the most-recent post_id from that).

---

## 6. Integration Points

### External Services

None new in this milestone. Email verification still logs the code (no mailer until Phase 10).

### Internal Boundaries

| Boundary | Communication | Notes |
|---|---|---|
| CLIHandler ↔ Foglet.TUI.App | `context` map passed through Lifecycle `options:` | Add `theme`, `require_email_verification` to session_context |
| Screen ↔ Foglet.TUI.App | `{:update, state, cmds}` return from `handle_key/2`; `render/1` reads state | Screens pass theme into widgets via props; cmd for `{:load_boards}` etc unchanged |
| Screen ↔ Widget | Function call with plain map | Widgets stateless; screens own state |
| Widget ↔ Raxol View DSL | `import Raxol.Core.Renderer.View`; block macros | Never emit tuple-shape trees into a block-macro parent |
| Foglet.Markdown ↔ PostReader/PostComposer preview | `render/1 → [{text, style}]` + `render_markdown_tuples/1 → column of text` | **Needs fix:** group tuples by newline separators; emit one `text/2` per resulting line |
| Foglet.Boards ↔ schema | Ecto queries | **Needs fix:** `advance_board_read_pointer/3` monotonic-max semantics |
| Foglet.Config ↔ session_context | `Config.get!/1` at session start; stash in context | Add `require_email_verification` key |

---

## 7. Scaling Considerations (Polish-Scope)

Not a new-scale question — this is a polish milestone, not an architecture change. But:

| Scale | Impact of polish changes |
|---|---|
| **Current (1 concurrent SSH user in dev)** | All decisions safe. Memoization costs negligible. |
| **10 concurrent users** | Per-session theme struct + per-screen markdown cache: ~1KB overhead per session × 10 = 10KB. Trivial. |
| **100+ concurrent users** | Markdown cache grows with posts viewed; already bounded by screen lifetime (cleared on screen exit via `Map.delete(state.screen_state, :post_reader)`). Safe. |

**Scaling priority for Phase 04+:** presence ticks will be the first to care — but the polish milestone adds no new per-session processes, no new ETS tables, no new global state. Neutral on scaling.

---

## 8. Open Questions / Handoff Flags for Planners

1. **§2.4 markdown hypothesis needs runtime verification.** Before P1 lands, spend 15 minutes in `iex -S mix` to confirm: `Foglet.Markdown.render("**bold**\n\nparagraph")` output, then emit that through a `column do [text(s, ...), ...] end` tree and observe. If the bug is something else (e.g., MDEx output shape changed, or CRLF translation corrupts the tuple content), adjust P1's scope.

2. **Seed thread content audit (scope item #3).** Open the seed file and eyeball: is the General seed content valid markdown? Raw control chars? The fix in §2.4 may or may not cover this — content-shape problems may be orthogonal. Flag: `lib/foglet_bbs/application.ex` / `priv/repo/seeds*.exs`.

3. **Theme struct field list is minimal.** §2.3 defines 6 fields. Real usage may want `fg_muted`, `fg_highlight`, `bg_frame` etc. Don't pre-optimize; add as needed during P2 screen migration.

4. **Terminal-too-small threshold is a guess.** 60×20 is conservative. Real test: render BoardList at 60×20 — does it look decent? If yes, ship. If not, bump to 80×24 (the Raxol baseline per `docs/ARCHITECTURE.md §7`).

5. **`ScreenFrame.render/1` prop shape** is sketched, not final. Planners should lock the exact prop names before P1 starts so screen migration in P2 is mechanical.

---

## Sources

- `lib/foglet_bbs/tui/app.ex` — App entry, update/view dispatch, modal handling
- `lib/foglet_bbs/tui/screens/{login,register,verify,main_menu,board_list,thread_list,post_reader,post_composer,new_thread}.ex` — all 9 screens
- `lib/foglet_bbs/tui/widgets/{status_bar,key_bar,modal}.ex` — current widget set
- `lib/foglet_bbs/tui/pub_sub_forwarder.ex` — PubSub-to-Raxol bridge pattern
- `lib/foglet_bbs/boards.ex`, `lib/foglet_bbs/threads.ex`, `lib/foglet_bbs/posts.ex` — domain contexts consumed by TUI
- `lib/foglet_bbs/boards/read_pointer.ex`, `lib/foglet_bbs/threads/read_pointer.ex` — read-pointer schemas (unread-count root-cause analysis)
- `lib/foglet_bbs/config.ex`, `lib/foglet_bbs/config/entry.ex` — ETS-backed runtime config
- `lib/foglet_bbs/markdown.ex` — MDEx-based markdown → `[{text, style}]` renderer
- `lib/foglet_bbs/ssh/cli_handler.ex` — SSH channel lifecycle, session_context build
- `lib/foglet_bbs/sessions/session.ex`, `lib/foglet_bbs/sessions/supervisor.ex` — Session GenServer and one-per-user enforcement
- `lib/foglet_bbs/accounts.ex`, `lib/foglet_bbs/accounts/user.ex` — User schema (theme field at `user.ex:41`; confirmed_at at `user.ex:29`)
- `vendor/raxol/lib/raxol/ui/components/**` — vendored Raxol component source (confirms tuple-shape render output)
- `docs/raxol/cookbook/THEMING.md` — Raxol theming capabilities
- `docs/raxol/cookbook/BUILDING_APPS.md` — TEA patterns
- `docs/ARCHITECTURE.md` — authoritative design reference
- `.planning/workstreams/phase-03-polish/STATE.md` — milestone scope (10 items)
- MEMORY: "Use Raxol's modern block-macro DSL, never the legacy function-form" (feedback_raxol_modern_dsl)

---

*Architecture research for: Foglet BBS Phase 03 polish (v1.0.1)*
*Researched: 2026-04-19*
