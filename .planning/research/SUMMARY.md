# Project Research Summary

**Project:** Foglet BBS v1.3 TUI Screen Facelift
**Domain:** SSH-first terminal UI facelift, Raxol widgets, Unicode-aware terminal layout
**Researched:** 2026-04-25
**Confidence:** HIGH

## Executive Summary

External ecosystem research was skipped for this milestone. `SCREENS.md` is a
project-specific PRD with concrete visual direction, target screens, primitive
gaps, implementation order, and Unicode width risks. The milestone should use
that PRD plus the existing TUI widget catalog as the source of truth.

The decisive implementation constraint is sequence. Width-aware text helpers
must land before glyph-heavy aligned layouts, shared chrome should land before
screen-by-screen facelift work, and the operator-console conversion should wait
until common row/table/grid/badge primitives are stable.

## Key Inputs

- `SCREENS.md` defines the Classic Modern BBS and Operator Console directions.
- `lib/foglet_bbs/tui/widgets/README.md` defines local widget placement,
  theming, and testing conventions.
- `docs/raxol/getting-started/WIDGET_GALLERY.md` confirms the existing Raxol
  primitives available for layout, text, display, input, and tables.
- Code search found layout-sensitive `String.length/1`, `String.slice/3`, and
  `String.split_at/2` usage in list rows, composers, main menu clipping,
  moderation rows, account forms, sysop forms, and verification input.

## Seed Selection

No planted seeds were selected. The current seed files cover webhook
notifications and email verification UX; neither matches the TUI facelift scope.

## Ready For Roadmap

Yes. Requirements and roadmap should proceed from `SCREENS.md`.

---
*Research synthesis updated: 2026-04-25 after PRD-based milestone initialization*
