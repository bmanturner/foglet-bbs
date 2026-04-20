---
phase: 07-migrate-hand-rolled-ui-components-to-raxol-widgets
verified: 2026-04-20T22:00:00Z
status: human_needed
score: 10/10 must-haves verified
overrides_applied: 0
human_verification:
  - test: "SSH into running BBS. Trigger an invalid-login modal (error type). Confirm the message color is the theme error hex (#ff5555) — not red. Trigger /help (info type). Confirm neutral color."
    expected: "Modal message text is hex-colored from theme slots; no red/yellow/green hard-coded terminal colors visible."
    why_human: "Terminal rendering and theme propagation require eyeballs. inspect() tests verify the data structure, not the rendered terminal output."
  - test: "SSH in. Open a seeded post that has more than 10 lines. Press j/k line-by-line and confirm smooth single-line scrolling. Press N/P to switch posts and confirm scroll position resets to the top of the new post. Resize the terminal window and confirm visible lines update without border fragments or jitter."
    expected: "j advances one line at a time; k retreats one line, clamped at 0; N/P reset scroll to top; terminal resize recalculates visible height without visual artifacts."
    why_human: "Viewport UX regression detection (smoothness, line boundary accuracy, scroll-to-end behavior) cannot be verified programmatically without running the SSH server."
---

# Phase 07: Migrate Hand-Rolled UI Components to Raxol Widgets — Verification Report

**Phase Goal:** Replace custom widget implementations with Raxol primitives where a built-in equivalent exists and overlap is high, gated on theming support. Modal becomes a thin adapter routing colors through Foglet.TUI.Theme slots; PostReader scroll windowing migrates to Raxol.UI.Components.Display.Viewport (which owns clamping); SelectionList (base + full) and StatusBar stay hand-rolled per the research theming verdicts.
**Verified:** 2026-04-20T22:00:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Modal.render/2 no longer contains hardcoded color atoms `:red`/`:yellow`/`:green` — all colors come from theme | VERIFIED | `modal.ex`: no `:red`/`:yellow`/`:green` atom matches; `color_for_type/2` returns `theme.error.fg`, `theme.warning.fg`, `theme.primary.fg` |
| 2 | app.ex render_modal_overlay/2 extracts theme from state.session_context | VERIFIED | Line 170: `theme = (Map.get(state, :session_context) \|\| %{}) \|> Map.get(:theme) \|\| Theme.default()` |
| 3 | MarkdownBody.render_tuples_as_lines/4 exists and returns a flat list | VERIFIED | `markdown_body.ex` line 110: `def render_tuples_as_lines(tuples, width, %Theme{} = theme, opts \\ [])` — returns `Enum.map(..., fn group -> line_group_to_row(...) end)` with no column wrapper |
| 4 | PostCard.render_body_lines/5 exists and delegates to MarkdownBody for body lines only | VERIFIED | `post_card.ex` line 110: `def render_body_lines(...)` calls `MarkdownBody.render_tuples_as_lines(tuples, width, theme, body_opts(opts))` — no assemble_card call |
| 5 | PostReader no longer has `:scroll_offset` as a live field — viewport owns scroll state | VERIFIED | `post_reader.ex`: `default_screen_state` has `viewport:` field, not `scroll_offset:`; `get_screen_state/1` drops `:scroll_offset` via `Map.drop([:scroll_offset])`; grep for `:scroll_offset` shows only comments and the drop call |
| 6 | scroll_post/2 calls Viewport.update with a scroll_by message | VERIFIED | Line 391: `{new_vp, []} = Viewport.update({:scroll_by, delta}, new_vp)` |
| 7 | advance_post/2 resets scroll via Viewport.update with scroll_to 0 | VERIFIED | Line 346: `{reset_vp, []} = Viewport.update({:scroll_to, 0}, ss.viewport)` |
| 8 | Theme hygiene: no bare `:red`/`:yellow`/`:green` color atoms in modal/post widgets | VERIFIED | Grep across `lib/foglet_bbs/tui/widgets/` returns zero matches in modal.ex and post widgets (one match in markdown_body.ex moduledoc is inside the string `` `:gray` / `:green` `` referring to a theme name, not a color atom used as an fg value) |
| 9 | Test files exist and reflect new API contracts | VERIFIED | `modal_test.exs`: 14 tests including 5 theme-slot routing + 1 hygiene (refute `:red`/`:yellow`/`:green`); `markdown_body_test.exs`: `describe "render_tuples_as_lines/4"` block; `post_card_test.exs`: `describe "render_body_lines/5"` block; `post_reader_test.exs`: `viewport.scroll_top` assertions throughout, no `scroll_offset` assertions |
| 10 | SelectionList and StatusBar are UNCHANGED (hand-rolled per research verdict) | VERIFIED | git log shows no commits touching `selection_list.ex` or `status_bar.ex` since phase 07 plans landed; no phase 07 SUMMARY references either file |

**Score:** 10/10 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/foglet_bbs/tui/widgets/modal.ex` | Theme-aware modal body renderer | VERIFIED | Contains `def render(%{message: msg} = spec, %Theme{} = theme)`, `color_for_type/2` with 4 clauses reading theme slots, `alias Foglet.TUI.Theme`. No `render/1` clause. |
| `lib/foglet_bbs/tui/app.ex` | Modal overlay that passes theme to Widgets.Modal | VERIFIED | `render_modal_overlay/2` at line 169 extracts theme from state, calls `Widgets.Modal.render(modal, theme)`. `alias Foglet.TUI.Theme` present. |
| `lib/foglet_bbs/tui/widgets/post/markdown_body.ex` | New `render_tuples_as_lines/4` flat-list function | VERIFIED | Exists at line 110. No `window_lines` or `lines_to_column` call. Returns raw list from `group_by_newline \|> Enum.map(line_group_to_row)`. |
| `lib/foglet_bbs/tui/widgets/post/post_card.ex` | New `render_body_lines/5` body-only flat-list function | VERIFIED | Exists at line 110. Delegates to `MarkdownBody.render_tuples_as_lines`. Does not call `assemble_card`. `_ = post` binding present. |
| `lib/foglet_bbs/tui/screens/post_reader.ex` | Viewport-backed scroll state | VERIFIED | `alias Raxol.UI.Components.Display.Viewport`; `default_screen_state` calls `Viewport.init`; `warm_viewport/4` exists; `show_scrollbar: false`. |
| `test/foglet_bbs/tui/widgets/modal_test.exs` | Theme-slot hygiene + routing assertions | VERIFIED | Contains `describe "render/2 — theme slot routing (Phase 7)"` and `describe "render/2 — theme hygiene (Phase 7)"` with `refute serialized =~ ":red"`. |
| `test/foglet_bbs/tui/widgets/post/markdown_body_test.exs` | Flat-list shape + length + no windowing tests | VERIFIED | `describe "render_tuples_as_lines/4 — flat list for Viewport children"` present with 6 tests. |
| `test/foglet_bbs/tui/widgets/post/post_card_test.exs` | Body-only flat-list + no header tests | VERIFIED | `describe "render_body_lines/5 — flat list for Viewport children"` present with 5 tests. |
| `test/foglet_bbs/tui/screens/post_reader_test.exs` | viewport.scroll_top assertions replacing scroll_offset | VERIFIED | `scroll_offset` appears 0 times as an assertion target; `viewport.scroll_top` appears in 14+ assertion lines. New viewport shape and render_cache preservation tests present. |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `app.ex render_modal_overlay/2` | `Widgets.Modal.render/2` | explicit theme arg | WIRED | Line 175: `Widgets.Modal.render(modal, theme)` — two args confirmed |
| `modal.ex color_for_type/2` | `Foglet.TUI.Theme` slots | `theme.error.fg`, `theme.warning.fg`, `theme.primary.fg` | WIRED | Lines 64-67: all 4 clauses read theme struct fields |
| `PostCard.render_body_lines/5` | `MarkdownBody.render_tuples_as_lines/4` | delegation | WIRED | `post_card.ex` line 113: `MarkdownBody.render_tuples_as_lines(tuples, width, theme, body_opts(opts))` |
| `post_reader.ex default_screen_state` | `Viewport.init/1` | `{:ok, vp} = Viewport.init(%{...})` | WIRED | Lines 237-244: init with `id`, `children`, `visible_height`, `scroll_top`, `show_scrollbar: false` |
| `post_reader.ex render_post_content/5` | `PostCard.render_body_lines/5` | children source for Viewport | WIRED | Line 77: `body_lines = PostCard.render_body_lines(post, tuples, w, theme)` |
| `post_reader.ex render_post_content/5` | `Viewport.render/2` | view element construction | WIRED | Line 85: `body_rendered = Viewport.render(vp, %{})` |
| `post_reader.ex scroll_post/2` | `Viewport.update({:scroll_by, delta})` | scroll operation | WIRED | Line 391: `{new_vp, []} = Viewport.update({:scroll_by, delta}, new_vp)` |
| `post_reader.ex advance_post/2` | `Viewport.update({:scroll_to, 0})` | scroll reset | WIRED | Line 346: `{reset_vp, []} = Viewport.update({:scroll_to, 0}, ss.viewport)` |
| `post_reader.ex warm_viewport/4` | `PostCard.render_body_lines/5` | children pre-population | WIRED | Line 328: `body_lines = PostCard.render_body_lines(post, tuples, w, theme)` |

---

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|-------------------|--------|
| `post_reader.ex render_post_content/5` | `body_lines` | `PostCard.render_body_lines(post, tuples, w, theme)` | Yes — delegates to `MarkdownBody.render_tuples_as_lines` which maps `group_by_newline \|> line_group_to_row` over actual parsed tuples | FLOWING |
| `post_reader.ex render_post_content/5` | `tuples` | `ss.render_cache[{post.id, w}] \|\| parse_body(state, post)` | Yes — render cache populated by `warm_cache` which calls `parse_body` which calls `Foglet.Markdown.render/1` on real post body | FLOWING |
| `app.ex render_modal_overlay/2` | `theme` | `state.session_context \|> Map.get(:theme) \|\| Theme.default()` | Yes — either real session theme or the populated `Theme.default()` struct; never nil | FLOWING |

---

### Behavioral Spot-Checks

Step 7b SKIPPED for the interactive terminal rendering behaviors — cannot run SSH server without external service setup. The orchestrator confirmed `mix test` → 624 tests, 0 failures, which covers all automated unit and integration assertions.

| Behavior | Result | Status |
|----------|--------|--------|
| 624 tests, 0 failures (full suite baseline per orchestrator) | All pass | PASS |
| `grep :red\|:yellow\|:green lib/foglet_bbs/tui/widgets/modal.ex` returns 0 matches | Confirmed | PASS |
| `grep scroll_offset lib/foglet_bbs/tui/screens/post_reader.ex` — only in comments and `Map.drop` | Confirmed | PASS |
| `grep Viewport.update lib/foglet_bbs/tui/screens/post_reader.ex` returns 8 matches (init, set_children x3, set_visible_height x2, scroll_by, scroll_to) | Confirmed | PASS |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| D-04 | 07-01, 07-03 | Theming gate applied before migration; thin adapter / full replacement per research | SATISFIED | Modal is thin adapter (ThemeManager rejected per research); Viewport full integration (theming gate passed). |
| D-05 | 07-01, 07-02, 07-03 | Theming gate applies to all five in-scope targets | SATISFIED | Modal, PostReader Viewport — both evaluated and migrated correctly. SelectionList/StatusBar stayed hand-rolled per research theming verdict. |
| D-06 | 07-01 | Modal types map correctly; color_for_type/2 maps :error/:warning/:confirm/:info to theme slots | SATISFIED | 4-clause `color_for_type/2` at modal.ex lines 64-67 |
| D-07 | 07-01 | `do_update({:show_modal, modal})` dispatch site unchanged; only render path updated | SATISFIED | `app.ex` line 281: `defp do_update({:show_modal, modal}, state)` is unchanged; only `render_modal_overlay/2` was updated |
| D-08 | 07-01 | Thin adapter: Modal.render/2 accepts (modal_spec, theme) | SATISFIED | `modal.ex` line 42: `def render(%{message: msg} = spec, %Theme{} = theme)` |
| D-12 | 07-03 | Manual scroll_offset + max_lines slice replaced by Display.Viewport | SATISFIED | `scroll_offset` removed from screen_state; `body_line_count` call gone from scroll_post; Viewport.update handles clamping |
| D-13 | 07-03 | render_cache keyed on {post.id, width} preserved | SATISFIED | `render_cache: %{}` in default_screen_state; cache reads/writes in warm_cache and render_post_content preserved |
| D-17 | 07-01 | Caller (app.ex) updated in same plan wave as widget change | SATISFIED | Plans 07-01 and 07-03 both updated callers alongside widget changes |
| D-R1 | 07-02, 07-03 | Viewport children are one element per rendered body line (flat list) | SATISFIED | `render_tuples_as_lines/4` returns raw list from `Enum.map(group_by_newline(...), line_group_to_row)`; Viewport receives these as children |

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `lib/foglet_bbs/tui/widgets/post/markdown_body.ex` | 29 | `` `:gray` / `:green` `` in moduledoc string | Info | False positive — this is a theme-name string inside `@moduledoc`, not a color atom used as an `fg:` value. No impact. |

No blockers or warnings found. The moduledoc reference is documentation text about theme variant names, not a hardcoded color atom in code.

---

### Human Verification Required

#### 1. Modal color rendering under SSH

**Test:** SSH into the running BBS. Attempt login with invalid credentials to trigger an `:error` modal. Then issue a help command to trigger an `:info` modal.
**Expected:** The `:error` modal message text is rendered in the theme error color (hex `#ff5555` in the default theme — a warm red, but coming from the theme struct, not a hardcoded `:red` atom). The `:info` modal message text is in the primary fg color (neutral gray). No ANSI color code that would result from atom-based rendering (e.g., bold red default from `:red`) should appear.
**Why human:** The `inspect(tree, ...)` tests verify the Raxol view element data structure contains the correct hex strings. They do not verify that Raxol's renderer correctly converts those hex strings to terminal escape codes when writing to the SSH pty. A theme regression at the renderer layer would not be caught by unit tests.

#### 2. Viewport scroll UX — smoothness, line boundary, reset behavior

**Test:** SSH in. Open a seeded post that has more than 10 lines of body content. Press `j` / `k` repeatedly. Then press `N` / `P` to navigate to another post. Resize the terminal window to a smaller then larger size while on the post reader screen.
**Expected:** `j` advances exactly one line at a time (no double-jump). `k` retreats one line and stops at the top without going negative or wrapping. `N`/`P` navigation resets the viewport to the top of the new post (not mid-scroll). Terminal resize updates the visible line count without border fragments or content duplication.
**Why human:** `scroll_post` and `advance_post` unit tests verify the state shape (`viewport.scroll_top == 1`, `== 0`), but Viewport's internal `clamp_scroll` behavior, the interaction between `set_visible_height` and `scroll_by` on a real terminal size, and visual layout quality cannot be verified without rendering to an actual SSH pty.

---

### Gaps Summary

No gaps found. All 10 must-haves are verified in the codebase. The two items in human_verification are manual UX/rendering checks that cannot be confirmed programmatically — they are not blocking gaps, but require human sign-off before the phase can be marked fully passed.

---

_Verified: 2026-04-20T22:00:00Z_
_Verifier: Claude (gsd-verifier)_
