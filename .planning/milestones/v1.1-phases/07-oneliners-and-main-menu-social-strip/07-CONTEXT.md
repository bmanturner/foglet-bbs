# Phase 07: oneliners-and-main-menu-social-strip - Context

**Gathered:** 2026-04-24 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

The main menu shows recent persisted oneliners in a bounded right-side social strip and lets authenticated users post one short oneliner through a focused composer/modal launched from the main menu. This phase adds the durable oneliner model, visible recent listing, split-pane main-menu display, and quick-post flow only. It does not add moderation hide UI, chat-like live behavior, sysop-editable oneliner policy, retention controls, or broader main-menu presence widgets.
</domain>

<decisions>
## Implementation Decisions

### Domain Persistence
- **D-01:** Add `Foglet.Oneliners` and `Foglet.Oneliners.Entry` as a normal Ecto context/schema backed directly by Postgres.
- **D-02:** Do not require a GenServer ring buffer in Phase 7. Persistence and recent-list queries from the database are sufficient for this phase; any future cache must remain secondary to Postgres.
- **D-03:** The public domain API should include a create path for authenticated users and a bounded recent-visible listing path for main-menu rendering.

### Schema and Validation
- **D-04:** The oneliner schema uses the locked/documented shape: `body`, `hidden`, `hidden_reason`, `user_id`, `hidden_by_id`, and `timestamps(updated_at: false)`.
- **D-05:** Set `user_id` from the authenticated actor in the context/API path, not through `cast/3` caller attrs.
- **D-06:** Enforce the Phase 7 hard body limit of 120 characters and reject blank bodies without inserting a row.
- **D-07:** Accepted entries default to `hidden: false`.
- **D-08:** Prevent the same user from posting two visible oneliners in a row. If the latest visible oneliner belongs to the current actor, creation returns a clear validation/domain error without inserting a row.

### Recent Listing
- **D-09:** Recent listing returns visible entries only, newest first, capped to the requested limit.
- **D-10:** The listing API preloads author data needed by the TUI so rendering can show handles without relying on nonexistent lazy loading.
- **D-11:** Hidden-entry support may exist in the schema for Phase 8, but Phase 7 UI must not expose hide behavior.

### Main Menu Rendering
- **D-12:** `Foglet.TUI.Screens.MainMenu` remains a pure/stateless renderer with no public `init_screen_state/1`.
- **D-13:** `MainMenu.render/1` reads recent oneliners already loaded into app state and renders them in the locked horizontal `split_pane` layout: navigation on the left, `Oneliners` panel on the right.
- **D-14:** Oneliner rows render as `@handle  body`, keep each entry to one visual row, cap/clip long handles around the locked 12-character presentation target, truncate or clip body text to the pane width, and omit timestamps.
- **D-15:** Existing navigation text, role-gated Account/Moderation/Sysop entries, key bindings, key-bar affordances, and 80x24 layout smoke expectations must remain intact.

### Loading and Refresh Ownership
- **D-16:** `Foglet.TUI.App` owns oneliner loading and refresh command tasks rather than running database reads inside `MainMenu.render/1`.
- **D-17:** Opening or returning to the main menu should trigger a bounded recent-oneliner load so the strip can render current persisted data.
- **D-18:** After a successful oneliner post, refresh the loaded recent-oneliner list and return to `:main_menu`.
- **D-19:** Do not add chat-like live typing, replies, reactions, or broad real-time conversation behavior in Phase 7.

### Composer Flow
- **D-20:** The `[O]` main-menu key opens a focused oneliner composer/modal using existing modal/form/input infrastructure, not a separate full-screen composer and not inline text-entry state inside `MainMenu`.
- **D-21:** Valid submit persists one oneliner, closes the focused composer/modal, refreshes recent oneliners, and returns to the main menu.
- **D-22:** Invalid submit, including blank, over-length, or back-to-back same-user posting, keeps the composer/modal focused and surfaces a visible validation/domain error without inserting a row.
- **D-23:** Cancel returns to the main menu without creating an oneliner.

### Testing and Quality Gate
- **D-24:** Add database-backed tests for persistence, schema shape, hidden default, 120-character acceptance, 121-character rejection, blank rejection, visible-only newest-first listing, author preload, and back-to-back same-user rejection.
- **D-25:** Add TUI tests for zero, one, and many oneliners in the split-pane main-menu layout, including long handle/body row clipping and no timestamp rendering.
- **D-26:** Add TUI/app tests proving `[O]` opens the focused composer/modal, valid submit persists and refreshes, invalid submit stays focused with error, cancel creates no row, and no Phase 7 UI exposes moderation hide behavior.
- **D-27:** `mix precommit` must pass before the phase is considered complete.

### the agent's Discretion
- Exact module/function names inside `Foglet.Oneliners`, as long as the public API is clear and tested.
- Exact recent-oneliner display limit, as long as it is bounded and the TUI tests cover overflow.
- Exact copy for empty state, validation errors, and success feedback.
- Whether the focused composer uses `Foglet.TUI.Widgets.Modal.Form` directly or a small dedicated wrapper around the same modal/input primitives, as long as it stays focused and does not make `MainMenu` stateful.
- Exact command/message names for load, submit, and refresh paths in `Foglet.TUI.App`.

### Folded Todos
None - `gsd-sdk query todo.match-phase 07` returned 0 matches.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase Scope and Requirements
- `.planning/phases/07-oneliners-and-main-menu-social-strip/07-SPEC.md` - locked Phase 7 requirements, boundaries, constraints, acceptance criteria, and interview log.
- `.planning/ROADMAP.md` - Phase 7 goal, dependencies, and success criteria.
- `.planning/REQUIREMENTS.md` - `ONEL-01`, `ONEL-02`, `ONEL-03`, plus deferred `MODR-05`, `SYSO-06`, and `ONEL-04` boundaries.
- `.planning/PROJECT.md` - SSH-first product direction, terminal-first constraints, and main-menu social/status milestone goals.

### Prior Decisions
- `.planning/phases/01-authorization-and-scope-backbone/01-CONTEXT.md` - pre-defined `:hide_oneliner` authorization for future moderation and the domain-as-trust-boundary rule.
- `.planning/phases/05-account-preferences-and-live-session-refresh/05-CONTEXT.md` - upstream session/preference refresh behavior that Phase 7 must not redefine.
- `.planning/phases/06-chrome-clock-and-main-menu-wiring/06-CONTEXT.md` - MainMenu statelessness, app-owned refresh behavior, chrome integration, and navigation visibility consistency.

### Data Model and Architecture
- `docs/DATA_MODEL.md` section 7 - documented `Foglet.Oneliners.Entry` schema, `oneliners` table, partial index, and future ring-buffer/moderation notes.
- `docs/ARCHITECTURE.md` - system architecture and aspirational oneliners ring-buffer placement.
- `.planning/codebase/ARCHITECTURE.md` - TUI/domain layering, Raxol app ownership, PubSub/custom subscription pattern, and app-owned command tasks.
- `.planning/codebase/CONVENTIONS.md` - Ecto schema, changeset, tagged-tuple, module, and test conventions.
- `.planning/codebase/STRUCTURE.md` - module layout for contexts, schemas, TUI screens, widgets, and tests.
- `.planning/codebase/TESTING.md` - ExUnit, DataCase, TUI render helper, and deterministic process-test patterns.

### TUI and Raxol References
- `docs/raxol/README.md` - Raxol documentation entry point.
- `docs/raxol/getting-started/WIDGET_GALLERY.md` - available Raxol layout primitives including split-pane style composition.
- `lib/foglet_bbs/tui/widgets/README.md` - local themed widget overview.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Foglet.TUI.Screens.MainMenu` - current stateless main-menu renderer/key handler; will gain split-pane rendering and `[O]` dispatch without gaining screen-local state.
- `Foglet.TUI.App` - owns screen routing, modal routing, command-task conversion, app state, PubSub subscriptions, and async domain reads.
- `Foglet.TUI.Modal` and `Foglet.TUI.Widgets.Modal` - existing focused modal overlay and global modal key routing.
- `Foglet.TUI.Widgets.Modal.Form` - stateful focused form container with text fields, submit/cancel, and inline error support.
- `Foglet.TUI.Widgets.Input.TextInput` - single-line input primitive with `max_length` support.
- `Foglet.TUI.Widgets.Chrome.ScreenFrame` - existing frame/key-bar host used by MainMenu.
- `Foglet.Authorization` - already includes `:hide_oneliner` for future Phase 8 moderation, but Phase 7 should not expose hide UI.
- `Foglet.Schema` and existing context/schema modules - local pattern for UUID primary keys, utc microsecond timestamps, changesets, and context-owned mutation APIs.

### Established Patterns
- Domain contexts own persistence and return tagged tuples or changesets; TUI code maps those results into visible UI state.
- Programmatically set ownership fields are assigned by context code, not cast from caller attrs.
- Screens are pure render/handle modules; `Foglet.TUI.App` owns cross-screen state, async I/O commands, modal routing, subscriptions, and lifecycle messages.
- MainMenu role/navigation visibility delegates to `ShellVisibility`; Phase 7 should preserve those existing entries and key guards.
- Modal-open key routing prevents underlying screens from consuming keys while the focused modal is active.

### Integration Points
- Add migration under `priv/repo/migrations/` for `oneliners` with UUID foreign keys to users, `hidden` default, nullable `hidden_reason` and `hidden_by_id`, `timestamps(updated_at: false)`, and a partial index for recent visible entries.
- Add `lib/foglet_bbs/oneliners.ex` and `lib/foglet_bbs/oneliners/entry.ex`.
- Extend `lib/foglet_bbs/tui/app.ex` with app state for recent oneliners and load/submit/refresh message handling.
- Extend `lib/foglet_bbs/tui/screens/main_menu.ex` to render the split-pane content and expose `[O]` in menu/key handling.
- Add or extend tests under `test/foglet_bbs/oneliners/`, `test/foglet_bbs/tui/screens/main_menu_test.exs`, `test/foglet_bbs/tui/app_test.exs`, and `test/foglet_bbs/tui/layout_smoke_test.exs`.
</code_context>

<specifics>
## Specific Ideas

- The strip should feel like BBS atmosphere, not a chat room.
- The right-side panel title should be `Oneliners`.
- Rows should stay compact: `@handle  body`, no timestamps, one visual row each.
- A same-user back-to-back guard is part of Phase 7 to keep the strip from becoming one person's monologue.
- The focused posting flow should feel quick from the main menu but should not make MainMenu itself hold editor state.
</specifics>

<deferred>
## Deferred Ideas

- A 24-hour per-user oneliner cooldown configurable by sysops - defer to a future policy/config phase because Phase 7 explicitly excludes sysop-editable oneliner policy, configurable max length, and richer controls.
- Oneliner moderation hide UI - Phase 8 owns `MODR-05`.
- Oneliner retention windows, richer browsing, and broader oneliner controls - v2 scope under `SYSO-06` and `ONEL-04`.

### Reviewed Todos (not folded)
None reviewed - `gsd-sdk query todo.match-phase 07` returned 0 matches.
</deferred>

---

*Phase: 07-oneliners-and-main-menu-social-strip*
*Context gathered: 2026-04-24*
