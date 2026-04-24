# Phase 7: Oneliners and Main Menu Social Strip — Specification

**Created:** 2026-04-24
**Ambiguity score:** 0.09 (gate: <= 0.20)
**Requirements:** 6 locked

## Goal

The main menu shows recent persisted oneliners and lets an authenticated user post one short oneliner through a focused composer without turning the menu into a chat surface.

## Background

The roadmap and data model already define oneliners as a persistent BBS atmosphere feature: `oneliners` records have a body, user, hidden flag, and timestamps; recent visible entries are intended to be cached in a ring buffer for fast main-menu rendering; and moderation hide behavior is explicitly owned by Phase 8. The current codebase has no `Foglet.Oneliners` context, no `Foglet.Oneliners.Entry` schema, no `oneliners` migration, and no main-menu social strip. `Foglet.TUI.Screens.MainMenu` is currently stateless, rendering only welcome text and navigation entries through `ScreenFrame`; key handlers route to boards, thread composition, Account, Moderation, Sysop, and logout.

## Requirements

1. **Persistent oneliner records**: Oneliners are stored in the database with author, body, visibility state, and creation time.
   - Current: `docs/DATA_MODEL.md` specifies an `oneliners` table, but no schema, migration, or context exists in `lib/`.
   - Target: The application has a persisted oneliner model with `body`, `hidden`, `hidden_reason`, `user_id`, `hidden_by_id`, and creation timestamp fields compatible with the documented data model.
   - Acceptance: A database-backed test can insert an oneliner through the public domain API, reload it from the repository after process restart-equivalent test setup, and observe the same author, body, hidden state, and timestamp data.

2. **Bounded posting**: Authenticated users can create visible oneliners whose body is non-empty and no longer than 120 characters.
   - Current: There is no oneliner creation API and no configured maximum length consumer.
   - Target: The public oneliner creation API accepts an authenticated user and a body, trims or rejects blank content, rejects bodies longer than 120 characters, and stores accepted entries as visible by default.
   - Acceptance: Tests prove a valid 120-character body is accepted, a 121-character body is rejected with a changeset/domain error, blank content is rejected, and accepted entries default to `hidden: false`.

3. **Recent visible list**: The main-menu strip reads a bounded list of recent visible oneliners, newest first.
   - Current: `MainMenu.render/1` has no oneliner data and no social strip; hidden oneliner handling exists only in the data model.
   - Target: The domain API returns the most recent visible oneliners in descending creation order with author data preloaded for rendering, excluding hidden entries.
   - Acceptance: Given more than the display limit worth of visible entries plus at least one hidden entry, the list API returns only visible entries, newest first, capped to the requested limit, with author handles available without additional lazy loading.

4. **Split-pane main-menu display**: Authenticated users can view recent oneliners in a right-side split-pane on the main menu without obscuring existing navigation.
   - Current: The main menu renders welcome text and navigation items only, and existing layout smoke coverage expects those rows to fit within 80x24.
   - Target: The main-menu content uses `split_pane(direction: :horizontal, ratio: {2, 3}, min_size: 24, children: [menu_panel, oneliners_panel])`, with navigation on the left and an `Oneliners` panel on the right.
   - Acceptance: Rendering the main menu with zero oneliners, one oneliner, and more entries than the display limit does not crash, keeps navigation text/key bindings visible in the left pane, and includes only the bounded recent strip content in the right pane.

5. **Oneliner row presentation**: Each displayed oneliner row shows the author handle and body in a compact single-line format.
   - Current: There is no oneliner strip and no display contract for author/body rows.
   - Target: Rows render as `@handle  body`, with the handle visually distinct from the body, handles visually capped around 12 characters, and body text clipped or truncated to the pane width.
   - Acceptance: Rendering a long handle and long body keeps each oneliner to one row, preserves the `@handle  body` shape, does not overlap adjacent rows or navigation, and does not render timestamps in the main-menu strip.

6. **Focused posting flow**: Posting starts from the main menu but uses a focused composer/modal and returns to the main menu after submit or cancel.
   - Current: `MainMenu` has no oneliner key binding and remains stateless; existing text entry flows live outside the menu itself.
   - Target: The `[O]` main-menu key binding opens a focused oneliner composer/modal, submit creates a valid oneliner and returns to `:main_menu`, and cancel returns to `:main_menu` without creating an entry.
   - Acceptance: TUI tests prove the posting key opens the focused composer/modal, valid submit persists one oneliner and returns to the main menu, invalid over-length submit surfaces validation without persisting, and cancel returns to the main menu with no new record.

## Boundaries

**In scope:**
- Database persistence for oneliner entries compatible with the documented `oneliners` table shape.
- A public oneliner domain API for creating entries and listing recent visible entries.
- A hard 120-character body limit with non-blank validation.
- Main-menu rendering of a bounded recent visible oneliner strip in a right-side horizontal split-pane.
- `@handle  body` row presentation without timestamps in the main-menu strip.
- A focused composer/modal launched from `[O]` on the main menu for quick posting.
- Tests covering persistence, length validation, visible-only listing, split-pane main-menu rendering, row clipping/truncation, and posting/cancel flows.

**Out of scope:**
- Moderation hide UI or operator hide commands — Phase 8 owns `MODR-05` and the populated moderation workspace.
- Chat-like real-time conversation behavior, threaded replies, reactions, or live typing — requirements define a lightweight social strip, not chat.
- Sysop-editable oneliner policy, retention windows, or configurable max length — `SYSO-06` and richer oneliner controls are v2 scope.
- Backfilling old data or importing oneliners from another system — no existing oneliner storage exists.
- Broad main-menu redesign or new community presence widgets beyond the oneliner strip — `MENU-03` is v2 scope.

## Constraints

- Oneliner bodies are capped at exactly 120 characters in Phase 7.
- Main-menu display uses a horizontal `split_pane` with navigation on the left and oneliners on the right; at the 80x24 baseline it must not hide current navigation entries or keybar affordances.
- Oneliner strip rows must use `@handle  body`, omit timestamps, cap displayed handles around 12 characters, and keep each entry to a single visual row by clipping or truncating body text to the pane width.
- The domain listing API must preload author data needed by rendering; templates/renderers must not rely on nonexistent lazy loading.
- Persistence is authoritative. Any ring-buffer or cache behavior may improve rendering but cannot be the only source of truth.
- Moderation-related schema fields may exist for forward compatibility, but Phase 7 must not expose hide behavior to operators.

## Acceptance Criteria

- [ ] The `oneliners` table and schema persist body, author, hidden state, hidden reason, hidden-by reference, and creation timestamp data.
- [ ] The public oneliner creation API accepts valid authenticated posts up to 120 characters.
- [ ] Blank oneliner bodies and bodies longer than 120 characters are rejected without inserting a row.
- [ ] Recent oneliner listing returns visible entries only, newest first, capped to the requested limit, with author handles available for rendering.
- [ ] The main menu renders navigation on the left and an `Oneliners` panel on the right through a horizontal `split_pane`.
- [ ] The split-pane main menu renders correctly for zero, one, and many oneliners while preserving existing navigation entries and key handling.
- [ ] Oneliner rows render as `@handle  body`, omit timestamps, and remain one visual row each even with long handles or bodies.
- [ ] The `[O]` main-menu posting key opens a focused composer/modal rather than embedding text-entry state directly in the menu.
- [ ] Valid composer submit persists one oneliner and returns to the main menu.
- [ ] Invalid composer submit surfaces validation and does not persist an oneliner.
- [ ] Composer cancel returns to the main menu without creating an oneliner.
- [ ] No Phase 7 UI exposes moderation hide behavior.

## Ambiguity Report

| Dimension           | Score | Min   | Status | Notes |
|---------------------|-------|-------|--------|-------|
| Goal Clarity        | 0.94  | 0.75  | met    | ONEL-01 through ONEL-03 plus the split-pane social-strip goal define a specific visible outcome. |
| Boundary Clarity    | 0.90  | 0.70  | met    | Moderation, chat behavior, sysop policy, retention, timestamps in the strip, and broader presence widgets are explicitly excluded. |
| Constraint Clarity  | 0.86  | 0.65  | met    | The 120-character limit, split-pane layout, row format, 80x24 fit, preloading, and persistence authority constraints are locked. |
| Acceptance Criteria | 0.88  | 0.70  | met    | Pass/fail checks cover persistence, validation, listing, split-pane rendering, row presentation, composer submit, cancel, and moderation exclusion. |
| **Ambiguity**       | 0.09  | <=0.20| met    | Weighted clarity passes the spec gate. |

Status: met = meets minimum, below = below minimum (planner treats as assumption)

## Interview Log

| Round | Perspective | Question summary | Decision locked |
|-------|-------------|------------------|-----------------|
| 1 | Researcher | What exists today for oneliners and main-menu behavior? | The data model and architecture describe oneliners, but the code has no oneliner context/schema/migration or main-menu strip; `MainMenu` is currently stateless navigation. |
| 1 | Researcher | Should Phase 7 include only visible, non-moderation behavior? | Yes. Phase 7 may include forward-compatible hidden fields, but hide/moderation behavior is deferred to Phase 8. |
| 1 | Researcher + Simplifier | What exact body length should be locked? | Oneliner bodies are capped at exactly 120 characters. |
| 1 | Researcher + Simplifier | Should posting be inline or focused? | Posting uses a focused composer/modal launched from the main menu, then returns to the main menu on submit or cancel. |
| 2 | Boundary Keeper | How should the social strip be presented on the main menu? | Use a horizontal `split_pane` with navigation on the left and an `Oneliners` panel on the right. |
| 2 | Boundary Keeper | How should each oneliner present the user and text? | Render rows as `@handle  body`, visually distinguish/cap the handle, truncate or clip body text to one row, and omit timestamps in the main-menu strip. |

---

*Phase: 07-oneliners-and-main-menu-social-strip*
*Spec created: 2026-04-24*
*Next step: $gsd-discuss-phase 7 — implementation decisions (how to build what's specified above)*
