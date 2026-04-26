---
phase: 22
slug: post-reader-facelift
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-04-25
---

# Phase 22 - Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit with project aliases |
| **Config file** | `test/test_helper.exs` plus `FogletBbs.DataCase` for layout smoke |
| **Quick run command** | `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs test/foglet_bbs/tui/widgets/post/post_card_test.exs` |
| **Full suite command** | `rtk mix precommit` |
| **Estimated runtime** | ~120 seconds |

## Sampling Rate

- **After every task commit:** Run `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs`
- **After every plan wave:** Run `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs test/foglet_bbs/tui/widgets/post/post_card_test.exs test/foglet_bbs/tui/layout_smoke_test.exs`
- **Before `$gsd-verify-work`:** `rtk mix precommit` must be green
- **Max feedback latency:** 120 seconds

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 22-01-01 | 01 | 1 | READER-01, READER-04 | T-22-01 | Rendering uses existing post data only; no new domain side effects | widget unit | `rtk mix test test/foglet_bbs/tui/widgets/post/post_card_test.exs` | yes | pending |
| 22-01-02 | 01 | 1 | READER-02 | T-22-02 | Gutter wrapping preserves markdown nodes instead of stringifying content | widget unit | `rtk mix test test/foglet_bbs/tui/widgets/post/post_card_test.exs` | yes | pending |
| 22-02-01 | 02 | 2 | READER-01, READER-02, READER-03, READER-04 | T-22-01, T-22-02 | Header/progress stay outside `Viewport`; body rows stay bounded | screen render | `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs` | yes | pending |
| 22-02-02 | 02 | 2 | READER-03 | T-22-03 | Navigation, reply/back, cache, and read-pointer behavior remain unchanged | screen behavior | `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs` | yes | pending |
| 22-03-01 | 03 | 3 | READER-02, READER-03 | T-22-01, T-22-02 | 64x22, 80x24, and 132x50 positioned text stays inside bounds | layout smoke | `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` | yes | pending |
| 22-03-02 | 03 | 3 | READER-01, READER-02, READER-03, READER-04 | T-22-01, T-22-02, T-22-03 | Full project gates pass after the facelift | full suite | `rtk mix precommit` | yes | pending |

## Wave 0 Requirements

- [ ] `test/foglet_bbs/tui/widgets/post/post_card_test.exs` - helper assertions for reader header, compact progress, and guttered body rows if a public helper is introduced.
- [ ] `test/foglet_bbs/tui/screens/post_reader_test.exs` - render assertions for compact header, message number, gutter, progress, and behavior preservation.
- [ ] `test/foglet_bbs/tui/layout_smoke_test.exs` - Phase 22 size-contract block for `{64,22}`, `{80,24}`, and `{132,50}`.

## Manual-Only Verifications

All Phase 22 behaviors have automated verification.

## Threat Model

| Ref | Threat | Severity | Mitigation |
|-----|--------|----------|------------|
| T-22-01 | Terminal/layout spoofing through unbounded post metadata or body text | medium | Use `Foglet.TUI.TextWidth` for width-sensitive glyph/header/progress decisions and enforce positioned overflow checks in layout smoke. |
| T-22-02 | Markdown semantics drift by flattening styled body rows into strings | medium | Preserve `Foglet.Markdown.render/1` -> `Post.MarkdownBody` and wrap existing row elements with a gutter rather than reparsing or stringifying. |
| T-22-03 | Authorization or read-pointer regression caused by moving domain behavior into rendering | high | Keep Phase 22 in TUI screen/widget rendering only; preserve existing `advance_post/2`, `flush_read_pointers/2`, and context-owned persistence paths. |

## Validation Sign-Off

- [x] All tasks have `<automated>` verify commands.
- [x] Sampling continuity: no 3 consecutive tasks without automated verify.
- [x] Wave 0 covers all MISSING references.
- [x] No watch-mode flags.
- [x] Feedback latency < 120 seconds.
- [x] `nyquist_compliant: true` set in frontmatter.

**Approval:** pending
