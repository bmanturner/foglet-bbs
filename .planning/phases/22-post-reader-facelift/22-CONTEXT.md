# Phase 22: post-reader-facelift - Context

**Gathered:** 2026-04-25 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 22 refreshes `Foglet.TUI.Screens.PostReader` into the Classic Modern BBS reader shape from `SCREENS.md`: the selected post has one compact metadata header with position, stable message number, author, and age; the body has a visible left gutter/card treatment while preserving markdown rendering; and the thread shows compact progress that works at 64x22. Existing `Viewport` scroll ownership, navigation keys, reply/back transitions, render-cache behavior, and read-pointer flushing remain unchanged.

Phase 22 does NOT change composer visuals, thread-list rows, board-directory presentation, post query semantics, message-number allocation, read-pointer persistence rules, markdown parsing semantics, or browser workflows.

</domain>

<decisions>
## Implementation Decisions

### Shared Post Unit

- **D-01:** Extend `Foglet.TUI.Widgets.Post.PostCard` as the shared post unit for the facelift instead of introducing a parallel sibling widget. `PostReader` should delegate post visual assembly to `Foglet.TUI.Widgets.Post.*`; it should not grow a new screen-local pile of header/body/footer formatting.
- **D-02:** `PostCard` may add a reader-oriented helper, recommended as a small public function that accepts a post, pre-parsed markdown tuples, width, theme, and `index`/`total` options, while keeping the existing markdown cache boundary intact. The helper should produce header/body/progress pieces or body lines in a shape `PostReader` can compose with `Viewport`.
- **D-03:** Do not route the reader through `PostCard.render/4` if that would put the entire card inside the viewport. The viewport remains responsible only for the scrollable post body rows; the header and progress surfaces remain non-scrolling content around it.

### Compact Header

- **D-04:** Render one compact metadata header for the selected post: `Post X of N • #message_number • @handle • age ago`. The exact separator may be `•` or another theme-consistent single-cell separator, but the rendered tree must include `Post X of N`, `#message_number`, `@handle`, and a short age token.
- **D-05:** Header formatting should reuse `PostCard.get_handle/1` and `PostCard.get_time_ago/1` or equivalent helper extraction under `Foglet.TUI.Widgets.Post`. It should degrade gracefully when handle, timestamp, or message number is missing, but tests must cover the normal fully-populated path.
- **D-06:** The header is rendered above the scrollable body and uses theme slots such as `theme.dim`, `theme.title`, `theme.badge`, or `theme.accent`; no hardcoded terminal color atoms are added.

### Body Gutter And Viewport

- **D-07:** Add the left body gutter in the post widget/body-line assembly path, recommended at `PostCard.render_body_lines/4` or a closely related `Post.MarkdownBody` helper, so every logical body row passed into `Viewport` already includes the gutter treatment.
- **D-08:** The minimum-size 64x22 body treatment is a lightweight left gutter such as `│ ` or `| `, not a full framed card. Full boxes are optional only if the planner can prove they do not steal too much body width or break the viewport at 64x22.
- **D-09:** Markdown rendering behavior remains delegated to `Post.MarkdownBody`; Phase 22 may wrap rendered line rows with a gutter, but it must not introduce a separate markdown parsing or styling pipeline in `PostReader`.
- **D-10:** `PostReader.State.viewport` remains the owner of within-post scroll state. `advance_post/2`, `scroll_post/2`, `warm_cache/4`, `warm_viewport/4`, and `prepare_after_load/3` keep their behavioral roles, with only the rendered body-line shape changing.

### Progress Surface

- **D-11:** Always render compact progress text such as `Posts X/N` for the selected post. This compact text is the required baseline at 64x22 and 80x24.
- **D-12:** A segmented visual indicator such as `▰▰▱▱▱` is allowed only as progressive enhancement when width permits. If included, it must be generated with display-width helpers and must collapse before the compact `Posts X/N` text disappears.
- **D-13:** Progress belongs in non-scrolling reader content, not inside the scrollable body rows. It may sit below the header, above the viewport, or below the viewport depending on what gives the cleanest 64x22 layout, but it must not compete with the command bar or change key hints.

### Test Placement

- **D-14:** Extend `test/foglet_bbs/tui/screens/post_reader_test.exs` for focused render assertions: compact header includes `Post 1 of 1`, `#42`, `@mina`, and an age token; longer-thread progress renders `Posts 3/12`; and existing navigation, scroll, reply, back, cache, and read-pointer tests continue to pass.
- **D-15:** Extend `test/foglet_bbs/tui/layout_smoke_test.exs` with a Phase 22 PostReader size-contract block at `[{64, 22}, {80, 24}, {132, 50}]`. Assertions should cover header text, body gutter presence, compact progress, selected body visibility, and no positioned text overflow/overlap.
- **D-16:** Add or extend `test/foglet_bbs/tui/widgets/post/post_card_test.exs` only if new public PostCard helper behavior is introduced. If the implementation only changes existing helper output through screen-level composition, screen and layout tests are sufficient.

### the agent's Discretion

- Exact function names and return shape for the PostCard reader helper, as long as `PostReader` delegates visual assembly to `Foglet.TUI.Widgets.Post.*` and preserves the render-cache tuple boundary.
- Exact separator glyph between header atoms. Prefer `•` because `SCREENS.md` uses it in the target sketch, but planner may choose another single-cell separator if tests or readability point elsewhere.
- Exact gutter glyph (`│` recommended; ASCII `|` acceptable if layout tests or terminal compatibility make it simpler).
- Whether the optional segmented progress indicator ships in Phase 22. Compact `Posts X/N` is mandatory; the segment bar is optional.
- Exact placement of progress relative to header and viewport, provided 64x22 remains readable and body rows retain practical width.

### Folded Todos

None — `gsd-sdk query todo.match-phase 22` returned `todo_count: 0`.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Locked Phase Scope

- `.planning/phases/22-post-reader-facelift/22-SPEC.md` — Locked Phase 22 requirements, boundaries, constraints, acceptance criteria, ambiguity report, and interview decisions.
- `.planning/ROADMAP.md` §Phase 22 — Milestone position, dependency on Phase 20, requirements `READER-01`-`READER-04`, and success criteria.
- `.planning/REQUIREMENTS.md` §Post Reader — Requirement IDs `READER-01`, `READER-02`, `READER-03`, `READER-04`.
- `SCREENS.md` §Post Reader — Classic Modern BBS target sketch, compact metadata header, left gutter, PostCard reuse, and progress indicator guidance.
- `SCREENS.md` §Design Principles and §Chosen Direction — Terminal-native, keyboard-first, Unicode-capable Classic Modern BBS direction.

### Dependency Contracts

- `.planning/phases/16-unicode-width-foundation/16-CONTEXT.md` — `Foglet.TUI.TextWidth` width-helper contract used for gutter/progress/header width safety and layout-smoke assertions.
- `.planning/phases/17-theme-and-mode-metadata/17-CONTEXT.md` — Theme-slot vocabulary and `:bbs` mode metadata.
- `.planning/phases/18-chrome-v2/18-CONTEXT.md` — `Chrome.ScreenFrame` composition boundary and `[{64,22},{80,24},{132,50}]` size-contract triple.
- `.planning/phases/19-main-menu-dashboard/19-CONTEXT.md` — Layout-smoke precedent and Classic Modern BBS glyph/theme discipline.
- `.planning/phases/20-rich-rows-and-thread-flow/20-CONTEXT.md` — Width-safe row/glyph precedent and shared testing shape.
- `.planning/phases/21-board-directory-facelift/21-CONTEXT.md` — Latest Classic Modern BBS facelift precedent, including row treatment, compact metadata, and size-contract testing.

### Existing Code Touch Points

- `lib/foglet_bbs/tui/screens/post_reader.ex` — Main screen to facelift. Preserve `handle_key/2`, `load_posts/2`, `flush_read_pointers/2`, `prepare_after_load/3`, render-cache keys, viewport ownership, and read-pointer behavior.
- `lib/foglet_bbs/tui/screens/post_reader/state.ex` — Existing `%PostReader.State{}` with `selected_post_index`, `viewport`, and `render_cache`; no shape change expected.
- `lib/foglet_bbs/tui/widgets/post/post_card.ex` — Shared post display unit to extend/reuse for compact header, body gutter, and cached tuple rendering.
- `lib/foglet_bbs/tui/widgets/post/markdown_body.ex` — Existing markdown-to-body-line renderer; preserve styling semantics and optionally wrap line output with a gutter through PostCard.
- `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex` — Existing chrome boundary. `PostReader.render/1` continues using it.
- `lib/foglet_bbs/tui/text_width.ex` — Display-width helpers for optional progress bars, gutter/body width calculations, and overflow-safe tests.
- `lib/foglet_bbs/tui/theme.ex` — Theme slots for header/gutter/progress styling; no hardcoded color atoms.
- `lib/foglet_bbs/time_ago.ex` — Short relative time formatter consumed by PostCard.
- `lib/foglet_bbs/tui/widgets/display/tree.ex` is not relevant to this phase; no board/tree work should leak in.

### Test Anchors

- `test/foglet_bbs/tui/screens/post_reader_test.exs` — Existing behavior tests; extend for header, message number, gutter/progress render assertions while preserving navigation/scroll/reply/back/cache/read-pointer coverage.
- `test/foglet_bbs/tui/layout_smoke_test.exs` — Existing positioned-render harness; add Phase 22 size-contract coverage at `64x22`, `80x24`, and `132x50`.
- `test/foglet_bbs/tui/widgets/post/post_card_test.exs` — Add or extend only if new public PostCard helper behavior is introduced.
- `test/foglet_bbs/tui/widgets/post/markdown_body_test.exs` — Reference for preserving markdown line grouping/styling behavior if gutter logic reaches MarkdownBody.
- `test/foglet_bbs/tui/text_width_test.exs` — Width fixtures for Unicode-safe progress/gutter assertions if needed.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- `Foglet.TUI.Widgets.Post.PostCard.render_from_tuples/5` already assembles a full post card from cached markdown tuples. It is the natural extension point for reader-specific post-unit rendering without reparsing markdown.
- `Foglet.TUI.Widgets.Post.PostCard.render_body_lines/4` already returns flat body row elements for `Viewport`. Wrapping these rows with a gutter keeps scroll ownership where it is today.
- `Foglet.TUI.Widgets.Post.PostCard.author_line/1`, `get_handle/1`, and `get_time_ago/1` already handle author/time extraction and graceful degradation.
- `Foglet.TUI.Widgets.Post.MarkdownBody.render_tuples_as_lines/4` already preserves markdown grouping/styling and returns one element per logical line.
- `Raxol.UI.Components.Display.Viewport` is already warmed from `PostReader.warm_viewport/4` and rendered from transient visible-height/children state inside `render_post_content/5`.
- `Foglet.TUI.TextWidth` provides display-width-safe truncation, slicing, and padding for any optional segmented progress or width-bound header work.

### Established Patterns

- Screen render helpers stay pure over already-loaded state; state writes remain in load/navigation/scroll helpers.
- Domain work stays out of TUI rendering. Phase 22 reads already-loaded posts only and introduces no context mutations.
- Styling routes through `Foglet.TUI.Theme` slots, not literal color atoms.
- Width-sensitive layout uses `TextWidth`, especially when Unicode glyphs such as `│`, `•`, `▰`, or `▱` are involved.
- Size contracts live in the shared `layout_smoke_test.exs` file at the v1.3 triple `[{64,22},{80,24},{132,50}]`.
- Existing screen behavior tests are extended in place instead of replaced by screenshot fixtures.

### Integration Points

- `PostReader.render/1` keeps calling `ScreenFrame.render(state, %{}, post_content, keys)`.
- `PostReader.render_post_content/5` becomes mostly composition: get selected post, retrieve cached tuples, ask `PostCard`/`Post.*` for header/body/progress pieces, update transient viewport visible height/children, and render the viewport.
- `warm_viewport/4` must use the same body-line helper as `render_post_content/5`, so scrolling keys and render output agree on content height.
- `advance_post/2` and `scroll_post/2` stay behaviorally unchanged, except that warmed viewport children now include the guttered body rows.
- `ThreadList` remains the route into `PostReader`; no Phase 22 changes are needed there.

</code_context>

<specifics>
## Specific Ideas

- Follow the `SCREENS.md` reader shape: `Post 3 of 12 • #42 • @mina • 9m ago`, a left body gutter, and compact progress such as `Posts 3/12`.
- Prefer `│` as the gutter glyph because it matches the sketch and reads as a light message-body rail. ASCII `|` is acceptable only if it simplifies compatibility.
- Treat a segmented progress bar as optional polish; the durable requirement is compact text progress.
- Preserve the existing `PostReader` command set (`N`, `P`, `J`, `K`, `R`, `Q`) and avoid introducing command-bar changes in this phase.

</specifics>

<deferred>
## Deferred Ideas

- Composer editor-frame, preview tabs, counters, and quoted-context facelift — Phase 23 scope.
- Thread-list details, rich-row changes, or browsing metadata changes — Phase 20 scope and follow-up territory, not Phase 22.
- Board-directory visual changes or subscription/read-state presentation — Phase 21 scope.
- Broader markdown styling redesign for headings, quotes, code, and links beyond preserving current markdown behavior inside the reader treatment.
- New read-pointer semantics, post query behavior, message-number allocation, or persistence changes.
- Screenshot-based terminal fixtures; Phase 22 sticks with code/layout tests unless a future visual QA phase adds screenshots.

### Reviewed Todos (not folded)

None — no matching todos for this phase.

</deferred>

---

*Phase: 22-post-reader-facelift*
*Context gathered: 2026-04-25*
