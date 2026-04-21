# Phase 03 Polish — Research Summary

**Project:** Foglet BBS
**Workstream:** phase-03-polish (v1.0.1)
**Domain:** Hardening pass on a shipped SSH + Raxol TUI — NOT new domain features
**Researched:** 2026-04-19
**Confidence:** HIGH

## Executive Summary

Phase 03 shipped a functional SSH-delivered Raxol TUI, but hands-on use surfaced eleven consistency, correctness, and completeness gaps. This is a **polish milestone, not a feature milestone** — every item is a fix to something already in production. The stack is locked (Elixir 1.19.5, Phoenix 1.8.5, Raxol 2.4.0 vendored, MDEx 0.12.1, Postgres). **Zero new runtime dependencies are required** — Raxol 2.4.0 already provides every UI primitive the scope needs; MDEx is already in `mix.exs`; relative-time formatting and min-size gating are stdlib-and-30-lines-of-code away.

The dominant risk is **re-inventing what Raxol already ships**. The block-macro DSL is load-bearing: the legacy `panel/1` + `box(children:)` function-form silently lays out to empty trees with the modern runtime (documented post-mortem in `memory/feedback_raxol_modern_dsl.md`). This extends to Raxol's own stateful components — `MarkdownRenderer`, `StatusBar`, `MultiLineInput.render/2` — which emit tuple-shape trees that crash Flexbox when embedded in block-macro parents. The research verdict is therefore nuanced: **use Raxol's state machinery and view DSL (`box`/`column`/`row`/`text`/`divider`), but re-implement component `render/N` paths as thin function-form widgets inside `Foglet.TUI.Widgets.*`.** That gives us the "don't reinvent" principle in spirit (composition over invention) without tripping the tuple-tree landmine.

Two root-cause bugs were located in-code and must be fixed:

1. **Markdown renders raw characters** because `Foglet.Markdown.render_markdown_tuples/1` maps each `{text, style}` tuple one-to-one to a `text/2` node including the literal `{"\n", :plain}` separator tuples — newlines become visible "\n" children instead of driving sibling separation inside a `column`. Fix: group tuples by newline, emit one `text/2` per line.
2. **Board unread count sticks at (6)** because `Boards.advance_board_read_pointer/3` uses a replace-on-conflict upsert — reading an older thread *after* a newer one moves the pointer **backwards**, reviving unread posts. Compounded by `ctx[:last_read_message_number] || 0` falling back to `0` (zeroes the pointer on quick-quit), and by `BoardList` caching `state.board_list` without refreshing on screen-return. Fix: monotonic-max upsert, remove the `|| 0` fallback, dispatch `{:load_boards}` on every `:board_list` transition.

## Key Findings

### Recommended Stack (zero new deps confirmed)

Stack is locked. Research narrowed to **which Raxol primitives map to which polish items** and what tiny Foglet-owned modules fill the gaps Raxol doesn't cover.

**Use these Raxol primitives directly (block-macro DSL):**
- `box`, `column`, `row`, `spacer`, `divider` — all layout
- `text/2` with `fg:`, `bg:`, `style:` — all text rendering; auto-downsamples colors
- Raxol auto-adaptive color (`Raxol.Style.Colors.Adaptive`) handles truecolor → 256 → 16 → mono

**Use Raxol state, render yourself:**
- `Raxol.UI.Components.Input.MultiLineInput` state struct — keep; never call its `render/2` (already the established pattern at `post_composer.ex:259`)

**Explicitly reject (incompatible with block-macro DSL):**
- `Raxol.UI.Components.MarkdownRenderer` — tuple-shape output; also uses Earmark fallback vs. our MDEx. Keep `Foglet.Markdown` but fix the newline-grouping bug.
- `Raxol.UI.Components.Display.StatusBar` — tuple-shape output; 20-line function widget does the job cleanly.
- `Raxol.UI.Theming.ThemeManager` (GenServer) — coupled to Raxol components we're rejecting; a plain `Foglet.TUI.Theme` struct in `session_context` gives 80% of the benefit.

**New Foglet-owned modules (all pure functions, no deps beyond stdlib + Raxol DSL):**
- `Foglet.TUI.Theme` — struct with 6–8 semantic color slots (`fg_primary`, `fg_dim`, `fg_accent`, `fg_error`, `fg_warning`, `border`); resolved once per session in `CLIHandler.build_context/3` from `user.theme`.
- `Foglet.TUI.Widgets.Chrome.ScreenFrame` — wraps every screen's `box + column + status_bar + divider + content + key_bar`; also owns the terminal-too-small render-time branch.
- `Foglet.TUI.Widgets.List.SelectionList` + `ListRow` — unifies board/thread/new-thread list navigation.
- `Foglet.TUI.Widgets.Post.MarkdownBody` + `PostCard` — fixes the markdown render bug.
- `Foglet.TimeAgo` — 30-line stdlib-only short-form relative time (`30s`, `5m`, `2h`, `3d`, `2w`, `6mo`, `2y`).

### MVP Floor (what must ship for v1.0.1 to feel like polish)

**Table stakes — ship or the milestone fails:**

| # | Item | Why it's floor |
|---|------|----------------|
| 1 | Markdown renders correctly (root-cause fix in `render_markdown_tuples/1`) | Posts currently show raw `**bold**` — most visible defect |
| 2 | Single `ScreenFrame` widget used by all 9 screens | Cross-cutting; prerequisite for #6, #8, #9 |
| 4 | Board unread count fix (monotonic pointer + refresh-on-navigate) | The "(6 unread) forever" bug; trust-destroying |
| 7 + 11 | `[C]` on thread_list routes to existing `:new_thread` (pre-filled board); thread creation wired end-to-end | Creating a new thread from the board page is literally impossible today — it crashes |
| 9 | Too-small terminal gate (render-time branch in `ScreenFrame`) | Below 60×20 the UI is garbled |

**Differentiators — ship if time allows:**

- Thread list row enrichment (item 5: creator, time-ago, post count) — uses `Foglet.TimeAgo` + existing `:created_by` preload
- Theme consistency (item 6: `Foglet.TUI.Theme` struct wired everywhere) — mechanical grep-and-replace of hardcoded `fg: :green`
- Widget layer polish (item 8) — emerges naturally from #2 + #5 and is effectively half-done by that point
- Item 3 (seeded threads render correctly) is an **acceptance criterion** of #1/#2, not a separate deliverable

**Safe to defer to a later polish pass or original milestone:**

- Item 10 (email verification toggle + resend wiring) — SEED-002 explicitly flags actual SMTP delivery for Milestone 10; the config-key + resend-cooldown work is small but auth-flow-adjacent (higher blast radius). If scope tightens, defer 10.
- Any theming beyond the static `Theme` struct — ThemeManager / per-user runtime theme switching belongs to Milestone 4's "theme stub"
- OSC-8 hyperlinks, syntax-highlighted code blocks, tables in markdown, live unread-count badges, clock in status bar

### Architecture Approach

Foglet TUI is a **single Raxol TEA loop** (`%App{}` model, `update/2`, `view/1`) per SSH session. Screens are pure `{render/1, handle_key/2}` modules — no per-screen process. Widgets are **function-form render helpers** (`Foglet.TUI.Widgets.*.render/1 :: props_map -> view_ast`), never `use Raxol.UI.Components.Base.Component`. This shape is already established; the polish work extends, doesn't replace.

**Nine integration decisions (from ARCHITECTURE.md):**

1. **Widget layer** — function-form widgets only; no component-form. (§2.1)
2. **Screen chrome** — `Chrome.ScreenFrame` helper called by each screen; not a sibling process, not an app-level wrapper. (§2.2)
3. **Theme** — struct in `session_context`, resolved once in `CLIHandler.build_context/3`; passed as a prop. (§2.3)
4. **Markdown** — render at view time with per-screen memoization keyed by `{post.id, width, last_edited_at}`; `body_rendered` column stays NULL. (§2.4)
5. **Unread count** — DB-level monotonic-max upsert + remove `|| 0` fallback + refresh `state.board_list` on every `:board_list` transition. (§2.5)
6. **Thread creation** — route `ThreadList [C]` to the **already existing** `:new_thread` screen with pre-filled board; do NOT extend `PostComposer` with a conditional title field. (§2.6)
7. **Too-small gate** — render-time branch inside `ScreenFrame` at 60×20 floor; preserves `screen_state` so resize-back restores unchanged. (§2.7)
8. **Email verification toggle** — `Foglet.Config` key `require_email_verification` read in `CLIHandler` context build; branches in `register.ex` and `login.ex`. (§2.8)
9. **Raxol rejections** — documented list of Raxol components we adopt, wrap, or reject with rationale. (§2.9)

### Build Order — Reconciled DAG

ARCHITECTURE.md proposed 6 phases (P1 Foundations → P2 Screen migration → P3 Unread → P4 New-thread flow → P5 Verify toggle → P6 E2E verification). PITFALLS.md proposed 7 (P0 Seeds → P1 Widget foundation → P2 Markdown → P3 Read-pointer → P4 Composer → P5 Resize → P6 Verify). These are compatible — PITFALLS adds a P0 seed-fixtures step and separates markdown from widget-foundation. **Adopt the PITFALLS ordering** because (a) the P0 seed step is a real prerequisite for UAT, (b) separating markdown from widget-foundation localizes the highest-risk correctness work, and (c) resize gating after composer stability avoids churning both together.

| Phase | Name | Scope items | Notes |
|-------|------|-------------|-------|
| P0 | Seeds & fixtures | #3 partial | Ensure seed threads have valid `message_number > 0` and non-nil `last_post_at`; quick win so later UAT has real data |
| P1 | Widget foundation + theme | #2, #6, #8 | `Theme` struct, `ScreenFrame`, `SelectionList`/`ListRow`, baseline for everything downstream |
| P2 | Markdown rendering | #1, (#3) | Fix `render_markdown_tuples/1` newline grouping; build `Post.MarkdownBody`; per-screen cache |
| P3 | Read-pointer correctness | #4, #5 | Monotonic-max upsert; remove `|| 0` fallback; refresh-on-navigate; thread-list row enrichment (`TimeAgo`, creator handle, post count) |
| P4 | Composer & thread creation | #7, #11 | Route `[C]` to `:new_thread`; verify reply path; delete broken `current_thread: nil → PostComposer` branch |
| P5 | Resize & min-size gating | #9 | Render-time branch in `ScreenFrame`; regression test on alt-screen leave across all exit paths |
| P6 | Email verification | #10 | `require_email_verification` config; `register`/`login` branches; resend cooldown moved into `resend_code_raw/1` |

**Strict dependencies:** P1 → P2 → P3; P4/P5/P6 are independent after P1+P2 land. P0 can run in parallel with P1.

## Use Raxol, Don't Rebuild — Pre-Approved Component Selection

Downstream planners: when a polish item calls for UI, pick from this table first. "Build" is only justified when Raxol's component emits tuple-shape output that breaks inside block-macro parents.

| Polish item | Raxol primitive / component | Action |
|-------------|------------------------------|--------|
| #1 Markdown rendering | `Raxol.UI.Components.MarkdownRenderer` | **Reject** (tuple-shape + Earmark vs MDEx). Fix `Foglet.Markdown.render_markdown_tuples/1` newline grouping; build `Post.MarkdownBody` function widget. |
| #2 Status bar | `Raxol.UI.Components.Display.StatusBar` | **Reject** (tuple-shape). Build `Widgets.Chrome.StatusBar` as a 20-line function widget using `row` + `text` + `spacer`. |
| #2 Screen chrome | `box`, `column`, `divider`, `row` | **Use directly** via block-macro DSL inside `Widgets.Chrome.ScreenFrame`. |
| #4 Board row / unread | `Raxol.UI.Components.Input.SelectList` | Consider for Phase 04; for v1.0.1 build `Widgets.List.SelectionList` as function widget with `row_renderer:` callback prop. |
| #5 Thread rows | `Raxol.UI.Components.Display.Table` | Not needed; use `row` with fixed-width `text` columns inside `Widgets.List.ListRow`. |
| #5 Relative time | none | Build `Foglet.TimeAgo` (stdlib only, 30 lines). |
| #6 Theme | `Raxol.UI.Theming.ThemeManager` | **Reject** (GenServer, couples to rejected components). Build `Foglet.TUI.Theme` struct. Raxol's auto-adaptive color downsampling still applies. |
| #7 Title input | `Raxol.UI.Components.Input.TextInput` via DSL `text_input/1` | **Already handled** — existing `new_thread.ex` implements the full flow. Route `ThreadList [C]` to it. |
| #7 Body input | `Raxol.UI.Components.Input.MultiLineInput` state struct | **Use state, not render** — already established pattern at `post_composer.ex:260-286`. |
| #8 Scrollable post body | `Raxol.UI.Components.Display.Viewport` | Candidate if long posts need scroll; defer if not. |
| #8 Modal | existing `Foglet.TUI.Widgets.Modal` | Keep as-is. |
| #9 Too-small gate | none (no Raxol equivalent) | Render-time branch inside `ScreenFrame`. |
| #9 Window-size detection | `{:window_change, w, h}` already normalized in `App.normalize_message/1` | **Already wired**; just read `state.terminal_size`. |
| #10 Key hints | existing `Foglet.TUI.Widgets.KeyBar` | Keep as-is. |

**Principle:** Raxol's **state machinery** (MultiLineInput value/cursor) and **view DSL** (block macros + leaf calls) are adopted. Raxol's **stateful component render pipelines** (`use Component`, `render/2` returning tuple trees) are rejected wholesale because they silently fail to lay out inside block-macro parents.

## Watch Out For (top 5 pitfalls, one-line prevention each)

1. **Legacy DSL drift (silent empty render)** — prevention: only `box do ... end` block form; add every new screen to `test/foglet_bbs/tui/app_test.exs` view-compile smoke test; assert on a rendered string, not just "no raise."
2. **Read-pointer non-monotonic overwrite** — prevention: `on_conflict: [set: [...], where: rp.last_read_message_number < ^message_number]`; add a StreamData property test asserting any advance sequence leaves the pointer at `max(seq)`.
3. **`|| 0` fallback on `last_read_message_number`** — prevention: skip the update when `ctx[:last_read_message_number]` is nil, don't write 0; symmetric with the thread-pointer path at `app.ex:560-564`.
4. **Resize-during-alt-screen flicker and draft loss** — prevention: "too small" is a render-time branch in `ScreenFrame`, not a `current_screen` change; never rebuild `MultiLineInput` state from width on resize; ensure `\e[?1049l` emitted on all three exit paths (graceful quit, EOF, closed-without-EOF).
5. **Composer state-machine trap (extending `PostComposer` with conditional title)** — prevention: do NOT extend PostComposer. `new_thread.ex` already exists and works; route `ThreadList [C]` there with pre-filled board; delete the broken `current_thread: nil → :post_composer` branch at `thread_list.ex:96`.

Secondary but worth planner attention: theme partial application (border un-themed while text is themed), StatusBar placement re-render storms when moved to app level, N+1 query risk on thread-list creator/last-post preload, email-verification toggle retroactive-bypass policy (existing `confirmed_at: nil` users when toggle flips OFF), ANSI escape injection in posts (already handled by `strip_ansi/1` — keep the test).

## Kept Out of Scope

Explicitly flagged by researchers as defer-or-differentiator to prevent scope creep:

- **Actual SMTP email delivery** — SEED-002 flags for Milestone 10 (Swoosh re-enable + digests). Polish scope ends at config-key + resend-cooldown wiring.
- **Raxol `ThemeManager` GenServer + per-user runtime theme switching** — belongs to Milestone 4's "theme stub." Static `Foglet.TUI.Theme` struct is the v1.0.1 surface.
- **`Timex` / `ex_cldr_dates_times`** — explicit new-dep rejection per CLAUDE.md and per scope; custom `Foglet.TimeAgo` instead.
- **Syntax highlighting inside fenced code blocks** — Raxol has `CodeBlock` + Makeup; tempting but adds surface; skip for v1.0.1.
- **OSC-8 clickable hyperlinks** — inconsistent terminal support; safer to render `text (url)` inline.
- **GFM tables inside posts, footnotes, task lists** — rabbit hole inside fixed-width terminal; defer.
- **Live unread-count PubSub refresh while viewing boards** — requires Presence wiring; Milestone 4 territory.
- **Clock / session-time / live user-count in status bar** — render-load and/or PubSub dependency; Milestone 4.
- **Sysop in-TUI toggle screens** — Milestone 8; for v1.0.1 sysop flips `require_email_verification` via Mix task or `Foglet.Config.put!/3`.
- **SEED-001 webhook delivery (any outbound HTTP)** — not in polish scope, not researched here.
- **`posts.body_rendered` column population** — leave NULL; reserve for post-phase-04 optimization.
- **Pre-rendering markdown at post-save** — terminal width varies per session; pinning to one width is wrong everywhere else.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Vendored Raxol source read directly; `mix.exs` / `mix.lock` confirmed; zero-new-deps finding is verified |
| Features | HIGH | Grounded in external TUI conventions (glow, mdcat, k9s, lazygit, btop) + in-repo code read for status-quo analysis |
| Architecture | HIGH | Every integration decision traces to a specific file/line in the codebase; vendored Raxol source verifies component return shapes |
| Pitfalls | HIGH | All 12 pitfalls grounded in this repo's git log, files, or shipped commits; generic TUI advice filtered out |

**Overall confidence:** HIGH.

### Gaps to Address During Planning

1. **Runtime verification of the markdown bug hypothesis** (ARCHITECTURE §2.4, flag 1). Spend 15 minutes in `iex -S mix`: `Foglet.Markdown.render("**bold**\n\nparagraph")`; emit through a `column do [text(s, ...), ...] end` tree; observe. If the bug shape differs (e.g., MDEx output shape drifted, or a seed post contains escaped markdown), adjust P2 scope accordingly.
2. **Seed content audit** (ARCHITECTURE flag 2). Open `priv/repo/seeds*.exs` and eyeball the General seed bodies — valid markdown? Raw control chars? Valid `message_number`? P0 owns this.
3. **`Theme` struct field list is minimal** (ARCHITECTURE flag 3). Six fields sketched; real usage during P2 screen migration may want `fg_muted`, `fg_highlight`, `bg_frame`. Add as needed during migration, not upfront.
4. **Too-small threshold is a guess at 60×20** (ARCHITECTURE flag 4). FEATURES.md argues 80×24 floor for comfortable thread-list density. Pick one: test BoardList at 60×20 at plan time; if it looks decent, ship; otherwise bump to 80×24.
5. **`ScreenFrame` prop shape is sketched, not final** (ARCHITECTURE flag 5). Planners should lock exact prop names before P1 starts so P2 screen migration is mechanical.
6. **Email-verification retroactive-bypass policy** (PITFALLS §9). Explicit decision needed before P6: when sysop flips `require_email_verification = false`, do existing `confirmed_at: nil` users gain access on next login, stay pending, or get batch-confirmed via migration? Document in P6's requirements.

## Sources

### Primary — HIGH confidence (in-repo, verified)

- `vendor/raxol/` — Raxol 2.4.0 source including `ui/components/`, `ui/theming/`, `core/runtime/`, `core/renderer/view.ex`; component return shapes verified
- `lib/foglet_bbs/tui/**` — all 9 screens, 3 widgets, app, markdown module read directly
- `lib/foglet_bbs/{boards,threads,posts}.ex` and `lib/foglet_bbs/boards/read_pointer.ex` — unread-count root-cause analysis
- `lib/foglet_bbs/ssh/cli_handler.ex`, `lib/foglet_bbs/sessions/*.ex` — session + alt-screen lifecycle
- `lib/foglet_bbs/config.ex` — ETS-cached runtime config pattern
- `docs/raxol/getting-started/WIDGET_GALLERY.md`, `docs/raxol/cookbook/{THEMING,BUILDING_APPS,SSH_DEPLOYMENT}.md`
- `mix.exs` + `mix.lock` — dependency inventory; zero-new-deps finding
- `memory/feedback_raxol_modern_dsl.md` — codebase's own post-mortem on DSL discipline
- `.planning/seeds/SEED-002-email-verification-ux.md` — scope item #10 source
- `.planning/workstreams/phase-03-polish/STATE.md` — milestone scope authority
- `.planning/PROJECT.md` — product framing

### Secondary — HIGH confidence (external TUI conventions)

- charmbracelet/glow, swsnr/mdcat, charmbracelet/glamour — terminal markdown rendering conventions
- K9s, lazytui, btop — status-bar-at-top + key-bindings-at-bottom convention
- catamphetamine/relative-time-format — 30s/5m/2h/3d/2w short-form confirmation
- Discourse Meta unread UX discussions — forum unread mental models

### Detailed research files consumed by this summary

- `.planning/workstreams/phase-03-polish/research/STACK.md` (HIGH)
- `.planning/workstreams/phase-03-polish/research/FEATURES.md` (HIGH)
- `.planning/workstreams/phase-03-polish/research/ARCHITECTURE.md` (HIGH)
- `.planning/workstreams/phase-03-polish/research/PITFALLS.md` (HIGH)

---
*Synthesis completed: 2026-04-19. Ready for requirements definition.*
