# Roadmap: Foglet BBS

## Milestones

- [x] **v1.1 Operations Surfaces & Invites** - Phases 0-8, including inserted Phase 1.1 (shipped 2026-04-24). See [v1.1 roadmap archive](milestones/v1.1-ROADMAP.md).
- [x] **v1.2 Pre-Alpha Gap Closure** - Phases 9-15 (shipped 2026-04-24). See [v1.2 roadmap archive](milestones/v1.2-ROADMAP.md).
- [ ] **v1.3 TUI Screen Facelift** - Phases 16-25 (active).

## Current Status

v1.3 is ready to plan. The milestone is driven by `SCREENS.md` and upgrades the SSH terminal UI in dependency order: width-safe primitives, mode/theme contracts, shared chrome, Classic Modern BBS screens, then Operator Console screens. The hard minimum terminal size is 64x22; 80x24 is the compact design target; larger terminals progressively gain panels, inspectors, detail strips, and additional status atoms.

## Phases

<details>
<summary>[x] v1.1 Operations Surfaces & Invites (Phases 0-8) - SHIPPED 2026-04-24</summary>

- [x] Phase 0: Screen Shells and Shared Surface Primitives (7/7 plans)
- [x] Phase 1: Authorization and Scope Backbone (4/4 plans)
- [x] Phase 1.1: Shared Modal Form Primitive (3/3 plans)
- [x] Phase 2: Sysop Config and Board Management (6/6 plans)
- [x] Phase 3: Invite Persistence and Registration Enforcement (3/3 plans)
- [x] Phase 4: Shared Invite Surface Activation (5/5 plans)
- [x] Phase 5: Account Preferences and Live Session Refresh (4/4 plans)
- [x] Phase 6: Chrome Clock and Main Menu Wiring (4/4 plans)
- [x] Phase 7: Oneliners and Main Menu Social Strip (3/3 plans)
- [x] Phase 8: Moderation Workspace Population and Scope-Aware Operations (4/4 plans)

</details>

<details>
<summary>[x] v1.2 Pre-Alpha Gap Closure (Phases 9-15) - SHIPPED 2026-04-24</summary>

- [x] Phase 9: Delivery Modes and Onboarding Honesty (7/7 plans)
- [x] Phase 10: User Status Administration (4/4 plans)
- [x] Phase 11: Posting Policy Enforcement (3/3 plans)
- [x] Phase 12: Account SSH Key Management (3/3 plans)
- [x] Phase 13: Board Subscription Management (4/4 plans)
- [x] Phase 14: Launch Hygiene and Operator Notes (3/3 plans)
- [x] Phase 15: Reset Path Gap Closure (2/2 plans)

</details>

### v1.3 TUI Screen Facelift

**Milestone Goal:** Make Foglet's SSH terminal UI feel like a polished, Unicode-capable BBS while keeping operator workflows dense, honest, and terminal-pragmatic.

- [x] **Phase 16: Unicode Width Foundation** - Layout-sensitive TUI rendering is width-safe before heavier Unicode adoption. (completed 2026-04-25)
- [x] **Phase 17: Theme and Mode Metadata** - Screens can declare BBS vs operator rhythm without forking the widget stack. (completed 2026-04-25)
- [ ] **Phase 18: Chrome V2** - Every screen shares breadcrumb chrome, mode-aware status, and grouped key commands.
- [ ] **Phase 19: Main Menu Dashboard** - The home screen becomes a selectable, social BBS front porch with activity context.
- [ ] **Phase 20: Rich Rows and Thread Flow** - Thread browsing uses semantic glyphs, width-safe metadata, and focused details.
- [ ] **Phase 21: Board Directory Facelift** - Board browsing presents categories, board state, subscriptions, and details as structured rows.
- [ ] **Phase 22: Post Reader Facelift** - Thread reading emphasizes message numbers, post metadata, body readability, and progress.
- [ ] **Phase 23: Composer Facelift** - New-thread and reply composition use focused editor surfaces with preview and counters.
- [ ] **Phase 24: Operator Console Primitives** - Shared badges, key/value grids, table presets, inspectors, and modal form treatment land before screen conversion.
- [ ] **Phase 25: Operator Console Conversion** - Account, Moderation, and Sysop become dense shared-console layouts.

## Phase Details

### Phase 16: Unicode Width Foundation

**Goal:** Layout-sensitive widgets handle Unicode display width correctly before glyph-heavy aligned layouts ship.
**Depends on:** Phase 15
**Requirements:** WIDTH-01, WIDTH-02, WIDTH-03, WIDTH-04, WIDTH-05
**Success Criteria** (what must be TRUE):
1. Aligned rows render correctly with ASCII, accented Latin, combining marks, CJK, and planned UI glyphs.
2. List rows, the existing command-footer path, composer cursor paths, and clipping/truncation paths use one shared display-width helper.
3. Width tests cover the SCREENS.md glyph set: `●`, `◆`, `▸`, `▾`, `✓`, `×`.
4. Facelifted widgets and screens are tested at 64x22, 80x24, and at least one wide/tall terminal size.
5. Existing ASCII-heavy screens keep their current layout behavior.
**Plans:** 4/4 plans complete
Plans:
- [x] 16-01-PLAN.md — Shared `Foglet.TUI.TextWidth` helper and Unicode glyph tests.
- [x] 16-02-PLAN.md — Width-aware `ListRow.render_with_metadata/6` migration.
- [x] 16-03-PLAN.md — Chrome keybar, modal wrapping, and main-menu clipping migration.
- [x] 16-04-PLAN.md — Composer cursor hardening, size contracts, and source-scan closure.
**UI hint:** yes

### Phase 17: Theme and Mode Metadata

**Goal:** Screens can opt into Classic Modern BBS or Operator Console presentation while sharing theme and primitive contracts.
**Depends on:** Phase 16
**Requirements:** MODE-01, THEME-01, THEME-02
**Success Criteria** (what must be TRUE):
1. BBS-flow screens declare `:bbs`; Account, Moderation, and Sysop declare `:operator`.
2. Theme slots cover success/info/badge-like states without hardcoded color atoms in new facelift widgets.
3. Tabs, rows, badges, command hints, and editor states have consistent theme-slot mappings.
4. Changing user theme changes color treatment but not screen mode or layout category.
**Plans:** 4/4 plans complete
Plans:
- [x] 17-01-PLAN.md — Central presentation-mode contract and unknown-screen tests.
- [x] 17-02-PLAN.md — Semantic theme slots and palette-wide coverage.
- [x] 17-03-PLAN.md — Theme mapping contract and phase validation.
- [x] 17-04-PLAN.md — Unowned widget primitive theme-routing sweep.
**UI hint:** yes

### Phase 18: Chrome V2

**Goal:** Shared chrome communicates location, status, and commands consistently across all facelifted screens.
**Depends on:** Phase 17
**Requirements:** CHROME-01, CHROME-02, CHROME-03, CHROME-04, CHROME-05, LOGIN-01
**Success Criteria** (what must be TRUE):
1. Users see breadcrumb-style location such as `Foglet ▸ Boards ▸ general` or `Foglet ▸ Sysop ▸ Users`, with deliberate ASCII fallback where needed.
2. Users see mode-appropriate right status fields, such as handle/time/unread for BBS and scope/system status for operator screens.
3. `Chrome.CommandBar` groups commands and truncates lower-priority hints inside the frame.
4. The existing simple key-list call path can render through `Chrome.CommandBar` rather than a parallel footer implementation.
5. Login declares Classic Modern BBS mode and receives Chrome V2 without changing authentication behavior.
6. Chrome remains usable at 64x22 without overlapping content, restores the intended compact treatment around 80x24, and progressively shows more status atoms on wider terminals.
**Plans:** 3/7 plans executed
Plans:
- [x] 18-01-PLAN.md — Breadcrumb and mode-aware status primitives.
- [x] 18-02-PLAN.md — Grouped command bar and legacy key-list normalizer.
- [x] 18-03-PLAN.md — ScreenFrame Chrome V2 integration and size contracts.
- [ ] 18-04-PLAN.md — Login, Home, and Board Directory caller migration.
- [ ] 18-05-PLAN.md — Thread and composer flow caller migration.
- [ ] 18-06-PLAN.md — Account and Moderation operator caller migration.
- [ ] 18-07-PLAN.md — Sysop caller migration and legacy footer closure.
**UI hint:** yes

### Phase 19: Main Menu Dashboard

**Goal:** The main menu becomes a selectable, social BBS home screen while preserving direct hotkeys.
**Depends on:** Phase 18
**Requirements:** HOME-01, HOME-02, HOME-03
**Success Criteria** (what must be TRUE):
1. Users can navigate main-menu destinations with selection keys and existing direct hotkeys.
2. Role-gated destinations remain absent when unavailable.
3. Users see useful session/activity context such as unread counts, boards, oneliners, or moderation count when available.
4. The layout remains navigable at 64x22, reaches the intended compact dashboard rhythm around 80x24, and uses side-by-side panels only when width permits.
**Plans:** TBD
**UI hint:** yes

### Phase 20: Rich Rows and Thread Flow

**Goal:** Thread browsing uses semantic, width-safe rows that make unread, sticky, locked, author, count, and age easy to scan.
**Depends on:** Phase 18
**Requirements:** RICHROW-01, THREADS-01, THREADS-02
**Success Criteria** (what must be TRUE):
1. Users can distinguish unread/read and sticky/locked state without relying only on text labels.
2. Thread metadata aligns correctly with Unicode state glyphs and variable-width titles.
3. Focused-thread details appear without disrupting keyboard navigation.
4. The row primitive is reusable by later board/operator surfaces.
**Plans:** TBD
**UI hint:** yes

### Phase 21: Board Directory Facelift

**Goal:** Board browsing presents categories and board state as structured terminal-native rows.
**Depends on:** Phase 20
**Requirements:** BOARDS-01, BOARDS-02, BOARDS-03, BOARDS-04
**Success Criteria** (what must be TRUE):
1. Users can distinguish expanded/collapsed categories, read/unread boards, and subscription state visually.
2. Board labels are semantic columns, not embedded bracket text.
3. Focused board/category details are visible through a 64x22-safe compact details strip, with a wide inspector only when width permits.
4. The current single-label tree limitation is solved through row callbacks or a dedicated board-tree wrapper.
5. Existing tree state and subscribe/open/back workflows continue to work.
**Plans:** TBD
**UI hint:** yes

### Phase 22: Post Reader Facelift

**Goal:** Thread reading feels message-oriented and BBS-native, with clear metadata, body treatment, and progress.
**Depends on:** Phase 20
**Requirements:** READER-01, READER-02, READER-03, READER-04
**Success Criteria** (what must be TRUE):
1. Users see post position, stable message number, author, and age in a compact header.
2. Post bodies render with a clear gutter or card treatment without breaking markdown rendering.
3. Post rendering uses the shared `PostCard` or an equivalent post unit rather than bespoke loose text rows.
4. Longer threads show progress in a 64x22-safe form, using richer visual indicators only when space permits.
5. Viewport scroll ownership and reply/back navigation remain intact.
**Plans:** TBD
**UI hint:** yes

### Phase 23: Composer Facelift

**Goal:** New-thread and reply composition provide a focused editor surface with preview, counters, and validation states.
**Depends on:** Phase 22
**Requirements:** COMPOSER-01, COMPOSER-02, COMPOSER-03, COMPOSER-04, COMPOSER-05
**Success Criteria** (what must be TRUE):
1. Users compose inside `Composer.EditorFrame`, wrapping the existing multiline input with focused/unfocused styling.
2. Edit and preview modes are visible as a tab/segmented control, not only hidden in key hints.
3. Character budgets use shared progress/counter treatment for normal, warning, and over-limit states.
4. Reply composition shows compact quoted context while new-thread composition shows the title field, with nonessential context collapsing first at 64x22.
5. Title `TextInput` and body `MultiLineInput` behavior remains width-aware and theme-routed.
**Plans:** TBD
**UI hint:** yes

### Phase 24: Operator Console Primitives

**Goal:** Shared operator-console primitives land before the dense Account, Moderation, and Sysop screen conversion.
**Depends on:** Phase 21, Phase 23
**Requirements:** CONSOLE-01, CONSOLE-02, CONSOLE-03, CONSOLE-04
**Success Criteria** (what must be TRUE):
1. `Display.Badge` standardizes compact state rendering for required, subscribed, locked, sticky, pending, healthy, and error states.
2. `Display.KvGrid` renders consistent label/value rows for Account, Sysop System, site settings, limits, and status summaries.
3. Table presets and optional `Workspace.Inspector` support dense selected-row workflows on operator screens, with inspectors treated as wide-terminal enhancement.
4. `Modal.Form` has stronger headings, labels, inline errors, and action footers while preserving the body-only overlay contract.
**Plans:** TBD
**UI hint:** yes

### Phase 25: Operator Console Conversion

**Goal:** Account, Moderation, and Sysop become dense, consistent terminal workbenches after shared console primitives are stable.
**Depends on:** Phase 24
**Requirements:** ACCOUNT-01, MOD-01, SYSOP-01
**Success Criteria** (what must be TRUE):
1. Account tabs use compact forms, swatches, SSH-key tables, invite tables, and clear dirty/saved/error states that remain usable at 64x22.
2. Moderation tabs show scope/status summaries, honest empty states, and table-driven log/user/board views that degrade cleanly at 64x22.
3. Sysop tabs use tables, metric cells, board/category rows, and cautious destructive-action styling, with wide metric layouts treated as enhancement.
4. Account, Moderation, and Sysop reuse shared badges, key/value grids, table presets, modal form treatment, and optional inspectors rather than bespoke strings.
**Plans:** TBD
**UI hint:** yes

## Progress

**Execution Order:**
Phases execute in dependency order: 16 -> 17 -> 18 -> 19/20 -> 21/22 -> 23 -> 24 -> 25

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 0. Screen Shells and Shared Surface Primitives | v1.1 | 7/7 | Complete | 2026-04-24 |
| 1. Authorization and Scope Backbone | v1.1 | 4/4 | Complete | 2026-04-24 |
| 1.1 Shared Modal Form Primitive | v1.1 | 3/3 | Complete | 2026-04-24 |
| 2. Sysop Config and Board Management | v1.1 | 6/6 | Complete | 2026-04-24 |
| 3. Invite Persistence and Registration Enforcement | v1.1 | 3/3 | Complete | 2026-04-24 |
| 4. Shared Invite Surface Activation | v1.1 | 5/5 | Complete | 2026-04-24 |
| 5. Account Preferences and Live Session Refresh | v1.1 | 4/4 | Complete | 2026-04-24 |
| 6. Chrome Clock and Main Menu Wiring | v1.1 | 4/4 | Complete | 2026-04-24 |
| 7. Oneliners and Main Menu Social Strip | v1.1 | 3/3 | Complete | 2026-04-24 |
| 8. Moderation Workspace Population and Scope-Aware Operations | v1.1 | 4/4 | Complete | 2026-04-24 |
| 9. Delivery Modes and Onboarding Honesty | v1.2 | 7/7 | Complete | 2026-04-24 |
| 10. User Status Administration | v1.2 | 4/4 | Complete | 2026-04-24 |
| 11. Posting Policy Enforcement | v1.2 | 3/3 | Complete | 2026-04-24 |
| 12. Account SSH Key Management | v1.2 | 3/3 | Complete | 2026-04-24 |
| 13. Board Subscription Management | v1.2 | 4/4 | Complete | 2026-04-24 |
| 14. Launch Hygiene and Operator Notes | v1.2 | 3/3 | Complete | 2026-04-24 |
| 15. Reset Path Gap Closure | v1.2 | 2/2 | Complete | 2026-04-24 |
| 16. Unicode Width Foundation | v1.3 | 4/4 | Complete    | 2026-04-25 |
| 17. Theme and Mode Metadata | v1.3 | 4/4 | Complete   | 2026-04-25 |
| 18. Chrome V2 | v1.3 | 3/7 | In Progress|  |
| 19. Main Menu Dashboard | v1.3 | 0/TBD | Pending | - |
| 20. Rich Rows and Thread Flow | v1.3 | 0/TBD | Pending | - |
| 21. Board Directory Facelift | v1.3 | 0/TBD | Pending | - |
| 22. Post Reader Facelift | v1.3 | 0/TBD | Pending | - |
| 23. Composer Facelift | v1.3 | 0/TBD | Pending | - |
| 24. Operator Console Primitives | v1.3 | 0/TBD | Pending | - |
| 25. Operator Console Conversion | v1.3 | 0/TBD | Pending | - |
