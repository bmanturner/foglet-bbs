# Pitfalls Research — phase-03-screen-audit

**Domain:** Retrospective audit of 9 shipped Raxol/Elixir TUI screens (Foglet BBS)
**Researched:** 2026-04-21
**Confidence:** HIGH (grounded in repo source + Phase 03-polish CONTEXT D-01..D-20)
**Scope fence:** Per-screen audits for (a) idiomatic Elixir correctness, (b) primitive/theme adoption. **Sparseness is mandatory** — preserve real estate for Milestones 4/5/6/9.

> These pitfalls are failure modes SPECIFIC to the audit pass. Generic Elixir
> gotchas (block-expression rebind, struct Access, OTP names, preloads, `:string`
> for text, one module per file) are already captured in `CLAUDE.md` and caught
> by `mix precommit`. This file names the ways a polish pass *of already-shipped
> screens* goes sideways.

---

## Critical Pitfalls

### Pitfall 1: Audit drifts into a refactor or feature add

**What goes wrong:**
While auditing `post_reader.ex` for theme hygiene, the auditor notices that
`warm_viewport/4` duplicates markdown parsing logic already in `warm_cache/4`,
and "while I'm in here" refactors both into a shared helper. Three commits
later the audit phase ships a behavior change that touches flush ordering
(`{:flush_read_pointers, ctx}`), invalidating LIST-01 / SSH-09 guarantees that
were validated in `phase-03-polish` Phase 3. Or: auditor decides the main menu
feels empty and adds a "last callers" tease — which is Milestone 4 scope.

**Why it happens:**
Audit work primes the auditor's mental model of the screen deeply enough to
see latent refactor opportunities. The refactor *feels* cheap because the file
is already open. Separately, small screens like `main_menu.ex` (58 LoC, 3 menu
items) trigger the "this looks bare, we have widgets now" reflex.

**How to avoid:**
Each phase's CONTEXT MUST name an explicit scope fence with three lists:

1. **In scope** — theme routing, primitive swaps for existing hand-rolled
   equivalents, idiomatic rewrites of single functions that don't change
   behaviour, `@spec` tightening.
2. **Allowed behaviour changes** — enumerate zero-or-more exceptions with
   explicit justification (e.g., "StatusBar reverse-video regression is
   accepted per 07 D-14/D-15" — cite decision IDs, don't invent new ones).
3. **Out of scope** — all of: adding features, adding Milestone 4/5/6/9
   functionality even when tempting, cross-screen helper hoisting, state-shape
   changes, dispatch-order changes in `App.update/2`, changes to
   `ScreenFrame` / `StatusBar` / `KeyBar` / `SizeGate` (these were locked in
   Phase 03-polish phases 1 + 5).

Success criterion per phase: `git diff` for the phase touches exactly ONE
screen file (+ its test) + incidental widget consumers. If the diff touches
`app.ex`, `size_gate.ex`, `chrome/*.ex`, `theme.ex`, or another screen — the
phase has drifted and MUST split.

**Warning signs:**
- Diff includes a file not in the phase's "touched files" list from CONTEXT.
- Commit message contains "also", "while I was there", "cleaner to".
- Test diff changes existing assertions instead of adding new ones.
- A "helper module" is introduced that didn't exist pre-audit.

**Phase to address:**
Every phase. First item on the Watch List. Reviewed at `/gsd-discuss-plan`.

---

### Pitfall 2: Theme struct mutation via `Map.put` / `%{theme | ...}`

**What goes wrong:**
Auditor tweaks a colour "just for this screen" by mutating the theme struct
before passing it down:

    theme = %{theme | accent: %{theme.accent | fg: "#ffcc00"}}
    PostCard.render_body_lines(tuples, w, theme)

This leaks a non-registered palette into downstream widgets, produces diffs
that the theme-hygiene test (`D-18 bar #2` — "rendering with two distinct
`Foglet.TUI.Theme` fixtures produces different output") can't detect, and
breaks the "single source of truth = `Foglet.TUI.Theme.register_all/0` +
session snapshot" invariant from `theme.ex:1..28`.

**Why it happens:**
The theme struct *looks* mutable because `%Foglet.TUI.Theme{}` is a plain
`defstruct` with map fields. The `|>` pipeline feels natural. Auditor
reaches for `%{t | slot: v}` before realising that slot values themselves
are maps that also need updating.

**How to avoid:**
The audit MUST NOT introduce any `%{theme | ...}` or `Map.put(theme, ...)`
call. Every per-screen colour change goes through either:

1. An existing theme slot (`theme.accent.fg`, `theme.warning.fg`, …) if the
   semantic already exists. Prefer reusing `warning` for "soft error"
   messaging, `dim` for meta, `error` for hard errors.
2. A new slot added to `Foglet.TUI.Theme` (requires a decision log entry,
   escapes the phase boundary — flag for deferral).

Add a `Grep` gate to the phase's verification:
`rg '%\{.*theme.*\|' lib/foglet_bbs/tui/screens/<screen>.ex` must return 0.

**Warning signs:**
- `%{theme | ...}` anywhere in a screen diff.
- A call site passing a bare `%{fg: "#..."}` map to a widget that expects
  `%Theme{}` (Button/Tabs/TextInput all `Keyword.fetch!(opts, :theme)` a
  `%Theme{}` — see `input/button.ex:50`, `input/tabs.ex:81`,
  `input/text_input.ex:93`).
- Hex literals (`"#xxxxxx"`) appearing inside a screen file.

**Phase to address:**
Every phase. Enforced by a per-phase grep gate.

---

### Pitfall 3: Dropping `theme:` keyword arg when swapping primitives

**What goes wrong:**
Auditor replaces a hand-rolled input in `login.ex` / `register.ex` /
`new_thread.ex` with `Widgets.Input.TextInput`, but forgets to pass
`theme:`:

    # hand-rolled:
    text(format_input_line("Handle: ", form.handle, true),
         fg: theme.accent.fg, style: [:bold])

    # attempted swap (BROKEN):
    TextInput.render(input_state, [])
    # → raises KeyError from Keyword.fetch!(opts, :theme) in text_input.ex:93

Or worse, auditor passes a Raxol `ThemeManager`-sourced theme map instead of
`%Foglet.TUI.Theme{}` — which bypasses D-07/D-09 and paints the input with
Raxol's default palette. This is the D-07/D-09 violation that Phase 07
RESEARCH.md §Pitfall 1 explicitly warned about and that we currently have
ZERO regression coverage for.

**Why it happens:**
The hand-rolled path reaches into `theme.accent.fg` inline — no ceremony.
Swapping to a Phase-8 widget means the theme must be passed as an opt. The
argument gets forgotten because it's the last thing added.

**How to avoid:**
When swapping any hand-rolled text/input into a Phase-8 widget:

1. Check the widget's `render/N` signature for `Keyword.fetch!(opts, :theme)`
   (all Phase-8 widgets enforce this — see Button `:50`, Tabs `:81`,
   TextInput `:93`, Table `:121`, Tree, Progress, Spinner).
2. Extract theme at the screen's top-of-render using the existing
   `(Map.get(state, :session_context) || %{}) |> Map.get(:theme) ||
   Theme.default()` idiom (every screen does this — don't invent a new one).
3. Pass `theme: theme` explicitly. The widgets use `Keyword.fetch!` not
   `Keyword.get`, so the crash is loud — but dialyzer will NOT catch a
   forgotten keyword.

Add to each phase's D-18 test bar: "smoke render the screen with a
non-default theme fixture (`Theme.default()` with one slot overridden) and
assert the overridden colour appears in the serialized tree." This catches
both forgotten-keyword and wrong-theme-map bugs.

**Warning signs:**
- A `Widgets.Input.*.render/2` or `Widgets.Display.*.render/2` call without
  a `theme:` keyword.
- `ThemeManager` appearing in any screen file (banned by Phase 07 D-04 and
  Phase 08 D-07/D-09).
- Test fixture using `%{}` as theme instead of `Theme.default()` or a real
  `%Theme{}` build.

**Phase to address:**
Any phase that swaps a hand-rolled widget for a Phase-8 primitive —
currently most likely Phases for `login`, `register`, `verify`, and
`new_thread` (they have hand-rolled `text/2` input lines that could become
`Input.TextInput`). But see Pitfall 11 for WHY that swap should mostly be
rejected.

---

### Pitfall 4: Breaking the D-14 / D-16 widget contract by composition

**What goes wrong:**
Auditor decides `verify.ex` should use `Widgets.Input.TextInput` for the
6-character code buffer. `TextInput` is D-14 (stateful — `init/1 +
handle_event/2 + render/2`), so its state (`raxol_state` map) must live
in `state.screen_state[:verify][:input]`. The auditor instead tries to
compose it inside `Verify.render/1` by calling
`TextInput.init/1 |> TextInput.render(...)` every frame — which rebuilds
the component state on every render, loses `input_state.value`, and
breaks every keystroke. This is the exact "composing stateful widgets
inside a render function" anti-pattern that Raxol's vendored docs warn
against.

Similarly: auditor hoists a stateless widget's "state" to screen state for
"consistency" — e.g., storing a `Button` render struct in screen_state when
the widget has no state struct at all (see `input/button.ex:29` — `@moduledoc`
`D-16 — no state struct`). This creates dead state that survives unmounts,
violates the "stateless widgets expose `render/*` only (D-16)" contract,
and makes the screen harder to reason about.

**Why it happens:**
The D-14 vs D-16 distinction is not enforced by the compiler — it's a
convention documented in `lib/foglet_bbs/tui/widgets/README.md:6..7`.
Auditor reads "stateful widget" and pattern-matches on having a `state`
field to store *something*, without checking the widget module's actual
contract.

**How to avoid:**
Before touching any screen, re-read `widgets/README.md` and mark each
widget the screen uses or might swap in as D-14 or D-16:

| Widget | D-14 (stateful) | D-16 (stateless) |
|---|:-:|:-:|
| `Chrome.ScreenFrame` / `StatusBar` / `KeyBar` | | ✓ |
| `Compose` (glue) | | ✓ |
| `Modal` (thin adapter) | | ✓ |
| `Post.MarkdownBody` / `Post.PostCard` | | ✓ |
| `List.SelectionList` / `List.ListRow` | | ✓ |
| `List.SmartList` | ✓ | |
| `Input.Button` / `Input.Checkbox` / `Input.RadioGroup` | | ✓ |
| `Input.TextInput` / `Input.Tabs` / `Input.Menu` | ✓ | |
| `Display.Table` / `Display.Tree` | ✓ | |
| `Display.Progress` / `Progress.Spinner` | | ✓ |
| `Raxol.UI.Components.Input.MultiLineInput` (used in composer/new_thread) | ✓ | |
| `Raxol.UI.Components.Display.Viewport` (used in post_reader) | ✓ | |

Rule — **D-14 widget state MUST be hoisted to the screen's state struct.**
Reference implementation: `post_reader.ex:241..256` (Viewport's state lives
in `screen_state[:post_reader][:viewport]`) and
`post_composer.ex:149..171` (`MultiLineInput.init/1` result lives in
`screen_state[:post_composer][:input_state]`). Any new D-14 widget goes in
the same place, NOT inside `render/1`.

**Warning signs:**
- `TextInput.init/1` / `Tabs.init/1` / `Table.init/1` / `Tree.init/1`
  appearing inside a `defp render_*` or inside the top-level `render/1`.
- A D-16 widget (Button, Checkbox, RadioGroup, Progress, Spinner) with a
  struct stored in `screen_state`.
- `handle_key/2` without a corresponding state write back into
  `screen_state[:<screen>]` after forwarding to a D-14 widget's
  `handle_event/2`.

**Phase to address:**
Any phase that swaps in Input.Tabs (register?), Input.TextInput (login?
verify?), or Display.Tree (— not applicable to Phase 03 screens, but watch
for cargo-cult introduction).

---

### Pitfall 5: Widget renders its own border/background fighting ScreenFrame chrome

**What goes wrong:**
`Input.TextInput.render/2` (text_input.ex:97), `Input.Tabs.render/2`
(tabs.ex:85), and `Display.Table.render/2` (table.ex:124) each wrap their
output in `box style: %{border_fg: theme.border.fg, padding: 0} do ... end`.
That box adds a visible border. When rendered inside `ScreenFrame`'s
already-bordered `box style: %{border: :single, padding: 1, ...}` chrome
(`chrome/screen_frame.ex:36`), the result is nested borders — a double
outline around the input that fights the BBS aesthetic and eats 2 columns
+ 2 rows of content area at the 64×22 floor.

Same trap with `box style: %{border: :double, padding: 1, ...}` in
`app.ex:174` (modal overlay) — fine because the modal overlay bypasses
`ScreenFrame`, but an auditor who doesn't realize the modal is overlay-mode
may copy the `box do` pattern into a regular screen.

**Why it happens:**
Phase-8 widgets were designed to be usable *with* or *without* ScreenFrame.
Their inner box adds a visual frame that makes them look complete in
isolation (e.g. in the widget gallery demo). Inside a ScreenFrame-wrapped
screen the frames stack.

**How to avoid:**
When integrating a Phase-8 widget into a `ScreenFrame`-wrapped screen,
planner MUST choose one of:

1. **Preferred** — render the widget's inner content directly inside the
   screen's content column without wrapping. For widgets that insist on
   their own `box`, wrap in `column do` with zero padding and accept the
   single extra border as a deliberate visual divider (only when the
   widget is semantically a self-contained surface — e.g. a focused
   form block).
2. **Alternative** — pre-compute inner width as `w - 4` (matches every
   existing screen's inner-width math — see `new_thread.ex:214`,
   `post_composer.ex:157`, `thread_list.ex:41`, `post_reader.ex:35`,
   `register.ex:45`), then size the widget to fit without visible
   overflow-on-narrow-terminal artifacts.

Never introduce a second `box style: %{border: ...}` wrapping inside a
ScreenFrame-wrapped screen unless the intent is an explicit inner surface
(rare; justify in the phase's CONTEXT).

**Warning signs:**
- `box style: %{border: :single, ...}` or `border: :double` inside a
  screen's content tree.
- Grep: `rg 'box style.*border' lib/foglet_bbs/tui/screens/` — should
  return zero matches today (ScreenFrame owns the outer border).
- Visual: screen renders with visibly doubled borders in a 64×22 smoke
  test.

**Phase to address:**
Any phase introducing `Widgets.Input.TextInput`, `Widgets.Input.Tabs`, or
`Widgets.Display.Table`. Most likely to bite `register.ex` (if auditor
tries to replace the single-line input with TextInput) or `verify.ex` (if
auditor tries to replace the 6-char buffer with TextInput, which is
explicitly rejected per 07 D-02).

---

### Pitfall 6: Key dispatch order change silently breaks a screen

**What goes wrong:**
Auditor "cleans up" `post_composer.ex:82..110` key handlers — rewrites the
three top clauses (`:tab`, Ctrl+S, Ctrl+C) and the catch-all `handle_key`
using a `case` or guarded function heads that compile cleanly but reorder
the match arms. Result: Ctrl+S in body-focus inserts `"s"` into the text
instead of submitting, because the fallthrough clause at
`post_composer.ex:87..110` that forwards keys to `MultiLineInput` now runs
before the `Ctrl+S` clause.

Same trap in `new_thread.ex:253..332` — the file has an explicit comment
block (lines 307..314) warning future editors that clause order is
load-bearing: "The Ctrl+C (cancel) and Ctrl+S (submit) clauses at lines
250 and 270 MUST remain above this clause in source order."

**Why it happens:**
Elixir's multi-clause dispatch is order-sensitive. An auditor who
reformats or reorganises a function body to "group related concerns" can
silently reorder clauses. The compiler doesn't warn because every clause
is still exhaustive.

**How to avoid:**
When touching any `handle_key/2` or `handle_*_key/N`:

1. Do NOT reorder clauses. Period. If a refactor requires reordering,
   it's out of audit scope.
2. Preserve the exact key-dispatch order from the current source. Adding
   a clause is fine if it goes in a position that doesn't shadow an
   existing match.
3. Every phase's plan MUST include a key-dispatch smoke test: drive each
   documented key (from the `KeyBar` for that screen) through
   `handle_key/2` on a realistic state fixture and assert the expected
   state transition.
4. For `post_composer.ex` and `new_thread.ex`, preserve the `# NOTE:`
   comment block that documents why the order matters. Do not delete
   this comment as "stale" — it IS the contract.

**Warning signs:**
- Diff moves `handle_key/handle_form_key/handle_compose_key` clauses up
  or down within a file.
- `case` or `cond` replacing a multi-clause function (often framed as
  "more idiomatic", but see Pitfall 14).
- Any diff in `post_composer.ex` that touches lines 82..110 without
  preserving source order of the three explicit-match clauses above the
  catch-all.

**Phase to address:**
`post_composer.ex` (Pitfall 6 hotspot per explicit comment). `new_thread.ex`
(same — explicit source-order comment at 307..314). `login.ex` (form vs
menu dispatch at `login.ex:52..58`). `post_reader.ex` (space vs `n`/`N`
share advance-post semantics and are all before `j`/`J` scroll — order
holds but is load-bearing).

---

### Pitfall 7: Size-gate re-entry loses stateful widget value

**What goes wrong:**
User types 80 characters into `post_composer`, drags the terminal narrow
enough to trigger the size gate (< 64 cols or < 22 rows, per
`size_gate.ex:23..24`), then resizes back. They expect to see their 80
characters. Auditor "helpfully" added a width-aware re-init of
`MultiLineInput` inside `render/1` — on resize, width changed, so
`MultiLineInput.init/1` is called again with the new width, and
`input_state.value` resets to `""`. User loses their draft.

This is the exact pitfall `05-CONTEXT.md` D-13 and its "Claude's
Discretion" section explicitly warned about:
> Phase 5 must NOT rebuild `MultiLineInput` from width on resize
> (research pitfall 4). This is a non-action: the existing
> `composer_screen_state/1` initializer is only called once on entry;
> resize does not flow into it. Planner should add a regression test
> that typing → resize (crossing threshold both ways) → typing preserves
> `input_state.value`.

Current implementation is safe — `post_composer.ex:149..171`
`composer_screen_state/1` is called from `render/1` but the `case
get_in(...)` match at `:153` short-circuits when an existing
`input_state` is present. An auditor who "simplifies" this guard (e.g.
"why the pattern match — just always return a fresh state") breaks it.

**Why it happens:**
The width guard logic *looks* like a defensive null-check that can be
simplified. Auditor doesn't realize the `case %{input_state: _} = ss ->
ss` clause is the re-entry contract.

**How to avoid:**
Any diff to `composer_screen_state/1` (post_composer.ex) or `screen_state/1`
(new_thread.ex:400..403) MUST come with:

1. A regression test matching the `05-CONTEXT.md` D-13 prescription:
   type → resize below gate → resize above gate → type again → assert
   the value contains both typed batches.
2. A CONTEXT note justifying why the guard can be simplified without
   losing the re-entry invariant.

For other screens: confirm that `state.screen_state[:<screen>]` is never
overwritten inside `render/1`. `render/1` MUST be pure read — no
`put_in`, no `Map.put(state.screen_state, ...)`, no `%{state | ...}`.
This is the Raxol MVU contract — see `post_reader.ex:77..82` for the
explicit "render is read-only, state writes happen in
scroll_post/advance_post/load_posts" comment.

**Warning signs:**
- Any `state | ` or `put_in(state.screen_state...)` inside a `defp
  render_*` or inside `render/1`.
- `MultiLineInput.init/1` appearing inside a frequently-called function
  (anywhere other than `init_screen_state/1` or an explicit one-shot
  initializer).
- Truncation logic in `enforce_max_len/2` (post_composer.ex:183..206)
  that calls `MultiLineInput.init/1` on every overflow keypress — this
  is current behaviour and rebuilds state intentionally on overflow, but
  any diff that changes it needs to preserve the "only on overflow"
  guard.

**Phase to address:**
`post_composer.ex`, `new_thread.ex`, `post_reader.ex` (Viewport has
equivalent re-entry concerns — `warm_viewport/4` at :327..337 is width-
aware but called from key handlers, not render). Plus `verify.ex` if
auditor tries to swap the 6-char buffer for TextInput (don't — see 07
D-02).

---

### Pitfall 8: SGR / colour-reset leak on screen transition

**What goes wrong:**
A polish pass on `login.ex`'s `render_login_form/2` changes the `text/2`
calls to emit styled sequences that don't get a clean reset before the
next screen renders. Because Raxol batches frame output, a dangling
`[:bold]` style from the login form bleeds into the first line of the
main menu's "Welcome back, …" text after login succeeds. The bleed is
invisible on most xterm palettes but produces visible "stuck bold" on
minimal terminal emulators (PuTTY, basic SSH clients).

Or: auditor manually writes ANSI escape sequences into a `text/2` string
("just add `\e[0m` to force reset") — which Raxol's buffer layer doesn't
sanitize and which produces double-reset artifacts at line boundaries.

**Why it happens:**
Raxol renders view elements to a buffer and emits SGR codes as needed.
`text/2` with `fg: "..."`, `bg: "..."`, `style: [...]` is the ONLY safe
path. Auditor who wants a "quick fix" for a display bug reaches for raw
ANSI and breaks the abstraction.

**How to avoid:**
Every character emitted by a screen MUST come from a Raxol view element
(`text/2`, `divider/1`, etc.) built via `import Raxol.Core.Renderer.View`.
No raw escape sequences in any screen file. Grep gate:
`rg '\\e\[' lib/foglet_bbs/tui/screens/` must return zero.

For cross-screen transitions: the current design relies on Raxol's
double-buffered frame to issue a full reset between frames — don't
introduce state that persists across a frame boundary (e.g.,
`Logger.debug` calls that emit raw ANSI, or `IO.write` inside a screen).

**Warning signs:**
- `\e[` or `\x1b` anywhere in a screen file.
- `IO.write` / `IO.puts` inside any `Foglet.TUI.Screens.*` module (the
  only writer should be the Raxol renderer driven by `view/1`).
- Any `text/2` with `style:` that isn't one of `[]`, `[:bold]`, `[:dim]`,
  `[:underline]`, `[:reverse]`.

**Phase to address:**
Low-probability, high-impact. Audit each phase with the grep gate; fail
fast. Most at risk: `login.ex`, `register.ex`, `verify.ex` (forms have
focus-state styling that uses `[:bold]`; auditor might reach for
reverse-video and introduce hand-rolled ANSI).

---

### Pitfall 9: Modal intercept lost during audit

**What goes wrong:**
`app.ex:321..334` gates all key dispatch on `state.modal != nil` —
when a modal is open, keys go to `global_key_handler/2`, NEVER to the
screen's `handle_key/2`. Auditor notices a per-screen modal flow
(`post_composer.ex` raises modals on max-length overflow; `login.ex`
raises modals on pending/suspended status) and decides "the screen should
own dismissal." They add `handle_key/2` clauses that inspect
`state.modal` and act on it — but the clauses are unreachable because
`app.ex` dispatches to `global_key_handler/2` before reaching the screen.
Diff compiles; behaviour unchanged; auditor thinks they fixed it; dead
code ships.

Or the inverse: auditor removes a `screen_state: %{}` reset on modal
entry (e.g. `login.ex:278` `%{state | modal: modal, screen_state: %{}}`)
because it "looks like a bug — why clear screen state when we're showing
a modal?" — but that reset is load-bearing. It ensures that dismissing
the modal lands the user on a consistent sub-state (menu, not login form
with stale input).

**Why it happens:**
The modal dispatch contract lives in `app.ex` but its consequences fan
out to every screen that raises modals. The contract isn't documented at
each call site. An auditor reading a single screen can't see the
dispatch rule.

**How to avoid:**
Add to each phase's Watch List an explicit note:
> Modal keys go through `App.global_key_handler/2`, NOT the screen's
> `handle_key/2`. Do not add key clauses that check `state.modal` —
> they will be dead code. When raising a modal from this screen, preserve
> any `screen_state` reset that was paired with the modal raise.

Regression test for every screen that raises a modal: show the modal,
press Enter, assert the modal dismisses AND the screen_state is the
documented post-dismiss shape.

**Warning signs:**
- A screen's `handle_key/2` references `state.modal`.
- A `%{state | modal: ...}` diff that drops an accompanying `screen_state:
  %{}` or `screen_state: Map.delete(...)` clause.
- Any new `defp handle_modal_*` in a screen module (modals are app-layer
  only).

**Phase to address:**
`login.ex` (raises 3 modals — :error on pending, suspended, invalid
credentials; clears `screen_state` with two of them). `post_composer.ex`
(raises :error on empty body, over-max, missing user). `post_reader.ex`
(no modal raise; watch for regression). `verify.ex` (5 modal raise
sites). `register.ex` (3 raise sites — including invite-code failure
that clears `current_input`).

---

### Pitfall 10: Layout white-space gets "filled" because widgets exist now

**What goes wrong:**
`main_menu.ex` is 58 LoC and renders 4 lines of visible content (welcome
+ 3 menu items) inside a 60×15 content area. After Phase 8 shipped all
the widgets, auditor thinks: "we have `Display.Progress`, `Input.Button`,
`Display.Tree`, `Progress.Spinner` — the main menu looks bare compared
to other BBSes. Let me add a session-info panel / unread-count badge /
presence tease / ASCII banner / last-caller spinner." Result: (a)
Milestone 4 / 6 / 9 scope drift, (b) screens can no longer accommodate
their actual future content (Presence will land on main menu; Chat will
claim vertical space; Search has a dedicated screen but shoutbox goes on
main menu).

Same shape: `board_list.ex` shows a `theme.warning.fg` "No boards
subscribed" one-liner when empty (line 30) — auditor adds a `Display.Tree`
preview of available categories as marketing, fills 8 rows. Or: auditor
sees `new_thread.ex` board-picker at `:79` showing a bare
`SelectionList`, wraps it in `Input.Tabs` to "give users a sense of
category grouping" when there are exactly zero product requirements for
that.

**Why it happens:**
The widget library is new (Phase 8), its demos look lush, and an audit
pass feels like the "right time" to show them off. Sparse screens feel
like failure modes when they're actually feature modes.

**How to avoid:**
The sparseness bar for each phase's CONTEXT:

1. **Baseline**: the post-audit screen MUST NOT contain more visible
   content rows than the pre-audit screen, unless a specific row is
   justified by a requirement already in `.planning/PROJECT.md` Active
   list — and that requirement's milestone is the next one up.
2. **Additions allowed**: only (a) widget swaps that *reduce* hand-rolled
   line count, (b) fixing an existing layout bug, (c) sparse affordances
   explicitly named in the phase's CONTEXT.
3. **Reserved space**: each screen's CONTEXT must explicitly name which
   future milestone's content will occupy today's empty space, so the
   auditor knows NOT to fill it. Mapping:

   | Screen | Reserved for |
   |---|---|
   | `main_menu` | Milestone 4 (last callers + news-of-day banner), Milestone 6 (notification badge), Milestone 9 (oneliners/shoutbox) |
   | `board_list` | Milestone 4 (presence roster column or footer), Milestone 6 (mentions/DM unread badges per subscribed board) |
   | `thread_list` | Milestone 5 (chat-room indicator per board), Milestone 6 (mention-in-thread highlight) |
   | `post_reader` | Milestone 6 (reply-thread tree / mention highlights), Milestone 9 (upvote row) |
   | `post_composer` / `new_thread` | Milestone 6 (@handle autocomplete hint row) |
   | `login` / `register` / `verify` | Minimal forever — these are gateways, not surfaces |

**Anti-affordances** the auditor MUST NOT add:
- A decorative `box style: %{border: ...}` around any sub-region that is
  already inside `ScreenFrame` (Pitfall 5 overlap).
- `Display.Table` for 2–3 rows of data — use `SelectionList` or
  `ListRow` (thread_list and board_list already do this correctly, don't
  regress them to Table).
- `Input.Tabs` where the screen has one logical mode (post_composer has
  edit/preview which IS a logical mode — but the current Tab-toggle
  keybinding is already the affordance; adding a visible Tabs bar
  wastes a row).
- `Input.Button` in place of plain `text/2` when there's no click/focus
  interactivity. Buttons live in forms with focus management; menu
  affordances are `text("  [B] Label", ...)` rows — don't upgrade.
- `Progress.Spinner` for "visual interest" on screens that aren't
  waiting on anything. Spinners must always have a semantic "in
  progress" target.
- `Display.Tree` for two-level board→thread nav — we already have a
  two-screen flow (`board_list` → `thread_list`); the tree adds a modal
  decision that doesn't match the navigation model.

**Warning signs:**
- Screen's post-audit rendered row count > pre-audit row count.
- Any `Progress.Spinner` / `Progress.Progress` / `Display.Tree` /
  `Display.Table` / `Input.Button` / `Input.Checkbox` /
  `Input.RadioGroup` / `Input.Tabs` / `Input.Menu` in a screen file.
  (Today: zero of these are used by any screen. The audit should
  preserve that property for all 9 screens unless a named requirement
  demands otherwise.)
- A `column style: %{gap: 1}` (non-zero gap) where `gap: 0` was the
  pre-audit default — gap-1 eats vertical space.

**Phase to address:**
Every phase. This is the single biggest regression risk for this
workstream. `main_menu` is the canonical trap.

---

### Pitfall 11: Replacing primitives that don't have a D-07/D-09-compatible swap

**What goes wrong:**
Auditor sees `login.ex:196..210` render hand-rolled `text/2` lines for
handle + password input (with `█` cursor and `*` masking) and thinks:
"Phase 8 shipped `Input.TextInput`, let me use that." They wire it in,
only to discover that `Input.TextInput`:

1. Wraps output in a `box` with its own border (Pitfall 5).
2. Doesn't implement the `█`-at-cursor style the login form uses (it
   uses Raxol's internal cursor handling, which isn't theme-aware at
   the cursor level in the way our `█` is — see `input/text_input.ex:128..134`
   which only sets `text.fg`, `cursor.fg`, `placeholder.fg`).
3. Is D-14, so its state must be hoisted (`screen_state[:login][:handle_input]`
   and `[:password_input]`) — which requires refactoring the form's
   `:focused_field` dispatch.

After 2 hours of yak-shaving, auditor produces a diff that (a) visually
regresses the form, (b) duplicates state, (c) doesn't save a line of
code. This is the same trap Phase 07 explicitly avoided for the Verify
6-char buffer (`07-CONTEXT.md` D-02: "Kept hand-rolled ... Verify code
buffer [ABC___] 6-char mask display is a deliberate UX choice; text_input
can't reproduce it without a custom renderer").

**Why it happens:**
The Phase 8 widget gallery is visually alluring. The auditor's baseline
is "use primitives wherever possible" — without the accompanying "where
theme and UX are preserved" caveat that Phase 07's theming gate enforced.

**How to avoid:**
Before any primitive swap, the auditor runs a 4-question gate (matches
Phase 07 D-04's "theming gate"):

1. Does the Phase-8 widget accept `%Theme{}` via `theme:`? (Yes for
   all listed in widgets/README.md; no for direct `Raxol.UI.Components.*`.)
2. Does it reproduce the exact visible behaviour of the hand-rolled
   version? (Cursor shape, masking, focus marker, wrap behaviour.)
3. Does it avoid introducing a nested border inside ScreenFrame? (See
   Pitfall 5.)
4. Does the swap reduce line count and/or remove a maintenance hotspot?

If ANY answer is no → keep hand-rolled, document the rejection in the
phase's CONTEXT with a decision entry citing the precedent (07 D-02 for
Verify, 07 D-04 for the theming gate more generally).

**Specific hand-rolled-keepers** (per Phase 07 decisions + sparseness
bar) — DO NOT replace:

| Screen | Keep hand-rolled | Why |
|---|---|---|
| `verify.ex` | 6-char `[ABC___]` buffer | 07 D-02; TextInput can't mask/render |
| `login.ex` | Handle + password `text/2` lines with `█` cursor | Cursor shape + per-field focus bolding beats TextInput visually |
| `register.ex` | Single-line wizard input with `█` cursor | Same as login; masking on :password step |
| `verify.ex` / `login.ex` / `register.ex` | `[R] Register` / `[L] Login` / `[Q] Quit` menu rows | Plain `text/2` is more readable than Button list |
| `main_menu.ex` | `[B] / [C] / [Q]` menu rows | Same reasoning |
| `new_thread.ex` | Title input as single-line `text/2` | Same cursor + focus story as login; 60-char soft cap |
| `post_reader.ex` | `PostCard` + `MarkdownBody` + `Viewport` pipeline | 07 D-02 + D-12 (Viewport is already the Phase-8 swap) |
| All 9 screens | `StatusBar` + `KeyBar` + `ScreenFrame` chrome | Chrome is Phase-1 locked per 01-CONTEXT |

**Warning signs:**
- A diff that deletes `render_login_form/2`, `render_body_step/2`, or
  the hand-rolled `text/2` input lines in favour of a Phase-8 widget.
- `Input.TextInput.init/1` appearing in any screen init.
- Verify / login / register diffs that touch more than theme extraction
  + KeyBar hint polish.

**Phase to address:**
`login.ex`, `register.ex`, `verify.ex`, `new_thread.ex` — the four
screens with hand-rolled input affordances. Bake the
keep-hand-rolled-decision into each phase's CONTEXT so the auditor
doesn't re-litigate.

---

### Pitfall 12: Multi-clause function → `case` "for idiomatic reasons"

**What goes wrong:**
Auditor rewrites `post_reader.ex:99..111` (four `handle_key` clauses for
`n`/`N`/space/page_down/page_up/`p`/`P`/page_up → advance_post) as a
single `handle_key` that pattern-matches on `%{key: k, char: c}` and then
`case`s inside the body. The result:

1. Is 2 more lines, not fewer.
2. Loses compile-time exhaustiveness warnings for unmatched key shapes
   (today, if Raxol adds a new key event, the screen returns `:no_match`
   cleanly; after the rewrite, the internal `case` may raise).
3. Forces dialyzer to re-infer narrower types and may produce new
   warnings about unreachable `true ->` branches.
4. Makes key dispatch order implicit (inside the `case`) rather than
   explicit (as function heads) — harder to audit next time.

**Why it happens:**
"Multi-clause functions with the same name are less idiomatic than a
case" is a common misread of Elixir style. The opposite is true for
event dispatch: multi-clause is the Elixir idiom.

**How to avoid:**
Do not convert multi-clause `handle_key/2` / `handle_*_key/N` dispatchers
into `case` expressions. The current shape is idiomatic.

Conversely: if an auditor finds a screen using a single `handle_key` with
an internal `case`, that IS a valid refactor target — but flag it as
out-of-audit-scope (it's a functional restructuring, see Pitfall 1).

**Warning signs:**
- Diff that converts N function heads into 1 function + `case`.
- `@spec` changes on `handle_key/2` that narrow from multi-pattern to
  single-pattern.
- Dialyzer warnings about "the pattern can never match" after a rewrite.

**Phase to address:**
Any phase where "idiomatic Elixir correctness" is a stated audit goal.
Most at risk: `post_reader.ex` (most key handlers, tempting to
consolidate). `thread_list.ex` and `board_list.ex` (identical j/k/↑/↓
pattern — tempting to DRY across screens; see Pitfall 13).

---

### Pitfall 13: Cross-screen helper hoisting creates coupling without value

**What goes wrong:**
Auditor notices that `board_list.ex:51..54`, `thread_list.ex:77..80`,
`new_thread.ex:201..204` (board picker) all implement identical
j/k/↑/↓-moves-selection logic. They hoist it into `Foglet.TUI.Screens.Nav`
or `Foglet.TUI.Widgets.List.Navigation`. Result:

1. The three screens now share a module that introduces a cross-screen
   coupling with zero functional benefit — each site is 4 lines,
   inlined is more readable.
2. The hoisted module must handle subtle differences:
   `board_list` uses `state.board_list`, `thread_list` uses
   `state.current_thread_list |> sort_threads`, `new_thread` uses
   `ss.boards`. The helper ends up with a `Keyword.get(opts, :source_fn)`
   config, i.e. a function-keyword bag that's harder to read than the
   original.
3. If a fourth screen (e.g. Milestone 7 mod queue) needs similar nav but
   with different edge semantics, the helper grows again.

The repo already shipped Phase 7 D-09's SelectionList pattern: "pure
rendering, no internal state" — and explicitly kept selection-index
handling per-screen. The audit should respect that decision.

**Why it happens:**
Three copies of 4 lines of code look like a DRY violation.

**How to avoid:**
No new shared module introduced during the audit unless:
1. At least 4 screens benefit from it (three is not enough — three is
   the sweet spot where inlining is still cheaper than hoisting), AND
2. The shared semantics are identical — no `opts` / `cb` / `Keyword.get`
   shimming required, AND
3. A requirement in PROJECT.md Active milestones demands it.

Default verdict: keep per-screen duplication. It's load-bearing
documentation.

**Warning signs:**
- A new module in `lib/foglet_bbs/tui/screens/` or `lib/foglet_bbs/tui/`
  that wasn't in the pre-audit tree.
- Existing screens all `alias` a new helper.
- An audit phase touches 3+ screen files in the same commit.

**Phase to address:**
`board_list.ex`, `thread_list.ex`, `new_thread.ex` (nav hoist trap).
`login.ex`, `register.ex`, `verify.ex` (form-state hoist trap — subtly
different shapes across the three).

---

### Pitfall 14: `|>` / `with` / `then` chains replace a short `case`

**What goes wrong:**
Auditor rewrites `login.ex:267..294` (`submit_login/1`) from a `case
Accounts.authenticate_by_password(...)` with explicit handlers per
outcome into a `with` chain. The `with` makes invalid_credentials look
like the "unhappy path" rather than a first-class outcome, and obscures
the modal-raising side-effects for pending/suspended/invalid cases. The
rewrite reads cleanly but makes the control flow less obvious.

Or: `post_composer.ex:252..271` `submit/1` uses `cond do` with three
outcomes — empty, over-max, happy. Auditor rewrites as `with` or a
`|> then(fn draft -> ... end)` chain; the outcome-to-modal mapping gets
buried.

**Why it happens:**
`with` and `|>` feel Elixir-idiomatic. Auditor pattern-matches on "many
`if`s → use `with`" without noticing that the screen's control flow is
explicitly branchy-by-outcome (a `case` *is* the idiom when the outcomes
each drive a different side-effect).

**How to avoid:**
Heuristic for this audit:

- `case`/`cond` with 2–4 outcome clauses, each with a distinct
  state-mutation or command-emission: KEEP. This is Elixir's idiom for
  outcome dispatch.
- `with` chain of 3+ `{:ok, _}` steps in a single pipeline: KEEP.
- `case` with 2 clauses that both return via a shared helper: MAY
  simplify to `case ... do`, but do NOT convert to `with` — with
  implies "happy path" which doesn't apply.

Idiomatic-Elixir rewrites are OUT OF AUDIT SCOPE unless the screen has
a measurable correctness issue — and then it's a correctness fix, not
an idiomatic rewrite. Document either way.

**Warning signs:**
- `case` → `with` conversion.
- Introduction of `|> then(fn x -> ... end)` with a single-clause body.
- `case` → multi-clause function extraction without a clear win.

**Phase to address:**
Every phase. `login.ex`, `register.ex`, `verify.ex` are most at risk
(multi-outcome form submissions). `post_composer.ex` / `new_thread.ex`
(multi-outcome submit). `post_reader.ex` (least at risk; control flow
is already multi-clause functions).

---

### Pitfall 15: `mix precommit` surprises — credo/dialyzer/sobelow drift

**What goes wrong:**
The audit passes local `mix test` but `mix precommit` (the contract per
CLAUDE.md) fails in non-obvious ways:

1. **Credo `--strict`** — surfaces new `Credo.Check.Readability.Specs`
   violations when a function's dispatch shape changes (multi-clause
   function split into a case has a different inferred `@spec`).
   Surfaces `Credo.Check.Refactor.Nesting` when the `cond` →
   nested-`case` rewrite happens (Pitfall 14). Surfaces
   `Credo.Check.Readability.PredicateFunctionNames` when an auditor
   renames `too_small?/1` → `is_too_small/1` (no! — keep `?` for
   predicates).

2. **Dialyzer** — spec drift after a widget swap. Example: hoisting
   `MultiLineInput.init/1` state into a new struct field means the
   screen's `t()` type widens; any caller that destructured the old
   shape fails PLT.

3. **Sobelow** — widget swap that introduces a new data flow from
   `state.current_input` directly into a format string can trigger
   `Config.HTTPS` or `Misc.BinToTerm` warnings. Low probability for
   this audit since it's TUI-only, but the precommit gate runs Sobelow
   and a data-flow change can surface new findings.

4. **Format** — `mix format` after a multi-clause → case rewrite may
   re-flow the `case` body into a different indent pattern, producing
   large whitespace-only diffs that the actual reviewer struggles to
   read.

5. **Compile warnings as errors** — the project runs
   `compile --warnings-as-errors` per CLAUDE.md. A widget swap that
   introduces an unused alias (e.g., old `alias Foglet.TUI.Widgets.List.SelectionList`
   left behind after a hypothetical migration) fails the build.

**Why it happens:**
Precommit gates run different checks than local dev. Auditor's local
edit cycle is `mix test test/foglet_bbs/tui/screens/<screen>_test.exs`,
skipping the broader checks. Issues surface only when a phase hits
`/gsd-verify-work`.

**How to avoid:**
Each phase's Wave 0 MUST include a `mix precommit` gate (not just `mix
test <path>`) before the phase can be marked complete. Latency impact
is ~2–3 minutes (per `08-VALIDATION.md` line 24) — acceptable.

Per-phase watch-list entries:
- After any `@spec` touch, run `mix dialyzer` specifically.
- After any multi-clause dispatch change, run `mix credo --strict` and
  review `Readability.Specs` + `Refactor.Nesting` findings.
- After any widget swap, grep for orphan aliases
  (`rg '^\s*alias Foglet.TUI.Widgets.*\n.*\n'` and visually scan).
- After any diff, run `mix format` standalone and confirm the diff
  doesn't include unrelated whitespace churn.

**Warning signs:**
- Local `mix test` green, first run of `mix precommit` red.
- `mix format` produces a larger diff than expected (> 10 lines of pure
  whitespace).
- Dialyzer finding mentions a type that wasn't touched — usually means
  a downstream spec narrowed.
- Sobelow finds a new path sensitivity after a widget swap.

**Phase to address:**
Every phase, gated at the phase's verification step. Most likely to
bite: widget-swap-heavy phases (`login`, `register`, `new_thread`,
`post_composer`).

---

## Screen-Specific Landmines

Each of the 9 screens has at least one pre-existing complexity that the
auditor should NOT un-complicate without explicit requirements.

### `main_menu.ex` (58 LoC) — `lib/foglet_bbs/tui/screens/main_menu.ex`

- **Sparseness trap (Pitfall 10, critical).** Screen is 3 menu items
  + welcome line. Reserved for Milestone 4 last-callers +
  notifications badge + shoutbox. The auditor MUST NOT fill vertical
  space. If anything, the audit should *trim* (remove the empty `text("")`
  spacer at :22 only if the theme spacing justifies it — verify
  visually first).
- **`@menu_items` duplication (:9..13 + :28..32):** the list is
  declared twice — once for render, once for KeyBar. This is
  load-bearing: the render formats `[K] Label` with spacing, the KeyBar
  renders `K Label` bare. DO NOT DRY into a single list with a
  formatter — it would force the KeyBar to understand the render
  format. Keep separate.
- **`state.terminal_size` default (:42):** `|| {80, 24}` is the
  established idiom across all 9 screens. Do not change to `{64, 22}`
  (the gate floor) — the 80×24 default is the "best-effort sensible
  render when size is absent" contract.

### `login.ex` (347 LoC) — `lib/foglet_bbs/tui/screens/login.ex`

- **Registration-mode gate (:140..147, :238..258, :163..167):**
  `registration_mode(state)` reads from `session_context.registration_mode`
  with a `Config.get` fallback. `keys_for/2` hides `[R] Register` when
  mode is "disabled". Modal flow on `:pending` / `:suspended` status
  clears `screen_state: %{}` (Pitfall 9). Do not touch the dispatch
  path — `submit_login/1` → `handle_active_user/2` →
  `start_verify_flow/2` has a locked 3-step flow.
- **Cursor + masking (:196..226):** hand-rolled `format_input_line`
  with `█` cursor and `mask_password` with `*`. Keep hand-rolled per
  Pitfall 11. Do NOT replace with `Input.TextInput`.
- **Tab focus dispatch (:76..95):** `handle_form_key` intercepts `:tab`
  and `:enter` before falling through to char input. Order is
  load-bearing (Pitfall 6).
- **VERIFY-01 retroactive bypass (:297..308):**
  `post_login_screen/1` returns `:verify` or `:main_menu` based on
  `require_email_verification` config. An auditor who hardcodes
  `:verify` "because the screen is called Login and users without
  verified email shouldn't skip" breaks the post-Milestone-10 flow.
  Leave the dispatch alone.
- **Compile-env log flag (:30, :339..346):** `@log_verify_codes`
  compile-time branch. If absent, the `maybe_log_verify_code/2`
  function clause without `require Logger` applies. Do not collapse
  these two clauses — the compile-env guard IS the feature.

### `register.ex` (294 LoC) — `lib/foglet_bbs/tui/screens/register.ex`

- **Wizard dispatch round-trip (:60..66):** Enter dispatches a
  `{:register_wizard, {:submit_step, ...}}` COMMAND that goes through
  `App.update/2` → `handle_wizard_event/2`. This indirection is the
  testability contract — it lets tests drive the wizard without
  synthetic keystrokes. Do not inline the `advance/4` call directly
  into `handle_key/2`.
- **Modes and first-step routing (:122..124):** `first_step_for/1`
  returns `:invite_code` for `"invite_only"`, else `:handle`. The
  `@modes` list at :23 is the source of truth — adding a mode requires
  touching both `@modes` and `first_step_for/1`. Do not DRY into a
  keyword list or a `@modes_to_first_step` map — the current shape
  reflects that `invite_only` is the only mode with a pre-handle step
  and that may change.
- **Invite code fallback path (:195..209):** `apply(Foglet.Accounts,
  :consume_invite_code, [code])` with `function_exported?` guard — the
  module may not exist yet (per the `# Phase 8 wires real invite code
  generation` comment). The `credo:disable-for-next-line` comment is
  load-bearing. Do not delete the `apply/3` — a direct call
  `Foglet.Accounts.consume_invite_code(code)` emits a compile warning.
- **Sysop-approved terminal modal (:213..230):** returns
  `{:terminate_after_modal, :pending_approval}` — a terminal command
  that ends the session. Preserve this.
- **Changeset error formatting (:282..284):** `Enum.map_join` with
  `"; "` separator. Keep hand-rolled; do not introduce an error module.

### `verify.ex` (271 LoC) — `lib/foglet_bbs/tui/screens/verify.ex`

- **6-char buffer is hand-rolled by decision (07 D-02).** Do NOT
  replace with `Input.TextInput`.
- **Two independent cooldowns (:17..21, :155..159):** `cooldown_until`
  (invalid-attempts, per D-10) vs `resend_cooldown_until` (resend-rate,
  per D-11) are independent. Resend clears `cooldown_until` and
  `attempts` per D-09 — this is a deliberate UX decision, not a bug.
  Preserve.
- **Upper-case coercion on input (:98):** `String.upcase(c)` — entry
  is case-insensitive but storage is upper. Do not refactor into a
  "normalize at submit" pattern.
- **DateTime comparison via stdlib (:151..152, :157..158):** uses
  `DateTime.compare/2` — correct per CLAUDE.md's "prefer Elixir stdlib
  for date/time work; never add a dep unless asked". Do not replace
  with `date_time_parser` — that library is only sanctioned for
  parsing.
- **`submit_raw/1` two clauses (:170..221):** first clause guards
  `current_user: nil`, second handles the real path. Clause order is
  load-bearing (Pitfall 6).

### `board_list.ex` (115 LoC) — `lib/foglet_bbs/tui/screens/board_list.ex`

- **Empty vs loading vs populated (:28..48):** three distinct states.
  Empty uses `theme.warning.fg`, loading uses `theme.dim.fg`, populated
  uses `SelectionList`. Do not collapse into a single ternary — the
  empty-state copy ("No boards subscribed. Ask your sysop …") is
  content-bearing.
- **Unread count staleness:** `board_unread/1` at :108..109 reads
  `board.unread_count` from the board struct. The board struct is
  loaded via `load_boards/1` (:86..91) — which calls the domain
  module (`Foglet.Boards.list_subscribed_boards/1`). The count is
  computed server-side; no caching concern at this layer. BUT: if the
  auditor swaps `SelectionList` for a `Display.Table` and enables
  sorting by unread, they'll discover the count is a snapshot and may
  go stale between the board-list render and the user's board-open.
  Resist the swap (Pitfall 10 anti-feature).
- **`domain_module/2` adapter (:111..114):** test-injection seam. Do
  not inline `Foglet.Boards`.
- **Enter with empty list (:56..58):** `Enum.at(boards, idx)` returns
  `nil` → `:no_match`. Do not rewrite to use `hd/1` or `List.first/1`
  without `nil` guard.

### `thread_list.ex` (196 LoC) — `lib/foglet_bbs/tui/screens/thread_list.ex`

- **Sticky + recency sort (:159..179):** two-pass sort — sticky first,
  then each group sorted by `last_post_at` desc with `nil` sorting
  last via `{0, ts}` / `{1, 0}` tuple trick. Do not simplify — the
  `Enum.sort_by` with ascending + `Enum.reverse` handles the nil-last
  semantics correctly; a naive `desc` sort with nil would crash or
  produce wrong ordering.
- **`list_threads/2` vs `/1` fallback (:130..147):** `cond` on
  `function_exported?` — the 2-arity version supports per-user unread
  annotation, the 1-arity version falls back with
  `annotate_fallback/1` adding `has_unread: false`. This is the
  test-injection + progressive-domain-module pattern. Do not collapse.
- **COMPOSE-01 / COMPOSE-03 pre-fill (:108..120):** `[C]` in
  thread_list skips the board picker (user is already inside a board)
  by pre-filling `step: :compose, board: current_board, boards: nil,
  origin: :thread_list`. Preserve this.
- **`render_thread_row/4` width math (:41):** `inner_width = max(width
  - 4, 40)` — the 40 floor matches `ListRow.@min_title_length` (20) +
  metadata width budget. Do not change 40 without rechecking
  `ListRow.render_with_metadata/6`.

### `post_reader.ex` (425 LoC) — `lib/foglet_bbs/tui/screens/post_reader.ex`

- **Viewport re-entry + width re-warm (:327..337, :394..403):**
  `warm_viewport/4` is width-aware and is called from `scroll_post/2`
  BEFORE issuing `Viewport.update({:set_visible_height, h}, vp)`. This
  is the Phase-7 D-12/D-13 contract — Viewport owns clamping. Do not
  remove the pre-warm: scroll clamping depends on the Viewport
  knowing `content_height`, which only happens after `set_children`
  runs.
- **`render_cache` preservation (:19, 07 D-13 explicit):** keyed on
  `{post.id, width}`. Survives post navigation but cleared on screen
  exit (`handle_key :q`). Do not merge with `viewport` — they have
  different invalidation semantics.
- **Render is pure-read (:77..82 comment):** `render_post_content/5`
  does NOT write back to `screen_state[:post_reader]`. State writes
  happen in `scroll_post`, `advance_post`, `load_posts`. Do not
  inline a `put_in(state.screen_state...)` inside render.
- **LIST-01 D-05 seed on entry (:149..156):** `load_posts/2` seeds
  `read_position[thread_id]` with post 0's `{last_read_post_id,
  last_read_message_number}` so pressing Q immediately still advances
  the board read pointer. "If you saw it, you read it." Do not skip
  the seed.
- **Absorb-keys-during-loading (:346..349, :381..383):**
  `advance_post/2` and `scroll_post/2` short-circuit with `{:update,
  state, []}` when `posts == []`. The intent is documented
  (`absorb … rather than falling through to the global key handler`).
  Keep.
- **`warm_viewport` + `warm_cache` order (:174..176):** warm cache
  first (parses markdown), then warm viewport (needs themed lines).
  Do not swap the order.

### `post_composer.ex` (361 LoC) — `lib/foglet_bbs/tui/screens/post_composer.ex`

- **D-14 re-entry guard (:150..171):** `composer_screen_state/1`
  returns existing `input_state` untouched when present — this is the
  size-gate re-entry contract (Pitfall 7). Do NOT simplify the `case
  %{input_state: _} = ss -> ss` match.
- **`enforce_max_len/2` rebuilds `MultiLineInput` (:183..206):** on
  over-max, truncates and calls `MultiLineInput.init/1` with a plain
  map (not struct — the comment at :188..189 is load-bearing). The
  plain-map vs struct distinction is a Raxol-specific gotcha that
  will bite on refactor.
- **Origin-aware cancel (:319..335):** `Map.get(ss, :origin, :main_menu)`
  — origin is stashed by the navigating screen (PostReader adds
  `origin: :post_reader`, ThreadList adds nothing → default main_menu,
  MainMenu adds `origin: :main_menu`). Do not hardcode.
- **Ctrl+S / Ctrl+C / Tab source order (:82..110):** the three explicit
  clauses MUST precede the catch-all (Pitfall 6). There is no comment
  on this in post_composer; add one during the audit.
- **Max-length config fallback (:341..360):** `safe_config_get/2` with
  rescue-to-default. Do not replace with a direct `Foglet.Config.get!`
  — the `rescue` is the point.

### `new_thread.ex` (435 LoC) — `lib/foglet_bbs/tui/screens/new_thread.ex`

- **Explicit source-order comment (:307..314):** "The Ctrl+C (cancel)
  and Ctrl+S (submit) clauses at lines 250 and 270 MUST remain above
  this clause in source order." DO NOT DELETE this comment. It's the
  Pitfall-6 seat belt.
- **Two-step wizard (:73..77):** `:board` step then `:compose` step.
  Each step has its own render + key-handler pair. Do not collapse
  into one render — the `board` step is only visible from MainMenu.
- **D-14 title cap (:294..303):** soft-cap via config, rejects typing
  past the cap (`:no_match` on overflow). Does not truncate; the cap
  is enforced at input time. Do not change to post-hoc truncation.
- **`put_ss` shape (:405..408):** the screen's state writer is a
  helper. Don't inline.
- **Empty-line placeholder (:171..174):** `Compose.render_input/4`
  with `empty_line_placeholder: " "` — NewThread's legacy single-space
  placeholder for empty lines (Plan 04-01's opt). Do not remove.
- **Cancel/Esc origin-aware (:253..259):** only the compose step uses
  `ss.origin`. Board step always routes to `:main_menu` (only entry
  point). Do not unify.
- **MultiLineInput re-init on board-select (:216..226):** on `:enter`
  from the board step, re-creates the body `MultiLineInput` with the
  current terminal width. This re-init is intentional (user just
  chose board, body hasn't been touched). Do not reuse the
  `:board`-step's `body_input_state` from `init_screen_state/1` —
  width may have changed.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|---|---|---|---|
| DRY j/k/↑/↓ nav helper across screens | –12 LoC | Couples 3 screens; adds opts-bag shim; blocks Milestone 7 mod-queue nav variants | Never during audit (Pitfall 13) |
| Replace hand-rolled `text/2` input with `Input.TextInput` | "Widget adoption" metric goes up | Nested border (Pitfall 5), loses `█` cursor, state must hoist, +state coupling | Only if theme/UX parity is proven AND line count drops |
| `with` chain for multi-outcome form submit | Looks idiomatic | Hides side-effects; implicit "happy path" that doesn't apply | Never for outcome dispatch (Pitfall 14) |
| Inline `Foglet.Boards` / `Foglet.Threads` etc. calls (remove domain-module adapter) | Removes indirection | Breaks test fakes wired via `session_context.domain` | Never — adapter is the test seam |
| Drop the `# NOTE: source order` comment in new_thread or post_composer | Reduces clutter | Next refactor breaks Ctrl+S silently | Never |
| Fill `main_menu` with widgets because it's sparse | Looks "finished" | Blocks Milestones 4/6/9 content | Never (Pitfall 10) |
| Hoist `theme = (Map.get(state, :session_context) \|\| %{}) \|> Map.get(:theme) \|\| Theme.default()` idiom into a `Theme.from_state/1` helper | –1 line per screen × 9 screens = –9 LoC | +1 indirection to trace; obscures that every screen reads theme identically (the repetition IS the contract) | If we land a helper, name it `Theme.from_state/1` and co-locate with `Theme.default/0`; never call it from anywhere but screens |
| Introduce `Foglet.TUI.Screens.Nav` shared key-handler module | –20 LoC | Hides dispatch order; opts-bag hell | Never |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|---|---|---|
| `Raxol.UI.Components.Display.Viewport` | Pass raw post body string as `children:` | Pre-render via `PostCard.render_body_lines/3` first; Viewport expects view elements |
| `Raxol.UI.Components.Input.MultiLineInput` | Pass a struct to `init/1` | `init/1` calls `struct(__MODULE__, props)` which requires an enumerable; pass a plain map (post_composer.ex:188..200 documents this) |
| `Raxol.UI.Components.Input.Tabs` | Assume the widget routes arrow-keys only | Widget consumes `1..9` unconditionally; filter in the parent screen if digits have a different meaning |
| `Raxol.UI.Components.Input.TextInput` | Assume `theme:` is a `%Theme{}` struct | The underlying Raxol component wants a map (`%{text: %{fg:}, cursor: %{fg:}, placeholder: %{fg:}}`); our wrapper builds it via `build_input_theme/1` (text_input.ex:128) |
| `Foglet.Config.get!` | Assume it raises on missing key | Returns `nil` or the stored value; `rescue` idiom in `safe_config_get` is for the exception path only (post_composer.ex:353..360) |
| `Foglet.Accounts.post_login_screen/1` | Assume it always returns `:verify` for unconfirmed users | Returns `:main_menu` when `require_email_verification` is false (VERIFY-01 retroactive bypass); preserve the case expression |
| Raxol `column`/`row` block macros | Assume `style: %{gap: 0}` is the default | Default gap is non-zero in some Raxol builds; ALWAYS pass `style: %{gap: 0}` explicitly when chaining `text/2` elements that should hug |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|---|---|---|---|
| Re-parse markdown on every render | Slow scroll, laggy `j`/`k`; `Foglet.Markdown.render/1` in hot path | `render_cache` keyed on `{post.id, width}` (post_reader.ex:19, 07 D-13) — preserve | Any long post (> 500 chars) on `j`/`k` |
| Re-init MultiLineInput on every keystroke | Input appears to swallow characters or reset cursor | Hoist state to `screen_state`; only init at screen entry (Pitfall 7) | Always — first broken keystroke |
| Sort threads on every render, not just on load | Visible jank when typing scrolls the list | `sort_threads/1` is pure + small (current impl is fine at 100-thread scale); if a board grows past ~1k threads, memoize on `state.current_thread_list` identity | At ~1000 threads per board |
| PubSub subscribe on every render | Duplicate subscriptions; message storm | `subscribe/1` is called by Raxol at mount (`app.ex:182..215`); do NOT add subscribes from screens | Always |
| Render storm on SIGWINCH burst | Rapid resize flickers or renders multiple times | Same-size guard in `do_update({:window_change, ...})` at `app.ex:255..270`; do not remove | Any tmux/iTerm drag |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---|---|---|
| Add a `Progress.Spinner` to main_menu "for life" | Looks like the app is loading something when nothing is happening; distracts from menu | No spinner unless something is in-progress |
| Add `Input.Tabs` to post_composer edit/preview | Replaces a working `Tab` keybinding with a visible bar that eats a row; mode switch is already discoverable via KeyBar | Keep current: `Tab` keybinding + `Tab | Preview/Edit` hint in KeyBar (post_composer.ex:75) |
| Replace `ListRow` unread-bold with a `[N]` badge | Changes the visual grammar mid-workstream; existing users recognize bold-is-unread | Preserve bold; Milestone 6 can add badges for notifications which are a different semantic |
| Add a `Display.Tree` view of boards → threads | Collapses the two-screen `board_list → thread_list` navigation into one; breaks the `Q` / back muscle memory; eats horizontal width | Preserve two-screen nav |
| Pad sparse screens with ASCII banners | Looks BBS-authentic but blocks future content (main_menu reserved for Milestone 4 banner anyway) | Defer to Milestone 4 (login sequence) which owns banner rendering |
| Change keybinding hints on the KeyBar "while I'm in here" | Breaks muscle memory; inconsistent with screens not audited yet | KeyBar hints are part of the locked UI-SPEC; any change needs a decision log entry |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---|---|---|
| Log `input_state.value` in post_composer / new_thread during "debug" | Leaks user-authored content to server logs | No `Logger.debug` / `Logger.info` with `input_state.value` or `current_input`; use `String.length/1` for size-based diagnostics |
| Log verification code (`Logger.info "[verify] code: ..."`) in non-dev configs | Leaks auth code to logs | `@log_verify_codes` compile-env guard (login.ex:30, register.ex:25); ensure this stays `false` outside dev |
| Reveal `invalid_credentials` vs `user_not_found` in the modal | Enumeration attack on handles | Current code returns `{:error, :invalid_credentials}` for both (login.ex:284..293); preserve — do not split error types "for clarity" |
| Reveal resend-cooldown timing on a per-user basis | Timing attack for account enumeration | Current cooldown is per-session; resend is independent of user existence at the UI layer. Don't add a "this email doesn't exist" branch |
| Drop the invite-code validation fallback (register.ex:204..208) | Auditor decides the regex fallback "shouldn't be here in prod" | The `function_exported?` guard means the regex only runs when the real consumer module doesn't exist; leaving it is not a security hole |

---

## "Looks Done But Isn't" Checklist

- [ ] **Theme hygiene:** every colour in the screen diff sources from a
  `theme.*` slot — verify with `rg '"#' lib/foglet_bbs/tui/screens/<screen>.ex`
  returning zero hex literals AND `rg ':red\|:green\|:cyan\|:yellow\|:blue\|:magenta\|:white\|:black' lib/foglet_bbs/tui/screens/<screen>.ex`
  returning zero named-colour atoms.
- [ ] **Source order preserved:** `handle_key/*` clauses in the same
  order as pre-audit; explicit comments (post_composer, new_thread)
  intact.
- [ ] **Screen state re-entry:** for screens with D-14 widgets
  (composer, new_thread, post_reader), a manual test of typing →
  resize below gate → resize above gate → typing produces a combined
  buffer.
- [ ] **Modal dispatch:** no `state.modal` check inside the screen's
  `handle_key/2`; modal raises preserve their paired `screen_state`
  reset.
- [ ] **KeyBar parity:** every key documented in the KeyBar actually
  dispatches; every key that dispatches is in the KeyBar.
- [ ] **Sparseness:** post-audit screen's visible row count ≤ pre-audit
  (or a named requirement justifies the delta).
- [ ] **Precommit clean:** `mix precommit` green end-to-end before
  `/gsd-verify-work`, not just per-file `mix test`.
- [ ] **Grep gates zero:** `rg '\\e\[' lib/foglet_bbs/tui/screens/<screen>.ex`,
  `rg '%\{.*theme.*\|' lib/foglet_bbs/tui/screens/<screen>.ex`,
  `rg 'IO\.(write\|puts\|inspect)' lib/foglet_bbs/tui/screens/<screen>.ex`,
  `rg 'box style.*border' lib/foglet_bbs/tui/screens/<screen>.ex`
  all return zero matches.
- [ ] **No orphan aliases:** the screen's `alias` block contains only
  modules actually referenced in the file.
- [ ] **Domain adapter seam intact:** `ctx[:domain][:boards]`,
  `ctx[:domain][:threads]`, `ctx[:domain][:posts]`,
  `ctx[:domain][:markdown]` pass-through lookups preserved.
- [ ] **Test fixture uses real `%Theme{}`:** no `%{}` theme in any new
  test; use `Theme.default()` or a real palette.
- [ ] **Widget contract:** any introduced D-14 widget has its state
  hoisted to `screen_state`; no D-16 widget has its "state" stored.
- [ ] **Line-count delta negative or neutral:** audit should not grow
  the screen.

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---|---|---|
| Pitfall 1 (scope drift) | MEDIUM | Split the phase; revert the out-of-scope diff; file the refactor as its own follow-up ticket |
| Pitfall 2 (theme mutation) | LOW | Grep for `%{theme \|` and `Map.put(theme`; revert each; add grep gate to phase's verification |
| Pitfall 3 (missing `theme:` kwarg) | LOW | Runtime `KeyError` or `Keyword.fetch!` crash reveals each site; add the kwarg; write the theme-hygiene test that would have caught it |
| Pitfall 4 (D-14/D-16 contract break) | MEDIUM | Hoist the state properly; fix tests; if the widget is D-16, remove the state from `screen_state` |
| Pitfall 5 (nested borders) | LOW | Remove the inner `box style: %{border: ...}`; pre-compute inner width if the widget's chrome was providing it |
| Pitfall 6 (dispatch reorder) | LOW → HIGH | Cheap if test coverage exists; expensive if a user reports "Ctrl+S inserts 's'". Revert to source-order; add an exhaustive key-dispatch smoke test |
| Pitfall 7 (size-gate re-entry) | MEDIUM | Add the prescribed regression test; verify `composer_screen_state/1` guard intact; document the re-entry contract inline |
| Pitfall 8 (SGR leak) | MEDIUM | Grep for `\e[` / `\x1b`; remove raw ANSI; rebuild affected renders through `text/2` |
| Pitfall 9 (modal intercept) | LOW | Remove dead `state.modal` checks from screen handlers; restore dropped `screen_state:` resets at modal-raise sites |
| Pitfall 10 (layout fill) | LOW | Revert the filler; document the reserved-space reason in CONTEXT |
| Pitfall 11 (bad primitive swap) | HIGH | Revert the swap; document in phase CONTEXT that this specific screen keeps the hand-rolled version per precedent |
| Pitfall 12 (multi-clause → case) | LOW | Revert the rewrite |
| Pitfall 13 (cross-screen hoist) | MEDIUM | Inline the helper back per call site; delete the shared module |
| Pitfall 14 (case → with / pipe) | LOW | Revert to case |
| Pitfall 15 (precommit fails) | MEDIUM | Fix each gate's finding; add the gate to Wave 0; re-run |

---

## Pitfall-to-Phase Mapping

The planner will spawn one phase per screen, 9 total, restart numbering
at 1. Every phase addresses pitfalls 1, 2, 3, 10, 15 (universal).
Screen-specific additions below.

| Phase | Screen | Additional pitfalls to watch |
|---|---|---|
| 1 | `login.ex` | 6 (form vs menu dispatch), 8 (form focus styling), 9 (3 modal raises with screen_state clears), 11 (keep hand-rolled cursor + password mask), 14 (`submit_login` multi-outcome) |
| 2 | `register.ex` | 6 (wizard dispatch clauses), 9 (3 modal raises), 11 (keep hand-rolled input + masking), 14 (`advance/4` multi-step) |
| 3 | `verify.ex` | 9 (5 modal raises — cooldowns, expired, invalid), 11 (07 D-02 hand-rolled 6-char buffer), 6 (char coercion + cooldown check order) |
| 4 | `main_menu.ex` | 10 (CRITICAL — single biggest risk for this screen), 13 (don't hoist the 2-duplication menu list) |
| 5 | `board_list.ex` | 10 (empty-state copy), 12 (j/k/↑/↓ four-clause dispatch), 13 (don't hoist nav) |
| 6 | `thread_list.ex` | 10 (reserved for Milestone 5/6 badges), 12 (nav dispatch), 13 (don't hoist nav) |
| 7 | `post_reader.ex` | 4 (Viewport D-14 contract), 6 (many key clauses), 7 (Viewport re-entry), 10 (reserved for Milestone 6 mention highlights + Milestone 9 upvotes), 12 (many multi-clause dispatchers) |
| 8 | `post_composer.ex` | 4 (MultiLineInput D-14), 6 (Ctrl+S before fallthrough), 7 (size-gate re-entry), 14 (`submit/1` multi-outcome cond), add the source-order comment |
| 9 | `new_thread.ex` | 4 (MultiLineInput D-14), 6 (source-order comment already exists — preserve), 7 (re-init on board-select), 14 (`do_submit/2` multi-outcome cond) |

---

## Sources

- `.planning/workstreams/phase-03-polish/phases/05-terminal-size-gate/05-CONTEXT.md` — D-01..D-13, size-gate decisions
- `.planning/workstreams/phase-03-polish/phases/07-migrate-hand-rolled-ui-components-to-raxol-widgets/07-CONTEXT.md` — D-01..D-17, migration + theming gate
- `.planning/workstreams/phase-03-polish/phases/07-migrate-hand-rolled-ui-components-to-raxol-widgets/07-RESEARCH.md` — per-component theming verdicts, Pitfalls 1..5
- `.planning/workstreams/phase-03-polish/phases/08-build-local-widget-library-from-raxol-primitives/08-VALIDATION.md` — D-18 per-widget test bar, precommit sampling
- `lib/foglet_bbs/tui/widgets/README.md` — widget catalog index, D-07/D-09/D-13/D-14/D-16 contracts
- `lib/foglet_bbs/tui/screens/*.ex` — all 9 screens, line-range anchors throughout
- `lib/foglet_bbs/tui/app.ex:140..340` — dispatch order for SizeGate / modal / screen
- `lib/foglet_bbs/tui/size_gate.ex:23..99` — 64×22 floor, render bypass
- `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex:36..52` — chrome box + spacing
- `lib/foglet_bbs/tui/widgets/modal.ex:42..57` — theme-routed modal
- `lib/foglet_bbs/tui/theme.ex:1..70` — slots, registry, session snapshot
- `CLAUDE.md` — project guidelines (precommit, stdlib preference, gotchas)

---

*Pitfalls research for: phase-03-screen-audit — retrospective TUI screen audit*
*Researched: 2026-04-21*
