---
phase: 22
slug: post-reader-facelift
status: verified
threats_open: 0
asvs_level: 1
created: 2026-04-26
---

# Phase 22 - Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| SSH TUI render boundary | Already-loaded post data is converted into terminal UI elements for the active SSH session. | Post metadata and markdown-rendered body text, low sensitivity because this phase only changes presentation of data already authorized and loaded upstream. |
| Raxol viewport boundary | Fixed reader rows and scrollable body rows are composed into Raxol elements and positioned by the layout engine. | Styled text elements, widths, positions, and viewport children. |

---

## Threat Register

| Threat ID | Category | Component | Disposition | Mitigation | Status |
|-----------|----------|-----------|-------------|------------|--------|
| T-22-01A | Tampering / spoofing | `PostCard.reader_parts/5` header and progress rows | mitigate | Header/progress strings are width-sensitive through `Foglet.TUI.TextWidth`; tests cover compact atoms, long-handle truncation, progress truncation, and theme hygiene in `test/foglet_bbs/tui/widgets/post/post_card_test.exs`. | closed |
| T-22-02A | Integrity | `PostCard.reader_parts/5` guttered markdown body rows | mitigate | Body rows delegate to `MarkdownBody.render_tuples_as_lines/4` and wrap existing styled row elements with a gutter instead of reparsing or flattening; tests cover styling preservation, gutter width, and width `1` safety. | closed |
| T-22-03A | Elevation of privilege / side effects | `PostCard` widget helper | mitigate | `PostCard.reader_parts/5` is pure over preloaded post data, tuples, width, theme, and opts; inspection found no `Repo` or context mutation calls in the helper path. | closed |
| T-22-01B | Spoofing | `PostReader.render_post_content/5` viewport ownership | mitigate | `PostReader` composes `[parts.header, parts.progress, Viewport.render(...)]` and passes only `parts.body_lines` into `Viewport.children`; tests assert header/progress are outside viewport children. | closed |
| T-22-02B | Integrity | PostReader render and warm paths | mitigate | Render and warm paths use the same private `reader_parts/6` wrapper, so scroll bounds and displayed body rows share the same source. | closed |
| T-22-03B | Integrity / repudiation | Navigation, scroll, reply/back, and read-pointer behavior | mitigate | Existing behavior tests remain in `test/foglet_bbs/tui/screens/post_reader_test.exs`; Phase 22 implementation leaves navigation, scrolling, reply/back, and read-pointer flushing semantics intact apart from body-line warm shape. | closed |
| T-22-01C | Denial of service / spoofing | 64x22, 80x24, and 132x50 terminal layouts | mitigate | Positioned layout smoke tests assert every text element remains within bounds and no adjacent same-row text overlaps at required sizes. | closed |
| T-22-02C | Integrity | Real layout engine output for compact progress and gutter | mitigate | Layout smoke coverage applies `Engine.apply_layout/2` and asserts header, progress, gutter, selected body text, and command bar text survive positioning. | closed |
| T-22-03C | Regression risk | Finish-line verification | mitigate | Focused Phase 22 suite passed locally on 2026-04-26: `rtk mix test test/foglet_bbs/tui/widgets/post/post_card_test.exs test/foglet_bbs/tui/screens/post_reader_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` returned 136 tests, 0 failures. Full `rtk mix precommit` is documented in `22-03-SUMMARY.md` as blocked by an unrelated existing Credo alias-order issue in `post_composer.ex`. | closed |

---

## Accepted Risks Log

No accepted risks.

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-04-26 | 9 | 9 | 0 | Codex |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-04-26
