# Phase 27: Cursor & Breadcrumb Polish - Research

**Researched:** 2026-04-26
**Domain:** Phoenix/Elixir SSH TUI widget rendering and shared chrome routing
**Confidence:** HIGH

## User Constraints

No `27-CONTEXT.md` exists for this phase. [VERIFIED: `rtk gsd-sdk query init.phase-op 27`]

### Locked Decisions

- Phase 27 must address `CURSOR-01` and `BREAD-01`. [VERIFIED: `.planning/REQUIREMENTS.md`]
- Phase 27 depends on Phase 26 because visual verification needs the stable layout canvas. [VERIFIED: `.planning/ROADMAP.md`]
- This is a stabilization milestone, not feature expansion. [VERIFIED: `.planning/STATE.md`]
- Foglet remains SSH-first/TUI-first; no end-user browser workflow should be introduced. [VERIFIED: `AGENTS.md`]

### the agent's Discretion

- No explicit discretion section exists. Use the existing widget/chrome architecture and keep edits narrowly scoped. [VERIFIED: `AGENTS.md`, `lib/foglet_bbs/tui/widgets/README.md`]

### Deferred Ideas (OUT OF SCOPE)

- Browser password reset, Web UI, hardcoded color literals, widget-internal focus state, new authorization scope shapes, forking vendored Raxol, and per-character animations are out of scope. [VERIFIED: `.planning/REQUIREMENTS.md`]

## Summary

Phase 27 should be planned as two small shared-surface repairs: fix cursor placement once in `Foglet.TUI.Widgets.Input.TextInput`, and extend `Foglet.TUI.Widgets.Chrome.BreadcrumbBar.parts_for/1` so auth/Login subflows expose the correct breadcrumb path. Current TextInput already delegates input mutation to vendored Raxol and stores `raxol_state.cursor_pos`, but Foglet renders a leading `"▌ "` before the input instead of inserting a cursor at the insertion point. [VERIFIED: `lib/foglet_bbs/tui/widgets/input/text_input.ex`, `vendor/raxol/lib/raxol/ui/components/input/text_input.ex`]

The breadcrumb issue is also centralized: `ScreenFrame` defaults `breadcrumb_parts` from `BreadcrumbBar.parts_for(state)`, while `BreadcrumbBar` currently maps `:login` to only `["Foglet", "Login"]` and has no explicit mapping for `:register` or `:verify`. Login has internal sub-states `:menu`, `:login_form`, and `:reset_request`; Register and Verify are separate screens that return to `:login` on Escape. [VERIFIED: `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex`, `lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex`, `lib/foglet_bbs/tui/screens/login.ex`, `lib/foglet_bbs/tui/screens/register.ex`, `lib/foglet_bbs/tui/screens/verify.ex`]

**Primary recommendation:** implement cursor and breadcrumb behavior at the shared widget/chrome boundary, then add focused unit tests plus layout-smoke coverage at 64x22 and 80x24. [VERIFIED: codebase grep]

<phase_requirements>

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CURSOR-01 | TextInput renders a cursor following the active insertion point across Login, Register, Forgot Password, Verify, Account, and Sysop screens. | TextInput already stores `cursor_pos`; render should split masked/display text with `TextWidth` and insert a themed marker at the focused cursor position. [VERIFIED: `TextInput`, vendored Raxol] |
| BREAD-01 | Shared chrome breadcrumb updates for Login Register/Forgot/Verify/reset-consume sub-states and returns to Login on back. | `BreadcrumbBar.parts_for/1` is the central mapping consumed by `ScreenFrame`; extend it for auth screens and Login sub-states. [VERIFIED: `BreadcrumbBar`, `ScreenFrame`] |

</phase_requirements>

## Project Constraints (from AGENTS.md)

- Use `rtk` as the shell command prefix in this repo, for example `rtk mix test`. [VERIFIED: `AGENTS.md`]
- Foglet is SSH-first; Phoenix is infrastructure, so do not add browser workflows. [VERIFIED: `AGENTS.md`]
- For TUI/Raxol work, consult `docs/raxol/getting-started/WIDGET_GALLERY.md` and `lib/foglet_bbs/tui/widgets/README.md`. [VERIFIED: `AGENTS.md`]
- Keep UI behavior in `Foglet.TUI.App` and screens; widgets must remain reusable primitives. [VERIFIED: `AGENTS.md`]
- Widgets route colors through `Foglet.TUI.Theme`, accept theme explicitly, and keep render functions pure over loaded state. [VERIFIED: `AGENTS.md`, widget README]
- Stateful widgets expose `init/1`, `handle_event/2`, and `render/2`; stateless widgets expose render functions. [VERIFIED: widget README]
- Focus state belongs to screens or sibling state modules, not hidden widget-internal ownership. [VERIFIED: `.planning/REQUIREMENTS.md`, `AGENTS.md`]
- Run `mix precommit` when code changes are complete. [VERIFIED: `AGENTS.md`]

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| TextInput cursor rendering | Browser / Client equivalent: SSH TUI widget layer | Raxol component state | The terminal UI render tree owns visible cursor placement; Raxol owns mutation/cursor index. [VERIFIED: local code] |
| Login/auth breadcrumb path | Browser / Client equivalent: shared TUI chrome | Screen state | `ScreenFrame` calls `BreadcrumbBar.parts_for(state)` centrally; screens only maintain `current_screen` and `screen_state`. [VERIFIED: local code] |
| 64x22/80x24 visual reliability | Browser / Client equivalent: TUI layout engine tests | Test support helpers | Existing layout smoke tests run render trees through `Raxol.UI.Layout.Engine.apply_layout/2`. [VERIFIED: `test/foglet_bbs/tui/layout_smoke_test.exs`] |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Elixir/Mix | 1.19.5 available in environment | Build/test runner | Project uses Mix aliases and ExUnit. [VERIFIED: `rtk mix help`] |
| Raxol | vendored path dependency; Hex latest listed as 2.4.0 | TUI component/render system | Foglet wraps Raxol components in local themed widgets; vendored source exposes TextInput `cursor_pos`. [VERIFIED: `mix.exs`, `vendor/raxol`, `rtk mix hex.info raxol`] |
| ExUnit | bundled with Mix | Unit and integration tests | Existing tests cover widgets, screens, and layout smoke. [VERIFIED: `test/foglet_bbs/tui/...`] |
| `Foglet.TUI.TextWidth` | local module | Terminal cell width math | Existing helper wraps `Raxol.UI.TextMeasure` for `display_width`, `split_at`, truncation, and padding. [VERIFIED: `lib/foglet_bbs/tui/text_width.ex`] |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Phoenix | `~> 1.8.5` | App infrastructure | No phase work should touch browser/Phoenix UI. [VERIFIED: `mix.exs`, `AGENTS.md`] |
| Bodyguard | `~> 2.4` | Authorization | Not directly involved; avoid adding new auth scope shapes. [VERIFIED: `mix.exs`, `.planning/REQUIREMENTS.md`] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Local TextInput render split | Patch/fork vendored Raxol TextInput | Out of scope: v1.4 explicitly excludes forking vendored Raxol; Foglet wrapper can satisfy the requirement without changing dependency behavior. [VERIFIED: `.planning/REQUIREMENTS.md`] |
| Central BreadcrumbBar mapping | Per-screen breadcrumb override maps | Central mapping is already the shared Chrome V2 contract and avoids duplicated auth path logic. [VERIFIED: `ScreenFrame`, `BreadcrumbBar`] |

**Installation:** no new package installation is needed. [VERIFIED: `mix.exs`]

## Architecture Patterns

### System Architecture Diagram

```text
SSH key/input event
  -> Foglet.SSH.CLIHandler
  -> Foglet.TUI.App routes to current screen
  -> Screen-local handle_key updates TextInput / sub-state
  -> Screen render calls TextInput.render(... focused: ...)
  -> TextInput splits display text at raxol_state.cursor_pos
  -> Raxol render tree
  -> terminal cells show cursor at insertion point

App state
  -> ScreenFrame.render(state, ...)
  -> BreadcrumbBar.parts_for(state)
  -> screen/sub-state decision
     -> :login + :menu => Foglet > Login
     -> :login + :reset_request => Foglet > Login > Forgot Password
     -> :login + :reset_consume => Foglet > Login > Forgot Password > Enter Token
     -> :register => Foglet > Login > Register
     -> :verify => Foglet > Login > Verify
  -> truncated/formatted chrome row
```

### Recommended Project Structure

```text
lib/foglet_bbs/tui/
├── widgets/input/text_input.ex          # cursor rendering repair
├── widgets/chrome/breadcrumb_bar.ex     # auth breadcrumb mapping
├── screens/login.ex                     # only if :reset_consume stub/state is needed for BREAD-01
└── text_width.ex                        # existing display-width primitive; do not duplicate

test/foglet_bbs/tui/
├── widgets/input/text_input_test.exs    # cursor unit contract
├── widgets/chrome/breadcrumb_test.exs   # auth breadcrumb paths
├── screens/login_test.exs               # state transitions and breadcrumb integration
└── layout_smoke_test.exs or helpers     # 64x22/80x24 render coverage
```

### Pattern 1: Cursor Is a Render Concern, Not Input Mutation

**What:** Keep using Raxol TextInput for mutation and cursor index, then render Foglet's visible cursor by splitting the masked display text at `raxol_state.cursor_pos`. [VERIFIED: `vendor/raxol/lib/raxol/ui/components/input/text_input.ex`]

**When to use:** Every single-line Foglet `TextInput.render/2` call with `focused: true`. [VERIFIED: codebase grep]

**Example:**

```elixir
# Source: local Foglet/Raxol TextInput contracts
left = TextWidth.slice_to_width(display_text_prefix, cursor_cell_width)
row style: %{gap: 0} do
  [
    text(left, fg: theme.primary.fg),
    text("▌", fg: theme.accent.fg, style: [:bold]),
    text(right, fg: theme.primary.fg)
  ]
end
```

### Pattern 2: Breadcrumb Parts Come From Central State Mapping

**What:** Add auth-specific clauses to `BreadcrumbBar.parts_for_screen/2` and a small helper for Login sub-state. [VERIFIED: `BreadcrumbBar.parts_for/1`]

**When to use:** Any phase that changes shared chrome path semantics. [VERIFIED: `ScreenFrame.normalize_chrome/2`]

**Example:**

```elixir
# Source: local BreadcrumbBar contract
defp parts_for_screen(state, :login), do: login_parts(state)
defp parts_for_screen(_state, :register), do: [@root, "Login", "Register"]
defp parts_for_screen(_state, :verify), do: [@root, "Login", "Verify"]
```

### Anti-Patterns to Avoid

- **Prefix cursor marker:** Rendering `"▌ "` before the input proves focus but not insertion point; it fails CURSOR-01 after cursor movement or backspace. [VERIFIED: current `TextInput.render/2`]
- **Hardcoded per-screen cursor fixes:** Account, Sysop, Register, and Login all reuse `TextInput`; fix the widget once. [VERIFIED: codebase grep]
- **Breadcrumb title-only checks:** `ScreenFrame.render(state, "Register", ...)` does not change `BreadcrumbBar.parts_for/1`; tests must assert breadcrumb parts/text, not just screen title. [VERIFIED: `ScreenFrame`, screen render code]
- **Changing Raxol cursor state semantics:** Raxol uses character indexes, while success criteria requires cell-width verification through `TextWidth.display_width`; preserve state and adapt rendering. [VERIFIED: vendored Raxol, requirements]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Terminal width math | Custom byte/string length cursor math | `Foglet.TUI.TextWidth` | Handles terminal display width and delegates primitive measurement to Raxol. [VERIFIED: `TextWidth`] |
| Text mutation/key handling | New input editor | Existing Raxol TextInput through Foglet wrapper | Raxol already handles char insertion, backspace, delete, left/right/home/end. [VERIFIED: vendored Raxol] |
| Chrome path formatting/truncation | Per-screen breadcrumb strings | `BreadcrumbBar.format/2` and `parts_for/1` | Existing separator, ASCII fallback, and truncation behavior should remain shared. [VERIFIED: `BreadcrumbBar`] |
| Full terminal visual test harness | New screenshot pipeline | Existing render helpers/layout smoke tests | Existing tests already apply Raxol layout engine to render trees. [VERIFIED: `layout_smoke_test.exs`] |

**Key insight:** the required behavior is already close to existing abstractions; hand-rolled per-screen fixes would increase drift right before Phase 28-31 form/auth work depends on visual reliability. [VERIFIED: roadmap dependencies]

## Common Pitfalls

### Pitfall 1: Character Position vs Cell Position

**What goes wrong:** `cursor_pos == 3` is true but the rendered cursor lands at the wrong terminal column for wide or combining graphemes. [VERIFIED: CURSOR-01 cites `TextWidth.display_width`]

**Why it happens:** Vendored Raxol cursor navigation stores character index; terminal layout cares about cell width. [VERIFIED: vendored Raxol]

**How to avoid:** Tests should compute the rendered prefix width with `TextWidth.display_width`, not `String.length`. [VERIFIED: `TextWidth`]

**Warning signs:** Tests pass for `"abcde"` but no test covers `"あ"` or combining `é`. [VERIFIED: Phase 26 width-helper requirement]

### Pitfall 2: Masked Password Cursor Uses Raw Value Length

**What goes wrong:** A password field renders raw text or cursor split mismatches the mask. [VERIFIED: existing mask test]

**Why it happens:** Raxol render computes masked display separately from `value`; Foglet cursor rendering must do the same. [VERIFIED: vendored Raxol]

**How to avoid:** Build display text from `mask_char`, `value`, and `placeholder` before splitting. [VERIFIED: vendored Raxol]

**Warning signs:** `inspect(rendered)` contains `"secret"` when `mask_char: "*"` is set. [VERIFIED: existing test]

### Pitfall 3: Placeholder Cursor on Empty Focused Inputs

**What goes wrong:** A focused empty input shows a cursor after placeholder text, or both placeholder and cursor in an ambiguous order. [ASSUMED]

**Why it happens:** Raxol displays placeholder when value is empty; insertion point for an empty value is column 0. [VERIFIED: vendored Raxol]

**How to avoid:** For focused empty input, show cursor at column 0 and only then placeholder text in dim style if retained. [ASSUMED]

**Warning signs:** `flatten_text(focused_empty)` starts with placeholder instead of cursor. [ASSUMED]

### Pitfall 4: Breadcrumb State Is Split Across Screens and Sub-States

**What goes wrong:** Register/Verify show `Foglet` or `Foglet > Register` instead of preserving Login ancestry. [VERIFIED: current `BreadcrumbBar` lacks clauses]

**Why it happens:** Register and Verify are separate screens, while Forgot Password is a Login sub-state. [VERIFIED: screen code]

**How to avoid:** Add explicit auth-screen clauses and Login sub-state mapping in `BreadcrumbBar`. [VERIFIED: `ScreenFrame` central call]

**Warning signs:** Escape returns to Login but breadcrumb tests never assert the intermediate path. [VERIFIED: existing tests]

## Code Examples

### Cursor Backspace Contract

```elixir
# Source: Phase requirement + existing TextInput event contract
state =
  Enum.reduce(String.graphemes("abcde"), TextInput.init([]), fn ch, st ->
    {next, _} = TextInput.handle_event(%{key: :char, char: ch}, st)
    next
  end)

{state, _} = TextInput.handle_event(%{key: :backspace}, state)
{state, _} = TextInput.handle_event(%{key: :backspace}, state)

assert state.raxol_state.cursor_pos == 3
rendered = TextInput.render(state, focused: true, theme: Theme.default())
assert cursor_prefix_width(rendered) == TextWidth.display_width("abc")
```

### Breadcrumb Auth Paths

```elixir
# Source: Phase BREAD-01 and current BreadcrumbBar API
assert BreadcrumbBar.parts_for(%{current_screen: :register}) ==
         ["Foglet", "Login", "Register"]

assert BreadcrumbBar.parts_for(%{
         current_screen: :login,
         screen_state: %{login: %{sub: :reset_consume}}
       }) == ["Foglet", "Login", "Forgot Password", "Enter Token"]
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Leading focus marker before every focused TextInput | Cursor rendered at insertion point using TextInput state and cell-width-aware tests | Phase 27 target | Makes later form/auth visual verification meaningful. [VERIFIED: roadmap] |
| Screen title as implicit location | Shared Chrome V2 breadcrumb derived centrally | Phase 18/Chrome V2 already established | BREAD-01 should extend central mapping only. [VERIFIED: `BreadcrumbBar`] |

**Deprecated/outdated:**

- Prefix cursor marker before input text: replace with insertion-point render. [VERIFIED: current test names and requirement]
- Login-only breadcrumb for auth flows: replace with auth ancestry paths. [VERIFIED: BREAD-01]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Focused empty inputs should render cursor at column 0 before placeholder text if placeholder is retained. | Common Pitfalls | Cursor UX may need product confirmation; planner should include a test and adjust expected text if UX differs. |

## Open Questions

1. **Should Phase 27 create the `:reset_consume` Login sub-state, or only make BreadcrumbBar recognize it?**
   - What we know: Phase 31 owns reset-token consume behavior, but BREAD-01 explicitly names the new `:reset_consume` sub-state. [VERIFIED: roadmap]
   - What's unclear: Whether Phase 27 should add a navigable placeholder state or only breadcrumb support for a future state.
   - Recommendation: Add breadcrumb support and a minimal Login menu transition only if required for BREAD-01 visual verification; leave token form/domain behavior to Phase 31. [ASSUMED]

2. **Does Verify count as a TextInput surface?**
   - What we know: Verify uses a custom 6-character slot buffer and explicitly says shared TextInput cannot reproduce that visualization. [VERIFIED: `lib/foglet_bbs/tui/screens/verify.ex`]
   - What's unclear: CURSOR-01 wording includes Verify, but current Verify is not a single-line `TextInput`.
   - Recommendation: Do not convert Verify in Phase 27; treat its custom slot cursor separately unless the planner/user decides CURSOR-01 requires a true TextInput there. [ASSUMED]

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| `rtk` | Required command prefix | yes | available | none |
| Mix/Elixir | Tests and precommit | yes | Mix 1.19.5 | none |
| Raxol vendored source | TUI render/input behavior | yes | path dependency; Hex latest 2.4.0 | use local vendor source |
| PostgreSQL test DB | Full `rtk mix test` alias | not probed | - | unit tests that do not need DB for widget/chrome |

**Missing dependencies with no fallback:** none found for research. [VERIFIED: command probes]

**Missing dependencies with fallback:** PostgreSQL was not probed during research; widget/chrome tests can run without app-level DB setup if targeted directly, but the project test alias may require DB. [ASSUMED]

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | ExUnit via Mix |
| Config file | `test/test_helper.exs` and Phoenix/DataCase support |
| Quick run command | `rtk mix test test/foglet_bbs/tui/widgets/input/text_input_test.exs test/foglet_bbs/tui/widgets/chrome/breadcrumb_test.exs test/foglet_bbs/tui/screens/login_test.exs` |
| Full suite command | `rtk mix precommit` |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| CURSOR-01 | typing five chars and backspacing twice leaves cursor at cell column 3; blur/disabled hides cursor | widget unit | `rtk mix test test/foglet_bbs/tui/widgets/input/text_input_test.exs` | yes |
| CURSOR-01 | focused TextInput cursor renders across Login/Register/Account/Sysop at 64x22 and 80x24 | layout smoke/integration | `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` | yes |
| BREAD-01 | Login/Register/Forgot/Verify/reset-consume breadcrumb paths | widget + screen unit | `rtk mix test test/foglet_bbs/tui/widgets/chrome/breadcrumb_test.exs test/foglet_bbs/tui/screens/login_test.exs` | yes |

### Sampling Rate

- **Per task commit:** targeted widget/chrome/screen tests above.
- **Per wave merge:** `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs`.
- **Phase gate:** `rtk mix precommit` before verify.

### Wave 0 Gaps

- [ ] Add cursor-position assertions to `test/foglet_bbs/tui/widgets/input/text_input_test.exs`.
- [ ] Add auth-path breadcrumb assertions to `test/foglet_bbs/tui/widgets/chrome/breadcrumb_test.exs`.
- [ ] Add or extend layout smoke cases for focused single-line inputs on Login, Register, Account Profile, Account Preferences, and Sysop Site at 64x22 and 80x24.

## Sources

### Primary (HIGH confidence)

- `.planning/STATE.md` - v1.4 decisions, milestone scope, recent quick fixes.
- `.planning/ROADMAP.md` - Phase 27 goal, dependencies, success criteria.
- `.planning/REQUIREMENTS.md` - CURSOR-01, BREAD-01, out-of-scope constraints.
- `AGENTS.md` - project architecture and workflow constraints.
- `docs/raxol/getting-started/WIDGET_GALLERY.md` - Raxol TextInput component pattern.
- `lib/foglet_bbs/tui/widgets/README.md` - Foglet widget contracts.
- `lib/foglet_bbs/tui/widgets/input/text_input.ex` - current Foglet TextInput wrapper.
- `vendor/raxol/lib/raxol/ui/components/input/text_input.ex` - Raxol TextInput state/render/key behavior.
- `lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex` - shared breadcrumb implementation.
- `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex` - breadcrumb integration point.
- `lib/foglet_bbs/tui/screens/login.ex`, `register.ex`, `verify.ex` - auth state and transitions.
- `lib/foglet_bbs/tui/text_width.ex` - display-width helper.

### Secondary (MEDIUM confidence)

- `rtk mix hex.info raxol` - registry summary says Hex latest is 2.4.0, while this project uses vendored path dependency.
- Existing tests under `test/foglet_bbs/tui/...` - test infrastructure and patterns.

### Tertiary (LOW confidence)

- None.

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH - verified from `mix.exs`, vendored source, and Mix/Hex commands.
- Architecture: HIGH - shared widget and chrome paths verified directly in local code.
- Pitfalls: MEDIUM - core pitfalls are verified; empty-placeholder cursor UX and reset-consume ownership need planner/user confirmation.

**Research date:** 2026-04-26
**Valid until:** 2026-05-26 for local architecture; re-check Raxol docs if vendored dependency changes.
