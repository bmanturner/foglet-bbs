# Project Retrospective

## Milestone: v1.1 — Operations Surfaces & Invites

**Shipped:** 2026-04-24  
**Phases:** 10 | **Plans:** 43

### What Was Built

- Account, Moderation, and Sysop terminal surfaces with shared shell and state primitives.
- Actor-aware authorization, stable scope shapes, and shared modal-form infrastructure.
- Persisted single-use invites, invite-only registration redemption, and shared live INVITES tabs.
- Account profile/preferences with live session refresh and preference-aware chrome time display.
- Persistent main-menu oneliners with composer flow.
- Moderation workspace population plus audited oneliner hide behavior.

### What Worked

- Small phase slices kept the SSH/TUI surface changes reviewable.
- Shared primitives prevented invite and form logic from forking across Account, Moderation, and Sysop.
- Phase verification caught a requirement wording mismatch before archive, and the product decision was recorded explicitly.

### What Was Inefficient

- Some planning metadata drifted from phase verification state, especially roadmap and requirements checkboxes.
- Several human UAT artifacts remained partial at close and had to be acknowledged as deferred.
- Summary extraction produced noisy milestone accomplishments, so the shipped entry needed manual cleanup.

### Patterns Established

- Domain mutations stay in contexts with actor-aware authorization.
- TUI screens delegate reusable behavior to shared widgets/actions and keep rendering pure over loaded state.
- Runtime configuration exposed in the TUI must be schematized and written through `Foglet.Config.put/3`.

### Key Lessons

- Requirement wording should be adjusted promptly when product intent changes, especially for UI display details.
- Milestone close should reconcile tracking metadata before archival to avoid stale pending states.
- Human terminal checks need an explicit owner or they accumulate as close-time debt.

## Milestone: v1.3 — TUI Screen Facelift

**Shipped:** 2026-04-26  
**Phases:** 10 | **Plans:** 48

### What Was Built

- Unicode-safe display-width primitives and migrated layout paths for rows, chrome, modals, main menu, and composers.
- BBS/operator presentation metadata, theme slots, and widget visual contracts.
- Chrome V2 with breadcrumbs, mode-aware status atoms, grouped command bars, and compatibility for legacy key-list callers.
- Classic Modern BBS screen treatment across Home, Board Directory, ThreadList, PostReader, and composer flows.
- Operator Console primitives and Account, Moderation, and Sysop conversions using shared dense-workbench widgets.

### What Worked

- Dependency ordering paid off: width helpers and presentation contracts landed before glyph-heavy layouts and dense operator screens.
- Shared primitives let later phases reuse earlier work instead of forking per-screen rendering logic.
- Layout smoke coverage across 64x22, 80x24, and 132x50 caught terminal size regressions early.

### What Was Inefficient

- ROADMAP and REQUIREMENTS status drifted behind verified implementation for Phase 20 and Phase 22.
- The generated milestone accomplishment extraction included noisy review snippets and file paths, requiring manual cleanup.
- Human terminal checks remained outside the automated verification loop and had to be carried as close debt.

### Patterns Established

- Use `Foglet.TUI.TextWidth` for terminal-cell width, not byte or grapheme length, on layout-sensitive paths.
- Build screen visual upgrades through shared widget primitives before migrating broad screen surfaces.
- Treat 64x22 as a hard non-overlap contract and 80x24 as the compact design target.

### Key Lessons

- Re-run or refresh stale audit artifacts before milestone close; old audit failures can become misleading after gap closure.
- Archive requirements only after reconciling traceability rows and requirement checkboxes to current verification.
- Keep human SSH/TUI checks visible as explicit deferred items when they are accepted as non-blocking.

## Cross-Milestone Trends

| Trend | Observation |
|-------|-------------|
| Planning metadata drift | Requirements and roadmap status can lag behind verified implementation. |
| Reusable TUI primitives | Shared widgets/actions reduce duplicated screen behavior. |
| Human UAT | Terminal visual and keyboard-flow checks remain hard to replace with automated tests. |
