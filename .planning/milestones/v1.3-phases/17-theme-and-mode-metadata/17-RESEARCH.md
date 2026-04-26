# Phase 17: Theme and Mode Metadata - Research

**Researched:** 2026-04-25
**Domain:** Elixir/Raxol terminal UI metadata and semantic theming contracts
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
## Implementation Decisions

### Mode Contract
- **D-01:** Implement the presentation-mode contract as a shared TUI-level API keyed by existing screen ids, rather than deriving mode inside individual render functions.
- **D-02:** The only supported presentation modes are exactly `:bbs` and `:operator`.
- **D-03:** Unsupported or unknown screen ids must be handled deliberately, with focused tests proving the behavior.

### Screen Mode Coverage
- **D-04:** Lock mode declarations for every current TUI screen id, not only the screens named in `SCREENS.md`.
- **D-05:** `:login`, `:register`, `:verify`, `:main_menu`, `:board_list`, `:thread_list`, `:post_reader`, `:new_thread`, and `:post_composer` resolve to `:bbs`.
- **D-06:** `:account`, `:moderation`, and `:sysop` resolve to `:operator`.
- **D-07:** Register and Verify are included because the mode contract should cover all current app-routed screens; they follow the BBS/authentication rhythm rather than the operator-console rhythm.

### Theme Slot Extension
- **D-08:** Add `success`, `info`, and `badge` as first-class fields in `%Foglet.TUI.Theme{}`, the `@type t`, `@slot_keys`, and every existing palette map.
- **D-09:** Initially synthesize the new semantic slots from existing palette colors where appropriate; do not retune palettes or perform contrast redesign in Phase 17.
- **D-10:** `Theme.resolve/1`, `Theme.default/0`, and `Theme.from_state/1` must return snapshots with non-empty `success`, `info`, and `badge` maps for every existing theme id.

### Theme Mapping Contract
- **D-11:** Capture tab, row, badge, command hint, and editor-state mappings as a project-local contract with tests that validate referenced slot names against `Foglet.TUI.Theme`.
- **D-12:** Do not implement new `Display.Badge`, `List.RichRow`, `Chrome.CommandBar`, `Composer.EditorFrame`, table preset, inspector, or visible layout-conversion behavior in this phase.
- **D-13:** Mapping coverage must include selected/unselected tabs, row selected/unread/normal/metadata/disabled states, badge info/success/warning/error/accent states, command group/key/destructive/inactive states, and editor focus/counter states.

### Theme Independence
- **D-14:** Mode resolution must ignore `state.session_context.theme`, `theme_id`, Account theme preview state, and any active palette data.
- **D-15:** User-selected theme changes color treatment only; it must not change a screen's presentation mode or layout category.

### Claude's Discretion
- Exact module name and public function names for the mode contract are planner discretion, provided downstream code has one documented source of truth for screen-to-mode resolution.
- Exact file location for the theme mapping contract is planner discretion. It may live in code, docs, or both, as long as tests can prove referenced slots exist on `Foglet.TUI.Theme`.

### Folded Todos
None.

### Deferred Ideas (OUT OF SCOPE)
## Deferred Ideas

None - discussion stayed within phase scope.

### Reviewed Todos (not folded)
None.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MODE-01 | TUI screens can declare Classic Modern BBS or Operator Console presentation mode without forking the widget stack. | Use one TUI-level screen-mode contract keyed by `Foglet.TUI.App.screen()` ids; do not branch inside render functions. [VERIFIED: `.planning/REQUIREMENTS.md`; `.planning/phases/17-theme-and-mode-metadata/17-CONTEXT.md`; `lib/foglet_bbs/tui/app.ex`] |
| THEME-01 | Theme slots cover success, informational, badge, selected, dim, warning, error, and accent states needed by facelift widgets. | Extend `%Foglet.TUI.Theme{}` and every palette map with `success`, `info`, and `badge`; existing slots already include selected, dim, warning, error, and accent. [VERIFIED: `.planning/REQUIREMENTS.md`; `lib/foglet_bbs/tui/theme.ex`] |
| THEME-02 | Tabs, rows, badges, command hints, and editor states have documented and tested theme-slot mappings without hardcoded color atoms. | Add a project-local mapping contract and tests that validate all referenced slots are members of `Foglet.TUI.Theme.slot_keys/0` or an equivalent public accessor. [VERIFIED: `.planning/phases/17-theme-and-mode-metadata/17-SPEC.md`; `SCREENS.md`; `lib/foglet_bbs/tui/widgets/README.md`] |
</phase_requirements>

## Summary

Phase 17 is a contract phase, not a visible facelift phase. The established architecture is to keep cross-cutting TUI contracts under `lib/foglet_bbs/tui/`, keep screen-local rendering in screen modules, and pass `%Foglet.TUI.Theme{}` explicitly into widgets. [VERIFIED: `CLAUDE.md`; `lib/foglet_bbs/tui/screen.ex`; `lib/foglet_bbs/tui/widgets/README.md`] The planner should add one small shared mode/mapping contract and extend the existing `Foglet.TUI.Theme` registry, while leaving Chrome V2, rich rows, badges, command bars, editor frames, and screen layout conversions to later phases. [VERIFIED: `.planning/phases/17-theme-and-mode-metadata/17-CONTEXT.md`; `.planning/phases/17-theme-and-mode-metadata/17-SPEC.md`]

**Primary recommendation:** Add `Foglet.TUI.Presentation` for `mode_for!/1` plus theme mapping metadata, and add `success`, `info`, and `badge` to `Foglet.TUI.Theme` as first-class slots across every palette. [VERIFIED: `lib/foglet_bbs/tui/app.ex`; `lib/foglet_bbs/tui/theme.ex`; `SCREENS.md`]

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Screen mode resolution | TUI runtime | Screens | Mode is product metadata keyed by `current_screen`; render functions should consume the contract later, not derive it locally. [VERIFIED: `lib/foglet_bbs/tui/app.ex`; `.planning/phases/17-theme-and-mode-metadata/17-CONTEXT.md`] |
| Theme slot registry | TUI theme infrastructure | Raxol theme registry | Foglet already stores palette slot maps in `Foglet.TUI.Theme` and registers them into Raxol component styles. [VERIFIED: `lib/foglet_bbs/tui/theme.ex`; `docs/raxol/cookbook/THEMING.md`] |
| Widget state-to-slot mapping | TUI contract | Widget tests | Existing widgets already map states to theme slots; Phase 17 should document and test the future mapping before later widgets consume it. [VERIFIED: `SCREENS.md`; `lib/foglet_bbs/tui/widgets/input/tabs.ex`; `lib/foglet_bbs/tui/widgets/list/list_row.ex`; `lib/foglet_bbs/tui/widgets/chrome/key_bar.ex`] |
| Theme independence from mode | TUI metadata contract | Account theme preview tests | Account preview mutates candidate theme state; mode resolution must depend only on screen id. [VERIFIED: `test/foglet_bbs/tui/screens/account_test.exs`; `.planning/phases/17-theme-and-mode-metadata/17-CONTEXT.md`] |

## Project Constraints (from CLAUDE.md)

- Foglet is SSH-first; Phoenix is infrastructure and Phase 17 must not add end-user browser workflows. [VERIFIED: `CLAUDE.md`]
- Use `rtk` as the shell prefix for repo commands, such as `rtk mix test`. [VERIFIED: `CLAUDE.md`]
- Keep `Foglet.TUI.*` responsible for Raxol app, screens, state, and widgets; keep `FogletBbs.*`/`FogletBbsWeb.*` as Phoenix infrastructure. [VERIFIED: `CLAUDE.md`]
- Keep UI behavior in `Foglet.TUI.App` and screens; keep reusable display in widgets; keep render functions pure over loaded state. [VERIFIED: `CLAUDE.md`]
- Route colors through `Foglet.TUI.Theme`, pass theme explicitly, and avoid hardcoded color atoms in widgets. [VERIFIED: `CLAUDE.md`; `lib/foglet_bbs/tui/widgets/README.md`]
- Use focused ExUnit tests under mirrored `test/foglet_bbs/...` paths. [VERIFIED: `CLAUDE.md`; `test/foglet_bbs/tui/theme_test.exs`]
- Run `mix precommit` when code changes are complete. [VERIFIED: `CLAUDE.md`; `mix.exs` aliases]

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Elixir / OTP | Elixir 1.19.5, OTP 28 | Runtime and ExUnit test environment | Installed project runtime; no new runtime dependency is needed. [VERIFIED: `elixir --version`] |
| Raxol | 2.4.0 | Terminal UI framework, View DSL, theme registry, widgets | Existing Foglet TUI stack and vendored dependency; use its theme component-style registry instead of replacing it. [VERIFIED: `mix.lock`; `rtk mix hex.info raxol`; `docs/raxol/cookbook/THEMING.md`] |
| Foglet.TUI.Theme | local | Project theme registry and flat session snapshot | Existing single source for palette slots and `Theme.from_state/1`. Extend it instead of creating parallel theme maps. [VERIFIED: `lib/foglet_bbs/tui/theme.ex`] |
| ExUnit | bundled | Contract tests for modes, slots, and mappings | Existing tests use ExUnit under mirrored TUI paths. [VERIFIED: `test/foglet_bbs/tui/theme_test.exs`; `test/foglet_bbs/tui/widgets/input/tabs_test.exs`] |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Phoenix | 1.8.5 | Infrastructure, PubSub, endpoint | Do not touch for Phase 17 except existing compile/test context. [VERIFIED: `mix.lock`; `rtk mix hex.info phoenix`; `CLAUDE.md`] |
| Bodyguard | 2.4.3 | Authorization | Not directly involved in Phase 17; keep out of mode/theme metadata. [VERIFIED: `mix.lock`; `rtk mix hex.info bodyguard`] |
| Ecto SQL | 3.13.5 | Persistence/migrations | Not directly involved; Phase 17 needs no schema or migration. [VERIFIED: `mix.lock`; `rtk mix hex.info ecto_sql`] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `Foglet.TUI.Presentation` module | Add optional callbacks to every screen module | Callbacks force touching every screen module and make unknown-screen behavior less centralized; the phase decisions require one keyed TUI-level API. [VERIFIED: `.planning/phases/17-theme-and-mode-metadata/17-CONTEXT.md`; `lib/foglet_bbs/tui/screen.ex`] |
| Extending `Foglet.TUI.Theme` | Separate semantic color module | A second color registry would duplicate the existing palette registry and break widget conventions that require `Foglet.TUI.Theme`. [VERIFIED: `lib/foglet_bbs/tui/theme.ex`; `lib/foglet_bbs/tui/widgets/README.md`] |
| Code mapping contract | Markdown-only mapping table | Markdown alone cannot validate referenced slot names; use code data plus optional docs so tests can prove validity. [VERIFIED: `.planning/phases/17-theme-and-mode-metadata/17-CONTEXT.md`] |

**Installation:**
```bash
# No installation required.
# Use existing locked dependencies:
rtk mix deps.get
```

**Version verification:** `rtk mix hex.info raxol` reported Raxol releases through `2.4.0`; `mix.lock` contains Raxol-related locked packages at `2.4.0`. [VERIFIED: `rtk mix hex.info raxol`; `mix.lock`]

## Architecture Patterns

### System Architecture Diagram

```text
App.current_screen
    |
    v
Foglet.TUI.Presentation.mode_for!/1
    |-- known BBS ids ----------> :bbs
    |-- known operator ids -----> :operator
    `-- unknown id -------------> deliberate error or {:error, :unknown_screen}

Theme id / session snapshot
    |
    v
Foglet.TUI.Theme.resolve/1
    |
    v
%Foglet.TUI.Theme{existing slots + success/info/badge}
    |
    v
Widgets and future Chrome/RichRow/Badge/Editor primitives
    |
    v
Foglet.TUI.Presentation.theme_mappings/0 validates state -> slot contract
```

### Recommended Project Structure

```text
lib/foglet_bbs/tui/
├── presentation.ex      # screen-mode and theme-state mapping contract
├── theme.ex             # add success/info/badge slots and palette values
└── app.ex               # keep screen type and routing; optionally delegate mode lookup

test/foglet_bbs/tui/
├── presentation_test.ex # mode coverage, unknown ids, theme independence, mapping slot validity
└── theme_test.exs       # all theme ids expose non-empty semantic slots
```

### Pattern 1: Central Screen Mode Lookup

**What:** Define one public TUI contract that resolves all current screen ids to `:bbs` or `:operator`. [VERIFIED: `.planning/phases/17-theme-and-mode-metadata/17-CONTEXT.md`]

**When to use:** Use for later Chrome/status/layout rhythm decisions; do not call `Theme.from_state/1` or inspect Account preview state to determine mode. [VERIFIED: `.planning/phases/17-theme-and-mode-metadata/17-CONTEXT.md`; `test/foglet_bbs/tui/screens/account_test.exs`]

**Example:**
```elixir
defmodule Foglet.TUI.Presentation do
  @type mode :: :bbs | :operator

  @bbs_screens [:login, :register, :verify, :main_menu, :board_list,
                :thread_list, :post_reader, :new_thread, :post_composer]
  @operator_screens [:account, :moderation, :sysop]

  @spec mode_for!(Foglet.TUI.App.screen()) :: mode()
  def mode_for!(screen) when screen in @bbs_screens, do: :bbs
  def mode_for!(screen) when screen in @operator_screens, do: :operator
  def mode_for!(screen), do: raise ArgumentError, "unknown TUI screen: #{inspect(screen)}"
end
```

### Pattern 2: Theme Slot Extension in the Existing Registry

**What:** Add `success`, `info`, and `badge` to the struct fields, `@type t`, `@slot_keys`, and every `@*_slots` palette. [VERIFIED: `lib/foglet_bbs/tui/theme.ex`; `.planning/phases/17-theme-and-mode-metadata/17-CONTEXT.md`]

**When to use:** Use whenever a state has semantic meaning across palettes; preserve current palette taste by synthesizing from existing palette colors. [VERIFIED: `SCREENS.md`; `.planning/phases/17-theme-and-mode-metadata/17-CONTEXT.md`]

**Example:**
```elixir
@type t :: %__MODULE__{
  # existing fields...
  success: style_map(),
  info: style_map(),
  badge: style_map()
}

defstruct # existing fields...
          success: %{},
          info: %{},
          badge: %{}

@slot_keys [
  # existing slots...
  :success,
  :info,
  :badge
]
```

### Pattern 3: Testable Mapping Contract

**What:** Represent UI state mappings as data and validate that every referenced slot exists. [VERIFIED: `.planning/phases/17-theme-and-mode-metadata/17-CONTEXT.md`]

**When to use:** Before implementing Phase 18+ widgets, use this mapping as the source for widget moduledocs/tests so tabs, rows, badges, command hints, and editor states stay aligned. [VERIFIED: `SCREENS.md`]

**Example:**
```elixir
def theme_mappings do
  %{
    tabs: %{inactive: :unselected, active: :selected, indicator: :accent, border: :border},
    rows: %{selected: :selected, unread: :primary, normal: :unselected,
            metadata: :dim, disabled: :dim},
    badges: %{info: :info, success: :success, warning: :warning,
              error: :error, accent: :accent},
    commands: %{group: :dim, key: :accent, destructive: :error, inactive: :dim},
    editor: %{focused: :accent, unfocused: :border, counter: :dim,
              counter_warning: :warning, counter_error: :error}
  }
end
```

### Anti-Patterns to Avoid

- **Mode as theme:** Do not encode `:bbs` or `:operator` in theme id, palette, or Account preview state; the PRD says the split is a product rule, not a theme rule. [VERIFIED: `SCREENS.md`; `.planning/phases/17-theme-and-mode-metadata/17-CONTEXT.md`]
- **Per-screen mode branches:** Do not add ad hoc `if current_screen == ...` mode logic inside individual screen render functions. [VERIFIED: `.planning/phases/17-theme-and-mode-metadata/17-CONTEXT.md`; `CLAUDE.md`]
- **Hardcoded color atoms in new contract consumers:** Raxol allows named atoms, but Foglet widget conventions forbid hardcoded color atoms in project widgets. [VERIFIED: `docs/raxol/cookbook/THEMING.md`; `lib/foglet_bbs/tui/widgets/README.md`]
- **Visible facelift leakage:** Do not build badges, rich rows, command bars, editor frames, or Chrome V2 here. [VERIFIED: `.planning/phases/17-theme-and-mode-metadata/17-SPEC.md`]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Theme storage/registration | Parallel palette registry or map literals in widgets | Extend `Foglet.TUI.Theme` and its Raxol registration path | Existing code already registers component styles and resolves flat snapshots. [VERIFIED: `lib/foglet_bbs/tui/theme.ex`] |
| Terminal color capability handling | Custom truecolor/ANSI fallback logic | Raxol color/style pipeline via existing theme maps | Raxol docs state terminal color support is adapted by its style system. [CITED: `docs/raxol/cookbook/THEMING.md`] |
| Screen metadata discovery | Runtime module introspection over screen modules | Explicit mapping keyed by `Foglet.TUI.App.screen()` ids | Phase context requires deliberate unknown handling and every current screen id covered. [VERIFIED: `.planning/phases/17-theme-and-mode-metadata/17-CONTEXT.md`; `lib/foglet_bbs/tui/app.ex`] |
| Mapping validation | Manual prose-only review | ExUnit validation over mapping data and theme slot keys | Planner/verifier need proof that mapping references real slots. [VERIFIED: `.planning/phases/17-theme-and-mode-metadata/17-SPEC.md`] |

**Key insight:** The hard part is contract completeness, not rendering. The safest plan is to make metadata impossible to drift by testing every screen id, every palette id, and every mapping slot. [VERIFIED: `.planning/phases/17-theme-and-mode-metadata/17-CONTEXT.md`; `test/foglet_bbs/tui/theme_test.exs`]

## Common Pitfalls

### Pitfall 1: Missing Register/Verify
**What goes wrong:** Tests pass for `SCREENS.md` named flows but future Chrome V2 hits unknown mode on `:register` or `:verify`. [VERIFIED: `.planning/phases/17-theme-and-mode-metadata/17-CONTEXT.md`]
**Why it happens:** The spec names major screens, while `App.screen()` includes auth-adjacent routed screens. [VERIFIED: `lib/foglet_bbs/tui/app.ex`; `.planning/phases/17-theme-and-mode-metadata/17-CONTEXT.md`]
**How to avoid:** Test exact coverage for all twelve current screen ids. [VERIFIED: `.planning/phases/17-theme-and-mode-metadata/17-CONTEXT.md`]
**Warning signs:** `mode_for/1` has a catch-all default to `:bbs`.

### Pitfall 2: Theme Slot Added to Struct but Not Palettes
**What goes wrong:** `%Theme{}` has fields, but `resolve/1` returns empty maps for some themes. [VERIFIED: `lib/foglet_bbs/tui/theme.ex`]
**Why it happens:** `resolve/1` builds snapshots from `@slot_keys` and palette component styles. [VERIFIED: `lib/foglet_bbs/tui/theme.ex`]
**How to avoid:** Add tests over `Theme.ids()` asserting every new slot is a non-empty map after `Theme.resolve/1`. [VERIFIED: `test/foglet_bbs/tui/theme_test.exs`]
**Warning signs:** Passing `Theme.default/0` only tests one palette.

### Pitfall 3: Mapping Contract References Future Slots That Do Not Exist
**What goes wrong:** Later widget phases follow the contract and crash or silently fall back because a mapping references a nonexistent slot. [VERIFIED: `.planning/phases/17-theme-and-mode-metadata/17-SPEC.md`]
**Why it happens:** SCREENS.md talks about future semantic slots, but Phase 17 must freeze concrete names now. [VERIFIED: `SCREENS.md`; `.planning/phases/17-theme-and-mode-metadata/17-CONTEXT.md`]
**How to avoid:** Expose `Theme.slot_keys/0` or equivalent and validate all mapping leaves against it. [VERIFIED: `lib/foglet_bbs/tui/theme.ex`]
**Warning signs:** Mapping tests assert only map keys/categories, not leaf slot names.

### Pitfall 4: Mode Changes During Theme Preview
**What goes wrong:** Account preview or persisted theme changes alter mode-dependent layout choices. [VERIFIED: `test/foglet_bbs/tui/screens/account_test.exs`; `.planning/phases/17-theme-and-mode-metadata/17-CONTEXT.md`]
**Why it happens:** Mode lookup accidentally reads `state.session_context.theme`, `theme_id`, or Account candidate theme. [VERIFIED: `.planning/phases/17-theme-and-mode-metadata/17-CONTEXT.md`]
**How to avoid:** Keep mode API input to screen id only; add tests with multiple themes for representative BBS and operator screens. [VERIFIED: `.planning/phases/17-theme-and-mode-metadata/17-SPEC.md`]
**Warning signs:** `mode_for/1` accepts full app state instead of `screen`.

## Code Examples

Verified patterns from project sources:

### Existing Theme Snapshot Resolution
```elixir
# Source: lib/foglet_bbs/tui/theme.ex
def from_state(state) do
  case Map.get(state, :session_context) do
    nil -> default()
    ctx -> Map.get(ctx, :theme) || default()
  end
end
```

### Existing Widget Theme Routing
```elixir
# Source: lib/foglet_bbs/tui/widgets/chrome/key_bar.ex
text("[#{k}] ", fg: theme.accent.fg, style: accent_style)
text("#{d}  ", fg: theme.dim.fg)
```

### Existing Tab Slot Mapping
```elixir
# Source: lib/foglet_bbs/tui/widgets/input/tabs.ex
%{
  tab: %{fg: t.unselected.fg},
  active_tab: %{fg: t.selected.fg, style: [:bold]},
  border: %{fg: t.border.fg}
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Inline Raxol color atoms in examples | Foglet routes widget colors through `%Foglet.TUI.Theme{}` slots | Existing project convention before Phase 17 | Raxol supports inline atoms, but Foglet widgets should not use them. [CITED: `docs/raxol/cookbook/THEMING.md`; VERIFIED: `lib/foglet_bbs/tui/widgets/README.md`] |
| Screen rhythm implied by screen name/layout | Explicit `:bbs` / `:operator` metadata | Phase 17 | Chrome V2 and later widgets can ask one contract instead of reclassifying screens. [VERIFIED: `.planning/phases/17-theme-and-mode-metadata/17-SPEC.md`] |
| `success` role mapped to `theme.primary` in older button tests | First-class `theme.success` semantic slot | Phase 17 | Future badges/buttons can distinguish healthy/success states without palette-specific logic. [VERIFIED: `test/foglet_bbs/tui/widgets/input/button_test.exs`; `SCREENS.md`] |

**Deprecated/outdated:**
- Treating `theme.primary` as success: replace in new facelift contracts with `theme.success`; existing widgets may remain until later phases touch them. [VERIFIED: `SCREENS.md`; `.planning/phases/17-theme-and-mode-metadata/17-CONTEXT.md`]
- Catch-all mode defaults: avoid because unknown screen ids must be deliberate. [VERIFIED: `.planning/phases/17-theme-and-mode-metadata/17-CONTEXT.md`]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | A new `Foglet.TUI.Presentation` module is the best exact module name. [ASSUMED] | Summary / Architecture Patterns | Low; planner can choose another TUI-level module name if it preserves one source of truth. |

## Open Questions

1. **Should `mode_for/1` return `{:ok, mode} | {:error, reason}` in addition to bang form?**
   - What we know: Unknown ids must be handled deliberately and tested. [VERIFIED: `.planning/phases/17-theme-and-mode-metadata/17-CONTEXT.md`]
   - What's unclear: Whether later Chrome callers prefer raising during development or tuple handling at runtime.
   - Recommendation: Provide `mode_for!/1` for internal invariant checks and optionally `mode_for/1` for tests or future user-supplied ids.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| Elixir/OTP | Compile and tests | yes | Elixir 1.19.5 / OTP 28 | none |
| Mix/Hex | Dependency inspection | yes | project Mix | none |
| Raxol | TUI View DSL/theme registry | yes | 2.4.0 locked | none |

**Missing dependencies with no fallback:**
- None. [VERIFIED: `elixir --version`; `mix.lock`; `rtk mix hex.info raxol`]

**Missing dependencies with fallback:**
- None. [VERIFIED: local environment probes]

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | ExUnit bundled with Elixir 1.19.5 [VERIFIED: `elixir --version`; `test/foglet_bbs/tui/theme_test.exs`] |
| Config file | `test/test_helper.exs` [VERIFIED: repo test layout] |
| Quick run command | `rtk mix test test/foglet_bbs/tui/theme_test.exs test/foglet_bbs/tui/presentation_test.exs` |
| Full suite command | `rtk mix test` |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| MODE-01 | Every current screen id resolves to exactly `:bbs` or `:operator`; unknown ids are deliberate | unit | `rtk mix test test/foglet_bbs/tui/presentation_test.exs` | No - Wave 0 |
| THEME-01 | Every theme id resolves non-empty `success`, `info`, and `badge` slots | unit | `rtk mix test test/foglet_bbs/tui/theme_test.exs` | Yes, needs expansion |
| THEME-02 | Mapping contract covers tabs, rows, badges, commands, editor states and references only real slots | unit | `rtk mix test test/foglet_bbs/tui/presentation_test.exs` | No - Wave 0 |

### Sampling Rate

- **Per task commit:** `rtk mix test test/foglet_bbs/tui/theme_test.exs test/foglet_bbs/tui/presentation_test.exs`
- **Per wave merge:** `rtk mix test`
- **Phase gate:** `rtk mix precommit` before completion. [VERIFIED: `CLAUDE.md`; `mix.exs`]

### Wave 0 Gaps

- [ ] `test/foglet_bbs/tui/presentation_test.exs` - covers MODE-01 and THEME-02.
- [ ] `test/foglet_bbs/tui/theme_test.exs` - extend for THEME-01.
- [ ] Optional public `Theme.slot_keys/0` - needed if mapping validation should avoid duplicating private `@slot_keys`.

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V2 Authentication | no | Phase 17 does not change auth flows. [VERIFIED: `.planning/phases/17-theme-and-mode-metadata/17-SPEC.md`] |
| V3 Session Management | no | Theme snapshots are read from session context, but no session lifecycle behavior changes. [VERIFIED: `lib/foglet_bbs/tui/theme.ex`; `.planning/phases/17-theme-and-mode-metadata/17-SPEC.md`] |
| V4 Access Control | no | Mode metadata is presentation-only and must not become authorization. [VERIFIED: `CLAUDE.md`; `.planning/phases/17-theme-and-mode-metadata/17-SPEC.md`] |
| V5 Input Validation | yes | Validate unknown screen ids deliberately in the mode API. [VERIFIED: `.planning/phases/17-theme-and-mode-metadata/17-CONTEXT.md`] |
| V6 Cryptography | no | No secrets, tokens, or crypto changes. [VERIFIED: `.planning/phases/17-theme-and-mode-metadata/17-SPEC.md`] |

### Known Threat Patterns for TUI Metadata

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Treating hidden/disabled operator UI as authorization | Elevation of privilege | Keep `Foglet.Authorization` checks in contexts; do not use mode as permission. [VERIFIED: `CLAUDE.md`] |
| Unknown screen id silently defaulting to BBS | Tampering | Raise or return explicit error for unknown ids; test it. [VERIFIED: `.planning/phases/17-theme-and-mode-metadata/17-CONTEXT.md`] |

## Sources

### Primary (HIGH confidence)

- `.planning/phases/17-theme-and-mode-metadata/17-CONTEXT.md` - locked implementation decisions and phase scope.
- `.planning/phases/17-theme-and-mode-metadata/17-SPEC.md` - requirements, boundaries, acceptance criteria.
- `.planning/REQUIREMENTS.md` - MODE-01, THEME-01, THEME-02.
- `SCREENS.md` - visual mode split and semantic theme mapping guidance.
- `CLAUDE.md` - project boundaries, TUI conventions, testing requirements.
- `lib/foglet_bbs/tui/app.ex` - current screen id type and route source.
- `lib/foglet_bbs/tui/theme.ex` - existing theme registry and slot mechanism.
- `docs/raxol/cookbook/THEMING.md` - Raxol theme/color behavior.

### Secondary (MEDIUM confidence)

- `rtk mix hex.info raxol`, `rtk mix hex.info phoenix`, `rtk mix hex.info bodyguard`, `rtk mix hex.info ecto_sql` - dependency version checks.
- `mix.lock` - locked dependency versions.
- Existing widget tests under `test/foglet_bbs/tui/widgets/` - local test patterns.

### Tertiary (LOW confidence)

- None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - project dependencies and local docs verified.
- Architecture: HIGH - phase decisions and code ownership boundaries are explicit.
- Pitfalls: HIGH - derived from locked context, current code, and existing tests.

**Research date:** 2026-04-25
**Valid until:** 2026-05-25 for local architecture; re-check dependency versions if changing stack.
