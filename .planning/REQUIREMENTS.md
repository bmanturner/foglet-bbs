# Requirements: Foglet BBS v1.3 TUI Screen Facelift

**Defined:** 2026-04-25
**Core Value:** A user can SSH into a living, reliable BBS and participate in conversations through a terminal-native experience that feels like arriving somewhere.
**Primary PRD:** `SCREENS.md`

## v1 Requirements

### Unicode Width Foundation

- [x] **WIDTH-01**: TUI widgets can measure, truncate, pad, and slice terminal text by display width through one shared helper.
- [x] **WIDTH-02**: Layout-sensitive row, chrome, clipping, and composer cursor paths use the shared display-width helper instead of direct length/slice assumptions.
- [x] **WIDTH-03**: Width tests cover ASCII, accented Latin, combining marks, CJK text, and the milestone glyph set from `SCREENS.md`.
- [x] **WIDTH-04**: Existing ASCII-heavy screens keep their current layout behavior after width hardening.
- [x] **WIDTH-05**: Facelifted widgets and screens have size-contract coverage for the 64x22 minimum, the 80x24 compact design target, and at least one wide/tall terminal layout.

### Mode And Theme Contracts

- [x] **MODE-01**: TUI screens can declare Classic Modern BBS or Operator Console presentation mode without forking the widget stack.
- [x] **THEME-01**: Theme slots cover success, informational, badge, selected, dim, warning, error, and accent states needed by facelift widgets.
- [x] **THEME-02**: Tabs, rows, badges, command hints, and editor states have documented and tested theme-slot mappings without hardcoded color atoms.

### Chrome V2

- [x] **CHROME-01**: Shared chrome renders breadcrumb-style locations such as `Foglet ▸ Boards ▸ general` and `Foglet ▸ Sysop ▸ Users`, with ASCII fallback handled deliberately where needed.
- [x] **CHROME-02**: Shared chrome renders mode-appropriate right-side status fields for BBS and operator screens.
- [x] **CHROME-03**: `Chrome.CommandBar` renders grouped commands inside the frame and truncates lower-priority hints first.
- [x] **CHROME-04**: Shared chrome remains usable at 64x22 without text overlap or content displacement, while restoring richer status atoms and command detail at 80x24 and wider sizes.
- [x] **CHROME-05**: The existing command-footer path is migrated so simple key-list callers can use `Chrome.CommandBar` through a compatibility adapter rather than a parallel footer implementation.

### Login

- [x] **LOGIN-01**: Login declares Classic Modern BBS mode and receives the shared Chrome V2 treatment while preserving existing authentication behavior and form flow.

### Main Menu Dashboard

- [ ] **HOME-01**: User can navigate main-menu destinations with selection keys while existing direct hotkeys continue to work.
- [ ] **HOME-02**: Home shows useful session and BBS activity context, such as unread counts, boards, oneliners, or moderation counts when available.
- [ ] **HOME-03**: Home remains navigable at 64x22, reaches the intended compact dashboard rhythm around 80x24, and uses side-by-side activity panels only when width permits.

### Rich Rows And Thread Flow

- [ ] **RICHROW-01**: A reusable rich-row primitive supports state glyphs, primary text, metadata, optional subtitle/details, selection, and theme routing.
- [ ] **THREADS-01**: Thread list rows expose unread/read, sticky, locked, author, reply count, and age in width-safe aligned rows.
- [ ] **THREADS-02**: Thread list shows focused-thread details without disrupting keyboard navigation or existing open/compose/back behavior.

### Board Directory

- [ ] **BOARDS-01**: Board directory rows distinguish expanded/collapsed categories, read/unread boards, and subscription state with semantic columns and glyphs.
- [ ] **BOARDS-02**: Focused board or category details are visible through a 64x22-safe compact details strip, with a wide-terminal inspector only when width permits.
- [ ] **BOARDS-03**: Existing board open, expand/collapse, subscribe, unsubscribe, and back workflows continue to work after the facelift.
- [ ] **BOARDS-04**: Board directory solves the current single-label tree limitation through `Tree.render_row/3`-style row callbacks or a dedicated `BoardTree` wrapper.

### Post Reader

- [ ] **READER-01**: Post reader shows post position, stable message number, author, and age in a compact header.
- [ ] **READER-02**: Post bodies render with a clear gutter or card treatment while preserving existing markdown rendering behavior.
- [ ] **READER-03**: Longer threads show reading progress in a 64x22-safe form without breaking viewport scrolling, reply, previous/next, or back navigation.
- [ ] **READER-04**: Post reader uses the shared `PostCard` or an equivalent post unit for header, body, and optional footer treatment instead of bespoke loose text rows.

### Composer

- [ ] **COMPOSER-01**: `Composer.EditorFrame` wraps `MultiLineInput` for new-thread and reply composition with visible editor boundaries and focused/unfocused styling.
- [ ] **COMPOSER-02**: Edit and preview modes are visible as a tab or segmented control instead of only hidden in key hints.
- [ ] **COMPOSER-03**: Character budgets use shared progress/counter treatment with normal, warning, and over-limit states for title and body inputs where applicable.
- [ ] **COMPOSER-04**: Reply composition shows compact quoted context while new-thread composition shows board and title context, with nonessential context collapsing first at 64x22.
- [ ] **COMPOSER-05**: Title `TextInput` and body `MultiLineInput` behavior remains width-aware and theme-routed after the editor-frame refresh.

### Operator Console Primitives

- [ ] **CONSOLE-01**: `Display.Badge` standardizes compact states such as required, subscribed, locked, sticky, pending, healthy, and error.
- [ ] **CONSOLE-02**: `Display.KvGrid` renders consistent label/value rows for Account, Sysop System, site settings, limits, and status summaries.
- [ ] **CONSOLE-03**: Shared table presets and optional `Workspace.Inspector` support dense operator rows and selected-row details, with inspectors treated as wide-terminal progressive enhancement.
- [ ] **CONSOLE-04**: `Modal.Form` visual refresh provides stronger headings, field labels, inline errors, and action footers while preserving the body-only overlay contract.

### Operator Console Screens

- [ ] **ACCOUNT-01**: Account tabs use compact forms, theme swatches, SSH-key tables, invite tables, and clear dirty/saved/error states that remain usable at 64x22.
- [ ] **MOD-01**: Moderation tabs show scope/status summaries, honest empty states, and table-driven log, user, board, and invite views that degrade cleanly at 64x22.
- [ ] **SYSOP-01**: Sysop tabs use tables, metric cells, board/category rows, and cautious destructive-action styling without fake workflows, with wide metric layouts treated as enhancement.

## v2 Requirements

### Later UI Enhancements

- **UI-01**: Ultra-compact chrome can place one or two global commands in the bottom border.
- **UI-02**: Operator workbenches can use persistent wide-terminal inspector panes for routine selected-row actions.
- **UI-03**: Theme palettes can be tuned beyond the new semantic slots after real SSH screenshots show contrast problems.
- **UI-04**: Future moderation case-management workflows can add queue review inspectors and sanctions once the domain model exists.
- **UI-05**: Additional large-terminal dashboards can take advantage of terminals far wider or taller than the current sketches once the core responsive contracts are proven.

## Out of Scope

| Feature | Reason |
|---------|--------|
| End-user browser UI | Foglet remains SSH-first; Phoenix stays operational infrastructure for this milestone. |
| New moderation case-management domain workflows | v1.3 is a visual and primitive facelift for existing surfaces, not a moderation product expansion. |
| Webhook notifications or email digests | Existing seeds remain dormant because this milestone does not add notification delivery channels. |
| CP437 nostalgia as the primary style constraint | `SCREENS.md` selects modern UTF-8 terminal UI with optional compatibility fallbacks. |
| One-off screen-specific styling systems | The facelift must share primitives, theme slots, and mode metadata across screens. |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| WIDTH-01 | Phase 16 | Complete |
| WIDTH-02 | Phase 16 | Complete |
| WIDTH-03 | Phase 16 | Complete |
| WIDTH-04 | Phase 16 | Complete |
| WIDTH-05 | Phase 16 | Complete |
| MODE-01 | Phase 17 | Complete |
| THEME-01 | Phase 17 | Complete |
| THEME-02 | Phase 17 | Complete |
| CHROME-01 | Phase 18 | Complete |
| CHROME-02 | Phase 18 | Complete |
| CHROME-03 | Phase 18 | Complete |
| CHROME-04 | Phase 18 | Complete |
| CHROME-05 | Phase 18 | Complete |
| LOGIN-01 | Phase 18 | Complete |
| HOME-01 | Phase 19 | Pending |
| HOME-02 | Phase 19 | Pending |
| HOME-03 | Phase 19 | Pending |
| RICHROW-01 | Phase 20 | Pending |
| THREADS-01 | Phase 20 | Pending |
| THREADS-02 | Phase 20 | Pending |
| BOARDS-01 | Phase 21 | Pending |
| BOARDS-02 | Phase 21 | Pending |
| BOARDS-03 | Phase 21 | Pending |
| BOARDS-04 | Phase 21 | Pending |
| READER-01 | Phase 22 | Pending |
| READER-02 | Phase 22 | Pending |
| READER-03 | Phase 22 | Pending |
| READER-04 | Phase 22 | Pending |
| COMPOSER-01 | Phase 23 | Pending |
| COMPOSER-02 | Phase 23 | Pending |
| COMPOSER-03 | Phase 23 | Pending |
| COMPOSER-04 | Phase 23 | Pending |
| COMPOSER-05 | Phase 23 | Pending |
| CONSOLE-01 | Phase 24 | Pending |
| CONSOLE-02 | Phase 24 | Pending |
| CONSOLE-03 | Phase 24 | Pending |
| CONSOLE-04 | Phase 24 | Pending |
| ACCOUNT-01 | Phase 25 | Pending |
| MOD-01 | Phase 25 | Pending |
| SYSOP-01 | Phase 25 | Pending |

**Coverage:**
- v1 requirements: 40 total
- Mapped to phases: 40
- Unmapped: 0

---
*Requirements defined: 2026-04-25*
*Last updated: 2026-04-25 after milestone v1.3 scope refinement*
