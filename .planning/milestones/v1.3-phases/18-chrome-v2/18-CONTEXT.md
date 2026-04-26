# Phase 18: chrome-v2 - Context

**Gathered:** 2026-04-25 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 18 delivers shared Chrome V2 for the named TUI screens: breadcrumb-style location, mode-aware right-side status atoms, grouped key commands inside the shared frame, deliberate migration from the old flat footer path, responsive behavior at 64x22, 80x24, and wide sizes, and Login receiving BBS-mode Chrome V2 without changing authentication behavior. It does not redesign Main Menu, rich rows, board rows, post cards, composer editor frames, operator-console primitives, or any browser workflow.
</domain>

<decisions>
## Implementation Decisions

### Chrome Data Contract
- **D-01:** Introduce structured Chrome V2 data while keeping `Chrome.ScreenFrame` as the single screen-facing composition boundary.
- **D-02:** Existing plain title and flat key-list callers may be supported through a short compatibility normalizer, but the normalized output must feed `Chrome.CommandBar`.
- **D-03:** Do not preserve `Chrome.KeyBar` as a separate production footer path after caller migration; the old simple key-list path should be an adapter into the grouped command contract only.

### Breadcrumb Ownership
- **D-04:** Derive breadcrumb paths centrally from the current screen plus existing app, screen, and domain state, rooted at `Foglet`.
- **D-05:** Screens should not build final breadcrumb strings ad hoc. They may expose or pass extra context only where that context already exists, such as current board, current thread, compose step, or active operator tab.
- **D-06:** Breadcrumb formatting must stay shared so later facelift phases can change screen bodies without unwinding per-screen chrome behavior.

### Mode-Aware Status
- **D-07:** Status rendering must consume Phase 17 presentation-mode metadata (`:bbs` or `:operator`) rather than deriving mode from active theme, user role, or screen-local conditionals.
- **D-08:** BBS-mode status may show handle, time, unread, or activity atoms when those values are already available; operator-mode status may show handle, scope, time, or system/status atoms when already available.
- **D-09:** Optional status atoms must degrade honestly: absent unread/activity/scope/system data is omitted, falling back to the current guest or `@handle | time` treatment rather than placeholder or fabricated values.

### Responsive Chrome And Tests
- **D-10:** Add focused Chrome V2 primitive and contract tests for breadcrumb resolution, mode-specific status atoms, grouped command ordering, and command truncation priority.
- **D-11:** Extend positioned render/layout coverage for 64x22, 80x24, and at least one wide terminal size using `Raxol.UI.Layout.Engine.apply_layout/2` or an equivalent positioned render path.
- **D-12:** Width and truncation behavior must use the Phase 16 `Foglet.TUI.TextWidth` contract once available, especially for breadcrumbs, status atoms, command groups, and compact fallbacks.
- **D-13:** Tests should assert no overlap or incoherent content displacement, not only that expected text appears somewhere in the render tree.

### the agent's Discretion
- Exact struct/module names for breadcrumb data, status atoms, command groups, and the compatibility normalizer are planner discretion as long as they are local to `Foglet.TUI.Widgets.Chrome` or a clearly shared TUI contract.
- Exact command group labels and default priorities are planner discretion, but they should be stable enough for tests and cover existing purposes such as navigation, actions, system, tabs, fields, save, and refresh.
- Exact wide-terminal extra status atoms are planner discretion; the minimum requirement is honest omission when data is unavailable.

### Folded Todos
None.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase Requirements
- `.planning/phases/18-chrome-v2/18-SPEC.md` — Locked Phase 18 requirements, boundaries, constraints, acceptance criteria, and interview decisions.
- `.planning/ROADMAP.md` §Phase 18 — Milestone position, dependency, requirements, and success criteria.
- `.planning/REQUIREMENTS.md` §Chrome V2 and §Login — Requirement IDs `CHROME-01` through `CHROME-05` and `LOGIN-01`.
- `SCREENS.md` — v1.3 visual direction for Classic Modern BBS and Operator Console chrome.

### Dependency Contracts
- `.planning/phases/16-unicode-width-foundation/16-CONTEXT.md` — Phase 16 width-helper decisions that Chrome V2 must consume for display-width behavior.
- `.planning/phases/17-theme-and-mode-metadata/17-SPEC.md` — Phase 17 mode metadata and semantic theme-slot contract consumed by Chrome V2.

### Existing Chrome And Screen Callers
- `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex` — Current shared frame composition boundary.
- `lib/foglet_bbs/tui/widgets/chrome/status_bar.ex` — Current title/status implementation and clock behavior.
- `lib/foglet_bbs/tui/widgets/chrome/key_bar.ex` — Current flat key-list footer to replace or reduce to compatibility behavior.
- `lib/foglet_bbs/tui/screens/login.ex` — Login caller and auth behavior that must remain unchanged.
- `lib/foglet_bbs/tui/screens/main_menu.ex` — BBS home caller and visible key-list pattern.
- `lib/foglet_bbs/tui/screens/board_list.ex` — Board directory caller and board-state context.
- `lib/foglet_bbs/tui/screens/thread_list.ex` — Thread list caller using current board context.
- `lib/foglet_bbs/tui/screens/post_reader.ex` — Post reader caller using current thread context.
- `lib/foglet_bbs/tui/screens/new_thread.ex` — New thread caller and compose-step context.
- `lib/foglet_bbs/tui/screens/post_composer.ex` — Reply composer caller.
- `lib/foglet_bbs/tui/screens/account.ex` — Operator-mode account caller and tab context.
- `lib/foglet_bbs/tui/screens/moderation.ex` — Operator-mode moderation caller and scope/tab context.
- `lib/foglet_bbs/tui/screens/sysop.ex` — Operator-mode sysop caller and tab/system context.

### Test Anchors
- `test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs` — Existing clock/status tests to evolve for Chrome V2 status contracts.
- `test/foglet_bbs/tui/layout_smoke_test.exs` — Existing positioned layout smoke tests to extend across Chrome V2 size contracts.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Chrome.ScreenFrame.render/4` already centralizes the outer bordered frame and is the right screen-facing integration point for Chrome V2.
- `Chrome.StatusBar` already reads user/session context and formats time through `ClockFormatter`, including fixed-clock test support through `session_context.clock_now`.
- `test/foglet_bbs/tui/layout_smoke_test.exs` already applies Raxol layout to full screen render trees and asserts positioned text behavior.
- Current screen state already carries most breadcrumb context: current board, current thread, compose state, and operator tab state.

### Established Patterns
- TUI widgets live under `lib/foglet_bbs/tui/widgets/`; Chrome V2 primitives should remain under `widgets/chrome/`.
- Screens render pure Raxol trees and pass theme through `Foglet.TUI.Theme`; Chrome V2 must keep this pattern.
- Named screens currently call one shared frame helper instead of rendering frame pieces directly.
- Widget and screen tests mirror the `lib/` path under `test/foglet_bbs/tui/`.

### Integration Points
- Replace or adapt `Chrome.KeyBar` through a new `Chrome.CommandBar` so current flat `{key, description}` lists no longer render as an independent footer.
- Update `Chrome.ScreenFrame` to compose breadcrumb/status chrome, content, separator, grouped command bar, and bottom border in one shared frame.
- Use Phase 17 mode resolution for named screens when selecting BBS versus operator status atoms.
- Preserve Login state transitions and key handling while changing only its chrome rendering.
</code_context>

<specifics>
## Specific Ideas

- Keep Chrome V2 boring and centralized: one shared frame contract, one breadcrumb resolver, one status atom builder, one command bar.
- Treat compatibility with existing `{key, description}` lists as migration support, not a second design system.
- Preserve the time-only chrome decision from earlier work; do not add date display to status atoms.
</specifics>

<deferred>
## Deferred Ideas

None — analysis stayed within phase scope.

### Reviewed Todos (not folded)
None.
</deferred>

---

*Phase: 18-chrome-v2*
*Context gathered: 2026-04-25*
