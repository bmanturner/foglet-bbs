# Technology Stack — v1.4 Post-Facelift Polish & Bug Fixes

**Project:** Foglet BBS
**Milestone:** v1.4 Post-Facelift Polish & Bug Fixes
**Researched:** 2026-04-26
**Mode:** Project research, brownfield, bug-fix milestone (subsequent)
**Overall recommendation:** **Add zero new dependencies.** All ~37 issues
in `ISSUES.md` are fixable inside existing TUI/widget/screen code, with one
small SSH-side terminal-protocol addition (bracketed-paste).

## TL;DR

| Area | Verdict | Why |
|------|---------|-----|
| Form-widget paste over SSH | **No new dep — implement bracketed-paste in CLIHandler** | OS clipboard helpers can't reach the SSH client; the standards-based fix is `DECSET 2004` plus `ESC[200~…ESC[201~` unwrap, which is a code change, not a library |
| Terminal table column widths | **No new dep — fix `Foglet.TUI.Widgets.Display.Table` to use `column_widths: :auto`** | Raxol's `Display.Table` already supports auto-allocation; the local facade is currently passing per-column literals and not wiring it through |
| IANA timezone enumeration | **No new dep — use `Tzdata.zone_list/0`** | `tzdata 1.1.3` is already a transitive dep via `timex`; `Timex.Timezone.exists?/1` already validates |
| Markdown paragraph/line breaks | **No new dep — pass `[render: [hardbreaks: true]]` to MDEx** | `mdex ~> 0.2` already supports comrak's `hardbreaks` render option |
| Editor word wrap | **No new dep — set `wrap: :word` on `MultiLineInput`** | Raxol's `MultiLineInput` ships with `:word`/`:char`/`:none` wrapping; Foglet currently configures it `wrap: :none` |
| Bracketed-paste handling | **No new dep — ~80 LOC in CLIHandler + Input pipeline** | Pure ANSI protocol: emit on PTY up, strip the markers in `IOAdapter.parse_input`, expose a `:paste` event |

The default answer for v1.4 is *fix in existing TUI/widget code*. The
roadmap should not budget a "stack work" phase.

## Existing Stack (do not re-research)

These are all locked by `mix.exs` + `.tool-versions` and validated through
v1.3:

### Runtime / Framework

| Item | Version | Source |
|------|---------|--------|
| Elixir | `1.19.5` | `.tool-versions` |
| Erlang/OTP | `28.3.1` | `.tool-versions` |
| Phoenix | `~> 1.8.5` | `mix.exs` |
| Ecto | `~> 3.13` (`ecto_sql`) | `mix.exs` |
| Postgrex | `>= 0.0.0` | `mix.exs` |
| Bandit | `~> 1.5` | `mix.exs` |

### TUI / Terminal

| Item | Version | Source |
|------|---------|--------|
| Raxol | vendored at `vendor/raxol` | `mix.exs` |
| `:ssh` (Erlang built-in) | OTP 28.3.1 | runtime |
| `Foglet.TUI.TextWidth` | local helper | v1.3 Phase 16 |
| `Foglet.TUI.Theme` | local | existing |
| `Foglet.TUI.Widgets.Input.TextInput` | local facade over `Raxol.UI.Components.Input.TextInput` | existing |
| `Foglet.TUI.Widgets.Display.Table` | local facade over `Raxol.UI.Components.Table` | existing |
| `Foglet.TUI.Widgets.Composer.EditorFrame` | local stateless shell | v1.3 Phase 23 |
| `Foglet.TUI.Widgets.Post.MarkdownBody` | local renderer | existing |

### Domain / Auth / Markdown / Time

| Item | Version | Source |
|------|---------|--------|
| `argon2_elixir` | `~> 4.0` | `mix.exs` |
| `bodyguard` | `~> 2.4` | `mix.exs` |
| `mdex` (CommonMark/GFM via comrak) | `~> 0.2` | `mix.exs` |
| `oban` | `~> 2.18` | `mix.exs` |
| `hammer` | `~> 7.3.0` | `mix.exs` |
| `timex` | `~> 3.7` | `mix.exs` |
| `tzdata` (transitive via Timex) | `1.1.3` | `mix.lock` |
| `swoosh` + `gen_smtp` | `~> 1.25` / `~> 1.3` | `mix.exs` |

Everything required for v1.4 is already on the BEAM in this project.

## v1.4 Recommendations

### Keep (no change)

- **Phoenix / Ecto / Bandit / Postgrex** — milestone is TUI bug-fix; no
  endpoint, persistence, or HTTP server changes.
- **Raxol (vendored)** — already provides `MultiLineInput` (with `:word`
  wrap), `Display.Table` (with `column_widths: :auto`, sortable,
  filterable), `Display.Tree` (expand/collapse), `MarkdownRenderer`,
  `Modal`, `Tabs`, etc. The bugs are integration/configuration in Foglet
  code, not Raxol gaps.
- **MDEx 0.2** — supports `hardbreaks`, `extension`, `parse`, `render`,
  and `syntax_highlight` option groups via comrak. Sufficient for the
  Globally #2 markdown line-break bug.
- **Timex 3.7 + Tzdata 1.1.3** — sufficient for IANA timezone
  enumeration (`Tzdata.zone_list/0` returns the canonical name list) and
  validation (`Timex.Timezone.exists?/1` already used in
  `Foglet.Accounts.User.default_timezone/0`).
- **Argon2 / Hammer / Bodyguard / Oban / Swoosh / gen_smtp** — none
  participate in the bug list.
- **Bandit 1.5 / DnsCluster 0.2 / Telemetry / DialyXir / Credo /
  Sobelow / StreamData / Dotenvy** — orthogonal to v1.4.

### Add

**No new runtime dependencies are warranted for v1.4.**

I considered five candidates and rejected each:

| Candidate | Rejected because |
|-----------|------------------|
| `nimble_csv` / `csv` for table layout | Not a layout library; Foglet needs column-width allocation, which Raxol's `Display.Table` already does |
| `tz` / `tz_extra` (alternative to `tzdata`) | Tzdata is already loaded as a transitive Timex dep; introducing a second tz library is duplication |
| `nimble_options` for form validation | The form errors are interaction bugs (Esc/Enter/Tab routing, focus, submit feedback) not validation-DSL gaps |
| Dedicated Erlang bracketed-paste library | None exists for OTP. Bracketed paste is an ANSI-escape protocol (`DECSET 2004` + `ESC[200~`/`ESC[201~`). The fix is ~80 LOC in `Foglet.SSH.CLIHandler` + `Foglet.TUI.Input` |
| `earmark`/`earmark_parser` (alternative markdown) | Switching markdown engines is a v1.3-equivalent foundation change, not a v1.4 polish item; MDEx already supports the hardbreak we need |

### Modify (existing-deps configuration changes)

These are wiring/option changes inside Foglet, **not** dependency
upgrades. They belong in the roadmap as code phases, not stack phases.

| Change | Where | What | Why |
|--------|-------|------|-----|
| Pass `wrap: :word` to `MultiLineInput.init/1` | `lib/foglet_bbs/tui/screens/post_composer/state.ex:39`, `lib/foglet_bbs/tui/screens/new_thread/state.ex:55`, `lib/foglet_bbs/tui/screens/new_thread.ex:229` | All three call sites currently set `wrap: :none` | Globally #3 — composer doesn't word-wrap long lines |
| Add `[render: [hardbreaks: true]]` to MDEx call | `lib/foglet_bbs/markdown.ex:64` (`MDEx.to_html!(sanitized, …)`) | Currently calls `MDEx.to_html!/1` with no options | Globally #2 — newlines collapse |
| Wire `column_widths: :auto` and per-column `:width` policy through `Display.Table` facade | `lib/foglet_bbs/tui/widgets/display/table.ex:184` (`normalize_column/1` defaults `:width` to `20`) | Hard-coded 20-char column cap is what's producing the cramped Invites layout | Sysop #12 — Invites table cramps |
| Emit bracketed-paste enable/disable on PTY in/out | `lib/foglet_bbs/ssh/cli_handler.ex` (alongside `send_alt_screen_enter`/`leave`) | Send `\e[?2004h` on PTY up, `\e[?2004l` on EOF/closed | Account #9 — paste SSH pubkey |
| Recognize `ESC[200~…ESC[201~` in `parse_input` and emit a `:paste` Raxol event | New helper in `Foglet.SSH.CLIHandler.handle_ssh_msg(:data, …)` or thin wrapper around `Raxol.SSH.IOAdapter.parse_input/1` | The vendored `IOAdapter` delegates to `Raxol.Terminal.ANSI.InputParser`; we can't extend Raxol without pinning a fork, so do the unwrap in CLIHandler before dispatch | Account #9 — paste SSH pubkey |
| Use `Tzdata.zone_list/0` for the timezone picker datasource | New picker widget under `lib/foglet_bbs/tui/widgets/input/` (or reuse `Raxol.UI.Components.Input.SelectList` with `enable_search: true`) | Currently a free-text field | Account #6 — no way to select a timezone |

## Per-Issue Stack Verdicts

Mapping ISSUES.md sections to stack decisions. For each issue, "**Code
fix**" means no dependency change is required.

### Login Screen

| # | Issue | Verdict |
|---|-------|---------|
| 1 | TextInput cursor doesn't follow typing | **Code fix** — already partially addressed in quick task 260426-hbu (cursor marker added). Remaining work is screen-side focus routing |
| 2 | Forgot Password missing email validation | **Code fix** — reuse `User.validate_email/1` regex (already in `Accounts.User`); no new validator dep needed |
| 3 | Breadcrumbs don't update on Register/Forgot screens | **Code fix** — `Foglet.TUI.App` chrome metadata wiring |
| 4 | Reset email crops at small terminals; no token-consume entry; no-email path | **Code fix** — layout fix using `Foglet.TUI.TextWidth` + new screen for token entry; MTAs already handled by `swoosh` + `gen_smtp` |

### Main Menu Screen

| # | Issue | Verdict |
|---|-------|---------|
| 1 | Box titles inside box, should be on border | **Code fix** — Raxol `box` accepts a title slot; already used elsewhere |
| 2 | Oneliners box `\|\|\|\|\|\|` glyph artifact on top border | **Code fix** — likely a render order / theme-routed character bug |
| 3 | Up/Down arrows inert (struck per PROJECT.md, fixed pre-milestone) | n/a |
| 4 | Navigation keys should be accent color | **Code fix** — `Foglet.TUI.Theme` slot routing |
| 5 | Indent corrections | **Code fix** — render-side spacing |
| 6, 7 | Theme application for navigation/oneliners | **Code fix** — theme slot wiring (D-07/D-09 already enforce this) |

### Account Screen

| # | Issue | Verdict |
|---|-------|---------|
| 1 | Esc Cancel does nothing | **Code fix** — screen-side key handling |
| 2 | "PROFILE" tab + "Profile" content header redundant | **Code fix** — render-side text |
| 3 | Profile submit gives no feedback, values lost | **Code fix** — submit path + persistence wiring; `Modal.Form` and `Foglet.TUI.Command` already exist |
| 4 | Preferences fields un-selectable | **Code fix** — focus routing in `prefs_form.ex` |
| 5 | Shift+Tab doesn't reverse focus | **Code fix** — `Foglet.TUI.Input` doesn't currently translate Shift+Tab; add `{:tab, :backward}` |
| 6 | No timezone picker | **Modify** — use `Tzdata.zone_list/0` (already loaded) as datasource; render via `Raxol.UI.Components.Input.SelectList` with `enable_search: true`. **No new dep.** |
| 7 | Submit/Cancel hint redundant under menu and on command bar | **Code fix** — chrome cleanup |
| 8 | Field focus leaks to timezone | **Code fix** — focus routing bug |
| 9 | **No SSH pubkey paste** | **Modify** — add bracketed-paste support in `Foglet.SSH.CLIHandler` (emit `\e[?2004h` on PTY up, parse `\e[200~…\e[201~`, emit `:paste` event). **No new dep.** Estimated ~80 LOC across CLIHandler + Input + screen-side handler |

### Sysop Screen

| # | Issue | Verdict |
|---|-------|---------|
| 1 | "Press any key to load" antipattern; only Tab loads | **Code fix** — initial load path in `Foglet.TUI.App` / sysop screen state |
| 2 | "1-6 Jump" inconsistency with other tab-bearing screens | **Code fix** — `Foglet.TUI.Widgets.Input.Tabs` already supports 1-9 numeric jump; surface consistently |
| 3 | Site tab values uneditable | **Code fix** — same form-interaction class as Account #4 |
| 4 | Subtitles expose internal planning denotions | **Code fix** — copy/text |
| 5 | Site tab Enter/Esc inert | **Code fix** — same form-interaction class |
| 6, 7, 8 | Boards / Limits / System tabs never load | **Code fix** — likely `state.ex` data-fetch / preload bugs in sysop screen state |
| 9 | Users tab loads sometimes | **Code fix** — race or data-fetch error handling |
| 10 | "Invalid status transition" surfaced | **Code fix** — `Accounts.update_user_status/2` validation message bubbles up; UX should pre-check transitions per `User.status_changeset` allowed transitions |
| 11 | Users tab keys inert | **Code fix** — screen-side key handling |
| 12 | **Invites table cramps columns** | **Modify** — `Display.Table` facade currently defaults `:width` to `20` per column. Switch to `column_widths: :auto` (Raxol supports it) and pass per-column hints from screen. **No new dep.** |
| 13 | No way to select existing invite codes | **Code fix** — table selection wiring |

### Moderation Screen

| # | Issue | Verdict |
|---|-------|---------|
| 1 | LOG/USERS/BOARDS extend above terminal | **Code fix** — same root cause as Boards #1: layout overflow when content > viewport. Use `Raxol.UI.Components.Display.Viewport` (already vendored) instead of unbounded columns |
| 2 | LOG table truncates early | **Modify** — same `column_widths: :auto` + responsive hint as Sysop #12 |

### Boards Screen

| # | Issue | Verdict |
|---|-------|---------|
| 1 | Interface extends above terminal | **Code fix** — viewport / size-gate fix; `Foglet.TUI.SizeGate` already exists, screens need to honor available height |
| 2 | Enter on category should expand/collapse | **Code fix** — `Raxol.UI.Components.Display.Tree` (already vendored, listed in WIDGET_GALLERY.md) provides expand/collapse semantics. Local facade `Foglet.TUI.Widgets.Display.Tree` already exists; wire it into the boards screen if not already |
| 3 | Selecting a board freezes (struck per PROJECT.md, fixed pre-milestone) | n/a |

### Globally

| # | Issue | Verdict |
|---|-------|---------|
| 1 | Border glyphs to right of right-most tab | **Code fix** — `Foglet.TUI.Widgets.Input.Tabs` render-side trailing-fill bug |
| 2 | **Markdown collapses newlines** | **Modify** — `MDEx.to_html!(sanitized, render: [hardbreaks: true])` in `Foglet.Markdown.render/1`. Optional: also adjust `Foglet.TUI.Widgets.Post.MarkdownBody.deduplicate_newlines/1` to allow up to one blank-line gap. **No new dep.** |
| 3 | **Editor doesn't word-wrap** | **Modify** — flip `wrap: :none` to `wrap: :word` on three `MultiLineInput.init/1` call sites. Also pass an updated `width:` on resize. **No new dep.** |

## Out of Scope for v1.4 Stack Decisions

Explicitly defer these to later milestones (record so the roadmapper
doesn't quietly pull them in):

- **Telnet transport** — already Out of Scope per `PROJECT.md`. Don't
  add `:tnt` or telnet-protocol libraries.
- **Web/LiveView UI** — Phoenix endpoint stays operational-only.
- **Email notification dependencies (e.g. `phoenix_swoosh`)** —
  SEED-001/SEED-002 are dormant; unlock when v1.5+ adds notifications.
- **Alternative markdown engine (`earmark_parser`)** — MDEx is the
  v1.3-validated choice; switching is foundation work, not v1.4 polish.
- **Multi-line input replacement (e.g. building a custom editor)** —
  Raxol's `MultiLineInput` does word-wrap, undo/redo, selection, and
  scroll. Configuration, not replacement.
- **Custom timezone picker UI library** — `Raxol.UI.Components.Input.SelectList`
  with `enable_search: true` covers Account #6 without new deps.
- **Phoenix LiveDashboard upgrades** — orthogonal to TUI bug-fix scope.
- **Argon2/Hammer/Bodyguard upgrades** — no v1.4 issue motivates a
  bump.

## Bracketed-Paste Implementation Sketch (informational)

For Account #9 (SSH key paste), since this is the only "non-trivial
code change pretending to be a stack question," here's the
implementation contract so the roadmapper can size it:

1. **Enable on PTY up.** In `Foglet.SSH.CLIHandler.handle_ssh_msg(:pty, …)`,
   alongside the existing `send_alt_screen_enter/1`, send
   `\e[?2004h`. On `:eof` and `:closed`, send `\e[?2004l` alongside the
   existing `send_alt_screen_leave/1`.
2. **Detect in `:data` handler.** Before calling
   `Raxol.SSH.IOAdapter.parse_input/1`, scan for `\e[200~`. If present,
   buffer raw bytes until `\e[201~`, then emit a synthetic `:paste`
   event carrying the content. Pass remaining bytes through normally.
   This keeps the change contained in `Foglet.SSH.CLIHandler` and avoids
   forking the vendored `Raxol.Terminal.ANSI.InputParser`.
3. **Translate in `Foglet.TUI.Input`.** Add a `translate_key/1` clause
   that maps a `:paste` event into a `MultiLineInput.update/2`
   `{:paste, content}` message. `Raxol.UI.Components.Input.MultiLineInput.ClipboardHelper`
   already exposes `paste/1` and an `insert_text/2`-equivalent path; the
   message routing is the integration point.
4. **For `TextInput` (single-line).** SSH key paste targets the
   single-line `TextInput`. Insert pasted content at cursor, truncating
   at `max_length`, stripping `\r` and `\n` (single-line invariant).

No vendored Raxol fork required. No new mix.exs dependency. ~80-120 LOC
including tests. Targets one ISSUES.md item but unblocks general paste
behavior across all `TextInput` and `MultiLineInput` consumers.

## Sources

- `mix.exs` and `mix.lock` (verified Timex/Tzdata transitive deps).
- `lib/foglet_bbs/markdown.ex` (verified `MDEx.to_html!/1` called
  without render options).
- `lib/foglet_bbs/tui/screens/post_composer/state.ex`,
  `new_thread/state.ex`, `new_thread.ex` (verified `wrap: :none` at
  three call sites).
- `lib/foglet_bbs/tui/widgets/display/table.ex` (verified
  `normalize_column/1` defaults `:width` to `20`, not `:auto`).
- `lib/foglet_bbs/ssh/cli_handler.ex` (verified existing alt-screen
  escape pattern; same pattern works for `\e[?2004h/l`).
- `vendor/raxol/lib/raxol/ui/components/input/multi_line_input.ex`
  (verified `wrap: :word` is the upstream default and supported).
- `vendor/raxol/lib/raxol/ssh/io_adapter.ex` (verified delegation to
  `Raxol.Terminal.ANSI.InputParser`; bracketed-paste must be unwrapped
  in CLIHandler before this delegation, or after via Foglet code).
- `vendor/raxol/lib/raxol/ui/components/input/multi_line_input/clipboard_helper.ex`
  (verified `Clipboard.paste/0` uses an OS clipboard helper — does NOT
  reach SSH client; bracketed-paste is the correct path).
- `docs/raxol/getting-started/WIDGET_GALLERY.md` (verified
  `MultiLineInput`, `Display.Table` with `column_widths: :auto`,
  `Display.Tree`, `Display.Viewport`, `Input.SelectList` with
  `enable_search` are all available).
- [MDEx.Document — MDEx v0.10.0 docs](https://hexdocs.pm/mdex/MDEx.Document.html) — confirmed `:hardbreaks` render option exists in MDEx (project pins `~> 0.2`, comrak ABI is stable for this option across that range; verify against `deps/mdex/lib` if pinning matters).
- [comrak / hardbreaks rendering option](https://github.com/kivikakk/comrak) — comrak (the Rust engine MDEx wraps) documents `hardbreaks` as a stable render flag.
- [Bracketed Paste Mode (cirw.in)](https://cirw.in/blog/bracketed-paste) — protocol spec: `\e[?2004h` enables, `\e[200~`/`\e[201~` wraps pastes.
- [Bracketed Paste Mode in Terminal (jdhao)](https://jdhao.github.io/2021/02/01/bracketed_paste_mode/) — confirms terminal-side mechanics; nothing Erlang-specific is required server-side.
