---
phase: 23
slug: composer-facelift
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-04-25
---

# Phase 23 - Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit via Mix |
| **Config file** | `test/test_helper.exs` and `test/support` |
| **Quick run command** | `rtk mix test test/foglet_bbs/tui/widgets/composer/editor_frame_test.exs test/foglet_bbs/tui/screens/post_composer_test.exs test/foglet_bbs/tui/screens/new_thread_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` |
| **Full suite command** | `rtk mix precommit` |
| **Estimated runtime** | ~15-45 seconds for quick run; full suite varies with Dialyzer/cache state |

---

## Sampling Rate

- **After every task commit:** Run the focused test file(s) touched by that task.
- **After every plan wave:** Run `rtk mix test test/foglet_bbs/tui/widgets/composer/editor_frame_test.exs test/foglet_bbs/tui/screens/post_composer_test.exs test/foglet_bbs/tui/screens/new_thread_test.exs test/foglet_bbs/tui/layout_smoke_test.exs`.
- **Before `$gsd-verify-work`:** `rtk mix precommit` must pass.
- **Max feedback latency:** 45 seconds for the quick-run sampling path.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 23-01-01 | 01 | 1 | COMPOSER-01, COMPOSER-02, COMPOSER-03 | T-23-01 | Editor chrome remains presentation-only; submit validation remains in existing contexts. | widget | `rtk mix test test/foglet_bbs/tui/widgets/composer/editor_frame_test.exs` | No, Wave 0 | pending |
| 23-02-01 | 02 | 2 | COMPOSER-02, COMPOSER-04 | T-23-02 | Preview and quote rendering must not create a new mutation path. | screen render | `rtk mix test test/foglet_bbs/tui/screens/post_composer_test.exs` | Yes, extend | pending |
| 23-03-01 | 03 | 2 | COMPOSER-01, COMPOSER-02, COMPOSER-04, COMPOSER-05 | T-23-03 | Title/body validation and submission stay on existing new-thread path. | screen render | `rtk mix test test/foglet_bbs/tui/screens/new_thread_test.exs` | Yes, extend | pending |
| 23-04-01 | 04 | 3 | COMPOSER-03, COMPOSER-04, COMPOSER-05 | T-23-04 | Narrow layouts keep required controls visible and preserve width-aware input behavior. | layout smoke | `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` | Yes, extend | pending |

*Status: pending, green, red, flaky.*

---

## Wave 0 Requirements

- [ ] `test/foglet_bbs/tui/widgets/composer/editor_frame_test.exs` - stubs and assertions for COMPOSER-01, COMPOSER-02, and COMPOSER-03.
- [ ] Extend `test/foglet_bbs/tui/screens/post_composer_test.exs` - shell presence, visible modes, quote context, counter, and preview-in-shell assertions.
- [ ] Extend `test/foglet_bbs/tui/screens/new_thread_test.exs` - title/body shell integration and behavior preservation assertions.
- [ ] Extend `test/foglet_bbs/tui/layout_smoke_test.exs` - canonical composer dimensions `64x22`, `80x24`, and `132x50`.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| None | N/A | All phase behaviors have automated verification anchors in ExUnit. | N/A |

---

## Threat Model

| Threat Ref | Severity | Threat | Mitigation Required In Plans |
|------------|----------|--------|------------------------------|
| T-23-01 | medium | UI-only character counters or validation states are mistaken for authoritative enforcement. | Preserve existing changeset/context validation; counters are display-only and tests prove over-limit state does not bypass submit validation. |
| T-23-02 | medium | Preview or editor mode introduces a new submit path that bypasses authorization/domain invariants. | Keep submit behavior in current screen/context paths; no new domain mutation API in widgets. |
| T-23-03 | low | Terminal control/input confusion breaks existing Ctrl+S/Ctrl+C and multiline edit behavior. | Preserve `Compose.translate_key/1`, screen-level command handling, and existing compose widget tests. |
| T-23-04 | low | Narrow layout hides required validation or action controls. | Add layout smoke coverage for `64x22` so nonessential context collapses before title/body/mode/counter controls. |

---

## Validation Sign-Off

- [x] All tasks have automated verify commands or Wave 0 dependencies.
- [x] Sampling continuity: no 3 consecutive tasks without automated verify.
- [x] Wave 0 covers all missing references.
- [x] No watch-mode flags.
- [x] Feedback latency target is less than 45 seconds for quick sampling.
- [x] `nyquist_compliant: true` set in frontmatter.

**Approval:** approved 2026-04-25
