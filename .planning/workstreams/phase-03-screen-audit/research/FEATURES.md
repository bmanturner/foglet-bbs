# Audit Checks — Per-Screen Rubric

**Domain:** Retrospective audit of 9 Foglet BBS TUI screens (login, register, verify, main_menu, board_list, thread_list, post_reader, post_composer, new_thread)
**Researched:** 2026-04-21
**Confidence:** HIGH (based on direct read of all 9 screen sources + widget library + CLAUDE.md gotchas)

---

## Orientation

This file is the "feature landscape" for the audit workstream. Rather than mapping product features, it enumerates the **checks** that each per-screen phase will execute. Two orthogonal rubrics:

- **Category A — Idiomatic Elixir.** Pass/fail correctness items grounded in CLAUDE.md gotchas, Foglet's existing style, and Elixir community conventions.
- **Category B — Styling Primitive Adoption.** Per-screen candidates for replacing ad-hoc rendering with `Foglet.TUI.Widgets.*` primitives.

Every check is marked **table stakes / differentiator / anti-feature** so the roadmapper can decide per-phase scope.

A **sparseness bias** threads through both categories: this milestone does *not* add vertical/horizontal density to any screen. Upcoming milestones need the whitespace (Phase 4 Presence roster, Phase 5 Chat split, Phase 6 Notification badges, Phase 9 Oneliner shoutbox). Any check that risks filling layout whitespace is flagged as an anti-feature.

Grounded by scanning all 9 screen files — concrete candidates are named by file and line.

---

## Category A — Idiomatic Elixir Audit Checks

### A.1 Table Stakes (must be true after the audit)

| ID | Check | Rationale | How to verify | Grounded candidates |
|----|-------|-----------|---------------|---------------------|
| A-TS-01 | **Every public function (`def`, not `defp`) has a `@spec`** | Already ~universal across the screens; we formalize it so the next 9 screens stay uniform. | `grep -c "@spec" screen.ex` ≥ count of public defs. | All 9 screens already do this for `render/1` and `handle_key/2`; domain-callback pubs (`load_boards/1`, `load_posts/2`, `flush_read_pointers/2`, `handle_wizard_event/2`, `handle_verify_event/2`, `init_screen_state/1`) currently have specs — confirm per-screen. |
| A-TS-02 | **No raw color atoms** (`:red`, `:green`, `:cyan`, `:yellow`, `:blue`, `:magenta`, `:white`, `:black`) in `fg:` / `bg:` positions in screen code | D-07/D-09. All colors must route through `theme.<slot>.fg`. | `grep "fg: :\(red\|green\|...\)\|bg: :\(red\|...\)"` → 0 matches per screen file. | Clean across all 9 screens at time of research (verified). Keep it clean. |
| A-TS-03 | **Theme resolution helper factored, not inlined** | All 9 screens currently inline `theme = (Map.get(state, :session_context) \|\| %{}) \|> Map.get(:theme) \|\| Theme.default()` verbatim. 9 copies of the same 3-expression pipeline is a DRY smell and a maintenance hazard when Theme gains a new argument. | One helper (e.g., `Foglet.TUI.Theme.from_state/1`) called from each screen; grep for inlined pipeline shows 0 matches in `screens/`. | Present in all 9 screens — e.g. `login.ex:36`, `new_thread.ex:80` and `:115` (double-inlined in the same file), `post_reader.ex:34` and `:329`, `post_composer.ex:38`, `verify.ex:41`, `register.ex:30`, `main_menu.ex:18`, `board_list.ex:18`, `thread_list.ex:20`. |
| A-TS-04 | **No struct Access abuse** — `%{struct \| field: x}` or `struct.field`, never `struct[:field]` | CLAUDE.md gotcha: "Structs don't implement `Access`." | `grep "struct_var\[:"` on every typed struct (User, Thread, Post, MultiLineInput, Theme). | No offenders found at research time — keep a dialyzer-level check. |
| A-TS-05 | **Block-expression rebinding correctness** — no `socket = assign(…)` / `state = %{…}` assignments *inside* `if`/`case`/`cond` blocks | CLAUDE.md explicit gotcha. Silently loses the rebind. | Manual review of every `if`/`case`/`cond` body (there's ~50 across the 9 files); flagged as an audit checklist item not a grep. | No offenders at research time; verify post-edit. |
| A-TS-06 | **Pattern-matching on function head where the shape is stable** instead of inline `case`/`cond` | Elixir idiom. Current code is mostly good — e.g., `thread_handle/1`, `thread_time_segment/1`, `display_value/2` in `register.ex`. A few `cond do` blocks in `verify.ex` (line 100–111, 180–221) and `new_thread.ex` (line 343–353) could become multi-clause heads. | Manual review; flag any screen whose `handle_key/2` or render helpers use `case` / `cond` where the branch condition is a shape of the input (not a computation). | `verify.ex:100-111` (cond on cooldown + regex + buffer length); `verify.ex:180-221` (cond with three branches) — **evaluate per-phase whether refactor improves or hurts readability**. Some `cond` is fine. |
| A-TS-07 | **`|>` pipelines for 2+ sequential transforms, not nested calls** | Elixir idiom. Screens are mostly OK; watch for sneaky nesting in newly added audit code. | Visual review — flag any `Enum.map(Enum.sort(x, …), …)` or similar 2-deep nests. | None significant at research time. |
| A-TS-08 | **`with` for happy-path chains where every step returns `{:ok, _} \| {:error, _}`** | Avoids the "nested case" anti-pattern. Screens use nested `case` in `login.ex:267-293` (authenticate → status check → post_login_screen), `register.ex:236-281` (register_user → post_login_screen → build_verify_code), `post_composer.ex:252-306` (submit pipeline). | Flag any nested `case` with 3+ levels of `{:ok,_} \| {:error,_}` that could be `with`. | **`login.ex:267-308`, `register.ex:232-280`, `post_composer.ex:252-306`** are the three concrete offenders. Each is a `with` candidate. |
| A-TS-09 | **No `apply/3` for known-at-compile-time MFAs** | `apply/3` disables Dialyzer contract checks and hides typos from the compiler. | `grep "apply(.*,"` → 0 matches unless explicitly credo-silenced with a rationale comment. | **`register.ex:200`** uses `apply(Foglet.Accounts, :consume_invite_code, [code])` with a credo-silence. It's there to work around the not-yet-defined function — keep the silence but re-evaluate once Phase 8 (Milestone 8 Sysop admin) lands invite codes. |
| A-TS-10 | **`function_exported?/3` guards `Code.ensure_loaded/1` first** | Without `ensure_loaded/1`, `function_exported?/3` returns false for unloaded modules — a silent sandtrap. | Grep every `function_exported?` call and confirm an `ensure_loaded` precedes it OR it's on a known-loaded stdlib module. | **`post_reader.ex:292` (`Code.ensure_loaded(markdown_mod)` then `function_exported?`)** is correct. **`thread_list.ex:136,140` (`function_exported?(threads_mod, :list_threads, 2)`)** does NOT `ensure_loaded/1` first — candidate fix. **`register.ex:196` (`function_exported?(Foglet.Accounts, :consume_invite_code, 1)`)** is on a compile-time-linked module so likely fine but verify. |
| A-TS-11 | **Public function `@doc` strings for any public beyond `render/1` + `handle_key/2`** | Screens differ: `post_reader.ex` doc-strings `load_posts/2` and `flush_read_pointers/2`; `board_list.ex` docs `load_boards/1`; `thread_list.ex` docs `load_threads/2`; others (`register.ex:handle_wizard_event/2`, `verify.ex:handle_verify_event/2`, `new_thread.ex:init_screen_state/1`, `post_composer.ex:init_screen_state/1`) already have them. | Confirm each public has `@doc`. | Mostly compliant — `main_menu.ex` has only `render/1` + `handle_key/2`, no other publics, so trivially compliant. |
| A-TS-12 | **`@moduledoc` present on every screen and accurate** | Every screen has one already; audit confirms the moduledoc still matches the code (drift detection). | Visual read — moduledoc examples and line refs should resolve. | `post_reader.ex` moduledoc references pre-Phase-7 shape (mentions replacement, valid context). `post_composer.ex` moduledoc still accurate. Audit confirms, doesn't rewrite unless drifted. |
| A-TS-13 | **No nested modules in a single file** | CLAUDE.md explicit gotcha. | `grep -c "defmodule" screen.ex` == 1 per file. | All 9 screen files are single-module (verified by read). |
| A-TS-14 | **No `String.to_atom/1` on untrusted input** | Precommit (credo/sobelow) catches this, but we confirm zero call sites in screens. | `grep "String.to_atom"` → 0 matches in `screens/`. | None found. |
| A-TS-15 | **`@default_*` module constants for per-screen magic numbers** | D-08 convention — follows what widgets already do. | Any literal integer/string used 2+ times in a file is a `@default_` candidate. | **`verify.ex`** does this well (`@max_attempts 5`, `@cooldown_seconds 60`, `@code_length 6`). **`new_thread.ex:422` `@default_max_thread_title_length 60`**. **`post_composer.ex:27` `@default_max_post_length 8192`**. Not all screens need constants — only flag where a literal repeats. |
| A-TS-16 | **Defensive `|| %{}` / `|| []` chains collapsed behind a default-struct helper where repeated 3+ times** | `verify.ex` shows the pattern — `state.verify_state || %{buffer: "", attempts: 0, cooldown_until: nil, resend_cooldown_until: nil}` appears at **lines 38, 76, 94, 123, 177, 224, 252**: 7 copies of the same default map. | Extract one `default_verify_state/0` helper. | **`verify.ex` is the clearest offender** — 7 occurrences of the same default map. **`post_reader.ex`** already has `default_screen_state/0` (line 241) and `get_screen_state/1` (line 262) — good model. **`login.ex`** has `%{handle: "", password: "", error: nil}` at lines 101, 113, 129, 184, 231 — candidate. **`new_thread.ex`** defaults are centralized in `init_screen_state/1` — good. |
| A-TS-17 | **Terminal-size fallback uses a single module-constant default** | Every screen has `{w, h} = state.terminal_size || {80, 24}` scattered through it. `{80, 24}` is effectively a hardcoded safety net that should be one named constant — possibly on `Foglet.TUI.SizeGate` or a new `Foglet.TUI.Constants` — so bumping it for testing is a one-line change. | `grep "{80, 24}"` in `screens/` should find it at ≤ 1 named module attribute per screen, not inline literals. | `main_menu.ex:41`, `thread_list.ex:40, 103`, `post_reader.ex:35, 117, 164, 352, 391`, `post_composer.ex:55, 117, 157`, `new_thread.ex:214, 176`. Count: 13+ inline occurrences. |
| A-TS-18 | **Domain-module resolution factored, not inlined** | Similar DRY issue to A-TS-03. The pattern `ctx = Map.get(state, :session_context) \|\| %{}; mod = get_in(ctx, [:domain, :<key>]) \|\| <Default>` is repeated across `board_list.ex:111-114`, `thread_list.ex:131-132`, `post_reader.ex:160-161, 199-201, 285-287`, `post_composer.ex:285-286`, `new_thread.ex:410-413`. | One helper (e.g., `Foglet.TUI.SessionContext.domain(state, :posts)`) used everywhere. | Seven copies of the same three-expression resolution — prime consolidation candidate. |
| A-TS-19 | **No `send/2` or process spawning in render/handler code paths** | Renders and handlers are pure — side effects go through `{:update, state, [commands]}`. | Grep for `send(`, `spawn(`, `Task.start` in `screens/` → 0. | Clean. |
| A-TS-20 | **`credo --strict` clean, `dialyzer` clean, `sobelow` clean** (via `mix precommit`) | Precommit catches the rest. | `mix precommit` exits 0. | Known to be green on HEAD (CI baseline). Per-phase must maintain. |
| A-TS-21 | **`{:update, state, commands}` tuple shape consistently used for handlers that mutate** | Every screen uses this shape; no drift to direct returns or `{:noreply, state}`-style. | Visual review of every `handle_key/2` clause. | Compliant. |
| A-TS-22 | **Screen state accessed via nil-safe `get_in/2` or `Map.get/3`, never bare field access on a possibly-nil key** | `get_in(state.screen_state, [:post_reader])` is the well-established shape. | Grep for bare `state.screen_state.some_key` which would crash on nil. | Compliant across all 9. |

### A.2 Differentiators (stretch — do if phase has room)

| ID | Check | Rationale | Grounded candidate |
|----|-------|-----------|---------------------|
| A-D-01 | **Replace `Application.compile_env/3` guards with `case`-dispatch or `@compile_env` module attribute pattern** | `login.ex:30` and `register.ex:25` both use a `@log_verify_codes Application.compile_env(…)` + `if @log_verify_codes do … else …` construct. Works, but the two `defp maybe_log_verify_code/2` clauses under the same `if` block are duplicated between the two screens. Candidate: extract `Foglet.Accounts.VerifyLogger.log/2`. | `login.ex:339-346`, `register.ex:286-293` — 8 lines duplicated verbatim. |
| A-D-02 | **Replace `cond do` chains with multi-clause function heads where branches pattern-match on state shape** | `verify.ex:100-111` (cond over cooldown / regex / length) could be 3 `defp try_append/2` clauses. Only worth it if readability improves. | `verify.ex:100-111, 180-221`. Case-by-case judgment — some `cond` reads better than many small clauses. |
| A-D-03 | **Collapse `screen_state` navigation into a single path-indexed helper per screen** | E.g., `login_ss(state)` / `put_login_ss(state, ss)` — already present in `login.ex:154-161`. **Every screen should have this pair**. | `thread_list.ex` and `board_list.ex` use `get_in/2` inline — could centralize. |
| A-D-04 | **Type specs on private functions that take/return non-trivial structures** | Not required; helps Dialyzer coverage. Highest ROI on submit/advance pipelines. | `register.ex:advance/4`, `post_composer.ex:submit_reply/4`, `new_thread.ex:do_create_thread/5`. |
| A-D-05 | **`@typedoc` + `@type` for the "screen state shape" map** | E.g., `@type login_state :: %{sub: :menu \| :login_form, form: form_t, focused_field: :handle \| :password}`. Surfaces the contract in docs and Dialyzer. | `login.ex`, `verify.ex`, `new_thread.ex`, `post_composer.ex`, `post_reader.ex` all have complex screen-state maps. |
| A-D-06 | **Extract the 5+ line "warm cache then viewport, then possibly clamp" blocks in `post_reader.ex` into named private helpers that read left-to-right** | `post_reader.ex:advance_post/2` and `scroll_post/2` have parallel warm/viewport/scroll sequences. | Lines 339–409. |

### A.3 Anti-Features (explicitly NOT in scope for this audit)

| ID | Anti-check | Why excluded | What to do instead |
|----|------------|--------------|---------------------|
| A-ANTI-01 | **New functionality of any kind** — adding a new key binding, new screen state, new domain call | This is an audit, not a feature phase. Stay on the current behavior contract. | Flag in a "follow-up" note in each phase's SUMMARY.md. |
| A-ANTI-02 | **Merging `PostComposer` + `NewThread` into one mode-switched screen** | Explicitly deferred in `Compose.@moduledoc` (D-12). | Leave them separate. |
| A-ANTI-03 | **Refactoring `App.update/2`, `SessionContext`, or any non-screen file** | Out of the audit scope — each phase is bound to one screen. | If an audit surfaces an App-level problem, record it in SUMMARY.md for a post-workstream cleanup. |
| A-ANTI-04 | **Replacing `Map.get(… || %{})` ceremony with `Access` behaviour or `Kernel.get_in/2` on structs** | CLAUDE.md gotcha — structs don't implement Access. Don't refactor toward a footgun. | Keep `Map.get/3` or pattern-match destructuring. |
| A-ANTI-05 | **Adding dialyzer ignores or credo silences to make a "clean" result** | Silencing is not cleaning. | If a dialyzer warning fires, fix it or leave the warning with a `@credo-disable` rationale. |
| A-ANTI-06 | **Expanding `@moduledoc` with tutorial-style prose** | Moduledoc should be terse and locate the file in the architecture. | Keep what's there unless drift detected (A-TS-12). |
| A-ANTI-07 | **Adding `Logger` calls for auditability** | Not a feature of the audit. Phase 11 (Observability) owns telemetry. | Leave logging alone. |
| A-ANTI-08 | **Extracting helpers that are used in only one place** | Premature DRY. Wait for the third copy. | Only extract after 3+ duplicates (A-TS-03, A-TS-16, A-TS-17, A-TS-18 all pass this bar). |

---

## Category B — Styling Primitive Adoption Checks

Reference: `lib/foglet_bbs/tui/widgets/README.md`. Primitives in scope: `Input.TextInput`, `Input.Button`, `Input.Checkbox`, `Input.RadioGroup`, `Input.Tabs`, `Input.Menu`, `Display.Table`, `Display.Tree`, `Display.Progress`, `Progress.Spinner`, `List.SmartList`, `List.SelectionList`, `List.ListRow`, `Post.PostCard`, `Post.MarkdownBody`, `Compose`, `Modal`, `Chrome.ScreenFrame`, `Chrome.StatusBar`, `Chrome.KeyBar`.

### B.1 Table Stakes (every screen must pass)

| ID | Check | Rationale | How to verify | Grounded candidates |
|----|-------|-----------|---------------|---------------------|
| B-TS-01 | **`ScreenFrame.render/4` wraps every screen** | FRAME-01. Consistent chrome. | Every screen's `render/1` top-level returns `ScreenFrame.render(state, title, content, keys)`. | Compliant across all 9. Confirm per-phase. |
| B-TS-02 | **`StatusBar` and `KeyBar` are applied *only* via `ScreenFrame`** — no direct calls from screens | Chrome composition is locked (D-05, D-06). | Grep `screens/` for `StatusBar.render\|KeyBar.render` → 0 matches. | Compliant. |
| B-TS-03 | **All errors/info/warnings raised from a screen use the `state.modal` map + `Modal.render/2` contract** | D-20. Unifies overlay styling. | Grep `screens/` for inline error-overlay rendering → 0 matches; every `modal:` assignment uses the `%{type:, message:, …}` shape. | **Compliant** — e.g., `login.ex:272-282`, `register.ex:150-154, 216-224, 259-264`, `verify.ex:97-110, 167-168, 171-172, 184-186, 194-218`, `post_composer.ex:259, 262-267, 278, 304`, `new_thread.ex:388-392`. All use the `%{type: …, message: …}` shape. |
| B-TS-04 | **Single-line text inputs use `Input.TextInput`** (or a documented exception) | Every screen currently hand-rolls input: `login.ex:render_login_form/2` and `register.ex:render/1` both format input lines with `text(…)` and a cursor glyph. | Target: each password/handle/email/code/invite-code field is an `Input.TextInput`. | **Candidates:** **`login.ex:196-210`** (handle + password fields — the whole "format_input_line + focus_style + mask_password" block is re-creating `Input.TextInput`); **`register.ex:39-49`** (single input line with cursor glyph); **`verify.ex:52-58`** (6-char code field — arguably custom enough to stay hand-rolled, but worth evaluating with `Input.TextInput` + `max_length: 6` + uppercase validator). **`new_thread.ex:124-128`** (title input — another hand-rolled input block). **`post_composer.ex` and `new_thread.ex` body fields** correctly use `MultiLineInput` via the `Compose` shim — no change. |
| B-TS-05 | **No raw ANSI escape codes or manual cursor drawing** | Every screen currently uses a `█` block glyph as a cursor (`login.ex:217`, `register.ex:45`, `verify.ex:145`, `new_thread.ex:125`, `post_composer.ex` via `Compose`). If `Input.TextInput` owns cursor rendering, pass it through. | Grep for `"█"` unicode glyph in `screens/` → 0 matches (after adoption). | 5 screens do this by hand. |
| B-TS-06 | **List-type selections (boards, threads) use `SelectionList.render/3` + `ListRow.render/3` or `ListRow.render_with_metadata/6`** | LIST-03, LIST-04 contracts. | Grep `screens/` for raw `Enum.with_index() \|> Enum.map` rendering of lists with manual selection glyphs → 0 matches. | **Compliant** — `board_list.ex:42-47`, `thread_list.ex:48-52`, `new_thread.ex:99-103` all use `SelectionList` + `ListRow`. No additional adoption opportunities here. |
| B-TS-07 | **Post content uses `Post.PostCard` + `Post.MarkdownBody`** | RENDER-01/02 contract. | Grep `screens/` for inline markdown rendering → 0 matches. | **Compliant** — `post_reader.ex:74, 82` uses PostCard; `post_composer.ex:57`, `new_thread.ex:178` both use `MarkdownBody.render/3` for preview. |
| B-TS-08 | **KeyBar entries are the *only* place where `[K] Desc` pairs appear** — no redundant in-content menu hints | The login and main_menu screens currently render `[L] Login`, `[R] Register`, etc. as in-content menu items **in addition to** the KeyBar showing the same keys. Visually redundant and eats vertical space that Phase 4 Presence needs. | Review: the KeyBar should carry the key hints; in-content menu items should either be removed or restyled as a titled list (e.g., SelectionList) that the user moves through with j/k. | **`login.ex:169-177` render_menu** (3 text lines for L/R/Q), **`main_menu.ex:20-26`** (3 text lines for B/C/Q). **Both duplicate the KeyBar** (`login.ex:167`, `main_menu.ex:28-32`). Phase decision per screen: remove in-content list, rely on KeyBar; OR convert to a SelectionList. **Sparseness bias = removing wins.** |
| B-TS-09 | **Theme colors routed via slot access** — no inline hex strings, no `:red`-style atoms in screen files | D-07/D-09. A.2 covers the atom case; this check covers inlined hex. | Grep `screens/` for `#[0-9a-fA-F]\{6\}` → 0 matches. | **None found** at research time. Clean. |
| B-TS-10 | **Section headings within a screen use theme slots consistently**: `title.fg` for titles, `primary.fg` for body, `dim.fg` for metadata, `accent.fg` for focus, `error.fg` for errors, `warning.fg` for empty states | Already ~uniform. Audit verifies per screen. | Visual review of every `text(…, fg:)` call in each screen file. | Mostly compliant; edge cases (e.g., `new_thread.ex:87` uses `dim.fg` for "Loading boards…" — could be `primary.fg`; `board_list.ex:30` uses `warning.fg` for "No boards subscribed" — appropriate). Judge per phase. |
| B-TS-11 | **Modal `:confirm` type used for any destructive or irreversible action** — not raw `:info` / `:error` | D-20 contract. | No destructive actions in current 9 screens. | **N/A for v1.0.2** — but codify the check for when Moderation lands. |

### B.2 Differentiators (stretch — do if phase has room and the primitive genuinely fits)

| ID | Check | Rationale | Grounded candidate |
|----|-------|-----------|---------------------|
| B-D-01 | **Buttons for affordances like "Send", "Cancel", "Next" where they're currently bracketed text labels** | `Input.Button` exists but is unused in screens. | **Not recommended for most screens** — the BBS idiom is key-bar-driven, not click-driven. Button could be useful in `modal` OK/Cancel bodies (future). **Defer unless a screen has a genuine click affordance.** **Anti-pattern candidate if forced.** |
| B-D-02 | **Use `SmartList` instead of `SelectionList` when pagination or search becomes useful** | `SmartList` is `D-02 / Phase 8`. Today 9 screens have 0–20 items per list — `SelectionList` is the right tool. | **Defer** — revisit when a board has >50 threads or >50 subscribed boards. |
| B-D-03 | **Use `Display.Table` for tabular data** | Table-like data candidates: thread metadata row (`@handle · N posts · Xh ago`) **already laid out as a single right-aligned line** via `ListRow.render_with_metadata/6`. True tables would require adding columns (sender, post count, time, unread) — **contradicts sparseness**. | **Anti-feature candidate** — do not turn `ThreadList` into a Table; the single-line metadata is sufficient and saves whitespace. |
| B-D-04 | **Use `Progress.Spinner` for `"Loading boards…"` / `"Loading posts…"` / `"Loading threads…"` placeholders** | Visual feedback. Current screens use static text: `board_list.ex:39`, `thread_list.ex:45`, `post_reader.ex:93`, `new_thread.ex:85`. | **Candidate**, but sparseness-constrained — a spinner adds a character animation but does not move the text into a new line, so it's safe. Only adopt if per-phase feedback latency makes the static text feel stuck. |
| B-D-05 | **Use `Display.Progress` bar for cooldown timers** | `verify.ex` has `cooldown_until` / `resend_cooldown_until` DateTimes. A progress bar showing "time remaining" could replace the current "Too many attempts. Please wait." text. | **Defer** — the current error text is sufficient and saves vertical space. `Progress` bar would add 1 line. Re-evaluate after Phase 4 lands. |
| B-D-06 | **Use `Input.Tabs` to toggle between `:edit` and `:preview` modes in composer screens** | `post_composer.ex:82` and `new_thread.ex:261-269` both toggle with Tab. `Input.Tabs` would visually display both modes. | **Marginal candidate** — `Input.Tabs` would take a whole row of chrome and add zero functionality over the current KeyBar hint. **Recommend: defer.** |
| B-D-07 | **Use `Input.Checkbox` / `Input.RadioGroup` for wizard mode selection** | `register.ex` wizard has mode awareness but no mode *selection* UI — mode is set from config. | **N/A** — no current use case. |
| B-D-08 | **Extract the "title field" in `new_thread.ex` into its own tiny widget** (`Input.TextInput` wrapped in a labeled row) | Currently `new_thread.ex:123-130` hand-rolls the title field. If `Input.TextInput` gets adopted (B-TS-04), this collapses naturally. | Grouped with B-TS-04. |

### B.3 Anti-Features (explicitly NOT in scope)

| ID | Anti-check | Why excluded | What to do instead |
|----|------------|--------------|---------------------|
| B-ANTI-01 | **Adding "nice" layout density** — banners, ASCII art, logos, header decorations | **Sparseness bias.** Phase 4 Presence needs the top-of-screen real estate that would otherwise go to decoration. | Leave empty space above the content. |
| B-ANTI-02 | **Multi-column layouts** (two-pane split, sidebars) | Phase 5 Chat has a roster/message split layout already designed. Pre-building split-pane into, e.g., board_list, would conflict. | Keep single-column screens. |
| B-ANTI-03 | **Boxed / bordered content blocks within a screen** | The outer `ScreenFrame` is the only border. Inner boxes add horizontal padding that eats content width and looks cluttered at 80-cell minimum terminal. | Use `divider/1` or `gap: 1` for separation. |
| B-ANTI-04 | **Replacing key-driven navigation with mouse/click-driven buttons** | BBS idiom is keyboard-first. Go CLI client (Milestone 13) and Phoenix Channels port are both keyboard-first. | Leave key bindings as primary; keep `Input.Button` usage minimal. |
| B-ANTI-05 | **Adding `Progress` bars for every async operation** | Most operations are sub-100ms in dev; a progress bar for a disk-cached DB query is visual clutter. | Add only where latency is user-visible (B-D-04). |
| B-ANTI-06 | **Using `Display.Tree` in `BoardList` for category grouping** | There are currently 0 nested categories in the domain model. Adopting Tree pre-emptively locks us into hierarchy when future categorization (Milestone 8 Sysop admin) might pick a different shape. | Defer until Milestone 2's `categories` schema lands and is populated. |
| B-ANTI-07 | **Replacing `SelectionList` with `SmartList` for the existing lists** | SmartList adds search + pagination + multi-select — none needed at 9-screen scale. Adds state-management complexity. | Stay with SelectionList. Revisit per B-D-02 trigger. |
| B-ANTI-08 | **Adding `Input.Menu` (dropdown) anywhere** | No current use case. Horizontal menu bars don't fit BBS aesthetic. | Defer indefinitely. |
| B-ANTI-09 | **Adding `Display.StatusBar` (the Raxol one, different from our `Chrome.StatusBar`) for multi-field status** | We own `Chrome.StatusBar` with a fixed 2-field layout (title + handle). Phase 4 Presence may extend with online count; that's a Chrome.StatusBar internal change, not a swap to the Raxol primitive. | Leave Chrome.StatusBar as the sole status bar widget. |
| B-ANTI-10 | **Making `ScreenFrame` configurable per-screen (different borders, paddings)** | Consistency is the point of FRAME-01. Breaking it makes every screen look "hand-crafted" which fights the uniform BBS feel. | Leave ScreenFrame's border/padding locked at `{border: :single, padding: 1}`. |

---

## Per-Screen Candidate Summary

Grounded per-screen checks derived from Categories A + B above. The roadmapper will use this to scope each phase.

| Screen | Lines | A-TS checks flagged | B-TS checks flagged | Differentiator opportunities |
|--------|------:|---------------------|---------------------|------------------------------|
| `login.ex` | 347 | A-TS-03 (inlined theme), A-TS-08 (nested case in `submit_login`), A-TS-16 (default form map ×5) | **B-TS-04** (handle + password hand-rolled → `Input.TextInput` ×2), **B-TS-05** (`█` cursor), **B-TS-08** (in-content menu duplicates KeyBar) | A-D-01 (share VerifyLogger with register), A-D-03 (login_ss helper already good — model for others), B-D-04 (spinner on "authenticating…") |
| `register.ex` | 294 | A-TS-03, **A-TS-08 (nested case in `submit/2`)**, A-TS-09 (apply/3 — justified), A-TS-18 (domain module pattern) | **B-TS-04** (single hand-rolled input), **B-TS-05** (`█` cursor) | A-D-01 (share VerifyLogger with login), A-D-05 (type the wizard step atom) |
| `verify.ex` | 271 | A-TS-03, **A-TS-16 (default verify_state map ×7 — top priority)**, A-TS-08 (nested case in `submit_raw/1`) | **B-TS-04** (6-char code field — evaluate), B-D-04 (spinner on resend), B-D-05 (progress bar on cooldown — defer per B.2) | A-D-02 (cond → multi-clause) |
| `main_menu.ex` | 58 | A-TS-03 | **B-TS-08** (in-content menu duplicates KeyBar) | None — this screen is already minimal. Don't over-audit. |
| `board_list.ex` | 115 | A-TS-03, A-TS-17 (terminal size default), A-TS-18 (domain module) | — fully compliant | B-D-04 (spinner on "Loading…") |
| `thread_list.ex` | 196 | A-TS-03, **A-TS-10** (function_exported? without ensure_loaded), A-TS-17, A-TS-18 | — fully compliant | A-D-03 (centralize screen_state path), B-D-04 (spinner on "Loading…") |
| `post_reader.ex` | 425 | A-TS-03 (×2 inlined — lines 34 and 329), A-TS-17 (×5), A-TS-18 (×3) | — fully compliant | A-D-06 (extract warm-cache/warm-viewport sequences), A-D-04 (specs on private helpers), B-D-04 (spinner on load) |
| `post_composer.ex` | 361 | A-TS-03, **A-TS-08 (nested case in `submit_reply/4`)**, A-TS-15 (good already), A-TS-17, A-TS-18 | — fully compliant (uses Compose widget correctly) | B-D-06 (Tabs for edit/preview — defer per B.2) |
| `new_thread.ex` | 435 | A-TS-03 (×2 inlined — lines 80 and 115), A-TS-08 (nested case in `do_create_thread/5`), A-TS-15 (good already), A-TS-17 | **B-TS-04** (title hand-rolled input), **B-TS-05** (`█` cursor on title), B-TS-10 (Loading text color) | B-D-06 (Tabs for edit/preview — defer) |

---

## Cross-Cutting Checks (not per-screen)

These fire across the audit as a whole, not per phase.

| ID | Check | Rationale | How to verify |
|----|-------|-----------|---------------|
| X-01 | **After all 9 phases, `grep -c "(Map.get(state, :session_context) || %{}) |> Map.get(:theme)"` in `screens/` returns 0** (per A-TS-03) | Consolidation is the payoff. | Single command, run at the end. |
| X-02 | **After all 9 phases, no screen file has more than one `default_*_state/0`-style helper AND a duplicated default map literal** (per A-TS-16) | Same payoff, per-screen scope. | Per-screen grep. |
| X-03 | **After all 9 phases, zero inlined `{80, 24}` literals in `screens/`** (per A-TS-17) | Centralize in `Foglet.TUI.Constants` (new module, if warranted) or on `SizeGate`. | Single grep. |
| X-04 | **After all 9 phases, zero `get_in(ctx, [:domain, :<module>])` literals in `screens/`** (per A-TS-18) | Consolidation helper lives in `Foglet.TUI.SessionContext`. | Single grep. |
| X-05 | **Test coverage unchanged or higher** — no test deletions during the audit | Audit should not reduce the safety net. | `mix test --cover` before/after. |
| X-06 | **`mix precommit` green on every phase branch before merge** | CI gate. | CI check. |
| X-07 | **No screen visually changed beyond what the audit goals require** — no cosmetic drift | Run the app before/after on each phase and confirm layouts are equivalent. A manual gate. | Manual SSH-in per phase. |

---

## Check Dependencies

```
A-TS-03 (inlined theme helper)
    └──resolves──> X-01 (cross-cutting count = 0)

A-TS-16 (default-state maps)
    └──resolves──> X-02

A-TS-17 (terminal-size literal)
    └──resolves──> X-03

A-TS-18 (domain module pattern)
    └──resolves──> X-04

B-TS-04 (Input.TextInput adoption)
    └──requires──> Input.TextInput covers all cases (password mask, custom validator, handle length cap)
    └──enables──> B-TS-05 (no more manual cursor)

B-TS-08 (KeyBar dedupe)
    └──trigger for──> sparseness bias check per phase
```

---

## Per-Phase Audit Rubric (extract for roadmap)

Every phase should run, in order:

1. **Read the screen file top-to-bottom** once, annotate against Categories A and B table-stakes items.
2. **Produce a candidate list** — each A-TS and B-TS flagged, with line references and proposed change.
3. **Confirm no anti-feature creeps** (A.3, B.3).
4. **Apply changes** one at a time, running `mix test test/foglet_bbs/tui/screens/<screen>_test.exs` after each.
5. **Visual smoke test** — SSH in with the default theme, navigate to the screen, compare against pre-audit screenshot.
6. **Run `mix precommit`** — must be green (A-TS-20, X-06).
7. **Commit with a single commit per phase** — the per-screen phase == one reviewable diff.

---

## Sources

- **Foglet code:** every file under `lib/foglet_bbs/tui/screens/`, `lib/foglet_bbs/tui/widgets/` (read in full).
- **Theme:** `lib/foglet_bbs/tui/theme.ex`.
- **Widget index:** `lib/foglet_bbs/tui/widgets/README.md`.
- **CLAUDE.md gotchas:** project root + user global.
- **Raxol primitives:** `docs/raxol/getting-started/WIDGET_GALLERY.md`.
- **Phase 8 widget-library contract:** `.planning/workstreams/phase-03-polish/phases/08-build-local-widget-library-from-raxol-primitives/08-VALIDATION.md` (D-18 bar for widget tests — the standard this audit is applying to screens).
- **Workstream context:** `.planning/workstreams/phase-03-screen-audit/STATE.md`.
- **Main roadmap:** `.planning/PROJECT.md` (upcoming Milestones 4-9 that drive the sparseness bias).

---

*Researched: 2026-04-21 — Confidence: HIGH. All concrete candidates grounded in file:line references from a first-hand read of the 9 screens plus supporting widgets and theme.*
