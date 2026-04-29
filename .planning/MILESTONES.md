# Project Milestones: Foglet BBS

## v2.0 TUI Runtime Shell & Screen Update Loops (Shipped: 2026-04-29)

**Phases completed:** 7 phases, 28 plans, 78 tasks

**Key accomplishments:**

- Introduced the screen runtime contract with `Foglet.TUI.Context`, `Foglet.TUI.Effect`, and screen-owned `init/1`, `update/3`, and `render/2` callbacks.
- Migrated auth, home, board/thread directory, post reader, composer, account, moderation, and sysop flows so local state and async results live in the owning screens.
- Simplified `Foglet.TUI.App` into a runtime shell for route/session/modal coordination, generic effects, PubSub forwarding, task dispatch, and render delegation.
- Replaced App-owned screen fields and screen-specific result handling with route-keyed screen state, screen-declared subscriptions, and reducer-owned task results.
- Closed Phase 39 carry-forward blockers, added the TUI screen contract guide, and passed the full `rtk mix precommit` close gate.
- Archived phase execution history, requirements, roadmap, and the passing v2.0 milestone audit.

**Known deferred items at close:** 16 acknowledged open artifacts; see `.planning/STATE.md` Deferred Items.

---

## v1.4 Post-Facelift Polish & Bug Fixes (Completed: 2026-04-28)

**Phases completed:** 8 phases, ending at Phase 33.

**Key accomplishments:**

- Repaired layout and width regressions surfaced after the v1.3 TUI facelift.
- Hardened modal form behavior, tab lifecycle loading, auth flow behavior, login chrome, and composer wrapping.
- Completed Boards category Enter expand/collapse interaction while preserving board navigation.
- Closed the v1.4 stabilization cycle enough to start a new architecture milestone.

**Known carry-forward context:** v2.0 should preserve all SSH/TUI behavior while changing the screen runtime ownership model.

---

## v1.3 TUI Screen Facelift (Shipped: 2026-04-26)

**Phases completed:** 10 phases, 48 plans, 68 tasks

**Key accomplishments:**

- Centralized terminal display-width handling in `Foglet.TUI.TextWidth` and migrated row, chrome, modal, main-menu, and composer layout paths to width-safe helpers.
- Added presentation-mode metadata, semantic theme slots, and explicit widget visual contracts for Classic Modern BBS and Operator Console surfaces.
- Shipped Chrome V2 with breadcrumb titles, mode-aware status atoms, grouped command bars, and legacy key-list compatibility across all primary TUI screens.
- Refreshed BBS conversation flows: Home dashboard, rich ThreadList rows, BoardTree directory rows, shared PostCard reader parts, and shared composer editor shell.
- Added operator-console primitives for badges, key/value grids, dense tables, inspectors, and modal forms.
- Converted Account, Moderation, and Sysop into shared-primitives-based terminal workbenches with per-tab smoke coverage.

---

## v1.2 Pre-Alpha Gap Closure (Shipped: 2026-04-24)

**Key accomplishments:**

- Runtime delivery-mode config with a Swoosh mailer boundary and terminal-native Accounts email builders.
- Honest email verification, password reset, pending-approval, and no-email flows.
- Sysop SITE config visibility backed by actor-aware runtime config validation.
- User status administration, board posting restrictions, SSH key management, board subscriptions, and README operator guidance.

---

## v1.1 Operations Surfaces & Invites (Shipped: 2026-04-24)

**Delivered:** A fuller SSH/TUI operations surface with account preferences, shared invite workflows, sysop controls, persistent oneliners, and populated moderation tooling.

**Key accomplishments:**

- Added Account, Moderation, and Sysop TUI surfaces with shared shell/state primitives and role-aware navigation.
- Introduced actor-aware authorization and reusable modal form infrastructure for operator workflows.
- Shipped persisted single-use invites, invite-only registration redemption, and shared live INVITES tabs across allowed surfaces.
- Added sysop runtime config, board/category management, system snapshot screens, account profile/preferences, persistent oneliners, and moderation hide/audit workflows.

---
