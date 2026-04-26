# Phase 24: operator-console-primitives - Context

**Gathered:** 2026-04-25 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 24 creates the reusable Operator Console primitive layer before Phase 25 converts Account, Moderation, and Sysop screens. It adds compact badges, key/value grids, dense operator table defaults, optional wide-terminal inspectors, and a refreshed `Modal.Form` body treatment. The work proves these primitives with realistic Account, Moderation, Sysop, invite, board, user, and moderation-shaped fixtures.

Phase 24 does NOT convert Account, Moderation, or Sysop tab bodies; add new moderation/sysop/account workflows; change authorization, persistence, or context behavior; add browser admin surfaces; or move modal overlay chrome into `Modal.Form`.

</domain>

<decisions>
## Implementation Decisions

### Widget Placement And Public Boundaries

- **D-01:** Add `Foglet.TUI.Widgets.Display.Badge` as a stateless display primitive under `lib/foglet_bbs/tui/widgets/display/`.
- **D-02:** Add `Foglet.TUI.Widgets.Display.KvGrid` as a stateless display primitive under `lib/foglet_bbs/tui/widgets/display/`.
- **D-03:** Add a new display-level operator table wrapper under the widget namespace, recommended as `Foglet.TUI.Widgets.Display.ConsoleTable` or a similarly explicit operator-console table module. It is a public API for dense operator rows and presets, not a replacement for all table rendering.
- **D-04:** Add `Foglet.TUI.Widgets.Workspace.Inspector` under a new `workspace/` widget bucket. It renders selected-row details/actions from caller-provided data and may collapse below a width threshold.
- **D-05:** Refresh `Foglet.TUI.Widgets.Modal.Form` in place. Keep the current module and behavior; do not introduce a parallel form primitive.

### Badge And State Semantics

- **D-06:** `Display.Badge` supports at least `:required`, `:subscribed`, `:locked`, `:sticky`, `:pending`, `:healthy`, `:error`, and neutral/info states.
- **D-07:** Badge rendering should be compact and terminal-native: short labels or single-cell glyphs are acceptable, but state must remain recognizable in flattened render output for tests.
- **D-08:** Badge roles route through `Foglet.TUI.Presentation.theme_mappings().badges` and then `Foglet.TUI.Theme` slots. Do not introduce hardcoded terminal color atoms.

### Key/Value Grid

- **D-09:** `Display.KvGrid` accepts caller-provided entries with label/value data plus optional state/badge metadata. It does not fetch data or infer domain behavior.
- **D-10:** KvGrid alignment, truncation, and padding use `Foglet.TUI.TextWidth` or existing width-safe helpers, not raw `String.length/1`.
- **D-11:** KvGrid tests should use Account profile/preference rows, Sysop system metric rows, site setting rows, runtime limit rows, and status summary rows at 64-column and 80-column widths.

### Console Table Strategy

- **D-12:** Build the operator table module as a wrapper/facade over `Foglet.TUI.Widgets.Display.Table` unless research finds a concrete blocker. Do not fork Raxol table behavior unnecessarily.
- **D-13:** The wrapper owns dense console defaults: compact columns, row data normalization, compact empty states, sortable/filterable/selectable flags, selected-row action handling, and theme routing.
- **D-14:** Console table tests instantiate LOG, USERS, BOARDS, SSH-key, invite, and moderation-shaped fixture data. They should prove headers, rows, empty states, deterministic selection actions, and no domain-specific screen logic inside the widget.

### Workspace Inspector

- **D-15:** `Workspace.Inspector` is optional progressive enhancement for wide terminals. At 64x22 and 80x24, it may intentionally render empty/collapsed output.
- **D-16:** Inspector input is caller-provided selected item details and scoped action descriptors. The widget never performs domain mutations or implies that an unavailable workflow exists.
- **D-17:** Inspector tests cover selected board, user, invite, and empty/no-selection fixture shapes, including collapse below threshold.

### Modal.Form Refresh

- **D-18:** Preserve `Modal.Form`'s current public behavior: `init/1`, `handle_event/2`, `render/2`, `set_errors/2`, typed coercion, Tab/Shift-Tab focus movement, Enter submit, Esc cancel, submit/cancel callback semantics, textarea raw-value workaround, and body-only rendering.
- **D-19:** Improve only the body hierarchy: stronger heading, clearer labels, visible required markers, inline field errors, base errors, and a compact action footer for submit/cancel controls.
- **D-20:** `Modal.Form.render/2` must not wrap output in a modal box, border, or centering container. `Foglet.TUI.App.render_modal_overlay/2` remains the single owner of overlay chrome.

### Size Contracts And Test Scope

- **D-21:** Add primitive-level size/layout coverage for Badge, KvGrid, console table, inspector, and refreshed Modal.Form at the milestone sizes: 64x22 minimum, 80x24 compact target, and one wide size, using the existing `132x50` precedent unless the planner has a clear reason to choose another wide size.
- **D-22:** Phase 24 proves primitive usability with fixture/example coverage only. Do not broadly migrate Account, Moderation, or Sysop tab bodies; Phase 25 owns conversion.
- **D-23:** Keep new widget tests under mirrored `test/foglet_bbs/tui/widgets/...` paths and extend existing `test/foglet_bbs/tui/widgets/modal/form_test.exs` for the form refresh. Use existing theme-hygiene helpers to refute hardcoded color atoms.

### the agent's Discretion

- Exact module name for the operator table wrapper, as long as it is explicit that this is the Operator Console table API and it reuses `Display.Table` where practical.
- Exact glyph/label choices for badges, provided required states are recognizable, single-cell where glyphs matter, and theme-routed.
- Exact KvGrid entry option names, provided the widget accepts label/value rows plus optional status/badge metadata and remains pure over caller-provided data.
- Exact inspector width threshold, with the recommended default being wide-terminal-only behavior aligned to the existing `132x50` layout smoke precedent.
- Exact Modal.Form footer copy, provided submit/cancel controls are visible and existing key behavior remains unchanged.

### Folded Todos

None — `gsd-sdk query todo.match-phase 24` returned `todo_count: 0`.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Locked Phase Scope

- `.planning/phases/24-operator-console-primitives/24-SPEC.md` — Locked Phase 24 requirements, boundaries, constraints, acceptance criteria, ambiguity report, and interview decisions.
- `.planning/ROADMAP.md` §Phase 24 — Milestone position, dependencies, requirements `CONSOLE-01` through `CONSOLE-04`, and success criteria.
- `.planning/REQUIREMENTS.md` §Operator Console Primitives — Requirement IDs `CONSOLE-01`, `CONSOLE-02`, `CONSOLE-03`, and `CONSOLE-04`.
- `SCREENS.md` §Visual Direction and §Design Principles — Operator Console rhythm, terminal pragmatism, and shared primitive stack.
- `SCREENS.md` §Account, §Moderation, and §Sysop — Target operator-console surfaces and fixture shapes for primitive proof.
- `SCREENS.md` §Widget And Primitive Work — `Display.Badge`, `Display.KvGrid`, `Modal.Form` refresh, and `Workspace.Inspector` primitive descriptions.
- `SCREENS.md` §Recommended Implementation Order — Phase ordering: primitives before operator screen conversion.

### Dependency Contracts

- `.planning/phases/16-unicode-width-foundation/16-CONTEXT.md` — `Foglet.TUI.TextWidth` display-width contract and size-test precedent.
- `.planning/phases/17-theme-and-mode-metadata/17-CONTEXT.md` — Operator mode metadata and badge/theme mapping contract.
- `.planning/phases/18-chrome-v2/18-CONTEXT.md` — `Chrome.ScreenFrame` boundary and `[{64,22},{80,24},{132,50}]` size-contract precedent.
- `.planning/phases/20-rich-rows-and-thread-flow/20-CONTEXT.md` — Theme-hygiene and width-safe glyph testing precedent.
- `.planning/phases/21-board-directory-facelift/21-CONTEXT.md` — Latest row/inspector deferral precedent and board-shaped fixture expectations.
- `.planning/phases/23-composer-facelift/23-CONTEXT.md` — Latest widget-boundary pattern: create shared primitive first, preserve screen behavior.

### Existing Code Touch Points

- `lib/foglet_bbs/tui/widgets/README.md` — Widget bucket, theme, and test conventions. Update it for new Display and Workspace primitives.
- `docs/raxol/getting-started/WIDGET_GALLERY.md` — Raxol table/layout conventions and widget composition reference.
- `lib/foglet_bbs/tui/widgets/display/table.ex` — Existing stateful facade over Raxol table; should be reused/wrapped for console table defaults.
- `test/foglet_bbs/tui/widgets/display/table_test.exs` — Existing table behavior and theme-hygiene tests.
- `lib/foglet_bbs/tui/widgets/modal/form.ex` — Existing form module to refresh while preserving body-only contract and behavior.
- `test/foglet_bbs/tui/widgets/modal/form_test.exs` — Existing Modal.Form behavior, coercion, navigation, errors, and theme-hygiene tests to preserve and extend.
- `lib/foglet_bbs/tui/presentation.ex` — `theme_mappings().badges` and operator screen mode metadata.
- `lib/foglet_bbs/tui/theme.ex` — Semantic theme slots consumed by new primitives.
- `lib/foglet_bbs/tui/text_width.ex` — Width-safe measurement, padding, truncation, and slicing.
- `test/foglet_bbs/tui/layout_smoke_test.exs` — Existing size-contract harness and helper patterns.

### Fixture Source References

- `lib/foglet_bbs/tui/screens/account/ssh_keys_surface.ex` — Current SSH-key list fields: label, fingerprint, created timestamp, last-used timestamp.
- `lib/foglet_bbs/tui/screens/account/profile_form.ex` and `lib/foglet_bbs/tui/screens/account/prefs_form.ex` — Account profile/preference row shapes for KvGrid fixtures.
- `lib/foglet_bbs/tui/screens/moderation.ex` — Current moderation LOG, USERS, and BOARDS row data shapes.
- `lib/foglet_bbs/tui/screens/sysop/system_snapshot.ex` — Current Sysop system metric labels and values for KvGrid/Badge fixtures.
- `lib/foglet_bbs/tui/screens/sysop/users_view.ex` — Current user status rows and action state for console table/inspector fixtures.
- `lib/foglet_bbs/tui/screens/sysop/boards_view.ex` — Current board/category rows and Modal.Form usage for fixture and modal refresh coverage.
- `lib/foglet_bbs/tui/screens/shared/invites_surface.ex` — Invite-shaped fixture data for table and inspector tests.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- `Foglet.TUI.Widgets.Display.Table` already wraps `Raxol.UI.Components.Table`, normalizes column specs, supports sortable/filterable/selectable flags, routes table styles through `Foglet.TUI.Theme`, and guards empty-table navigation.
- `Foglet.TUI.Widgets.Modal.Form` already owns typed field state, focus navigation, coercion, inline/base error state, submit/cancel callbacks, and the body-only modal overlay contract.
- `Foglet.TUI.Presentation.theme_mappings().badges` already maps badge roles to theme slots: `:info`, `:success`, `:warning`, `:error`, and `:accent`.
- `Foglet.TUI.Theme` already has semantic slots needed by operator widgets: `success`, `info`, `error`, `warning`, `badge`, `selected`, `unselected`, `dim`, `accent`, `title`, and `border`.
- `Foglet.TUI.TextWidth` provides the required display-width-safe helpers for aligned KvGrid rows, compact badges, and layout checks.
- Existing screen modules provide realistic fixture shapes without requiring Phase 24 to convert their render paths.

### Established Patterns

- New widgets live under `lib/foglet_bbs/tui/widgets/<bucket>/`, accept `theme:` explicitly, and route colors through `Foglet.TUI.Theme`.
- Stateful widgets expose `init/1`, `handle_event/2`, and `render/2`; stateless widgets expose render functions only.
- Widget tests live under mirrored `test/foglet_bbs/tui/widgets/<bucket>/` paths and include smoke render plus theme-hygiene coverage.
- Size-contract tests use 64x22, 80x24, and 132x50 as the recurring v1.3 terminal-size triple.
- Screen render functions and widgets stay pure over already-loaded state; domain mutations and authorization remain in contexts and screen/app command boundaries.

### Integration Points

- Phase 24 can add primitives and tests without touching Account/Moderation/Sysop render modules except for fixture reference or narrow Modal.Form call-site compatibility if the render body shape requires it.
- The new console table wrapper should delegate to `Display.Table.init/1`, `Display.Table.handle_event/2`, and `Display.Table.render/2` where possible, adding console-specific defaults around that boundary.
- `Workspace.Inspector` should be designed for Phase 25 callers to compose beside tables, but Phase 24 tests should instantiate it directly with fixture data.
- `Modal.Form` visual changes must keep `BoardsView`, Site/Limits forms, and existing form tests passing because Sysop already depends on the form primitive.

</code_context>

<specifics>
## Specific Ideas

- Operator Console primitives should read as dense administrative UI, not Classic Modern BBS decoration.
- Badge state examples should include the actual product vocabulary from the SPEC: required, subscribed, locked, sticky, pending, healthy, error, and neutral/info.
- KvGrid should replace bespoke rows such as Sysop `SystemSnapshot`'s padded `"  #{label}#{value}"` strings in Phase 25, but Phase 24 only proves the primitive.
- Console table fixtures should mirror current target surfaces: moderation log/users/boards, sysop users/boards, Account SSH keys, and invites.
- Inspectors are wide-terminal enhancement. They should not steal 64x22 or 80x24 space.
- Modal.Form refresh should make required markers and action footer visible without double-bordering the app-level modal overlay.

</specifics>

<deferred>
## Deferred Ideas

- Broad Account, Moderation, and Sysop screen conversion — Phase 25.
- New moderation queue, sanctions, review, suspend, archive, or destructive workflows — future domain/product phases.
- Browser admin UI or Phoenix end-user/admin workflows — out of scope for this SSH-first milestone.
- Making inspectors mandatory on compact terminals — rejected for Phase 24; wide-only progressive enhancement.
- Replacing `Display.Table` internals wholesale — only consider if research finds a concrete blocker.

### Reviewed Todos (not folded)

None — no matching todos for this phase.

</deferred>

---

*Phase: 24-operator-console-primitives*
*Context gathered: 2026-04-25*
