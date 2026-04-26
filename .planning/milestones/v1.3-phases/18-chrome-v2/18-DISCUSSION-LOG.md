# Phase 18: chrome-v2 - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the analysis.

**Date:** 2026-04-25
**Phase:** 18-chrome-v2
**Mode:** assumptions
**Areas analyzed:** Chrome Data Contract, Breadcrumb Ownership, Mode-Aware Status, Responsive Chrome And Tests

## Assumptions Presented

### Chrome Data Contract

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Phase 18 should introduce structured Chrome V2 data while keeping `ScreenFrame` as the single screen-facing composition boundary; existing plain title/key inputs should be normalized through a compatibility path instead of preserving `Chrome.KeyBar` as a separate footer. | Likely | `.planning/phases/18-chrome-v2/18-SPEC.md`; `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex`; named screen callers under `lib/foglet_bbs/tui/screens/` |

If wrong: Planning could either force every screen to duplicate chrome mapping immediately, increasing regression risk across key handling, or accidentally keep `KeyBar` alive as a parallel production footer and fail `CHROME-05`.

### Breadcrumb Ownership

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Breadcrumb paths should be derived centrally from the current screen plus existing screen state/domain state, with screens only supplying extra context where already available, not building breadcrumb text ad hoc in each renderer. | Confident | `.planning/phases/18-chrome-v2/18-SPEC.md`; `.planning/phases/17-theme-and-mode-metadata/17-SPEC.md`; `lib/foglet_bbs/tui/screens/board_list.ex`; `lib/foglet_bbs/tui/screens/thread_list.ex`; `lib/foglet_bbs/tui/screens/post_reader.ex`; `lib/foglet_bbs/tui/screens/new_thread.ex`; `lib/foglet_bbs/tui/screens/account.ex`; `lib/foglet_bbs/tui/screens/moderation.ex`; `lib/foglet_bbs/tui/screens/sysop.ex` |

If wrong: Breadcrumb formatting would drift between screens, and later facelift phases would have to unwind per-screen chrome decisions before adding richer screen bodies.

### Mode-Aware Status

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Status rendering should use Phase 17 presentation mode metadata, not theme identity or screen-local role checks, and should degrade to the current guest/handle/time behavior when richer atoms are unavailable. | Confident | `.planning/phases/17-theme-and-mode-metadata/17-SPEC.md`; `.planning/phases/18-chrome-v2/18-SPEC.md`; `lib/foglet_bbs/tui/widgets/chrome/status_bar.ex`; `test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs` |

If wrong: Operator screens could render BBS status or vice versa, especially when users preview themes, and Phase 18 would violate the Phase 17 contract by inferring mode from visual palette.

### Responsive Chrome And Tests

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Phase 18 should add focused render/contract tests around Chrome V2 primitives plus extend layout smoke coverage for 64x22, 80x24, and wide terminal sizes, using positioned text assertions rather than relying only on collected text strings. | Confident | `.planning/REQUIREMENTS.md`; `.planning/phases/18-chrome-v2/18-SPEC.md`; `.planning/phases/16-unicode-width-foundation/16-CONTEXT.md`; `test/foglet_bbs/tui/layout_smoke_test.exs`; `test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs` |

If wrong: The implementation could pass simple text tests while still overlapping breadcrumbs, status atoms, commands, or content at the hard minimum 64x22 target.

## Corrections Made

No corrections — all assumptions confirmed after the full confidence/consequence view was shown.
