# Phase 0: Screen Shells and Shared Surface Primitives - Context

**Gathered:** 2026-04-23 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Scaffold navigable Account, Moderation, and Sysop TUI shells with stable tabbing and shell-state primitives, including a reusable future-facing `INVITES` tab seam, without shipping fake persistence or fake operator behavior that later phases must undo.

</domain>

<decisions>
## Implementation Decisions

### Navigation and Role Visibility
- **D-01:** Account is a standard main-menu destination for authenticated users.
- **D-02:** Moderation and Sysop entry points use current session-role visibility checks in Phase 0 (`:mod`, `:sysop`) so the shells can be navigated now without pre-empting the actor-aware authorization seam planned for Phase 1.

### Shell Architecture Pattern
- **D-03:** Account, Moderation, and Sysop are first-class `Foglet.TUI.Screen` modules added to `Foglet.TUI.App` routing, rendered through `Foglet.TUI.Widgets.Chrome.ScreenFrame`.
- **D-04:** Each shell owns screen-local tab/focus state under `state.screen_state`, following the existing state-struct pattern already used by other non-trivial screens.

### Tab Model and Shared Invite Primitive
- **D-05:** Shell tabs use `Foglet.TUI.Widgets.Input.Tabs` for stable left/right and digit-based tab navigation instead of ad hoc tab handling.
- **D-06:** Phase 0 introduces a shared `INVITES` shell/tab primitive as reusable state and rendering scaffolding only; it is not a live invite workflow in this phase.
- **D-07:** The shared `INVITES` primitive is future-facing and conditionally shown, so later phases can activate it according to role and config without duplicating shell code.

### Shell Tab Sets
- **D-08:** Account has `PROFILE` and `PREFS` tabs in Phase 0.
- **D-09:** Account also carries the future-facing, conditionally shown `INVITES` tab scaffold in the shell contract.
- **D-10:** Moderation has `QUEUE`, `LOG`, `USERS`, `SANCTIONS`, and `BOARDS` tabs.
- **D-11:** Sysop has `SITE`, `BOARDS`, `LIMITS`, `SYSTEM`, and `USERS` tabs.

### Placeholder, Loading, and Error Semantics
- **D-12:** Shell tabs follow existing TUI semantics: `nil` state means loading, empty collections/states render explicit placeholder copy, and unexpected failures surface through the shared modal/error path rather than fake inline business data.
- **D-13:** Phase 0 placeholder content must stay obviously non-operational and must not introduce fake save actions, fake moderation actions, or fake invite behavior.

### the agent's Discretion
- Exact placeholder copy inside each shell/tab, as long as it stays clearly scaffold-only.
- Whether tab-local state lives in one per-screen struct or a small shared shell-state helper, as long as it stays consistent with existing `screen_state` patterns.
- Exact key-bar labels and menu wording, as long as navigation remains explicit and terminal-native.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase Scope and Requirements
- `.planning/ROADMAP.md` — Phase 0 goal, success criteria, and shell/reuse constraints for Account, Moderation, Sysop, and shared `INVITES`.
- `.planning/REQUIREMENTS.md` — `ACCT-01`, `MODR-01`, and `SYSO-01`, plus out-of-scope notes that prevent overbuilding the shells.
- `.planning/PROJECT.md` — milestone goal, terminal-first constraints, surface reuse requirement, and future board-scoped moderation direction.
- `.planning/STATE.md` — current milestone notes that Phase 0 is shell-only work and should not ship fake business behavior.

### TUI Architecture and Widget Contracts
- `docs/ARCHITECTURE.md` — system architecture, TUI/session layering, and screen-oriented app model.
- `docs/raxol/README.md` — Raxol entry point and navigation to widget/layout guidance.
- `docs/raxol/getting-started/WIDGET_GALLERY.md` — available Raxol layout and input primitives, especially tab and container patterns.
- `lib/foglet_bbs/tui/widgets/README.md` — local Foglet widget conventions and available themed widgets.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Foglet.TUI.Widgets.Chrome.ScreenFrame` — existing outer shell chrome for every screen; new shells should render through this rather than inventing their own frame.
- `Foglet.TUI.Widgets.Input.Tabs` — ready-made tab bar with Left/Right/Home/End and `1-9` shortcuts.
- `Foglet.TUI.Widgets.Progress.Spinner` — existing loading indicator for shell-level loading states.
- `Foglet.TUI.Widgets.Modal` plus `Foglet.TUI.App` modal handling — shared error/warning path for unexpected failures.
- `Foglet.TUI.Widgets.List.SelectionList` and `ListRow` — available if any shell tab needs simple selectable placeholder rows.

### Established Patterns
- `Foglet.TUI.App` is the routing conductor; screens are pure render/handle modules selected by `current_screen`.
- Non-trivial screens keep local state in `state.screen_state` and often use a dedicated nested state struct.
- Existing screens treat `nil` as loading, `[]` as empty, and use themed placeholder copy rather than fake populated data.
- Theme selection flows through `Theme.from_state/1`; shell code should route all colors through the existing theme contract.
- Session role is already carried in `Foglet.Sessions.Session`, making role-based shell visibility straightforward even before Phase 1 adds deeper authz enforcement.

### Integration Points
- `Foglet.TUI.Screens.MainMenu` will need new menu items and key handling to route into Account, Moderation, and Sysop.
- `Foglet.TUI.App` will need new screen atoms and `screen_module_for/1` entries for the new shell screens.
- Shared shell primitives can live under the existing TUI screen/widget namespaces so later phases can activate real behavior without reworking navigation.
- Runtime config and role checks already have seams in `Foglet.Config` and session/user state, which later phases can connect to conditional `INVITES` visibility.

</code_context>

<specifics>
## Specific Ideas

- Account should expose `PROFILE` and `PREFS` from the start, not a single undifferentiated shell.
- `INVITES` should exist now only as a future-facing, conditionally shown scaffold so later phases can activate it without redoing the shell layout.

</specifics>

<deferred>
## Deferred Ideas

None — analysis stayed within phase scope.

</deferred>
