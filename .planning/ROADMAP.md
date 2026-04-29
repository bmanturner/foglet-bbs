# Roadmap: Foglet BBS v2.1 Stability & Maintenance Hardening

## Overview

v2.1 turns the post-v2.0 concerns audit into a focused hardening milestone. The work starts by retiring the remaining TUI contract compatibility seams, then reduces App and screen maintenance risk, hardens PostReader/content-query behavior, stabilizes SSH/session lifecycle paths, and closes with domain cleanup, Dialyzer baseline reduction, and an explicit concern-by-concern verification artifact.

## Phases

**Phase Numbering:**
- Integer phases (41, 42, 43): Planned milestone work
- Decimal phases (41.1, 41.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 41: TUI Contract And Modal Effects** - Retire legacy screen callbacks and route modal submits through explicit effects. (completed 2026-04-29)
- [ ] **Phase 42: App Runtime Helper Extraction** - Split routing, modal, subscription, and effect runtime helpers out of `Foglet.TUI.App`.
- [ ] **Phase 43: Large Screen Decomposition** - Separate reducer, state, and render responsibilities in the largest screen modules named by the audit.
- [ ] **Phase 44: PostReader And Content Query Hardening** - Add scalable PostReader loading/cache behavior and protect soft-delete/purity invariants.
- [ ] **Phase 45: SSH And Session Runtime Hardening** - Bound key stashes, strengthen promotion auditability, and make termination/counter behavior trustworthy.
- [ ] **Phase 46: Domain Cleanup And Final Quality Gate** - Resolve board/domain cleanup, Dialyzer baseline debt, and prove every audit concern has a disposition.

## Phase Details

### Phase 41: TUI Contract And Modal Effects
**Goal**: Maintainers can rely on one canonical screen contract and one explicit modal-submit path.
**Depends on**: Phase 40
**Requirements**: TUI-01, TUI-02, TUI-03, QUAL-02
**Success Criteria** (what must be TRUE):
  1. Maintainer can remove `render/1`, `handle_key/2`, and `init_screen_state/1` compatibility callbacks from `Foglet.TUI.Screen` without breaking production screens.
  2. Maintainer can run screen and smoke tests through `init/1`, `update/3`, and `render/2` only.
  3. Maintainer can trace a modal submit from form event to target screen `update/3` through a first-class `Foglet.TUI.Effect`.
  4. Maintainer has targeted tests proving the direct modal-submit round trip succeeds and failure paths remain visible.
**Plans**:

**Wave 1**
- `41-01` - Canonical screen contract cleanup.
- `41-03` - First-class modal-submit effect and App routing.

**Wave 2** *(blocked on Wave 1 completion)*
- `41-02` - Canonical test, smoke-helper, and screen-contract documentation migration.
- `41-04` - Modal consumer migration and `SubmitStash` removal.

Cross-cutting constraints:
- Preserve the target reducer boundary shape `{:modal_submit, kind, payload}` in every modal-submit plan.
- Keep tests behavioral and avoid pure text-presence assertions.
**UI hint**: yes

### Phase 42: App Runtime Helper Extraction
**Goal**: Maintainers can change App shell behavior through narrow runtime helper modules instead of one concentrated file.
**Depends on**: Phase 41
**Requirements**: TUI-04
**Success Criteria** (what must be TRUE):
  1. Maintainer can find route encoding and screen-state plumbing in a routing helper with a narrow public API.
  2. Maintainer can find modal overlay and dismissal behavior in a modal helper without screen-specific business logic.
  3. Maintainer can find dynamic PubSub topic refresh and subscription diffing in a subscription helper.
  4. Maintainer can find generic effect interpretation in an effect helper while domain mutations remain in `Foglet.*` contexts.
**Plans**: TBD
**UI hint**: yes

### Phase 43: Large Screen Decomposition
**Goal**: Maintainers can work on oversized TUI screens through clear reducer, state, and render boundaries.
**Depends on**: Phase 42
**Requirements**: TUI-05
**Success Criteria** (what must be TRUE):
  1. Maintainer can modify PostReader, Sysop, Login, MainMenu, NewThread, and Account screen rendering without digging through unrelated reducer code.
  2. Maintainer can test reducer behavior for decomposed screens without invoking render helpers.
  3. Maintainer can identify each decomposed screen's local state owner and render entry point from module names and documentation.
  4. Existing TUI behavior remains stable through reducer tests and render smoke verification after the splits.
**Plans**: TBD
**UI hint**: yes

### Phase 44: PostReader And Content Query Hardening
**Goal**: Users can read large threads reliably while maintainers have automated protection for PostReader and list-query invariants.
**Depends on**: Phase 43
**Requirements**: POST-01, POST-02, POST-03, POST-04
**Success Criteria** (what must be TRUE):
  1. User can navigate a very large thread without PostReader eagerly loading every post into local state.
  2. User can resize the terminal during a PostReader session without stale-width render-cache entries accumulating for the life of the screen.
  3. Maintainer has automated protection that prevents `render_*` helpers in PostReader from mutating screen state.
  4. Maintainer has query coverage or a shared helper proving soft-deleted posts stay out of list paths that should hide them.
**Plans**: TBD
**UI hint**: yes

### Phase 45: SSH And Session Runtime Hardening
**Goal**: Operators can trust SSH authentication, promotion, termination, and connection accounting under normal and fragile lifecycle paths.
**Depends on**: Phase 44
**Requirements**: SSH-01, SSH-02, SSH-03, SSH-04, SESS-01
**Success Criteria** (what must be TRUE):
  1. Operator can see bounded SSH public-key stash behavior through TTL or sweep cleanup for orphaned key offers.
  2. Operator can audit guest-to-user SSH session promotions with peer context when it is available.
  3. Maintainer can change SSH channel termination behavior in one helper that owns alt-screen leave, lifecycle stop, session stop, and connection-count cleanup.
  4. Operator can trust the global SSH connection counter after normal closes, EOF, lifecycle exits, over-limit rejects, and crash-during-init paths.
  5. Maintainer has direct coverage for the forced-termination fallback in `replace_then_promote/3`.
**Plans**: TBD

### Phase 46: Domain Cleanup And Final Quality Gate
**Goal**: Maintainers close the remaining audit concerns with domain cleanup, Dialyzer baseline reduction, and explicit verification evidence.
**Depends on**: Phase 45
**Requirements**: DOM-01, DOM-02, QUAL-01, QUAL-03
**Success Criteria** (what must be TRUE):
  1. Maintainer can no longer confuse `Foglet.Boards.Supervisor.boot_board_servers/0` with the board boot source of truth.
  2. Maintainer can understand or rely on the chosen transaction shape in `Foglet.Boards.Server` without convention drift from `Repo.transact/1`.
  3. Maintainer can run Dialyzer with fewer ignored warnings, with each audit-called warning fixed or explicitly reclassified.
  4. Maintainer can review a final verification artifact mapping every item in `.planning/codebase/CONCERNS.md` to fixed, intentionally retained, or covered.
  5. Maintainer can run the milestone close gate and see no unaddressed concern-audit items.
**Plans**: TBD

## Concern Coverage

| Concern | Phase |
|---------|-------|
| Legacy `Foglet.TUI.Screen` compatibility callbacks | Phase 41 |
| Process-dictionary modal-submit handoff | Phase 41 |
| App-shell modal-submit direct coverage gap | Phase 41 |
| `Foglet.TUI.App` routing/effects concentration | Phase 42 |
| Large screen modules with mixed responsibilities | Phase 43 |
| `Foglet.Posts.list_posts/1` eager PostReader loading | Phase 44 |
| PostReader render cache keyed by stale terminal widths | Phase 44 |
| PostReader render-path purity convention | Phase 44 |
| Soft-delete-aware list path coverage gap | Phase 44 |
| SSH public-key ETS stash TTL/sweep | Phase 45 |
| Guest-to-user SSH promotion audit visibility | Phase 45 |
| SSH channel termination paths and alt-screen cleanup | Phase 45 |
| SSH global connection counter lifecycle balance | Phase 45 |
| `replace_then_promote/3` forced-termination fallback coverage | Phase 45 |
| `Boards.Supervisor.boot_board_servers/0` no-op stub | Phase 46 |
| `Boards.Server` direct `Repo.transaction/1` convention drift | Phase 46 |
| `.dialyzer_ignore.exs` baseline debt | Phase 46 |
| Full concerns-audit disposition proof | Phase 46 |

## Progress

**Execution Order:**
Phases execute in numeric order: 41 -> 42 -> 43 -> 44 -> 45 -> 46

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 41. TUI Contract And Modal Effects | 4/4 | Complete    | 2026-04-29 |
| 42. App Runtime Helper Extraction | 2/5 | In Progress|  |
| 43. Large Screen Decomposition | 0/TBD | Not started | - |
| 44. PostReader And Content Query Hardening | 0/TBD | Not started | - |
| 45. SSH And Session Runtime Hardening | 0/TBD | Not started | - |
| 46. Domain Cleanup And Final Quality Gate | 0/TBD | Not started | - |
