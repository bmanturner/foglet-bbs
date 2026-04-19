# Feature Landscape — Phase 03 Polish (v1.0.1)

**Domain:** SSH-delivered BBS / TUI — polish pass on shipped features
**Researched:** 2026-04-19
**Scope:** Calibrate "good looks like" for each polish item in the milestone scope and split it into table stakes vs differentiators. This is not domain-feature research — no new product surface is being added here. Every item is a correctness or consistency fix to the Phase 03 TUI.

## Guiding Framing

A "polish" milestone lives or dies on one question: **what's the floor a user expects before the product stops feeling broken?** Everything below is graded against that floor.

- **Table stakes** — if this isn't in v1.0.1, users will still say "the TUI feels broken / inconsistent." These must ship.
- **Differentiators** — if this *is* in v1.0.1, users will say "this feels unusually nice for a hobby BBS." Cut freely if scope pressure arrives.
- **Anti-features** — explicit "we are not building this in polish, here's what to do instead" to prevent scope creep from well-intentioned side quests.

Every recommendation below is opinionated. Hedging (`consider`, `you might`) is deliberately avoided because the requirements writer needs cut/keep decisions, not options.

---

## 1. Markdown → ANSI rendering

**Status today:** `lib/foglet_bbs/markdown.ex` has a pipeline (MDEx HTML → custom marker tokens → `{text, style}` tuples) that `PostReader.render_markdown_tuples/1` renders with `text/2`. Breakage surfaces as raw markdown showing through, from at least three root causes visible in the code:

1. **Line structure is collapsed into a flat tuple list with embedded `"\n"` tuples.** The renderer in `post_reader.ex:204-215` maps each tuple to one `text/2` element inside a single `column`, so a `"\n"` tuple becomes a standalone text line — but adjacent styled tuples on the "same" source line get rendered on separate lines. Paragraphs and lists visually smear.
2. **No wrapping at terminal width.** Long paragraphs run off the right edge.
3. **Headings uppercase + underline is unconditional** (D-02) even for H6, which looks wrong for deeper nesting. But the bigger issue is that the heading marker flow lands on the same line as the preceding text in some cases.

### What "good" looks like (calibration)

Grounded in what `glow`, `mdcat`, and `glamour` do well for terminal markdown:

| Element | Recommended rendering | Source confidence |
|---|---|---|
| `# H1` / `## H2` | Uppercase, bold, bright fg, blank line before+after | HIGH (glow, mdcat both do this) |
| `### H3`+ | Bold, no uppercase, blank line before | HIGH |
| `**bold**` | ANSI bold SGR | HIGH |
| `*italic*` | ANSI italic if terminal supports it, fall back to underline | MEDIUM (mdcat does this explicitly; many terminals still render italic) |
| `` `inline` `` | Dim + distinct fg (cyan/magenta), or bg-tinted | HIGH |
| Fenced code block | 2-space indent, dim fg, preserve line breaks, no syntax highlighting in v1.0.1 | HIGH for indent+dim; syntax highlighting is differentiator |
| `- list` | `  • item` (U+2022) with hanging indent for wraps | HIGH |
| `1. list` | `  1. item`, `  2. item` preserving numbers | HIGH |
| `> quote` | `│ ` (U+2502) or `> ` prefix, dim fg, one space between prefix and text | HIGH |
| `[text](url)` | `text` in underlined fg, then ` (url)` in dim fg when url differs meaningfully from text | MEDIUM — OSC-8 hyperlinks work in many terminals but aren't universal; deferring is fine |
| `![alt](url)` | `[image: alt]` in dim | HIGH |
| Horizontal rule `---` | Divider line (U+2500 repeat) across width | HIGH |
| Hard break (two trailing spaces) | Line break without blank line | LOW — users rarely notice |

**Wrapping** is the hidden requirement: all rendered markdown must wrap at the inner width of the post reader's content box, preserving indentation on wrapped list items and blockquotes. This is where the current implementation gaps are most painful — a paragraph with a `**bold**` phrase currently breaks wrapping because each tuple is its own `text/2`.

### Table stakes vs differentiators

| Feature | Bucket | Why |
|---|---|---|
| Headings (levels 1-3) render distinctly | Table stakes | Threads seeded with `#` headings show raw `#` today — canonical "polish feels broken" symptom |
| Bold + italic render with SGR | Table stakes | Users write `**emphasis**` all the time |
| Bullet lists render with `•` and wrap correctly | Table stakes | Seed threads in General use bullet lists |
| Inline code renders distinct | Table stakes | Cheap, high signal-to-noise |
| Fenced code blocks (dim + indent, no highlighting) | Table stakes | Any post sharing a command/snippet needs this |
| Blockquote rendering | Table stakes | `>` prefix is already idiomatic in the seed |
| Word-wrap at content width preserving indentation | Table stakes | Without this nothing looks right past 80 cols |
| Link rendering (`text (url)` fallback) | Table stakes | Links appear in seeds; raw `[text](url)` is ugly |
| OSC-8 hyperlinks (clickable terminal links) | Differentiator | Nice-to-have; only some terminals; requires capability detection |
| Syntax highlighting inside fenced blocks | Differentiator | Raxol has `CodeBlock` with Makeup for Elixir — tempting but adds complexity; skip in v1.0.1 |
| GFM task lists `- [x]` | Differentiator | Not used in current seeds |
| Tables | Differentiator | Punt; Raxol `table` component could help but markdown tables with wrapping in constrained widths is a rabbit hole |
| Footnotes, definition lists, autolinks to `@handles` | Anti-feature | `@mention` linkification belongs in M6, not here |

### Anti-feature

**Don't try to re-implement a markdown renderer from scratch, and don't persist `body_rendered`.** `DATA_MODEL.md` §16 already flags this: cache in ETS per-session if perf matters. Polish milestone's only job is "the tuples render correctly in a wrapping container." Everything else is M2/M6 work.

### Complexity notes

- **Medium-High.** The root fix isn't in `Foglet.Markdown` — it's in the rendering bridge. The correct shape of the output probably needs to change from flat `[{text, style}]` to **a tree of block elements** (paragraph, heading, list, code block, quote) where the renderer knows to emit one `text/2` per wrapped line with correct indentation. Alternatively: evaluate Raxol's `MarkdownRenderer` component (docs confirm it exists as a component module with `width:` option — this likely solves wrapping for free). The existing custom renderer might be throwaway-able.
- **Depends on:** widget width awareness (item 8) — markdown can't wrap correctly without knowing the content-box inner width.

---

## 2. Layout consistency — header + divider + status bar

**Status today:** Every screen (board_list, thread_list, post_reader, post_composer) hand-rolls the same pattern: outer `box` with single border and padding, inner `column`, title text, `divider()`, `StatusBar.render/1`, content, `KeyBar.render/1` pinned to bottom via `justify_content: :space_between`. The pattern is duplicated, subtly inconsistent, and the StatusBar today is two `text/1` items in a `row` — not a visual bar.

### What "good" looks like

A single reusable **screen chrome** widget that every screen uses. Concretely:

- Top line: a **single visual bar** (inverse-video or colored-bg row spanning full width) with left content (app name + context, e.g., `Foglet BBS  ›  Threads: General`) and right content (`@handle`, session indicator). This is what k9s, lazygit, btop all do — status bar at top with current-location breadcrumb, keys at bottom.
- Divider below the bar.
- Content region (screen-specific).
- Bottom: KeyBar (already exists, keep it).
- Modal overlays (already exists in `Foglet.TUI.Widgets.Modal`).

The status bar should accept **context** as a structured value, not a string:

```elixir
%{
  section: :boards | :threads | :post | :composer | ...,
  title: "General",
  handle: "alice",
  unread_badge: 3 | nil,
  extras: [] # session-specific bits (e.g., composer mode)
}
```

Reasoning: string-based `"Reading: #{title}"` locks the widget out of future polish (e.g., separator styling, truncation logic at small widths, localization).

### Table stakes vs differentiators

| Feature | Bucket | Why |
|---|---|---|
| Every screen uses a single `Screen` wrapper widget | Table stakes | The explicit ask; also a prerequisite for fixing items 6, 8, 9 |
| StatusBar is a real visual bar (inverse-video full width) | Table stakes | Current implementation is two dim texts in a row — doesn't read as a bar |
| Breadcrumb-style location (`Boards › General › Thread title`) | Table stakes | Tells the user where they are on every screen |
| Status bar at TOP with divider underneath | Table stakes | User ask; matches k9s/btop/lazygit |
| Handle on the right | Table stakes | Classic BBS identity signal |
| Truncation of long titles at small widths | Table stakes | `Threads: Some very long thread title that...` — required so the bar never wraps |
| Unread badge in status bar | Differentiator | Only matters once item 4 is fixed and unread counts are trustworthy |
| Clock/session-time display | Differentiator | Classic BBS vibe but adds re-render load |
| Color-code the left section by `section:` atom | Differentiator | Nice but purely decorative |

### Anti-feature

**Don't build a "page title banner" widget separate from the status bar.** Some screens currently have ` Thread: Foo ` bolded text above the divider above the status bar. That's three redundant location indicators on one screen. The status bar is the single location truth.

### Complexity notes

- **Low-Medium.** Mechanical refactor once the widget shape is agreed. Risk: Raxol's layout engine is sensitive to how elements compose (per the bug history in `post_composer.ex:261` — `render_input_as_text/2` bypasses `MultiLineInput.render/2` because it crashed `Flexbox.measure_flex_child/3`). Keep the wrapper widget minimal and composed of proven primitives.
- **Depends on:** widget layer (item 8) — this IS one of the widgets. The StatusBar upgrade is the most concrete case study for item 8.

---

## 3. Seeded threads wrap/render correctly

**Status today:** Seed thread bodies contain markdown with paragraphs, lists, and inline formatting. They render poorly because of items 1 and 2 (markdown renderer and no wrapping).

### What "good" looks like

Seed threads are the *canary* for markdown+wrapping+theming correctness. After items 1, 2, 6 are done, the seed threads should:

- Render paragraphs as wrapped blocks with blank lines between them.
- Render bulleted lists with hanging indent and `•` markers.
- Render `**bold**`, `*italic*`, `` `code` `` inline without breaking flow.
- Fit inside the post reader's content box at any terminal width ≥ the minimum (item 9).

### Table stakes vs differentiators

This is **entirely subsumed by items 1, 2, 6, 8, 9**. It is not a distinct deliverable — it's an *acceptance test*. The requirement should be phrased: "all seed threads render correctly at 80×24, 100×30, 120×40 after items 1/2/6/8/9 are complete." Treating it as its own requirement risks duplicate work.

### Anti-feature

**Don't patch individual seed posts to avoid triggering renderer bugs.** Seeds stay realistic; renderer fixes handle them.

### Complexity notes

- **Zero** as an independent item; it's a test artifact.

---

## 4. Unread counts — the "stuck (6 unread)" bug

**Status today:**

- `BoardList.render_board_row/3` (line 59) reads `board.unread_count`.
- `BoardList.load_boards/1` (line 106) calls `list_subscribed_boards(user)` and displays whatever unread count that returns.
- `PostReader.flush_read_pointers/2` (line 113) advances both `board_read_pointers` and `thread_read_pointers` on `[Q]` back out of the reader — so the write path exists.
- `BoardList` is loaded once (via `:load_boards` on screen entry) and **never reloaded when the user returns from reading a thread.** The stale count sits in `state.board_list`.

That's almost certainly the "stuck (6 unread)" bug: the DB is updated, but the in-memory `state.board_list` is not refreshed.

### What "good" looks like — the unread mental model

Forum unread mental models vary, and the Discourse Meta discussion surfaces real tension. The cleanest, most-forgiving model for a BBS (closest to classic BBS + Discourse's default) is:

1. **Unread count = posts in the board with `message_number > board_read_pointer.last_read_message_number` AND `deleted_at IS NULL`.** Pure SQL, no staleness issues.
2. **Count decrements when the read pointer advances**, which happens:
   - Implicitly on `[Q]` (leaving post reader) — flushes pointer to the latest post seen in the thread, plus advances board pointer to that thread's highest message number.
   - Never mid-thread. BBSes are sequential; "scrolled past a post" = "read it." The current code already does this via `advance_post/2`.
3. **The board list must refresh after returning from post reader.** This is the actual bug.

Alternative model considered: "decrement only when ALL posts in a thread have been seen." This is what some modern forums do, but it conflicts with the BBS "linear message-number" concept encoded in `DATA_MODEL.md` and `board_read_pointers.last_read_message_number`. Keep the message-number model.

### Table stakes vs differentiators

| Feature | Bucket | Why |
|---|---|---|
| Board-list refresh on return from post reader | Table stakes | The literal bug |
| Unread count reflects soft-deleted posts correctly | Table stakes | Seeded data + likely future moderation |
| Unread count at thread level (thread list rows) — same invalidation fix | Table stakes | Part of item 5 anyway; fix once, apply twice |
| Live unread count updates from PubSub when new posts arrive in current view | Differentiator | Requires presence/pubsub wiring; likely M4+ territory |
| "Mark board as read" command (`[A]`) | Differentiator | Classic BBS feature; worth noting as a seed for M2 polish but not polish-milestone scope |
| Unread badge in status bar (see item 2) | Differentiator | Visible reminder across screens |

### Anti-feature

**Don't cache unread counts client-side in TUI state beyond the current render.** Every time the user lands on the boards screen, re-query. Postgres is fast; correctness matters more than saving one query.

### Complexity notes

- **Low for the bug fix.** Trigger `:load_boards` when transitioning out of `post_reader` back to `thread_list` (or on re-enter of `board_list` from `thread_list`).
- **Low-Medium** if the fix also bundles the "refresh thread list when returning from post reader" (needed for item 5's "last activity" column to stay fresh).

---

## 5. Thread list row — richer info

**Status today:** Row format is `> [S] Thread title (N)` — sticky mark, title, unread count. No creator, no last-activity time, no post count.

### What "good" looks like

Target: classic BBS thread list density — pack useful info into a single row that works at 80 columns. A row format that survives scaling:

```
  2h  alice     [S] Welcome to General                          3 unread · 42 posts
 14m  bob           Thread with a long title that will truncate…  1 unread · 7 posts
```

Columns left-to-right, fixed or proportionally-sized:

| Column | Width strategy | Notes |
|---|---|---|
| Selection marker (`>`/` `) | 2 | Existing |
| Relative time (last activity) | 4-5 | Right-aligned; `30s`, `5m`, `2h`, `3d`, `2w`, `6mo`, `1y` |
| Creator handle | 12, truncated with `…` | Left-aligned |
| Sticky/locked marks | 4 | `[S]`, `[L]`, combined; skip column if none |
| Title | flex, truncated with `…` | Left-aligned |
| Stats | ~16 right-aligned | `3 unread · 42 posts` — collapse to `42 posts` when unread=0 |

Row has to fit 80 cols and scale up: at 120 cols let the title grow.

### Relative time format

Convention from the research (HIGH confidence — matches Slack/GitHub/Twitter/Discourse/common JS libs):

| Duration | Format |
|---|---|
| < 60s | `30s` |
| < 60m | `5m` |
| < 24h | `2h` |
| < 7d | `3d` |
| < 30d | `2w` |
| < 365d | `6mo` |
| ≥ 365d | `1y` |

Precision: integer, floor. No decimals. No "ago" suffix — the column header (if any) implies it; bare format is the convention in dense TUIs.

Switch to absolute date at 30+ days? No — the BBS context benefits from continuity ("2mo" keeps the same visual weight as "3d"); flip to absolute only at year-plus, if ever. The Discourse convention of "Dec 4, 2023" at 1yr+ is also acceptable; pick one, document it, move on.

### Table stakes vs differentiators

| Feature | Bucket | Why |
|---|---|---|
| Relative time column | Table stakes | Explicit user ask; core "is this thread alive?" signal |
| Creator handle column | Table stakes | Explicit user ask; prevents "who started this?" context flicker |
| Thread title truncation with `…` | Table stakes | Required to not break layout |
| Post count (total) | Table stakes | Cheap since `threads.post_count` is denormalized per DATA_MODEL §3 |
| Sticky mark `[S]` | Table stakes | Already present, keep it |
| Locked mark `[L]` | Differentiator | Schema supports it but M7 feature — show as read-only indicator if set |
| Tag/category column | Anti-feature | Tags aren't in the domain model |
| Per-row color by freshness | Differentiator | Dim older threads, bold recently-active — easy win, small complexity |

### Anti-feature

**Don't add a hoverable/focused "thread preview" pane in this milestone.** Tempting but it's an entire new layout. Defer to a future "reading experience" polish pass.

### Complexity notes

- **Medium.** Most complexity is in "compute relative time at render time" (pure function + a `utc_now/0` call — trivial) and "fixed-column layout that scales." Raxol's `row` with per-child `width:` can do fixed columns, but interplay with flex children under truncation is where bugs will show up. Test at 80, 100, 120 cols explicitly.
- **Depends on:** nothing new from the domain — `threads.post_count` and `threads.last_post_at` already exist (DATA_MODEL §3). Creator handle requires `threads.created_by` preloaded in `Foglet.Threads.list_threads/1`; verify the query does this.

---

## 6. Theme application consistency

**Status today:** `THEMING.md` shows Raxol has a full theme system (`ThemeManager`, `component_style/2`, JSON themes, pseudo-states). Foglet's screens directly use `fg: :green`, `style: [:bold]`, `style: [:dim]` throughout — hardcoded. The "border box and some text don't pick up theme" symptom is because *nothing* picks up theme — there's no theme in play, just hardcoded colors.

### What "good" looks like

Pick one of two paths:

**Path A — use Raxol's ThemeManager (recommended).**
- Define one Foglet theme JSON in `priv/themes/foglet.json` (default green-on-black BBS).
- Each widget reads `Theme.component_style(theme, :status_bar)` (etc.) instead of hardcoding colors.
- Screens never reference literal colors; they reference semantic roles: `:primary_text`, `:accent`, `:dim`, `:border`.

**Path B — a tiny Foglet-specific theme map.**
- `Foglet.TUI.Theme.get(:primary_fg) :: atom()` — module-local indirection.
- No Raxol ThemeManager integration.
- Easier if Raxol's theme system has sharp edges.

Path A wins if Raxol's system is solid; otherwise Path B. Research here is a recommendation but the implementing agent should spike both in 15 minutes before committing.

The semantic roles — **this is the actual table-stakes output of this item** — should be:

| Role | Current hardcoded usage | Example |
|---|---|---|
| `:primary_fg` | `fg: :green` | Main text |
| `:dim_fg` | `style: [:dim]` | Metadata, hints, inactive |
| `:accent_fg` | `style: [:bold]` + green | Selected row, titles |
| `:warning_fg` | `fg: :yellow` | Empty states, soft warnings |
| `:error_fg` | `fg: :red` | Errors |
| `:border_fg` | — | Border color for boxes |
| `:bar_bg` | — | StatusBar background (inverse-video) |
| `:bar_fg` | — | StatusBar foreground |

### Table stakes vs differentiators

| Feature | Bucket | Why |
|---|---|---|
| Single source of truth for TUI colors | Table stakes | The bug fix |
| All 4 main screens use the theme indirection | Table stakes | Otherwise the inconsistency persists |
| Borders pick up theme | Table stakes | Explicit user observation |
| Default theme = classic amber/green BBS | Table stakes | Product identity |
| User-selectable theme via `users.theme` preference | Differentiator | Schema supports it (DATA_MODEL §1, `users.theme :string default "default"`) but wiring is M11+ polish |
| Multiple built-in themes (amber, green, mono) | Differentiator | Product differentiator but cut if pressed |
| Theme preview/switcher TUI | Anti-feature | Punt to sysop admin milestone |

### Anti-feature

**Don't over-abstract the theme into dozens of role atoms.** 8-10 roles cover every current screen. If a screen needs more, that screen probably has a structural problem (item 2 territory).

### Complexity notes

- **Medium.** Spike Raxol ThemeManager first (30 min) to assess. If it works, the rest is mechanical replacement. If it has gaps, Path B is a ~30-line module.
- **Depends on:** item 2 (screen wrapper) is the best anchor — refactor the wrapper to consume theme; other screens inherit once they use the wrapper.

---

## 7. Composer — title field for new threads

**Status today:**

- `post_composer.ex` has no title field. `title_for/2` (line 288) renders `"New Thread"` if no reply-to and no current_thread, but no editable title input exists.
- `new_thread.ex` exists as a separate screen file — unread so far in this research but name suggests it's a separate path. (Code: the thread_list's `[C]` key handler (line 95) routes to `post_composer` with `current_thread: nil`, not to `new_thread`.)
- `Foglet.Posts.create_reply/4` is called for *all* submits (line 377) — reply-only API. There's no create-thread API wired through the composer.
- Therefore: starting a new thread from the TUI is genuinely impossible today. User correctly flagged this.

### What "good" looks like

Two paths:

**Path A: unify into PostComposer.** Composer has two modes (reply / new thread) driven by whether `current_thread` is set. When new-thread mode is active, a single-line title `text_input` appears above the body textarea. Tab order: title → body → submit.

**Path B: separate NewThread screen.** Resurrect `new_thread.ex`, wire `[C]` from thread_list to it instead of `post_composer`. Keep post_composer reply-only.

**Recommendation: Path B if `new_thread.ex` already has a working title field; Path A otherwise.** Read `new_thread.ex` to decide. A separate screen is cleaner because the domain operation is different (`create_thread` vs `create_reply`) — bundling them into one screen creates conditional complexity. But if `new_thread.ex` is empty/stub, retrofitting PostComposer is faster.

Regardless of path, the UX requirements:

- Title field ≤ 200 chars (validate against threads.title length — verify schema constraint exists).
- Title required, body required (both trimmed non-empty).
- Tab cycles between title and body.
- Ctrl+S validates both fields before submit.
- Error states distinct per-field.

### Table stakes vs differentiators

| Feature | Bucket | Why |
|---|---|---|
| Title field exists and is editable | Table stakes | The feature is currently missing entirely |
| Title is required, validated, error-shown | Table stakes | Prevents empty-title threads |
| `create_thread` domain call wired end-to-end | Table stakes | Part of item 11 |
| Title length limit enforced (cap from config) | Table stakes | Match post body limit pattern |
| Preview mode shows title as a heading above preview body | Differentiator | Nice symmetry but cosmetic |
| Title auto-focus on entry | Differentiator | Keyboard-first UX; add if cheap |
| "Save draft" (persist unsent composer contents across navigation) | Anti-feature | Punt — session-transient is fine for v1.0.1 |

### Anti-feature

**Don't add tag/category pickers, thread templates, or cross-board posting.** Scope creep; none are in the domain yet.

### Complexity notes

- **Medium.** Hinges on picking Path A vs B. If Path B, `new_thread.ex` needs to implement the full composer skeleton — risk of duplicating what `post_composer.ex` already handles for body input. Path A is more code movement but less duplication.
- **Depends on:** item 11 (wiring thread creation/reply end-to-end). These two items should be planned together.

---

## 8. Reusable widget layer on Raxol

**Status today:**

- Three widgets exist in `lib/foglet_bbs/tui/widgets/`: `status_bar.ex`, `key_bar.ex`, `modal.ex`.
- Each screen reimplements the outer `box → column → title → divider → status_bar → content → key_bar` pattern inline.
- Raxol provides (per Widget Gallery): `column`, `row`, `box`, `spacer`, `divider`, `split_pane`, `text`, `list`, `table`, `viewport`, `MarkdownRenderer`, `MultiLineInput`, `Modal`, `StatusBar` (as a component), `CodeBlock`, `focus_ring`, etc.

### What "good" looks like

A **thin** Foglet widget layer that composes Raxol primitives for Foglet-specific repeated patterns:

| Foglet widget | Raxol underneath | Reason to exist in Foglet |
|---|---|---|
| `Foglet.TUI.Widgets.Screen` | `box` + `column` + `divider` | Standard screen chrome; enforces consistency (item 2) |
| `Foglet.TUI.Widgets.StatusBar` (upgraded) | `row` + `text` with theme | Context-aware (item 2) |
| `Foglet.TUI.Widgets.KeyBar` (exists, keep) | `row` + `text` | Bottom key hints |
| `Foglet.TUI.Widgets.ThreadRow` | `row` with fixed columns | Item 5's row layout in one place |
| `Foglet.TUI.Widgets.BoardRow` | `row` + `text` | Item 4 unread badge + name |
| `Foglet.TUI.Widgets.PostBlock` | `column` of `text` from markdown tuples | Item 1's markdown+wrapping |
| `Foglet.TUI.Widgets.RelativeTime` | `text` | Pure formatter; factor out of ThreadRow for reuse (e.g., last_callers in M4) |
| `Foglet.TUI.Widgets.Modal` (exists, keep) | `Raxol.UI.Components.Modal` | Already does this |

Critical: **do not** wrap Raxol widgets that Foglet uses once. `button`, `text_input`, `table`, `list` — pass through. Only wrap where there's real duplication or Foglet-specific policy.

The user-stated rule "without reinventing widgets Raxol already provides" is well-captured by this principle: **if Raxol has it, use it directly. Wrap only to enforce Foglet-specific composition or styling.**

### Table stakes vs differentiators

| Feature | Bucket | Why |
|---|---|---|
| `Screen` widget (item 2's chrome) | Table stakes | The foundation of item 2 |
| `ThreadRow` widget (item 5) | Table stakes | The foundation of item 5 |
| `PostBlock` widget (item 1 + 3) | Table stakes | The foundation of markdown rendering |
| `RelativeTime` pure function | Table stakes | Trivial, used in ThreadRow and later M4 |
| Evaluate Raxol `MarkdownRenderer` component | Table stakes | Saves a large custom implementation if it fits |
| Widget tests (pure render, no Raxol runtime) | Differentiator | Nice to have; add once widgets stabilize |
| Widget style guide doc | Anti-feature | Not polish-milestone scope; emerges naturally |

### Anti-feature

**Don't build a generic `Panel`, `Pane`, or `Section` abstraction.** These are the trap that leads to reinventing Raxol. Wrap concrete repeated patterns only.

### Complexity notes

- **Medium.** Each widget is small; the overhead is in the cross-cutting refactor (every screen touches every widget).
- **Depends on:** item 6 (theming) — widgets should read theme, not hardcode.

---

## 9. Minimum terminal dimensions

**Status today:** No code path for "terminal too small" was found. `post_composer.ex:172` takes `state.terminal_size || {80, 24}` as fallback. Screens render and probably look broken at 40×10.

### What "good" looks like

Three parts:

1. **Define minimums.** For Foglet's current screens: **80×24** is the floor. Justification: thread list at 80 cols with the column layout in item 5 fits; post reader with wrapped markdown fits; status bar + divider + content + key bar fits in 24 rows. Many TUIs pick 80×24 (HIGH confidence — research: "standard inherited from early terminal computing"). Above that, scale.
2. **Detect too-small terminal.** On every render, check `state.terminal_size`. If either dimension is below threshold, render a different screen: a single centered message.
3. **Render a clear resize message.** Multi-line, centered, dim: `Terminal too small.  /  This BBS needs at least 80×24.  /  Yours is: 72×18.  /  Please resize and try again.` No interactivity except SSH disconnect. Re-render as usual on SIGWINCH / window-change events.

### Table stakes vs differentiators

| Feature | Bucket | Why |
|---|---|---|
| Define threshold (80×24) | Table stakes | The explicit ask |
| Too-small screen with clear message | Table stakes | Without this, small terminals show garbled UI |
| Auto-exit the too-small screen on resize up | Table stakes | SIGWINCH-triggered re-render already exists (Phase 03 gap closure 03-06); just re-check |
| Current size displayed in message | Differentiator | Helps debugging but adds complexity |
| Different thresholds per screen | Anti-feature | One threshold, keep it simple |
| Graceful degradation to a "compact" layout under 80 cols | Anti-feature | Not worth the test surface; tell user to resize |

### Anti-feature

**Don't try to make every screen work below 80 cols with a "compact layout."** Test matrix explodes, and 80×24 is a near-universal minimum any SSH client supports.

### Complexity notes

- **Low.** A single guard in `Foglet.TUI.App.view/1` or `render/1` that short-circuits to a `TooSmall` screen when `w < 80 or h < 24`. Window-resize events are already plumbed (SSH-10 gap closure per main roadmap).

---

## 10. Email verification toggle (SEED-002 fold-in)

**Status today:**

- `SEED-002` fully describes the requirement: `registration.require_email_verification` config boolean; resend flow stub in `verify.ex:101,109`; `login.ex:273` guard on `confirmed_at: nil`.
- `DATA_MODEL.md` §11 already lists `registration.require_email_verification` as an expected config key.
- `users.confirmed_at` field exists (DATA_MODEL §1).

### What "good" looks like

Break into two orthogonal deliverables:

**10a. Configurable verification requirement (table stakes for polish).**

- Add `registration.require_email_verification` to `Foglet.Config` default keys.
- Register flow reads it:
  - `true` (default): current behavior — create user with `confirmed_at: nil`, generate token, redirect to Verify.
  - `false`: create user with `confirmed_at: NaiveDateTime.utc_now()`, skip Verify, go straight to main menu.
- Login flow: skip the `confirmed_at: nil` guard when config is `false` (or in practice, it'll be non-nil so guard never triggers — simpler).
- Sysop toggle: via config table edit (sysop TUI comes in M8, so for v1.0.1 it's a SQL or Mix task affordance).

**10b. Resend verification code (table stakes for polish).**

- Wire the existing `{:resend}` stub in `verify.ex:101,109` to a visible key hint (e.g., `[R] Resend code`).
- Cooldown: 60s between resends, displayed inline (`Resent. Wait 42s…`).
- Rate limit: max 3 resends per session (hard-stop with error).
- When `require_email_verification = false`, the Verify screen is never reached so the resend UI doesn't matter in that mode.

### Registration modes × verification matrix

The research question asked for this explicitly. Foglet has three registration modes per DATA_MODEL config: `open | invite_only | sysop_approved`. Times verification boolean:

| Mode | Verification ON (default) | Verification OFF |
|---|---|---|
| `open` | Classic: register → email code → confirmed | Register → immediately confirmed |
| `invite_only` | Invite validates identity anyway; verification is redundant but harmless | Same but faster onboarding |
| `sysop_approved` | Sysop approval already gates; verification is redundant | Recommended default in this mode |

**Recommendation for polish milestone: sysop can set verification ON/OFF independent of registration mode, but the default pairing should be:**
- `open` + ON (current default)
- `invite_only` + ON (keep a second identity check)
- `sysop_approved` + OFF (sysop review is the gate; email is optional)

Don't hardcode this pairing — expose both config keys independently. But document the recommendation.

### "Skip verification" mechanical semantics

Concrete definition: a user created when `require_email_verification = false` is indistinguishable from a verified user — `confirmed_at` is set at creation time, no token is generated, no email is sent. The `confirmed_at` field remains the single source of truth for "this user can log in"; the only change is what fills it.

Alternative rejected: a separate `verification_required: false` field on the user. Adds schema surface for no benefit.

### Resend UX conventions

- Cooldown display: the resend key goes grayed-out (dim) with countdown text: `[R] Resend in 42s…` (disabled during cooldown).
- Success feedback: transient message `Code resent to your email.` in status area.
- Attempt limit: after N attempts, show `Too many resends. Please contact sysop.` with the key removed.

### Table stakes vs differentiators

| Feature | Bucket | Why |
|---|---|---|
| `registration.require_email_verification` config key | Table stakes | Explicit ask from SEED-002 |
| Register/login honor the config | Table stakes | The config is meaningless without enforcement |
| Resend key wired to existing stub | Table stakes | Low-hanging fruit — event handler already stubbed |
| Resend cooldown display | Table stakes | Prevents spam |
| Resend rate limit | Table stakes | Prevents abuse |
| Email delivery (actual send) | Anti-feature for v1.0.1 | Swoosh isn't wired until M10; current flow shows the code inline anyway |
| Per-mode default pairing | Differentiator | Nice polish but not strictly required |
| Sysop TUI toggle | Anti-feature | M8 scope; SQL/Mix is fine for v1.0.1 |

### Anti-feature

**Don't wire actual SMTP delivery in this milestone.** SEED-002 explicitly flags this for M10. Polish scope ends at "the config key exists and is honored, and the resend stub is wired to a visible key."

### Complexity notes

- **Low-Medium.** Config key is trivial; register/login flow changes are ~20 lines. Resend cooldown is a local timer in Verify screen state.
- **Depends on:** `Foglet.Config` infrastructure (already exists per `lib/foglet_bbs/config.ex` and the usage in `post_composer.ex:425`).

---

## 11. Wire thread creation + post reply end-to-end

**Status today:**

- **Post reply:** `PostComposer.do_submit/3` calls `Foglet.Posts.create_reply/4` — wired to a domain call. Works if `Foglet.Posts` exposes that function with that arity. Verify the domain module does.
- **Thread create:** No code path calls `create_thread` from the TUI. Confirmed above (item 7).

### What "good" looks like

End-to-end means:

1. TUI screen collects input → validates → calls domain function.
2. Domain function writes to DB inside `Ecto.Multi` (see DATA_MODEL §3 — thread + first post in one transaction; allocate message number via board server).
3. Domain function returns `{:ok, struct}` or `{:error, changeset}`.
4. TUI screen interprets result — on OK, navigate to the new thread; on error, surface validation errors in the composer.
5. Lists refresh (item 4's refresh-on-navigate pattern) so the new thread appears.

For **reply**: existing path is OK if `create_reply/4` actually goes through `Foglet.Boards.Server` for message number allocation. Verify.

For **thread create**: need a `Foglet.Threads.create_thread/3` or similar that wraps the board server + `Ecto.Multi` per DATA_MODEL §3.

### Table stakes vs differentiators

| Feature | Bucket | Why |
|---|---|---|
| `Foglet.Threads.create_thread/N` domain function exists and works | Table stakes | Block for v1.0.1 |
| TUI composer (new-thread mode) calls it | Table stakes | User-visible feature |
| `Foglet.Posts.create_reply/4` confirmed to route through BoardServer | Table stakes | Correctness: message numbers must be allocated through the server |
| Navigation after create (land on new thread) | Table stakes | Without this, "did it work?" ambiguity |
| Thread list refreshes on return | Table stakes | Same pattern as item 4 |
| Error display in composer (not via modal) | Differentiator | Modal is fine; inline is nicer |
| Optimistic insert in TUI state before DB confirm | Anti-feature | Premature optimization |

### Anti-feature

**Don't stub or mock the domain functions "for now" in v1.0.1.** The main roadmap marks Phase 03 complete because these screens exist; the polish milestone's correctness floor requires actual working CRUD. If the domain modules don't support this yet, that's the blocker, not a stub.

### Complexity notes

- **Medium-High.** The thread creation path touches `Foglet.Boards.Server` (message number allocation), `Foglet.Threads` (thread schema + changeset), `Foglet.Posts` (first post), and requires an `Ecto.Multi`. If the infra exists, wiring is ~50 lines. If it doesn't, this is the biggest item in the milestone.
- **Depends on:** item 7 (title field) — they're two sides of the same feature.

---

## Cross-cutting: MVP Recommendation

If scope has to be cut, recommended floor for v1.0.1:

**Must ship (true table stakes):**
1. Item 1: Markdown rendering (items 3 falls out for free)
2. Item 2: Screen chrome / StatusBar consistency
3. Item 4: Unread count fix
4. Item 7 + Item 11: Composer title + thread create wiring (single slice)
5. Item 9: Too-small terminal guard

**Should ship:**
6. Item 5: Thread list row enrichment
7. Item 6: Theming consistency
8. Item 8: Widget layer (naturally emerges from 2, 5)

**Could defer if crunched:**
9. Item 10: Verification toggle + resend (SEED-002 — the seed is already flagged for M10; deferring is well-justified)

---

## Feature Dependencies

```
item 2 (Screen chrome) ─┬─> item 6 (Theming) ─┐
                        │                      │
                        └─> item 8 (Widget layer) ─┬─> item 5 (Thread row)
                                                  ├─> item 1 (Markdown → PostBlock)
                                                  └─> item 9 (TooSmall screen)

item 1 ─> item 3 (acceptance-only)
item 7 <───> item 11 (tightly coupled)
item 4 (independent; small fix)
item 10 (independent; two sub-items 10a/10b)
```

---

## Complexity Summary

| Item | Complexity | Notes |
|---|---|---|
| 1. Markdown rendering | Med-High | May replace custom renderer with Raxol `MarkdownRenderer` |
| 2. Layout / StatusBar | Low-Med | Mechanical refactor once shape agreed |
| 3. Seed thread rendering | — | Subsumed by 1/2/6/8/9 |
| 4. Unread count fix | Low | Refresh-on-navigate |
| 5. Thread list rows | Med | Fixed-column layout + time formatter |
| 6. Theming consistency | Med | Spike Raxol ThemeManager first |
| 7. Composer title | Med | Path A vs B decision |
| 8. Widget layer | Med | Cross-cutting but each widget is small |
| 9. Minimum dimensions | Low | Single guard in root render |
| 10. Email verification | Low-Med | Two sub-items; infra exists |
| 11. Thread create + reply wiring | Med-High | Depends on domain module state |

---

## Sources

- [Glow — charmbracelet/glow](https://github.com/charmbracelet/glow) — terminal markdown rendering reference
- [mdcat — swsnr/mdcat](https://github.com/swsnr/mdcat) — confirms bold headers, dim code, link handling conventions
- [glamour — charmbracelet/glamour](https://github.com/charmbracelet/glamour) — style-sheet-based terminal markdown
- [Discourse Meta: unread count UX discussions](https://meta.discourse.org/t/should-not-unread-count-not-disappear-until-i-open-the-unread-things/34236) — forum unread mental models
- [relative-time-format conventions — npm/GitHub](https://github.com/catamphetamine/relative-time-format) — 30s/5m/2h/3d/2w short format confirmation
- [K9s docs](https://k9scli.io/) — TUI status bar at top + key hints at bottom pattern
- [LazyTui component patterns](https://github.com/DokaDev/lazytui) — StatusBar + key bindings convention
- [TUI design skill notes — 80×24 minimum](https://explainx.ai/skills/hyperb1iss/hyperskills/tui-design) — terminal minimum dimension norm
- `docs/raxol/getting-started/WIDGET_GALLERY.md` — authoritative inventory of Raxol primitives (HIGH confidence)
- `docs/raxol/cookbook/THEMING.md` — Raxol theme system capabilities (HIGH confidence)
- `docs/DATA_MODEL.md` — schema reference for unread pointers, config keys, user verification (HIGH confidence, in-repo)
- `.planning/seeds/SEED-002-email-verification-ux.md` — scope of item 10 (HIGH confidence, in-repo)
- Current TUI screen source in `lib/foglet_bbs/tui/screens/*.ex` — status-quo behavior analysis (HIGH confidence, direct read)
