# Requirements: Foglet BBS v2.1 Stability & Maintenance Hardening

**Defined:** 2026-04-29
**Core Value:** A user can SSH into a living, reliable BBS and participate in conversations through a terminal-native experience that feels like arriving somewhere.
**Source:** `.planning/codebase/CONCERNS.md` from the post-v2.0 concerns audit.

## v2.1 Requirements

Requirements for the v2.1 hardening milestone. Every item in the concerns audit is represented here and must map to exactly one roadmap phase.

### TUI Contract

- [ ] **TUI-01**: Maintainer can remove legacy `Foglet.TUI.Screen` compatibility callbacks without breaking production screens or valid tests.
- [ ] **TUI-02**: Maintainer can run screen tests and smoke helpers through the canonical `init/1`, `update/3`, and `render/2` contract only.
- [ ] **TUI-03**: Maintainer can change modal submit behavior through a first-class `Foglet.TUI.Effect` path instead of a process-dictionary handoff.
- [ ] **TUI-04**: Maintainer can understand and modify `Foglet.TUI.App` through narrow runtime helper modules for routing, modal, subscription, and effect concerns.
- [ ] **TUI-05**: Maintainer can work on the largest TUI screens through separated reducer/state/render modules where the concerns audit identified mixed responsibilities.

### Post Reader And Content Queries

- [ ] **POST-01**: User can read very large threads without PostReader requiring every post in the thread to be loaded eagerly.
- [ ] **POST-02**: User can resize the terminal during PostReader sessions without stale-width render-cache entries accumulating for the life of the screen.
- [ ] **POST-03**: Maintainer has automated protection for the PostReader render-path purity invariant so render helpers do not mutate state.
- [ ] **POST-04**: Maintainer has automated coverage or a shared query helper that prevents soft-deleted posts from reappearing in list paths.

### SSH And Session Runtime

- [ ] **SSH-01**: Operator has bounded SSH public-key stash behavior through TTL or sweep cleanup for orphaned key-offer entries.
- [ ] **SSH-02**: Operator has audit-grade visibility into guest-to-user SSH session promotions, including peer context where available.
- [ ] **SSH-03**: Maintainer can change SSH channel termination behavior through one helper that owns alt-screen leave, lifecycle stop, session stop, and connection-count cleanup.
- [ ] **SSH-04**: Operator can trust the global SSH connection counter to remain balanced across normal closes, EOF, lifecycle exits, over-limit rejects, and crash-during-init paths.
- [ ] **SESS-01**: Maintainer has direct coverage for the `replace_then_promote/3` forced-termination fallback so one-session-per-user replacement remains safe.

### Domain And Persistence Cleanup

- [ ] **DOM-01**: Maintainer can no longer mistake `Foglet.Boards.Supervisor.boot_board_servers/0` for the board boot source of truth.
- [ ] **DOM-02**: Maintainer can understand why `Foglet.Boards.Server` uses direct `Repo.transaction/1` with `Ecto.Multi`, or can rely on an equivalent `Repo.transact/1` shape if converted.

### Quality Baseline

- [ ] **QUAL-01**: Maintainer can reduce the `.dialyzer_ignore.exs` baseline by fixing or explicitly reclassifying each warning called out by the concerns audit.
- [ ] **QUAL-02**: Maintainer can verify the direct modal-submit round trip with targeted tests, not only through indirect screen reducer paths.
- [ ] **QUAL-03**: Maintainer can verify that every concern in `.planning/codebase/CONCERNS.md` was fixed, documented as intentionally retained, or covered by an explicit test/verification note.

## Future Requirements

Deferred to future releases. These are acknowledged but not part of this hardening milestone.

### Notifications

- **NOTIF-FUTURE-01**: User can receive outbound webhook notifications.
- **EMAIL-FUTURE-01**: User can resend verification email from the Verify screen after email delivery becomes intentional product scope.
- **EMAIL-FUTURE-02**: Sysop can configure whether email verification is required after onboarding/email scope is reopened.

## Out of Scope

Explicitly excluded for v2.1. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| New end-user browser workflows | Foglet remains SSH-first and terminal-native. |
| New notification delivery channels | SEED-001 and SEED-002 remain dormant; v2.1 is driven by concerns cleanup, not outbound delivery expansion. |
| Replacing Raxol | The milestone hardens the current Raxol-based screen/runtime boundary. |
| Rewriting domain contexts | Domain ownership stays in `Foglet.*` contexts; v2.1 may add focused helpers but not broad rewrites. |
| Pure text-presence tests | The project standard forbids tests that only assert text exists. |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| TUI-01 | Phase 41 | Pending |
| TUI-02 | Phase 41 | Pending |
| TUI-03 | Phase 42 | Pending |
| TUI-04 | Phase 42 | Pending |
| TUI-05 | Phase 43 | Pending |
| POST-01 | Phase 44 | Pending |
| POST-02 | Phase 43 | Pending |
| POST-03 | Phase 43 | Pending |
| POST-04 | Phase 44 | Pending |
| SSH-01 | Phase 45 | Pending |
| SSH-02 | Phase 45 | Pending |
| SSH-03 | Phase 45 | Pending |
| SSH-04 | Phase 45 | Pending |
| SESS-01 | Phase 45 | Pending |
| DOM-01 | Phase 44 | Pending |
| DOM-02 | Phase 44 | Pending |
| QUAL-01 | Phase 46 | Pending |
| QUAL-02 | Phase 42 | Pending |
| QUAL-03 | Phase 46 | Pending |

**Coverage:**
- v2.1 requirements: 19 total
- Mapped to phases: 19
- Unmapped: 0

---
*Requirements defined: 2026-04-29*
*Last updated: 2026-04-29 after v2.1 milestone initialization*
