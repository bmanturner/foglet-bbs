---
phase: 7
slug: migrate-hand-rolled-ui-components-to-raxol-widgets
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-20
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit (built-in) |
| **Config file** | `test/test_helper.exs` |
| **Quick run command** | `mix test test/foglet_bbs/tui/` |
| **Full suite command** | `mix test` |
| **Estimated runtime** | ~20 seconds (tui subset); ~60 seconds (full) |

---

## Sampling Rate

- **After every task commit:** Run `mix test test/foglet_bbs/tui/`
- **After every plan wave:** Run `mix test`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 20 seconds (tui subset)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 07-01-XX | 01 (Modal adapter) | 1 | MODAL-THEME-01 | — | Modal renders with theme slot fg (not hardcoded `:red`/`:yellow`/`:green` atoms) | unit | `mix test test/foglet_bbs/tui/widgets/modal_test.exs` | ❌ W0 | ⬜ pending |
| 07-01-XX | 01 (Modal adapter) | 1 | MODAL-THEME-01 | — | All `{:show_modal, spec}` dispatch sites pass theme through app.ex | unit | `mix test test/foglet_bbs/tui/app_test.exs` | ✅ | ⬜ pending |
| 07-02-XX | 02 (Viewport integration) | 2 | VIEWPORT-01 | — | PostReader scroll via Viewport — j/k advances scroll_top by 1 line | unit | `mix test test/foglet_bbs/tui/screens/post_reader_test.exs` | ✅ | ⬜ pending |
| 07-02-XX | 02 (Viewport integration) | 2 | VIEWPORT-02 | — | `render_cache` keyed on `{post.id, width}` preserved through Viewport migration | unit | `mix test test/foglet_bbs/tui/screens/post_reader_test.exs` | ✅ | ⬜ pending |
| 07-02-XX | 02 (Viewport integration) | 2 | VIEWPORT-03 | — | N/P key handlers reset Viewport `scroll_top` to 0 when switching posts | unit | `mix test test/foglet_bbs/tui/screens/post_reader_test.exs` | ✅ | ⬜ pending |
| 07-02-XX | 02 (Viewport integration) | 2 | VIEWPORT-04 | — | `PostCard.render_from_tuples/5` returns flat list of line elements (no `scroll_offset:`/`max_lines:` opts) | unit | `mix test test/foglet_bbs/tui/widgets/post/post_card_test.exs` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/foglet_bbs/tui/widgets/modal_test.exs` — stubs asserting theme slot fg values (`theme.error.fg`, `theme.warning.fg`, `theme.primary.fg`) appear in rendered output; NOT hardcoded `:red`/`:yellow`/`:green` atoms
- [ ] Confirm `test/foglet_bbs/tui/screens/post_reader_test.exs` covers `screen_state[:post_reader].viewport` shape after Viewport integration (replaces assertions on `:scroll_offset` integer)

*If none: "Existing infrastructure covers all phase requirements."*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Modal colors visible under SSH session | MODAL-THEME-01 | Terminal rendering and theme propagation need eyeballs across themes | 1. SSH into running BBS. 2. Trigger modal with invalid credentials (error type). 3. Trigger modal with `/help` (info type). 4. Confirm colors match theme definitions (no `:red` atom default). |
| Post scroll feels identical before/after Viewport migration | VIEWPORT-01 | UX regression detection (smoothness, line boundaries, scroll-to-end behavior) | 1. Open long seeded post. 2. Press `j`/`k` line-by-line. 3. Press `N`/`P` to switch posts — scroll must reset to top. 4. Resize terminal — visible lines update without jitter. |

*If none: "All phase behaviors have automated verification."*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (`modal_test.exs`)
- [ ] No watch-mode flags
- [ ] Feedback latency < 20s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
