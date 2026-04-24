# Phase 04: shared-invite-surface-activation - Context

**Gathered:** 2026-04-23 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

The shared `INVITES` tab becomes a live TUI feature in Account, Moderation, and Sysop only when the current actor and `invite_code_generators` policy allow invite generation. This phase activates listing, generation, revocation, selection, refresh, and error display on top of the existing Phase 3 invite domain APIs. It does not change invite persistence, registration redemption, invite policy editing, or the broader Account/Moderation/Sysop workspaces.

</domain>

<decisions>
## Implementation Decisions

### Visibility and Surface Placement
- **D-01:** Account, Moderation, and Sysop expose `INVITES` through each shell's existing tab-state construction, using `Foglet.TUI.Screens.ShellVisibility.invites_visible?/2` as the shared policy seam.
- **D-02:** Account remains the regular-user invite surface for `invite_code_generators == "any_user"`.
- **D-03:** Moderation adds `INVITES` only for moderators when `invite_code_generators == "mods"`.
- **D-04:** Sysop adds an allowed operator `INVITES` surface for sysops when policy permits sysop invite generation, including `sysop_only`; the planner should preserve sysop access under broader policies unless the locked SPEC tests prove a narrower interpretation is required.
- **D-05:** Hidden tabs are only UI exposure control. Domain authorization and runtime policy remain authoritative through `Foglet.Accounts`.

### Shared Invite State and Actions
- **D-06:** List loading, generated-code display, selected-row state, refresh state, and error state live in `Foglet.TUI.Screens.Shared.InvitesState` or adjacent shared invite modules.
- **D-07:** Account, Moderation, and Sysop contain only tab visibility, tab dispatch, and delegation code for `INVITES`; they must not duplicate list/generate/revoke behavior.
- **D-08:** The shared action path handles load, refresh, generate, select, revoke, and error mapping for all three surfaces.

### Domain API Boundary
- **D-09:** The TUI calls only `Foglet.Accounts.create_invite/1`, `Foglet.Accounts.list_invites/1`, and `Foglet.Accounts.revoke_invite/2` for live invite behavior.
- **D-10:** The TUI must not reimplement invite authorization, generation limits, code generation, persistence queries, or registration redemption semantics.
- **D-11:** Tagged errors from `Accounts` such as `:forbidden`, `:limit_reached`, `:not_found`, and `:unavailable` are mapped into TUI-visible errors without mutating local state as though the action succeeded.

### Rendering and Interaction Shape
- **D-12:** `InvitesSurface.render/2` replaces scaffold/future-placeholder copy with live status rows from `Accounts.list_invites/1`.
- **D-13:** Each row shows invite code, issuer id, inserted timestamp, derived status, and state-specific consumed or revoked details required by `04-SPEC.md`.
- **D-14:** Generation and revocation are keyboard-driven commands in the shared active tab, consistent with terminal-first TUI conventions.
- **D-15:** A generated invite code is displayed immediately after successful creation so the actor can copy/share it once from the TUI, while the refreshed list also includes the new code.
- **D-16:** Consumed and revoked invites remain visible but cannot be successfully revoked; failed revoke attempts surface a TUI error and leave persisted state unchanged.

### Testing and Quality Gate
- **D-17:** Add regression tests for policy-controlled tab visibility across Account, Moderation, and Sysop.
- **D-18:** Add shared-surface tests for rendering available, consumed, and revoked invite rows with the required fields.
- **D-19:** Add action tests proving allowed Account, Moderation, and Sysop surfaces each delegate through the same shared generation path and persist exactly one invite.
- **D-20:** Add revoke tests for available, consumed, already revoked, missing, and unauthorized invite codes.
- **D-21:** `mix precommit` must pass before the phase is considered complete.

### the agent's Discretion
- Exact key bindings for generate, revoke, refresh, and row selection, as long as they are visible in the key bar and consistent with nearby TUI screens.
- Exact row layout and timestamp formatting, as long as the required fields are present and readable in terminal output.
- Whether shared action helpers live directly in `InvitesSurface`, in a new sibling module, or split between state/action/render modules. Prefer one shared path with clear tests over a particular module shape.
- Exact wording for TUI error messages, as long as forbidden, limit-reached, not-found, unavailable, and validation failures are distinguishable enough for the actor.

### Folded Todos
None — `gsd-sdk query todo.match-phase 04` returned 0 matches.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase Scope and Requirements
- `.planning/phases/04-shared-invite-surface-activation/04-SPEC.md` — locked Phase 4 requirements, boundaries, constraints, and acceptance criteria.
- `.planning/ROADMAP.md` — Phase 4 goal and success criteria.
- `.planning/REQUIREMENTS.md` — `INVT-01`, `MODR-04`, `SYSO-05`, and related invite workflow requirements.
- `.planning/PROJECT.md` — terminal-first constraint, reusable invite-management decision, and v1.1 milestone goals.

### Prior Decisions
- `.planning/phases/00-screen-shells-and-shared-surface-primitives/00-CONTEXT.md` — shell/tab architecture and scaffold-only shared `INVITES` primitive.
- `.planning/phases/01-authorization-and-scope-backbone/01-CONTEXT.md` — actor-aware authorization, domain-as-trust-boundary, and invite action atoms.
- `.planning/phases/02-sysop-config-and-board-management/02-CONTEXT.md` — `invite_code_generators`, per-user limit semantics, and config policy editing ownership.
- `.planning/phases/03-invite-persistence-and-registration-enforcement/03-SPEC.md` — invite persistence and registration boundary.
- `.planning/phases/03-invite-persistence-and-registration-enforcement/03-VERIFICATION.md` — confirmation that Accounts invite APIs and invite-only registration are complete.

### TUI and Codebase Patterns
- `.planning/codebase/ARCHITECTURE.md` — TUI/domain layering and domain state ownership.
- `.planning/codebase/CONVENTIONS.md` — screen state, tagged-tuple errors, module layout, and test conventions.
- `.planning/codebase/TESTING.md` — ExUnit, DataCase, async/sync, and TUI test helper patterns.
- `docs/raxol/README.md` — Raxol documentation entry point.
- `docs/raxol/getting-started/WIDGET_GALLERY.md` — available TUI primitives.
- `lib/foglet_bbs/tui/widgets/README.md` — local themed widget overview.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Foglet.TUI.Screens.Shared.InvitesSurface` — existing shared renderer and title primitive; currently scaffold-only and must become live.
- `Foglet.TUI.Screens.Shared.InvitesState` — existing shared state struct; must grow from `items` only into live list/action/error state.
- `Foglet.TUI.Screens.ShellVisibility.invites_visible?/2` — central invite policy/role visibility seam.
- `Foglet.Accounts.create_invite/1`, `list_invites/1`, `get_invite_status/1`, `revoke_invite/2` — Phase 3 invite domain APIs.
- `Foglet.TUI.Widgets.Input.Tabs` — existing tab navigation primitive used by Account, Moderation, and Sysop.
- `Foglet.TUI.Widgets.List.SelectionList` and `ListRow` — likely row-selection primitives for selecting an invite to revoke.
- `Foglet.TUI.Widgets.Chrome.ScreenFrame` — existing screen chrome and key-bar host.

### Established Patterns
- Screens own local state under `state.screen_state` and delegate tab-local behavior to shared modules or submodules.
- Domain context functions return tagged tuples and are the trust boundary for authorization and mutation.
- TUI visibility checks are advisory and must not replace domain authorization.
- Placeholder/loading/error semantics already exist in shell screens and should become real load/error states instead of fake business data.
- Config visibility can be recomputed on render from `session_context` with fallback to `Foglet.Config`.

### Integration Points
- `lib/foglet_bbs/tui/screens/account.ex` and `account/state.ex` already include conditional `INVITES` wiring.
- `lib/foglet_bbs/tui/screens/moderation.ex` and `moderation/state.ex` need conditional `INVITES` tab inclusion and shared delegation.
- `lib/foglet_bbs/tui/screens/sysop.ex` and `sysop/state.ex` need conditional `INVITES` tab inclusion and shared delegation alongside existing submodule delegation.
- `lib/foglet_bbs/accounts.ex` exposes the persisted invite status map shape consumed by rendering.
- `test/foglet_bbs/tui/screens/shared/invites_surface_test.exs` currently asserts scaffold behavior and should be updated for live behavior.
- `test/foglet_bbs/accounts/invite_test.exs` is the domain behavior reference for TUI action tests.

</code_context>

<specifics>
## Specific Ideas

- Keep the surface terminal-native: visible key hints for generate, refresh, revoke, and navigation matter more than browser-like affordances.
- Treat the generated-code display as a transient success banner or focused status area in the shared tab, while still refreshing the persisted list.
- Preserve scaffold-free live rendering: once the shared tab loads, it should not say "later phase" or "Phase 4 activates this tab."

</specifics>

<deferred>
## Deferred Ideas

None — analysis stayed within phase scope.

### Reviewed Todos (not folded)
None reviewed — `gsd-sdk query todo.match-phase 04` returned 0 matches.

</deferred>

---

*Phase: 04-shared-invite-surface-activation*
*Context gathered: 2026-04-23*
