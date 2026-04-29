# Phase 43: Large Screen Decomposition - Context

**Gathered:** 2026-04-29 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 43 decomposes the six audited oversized TUI screen modules: PostReader, Sysop, Login, MainMenu, NewThread, and Account. Each named screen must keep a reducer-facing top-level screen module, keep or use its sibling `State` owner, and gain a sibling render entry point so maintainers can change rendering without reading unrelated reducer, task, or modal flow code.

Locked requirements come from `43-SPEC.md`: all six audited screens receive the agreed treatment; detailed render helpers move out of top-level modules; reducer behavior remains available through `init/1`, `update/3`, and `render/2`; render modules stay pure over loaded state and context; behavior stability is proved through reducer/effect tests plus render smoke evidence; and TUI documentation captures the decomposition pattern.
</domain>

<decisions>
## Implementation Decisions

### Decomposition Boundary
- **D-01:** Add sibling render entry points for all six named screens using the local namespace shape `Foglet.TUI.Screens.<Screen>.Render` under `lib/foglet_bbs/tui/screens/<screen>/render.ex`.
- **D-02:** Keep top-level screen modules as the reducer-facing `Foglet.TUI.Screen` implementations. They retain `init/1`, `update/3`, optional `subscriptions/2`, reducer helpers, task effect creation, modal submit handling, and public non-render test seams already documented as intentional.
- **D-03:** Make each top-level `render/2` delegate to the sibling render entry point. The top-level modules should no longer contain detailed private screen-body render helper families after extraction.

### Render Module Ownership
- **D-04:** Render modules own frame/content/keybar assembly and detailed body/tab/helper rendering for their screen, while consuming existing state structs and `Foglet.TUI.Context` or a derived render model.
- **D-05:** Render modules must not perform Repo calls, PubSub subscription changes, task starts, durable domain writes, or screen-state mutations. Existing render-path purity guidance in `SCREEN_CONTRACT.md` remains load-bearing.
- **D-06:** Route colors and styling through `Foglet.TUI.Theme` and existing widgets. Do not introduce new visual behavior or product workflows while moving render code.

### Screen-Specific Treatment
- **D-07:** For PostReader, extract render helpers only. Leave current loading, navigation, read-pointer flushing, viewport/cache warming, and `render_cache` mutation plumbing in the reducer/state side; PostReader eager loading and resize cache eviction remain Phase 44 scope.
- **D-08:** For Sysop and Account, the new render modules should orchestrate existing surface modules such as `BoardsView`, `UsersView`, `ProfileForm`, `PrefsForm`, `SSHKeysSurface`, and shared invite surfaces rather than replacing those established submodule boundaries.
- **D-09:** For Login, MainMenu, and NewThread, extract the current menu/form/panel/composer render helpers into render modules while keeping input handling, task result handling, domain-module resolution, and validation flow in the reducer-facing module or `State`.

### Extraction Order
- **D-10:** Prefer an incremental extraction order that limits blast radius: start with smaller or already-surface-oriented screens, then move through the more entangled render helpers. The planner may group screens into multiple plans as long as every plan leaves tests passing.
- **D-11:** Do not introduce a separate reducer module unless an existing screen's reducer code clearly needs it after render extraction. The phase target is state/render/reducer clarity, not an extra abstraction for its own sake.

### Coverage And Evidence
- **D-12:** Preserve and extend reducer/effect tests around behavior touched by extraction by driving `Screen.update/3`, task results, modal submit messages, route entry, or public non-render seams directly.
- **D-13:** Render verification should use existing layout smoke coverage or `rtk mix foglet.tui.render` evidence for all six named screens. Tests must not assert only the presence or absence of text.
- **D-14:** Add focused render-module tests only when they assert structural behavior, widget/model routing, or width-safe shape. Avoid snapshot or pure text-presence tests.
- **D-15:** Update TUI documentation to state when large screens should use sibling `state.ex` and `render.ex`, what top-level screen modules retain, and what render modules must not do.

### the agent's Discretion
- Downstream agents may choose the exact render module public function names and arities, provided they are consistent across screens where practical and easy to grep.
- Downstream agents may choose the plan grouping and extraction sequence, provided each step keeps behavior stable and does not leave a screen half-migrated.
- Downstream agents may keep small, non-detailed render delegation helpers in top-level modules when doing so improves clarity, but detailed body/tab/panel rendering belongs in render modules.

### Folded Todos
No matching todos were folded into this phase.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

- `.planning/phases/43-large-screen-decomposition/43-SPEC.md`
- `.planning/phases/42-app-runtime-helper-extraction/42-CONTEXT.md`
- `.planning/phases/41-tui-contract-and-modal-effects/41-CONTEXT.md`
- `.planning/ROADMAP.md`
- `.planning/REQUIREMENTS.md`
- `.planning/PROJECT.md`
- `.planning/codebase/CONCERNS.md`
- `.planning/codebase/CONVENTIONS.md`
- `.planning/codebase/STRUCTURE.md`
- `.planning/codebase/TESTING.md`
- `lib/foglet_bbs/tui/SCREEN_CONTRACT.md`
- `lib/foglet_bbs/tui/widgets/README.md`
- `docs/raxol/getting-started/WIDGET_GALLERY.md`
- `lib/foglet_bbs/tui/screens/post_reader.ex`
- `lib/foglet_bbs/tui/screens/post_reader/state.ex`
- `lib/foglet_bbs/tui/screens/sysop.ex`
- `lib/foglet_bbs/tui/screens/sysop/state.ex`
- `lib/foglet_bbs/tui/screens/login.ex`
- `lib/foglet_bbs/tui/screens/login/state.ex`
- `lib/foglet_bbs/tui/screens/main_menu.ex`
- `lib/foglet_bbs/tui/screens/main_menu/state.ex`
- `lib/foglet_bbs/tui/screens/new_thread.ex`
- `lib/foglet_bbs/tui/screens/new_thread/state.ex`
- `lib/foglet_bbs/tui/screens/account.ex`
- `lib/foglet_bbs/tui/screens/account/state.ex`
- `test/foglet_bbs/tui/screens/post_reader_test.exs`
- `test/foglet_bbs/tui/screens/sysop_test.exs`
- `test/foglet_bbs/tui/screens/login_test.exs`
- `test/foglet_bbs/tui/screens/main_menu_test.exs`
- `test/foglet_bbs/tui/screens/new_thread_test.exs`
- `test/foglet_bbs/tui/screens/account_test.exs`
- `test/foglet_bbs/tui/layout_smoke_test.exs`
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Foglet.TUI.Context` is already the narrow screen-facing runtime value and should be passed to render entry points or used to derive render models.
- `Foglet.TUI.Theme`, `ScreenFrame`, `Tabs`, `SelectionList`, `ListRow`, `EditorFrame`, `Compose`, `MarkdownBody`, `PostCard`, `Modal.Form`, and existing account/sysop surface modules are reusable render assets.
- All six named screens already have sibling `State` modules: `PostReader.State`, `Sysop.State`, `Login.State`, `MainMenu.State`, `NewThread.State`, and `Account.State`.
- Sysop and Account already delegate several tab bodies to submodules, giving the render extraction an existing surface-module pattern to preserve.

### Established Patterns
- Screen modules implement `init/1`, `update/3`, and `render/2`; App stores local screen state and interprets effects.
- Screen-local state structs own cursor position, loaded rows, drafts, selected indexes, submit status, route identity, and render caches.
- Screens request runtime or domain work through `Foglet.TUI.Effect` and receive `{:task_result, op, result}` or `{:modal_submit, kind, payload}` messages back through `update/3`.
- Render code is expected to be pure over loaded state and context-derived data; durable domain work belongs in `Foglet.*` contexts reached through task effects.
- Tests should assert reducer/effect outcomes and structural state, not static UI text.

### Integration Points
- `PostReader.render/2` currently builds frame state, chrome, post content, loading/error/empty views, viewport rendering, and post-card body rendering inline.
- `Sysop.render/2` currently owns authorization rendering, tab frame assembly, keybar hints, and tab-body dispatch while existing submodules render several tab surfaces.
- `Login.render/2` currently owns menu, login form, reset-request, and reset-token-consume rendering alongside reducer and task-result logic.
- `MainMenu.render/2` currently owns navigation/oneliner panels and command visibility rendering while reducer logic handles oneliner actions and modal submits.
- `NewThread.render/2` currently owns board-picker and composer rendering while reducer logic owns board loading, input handling, validation, and create-thread effects.
- `Account.render/2` currently owns tab frame assembly, theme preview routing, keybar hints, and tab-body dispatch while existing submodules render profile, prefs, SSH keys, and invites surfaces.
</code_context>

<specifics>
## Specific Ideas

- Treat Phase 43 as maintainability extraction only. Preserve SSH-first terminal behavior and avoid visual redesign.
- Keep PostReader Phase 44 concerns out of this phase: no pagination rewrite, no cache-eviction redesign, no content-query invariant work.
- Prefer grep-friendly file names and module names so a maintainer can find each screen's reducer-facing module, state owner, and render entry point immediately.
</specifics>

<deferred>
## Deferred Ideas

None - analysis stayed within phase scope.

### Reviewed Todos (not folded)
No matching todos were found for this phase.
</deferred>

---

*Phase: 43-large-screen-decomposition*
*Context gathered: 2026-04-29*
