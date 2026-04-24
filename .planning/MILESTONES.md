# Project Milestones: Foglet BBS

## v1.2 Pre-Alpha Gap Closure (Shipped: 2026-04-24)

**Phases completed:** 7 phases, 26 plans, 46 tasks

**Key accomplishments:**

- Runtime delivery-mode config with a Swoosh mailer boundary and terminal-native Accounts email builders
- Accounts-owned Swoosh verification delivery with honest Register and Verify terminal copy
- Enumeration-safe terminal password reset requests wired from Login to Accounts in email delivery mode
- Sysop SITE config now exposes delivery_mode and rejects impossible no-email verification settings before persistence
- Delivery-mode-aware break-glass reset task with no-email blocking and explicit operator-only copy
- Cross-surface delivery-copy guards for Phase 9 terminal and operator reset surfaces
- Delivery-mode gap closure for valid no-email defaults, Login verification delivery, and operator retrieval tasks
- Durable rejected users with a sysop-only Accounts transition boundary and locked status graph
- Terminal-native user status administration in the Sysop workspace
- Break-glass account status task using the Accounts transition boundary
- Approval/rejection delivery metadata and honest login/registration copy
- Thread creation now enforces active-user and board postability policy before board-server message-number allocation.
- Reply creation now enforces board posting policy and locked-thread rules before board-server message-number allocation.
- TUI posting screens now map structured policy and lock denials to clear terminal copy without success navigation.
- Accounts-owned SSH key lifecycle APIs with registered-key authentication that records last-used metadata only after successful active-user matches.
- Terminal Account SSH key management with Accounts-backed add, list, refresh, and revoke flows.
- Requirement-tagged Account SSH key regression coverage with focused Phase 12 validation and full precommit pass.
- Required-subscription board policy plus shared Foglet.Boards directory, subscribe, and unsubscribe APIs.
- Terminal category-tree board directory with focused subscribe/unsubscribe actions and honest new-thread empty states.
- Break-glass `mix foglet.board_subscriptions` operator task for safe board subscription inspection and adjustment.
- Sysop runtime-config visibility is now backed by an executable schema ledger and actor-aware form behavior tests.
- Terminal-visible launch copy now has an executable forbidden-claim audit and verified blocker-flow evidence for v1.2 pre-alpha scope.
- Root README now gives pre-alpha operators concrete SSH-first, SMTP, no-email, break-glass, blocker, and launch-caveat guidance.
- Operator password reset now returns raw, verifiable reset tokens through Accounts-owned hashed-token persistence instead of unsupported browser URLs.
- Reset launch copy now describes raw-token, operator-assisted SSH handling and preserves Phase 14's historical false-URL failure record with Phase 15 closure evidence.

---

## v1.1 Operations Surfaces & Invites (Shipped: 2026-04-24)

**Delivered:** A fuller SSH/TUI operations surface with account preferences, shared invite workflows, sysop controls, persistent oneliners, and populated moderation tooling.

**Phases completed:** 0-8, including inserted Phase 1.1 (10 phases, 43 plans, 64 tasks)

**Key accomplishments:**

- Added Account, Moderation, and Sysop TUI surfaces with shared shell/state primitives and role-aware navigation.
- Introduced actor-aware authorization and reusable modal form infrastructure for operator workflows.
- Shipped persisted single-use invites, invite-only registration redemption, and shared live INVITES tabs across allowed surfaces.
- Added sysop runtime config, board/category management, and system snapshot screens.
- Added account profile/preferences with live session refresh and user-format-aware chrome time display.
- Added persistent oneliners plus moderation hide/audit workflows inside the terminal UI.

**Known deferred items at close:** 19 open planning artifacts acknowledged and deferred (see `.planning/STATE.md` Deferred Items).

**Audit note:** Phase 6's date-rendering audit concern was accepted as intentional. The chrome clock is time-only by product decision and still honors user timezone and 12h/24h preferences.

**What's next:** Start a fresh milestone with `$gsd-new-milestone`.

---
