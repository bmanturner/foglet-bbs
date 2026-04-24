# Phase 13: Board Subscription Management - Specification

**Created:** 2026-04-24
**Ambiguity score:** 0.14 (gate: <= 0.20)
**Requirements:** 6 locked

## Goal

Users can inspect all active boards from the terminal and intentionally subscribe or unsubscribe, while required default boards remain protected and operators have a break-glass subscription management path.

## Background

Foglet already persists `board_subscriptions` with a unique `(user_id, board_id)` row meaning subscribed. `Foglet.Boards.subscribe_to_defaults/1` subscribes new users to boards where `default_subscription` is true, and `Foglet.Boards.subscribe/2` can add an individual subscription. Existing terminal board flows only load `Boards.list_subscribed_boards/1`: the `Boards` screen lists subscribed boards, and the new-thread board picker only offers subscribed boards. There is no unsubscribe context function, no active-board directory that shows unsubscribed boards, no board-level rule for mandatory subscriptions, and the current empty states tell users to ask a sysop instead of pointing to a real available action. The Sysop `USERS` tab is still a placeholder, so Phase 13 uses a break-glass Mix task for operator subscription adjustment.

## Requirements

1. **Category tree board directory**: The user-facing board directory lists all active boards the user is authorized to see, including both subscribed and unsubscribed boards, in one keyboard-navigable category tree.
   - Current: `BoardList` renders only `Boards.list_subscribed_boards/1`, so unsubscribed active boards are invisible to users.
   - Target: The board directory displays categories as expandable/collapsible parent nodes and boards as child nodes in category/display order. Board rows show inline subscription status; `Enter` on a board leaf continues to open the focused board.
   - Acceptance: A screen or app test with one category containing one subscribed active board and one unsubscribed active board proves both board rows render under the category, each board row exposes subscription status, `Left` or equivalent collapse hides the category's board rows, `Right` or equivalent expand shows them again, and `Enter` on a board leaf navigates to that board's thread list.

2. **User subscribe action**: A user can subscribe to an active unsubscribed board from the terminal board directory.
   - Current: `Foglet.Boards.subscribe/2` exists, but no terminal user action exposes it from board discovery.
   - Target: A focused-board tree action subscribes the current user to an active board, refreshes the directory state, and gives clear terminal feedback.
   - Acceptance: A test starts from an unsubscribed active board, triggers the terminal subscribe action, verifies a `board_subscriptions` row exists for the current user and board, and verifies the refreshed row is marked subscribed.

3. **Required default-board unsubscribe policy**: Boards gain a persisted policy column that marks whether a subscription is required, and that policy can only be enabled for boards with `default_subscription: true`.
   - Current: `boards` has `default_subscription`, but there is no persisted way to mark announcement-style boards as non-unsubscribable.
   - Target: Board schema, migration, changeset, Sysop board management, and tests support a required-subscription flag whose true value is valid only when `default_subscription` is also true.
   - Acceptance: Schema/context tests prove `required_subscription: true` with `default_subscription: true` is accepted, `required_subscription: true` with `default_subscription: false` is rejected, and persisted required boards remain identifiable by board-directory and unsubscribe logic.

4. **User unsubscribe action with enforcement**: A user can unsubscribe from a subscribed board only when the board is not marked as a required subscription.
   - Current: No unsubscribe context function or terminal action exists.
   - Target: Unsubscribe is available from the board directory for subscribed non-required board leaves, removes the subscription row, refreshes the directory state, and is blocked with clear feedback for required boards.
   - Acceptance: Focused context and TUI tests prove unsubscribing from a subscribed non-required board deletes the row, while unsubscribing from a required board returns a forbidden or validation result and leaves the row intact.

5. **Break-glass operator subscription task**: A Mix task lets an operator inspect and adjust a user's board subscriptions without relying on an incomplete Sysop `USERS` terminal surface.
   - Current: There are break-glass user tasks for creation, promotion, and password reset, but no subscription inspection or adjustment task.
   - Target: An operator can list a user's board subscriptions and subscribe or unsubscribe that user from a board through a documented Mix task; the task enforces the same active-board and required-subscription rules as the user path.
   - Acceptance: Mix task tests prove list, subscribe, unsubscribe-success, unknown-user, unknown-board, archived-board, and required-board-unsubscribe cases produce correct exit behavior and do not bypass context rules.

6. **Honest empty and new-thread states**: Empty board-list and new-thread states point users to the real board-directory subscription action instead of telling them to ask a sysop.
   - Current: Board-list and new-thread empty states say the user is not subscribed and should ask a sysop.
   - Target: Empty states distinguish no active boards available from no subscribed boards yet, and direct users to the board directory action when unsubscribed active boards exist.
   - Acceptance: Screen tests for board-list and new-thread states prove copy does not mention nonexistent sysop work and does identify the available terminal subscription path when active unsubscribed boards exist.

## Boundaries

**In scope:**
- A single-page terminal board directory using a category tree with expandable/collapsible category nodes and board leaf nodes.
- Inline subscribed/unsubscribed status on board rows.
- User subscribe and unsubscribe actions from the board directory.
- A persisted board-level required-subscription policy column constrained to default-subscription boards.
- Context-level enforcement for active-board subscription changes and required-board unsubscribe blocking.
- Sysop board-management support for the new required-subscription policy field.
- A break-glass Mix task for operator subscription inspection and adjustment.
- Empty-state and new-thread copy that points to real subscription actions.
- Focused context, TUI, schema, migration, and Mix task tests for SUBS-01 through SUBS-05.

**Out of scope:**
- Two-tab subscribed/unsubscribed board directory UI - UX review selected inline status in a category tree to preserve scanability and `Enter`-to-open behavior.
- Full Sysop `USERS` terminal subscription management - Phase 13 uses a Mix task because the roadmap allows a break-glass path and `USERS` remains incomplete.
- Bulk subscription assignment by role or cohort - this is v2 requirement ADMN-02.
- Browser admin or end-user browser subscription workflows - Foglet remains SSH-first for this milestone.
- Webhook notifications, email digests, or subscription-based notification delivery - those are outside Phase 13's board membership scope.
- Changing board read-pointer monotonicity or historical message numbering - subscription state must not alter read-pointer invariants or board-server numbering.

## Constraints

- Subscription mutation rules live in `Foglet.Boards` or another owning domain context, not directly in TUI screens or Mix task database code.
- The required-subscription flag is only meaningful and valid when `default_subscription` is true.
- TUI changes must keep `Enter` on a board leaf as the open-board action; subscribe/unsubscribe uses a separate focused-board command.
- Category nodes must support collapse and expand so a category can hide or reveal its boards.
- The board directory only lists active, non-archived boards in non-archived categories.
- Existing unread-count display for subscribed boards must be preserved where available; unsubscribed boards must not require unread counters.
- The Mix task must route through the same context rules as the user-facing terminal path.

## Acceptance Criteria

- [ ] Board directory renders subscribed and unsubscribed active boards together as category tree leaves with inline subscription status.
- [ ] Category tree nodes can collapse to hide their boards and expand to reveal them again.
- [ ] `Enter` on a board-directory leaf still opens the focused board's thread list.
- [ ] A user can subscribe to an active unsubscribed board from the terminal board directory.
- [ ] Boards have a persisted required-subscription policy field that cannot be true unless `default_subscription` is true.
- [ ] A user can unsubscribe from a subscribed non-required board.
- [ ] A user cannot unsubscribe from a required board, and the subscription row remains present.
- [ ] Sysop board management exposes and validates the required-subscription field consistently with `default_subscription`.
- [ ] A break-glass Mix task can list, add, and remove a user's board subscriptions while enforcing active-board and required-board rules.
- [ ] Empty board-list and new-thread states direct users to the real subscription action instead of nonexistent sysop work.

## Ambiguity Report

| Dimension          | Score | Min   | Status | Notes |
|--------------------|-------|-------|--------|-------|
| Goal Clarity       | 0.90  | 0.75  | met    | User and operator outcomes are specific and measurable. |
| Boundary Clarity   | 0.80  | 0.70  | met    | Category tree directory, required boards, and Mix task path are locked; richer Sysop users UI is excluded. |
| Constraint Clarity | 0.82  | 0.65  | met    | Required-subscription flag constraints and terminal behavior constraints are explicit. |
| Acceptance Criteria| 0.84  | 0.70  | met    | Pass/fail checks cover context, TUI, schema, and Mix task behavior. |
| **Ambiguity**      | 0.14  | <=0.20| met    | Gate passed after round 1. |

Status: met = met minimum, below = below minimum (planner treats as assumption)

## Interview Log

| Round | Perspective | Question summary | Decision locked |
|-------|-------------|------------------|-----------------|
| 1 | Researcher | Should subscription status be inline or split into subscribed/unsubscribed tabs? | Use one active-board directory with inline subscription status; a UX researcher selected this because it preserves scanability and `Enter`-to-open behavior. |
| 1 amendment | Researcher | Should categories and boards use the existing Tree primitive? | Yes. `Foglet.TUI.Widgets.Display.Tree` supports expand/collapse for parent nodes and leaf activation, so the board directory should render categories as collapsible parents and boards as selectable leaves. |
| 1 | Researcher | What makes a board non-unsubscribable? | Add a board-level required-subscription policy column, motivated by announcement boards. |
| 1 | Researcher | How does required-subscription relate to default subscription? | The required-subscription setting can only be true and enforced when `default_subscription` is true. |
| 1 | Researcher | Is a Mix task acceptable for sysop subscription adjustment? | Yes. Phase 13 may satisfy the operator path with a break-glass Mix task. |

---

*Phase: 13-board-subscription-management*
*Spec created: 2026-04-24*
*Next step: $gsd-discuss-phase 13 - implementation decisions (how to build what's specified above)*
