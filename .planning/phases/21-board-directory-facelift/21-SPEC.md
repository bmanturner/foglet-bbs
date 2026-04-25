# Phase 21: Board Directory Facelift — Specification

**Created:** 2026-04-25
**Ambiguity score:** 0.127 (gate: ≤ 0.20)
**Requirements:** 6 locked

## Goal

`BoardList` becomes a Classic Modern BBS board directory: a new `Foglet.TUI.Widgets.List.BoardTree` wrapper renders categories with `▾`/`▸` state and emits each board row through Phase 20's `Foglet.TUI.Widgets.List.RichRow` with semantic columns — leading read-state glyph (`●`/`◇`), board name, subscription state column (`✓ required` / `✓ subscribed` / `+ subscribe`), and unread count — replacing today's single embedded label string `"name [required] (3 unread)"`. A 64x22-safe compact details strip beneath the tree describes the focused board (or category) using `name • state • unread • last post age`, fed by a new `:last_post_at` field on `Foglet.Boards.directory_board`. The wide-terminal inspector pane is deferred.

## Background

`Foglet.TUI.Screens.BoardList` (`lib/foglet_bbs/tui/screens/board_list.ex`) renders the directory through `Foglet.TUI.Widgets.Display.Tree` (`lib/foglet_bbs/tui/widgets/display/tree.ex`). `Display.Tree` builds a single label string per node — categories use `node.name`, boards use `board_label/4` to assemble `"#{name} [required]#{unread_suffix(...)}"`, `"#{name} [subscribed]#{unread_suffix(...)}"`, or `"#{name} [unsubscribed]"` (lines 222–230). Display.Tree's only state glyphs are `▼` (expanded) and `▶` (collapsed) — different from the SCREENS.md target `▾`/`▸`. The `Foglet.Threads.ThreadEntry`-style `:locked` cue and the SCREENS.md per-board glyphs (`●`/`◇`/`✓`/`+`) are not rendered at all today.

`Foglet.Boards.board_directory_for/1` (`lib/foglet_bbs/boards.ex:243-271`) returns a list of `%{category, boards: [%{board, subscribed?, required_subscription?, unread_count}]}`. There is no per-board `last_post_at` on this surface today — `last_post_at` exists only on `Foglet.Threads.Thread` and is exposed up to the UI through `Foglet.Threads.ThreadEntry`. A details strip showing "last post Xm ago" therefore requires extending `directory_board` with a new field, joined from threads.

Phase 20 (in flight on a parallel track) introduces `Foglet.TUI.Widgets.List.RichRow` as a generic state-cluster row primitive with leading state glyphs, primary text, right metadata, selection rendering, and theme routing. Its acceptance contract requires a non-thread state shape (e.g. `[:subscribed, :required]` or equivalent) so `BoardList` can adopt it directly. Phase 25 (Operator Console Conversion) is a future consumer of the same primitive seam — `BoardTree` lands here so Sysop board screens can later reuse it.

Existing `BoardList` workflows (j/k or ↑/↓ navigation, ←/→ collapse/expand, Enter open, s/u subscribe/unsubscribe, q/Q back), feedback flash for "Already subscribed" / "This board is a required subscription" / "Not subscribed", and `BoardList.State` (`:tree`, `:feedback`) are functionally preserved — same actions reachable from the same keys, but state-transition shapes may evolve where the new primitive seam is more idiomatic.

This phase is not a `Display.Tree` rewrite. `Display.Tree` keeps its current contract for any other future tree consumers; `BoardTree` is a new wrapper that internally orchestrates `Display.Tree` for category state and `RichRow` for board rows.

## Requirements

1. **`BoardTree` wrapper lands**: A new `Foglet.TUI.Widgets.List.BoardTree` widget renders categories with `▾`/`▸` state and routes each board row through `Foglet.TUI.Widgets.List.RichRow`.
   - Current: `BoardList` renders directly through `Foglet.TUI.Widgets.Display.Tree`, which emits a single label string per node and uses `▼`/`▶` glyphs.
   - Target: `Foglet.TUI.Widgets.List.BoardTree` exists at `lib/foglet_bbs/tui/widgets/list/board_tree.ex` with a public render entry point and a documented `@moduledoc`. Categories render with `▾` (expanded) and `▸` (collapsed) glyphs; board rows are emitted via `RichRow` with a state-cluster shape that includes read state and subscription state. `Foglet.TUI.Screens.BoardList` renders through `BoardTree`, not directly through `Display.Tree`.
   - Acceptance: A focused render test asserts (a) `BoardTree` renders an expanded category row containing `▾`, (b) a collapsed category row containing `▸`, (c) board rows are produced through `RichRow` (test detects RichRow's state-cluster shape, not by source-grep), and (d) `BoardList` source contains no remaining direct `Foglet.TUI.Widgets.Display.Tree` reference in its row render path.

2. **Board row state glyphs**: Board rows show read state (`●` unread, `◇` read) and subscription state (`✓ required`, `✓ subscribed`, `+ subscribe`) as semantic columns, replacing the current `[required]` / `[subscribed]` / `[unsubscribed]` text suffix.
   - Current: `BoardList.board_label/4` embeds subscription state as bracketed text (`"name [required] (N unread)"`); read state is not visualized at all; the `unread_count` is rendered as a parenthesized suffix only when `>= 1`.
   - Target: Each board row begins with a fixed-width leading state cluster containing `●` when `unread_count >= 1` and `◇` when `unread_count == 0` (or unread_count is nil for unsubscribed boards). The subscription state column shows `✓ required` when `required_subscription?: true`, `✓ subscribed` when `subscribed?: true and required_subscription?: false`, and `+ subscribe` when `subscribed?: false`. The trailing column shows `N unread` when `unread_count >= 1`, `all read` when `unread_count == 0`, and is absent when `unread_count` is nil. No row contains `[required]`, `[subscribed]`, or `[unsubscribed]` literal text.
   - Acceptance: A focused render test asserts each combination — (subscribed × read), (subscribed × unread), (required × read), (required × unread), (unsubscribed × read), (unsubscribed × unread, where applicable) — produces the expected glyphs and column text per the table above, and asserts no row contains the literal strings `"[required]"`, `"[subscribed]"`, or `"[unsubscribed]"`.

3. **`directory_board` exposes `last_post_at`**: `Foglet.Boards.board_directory_for/1` returns a `:last_post_at` field on every board entry.
   - Current: `Foglet.Boards.directory_board` typespec is `%{board, subscribed?, required_subscription?, unread_count}` (`lib/foglet_bbs/boards.ex:224-229`); no per-board last-post timestamp is exposed.
   - Target: The typespec becomes `%{board, subscribed?, required_subscription?, unread_count, last_post_at}` where `last_post_at: DateTime.t() | nil`. The value is the maximum `Foglet.Threads.Thread.last_post_at` across non-deleted threads in the board, or `nil` when the board has no non-deleted threads. The field is populated identically for subscribed and unsubscribed boards (boards are public-readable; subscription state does not affect this field).
   - Acceptance: A context test asserts that for a board with three non-deleted threads of known `last_post_at` values, `board_directory_for/1` returns the max value in `:last_post_at`; for a board with no non-deleted threads, returns `nil`; and that the value is identical for the same board regardless of whether the requesting actor is subscribed.

4. **Details strip for focused row**: A 64x22-safe compact details strip beneath the tree describes the focused board or category.
   - Current: No details strip exists; `BoardList` renders only the tree (and optional feedback line) inside the `ScreenFrame` body.
   - Target: When the focused tree node is a board, the details strip renders `{board.name} • {state} • {unread} • {last post age}` where `state` is one of `required` / `subscribed` / `subscribe` (matching the row's subscription state column word), `unread` is `N unread` / `all read` / omitted when `unread_count` is nil, and `last post age` is a humanized form (e.g. `"12m ago"`, `"2h ago"`, `"3d ago"`, `"no posts yet"` when `last_post_at` is nil). When the focused node is a category, the strip renders `{category.name} • {N boards} • {M unread total}` where `M` is the sum of unread counts across visible boards in that category. The strip renders inside the `ScreenFrame` body and remains visible at 64x22.
   - Acceptance: A focused render test at 64x22 asserts (a) a focused subscribed board row produces the expected `name • subscribed • N unread • Xm ago` line, (b) a focused unsubscribed board row produces the expected `name • subscribe • • last post age` line (or analogous form when `unread_count` is nil), (c) a focused category row produces the expected `name • N boards • M unread total` line, and (d) the details strip is present and not clipped at 64x22.

5. **64x22 priority contract — name truncates first**: At a 64-cell content width, the leading state cluster, subscription state column, and trailing unread column always render fully; the board name is the only segment allowed to truncate.
   - Current: Single embedded label string is rendered without an explicit width contract — there is no separate state cluster, subscription column, or unread column to truncate independently today.
   - Target: `BoardTree` (via `RichRow`) preserves Phase 20's priority contract for board rows: the leading state cluster width is fixed; the subscription state column renders in full; the trailing unread column renders in full; the board name truncates with `…` when content exceeds the width budget, with at least Phase 20's 20-cell minimum name attempt before below-minimum fallback.
   - Acceptance: A focused render test renders a board with a long name at 64-cell content width and asserts (a) the leading read-state glyph is fully present, (b) the subscription state column text (`✓ required` / `✓ subscribed` / `+ subscribe`) is present in full, (c) the unread column text is present in full when `unread_count >= 1` or `== 0`, (d) the board name contains `…`, and (e) total row display-width does not exceed 64 cells.

6. **Workflows functionally preserved**: Existing open, expand/collapse, subscribe, unsubscribe, and back actions remain reachable from existing keys with equivalent outcomes.
   - Current: j/k and ↑/↓ navigate; ←/→ collapse/expand; Enter opens the focused board into the thread list (loading threads); `s` subscribes; `u` unsubscribes (refusing if `required_subscription?`); q/Q returns to main menu. Feedback flash strings `"Already subscribed."`, `"Not subscribed."`, and `"This board is a required subscription."` render through `maybe_feedback/2`.
   - Target: Each existing key remains bound to its current action and produces the equivalent outcome (open, expand/collapse, subscribe, unsubscribe with required-subscription guard, back). Subscription feedback is still surfaced to the user through some user-visible mechanism (the same top-of-tree flash line, an inline indication on the row, or another visible treatment) but the exact mechanism may evolve as the new primitive seam is more idiomatic. State-transition shapes (e.g. how `BoardList.State` stores tree state) may change so long as functional behavior is preserved.
   - Acceptance: A focused screen test asserts (a) j, k, ↑, ↓, ←, →, Enter, s, u, q, Q each produce a state transition consistent with their pre-Phase-21 outcome (open/navigate/expand-collapse/subscribe/unsubscribe/back) — same destination action, same authorization guards, same `:load_threads` command emission on Enter for a board node, (b) attempting `u` on a `required_subscription?: true` board surfaces a user-visible "required" message and does not emit an unsubscribe command, and (c) the empty-directory and loading states render through their existing "No active boards are available." text and spinner row paths respectively.

## Boundaries

**In scope:**
- New `Foglet.TUI.Widgets.List.BoardTree` widget under `lib/foglet_bbs/tui/widgets/list/`.
- Migration of `Foglet.TUI.Screens.BoardList` from direct `Display.Tree` rendering to `BoardTree`.
- Category-row glyphs `▾` (expanded) and `▸` (collapsed).
- Board-row leading state cluster: `●` unread, `◇` read.
- Board-row subscription state column: `✓ required`, `✓ subscribed`, `+ subscribe` (visual treatment only — no new keyboard binding).
- Board-row trailing unread column: `N unread`, `all read`, or absent (when `unread_count` is `nil`).
- Removal of `[required]`, `[subscribed]`, `[unsubscribed]` text suffixes from `BoardList` rendering.
- Compact details strip beneath the tree for focused board OR focused category, 64x22-safe.
- Extension of `Foglet.Boards.directory_board` typespec and `board_directory_for/1` implementation with `:last_post_at` (max of non-deleted thread `last_post_at`, or `nil`).
- Size-contract render coverage at 64x22, 80x24, and at least one wider terminal size.
- `@moduledoc` documentation of the `BoardTree` public API for Phase 25 adopters.
- Functional preservation of j/k, ↑/↓, ←/→, Enter, s, u, q/Q workflows including required-subscription guard and empty/loading states.

**Out of scope:**
- Wide-terminal inspector pane on the right (board description, posting policy, full subscription/unread detail) — matches Phase 20's deferral pattern; can be added in a later phase as progressive enhancement.
- ASCII-only fallback glyph set — Phase 20 locked single-Unicode-set across themes; Phase 21 inherits.
- Changes to `Foglet.Boards.Category`, `Foglet.Boards.Board`, or `Foglet.Boards.Subscription` schemas — the phase consumes existing schema fields and adds only one virtual field on the `directory_board` map.
- Changes to `Foglet.TUI.Widgets.Display.Tree` itself — Display.Tree keeps its current contract for any other future consumers; `BoardTree` is a new wrapper that orchestrates Display.Tree from above.
- Changes to `Foglet.TUI.Widgets.List.RichRow` API — Phase 21 consumes the API Phase 20 ships and does not modify it.
- New keyboard binding for "+ subscribe" — `+` is visual state only; subscription remains on the existing `s` key.
- Changes to `Foglet.Threads`, `Foglet.Posts`, or any persistence layer beyond the `last_post_at` derivation in `board_directory_for/1`.
- Changes to the `Sysop` board management screen (`lib/foglet_bbs/tui/screens/sysop/boards_view.ex`). That screen adopts `BoardTree` (or not) inside its own roadmap phase.
- Verbatim preservation of subscription-feedback flash placement — the user-visible feedback is preserved but the exact mechanism (top-of-tree line vs inline row vs other) may evolve.

## Constraints

- Foglet remains SSH-first/TUI-first. No browser workflow is introduced.
- All rendering must continue to flow through `Foglet.TUI.Widgets.Chrome.ScreenFrame.render/4` and theme-routed primitives. No hardcoded color atoms in `BoardTree`, `BoardList`, or the details strip.
- All width math must use `Foglet.TUI.TextWidth` helpers (display width, truncation, padding). Byte-length, grapheme-count, and `String.length/1` are not allowed for layout decisions.
- Glyph rendering uses the single Unicode set established by Phase 20. No per-theme ASCII fallback.
- The leading state cluster's display width is fixed and identical across all (read/unread, subscribed/required/unsubscribed) combinations so columns stay aligned.
- `BoardTree` adheres to the `Foglet.TUI.Theme` slot vocabulary already established by Phase 17 (no new slots are introduced for Phase 21).
- The 20-cell minimum board-name attempt established by Phase 20's `RichRow` priority contract is preserved.
- `last_post_at` derivation in `board_directory_for/1` must not introduce N+1 queries — it joins through the threads relation in a single query (or one bounded query per call) consistent with the rest of `board_directory_for/1`.
- `Foglet.Threads.Thread`'s `:deleted_at` (or equivalent soft-delete flag) is respected — `last_post_at` is computed only across non-deleted threads.
- No new database query, schema field, or context API beyond the additive `:last_post_at` field on `directory_board` is introduced.
- Tests use `start_supervised!/1` for any supervised processes; no `Process.sleep/1` or `Process.alive?/1` synchronization.

## Acceptance Criteria

- [ ] `Foglet.TUI.Widgets.List.BoardTree` module exists at `lib/foglet_bbs/tui/widgets/list/board_tree.ex` with a public render entry point and `@moduledoc`.
- [ ] `Foglet.TUI.Screens.BoardList` source contains no direct `Foglet.TUI.Widgets.Display.Tree` reference in its row render path.
- [ ] An expanded category row contains `▾`; a collapsed category row contains `▸`.
- [ ] Board rows are emitted through `RichRow` (verifiable via the RichRow state-cluster shape in the rendered view).
- [ ] An unread board row's leading cluster contains `●`; a read board row's contains `◇`.
- [ ] A required board row's subscription column reads `✓ required`; a subscribed (non-required) row's reads `✓ subscribed`; an unsubscribed row's reads `+ subscribe`.
- [ ] An `unread_count >= 1` row's trailing column reads `N unread`; an `unread_count == 0` row's reads `all read`; an `unread_count == nil` row has no trailing unread text.
- [ ] No board row in any rendered state contains the literal strings `"[required]"`, `"[subscribed]"`, or `"[unsubscribed]"`.
- [ ] At 64-cell content width with a long board name, the name truncates with `…` while the leading state cluster, subscription state column, and trailing unread column all render in full.
- [ ] `Foglet.Boards.board_directory_for/1` returns a `:last_post_at` field on every board entry.
- [ ] `:last_post_at` equals the max `Foglet.Threads.Thread.last_post_at` across non-deleted threads in the board (or `nil` when no non-deleted threads exist), and is identical for subscribed and unsubscribed actors on the same board.
- [ ] `:last_post_at` is computed without introducing N+1 queries beyond the existing `board_directory_for/1` query budget.
- [ ] A focused board row renders a details strip line `{name} • {state} • {unread} • {last post age}` at 64x22, where `last post age` is humanized (`"Xm ago"` / `"Xh ago"` / `"Xd ago"` / `"no posts yet"`).
- [ ] A focused category row renders a details strip line `{name} • {N boards} • {M unread total}` at 64x22.
- [ ] Each existing key (j, k, ↑, ↓, ←, →, Enter, s, u, q, Q) produces a state transition equivalent to its pre-Phase-21 outcome (open/navigate/expand-collapse/subscribe/unsubscribe/back).
- [ ] `u` on a `required_subscription?: true` focused board surfaces a user-visible "required" message and does not emit an unsubscribe command.
- [ ] The empty-directory state renders `"No active boards are available."`; the loading state renders the spinner row.
- [ ] No `BoardTree`, `BoardList`, or details-strip code path references a hardcoded color outside `Foglet.TUI.Theme`.
- [ ] Size-contract render tests cover 64x22, 80x24, and at least one wider terminal size.

## Ambiguity Report

| Dimension          | Score | Min   | Status | Notes                                                                       |
|--------------------|-------|-------|--------|-----------------------------------------------------------------------------|
| Goal Clarity       | 0.92  | 0.75  | met    | BoardTree+RichRow seam, glyph set, details strip data, inspector deferral locked. |
| Boundary Clarity   | 0.90  | 0.70  | met    | In/out scope explicit; Display.Tree, Sysop screen, RichRow API, schemas excluded. |
| Constraint Clarity | 0.85  | 0.65  | met    | 64x22 priority, name truncates first, no N+1, single Unicode set, Theme-routed. |
| Acceptance Criteria| 0.78  | 0.70  | met    | 19 pass/fail criteria covering glyphs, columns, truncation, data layer, workflows. |
| **Ambiguity**      | 0.127 | ≤0.20 | met    | Gate passed.                                                                |

Status: met = meets minimum, below = planner treats as assumption

## Interview Log

| Round | Perspective     | Question summary                                                                 | Decision locked                                                                                                  |
|-------|-----------------|----------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------|
| 1     | Researcher      | How should Phase 21 render board rows (RichRow / BoardRow / Tree.render_row)?    | BoardTree wrapper that uses Phase 20's RichRow for board rows; categories render through a separate code path.   |
| 1     | Researcher      | Should `directory_board` gain `last_post_at`, or should details strip use existing data? | Add `last_post_at` to `directory_board` (faithful to SCREENS.md sketch); accept domain/data-layer change.        |
| 1     | Researcher      | Wide-terminal inspector pane in this phase or deferred?                          | Compact details strip only; wide inspector deferred to a later phase (matches Phase 20 deferral pattern).        |
| 2     | Boundary Keeper | Lock SCREENS.md glyph set as-is, or distinguish required vs subscribed visually? | Lock SCREENS.md set as-is: `▾`/`▸`, `●`, `◇`, `✓` (subscribed AND required), `+`. Required vs subscribed differs in column text. |
| 2     | Simplifier      | Is "+ subscribe" a visual state column or a new keyboard binding?                | Visual state column only; existing `s` key preserves subscribe workflow verbatim.                                |
| 2     | Constraint      | `last_post_at` for unsubscribed boards: nil or always populate?                  | Always populate; boards are public-readable so subscription state does not gate this field.                       |
| 3     | Boundary Keeper | At 64x22, what truncates first when a row overflows?                             | Board name truncates first with `…`; state cluster, subscription column, and unread column render in full. Mirrors Phase 20. |
| 3     | Failure Analyst | How strict is BOARDS-03 workflow preservation for SPEC acceptance?               | Functional preservation only — same actions reachable from same keys; bindings/transitions may evolve where the new primitive seam is more idiomatic. |

---

*Phase: 21-board-directory-facelift*
*Spec created: 2026-04-25*
*Next step: /gsd-discuss-phase 21 — implementation decisions (BoardTree internal API, RichRow state-cluster shape for boards, details-strip rendering surface, last_post_at query strategy)*
