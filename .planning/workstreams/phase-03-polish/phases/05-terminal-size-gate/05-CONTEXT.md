# Phase 5: Terminal size gate — Context

**Gathered:** 2026-04-20
**Status:** Ready for planning
**Workstream:** phase-03-polish (v1.0.1)

<domain>
## Phase Boundary

Below an agreed minimum terminal dimension, `App.view/1` short-circuits normal screen rendering and emits a centered "terminal too small" message showing required and current dimensions. When the terminal resizes back above the threshold, `App.view/1` resumes normal rendering — `current_screen`, `screen_state`, composer drafts, and selected indices are preserved across the resize because the gate never touches them.

**In scope:**
- Add a `too_small?/1` predicate on terminal size.
- Add a render-time branch in `App.view/1` that short-circuits screen rendering when gated.
- Render a centered multi-line "too small" message with required and current dims.
- Swallow key events at `App.update/2` when gated so hidden screens don't silently mutate state.
- Dedupe bursty `{:window_change, cols, rows}` events with a same-size guard in `app.ex:251`.

**Explicitly NOT in scope:**
- Graceful compact layouts for small terminals (anti-feature per research — one threshold, not per-screen).
- Per-screen thresholds.
- Time-based debouncing (Raxol coalesces renders; the same-size guard is sufficient).
- Alt-screen handling changes (already hardened — do not touch).
- Hysteresis / anti-flicker band at the boundary (same-size guard is sufficient; boundary oscillation is rare in practice).
- New Foglet.Config key for min dims (chose hard-coded constants; sysop-tunable minimums not needed for v1.0.1).

**Dependencies met:** Phase 1 (ScreenFrame exists; the gate bypasses it but needs terminal_size plumbing which Phase 1 did not touch — terminal_size was already wired via CLIHandler).

</domain>

<decisions>
## Implementation Decisions

### Threshold value

- **D-01:** User-facing minimum terminal size is **60×20**. Narrow but usable. BoardList row density suffers slightly at 60 cols; Phase 3 D-03's `…` title truncation handles the overflow. Chosen over research's 80×24 recommendation to accommodate phone SSH clients and small tmux panes.
- **D-02:** Actual code-level threshold is `cols < 64 OR rows < 22`. The 4-col / 2-row margin above the 60×20 mental minimum accounts for chrome overhead: outer border (2 cols + 2 rows), box padding (2 cols + 2 rows), StatusBar (1 row), divider (1 row), KeyBar (1 row). Effective content area at 64×22 = 60×15, giving the user-visible 60-col content column from their stated minimum.
- **D-03:** Threshold is a module constant — `@min_cols 64` and `@min_rows 22` in `Foglet.TUI.App` (or a new `Foglet.TUI.SizeGate` module — planner decides; see Claude's Discretion). NOT a Foglet.Config key. Sysop cannot tune via config in v1.0.1; adjustment requires a code change. This is intentional — the threshold correlates with chrome geometry (Phase 1 decisions) and should be co-located.

### Gate implementation location

- **D-04:** Gate lives at `App.view/1` top level, NOT inside `ScreenFrame.render/4`. The check runs before `screen_module_for(state.current_screen).render(state)` dispatch. When gated, `App.view/1` returns a standalone centered element — the ScreenFrame is bypassed entirely. No outer border, no StatusBar, no KeyBar on the too-small screen — it's pure text.
- **D-05:** The gate is a pure render-time branch. It reads `state.terminal_size` and returns a different element tree. It does NOT:
  - Change `state.current_screen`
  - Clear or modify `state.screen_state`
  - Trigger any commands (empty command list)
  - Touch composer drafts or MultiLineInput state
- **D-06:** `App.view/1` gains a new internal helper: `too_small?/1` that takes state (or terminal_size) and returns boolean. Planner decides the exact function signature.

### Gate message content

- **D-07:** Multi-line centered message, themed in `theme.dim.fg`:
  ```
  Terminal too small.
  Foglet BBS requires at least 60×20.
  Your terminal is currently: {cols}×{rows}.
  Please resize.
  ```
  The current-size line is dynamic — reads from `state.terminal_size`. No exit / disconnect hint (Ctrl+C works anyway via SSH channel). No ASCII frame around the message.
- **D-08:** Centering uses existing Raxol layout primitives (planner's choice of `column` + `row` with `justify_content: :center` or a simple centered `text/2`). The 60×20 minimum guarantees enough horizontal space for the longest line ("Foglet BBS requires at least 60×20." = 36 chars) and vertical room for 4 lines.

### Resize event dedup

- **D-09:** Add a same-size guard to `App.do_update({:window_change, cols, rows}, state)` at `app.ex:251-254`. Short-circuit with `{state, []}` when `{cols, rows} == state.terminal_size`. Prevents render storms during tmux/iTerm drags that fire bursty SIGWINCH events at the same terminal size.
- **D-10:** No time-based debouncing. Raxol's internal render coalescing handles the frame-rate concern. The same-size guard is sufficient per research.

### Keys during too-small state

- **D-11:** At `App.update/2` entry, check `too_small?(state)` BEFORE dispatching to the current screen's `handle_key/2`. When gated, return `{state, []}` — swallow the event. Exception: resize events (`:window_change`) always reach `do_update` because the whole point is to un-gate on resize.
- **D-12:** Disconnect events (Ctrl+C at SSH layer, EOF on stdin) are NOT BBS key events — they arrive at the SSH channel layer in `CLIHandler` and terminate the session regardless of gate state. No special handling needed in the gate logic.

### Boundary semantics

- **D-13:** Gate fires on STRICT inequality: `cols < @min_cols` OR `rows < @min_rows`. A terminal at exactly 64×22 passes through to normal rendering. The `@min_cols`/`@min_rows` constants represent the lowest working size (inclusive floor).

### Claude's Discretion

- **Module placement:** D-03 puts the constants in `Foglet.TUI.App` OR a new `Foglet.TUI.SizeGate` module. If the gate grows beyond ~10 LOC (likely true — predicate + renderer + constants), a dedicated module is cleaner. Both are acceptable.
- **Message rendering function:** D-07 gives the exact text; planner decides the exact Raxol element shape (single `text/2` per line in a `column`, or one multi-line `text/2` — Raxol handling of embedded newlines in `text/2` is worth a quick empirical check first).
- **Predicate shape:** `too_small?(state)` vs `too_small?(terminal_size)` vs inline check in `App.view/1` — all viable. If used in multiple places (view, update, handle_key), a named helper makes the call sites read cleanly.
- **Legacy `composer_draft` / `MultiLineInput` resize interaction:** Phase 4 CONTEXT notes the composer_draft field is legacy. Phase 5 must NOT rebuild `MultiLineInput` from width on resize (research pitfall 4). This is a non-action: the existing `composer_screen_state/1` initializer is only called once on entry; resize does not flow into it. Planner should add a regression test that typing → resize (crossing threshold both ways) → typing preserves `input_state.value`.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Workstream Requirements and Roadmap
- `.planning/workstreams/phase-03-polish/REQUIREMENTS.md` — FRAME-03 requirement; open-decision table entry resolving to 60×20 (this CONTEXT)
- `.planning/workstreams/phase-03-polish/ROADMAP.md` — Phase 5 success criteria; dependency on Phase 1

### Research
- `.planning/workstreams/phase-03-polish/research/FEATURES.md` §9 — Minimum terminal size analysis (research recommended 80×24; user chose 60×20 per this CONTEXT)
- `.planning/workstreams/phase-03-polish/research/PITFALLS.md` §Pitfall 4 — Resize-during-alt-screen flicker and state loss prevention; render-time branch, same-size guard, never rebuild MultiLineInput from width
- `.planning/workstreams/phase-03-polish/research/SUMMARY.md` — High-confidence findings on alt-screen already being hardened

### Prior Phase Context
- `.planning/workstreams/phase-03-polish/phases/01-widget-foundation-theme-screen-chrome/01-CONTEXT.md` — ScreenFrame chrome overhead (D-05/D-06: outer border + padding + StatusBar + divider + KeyBar); theme slots (`theme.dim.fg` for gate message)
- `.planning/workstreams/phase-03-polish/phases/04-composer-thread-creation-end-to-end/04-CONTEXT.md` — Composer state management; MultiLineInput state lifecycle (do not rebuild on resize)

### Raxol DSL Constraint
- `lib/foglet_bbs/tui/widgets/chrome/` — canonical examples of function-form widget DSL for the centered message (`column/row/box do...end` block macros)

### Existing Code to Modify
- `lib/foglet_bbs/tui/app.ex` — `view/1` gate branch (D-04); `update/2` key-swallow guard (D-11); `do_update({:window_change, ...})` same-size guard (D-09, at line 251-254)
- (Optionally new) `lib/foglet_bbs/tui/size_gate.ex` — dedicated module housing `@min_cols`, `@min_rows`, `too_small?/1`, and `render_too_small/1` if planner chooses module placement over inlining in App

### Do NOT Touch
- `lib/foglet_bbs/ssh/cli_handler.ex` — alt-screen takeover and `\e[?1049l` exit paths (already hardened per research; exit paths at lines 196, 203)
- `lib/foglet_bbs/sessions/session.ex` — terminal_size tracking (already correct)
- `Foglet.TUI.Widgets.Chrome.ScreenFrame` — Phase 1 locked signature and layout; the gate bypasses ScreenFrame, does not modify it

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `state.terminal_size` — already `{cols, rows}` tuple, plumbed end-to-end via CLIHandler → Session → App. Every screen that needs width reads it correctly.
- `Foglet.TUI.App.do_update({:window_change, cols, rows}, state)` at `app.ex:251-254` — already updates `terminal_size`; D-09 adds the same-size guard here.
- `Foglet.TUI.App.view/1` — current dispatcher pattern `screen_module_for(state.current_screen).render(state)`. D-04 adds a branch above this.
- Theme `theme.dim.fg` — available via `state.session_context.theme` or `Theme.default()`. Used for the gate message text color per D-07.

### Established Patterns
- Screen state is preserved across `{:window_change, ...}` events today because `do_update` only updates `terminal_size` and notifies the Session GenServer — it does not touch `screen_state` or `current_screen`. The gate's render-time branch preserves this guarantee.
- `handle_key/2` dispatch pattern: `App.update/2` → `screen_module_for(state.current_screen).handle_key(key, state)`. D-11 inserts a gate check before this dispatch.
- All screens receive `state.terminal_size` and make their own width decisions (`{w, _h} = state.terminal_size || {80, 24}`). These per-screen calls continue to work above the threshold.

### Integration Points
- `app.ex:149` — `render/1` currently composes a modal overlay on top of `view/1`. The gate should run before modal overlay — gated state means no modal either. Planner choice on exact ordering.
- `app.ex:251-254` — same-size guard for `{:window_change, ...}`
- `app.ex:84` — `extract_context` pulls initial `terminal_size`. Already defaults to `{80, 24}` — no change needed.
- `Sessions.Session.set_terminal_size/2` — already called from both `do_update({:window_change, ...})` and `CLIHandler`. Keep both; the same-size guard prevents redundant casts at the App layer but the Session-level cast is idempotent.

### Scope Fencing Notes
- Research Pitfall 4 explicitly calls out the alt-screen + resize trap. This phase resolves the render-time-branch half of the pitfall; alt-screen exit paths are already correct.
- Phase 4's composer work depends on `state.terminal_size` for MultiLineInput width at init (`post_composer.ex:152`, `new_thread.ex:254`). Those init calls are one-shot on screen entry and NOT re-run on resize — Phase 5 does not need to intervene. Add a regression test only.
- The 60×20 floor is more generous than Phase 3's assumption for thread-row density. Thread rows at 60 cols will truncate titles more aggressively per Phase 3 D-03 (`…` fallback). Acceptable: metadata is preserved, title is what truncates.

</code_context>

<specifics>
## Specific Ideas

- **User's mental model:** "60×20 should feel like the minimum a user should need" — accepting that narrow panes look cramped is a reasonable trade-off vs locking out phone-SSH or small-pane users (D-01).
- **Chrome overhead math:** 4 cols / 2 rows (D-02). Derived from Phase 1's ScreenFrame structure (border 1×1 each side = 2 cols + 2 rows; padding 1×1 each side = 2 cols + 2 rows; StatusBar, divider, KeyBar consume 3 rows but 2 fit in the 2-row margin if compact). The exact math is the planner's to validate empirically — if Raxol's padding behaves differently, adjust `@min_cols`/`@min_rows` before shipping.
- **Message copy:** "Foglet BBS requires at least 60×20." — use the "×" character (U+00D7), not lowercase "x", for visual match with classic terminal convention. "Your terminal is currently:" phrasing (not "Your current size is:") to match the research-recommended diagnostic tone.
- **Gate is the only visible action while gated** — no StatusBar, no KeyBar, no border. Deliberate: user needs ONE action (resize), so one message.

</specifics>

<deferred>
## Deferred Ideas

- **Sysop-tunable min dims via Foglet.Config** — Considered; rejected for v1.0.1 (D-03) because the threshold correlates with chrome geometry. Revisit if/when chrome becomes configurable.
- **Hysteresis / anti-flicker band** — e.g., engage gate at 63×21 but release at 65×23. Not needed; same-size guard (D-09) handles the common flicker case and Raxol coalesces renders.
- **Graceful compact layouts for narrow screens** — Explicitly out of scope per research (anti-feature).
- **Per-screen thresholds** — Anti-feature; one threshold is simpler.
- **Time-based debounce on window_change** — Not needed with the same-size guard.
- **Exit / disconnect hint in the gate message** — Considered; rejected because Ctrl+C at the SSH channel layer works regardless and the user already knows how to disconnect.

</deferred>

---

*Phase: 05-terminal-size-gate*
*Context gathered: 2026-04-20*
