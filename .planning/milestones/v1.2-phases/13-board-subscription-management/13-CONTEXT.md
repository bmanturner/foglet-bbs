# Phase 13: Board Subscription Management - Context

**Gathered:** 2026-04-24 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Users can inspect all active boards from the terminal and intentionally subscribe or unsubscribe, while required default boards remain protected and operators have a break-glass Mix task for subscription management. The locked SPEC defines a category-tree board directory, inline subscription status, user subscribe/unsubscribe actions, a persisted required-subscription board policy, Mix task operator adjustment, and honest empty-state/new-thread copy.
</domain>

<decisions>
## Implementation Decisions

### Locked Specification
- **D-01:** Treat `.planning/phases/13-board-subscription-management/13-SPEC.md` as the canonical source of requirements, boundaries, constraints, and acceptance criteria for Phase 13.
- **D-02:** The user-facing board directory must be a single terminal category tree showing subscribed and unsubscribed active boards together with inline subscription status; do not replace this with split subscribed/unsubscribed tabs.
- **D-03:** Category nodes must support collapse and expand, and `Enter` on a board leaf must continue to open the focused board's thread list.

### Domain Subscription Boundary
- **D-04:** Board subscription management belongs in `Foglet.Boards` or another owning domain context, not in TUI screens, Mix task database code, or direct `Repo` calls from callers.
- **D-05:** Extend the existing subscription surface with context APIs for listing active boards with per-user subscription state, subscribing to an active board, and unsubscribing from a subscribed board.
- **D-06:** Subscription changes must preserve the existing row-presence model in `board_subscriptions`: subscribing inserts or keeps a row, and unsubscribing from an allowed board deletes the row.

### Required Subscription Policy
- **D-07:** Add a persisted board-level column that marks whether a board subscription is required and therefore cannot be unsubscribed by users or by the break-glass task.
- **D-08:** The required-subscription flag is valid only when `default_subscription` is true; schema, changeset, context, Sysop board-management, and tests must enforce this relationship.
- **D-09:** Users are allowed to unsubscribe down to zero board subscriptions. The unsubscribe blocker is the board's required-subscription policy, not a minimum remaining subscription count.
- **D-10:** Unsubscribe from a required board must return a structured forbidden or validation result and leave the `board_subscriptions` row intact.

### User Terminal Flow
- **D-11:** Add subscribe and unsubscribe actions to the board directory as focused-board commands separate from `Enter`, because `Enter` remains the open-board action.
- **D-12:** The board directory should refresh after subscribe or unsubscribe and provide clear terminal feedback about the result.
- **D-13:** Preserve unread-count display for subscribed boards where available; unsubscribed board rows do not need unread counters.
- **D-14:** The directory should list only active, non-archived boards in non-archived categories.

### Operator Break-Glass Path
- **D-15:** Phase 13 satisfies sysop/operator subscription adjustment through a break-glass Mix task, not through full Sysop `USERS` terminal subscription management.
- **D-16:** The Mix task must route through the same `Foglet.Boards` context rules as the user-facing terminal path and must not bypass active-board or required-subscription enforcement.
- **D-17:** The task should support listing a user's board subscriptions plus subscribing and unsubscribing that user from a board, with explicit output for unknown user, unknown board, archived board, required-board unsubscribe, and success cases.

### Honest Empty And New-Thread States
- **D-18:** Board-list and new-thread empty states must stop telling users to ask a sysop for subscriptions.
- **D-19:** Empty states should distinguish no active boards available from no subscribed boards yet, and should point users to the real board-directory subscription action when active unsubscribed boards exist.

### the agent's Discretion
- Exact column name for the required-subscription flag, provided its meaning is clear and it is documented in schema/data-model docs.
- Exact subscribe/unsubscribe key bindings and terminal feedback wording, provided `Enter` remains open-board and copy is honest.
- Exact context function names and tagged tuple shapes, provided tests can distinguish success, forbidden required-board unsubscribe, unknown user/board, archived board, and validation failures.
- Exact Mix task name and option shape, provided it follows existing `mix foglet.*` task style and documents list/subscribe/unsubscribe usage.

### Folded Todos
None.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase specification
- `.planning/phases/13-board-subscription-management/13-SPEC.md` - Locked Phase 13 requirements, boundaries, constraints, acceptance criteria, and interview decisions.

### Project requirements and roadmap
- `.planning/REQUIREMENTS.md` - SUBS-01 through SUBS-05 traceability and v1.2 scope.
- `.planning/ROADMAP.md` - Phase 13 goal, dependency, and success criteria.
- `.planning/PROJECT.md` - SSH-first product boundary, v1.2 gap-closure milestone, and no end-user browser workflow constraint.

### Architecture and data model
- `docs/DATA_MODEL.md` - Existing `boards` and `board_subscriptions` schema model, unique subscription invariant, and data-model conventions.
- `.planning/codebase/CONVENTIONS.md` - Context, schema, changeset, test, and documentation conventions.
- `.planning/codebase/STRUCTURE.md` - Existing `Foglet.Boards`, TUI screen, widget, and Mix task file organization.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Foglet.Boards` in `lib/foglet_bbs/boards.ex` already owns board subscription APIs, default subscription enrollment, subscribed-board listing, unread counts, and read pointers.
- `Foglet.Boards.Subscription` in `lib/foglet_bbs/boards/subscription.ex` already models subscription row creation with unique `(user_id, board_id)` enforcement.
- `Foglet.TUI.Screens.BoardList` in `lib/foglet_bbs/tui/screens/board_list.ex` is the existing terminal board entry point and currently needs conversion from subscribed-only list to all-board directory.
- `Foglet.TUI.Screens.NewThread` in `lib/foglet_bbs/tui/screens/new_thread.ex` is the existing subscribed-board picker and contains copy that must be made honest.
- `Foglet.TUI.Widgets.Display.Tree` is called out by the SPEC as the intended existing primitive for expandable/collapsible category rendering.
- Existing `mix foglet.user.*` tasks under `lib/mix/tasks/` provide task style and test placement for the break-glass subscription task.

### Established Patterns
- Domain mutations route through context functions with typed results; callers should not manipulate schemas directly.
- Programmatically set foreign keys on structs before changeset construction; do not add caller-set foreign keys to `cast/3`.
- TUI screens keep screen-local state in the screen or sibling state modules and route persistence through `Foglet.TUI.Command.task/2` / app update messages.
- Sysop board-management behavior already belongs in existing Sysop board surfaces, but full Sysop `USERS` subscription management is out of scope for this phase.

### Integration Points
- Add the required-subscription board column through migration, schema, changeset validation, seed/default handling, Sysop board management, and tests.
- Extend `Foglet.Boards` with active-board directory and subscription mutation APIs used by both the board directory and Mix task.
- Update `Foglet.TUI.App` loading paths so board-directory and new-thread empty states receive enough state to distinguish no active boards from no subscribed boards.
- Update `BoardList` rendering/key handling around category tree state, subscribe/unsubscribe actions, refresh behavior, and open-board navigation.
- Add focused context, schema, TUI, and Mix task tests matching the SPEC acceptance criteria.
</code_context>

<specifics>
## Specific Ideas

- User correction: Foglet must support a user choosing to be subscribed to no boards.
- User correction: the inability to unsubscribe is dictated by the new persisted board-level required-subscription column.
- User correction: Phase 13 sysop-related subscription adjustment is the Mix task path; full Sysop `USERS` terminal management is not part of this phase.
</specifics>

<deferred>
## Deferred Ideas

- Full Sysop `USERS` terminal subscription management - explicitly out of scope for Phase 13; use the Mix task.
- Bulk subscription assignment by role or cohort - v2 requirement ADMN-02.
- Subscription-based notifications, webhooks, email digests, or notification delivery - outside Phase 13 board membership scope.
</deferred>

---

*Phase: 13-board-subscription-management*
*Context gathered: 2026-04-24*
