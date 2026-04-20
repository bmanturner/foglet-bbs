# Phase 7: Migrate hand-rolled UI components to Raxol widgets — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-20
**Phase:** 07-migrate-hand-rolled-ui-components-to-raxol-widgets
**Areas discussed:** Scope, Modal theme injection, Namespace organization

---

## Scope

The initial gray area analysis identified only `Widgets.Modal` (hardcoded color atoms) and `Widgets.Compose` (flat namespace) as candidates. The user corrected this with a full research list covering 6 components.

**User's research list:** Modal, SelectionList (base), SelectionList (full), PostReader scroll windowing, MarkdownBody, StatusBar, Verify code buffer.

**Mental model clarification:** Phase 7 is about replacing hand-rolled implementations with Raxol primitives where a built-in equivalent already exists — not about theming fixes or namespace reorganization.

---

## MarkdownBody gap

| Option | Description | Selected |
|--------|-------------|----------|
| Wrap it — thin wrapper adds color back | Use MarkdownRenderer as base, add theme colors on top | |
| Accept the gap — use Raxol defaults | Drop custom accent colors | |
| Skip it — keep hand-rolled | Custom pipeline + accent colors worth preserving | ✓ |

**User's choice:** Skip — keep hand-rolled
**Notes:** The custom Foglet.Markdown render pipeline with accent color mapping is the reason to keep it. MarkdownRenderer base rendering isn't worth losing the theme integration.

---

## StatusBar gap

| Option | Description | Selected |
|--------|-------------|----------|
| Skip it — keep hand-rolled | Reverse-video is genuine BBS aesthetic, tiny impl | |
| Wrap it — Display.StatusBar + custom style | Use Raxol layout, add reverse-video on top | |
| Accept the gap — lose reverse-video | Migrate to Display.StatusBar, drop reverse-video styling | ✓ |

**User's choice:** Accept the gap — lose reverse-video
**Notes:** User consciously chose to drop the reverse-video treatment when migrating. However D-16 in CONTEXT preserves a guard: if Display.StatusBar ALSO can't accept our hex colors, keep hand-rolled entirely.

---

## Verify code buffer gap

| Option | Description | Selected |
|--------|-------------|----------|
| Skip it — keep hand-rolled | [ABC___] mask is a deliberate UX choice | ✓ |
| Wrap it — text_input + custom mask renderer | Use text_input for input management, add mask | |
| Accept the gap — plain text_input | Drop [___] mask display | |

**User's choice:** Skip — keep hand-rolled
**Notes:** The [ABC___] 6-character mask display is a deliberate UX choice that plain text_input can't reproduce without a custom renderer — at which point it's still hand-rolled.

---

## Modal theme injection

**Question:** Full replacement (delete Widgets.Modal) vs thin adapter (facade)?

User's follow-up: "Does either option allow us to keep our theme colors intact?"

Resolution: Raxol Modal theming API is unverified, so the question can't be answered without checking. The same applies to all Raxol components.

| Option | Description | Selected |
|--------|-------------|----------|
| Thin adapter — keep theme control | Widgets.Modal stays as facade | |
| Verify first, then decide | Check docs/raxol/cookbook/THEMING.md before committing | ✓ |

**User's choice:** Verify first — and this gate applies to ALL five migration targets
**Notes:** User pointed to `docs/raxol/cookbook/THEMING.md` as the source of truth. If a Raxol component supports theme injection → full replacement. If not → thin adapter.

---

## SelectionList

| Option | Description | Selected |
|--------|-------------|----------|
| One pass — evaluate each use site | Check board list + thread list in context, use right tier per site | ✓ |
| Base first, full second | Two separate plans | |

**User's choice:** One pass
**Notes:** ListRow's metadata variant (@handle · N posts · Xh ago) is genuinely custom and kept regardless of base SelectionList migration.

---

## Namespace / caller updates

| Option | Description | Selected |
|--------|-------------|----------|
| Update callers in the same pass | No orphan aliases; clean state per commit wave | ✓ |
| Add transition aliases | Smaller per-commit diffs, then clean up | |

**User's choice:** Update callers in same pass

---

## Claude's Discretion

- Thin adapter API shape (pass `%Theme{}` vs full `state`) — planner decides, following existing module patterns
- Plan breakdown (one plan per target vs bundled) — planner decides

## Deferred Ideas

None — discussion stayed within phase scope.
