# Phase 22: Post Reader Facelift - Research

**Researched:** 2026-04-25
**Domain:** SSH-first Elixir/Raxol terminal post reader UI
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

Phase 22 refreshes `Foglet.TUI.Screens.PostReader` into the Classic Modern BBS reader shape from `SCREENS.md`: the selected post has one compact metadata header with position, stable message number, author, and age; the body has a visible left gutter/card treatment while preserving markdown rendering; and the thread shows compact progress that works at 64x22. Existing `Viewport` scroll ownership, navigation keys, reply/back transitions, render-cache behavior, and read-pointer flushing remain unchanged.

Phase 22 does NOT change composer visuals, thread-list rows, board-directory presentation, post query semantics, message-number allocation, read-pointer persistence rules, markdown parsing semantics, or browser workflows.

- **D-01:** Extend `Foglet.TUI.Widgets.Post.PostCard` as the shared post unit for the facelift instead of introducing a parallel sibling widget. `PostReader` should delegate post visual assembly to `Foglet.TUI.Widgets.Post.*`; it should not grow a new screen-local pile of header/body/footer formatting.
- **D-02:** `PostCard` may add a reader-oriented helper, recommended as a small public function that accepts a post, pre-parsed markdown tuples, width, theme, and `index`/`total` options, while keeping the existing markdown cache boundary intact. The helper should produce header/body/progress pieces or body lines in a shape `PostReader` can compose with `Viewport`.
- **D-03:** Do not route the reader through `PostCard.render/4` if that would put the entire card inside the viewport. The viewport remains responsible only for the scrollable post body rows; the header and progress surfaces remain non-scrolling content around it.
- **D-04:** Render one compact metadata header for the selected post: `Post X of N • #message_number • @handle • age ago`. The exact separator may be `•` or another theme-consistent single-cell separator, but the rendered tree must include `Post X of N`, `#message_number`, `@handle`, and a short age token.
- **D-05:** Header formatting should reuse `PostCard.get_handle/1` and `PostCard.get_time_ago/1` or equivalent helper extraction under `Foglet.TUI.Widgets.Post`. It should degrade gracefully when handle, timestamp, or message number is missing, but tests must cover the normal fully-populated path.
- **D-06:** The header is rendered above the scrollable body and uses theme slots such as `theme.dim`, `theme.title`, `theme.badge`, or `theme.accent`; no hardcoded terminal color atoms are added.
- **D-07:** Add the left body gutter in the post widget/body-line assembly path, recommended at `PostCard.render_body_lines/4` or a closely related `Post.MarkdownBody` helper, so every logical body row passed into `Viewport` already includes the gutter treatment.
- **D-08:** The minimum-size 64x22 body treatment is a lightweight left gutter such as `│ ` or `| `, not a full framed card. Full boxes are optional only if the planner can prove they do not steal too much body width or break the viewport at 64x22.
- **D-09:** Markdown rendering behavior remains delegated to `Post.MarkdownBody`; Phase 22 may wrap rendered line rows with a gutter, but it must not introduce a separate markdown parsing or styling pipeline in `PostReader`.
- **D-10:** `PostReader.State.viewport` remains the owner of within-post scroll state. `advance_post/2`, `scroll_post/2`, `warm_cache/4`, `warm_viewport/4`, and `prepare_after_load/3` keep their behavioral roles, with only the rendered body-line shape changing.
- **D-11:** Always render compact progress text such as `Posts X/N` for the selected post. This compact text is the required baseline at 64x22 and 80x24.
- **D-12:** A segmented visual indicator such as `▰▰▱▱▱` is allowed only as progressive enhancement when width permits. If included, it must be generated with display-width helpers and must collapse before the compact `Posts X/N` text disappears.
- **D-13:** Progress belongs in non-scrolling reader content, not inside the scrollable body rows. It may sit below the header, above the viewport, or below the viewport depending on what gives the cleanest 64x22 layout, but it must not compete with the command bar or change key hints.
- **D-14:** Extend `test/foglet_bbs/tui/screens/post_reader_test.exs` for focused render assertions: compact header includes `Post 1 of 1`, `#42`, `@mina`, and an age token; longer-thread progress renders `Posts 3/12`; and existing navigation, scroll, reply, back, cache, and read-pointer tests continue to pass.
- **D-15:** Extend `test/foglet_bbs/tui/layout_smoke_test.exs` with a Phase 22 PostReader size-contract block at `[{64, 22}, {80, 24}, {132, 50}]`. Assertions should cover header text, body gutter presence, compact progress, selected body visibility, and no positioned text overflow/overlap.
- **D-16:** Add or extend `test/foglet_bbs/tui/widgets/post/post_card_test.exs` only if new public PostCard helper behavior is introduced. If the implementation only changes existing helper output through screen-level composition, screen and layout tests are sufficient.

### the agent's Discretion

- Exact function names and return shape for the PostCard reader helper, as long as `PostReader` delegates visual assembly to `Foglet.TUI.Widgets.Post.*` and preserves the render-cache tuple boundary.
- Exact separator glyph between header atoms. Prefer `•` because `SCREENS.md` uses it in the target sketch, but planner may choose another single-cell separator if tests or readability point elsewhere.
- Exact gutter glyph (`│` recommended; ASCII `|` acceptable if layout tests or terminal compatibility make it simpler).
- Whether the optional segmented progress indicator ships in Phase 22. Compact `Posts X/N` is mandatory; the segment bar is optional.
- Exact placement of progress relative to header and viewport, provided 64x22 remains readable and body rows retain practical width.

### Deferred Ideas (OUT OF SCOPE)

- Composer editor-frame, preview tabs, counters, and quoted-context facelift — Phase 23 scope.
- Thread-list details, rich-row changes, or browsing metadata changes — Phase 20 scope and follow-up territory, not Phase 22.
- Board-directory visual changes or subscription/read-state presentation — Phase 21 scope.
- Broader markdown styling redesign for headings, quotes, code, and links beyond preserving current markdown behavior inside the reader treatment.
- New read-pointer semantics, post query behavior, message-number allocation, or persistence changes.
- Screenshot-based terminal fixtures; Phase 22 sticks with code/layout tests unless a future visual QA phase adds screenshots.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| READER-01 | Post reader shows post position, stable message number, author, and age in a compact header. | Use a `PostCard.reader_header/4`-style helper that reuses `get_handle/1` and `get_time_ago/1`, formats `#message_number`, and remains outside `Viewport`. `[VERIFIED: .planning/REQUIREMENTS.md]` `[VERIFIED: lib/foglet_bbs/tui/widgets/post/post_card.ex]` |
| READER-02 | Post bodies render with a clear gutter or card treatment while preserving markdown rendering behavior. | Wrap `PostCard.render_body_lines/4` output, or add an option there, so `MarkdownBody.render_tuples_as_lines/4` remains the markdown pipeline and `Viewport` receives guttered logical rows. `[VERIFIED: .planning/REQUIREMENTS.md]` `[VERIFIED: lib/foglet_bbs/tui/widgets/post/markdown_body.ex]` |
| READER-03 | Longer threads show reading progress in a 64x22-safe form without breaking viewport scrolling, reply, previous/next, or back navigation. | Render compact `Posts X/N` outside `Viewport`; keep `advance_post/2`, `scroll_post/2`, `handle_key/2`, and read-pointer flushing behavior untouched except for body-line shape. `[VERIFIED: .planning/REQUIREMENTS.md]` `[VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex]` |
| READER-04 | Post reader uses shared `PostCard` or equivalent post unit for header, body, and optional footer treatment. | Extend `PostCard` rather than adding screen-local formatting; add widget tests only if the helper is public. `[VERIFIED: .planning/REQUIREMENTS.md]` `[VERIFIED: .planning/phases/22-post-reader-facelift/22-CONTEXT.md]` |
</phase_requirements>

## Summary

The established pattern is a split reader composition: `PostReader` owns screen state, key handling, read-pointer flushing, render-cache warming, and `Viewport` wiring; `Foglet.TUI.Widgets.Post.*` owns the selected post visual unit; `MarkdownBody` remains the only markdown-to-Raxol line pipeline. `[VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex]` `[VERIFIED: lib/foglet_bbs/tui/widgets/post/post_card.ex]` `[VERIFIED: lib/foglet_bbs/tui/widgets/post/markdown_body.ex]`

The implementation should not add a library or a new display subsystem. Extend `PostCard` with a reader-specific assembly helper or options on existing helpers, then make `PostReader.render_post_content/5` a thin composition layer: selected post lookup, cached tuple retrieval, header/progress rendering, guttered body-line generation, transient `Viewport.update/2`, and frame rendering. `[VERIFIED: AGENTS.md]` `[VERIFIED: .planning/phases/22-post-reader-facelift/22-CONTEXT.md]`

**Primary recommendation:** Add `PostCard.reader_header/4`, `PostCard.reader_progress/4`, and a gutter option for `render_body_lines/4` or a single `PostCard.reader_parts/5` helper that returns `{header, progress, body_lines}`; keep only `body_lines` inside `Viewport`. `[VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex]` `[VERIFIED: vendor/raxol/lib/raxol/ui/components/display/viewport.ex]`

## Project Constraints (from AGENTS.md)

- Foglet BBS is SSH-first; do not add end-user browser workflows for this phase. `[VERIFIED: AGENTS.md]`
- Use `rtk` as the shell prefix for repo commands. `[VERIFIED: AGENTS.md]`
- Before TUI/Raxol work, read Raxol and local widget docs. `[VERIFIED: AGENTS.md]`
- Keep UI behavior in `Foglet.TUI.App` and screens; reusable display belongs in widgets. `[VERIFIED: AGENTS.md]`
- Keep domain workflows in `Foglet.*` contexts, not controllers, SSH callbacks, or TUI render functions. `[VERIFIED: AGENTS.md]`
- Route colors through `Foglet.TUI.Theme`, pass theme explicitly, and keep render functions pure over already-loaded state. `[VERIFIED: AGENTS.md]`
- For TUI flows, keep global navigation in `Foglet.TUI.App`, screen-local state in the screen or sibling state module, data/mutations in contexts, off-process work in `Foglet.TUI.Command`/Raxol commands, and reusable display in widgets. `[VERIFIED: AGENTS.md]`
- Use `start_supervised!/1` for processes in tests; avoid `Process.sleep/1` and `Process.alive?/1`. `[VERIFIED: AGENTS.md]`
- Run `mix precommit` after code changes. `[VERIFIED: AGENTS.md]`

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|--------------|----------------|-----------|
| Compact post metadata header | TUI Widget | TUI Screen | `PostCard` owns per-post display formatting; `PostReader` supplies index/total and composes the returned element outside the viewport. `[VERIFIED: lib/foglet_bbs/tui/widgets/post/post_card.ex]` |
| Markdown body rendering | TUI Widget | Markdown utility | `Post.MarkdownBody` groups markdown tuples into logical line rows; `PostReader` must not parse or style markdown itself. `[VERIFIED: lib/foglet_bbs/tui/widgets/post/markdown_body.ex]` |
| Body gutter treatment | TUI Widget | TUI Screen | Gutter should be applied before `Viewport` receives children so scroll math and render output share the same line list. `[VERIFIED: .planning/phases/22-post-reader-facelift/22-CONTEXT.md]` |
| Within-post scrolling | TUI Screen State / Raxol Component | TUI Widget | `PostReader.State.viewport` owns `scroll_top`, `visible_height`, `content_height`, and `children`; `Viewport` slices visible children. `[VERIFIED: lib/foglet_bbs/tui/screens/post_reader/state.ex]` `[VERIFIED: vendor/raxol/lib/raxol/ui/components/display/viewport.ex]` |
| Thread progress display | TUI Widget | TUI Screen | Progress is a non-scrolling reader surface derived from selected index and total; optional segment rendering can reuse the local Display.Progress wrapper. `[VERIFIED: lib/foglet_bbs/tui/widgets/display/progress.ex]` |
| Read-pointer advancement/flushing | Domain Context + TUI Screen command boundary | Database | Existing reader behavior advances local read position on navigation and flushes through `Foglet.Boards`/`Foglet.Threads`; Phase 22 must not change semantics. `[VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex]` |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Elixir / OTP | Elixir 1.19.5, OTP 28 available; project constraint `~> 1.17` | Runtime and implementation language | Existing project runtime and Mix configuration. `[VERIFIED: elixir --version]` `[VERIFIED: mix.exs]` |
| Raxol | path dependency `vendor/raxol`; lock transitive packages `raxol_core`/terminal/etc. 2.4.0 | Terminal UI DSL, layout, `Viewport`, text measurement | Existing SSH-first TUI framework and local widget stack. `[VERIFIED: mix.exs]` `[VERIFIED: mix.lock]` |
| Raxol `Viewport` | local vendor source | Scrollable window over child elements | Existing `PostReader.State.viewport` owner; it slices `children` by `scroll_top` and `visible_height`. `[VERIFIED: vendor/raxol/lib/raxol/ui/components/display/viewport.ex]` |
| `Foglet.TUI.Widgets.Post.PostCard` | local module | Shared per-post display unit | Already owns post card rendering, author/time extraction, body-line generation, and cached tuple rendering. `[VERIFIED: lib/foglet_bbs/tui/widgets/post/post_card.ex]` |
| `Foglet.TUI.Widgets.Post.MarkdownBody` | local module | Markdown tuples to Raxol body rows | Existing renderer preserves logical line grouping and style mapping; do not replace it. `[VERIFIED: lib/foglet_bbs/tui/widgets/post/markdown_body.ex]` |
| `Foglet.TUI.TextWidth` | local module | Terminal display-width measurement, truncation, padding | Phase 16 helper wraps `Raxol.UI.TextMeasure`; use for Unicode glyph decisions and tests. `[VERIFIED: lib/foglet_bbs/tui/text_width.ex]` |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `Foglet.TUI.Widgets.Display.Progress` | local module | Theme-routed segmented or bracket progress | Use only if adding the optional segment bar; compact text progress remains mandatory. `[VERIFIED: lib/foglet_bbs/tui/widgets/display/progress.ex]` |
| `Foglet.TimeAgo` | local module | Short relative time tokens | Reuse through `PostCard.get_time_ago/1`; append `" ago"` only in the reader header if using the locked `Post X of N • #42 • @mina • 9m ago` shape. `[VERIFIED: lib/foglet_bbs/tui/widgets/post/post_card.ex]` |
| ExUnit | bundled with Elixir | Focused screen/widget tests and layout smoke tests | Existing test suite uses ExUnit and `FogletBbs.DataCase` for layout smoke. `[VERIFIED: test/foglet_bbs/tui/screens/post_reader_test.exs]` `[VERIFIED: test/foglet_bbs/tui/layout_smoke_test.exs]` |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `PostCard` extension | New `PostReaderCard` module | Rejected by D-01/D-04; it would create a parallel post display unit and drift from existing markdown/body helpers. `[VERIFIED: .planning/phases/22-post-reader-facelift/22-CONTEXT.md]` |
| `MarkdownBody` pipeline | Direct Raxol markdown renderer | Rejected by D-09 and existing tests; it would risk changing newline grouping and style semantics. `[VERIFIED: .planning/phases/22-post-reader-facelift/22-CONTEXT.md]` `[VERIFIED: test/foglet_bbs/tui/screens/post_reader_test.exs]` |
| Full boxed card at 64x22 | Lightweight gutter | Full boxes consume scarce columns/rows; locked decision requires lightweight gutter at minimum size. `[VERIFIED: .planning/phases/22-post-reader-facelift/22-CONTEXT.md]` |
| Raxol raw progress component | Local `Display.Progress` wrapper | Local wrapper exists specifically to enforce theme routing and avoid hardcoded color atom leakage. `[VERIFIED: lib/foglet_bbs/tui/widgets/display/progress.ex]` |

**Installation:** No new dependency installation. Use existing project dependencies. `[VERIFIED: mix.exs]`

**Version verification:** Versions are verified from `mix.exs`, `mix.lock`, and local tool probes because this Elixir phase has no npm packages. `[VERIFIED: mix.exs]` `[VERIFIED: mix.lock]` `[VERIFIED: elixir --version]`

## Architecture Patterns

### System Architecture Diagram

```text
SSH key input
  -> Foglet.TUI.App routes key/render
    -> Foglet.TUI.Screens.PostReader
      -> selected post + {post.id, width} cache lookup
        -> PostCard reader helper
          -> header element outside Viewport
          -> progress element outside Viewport
          -> MarkdownBody-rendered body lines wrapped with gutter
        -> Raxol Viewport receives only guttered body lines
          -> Viewport slices visible rows by scroll_top/visible_height
            -> Chrome.ScreenFrame wraps reader content + command bar
```

### Recommended Project Structure

```text
lib/foglet_bbs/tui/screens/
├── post_reader.ex                  # screen composition, key handling, viewport wiring
└── post_reader/state.ex            # selected index, viewport state, render cache

lib/foglet_bbs/tui/widgets/post/
├── post_card.ex                    # reader header/progress/body-line helper
└── markdown_body.ex                # existing markdown tuple -> body row pipeline

test/foglet_bbs/tui/screens/
└── post_reader_test.exs            # focused reader render/behavior tests

test/foglet_bbs/tui/widgets/post/
└── post_card_test.exs              # helper tests if public helper added
```

### Pattern 1: Split Header/Progress From Viewport Body

**What:** `PostReader` renders metadata and progress as fixed non-scrolling rows, then passes only body rows into `Viewport`. `[VERIFIED: .planning/phases/22-post-reader-facelift/22-CONTEXT.md]`

**When to use:** Always for Phase 22. The locked decision rejects putting the full card inside `Viewport`. `[VERIFIED: .planning/phases/22-post-reader-facelift/22-CONTEXT.md]`

**Example:**

```elixir
# Source: lib/foglet_bbs/tui/screens/post_reader.ex + proposed PostCard boundary
parts =
  PostCard.reader_parts(post, tuples, w, theme,
    index: idx,
    total: total,
    body_gutter: true,
    progress: true
  )

{vp, _} = Viewport.update({:set_visible_height, available_height}, ss.viewport)
{vp, _} = Viewport.update({:set_children, parts.body_lines}, vp)

column style: %{gap: 0} do
  [parts.header, parts.progress, Viewport.render(vp, %{})]
end
```

### Pattern 2: Cached Tuple Boundary Stays Intact

**What:** `PostReader` continues caching `Foglet.Markdown.render/1` output by `{post.id, width}` and passes cached tuples into `PostCard` helpers. `[VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex]`

**When to use:** In `render_post_content/5`, `warm_viewport/4`, `prepare_after_load/3`, and navigation/scroll paths. `[VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex]`

**Example:**

```elixir
# Source: lib/foglet_bbs/tui/screens/post_reader.ex
tuples = ss.render_cache[{post.id, w}] || parse_body(state, post)
body_lines = PostCard.render_body_lines(tuples, w, theme, gutter: true)
```

### Pattern 3: Width-Safe Progressive Enhancement

**What:** Always render compact `Posts X/N`; render optional segment glyphs only when there is enough width, and measure with `TextWidth`. `[VERIFIED: .planning/phases/22-post-reader-facelift/22-CONTEXT.md]` `[VERIFIED: lib/foglet_bbs/tui/text_width.ex]`

**When to use:** If the planner includes the optional segment indicator. `[VERIFIED: .planning/phases/22-post-reader-facelift/22-CONTEXT.md]`

**Example:**

```elixir
# Source: Foglet.TUI.TextWidth + Display.Progress precedent
compact = "Posts #{index + 1}/#{total}"
segment_width = TextWidth.display_width(" ▰▰▱▱▱")

if width >= TextWidth.display_width(compact) + segment_width + 2 do
  row style: %{gap: 1} do
    [
      text(compact, fg: theme.dim.fg),
      Progress.render((index + 1) / total, segments: 5, show_percentage: false, theme: theme)
    ]
  end
else
  text(compact, fg: theme.dim.fg)
end
```

### Anti-Patterns to Avoid

- **Parsing markdown in `PostReader`:** breaks the existing `MarkdownBody` pipeline and cache boundary. `[VERIFIED: lib/foglet_bbs/tui/widgets/post/markdown_body.ex]`
- **Putting header/progress inside `Viewport.children`:** causes header/progress to scroll away and changes `content_height`. `[VERIFIED: vendor/raxol/lib/raxol/ui/components/display/viewport.ex]`
- **Adding a full box at 64x22:** consumes body width/height in the minimum terminal where the locked requirement only asks for a gutter. `[VERIFIED: .planning/phases/22-post-reader-facelift/22-CONTEXT.md]`
- **Hardcoding color atoms:** violates the widget contract and local `Display.Progress` precedent. `[VERIFIED: lib/foglet_bbs/tui/widgets/README.md]` `[VERIFIED: lib/foglet_bbs/tui/widgets/display/progress.ex]`
- **Testing whole-screen flat text width as the only proof:** Phase 20 review history shows row-isolated width assertions are stronger than whole-screen proxies. `[VERIFIED: .planning/phases/20-rich-rows-and-thread-flow/20-REVIEWS.md]`

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Markdown parsing/styling | New markdown renderer in `PostReader` | `Post.MarkdownBody` via `PostCard` | Existing renderer groups newline-separated tuples correctly and maps styles to theme slots. `[VERIFIED: lib/foglet_bbs/tui/widgets/post/markdown_body.ex]` |
| Terminal display-width math | `String.length/1`, `byte_size/1`, raw grapheme counts | `Foglet.TUI.TextWidth` | Handles display cells, CJK, combining marks, truncation, and padding. `[VERIFIED: lib/foglet_bbs/tui/text_width.ex]` `[VERIFIED: test/foglet_bbs/tui/text_width_test.exs]` |
| Scroll state and clamping | Manual `max_scroll` math in the screen | `Raxol.UI.Components.Display.Viewport.update/2` | Viewport already clamps `scroll_top` on children/height/scroll updates. `[VERIFIED: vendor/raxol/lib/raxol/ui/components/display/viewport.ex]` |
| Progress bar rendering with colors | Raw Raxol progress component or ad hoc color atoms | Compact text plus optional local `Display.Progress` | Local wrapper is theme-routed and avoids hardcoded color leakage. `[VERIFIED: lib/foglet_bbs/tui/widgets/display/progress.ex]` |
| Author/time extraction | Repeated map traversal in `PostReader` | `PostCard.get_handle/1` and `PostCard.get_time_ago/1` | Existing helpers handle missing/empty values and NaiveDateTime conversion. `[VERIFIED: lib/foglet_bbs/tui/widgets/post/post_card.ex]` |
| Read-pointer updates | New UI-local persistence shortcuts | Existing `advance_post/2` and `flush_read_pointers/2` paths | Read pointers are monotonic persisted user state owned by contexts; existing tests cover the behavior. `[VERIFIED: AGENTS.md]` `[VERIFIED: test/foglet_bbs/tui/screens/post_reader_test.exs]` |

**Key insight:** The hard part is preserving boundary ownership, not inventing UI primitives. The implementation is small if `PostCard` becomes the post-unit assembler and `PostReader` remains the viewport/navigation coordinator. `[VERIFIED: .planning/phases/22-post-reader-facelift/22-CONTEXT.md]`

## Common Pitfalls

### Pitfall 1: Header Accidentally Scrolls

**What goes wrong:** Header or progress is included in `Viewport.children`, so it disappears when the user scrolls and changes content-height math. `[VERIFIED: vendor/raxol/lib/raxol/ui/components/display/viewport.ex]`

**Why it happens:** `PostCard.render_from_tuples/5` returns a full card, but `PostReader` needs only body rows inside the viewport. `[VERIFIED: lib/foglet_bbs/tui/widgets/post/post_card.ex]`

**How to avoid:** Use a helper that returns separate header/progress/body parts, or keep header/progress in `PostReader` but delegate their text assembly to `PostCard`. `[VERIFIED: .planning/phases/22-post-reader-facelift/22-CONTEXT.md]`

**Warning signs:** `content_height` increases by 1-2 rows after adding header/progress, or scrolling down hides `Post X of N`. `[VERIFIED: vendor/raxol/lib/raxol/ui/components/display/viewport.ex]`

### Pitfall 2: Gutter Breaks Markdown Row Grouping

**What goes wrong:** Gutter wrapping flattens multi-run markdown rows into plain strings, losing bold/italic/code style nodes. `[VERIFIED: lib/foglet_bbs/tui/widgets/post/markdown_body.ex]`

**Why it happens:** `MarkdownBody` may return bare `text/2` nodes for single-run lines and `row` nodes for multi-run lines. `[VERIFIED: lib/foglet_bbs/tui/widgets/post/markdown_body.ex]`

**How to avoid:** Wrap each existing row element in a new `row style: %{gap: 1}` with a themed gutter text node and the original row element as a child; do not stringify the child. `[VERIFIED: lib/foglet_bbs/tui/widgets/post/markdown_body.ex]`

**Warning signs:** Tests no longer find styled `world` without raw `**world**`, or body text appears but style assertions fail. `[VERIFIED: test/foglet_bbs/tui/screens/post_reader_test.exs]`

### Pitfall 3: Body Width Ignores Gutter Cost

**What goes wrong:** A gutter is added while still rendering markdown at full terminal width, so positioned body text can overflow. `[VERIFIED: test/foglet_bbs/tui/layout_smoke_test.exs]`

**Why it happens:** `PostReader` currently passes full `w` into `PostCard.render_body_lines/4`. `[VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex]`

**How to avoid:** Use a body width budget of `max(w - gutter_width - spacing - frame_margin, 1)` when rendering/warming body lines, and use `TextWidth.display_width/1` for gutter width. `[VERIFIED: lib/foglet_bbs/tui/text_width.ex]`

**Warning signs:** 64x22 layout smoke fails with `element.x + TextWidth.display_width(text) > width`. `[VERIFIED: test/foglet_bbs/tui/layout_smoke_test.exs]`

### Pitfall 4: Cache And Viewport Use Different Body-Line Helpers

**What goes wrong:** Initial render shows guttered body rows, but `j/k` scroll state was warmed with unguttered rows or a different line count. `[VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex]`

**Why it happens:** `render_post_content/5` and `warm_viewport/4` both call `PostCard.render_body_lines/4` today; changing only one creates divergence. `[VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex]`

**How to avoid:** Add one private `reader_body_lines(post, tuples, width, theme)` call path or a public `PostCard` helper and use it from both render and warm paths. `[VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex]`

**Warning signs:** `viewport.children` test passes before render but visual render lacks the gutter, or vice versa. `[VERIFIED: test/foglet_bbs/tui/screens/post_reader_test.exs]`

### Pitfall 5: Progress Competes With The Command Bar

**What goes wrong:** Progress is placed too low or consumes too many rows, pushing content into bottom chrome or hiding commands at 64x22. `[VERIFIED: .planning/phases/18-chrome-v2/18-CONTEXT.md]`

**Why it happens:** Current reader reserves `available_height = max(h - 10, 5)`; adding rows without recalculating the fixed header/progress budget changes usable body height. `[VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex]`

**How to avoid:** Treat progress as a one-line fixed surface and recompute available viewport height based on actual fixed rows, with 5 as the minimum visible body height only if chrome still fits. `[VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex]`

**Warning signs:** Layout smoke has overlapping y-ranges or command text disappears at 64x22. `[VERIFIED: test/foglet_bbs/tui/layout_smoke_test.exs]`

## Code Examples

### Header Formatting Helper

```elixir
# Source: lib/foglet_bbs/tui/widgets/post/post_card.ex helper extraction pattern
def reader_header(post, width, %Theme{} = theme, opts) do
  index = Keyword.fetch!(opts, :index)
  total = Keyword.fetch!(opts, :total)
  handle = get_handle(post) || "unknown"
  age = get_time_ago(post)
  message_number = Map.get(post, :message_number)

  atoms =
    [
      "Post #{index + 1} of #{total}",
      if(message_number, do: "##{message_number}", else: "#?"),
      "@#{handle}",
      if(age, do: "#{age} ago", else: "age ?")
    ]

  content = Enum.join(atoms, " • ") |> TextWidth.truncate(width)
  text(content, fg: theme.dim.fg)
end
```

### Guttered Body Lines Without Flattening Markdown

```elixir
# Source: MarkdownBody returns row/text elements; wrap, do not stringify.
def render_body_lines(tuples, width, %Theme{} = theme, opts) do
  gutter? = Keyword.get(opts, :gutter, false)
  gutter = Keyword.get(opts, :gutter_char, "│")
  gutter_width = TextWidth.display_width(gutter <> " ")
  body_width = if gutter?, do: max(width - gutter_width, 1), else: width

  lines = MarkdownBody.render_tuples_as_lines(tuples, body_width, theme, body_opts(opts))

  if gutter? do
    Enum.map(lines, fn line ->
      row style: %{gap: 1} do
        [text(gutter, fg: theme.border.fg), line]
      end
    end)
  else
    lines
  end
end
```

### Size Contract Assertion Shape

```elixir
# Source: test/foglet_bbs/tui/layout_smoke_test.exs positioned-render pattern
for {width, height} <- [{64, 22}, {80, 24}, {132, 50}] do
  positioned = PostReader.render(state) |> apply_at_size({width, height})
  texts = text_elements(positioned)

  assert Enum.any?(texts, &String.contains?(&1.text, "Post 3 of 12"))
  assert Enum.any?(texts, &String.contains?(&1.text, "#42"))
  assert Enum.any?(texts, &String.contains?(&1.text, "Posts 3/12"))
  assert Enum.any?(texts, &(&1.text == "│" or String.contains?(&1.text, "|")))

  for element <- texts do
    assert element.x >= 0
    assert element.y >= 0
    assert element.x + TextWidth.display_width(element.text) <= width
  end
end
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Screen-local post header lines plus loose body rows | Shared post-unit boundary under `Foglet.TUI.Widgets.Post.*` with reader-specific parts | Phase 22 locked context, 2026-04-25 | Keeps post rendering reusable and avoids per-screen visual drift. `[VERIFIED: .planning/phases/22-post-reader-facelift/22-CONTEXT.md]` |
| Whole-card rendering as one element | Split fixed header/progress and scrollable body lines | Existing `Viewport` migration before Phase 22 | Preserves scroll ownership and content-height semantics. `[VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex]` |
| Raw length/slice layout checks | `Foglet.TUI.TextWidth` display-cell helpers | Phase 16 milestone foundation | Unicode glyphs and combining/CJK text remain layout-safe. `[VERIFIED: .planning/REQUIREMENTS.md]` `[VERIFIED: lib/foglet_bbs/tui/text_width.ex]` |
| Raxol progress component directly | Local `Display.Progress` wrapper or compact text | Existing local widget library | Avoids hardcoded color defaults and enforces theme routing. `[VERIFIED: lib/foglet_bbs/tui/widgets/display/progress.ex]` |

**Deprecated/outdated:**
- Two-line reader metadata (`Post X of N` plus `By @handle · age`) is superseded by one compact metadata header with stable message number. `[VERIFIED: .planning/phases/22-post-reader-facelift/22-SPEC.md]`
- Full card-in-viewport composition is rejected for this phase because it would scroll header/progress with body content. `[VERIFIED: .planning/phases/22-post-reader-facelift/22-CONTEXT.md]`

## Assumptions Log

All claims in this research were verified or cited from local project source, locked phase context, or local dependency source. No user confirmation needed.

## Open Questions

1. **Should optional segmented progress ship now?**
   - What we know: Compact `Posts X/N` is mandatory; segmented glyphs are optional enhancement. `[VERIFIED: .planning/phases/22-post-reader-facelift/22-CONTEXT.md]`
   - What's unclear: Whether the extra visual polish is worth the test and width-budget cost in Phase 22.
   - Recommendation: Ship compact text first; include segments only if the implementation stays under the same test wave and collapses before compact text.

2. **Should the helper return `{header, progress, body_lines}` or separate functions?**
   - What we know: Planner has discretion over exact function names and return shape. `[VERIFIED: .planning/phases/22-post-reader-facelift/22-CONTEXT.md]`
   - What's unclear: Which shape will read cleaner after implementation.
   - Recommendation: Prefer one `reader_parts/5` helper if it eliminates duplicate width/gutter math between render and warm paths.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| `rtk` | Required repo command prefix | yes | 0.37.2 | none |
| Elixir | Compile/tests | yes | 1.19.5 on OTP 28 | none |
| Mix | Test/precommit aliases | yes | 1.19.5 | none |
| PostgreSQL client | DataCase-backed test setup | yes | psql 14.20 | Existing `rtk mix test` setup handles DB create/migrate |
| Raxol local vendor source | TUI framework source inspection | yes | path dependency, transitive 2.4.0 packages in lock | none |

**Missing dependencies with no fallback:** None found. `[VERIFIED: command probes]`

**Missing dependencies with fallback:** None found. `[VERIFIED: command probes]`

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | ExUnit with project aliases |
| Config file | `test/test_helper.exs` plus `FogletBbs.DataCase` for DB-backed tests |
| Quick run command | `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs test/foglet_bbs/tui/widgets/post/post_card_test.exs` |
| Full suite command | `rtk mix precommit` |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| READER-01 | Header includes `Post X of N`, `#message_number`, `@handle`, and age token | unit/render | `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs` | yes |
| READER-02 | Body rows preserve markdown and show gutter | unit/render + layout smoke | `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` | yes |
| READER-03 | Compact progress renders for longer threads and behavior remains intact | unit/behavior | `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs` | yes |
| READER-04 | Reader delegates visual assembly to `Foglet.TUI.Widgets.Post.*` | unit/static source or helper tests | `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs test/foglet_bbs/tui/widgets/post/post_card_test.exs` | yes |

### Sampling Rate

- **Per task commit:** `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs`
- **Per wave merge:** `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs test/foglet_bbs/tui/widgets/post/post_card_test.exs test/foglet_bbs/tui/layout_smoke_test.exs`
- **Phase gate:** `rtk mix precommit`

### Wave 0 Gaps

- [ ] Add Phase 22 assertions to `test/foglet_bbs/tui/screens/post_reader_test.exs` for compact header, message number, gutter, progress, and existing behavior preservation.
- [ ] Add Phase 22 size-contract block to `test/foglet_bbs/tui/layout_smoke_test.exs` for `{64,22}`, `{80,24}`, `{132,50}`.
- [ ] Add `test/foglet_bbs/tui/widgets/post/post_card_test.exs` coverage only if a new public `PostCard` reader helper is introduced.

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V2 Authentication | no | Existing SSH/session flow unchanged. `[VERIFIED: .planning/phases/22-post-reader-facelift/22-SPEC.md]` |
| V3 Session Management | no | Existing `PostReader` screen transition and `TUI.App` routing unchanged. `[VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex]` |
| V4 Access Control | no new control | No new domain queries or mutations; existing posts are already loaded by context flow. `[VERIFIED: .planning/phases/22-post-reader-facelift/22-SPEC.md]` |
| V5 Input Validation | no new user input | Phase renders already-loaded post data and handles existing keys only. `[VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex]` |
| V6 Cryptography | no | No secrets, tokens, or cryptographic operations. `[VERIFIED: .planning/phases/22-post-reader-facelift/22-SPEC.md]` |

### Known Threat Patterns for SSH TUI Rendering

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Terminal/layout spoofing through unbounded post text | Spoofing / Tampering | Keep rendered text within layout bounds using `TextWidth` and layout smoke overflow checks. `[VERIFIED: test/foglet_bbs/tui/layout_smoke_test.exs]` |
| Authorization bypass via visual-only hiding | Elevation of Privilege | Do not add domain side effects; preserve existing context-owned post loading and read-pointer flushing. `[VERIFIED: AGENTS.md]` |
| Escaped markdown semantics drift | Tampering | Preserve `Foglet.Markdown.render/1` -> `MarkdownBody` path; do not add a second parser. `[VERIFIED: lib/foglet_bbs/tui/widgets/post/markdown_body.ex]` |

## Sources

### Primary (HIGH confidence)

- `AGENTS.md` - SSH-first boundary, widget/theme conventions, TUI workflow rules, test/precommit rules.
- `.planning/phases/22-post-reader-facelift/22-CONTEXT.md` - Locked implementation decisions D-01 through D-16.
- `.planning/phases/22-post-reader-facelift/22-SPEC.md` - Requirements, constraints, acceptance criteria, boundaries.
- `.planning/REQUIREMENTS.md` - READER-01 through READER-04 and v1.3 traceability.
- `SCREENS.md` - Classic Modern BBS post reader target sketch.
- `docs/raxol/getting-started/WIDGET_GALLERY.md` - Raxol DSL, `Viewport`, markdown renderer, progress docs.
- `lib/foglet_bbs/tui/widgets/README.md` - Local widget conventions and theme routing contract.
- `lib/foglet_bbs/tui/screens/post_reader.ex` - Existing reader composition, cache, viewport, key handling, read-pointer flushing.
- `lib/foglet_bbs/tui/widgets/post/post_card.ex` - Existing post display unit, cached tuple renderer, body-line renderer, author/time helpers.
- `lib/foglet_bbs/tui/widgets/post/markdown_body.ex` - Existing markdown body renderer and logical line grouping.
- `vendor/raxol/lib/raxol/ui/components/display/viewport.ex` - Viewport state, update, clamp, and render behavior.
- `test/foglet_bbs/tui/screens/post_reader_test.exs` - Existing behavior tests and render assertions.
- `test/foglet_bbs/tui/layout_smoke_test.exs` - Positioned layout test patterns and canonical size checks.

### Secondary (MEDIUM confidence)

- `.planning/phases/20-rich-rows-and-thread-flow/20-RESEARCH.md` and `20-REVIEWS.md` - Prior width-testing lessons and anti-patterns.
- `.planning/phases/21-board-directory-facelift/21-RESEARCH.md` and `21-CONTEXT.md` - Latest Classic Modern BBS facelift precedent.

### Tertiary (LOW confidence)

- None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - existing local stack and versions verified through `mix.exs`, `mix.lock`, vendor source, and command probes.
- Architecture: HIGH - locked phase context and current source agree on screen/widget/viewport boundaries.
- Pitfalls: HIGH - derived from existing tests, Raxol `Viewport` source, and prior Phase 20/21 planning evidence.

**Research date:** 2026-04-25
**Valid until:** 2026-05-25 for this local-stack phase; re-check if `vendor/raxol`, `PostReader`, or `PostCard` changes first.
